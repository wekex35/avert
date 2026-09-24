import AppKit
import Carbon
import Foundation
import OSLog
import ServiceManagement

@MainActor
final class LoginItemService {
    private let log = Logger(subsystem: "com.avert.app", category: "LoginItem")

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("Login item failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// ⌘⇧B toggles panic full-screen blur.
@MainActor
final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let log = Logger(subsystem: "com.avert.app", category: "Hotkey")

    var onTogglePanic: (() -> Void)?

    func start() {
        stop()

        var hotKeyID = EventHotKeyID(signature: OSType(0x504B4752), id: 1) // 'PKGR'
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            log.error("RegisterEventHotKey failed: \(status)")
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                var hk = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hk
                )
                if hk.id == 1 {
                    Task { @MainActor in
                        service.onTogglePanic?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        log.info("Hotkey ⌘⇧B registered")
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}

/// Detects settled pose that no longer matches calibration center.
@MainActor
final class DriftMonitor {
    private let settings: SettingsStore
    private var driftStarted: Date?
    private var lastPrompt: Date?
    private let settleSeconds: TimeInterval = 10
    private let cooldown: TimeInterval = 15 * 60
    /// ~12° yaw or pitch while “settled” suggests calibration is stale.
    private let driftRadians = 12.0 * .pi / 180.0
    private let stillRate = 0.05

    var onNeedsRecalibration: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func reset() {
        driftStarted = nil
    }

    func ingest(pose: RelativePose, facingScreenBand: Bool) {
        guard settings.autoRecalibratePrompt else {
            driftStarted = nil
            return
        }

        let drifted = abs(pose.yaw) > driftRadians || abs(pose.pitch) > driftRadians
        let settled = pose.rotationRateMagnitude < stillRate
        // Not in the tight facing band, but head isn't turning — likely new seating pose.
        let candidate = drifted && settled && !facingScreenBand

        let now = Date()
        if candidate {
            if driftStarted == nil {
                driftStarted = now
            } else if let start = driftStarted,
                      now.timeIntervalSince(start) >= settleSeconds,
                      canPrompt(now: now) {
                lastPrompt = now
                driftStarted = nil
                onNeedsRecalibration?()
            }
        } else {
            driftStarted = nil
        }
    }

    private func canPrompt(now: Date) -> Bool {
        guard let lastPrompt else { return true }
        return now.timeIntervalSince(lastPrompt) >= cooldown
    }
}

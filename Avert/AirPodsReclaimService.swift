import CoreAudio
import Foundation
import IOBluetooth
import OSLog

/// Tries to pull AirPods back to this Mac after an iPhone call / Automatic Switching handoff.
@MainActor
final class AirPodsReclaimService {
    private let log = Logger(subsystem: "com.avert.app", category: "AirPodsReclaim")
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?

    var onAudioHardwareChanged: (() -> Void)?

    func startWatchingHardware() {
        guard devicesListener == nil else { return }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.onAudioHardwareChanged?()
            }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            devicesBlock
        ) == noErr {
            devicesListener = devicesBlock
        }

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.onAudioHardwareChanged?()
            }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            DispatchQueue.main,
            defaultBlock
        ) == noErr {
            defaultOutputListener = defaultBlock
        }
    }

    func stopWatchingHardware() {
        if let block = devicesListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            devicesListener = nil
        }
        if let block = defaultOutputListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            defaultOutputListener = nil
        }
    }

    func airPodsPresent() -> Bool {
        !findCandidateOutputDevices().isEmpty
    }

    /// Best-effort: Bluetooth reconnect + set as default audio when Core Audio lists them.
    @discardableResult
    func reclaimAsDefaultAudio(aggressive: Bool = false) -> Bool {
        let bluetoothOK = reconnectPairedAirPods(aggressive: aggressive)
        let devices = findCandidateOutputDevices()
        guard let device = devices.first else {
            logKnownAudioDevices()
            return bluetoothOK
        }

        var changed = false
        if defaultDeviceID(for: kAudioHardwarePropertyDefaultOutputDevice) != device {
            if setDefaultDevice(device, selector: kAudioHardwarePropertyDefaultOutputDevice) {
                log.info("Set default output → \(self.deviceName(device), privacy: .public)")
                changed = true
            }
        }
        if channelCount(device, scope: kAudioDevicePropertyScopeInput) > 0,
           defaultDeviceID(for: kAudioHardwarePropertyDefaultInputDevice) != device
        {
            if setDefaultDevice(device, selector: kAudioHardwarePropertyDefaultInputDevice) {
                log.info("Set default input → \(self.deviceName(device), privacy: .public)")
                changed = true
            }
        }
        return bluetoothOK || changed || true
    }

    /// Open (or bounce) the already-connected AirPods — ignore stale duplicate pairings.
    @discardableResult
    func reconnectPairedAirPods(aggressive: Bool) -> Bool {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            log.notice("IOBluetooth pairedDevices unavailable")
            return false
        }

        let targets = paired.compactMap { device -> IOBluetoothDevice? in
            let name = (device.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let lower = name.lowercased()
            guard lower.contains("airpods") || lower.contains("beats") else { return nil }
            // Require a usable address — "No name or address" entries are useless.
            guard device.addressString != nil else { return nil }
            return device
        }

        guard !targets.isEmpty else {
            log.notice("No usable paired AirPods/Beats in IOBluetooth")
            return false
        }

        let connected = targets.filter { $0.isConnected() }
        // Prefer the live Mac link. Never open a greyed-out duplicate while one is already connected.
        let focus = connected.isEmpty ? targets : connected

        var attempted = false
        for device in focus {
            let name = device.name ?? "?"
            if device.isConnected() {
                if aggressive {
                    log.info("Bouncing connected BT link for \(name, privacy: .public)")
                    device.closeConnection()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        _ = device.openConnection()
                    }
                    attempted = true
                } else {
                    log.info("BT already connected: \(name, privacy: .public) — leaving link alone")
                    attempted = true
                }
            } else {
                log.info("Opening BT connection to \(name, privacy: .public)")
                _ = device.openConnection()
                attempted = true
            }
        }
        return attempted
    }

    private func findCandidateOutputDevices() -> [AudioDeviceID] {
        allDeviceIDs().filter { id in
            guard channelCount(id, scope: kAudioDevicePropertyScopeOutput) > 0 else { return false }
            let name = deviceName(id).lowercased()
            if name.contains("airpods") || name.contains("beats") { return true }
            // Some macOS builds expose buds with sparse names — accept Bluetooth headphone outputs.
            let transport = transportType(id)
            if transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE
            {
                // Exclude obvious non-buds (keyboards, mice sometimes appear as BT).
                if name.contains("keyboard") || name.contains("mouse") || name.contains("trackpad") {
                    return false
                }
                return true
            }
            return false
        }
    }

    private func logKnownAudioDevices() {
        let names = allDeviceIDs().map { "\(deviceName($0)) [\(transportLabel(transportType($0)))]" }
        log.notice("No AirPods audio endpoint yet. Core Audio devices: \(names.joined(separator: ", "), privacy: .public)")
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else { return [] }
        return devices
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return "" }
        return name as String
    }

    private func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else {
            return 0
        }
        return transport
    }

    private func transportLabel(_ type: UInt32) -> String {
        switch type {
        case kAudioDeviceTransportTypeBluetooth: return "bt"
        case kAudioDeviceTransportTypeBluetoothLE: return "ble"
        case kAudioDeviceTransportTypeBuiltIn: return "built-in"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypeUSB: return "usb"
        default: return String(format: "0x%08x", type)
        }
    }

    private func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        var channels = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }

    private func defaultDeviceID(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr else { return nil }
        return device
    }

    private func setDefaultDevice(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = device
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &value
        ) == noErr
    }
}

import CoreMotion
import Foundation
import OSLog

enum HeadTrackerStatus: Equatable {
    case idle
    case unavailable
    case unauthorized
    case waitingForHeadphones
    case waitingForMotion
    /// Motion paused because buds hopped to a phone call / other device.
    case busyElsewhere
    case readyToCalibrate
    case tracking
    case error(String)
}

@MainActor
final class HeadTracker: NSObject {
    private var manager = CMHeadphoneMotionManager()
    private let motionQueue = OperationQueue()
    private let log = Logger(subsystem: "com.avert.app", category: "HeadTracker")

    private var wantsRunning = false
    private var disconnectWorkItem: DispatchWorkItem?
    private var pendingEarChange: DispatchWorkItem?
    private var restartWorkItem: DispatchWorkItem?
    private var disconnectGraceSeconds: TimeInterval = 1.2
    private var lastCalibrateAt = Date.distantPast
    private var lastSampleAt: Date?
    private var seenEars: Set<ActiveEar> = []
    private var watchdogTimer: Timer?
    private var availabilityTimer: Timer?
    private var managerGeneration = 0
    private var lastForceResumeAt = Date.distantPast
    private var lastPipelineStartAt = Date.distantPast

    /// Keep calibration across brief phone-call handoffs.
    private var preservedReference: CMAttitude?

    private(set) var status: HeadTrackerStatus = .idle
    private(set) var referenceAttitude: CMAttitude?
    private(set) var latestAttitude: CMAttitude?
    private(set) var latestRelativeYaw: Double?
    private(set) var latestRelativePitch: Double?
    private(set) var latestRelativeRoll: Double?
    private(set) var latestActiveEar: ActiveEar = .unknown
    private(set) var sampleCount: Int = 0
    /// True after we’ve only ever seen one concrete ear this session (typical single-bud use).
    private(set) var appearsSingleEarSession = true

    var onStatusChange: ((HeadTrackerStatus) -> Void)?
    var onRelativePose: ((RelativePose) -> Void)?
    var onHeadphonesDisconnected: (() -> Void)?
    /// Fires on every sample before calibration so UI can leave “waiting”.
    var onPreCalibrationSample: ((ActiveEar, Int) -> Void)?
    /// Fires when the streaming bud switches left ↔ right (pose frame can jump).
    var onActiveEarChanged: ((ActiveEar) -> Void)?

    /// Seconds since last successful calibrate (for ignoring stacked ear-switch recenters).
    var secondsSinceCalibrate: TimeInterval {
        Date().timeIntervalSince(lastCalibrateAt)
    }

    override init() {
        super.init()
        motionQueue.name = "com.avert.motion"
        motionQueue.maxConcurrentOperationCount = 1
        manager.delegate = self
    }

    var isDeviceMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    /// True while updates are requested but the first attitude hasn't arrived yet.
    var isAwaitingFirstSample: Bool {
        wantsRunning && latestAttitude == nil && Date().timeIntervalSince(lastPipelineStartAt) < 10
    }

    var canCalibrate: Bool {
        latestAttitude != nil
    }

    func setDisconnectGraceSeconds(_ seconds: TimeInterval) {
        disconnectGraceSeconds = max(0.8, min(4.0, seconds))
    }

    func start() {
        wantsRunning = true

        let auth = CMHeadphoneMotionManager.authorizationStatus()
        log.info("authorizationStatus=\(String(describing: auth), privacy: .public) available=\(self.manager.isDeviceMotionAvailable)")
        switch auth {
        case .denied, .restricted:
            updateStatus(.unauthorized)
            return
        case .notDetermined:
            // Starting updates should present the system prompt (macOS may keep reporting notDetermined).
            log.notice("Motion auth notDetermined — starting updates to trigger prompt if needed")
        case .authorized:
            break
        @unknown default:
            break
        }

        if !manager.isDeviceMotionAvailable {
            log.notice("isDeviceMotionAvailable == false (will keep retrying)")
            updateStatus(.unavailable)
            startAvailabilityPolling()
            return
        }

        stopAvailabilityPolling()
        updateStatus(.waitingForHeadphones)

        if !manager.isConnectionStatusActive {
            manager.startConnectionStatusUpdates()
        }

        restartMotionPipeline(reason: "start")
        startWatchdog()
    }

    func stop() {
        wantsRunning = false
        cancelPendingDisconnect()
        pendingEarChange?.cancel()
        pendingEarChange = nil
        cancelRestart()
        stopWatchdog()
        stopAvailabilityPolling()

        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        if manager.isConnectionStatusActive {
            manager.stopConnectionStatusUpdates()
        }

        referenceAttitude = nil
        preservedReference = nil
        latestAttitude = nil
        latestRelativeYaw = nil
        latestRelativePitch = nil
        latestRelativeRoll = nil
        latestActiveEar = .unknown
        sampleCount = 0
        lastSampleAt = nil
        seenEars = []
        appearsSingleEarSession = true
        updateStatus(.idle)
    }

    /// Soft resume: restart updates without tearing down the manager (preferred).
    func softResume(reason: String = "soft") {
        guard wantsRunning else { return }
        restoreReferenceIfNeeded()
        // Don't interrupt a pipeline that just started and is still waiting for the first sample.
        if latestAttitude == nil, Date().timeIntervalSince(lastPipelineStartAt) < 3.5 {
            log.info("Soft resume skipped — still waiting for first sample (\(reason, privacy: .public))")
            return
        }
        restartMotionPipeline(reason: reason)
        startWatchdog()
        if !manager.isDeviceMotionAvailable {
            startAvailabilityPolling()
        }
    }

    /// Hard resume: recreate manager at most once every few seconds.
    func forceResume(reason: String = "reclaim") {
        guard wantsRunning else { return }
        if Date().timeIntervalSince(lastForceResumeAt) < 5.0 {
            softResume(reason: "\(reason)-debounced")
            return
        }
        lastForceResumeAt = Date()
        restoreReferenceIfNeeded()
        recreateManager(reason: reason)
        restartMotionPipeline(reason: reason)
        startWatchdog()
        if !manager.isDeviceMotionAvailable {
            startAvailabilityPolling()
        }
    }

    private func recreateManager(reason: String) {
        log.info("Recreating CMHeadphoneMotionManager (\(reason, privacy: .public))")
        cancelRestart()
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        if manager.isConnectionStatusActive {
            manager.stopConnectionStatusUpdates()
        }
        manager.delegate = nil
        managerGeneration += 1
        manager = CMHeadphoneMotionManager()
        manager.delegate = self
        if wantsRunning {
            manager.startConnectionStatusUpdates()
        }
    }

    @discardableResult
    func calibrate(reason: String = "manual") -> Bool {
        if Date().timeIntervalSince(lastCalibrateAt) < 1.0, referenceAttitude != nil {
            return true
        }

        guard let attitude = latestAttitude ?? manager.deviceMotion?.attitude else {
            log.notice("Calibrate failed: no attitude yet")
            if status != .unauthorized && status != .unavailable {
                updateStatus(sampleCount == 0 ? .waitingForMotion : .waitingForHeadphones)
            }
            return false
        }

        let copy = attitude.copy() as? CMAttitude ?? attitude
        referenceAttitude = copy
        preservedReference = copy
        latestRelativeYaw = 0
        latestRelativePitch = 0
        latestRelativeRoll = 0
        lastCalibrateAt = Date()
        updateStatus(.tracking)
        return true
    }

    /// Soft pause used when buds leave for a phone call — keeps calibration for resume.
    private func pauseForExternalHandoff() {
        log.info("Motion handoff pause (call / other device)")
        if let reference = referenceAttitude {
            preservedReference = reference
        }
        latestAttitude = nil
        latestRelativeYaw = nil
        latestRelativePitch = nil
        latestRelativeRoll = nil
        latestActiveEar = .unknown
        // Keep sampleCount so UI knows we had a session.
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        updateStatus(.busyElsewhere)
        onHeadphonesDisconnected?()
        startAvailabilityPolling()
    }

    private func restoreReferenceIfNeeded() {
        if referenceAttitude == nil, let preserved = preservedReference {
            referenceAttitude = preserved
            log.info("Restored calibration after handoff")
        }
    }

    private func restartMotionPipeline(reason: String) {
        guard wantsRunning else { return }
        cancelRestart()

        if !manager.isDeviceMotionAvailable {
            log.notice("Restart skipped — motion unavailable (\(reason, privacy: .public))")
            updateStatus(status == .busyElsewhere ? .busyElsewhere : .unavailable)
            startAvailabilityPolling()
            return
        }

        stopAvailabilityPolling()

        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }

        // Brief gap so Core Motion releases the previous session after HFP handoff.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsRunning else { return }
            self.manager.startDeviceMotionUpdates(to: self.motionQueue) { [weak self] motion, error in
                Task { @MainActor in
                    self?.handle(motion: motion, error: error)
                }
            }
            self.lastPipelineStartAt = Date()
            self.log.info("Requested device motion updates (\(reason, privacy: .public))")
            if self.status == .waitingForHeadphones
                || self.status == .idle
                || self.status == .busyElsewhere
                || self.status == .unavailable
            {
                self.updateStatus(.waitingForMotion)
            }
        }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func cancelRestart() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
    }

    private func handle(motion: CMDeviceMotion?, error: Error?) {
        if let error {
            log.error("Motion error: \(error.localizedDescription, privacy: .public)")
            // Transient errors during phone handoff — soft-pause and retry.
            pauseForExternalHandoff()
            softResume(reason: "after-error")
            return
        }

        guard let motion else {
            // Handler can fire with nil during handoff; don't treat as success.
            return
        }

        cancelPendingDisconnect()
        stopAvailabilityPolling()
        lastSampleAt = Date()
        sampleCount += 1
        latestAttitude = motion.attitude.copy() as? CMAttitude ?? motion.attitude
        restoreReferenceIfNeeded()

        let ear = ActiveEar(sensorLocation: motion.sensorLocation)
        let previousEar = latestActiveEar
        latestActiveEar = ear
        if ear == .left || ear == .right {
            seenEars.insert(ear)
            appearsSingleEarSession = seenEars.count <= 1
        }

        if sampleCount == 1 {
            let auth = CMHeadphoneMotionManager.authorizationStatus()
            log.info("First motion sample received (auth=\(String(describing: auth), privacy: .public), ear=\(ear.rawValue, privacy: .public))")
        }

        if previousEar != .unknown, ear != .unknown, previousEar != ear {
            scheduleEarChange(ear)
        }

        if referenceAttitude == nil {
            updateStatus(.readyToCalibrate)
            onPreCalibrationSample?(ear, sampleCount)
            return
        }

        guard let reference = referenceAttitude else { return }
        let pose = PoseMath.relative(
            current: motion.attitude,
            reference: reference,
            rotationRate: motion.rotationRate,
            sensorLocation: motion.sensorLocation
        )
        latestRelativeYaw = pose.yaw
        latestRelativePitch = pose.pitch
        latestRelativeRoll = pose.roll

        updateStatus(.tracking)
        onRelativePose?(pose)
    }

    private func scheduleEarChange(_ ear: ActiveEar) {
        pendingEarChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.latestActiveEar == ear else { return }
            self.log.info("Active ear switch confirmed → \(ear.rawValue, privacy: .public)")
            self.onActiveEarChanged?(ear)
        }
        pendingEarChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func scheduleDisconnectHandling() {
        cancelPendingDisconnect()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsRunning else { return }
            self.pauseForExternalHandoff()
        }
        disconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + disconnectGraceSeconds, execute: work)
    }

    private func cancelPendingDisconnect() {
        disconnectWorkItem?.cancel()
        disconnectWorkItem = nil
    }

    private func startWatchdog() {
        stopWatchdog()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.watchdogTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        guard wantsRunning else { return }

        // Motion API vanished (common during iPhone call handoff).
        if !manager.isDeviceMotionAvailable {
            if status != .busyElsewhere && status != .unavailable && status != .unauthorized {
                pauseForExternalHandoff()
            }
            startAvailabilityPolling()
            return
        }

        // Waiting for first sample after a restart — soft-retry once if it takes too long.
        if latestAttitude == nil {
            let waited = Date().timeIntervalSince(lastPipelineStartAt)
            if waited > 6.0,
               status == .waitingForMotion || status == .busyElsewhere || status == .readyToCalibrate
            {
                // Allow softResume to run by aging out the "just started" guard.
                lastPipelineStartAt = .distantPast
                softResume(reason: "watchdog-no-sample")
            }
            return
        }

        guard let last = lastSampleAt else { return }
        let stalled = Date().timeIntervalSince(last) > 3.5
        guard stalled else { return }

        if status == .tracking || status == .readyToCalibrate || status == .waitingForMotion {
            log.notice("Motion stalled \(String(format: "%.1f", Date().timeIntervalSince(last)), privacy: .public)s — soft restart")
            if status == .tracking {
                updateStatus(.busyElsewhere)
                onHeadphonesDisconnected?()
            }
            softResume(reason: "watchdog-stall")
        }
    }

    private func startAvailabilityPolling() {
        guard availabilityTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.availabilityTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        availabilityTimer = timer
    }

    private func stopAvailabilityPolling() {
        availabilityTimer?.invalidate()
        availabilityTimer = nil
    }

    private func availabilityTick() {
        guard wantsRunning else { return }
        guard manager.isDeviceMotionAvailable else { return }

        // Soft only — recreating here was interrupting the stream mid-handshake.
        log.info("Motion available — soft resume")
        stopAvailabilityPolling()
        softResume(reason: "availability")
    }

    private func updateStatus(_ newStatus: HeadTrackerStatus) {
        guard status != newStatus else { return }
        status = newStatus
        onStatusChange?(newStatus)
    }
}

extension HeadTracker: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.log.info("Headphones connected")
            guard self.wantsRunning else { return }
            self.cancelPendingDisconnect()
            self.restoreReferenceIfNeeded()
            if self.latestAttitude == nil {
                self.updateStatus(.waitingForMotion)
            }
            self.restartMotionPipeline(reason: "connect")
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.log.info("Headphones disconnect signal (debouncing)")
            guard self.wantsRunning else { return }
            self.scheduleDisconnectHandling()
        }
    }
}

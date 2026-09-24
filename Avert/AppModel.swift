import AppKit
import Foundation
import Observation

enum AppPhase: Equatable {
    case disabled
    case unauthorized
    case waitingForMotion
    case awaitingCalibration
    case tracking
    case motionUnavailable
    case schedulePaused
}

@MainActor
@Observable
final class AppModel {
    let settings = SettingsStore()
    let headTracker = HeadTracker()
    let overlays = OverlayManager()
    let displayWatcher = DisplayWatcher()
    let notifications = NotificationService()
    let loginItem = LoginItemService()
    let hotkey = HotkeyService()
    let panicImages = PanicImageStore()
    let reclaim = AirPodsReclaimService()

    private let privacy: PrivacyController
    private let neckCare: NeckCareMonitor
    private let drift: DriftMonitor
    private var didStart = false
    private var reclaimRetryWork: DispatchWorkItem?
    private var lastReclaimAttempt = Date.distantPast
    private var sawLeftBlur = false
    private var sawRightBlur = false
    private var lastStatusPublish = Date.distantPast
    private var samplesAtCalibration = 0
    private var autoCalibrateWork: DispatchWorkItem?

    private(set) var isEnabled = false
    private(set) var phase: AppPhase = .disabled
    private(set) var statusLine: String = "Off"
    private(set) var isPanicBlurActive = false
    private(set) var lastYawDegrees: Double?
    private(set) var lastPitchDegrees: Double?
    private(set) var activeEar: ActiveEar = .unknown
    private(set) var motionSampleCount: Int = 0
    private(set) var lastCalibrateSummary: String = "—"
    private(set) var neckCareStatus: String = ""
    private(set) var needsRecalibration = false
    /// Thumbnail for Privacy → panic cover.
    private(set) var panicImagePreview: NSImage?
    /// Guided neck exercise sheet (3 compound moves × 4 reps).
    var isExerciseSheetPresented = false
    private(set) var exerciseStepIndex = 0
    private(set) var exerciseReps = 0
    private(set) var exerciseCoachHint = "Start from center"
    private(set) var exerciseAxisDegrees = 0.0
    private(set) var exerciseHalf: ExerciseHalf = .first
    private(set) var exercisePhaseTitle = "Center"
    private(set) var exercisePhaseCue = "Face straight ahead"
    private(set) var exercisePhaseImageName = "look-center"
    /// Whole seconds for the big timer (avoids 60 Hz float churn).
    private(set) var exerciseHoldSecondsDisplay = 0
    private let exerciseTracker = ExerciseRepTracker()
    private let exerciseVoice = ExerciseVoiceCoach()

    var exerciseSetComplete: Bool {
        guard isExerciseSheetPresented else { return false }
        let last = NeckExercise.catalog.count - 1
        return exerciseStepIndex >= last && exerciseReps >= NeckExercise.catalog[last].targetReps
    }

    /// Calibration dialog visibility.
    var isCalibrationSheetPresented = false
    var calibrationStep: CalibrationStep = .faceScreen

    /// Live line in Status — no runaway sample counter while tracking.
    var trackingDebugLine: String {
        let yaw = lastYawDegrees.map { String(format: "%.0f°", $0) } ?? "—"
        let pitch = lastPitchDegrees.map { String(format: "%.0f°", $0) } ?? "—"
        let ear = activeEar == .unknown ? "—" : activeEar.shortTitle
        if phase == .tracking || phase == .schedulePaused {
            return "ear \(ear)  ·  yaw \(yaw)  ·  pitch \(pitch)"
        }
        return "ear \(ear)  ·  getting ready…"
    }

    var motionStatusLabel: String {
        switch phase {
        case .tracking, .schedulePaused:
            return "Live"
        case .awaitingCalibration, .waitingForMotion:
            return canCalibrate ? "Ready" : "Waiting"
        default:
            return "—"
        }
    }

    var canCalibrate: Bool {
        isEnabled && headTracker.canCalibrate
    }

    var phaseLabel: String {
        switch phase {
        case .disabled: return "Off"
        case .unauthorized: return "Motion denied"
        case .waitingForMotion: return "Waiting for AirPods"
        case .awaitingCalibration: return "Needs calibration"
        case .tracking: return "Tracking"
        case .motionUnavailable: return "On call / other device"
        case .schedulePaused: return "Paused by schedule"
        }
    }

    var detailStatusTitle: String {
        if isPanicBlurActive { return "Panic blur is on" }
        if needsRecalibration { return "Recalibration suggested" }
        switch phase {
        case .disabled:
            return "Avert is off"
        case .unauthorized:
            return "Motion access needed"
        case .waitingForMotion:
            return "AirPods motion unavailable"
        case .motionUnavailable:
            return "AirPods busy (call or other device)"
        case .awaitingCalibration:
            return "Motion is flowing — calibrate now"
        case .schedulePaused:
            return "Paused by schedule"
        case .tracking:
            return "Protection is on"
        }
    }

    var detailStatusSubtitle: String {
        if isPanicBlurActive {
            return "Press ⌘⇧B or Clear panic blur to dismiss. Looking down or forward will not clear it."
        }
        switch phase {
        case .disabled:
            return "Enable when you want look-away privacy from AirPods head tracking."
        case .unauthorized:
            return "Allow Motion & Fitness for Avert in System Settings."
        case .waitingForMotion:
            return "Put AirPods in and wait until motion samples arrive. Moving your head helps the stream start."
        case .motionUnavailable:
            return "Bluetooth can look connected while audio stays on iPhone. Tap Bring AirPods to Mac, or click AirPods in the Bluetooth menu to Connect."
        case .awaitingCalibration:
            return "You don’t need more motion. Face the screen — Avert recenters automatically if you’ve calibrated before, or tap Calibrate."
        case .schedulePaused:
            return "Enabled, but the current schedule says protection should stay off right now."
        case .tracking:
            return "Look left or right to veil that side. Look down for a soft dim if enabled."
        }
    }

    init() {
        privacy = PrivacyController(settings: settings)
        neckCare = NeckCareMonitor(settings: settings)
        drift = DriftMonitor(settings: settings)
        isEnabled = settings.enabled
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        wireCallbacks()
        displayWatcher.onDisplaysChanged = { [weak self] in
            self?.overlays.recreateForDisplayChange()
        }
        displayWatcher.start()
        overlays.setDisplayCoverage(settings.displayCoverage)
        overlays.setFadeDuration(settings.fadeDuration)
        refreshPanicCoverMode()
        applySingleEarPreferences()

        if settings.launchAtLogin != loginItem.isEnabled {
            _ = loginItem.setEnabled(settings.launchAtLogin)
        }

        if settings.hotkeyEnabled {
            hotkey.start()
        }

        Task {
            await notifications.requestAuthorizationIfNeeded()
            notifications.scheduleNeckExerciseReminders(enabled: settings.neckExercisesEnabled)
        }

        if isEnabled {
            enableTracking()
        } else {
            phase = .disabled
            statusLine = "Off"
        }
    }

    func shutdown() {
        isCalibrationSheetPresented = false
        isExerciseSheetPresented = false
        cancelAutoCalibrate()
        exerciseVoice.stop()
        stopReclaimRetries()
        reclaim.stopWatchingHardware()
        headTracker.stop()
        neckCare.reset()
        drift.reset()
        overlays.clearPanic()
        overlays.tearDown()
        displayWatcher.stop()
        hotkey.stop()
    }

    func openCalibrationFlow() {
        guard isEnabled else { return }
        cancelAutoCalibrate()
        needsRecalibration = false
        sawLeftBlur = false
        sawRightBlur = false
        calibrationStep = headTracker.canCalibrate ? .faceScreen : .waitingForMotion
        isCalibrationSheetPresented = true
        // Ensure main window is up so the sheet has a presenter.
        NotificationCenter.default.post(name: .avertOpenMainWindow, object: nil)
    }

    func cancelCalibrationFlow() {
        isCalibrationSheetPresented = false
        calibrationStep = .faceScreen
    }

    func finishCalibrationFlow() {
        isCalibrationSheetPresented = false
        calibrationStep = .done
        // Drop any practice look-up cover so the desktop is usable again.
        if !isPanicBlurActive {
            overlays.clear()
        }
        refreshStatus(force: true)
    }

    func skipCalibrationPractice() {
        calibrationStep = .done
    }

    /// Skip only the current practice step.
    func advanceCalibrationPractice() {
        switch calibrationStep {
        case .practiceLeft: calibrationStep = .practiceRight
        case .practiceRight: calibrationStep = .practiceDown
        case .practiceDown: calibrationStep = .practiceUp
        case .practiceUp: calibrationStep = .done
        default: calibrationStep = .done
        }
    }

    /// Called from the calibration dialog’s primary button.
    func confirmCalibrationInFlow() {
        guard calibrate() else { return }
        calibrationStep = .practiceLeft
    }

    @discardableResult
    func calibrate() -> Bool {
        guard isEnabled else { return false }
        let ok = headTracker.calibrate(reason: "manual")
        if ok {
            settings.calibratedOnce = true
            privacy.reset()
            neckCare.reset()
            drift.reset()
            needsRecalibration = false
            overlays.clearPanic()
            isPanicBlurActive = false
            overlays.clear()
            phase = settings.isProtectionAllowed() ? .tracking : .schedulePaused
            lastYawDegrees = 0
            lastPitchDegrees = 0
            samplesAtCalibration = headTracker.sampleCount
            motionSampleCount = headTracker.sampleCount
            lastCalibrateSummary = "OK"
            sawLeftBlur = false
            sawRightBlur = false
        }
        refreshStatus(force: true)
        return ok
    }

    func dismissTutorial() {
        // Kept for call-site compatibility; floating tutorial removed.
        cancelCalibrationFlow()
    }

    private func enableTracking() {
        overlays.setFadeDuration(settings.fadeDuration)
        overlays.setDisplayCoverage(settings.displayCoverage)
        overlays.recreateForDisplayChange()
        neckCare.reset()
        drift.reset()
        reclaim.startWatchingHardware()
        headTracker.start()

        if !headTracker.isDeviceMotionAvailable {
            phase = .motionUnavailable
            scheduleReclaimRetries()
            refreshStatus(force: true)
            return
        }

        applyTrackerStatus(headTracker.status)
        // First launch only — afterward we quietly recenter when motion returns.
        if !settings.calibratedOnce {
            openCalibrationFlow()
        }
    }

    private func disableTracking() {
        cancelCalibrationFlow()
        cancelAutoCalibrate()
        stopReclaimRetries()
        reclaim.stopWatchingHardware()
        headTracker.stop()
        privacy.reset()
        neckCare.reset()
        drift.reset()
        overlays.clearPanic()
        isPanicBlurActive = false
        overlays.clear()
        lastYawDegrees = nil
        lastPitchDegrees = nil
        neckCareStatus = ""
        needsRecalibration = false
        phase = .disabled
        refreshStatus(force: true)
    }

    /// Select AirPods as this Mac’s audio device and rebuild the motion stream.
    func bringAirPodsToMac() {
        guard isEnabled else { return }
        // Aggressive BT bounce — Bluetooth menu can show connected while audio/motion stay on iPhone.
        _ = reclaim.reclaimAsDefaultAudio(aggressive: true)
        headTracker.softResume(reason: "user-reclaim")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            _ = self?.reclaim.reclaimAsDefaultAudio(aggressive: false)
            self?.headTracker.softResume(reason: "user-reclaim-followup")
        }
        // Only hard-recreate if still no samples after the soft attempts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            guard let self, self.isEnabled else { return }
            guard self.phase == .motionUnavailable || self.phase == .waitingForMotion else { return }
            self.headTracker.forceResume(reason: "user-reclaim-hard")
        }
        refreshStatus(force: true)
    }

    private func scheduleReclaimRetries() {
        stopReclaimRetries()
        let work = DispatchWorkItem { [weak self] in
            self?.reclaimTick()
            self?.scheduleReclaimRetries()
        }
        reclaimRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func stopReclaimRetries() {
        reclaimRetryWork?.cancel()
        reclaimRetryWork = nil
    }

    private func reclaimTick() {
        guard isEnabled else { return }
        guard phase == .motionUnavailable || phase == .waitingForMotion else {
            stopReclaimRetries()
            return
        }
        // Don't poke the motion pipeline while it's already waiting on the first sample.
        if headTracker.isAwaitingFirstSample { return }

        let now = Date()
        guard now.timeIntervalSince(lastReclaimAttempt) >= 5.0 else { return }
        lastReclaimAttempt = now

        if reclaim.airPodsPresent() {
            _ = reclaim.reclaimAsDefaultAudio(aggressive: false)
            headTracker.softResume(reason: "auto-reclaim-audio")
        }
        // Bluetooth reconnect is user-driven only (Bring AirPods to Mac).
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "avert.main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // SwiftUI Window opens via openWindow in view; fall back to ordering any Avert window.
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func setEnabled(_ enabled: Bool) {
        settings.enabled = enabled
        isEnabled = enabled
        if enabled {
            enableTracking()
        } else {
            disableTracking()
        }
    }

    func setLookDownDimEnabled(_ enabled: Bool) {
        settings.lookDownDimEnabled = enabled
    }

    func setLookUpPanicEnabled(_ enabled: Bool) {
        settings.lookUpPanicEnabled = enabled
    }

    func setPanicCoverStyle(_ style: PanicCoverStyle) {
        settings.panicCoverStyle = style
        refreshPanicCoverMode()
    }

    func choosePanicImage() {
        if panicImages.pickImageFromUser() {
            settings.panicCoverStyle = .customImage
            refreshPanicCoverMode()
        }
    }

    func clearPanicImage() {
        panicImages.clear()
        if settings.panicCoverStyle == .customImage {
            settings.panicCoverStyle = .solidBlack
        }
        refreshPanicCoverMode()
    }

    private func refreshPanicCoverMode() {
        panicImagePreview = panicImages.loadImage()
        switch settings.panicCoverStyle {
        case .solidBlack:
            overlays.setPanicCoverMode(.solidBlack)
        case .customImage:
            if let image = panicImagePreview {
                overlays.setPanicCoverMode(.image(image))
            } else {
                overlays.setPanicCoverMode(.solidBlack)
            }
        }
    }

    func setNeckCareEnabled(_ enabled: Bool) {
        settings.neckCareEnabled = enabled
        if enabled {
            Task { await notifications.requestAuthorizationIfNeeded() }
        } else {
            neckCare.reset()
            neckCareStatus = ""
            refreshStatus(force: true)
        }
    }

    func setSustainedFlexEnabled(_ enabled: Bool) {
        settings.sustainedFlexEnabled = enabled
        if !enabled { neckCare.reset() }
    }

    func setStillnessMinutes(_ minutes: Int) {
        settings.stillnessMinutes = minutes
        neckCare.reset()
    }

    func setNeckExercisesEnabled(_ enabled: Bool) {
        settings.neckExercisesEnabled = enabled
        Task {
            await notifications.requestAuthorizationIfNeeded()
            notifications.scheduleNeckExerciseReminders(enabled: enabled)
        }
    }

    func setNeckExerciseVoiceEnabled(_ enabled: Bool) {
        settings.neckExerciseVoiceEnabled = enabled
        exerciseVoice.isEnabled = enabled
        if !enabled {
            exerciseVoice.stop()
        }
    }

    func openExerciseSession() {
        isCalibrationSheetPresented = false
        exerciseStepIndex = 0
        exerciseReps = 0
        exerciseVoice.isEnabled = settings.neckExerciseVoiceEnabled
        exerciseVoice.reset()
        configureExerciseTrackerForCurrentStep()
        // Privacy overlays would fight look-up / turns — clear and pause while exercising.
        if !isPanicBlurActive {
            overlays.clear()
        }
        isExerciseSheetPresented = true
        NotificationCenter.default.post(name: .avertOpenMainWindow, object: nil)
        exerciseVoice.announcePhase(id: exerciseTracker.speechPhaseID, prompt: exerciseTracker.spokenPrompt)
    }

    func finishExerciseSession(completed: Bool) {
        isExerciseSheetPresented = false
        exerciseCoachHint = "Start from center"
        exerciseAxisDegrees = 0
        exerciseVoice.stop()
        if completed {
            settings.lastNeckExerciseCompletedAt = Date()
            neckCareStatus = "Neck set done"
            exerciseVoice.announceSessionComplete()
            refreshStatus(force: true)
        } else {
            exerciseVoice.reset()
        }
    }

    func skipExerciseMove() {
        advanceExerciseMove()
    }

    func advanceExerciseMove() {
        let last = NeckExercise.catalog.count - 1
        if exerciseStepIndex >= last {
            finishExerciseSession(completed: true)
            return
        }
        exerciseStepIndex += 1
        exerciseReps = 0
        configureExerciseTrackerForCurrentStep()
    }

    private func configureExerciseTrackerForCurrentStep() {
        let exercise = NeckExercise.catalog[exerciseStepIndex]
        exerciseTracker.reset(kind: exercise.motion, invertVertical: settings.invertVerticalPitch)
        exerciseVoice.reset()
        refreshExercisePhaseUI()
        exerciseAxisDegrees = 0
        exerciseVoice.announcePhase(id: exerciseTracker.speechPhaseID, prompt: exerciseTracker.spokenPrompt)
    }

    private func refreshExercisePhaseUI() {
        let half = exerciseTracker.half
        let hint = exerciseTracker.coachHint
        let title = exerciseTracker.phaseTitle
        let cue = exerciseTracker.phaseCue
        let imageName = exerciseTracker.phaseImageName
        let holdDisplay = exerciseTracker.holdSecondsDisplay

        // Only publish when values change — motion arrives ~60 Hz.
        if exerciseHalf != half { exerciseHalf = half }
        if exerciseCoachHint != hint { exerciseCoachHint = hint }
        if exercisePhaseTitle != title { exercisePhaseTitle = title }
        if exercisePhaseCue != cue { exercisePhaseCue = cue }
        if exercisePhaseImageName != imageName { exercisePhaseImageName = imageName }
        if exerciseHoldSecondsDisplay != holdDisplay { exerciseHoldSecondsDisplay = holdDisplay }

        exerciseVoice.announcePhase(id: exerciseTracker.speechPhaseID, prompt: exerciseTracker.spokenPrompt)
        if exerciseTracker.shouldSpeakHoldCountdown, (1...3).contains(holdDisplay) {
            exerciseVoice.announceCountdown(displaySeconds: holdDisplay)
        }
    }

    private func ingestExercisePose(_ pose: RelativePose) {
        let axis = exerciseTracker.axisDegrees(pose)
        if exerciseAxisDegrees.rounded() != axis.rounded() {
            exerciseAxisDegrees = axis
        }

        let exercise = NeckExercise.catalog[exerciseStepIndex]
        guard exerciseReps < exercise.targetReps else {
            refreshExercisePhaseUI()
            return
        }

        let completedRep = exerciseTracker.ingest(pose: pose)
        refreshExercisePhaseUI()

        if completedRep {
            exerciseReps += 1
            exerciseVoice.announceRepComplete(exerciseReps, target: exercise.targetReps)
            if exerciseReps >= exercise.targetReps {
                exerciseCoachHint = exerciseStepIndex >= NeckExercise.catalog.count - 1
                    ? "Set complete — tap Done"
                    : "Nice — next set when ready"
                if exerciseStepIndex < NeckExercise.catalog.count - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        guard let self, self.isExerciseSheetPresented else { return }
                        let current = NeckExercise.catalog[self.exerciseStepIndex]
                        guard self.exerciseReps >= current.targetReps else { return }
                        self.advanceExerciseMove()
                    }
                }
            }
        }
    }

    func setDisplayCoverage(_ coverage: DisplayCoverage) {
        settings.displayCoverage = coverage
        overlays.setDisplayCoverage(coverage)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        _ = loginItem.setEnabled(enabled)
    }

    func setHotkeyEnabled(_ enabled: Bool) {
        settings.hotkeyEnabled = enabled
        if enabled {
            hotkey.start()
        } else {
            hotkey.stop()
        }
    }

    func setSingleEarMode(_ enabled: Bool) {
        settings.singleEarMode = enabled
        applySingleEarPreferences()
    }

    func setAutoRecalibrateOnEarSwitch(_ enabled: Bool) {
        settings.autoRecalibrateOnEarSwitch = enabled
    }

    private func applySingleEarPreferences() {
        // Single-ear + Automatic Ear Detection often flaps connect; give more grace.
        headTracker.setDisconnectGraceSeconds(settings.singleEarMode ? 2.6 : 1.2)
    }

    func clearRecalibrationPrompt() {
        needsRecalibration = false
        drift.reset()
        refreshStatus(force: true)
    }

    private func wireCallbacks() {
        headTracker.onStatusChange = { [weak self] status in
            self?.applyTrackerStatus(status)
        }
        headTracker.onRelativePose = { [weak self] pose in
            self?.handlePose(pose)
        }
        headTracker.onPreCalibrationSample = { [weak self] ear, count in
            self?.handlePreCalibrationSample(ear: ear, count: count)
        }
        headTracker.onHeadphonesDisconnected = { [weak self] in
            self?.handleDisconnect()
        }
        neckCare.onAlert = { [weak self] event in
            self?.handleNeckCare(event)
        }
        drift.onNeedsRecalibration = { [weak self] in
            self?.needsRecalibration = true
            self?.refreshStatus(force: true)
            self?.notifications.postRecalibratePrompt()
        }
        hotkey.onTogglePanic = { [weak self] in
            self?.togglePanicBlur()
        }
        headTracker.onActiveEarChanged = { [weak self] ear in
            self?.handleActiveEarChanged(ear)
        }
        reclaim.onAudioHardwareChanged = { [weak self] in
            self?.handleAudioHardwareChanged()
        }
    }

    private func handleAudioHardwareChanged() {
        guard isEnabled else { return }
        guard phase == .motionUnavailable || phase == .waitingForMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if self.reclaim.airPodsPresent() {
                _ = self.reclaim.reclaimAsDefaultAudio(aggressive: false)
            }
            self.headTracker.softResume(reason: "audio-hardware")
        }
    }

    private func handlePreCalibrationSample(ear: ActiveEar, count: Int) {
        activeEar = ear
        motionSampleCount = count
        if phase != .awaitingCalibration && phase != .tracking && phase != .schedulePaused {
            phase = .awaitingCalibration
            refreshStatus(force: true)
        }
        if isCalibrationSheetPresented {
            calibrationStep = headTracker.canCalibrate ? .faceScreen : .waitingForMotion
        }
        // Returning users: don't force the calibrate sheet — snap center once motion is steady.
        if settings.calibratedOnce, headTracker.referenceAttitude == nil {
            scheduleAutoCalibrate()
        }
    }

    private func scheduleAutoCalibrate() {
        guard isEnabled, settings.calibratedOnce else { return }
        guard headTracker.referenceAttitude == nil else { return }
        guard headTracker.canCalibrate else { return }
        guard autoCalibrateWork == nil else { return }
        // Brief settle so the first noisy sample after reconnect isn't used as center.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.autoCalibrateWork = nil
            guard self.isEnabled, self.settings.calibratedOnce else { return }
            guard self.headTracker.referenceAttitude == nil else { return }
            guard !self.isCalibrationSheetPresented else { return }
            guard !self.isExerciseSheetPresented else { return }
            if self.headTracker.calibrate(reason: "auto-resume") {
                self.privacy.reset()
                self.neckCare.reset()
                self.drift.reset()
                self.needsRecalibration = false
                self.phase = self.settings.isProtectionAllowed() ? .tracking : .schedulePaused
                self.lastYawDegrees = 0
                self.lastPitchDegrees = 0
                self.samplesAtCalibration = self.headTracker.sampleCount
                self.motionSampleCount = self.headTracker.sampleCount
                self.lastCalibrateSummary = "Auto"
                self.refreshStatus(force: true)
            }
        }
        autoCalibrateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func cancelAutoCalibrate() {
        autoCalibrateWork?.cancel()
        autoCalibrateWork = nil
    }

    private func handleActiveEarChanged(_ ear: ActiveEar) {
        activeEar = ear
        // Skip if we just calibrated manually — avoids the double "Calibrated after N" log.
        guard headTracker.secondsSinceCalibrate > 2.5 else {
            refreshStatus(force: true)
            return
        }
        guard settings.autoRecalibrateOnEarSwitch else {
            needsRecalibration = true
            refreshStatus(force: true)
            return
        }
        if headTracker.calibrate(reason: "ear-switch") {
            privacy.reset()
            overlays.clear()
            needsRecalibration = false
            motionSampleCount = headTracker.sampleCount
            lastCalibrateSummary = "OK"
            neckCareStatus = "Recentered on \(ear.title.lowercased())"
        } else {
            needsRecalibration = true
        }
        refreshStatus(force: true)
    }

    func togglePanicBlur() {
        isPanicBlurActive = overlays.togglePanic()
        refreshStatus(force: true)
    }

    private func handleNeckCare(_ event: NeckCareEvent) {
        notifications.postNeckCare(event)
        switch event {
        case .stillness:
            neckCareStatus = "Neck break suggested"
        case .sustainedFlex:
            neckCareStatus = "Posture reset suggested"
        }
        refreshStatus(force: true)
    }

    private func handleDisconnect() {
        guard isEnabled else { return }
        privacy.reset()
        neckCare.reset()
        drift.reset()
        if !isPanicBlurActive {
            overlays.clear()
        }
        lastYawDegrees = nil
        lastPitchDegrees = nil
        phase = .motionUnavailable
        scheduleReclaimRetries()
        // Keep calibration sheet on "waiting" only if they never had a reference;
        // after a call handoff we still have calibration and will auto-resume.
        if isCalibrationSheetPresented, headTracker.referenceAttitude == nil {
            calibrationStep = .waitingForMotion
        }
        refreshStatus(force: true)
    }

    private func applyTrackerStatus(_ status: HeadTrackerStatus) {
        guard isEnabled else { return }

        switch status {
        case .idle:
            break
        case .unavailable, .error, .waitingForHeadphones, .busyElsewhere:
            phase = .motionUnavailable
            privacy.reset()
            neckCare.reset()
            if !isPanicBlurActive { overlays.clear() }
            scheduleReclaimRetries()
        case .unauthorized:
            phase = .unauthorized
            privacy.reset()
            neckCare.reset()
            if !isPanicBlurActive { overlays.clear() }
            stopReclaimRetries()
        case .waitingForMotion:
            // After a call, we're waiting for samples but may still be calibrated.
            if headTracker.referenceAttitude != nil {
                phase = .motionUnavailable
                scheduleReclaimRetries()
            } else {
                phase = .waitingForMotion
            }
        case .readyToCalibrate:
            phase = .awaitingCalibration
            stopReclaimRetries()
            if isCalibrationSheetPresented, calibrationStep == .waitingForMotion {
                calibrationStep = .faceScreen
            }
            if settings.calibratedOnce, headTracker.referenceAttitude == nil {
                scheduleAutoCalibrate()
            }
        case .tracking:
            stopReclaimRetries()
            cancelAutoCalibrate()
            if headTracker.referenceAttitude == nil {
                phase = .awaitingCalibration
                if settings.calibratedOnce {
                    scheduleAutoCalibrate()
                }
            } else {
                phase = settings.isProtectionAllowed() ? .tracking : .schedulePaused
                if isCalibrationSheetPresented, calibrationStep == .waitingForMotion {
                    isCalibrationSheetPresented = false
                }
            }
        }
        refreshStatus(force: true)
    }

    private func handlePose(_ pose: RelativePose) {
        guard isEnabled, headTracker.referenceAttitude != nil else { return }

        lastYawDegrees = pose.yaw * 180.0 / .pi
        lastPitchDegrees = pose.pitch * 180.0 / .pi
        activeEar = pose.activeEar
        motionSampleCount = headTracker.sampleCount

        // Guided exercises own the head stream — count reps, don't veil the screen.
        if isExerciseSheetPresented {
            ingestExercisePose(pose)
            if !isPanicBlurActive { overlays.clear() }
            neckCare.ingest(pose: pose, facingScreen: false)
            return
        }

        let intent = privacy.intent(pose: pose)
        let allowed = settings.isProtectionAllowed()

        if !allowed {
            if phase != .schedulePaused {
                phase = .schedulePaused
                if !isPanicBlurActive { overlays.clear() }
                refreshStatus(force: true)
            }
            neckCare.ingest(pose: pose, facingScreen: false)
            return
        }

        if !isPanicBlurActive {
            if intent.lookUpPanic {
                if isCalibrationSheetPresented {
                    // During calibrate practice, show cover without sticky lock.
                    overlays.apply(intent)
                } else {
                    // Sticky: stays until ⌘⇧B / Clear — looking down does not dismiss.
                    isPanicBlurActive = overlays.setPanic(true)
                    refreshStatus(force: true)
                }
            } else {
                overlays.apply(intent)
            }
        }
        neckCare.ingest(pose: pose, facingScreen: intent.facingScreen)
        drift.ingest(pose: pose, facingScreenBand: intent.facingScreen)

        if phase != .tracking {
            phase = .tracking
            refreshStatus(force: true)
        }
        updateCalibrationPractice(intent)
    }

    private func updateCalibrationPractice(_ intent: BlurIntent) {
        guard isCalibrationSheetPresented else { return }
        switch calibrationStep {
        case .practiceLeft:
            if intent.side == .left {
                sawLeftBlur = true
                calibrationStep = .practiceRight
            }
        case .practiceRight:
            if intent.side == .right {
                sawRightBlur = true
                calibrationStep = .practiceDown
            }
        case .practiceDown:
            if intent.lookDownDim > 0.2 {
                calibrationStep = .practiceUp
            }
        case .practiceUp:
            if intent.lookUpPanic {
                calibrationStep = .done
            }
        default:
            break
        }
    }

    private func refreshStatus(force: Bool = false) {
        if !isEnabled {
            setStatusLine("Off", force: force)
            return
        }

        let next: String
        if isPanicBlurActive {
            next = "Panic blur on — ⌘⇧B to clear"
        } else if needsRecalibration {
            next = "Recalibrate suggested"
        } else {
            switch phase {
            case .disabled:
                next = "Off"
            case .unauthorized:
                next = "Allow Motion in System Settings"
            case .waitingForMotion:
                next = "Waiting for AirPods…"
            case .awaitingCalibration:
                next = "Ready to calibrate"
            case .tracking:
                next = neckCareStatus.isEmpty ? "Tracking" : neckCareStatus
            case .motionUnavailable:
                next = "AirPods on call / other device"
            case .schedulePaused:
                next = "Paused by schedule"
            }
        }

        setStatusLine(next, force: force)
    }

    private func setStatusLine(_ next: String, force: Bool) {
        guard force || next != statusLine else { return }
        statusLine = next
        lastStatusPublish = Date()
    }
}

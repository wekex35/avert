import Foundation

enum DisplayCoverage: String, CaseIterable, Identifiable {
    case allDisplays
    case mainOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allDisplays: return "All displays"
        case .mainOnly: return "Built-in / main only"
        }
    }
}

enum ScheduleMode: String, CaseIterable, Identifiable {
    case always
    case activeHours
    case outsideWorkHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Always when enabled"
        case .activeHours: return "Only during active hours"
        case .outsideWorkHours: return "Only outside work hours"
        }
    }
}

enum PanicCoverStyle: String, CaseIterable, Identifiable {
    case solidBlack
    case customImage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solidBlack: return "Solid black"
        case .customImage: return "Selected image"
        }
    }
}

@MainActor
final class SettingsStore {
    private enum Key {
        static let enabled = "enabled"
        static let yawThresholdDegrees = "yawThresholdDegrees"
        static let pitchLookDownDegrees = "pitchLookDownDegrees"
        static let blurIntensity = "blurIntensity"
        static let fadeMilliseconds = "fadeMilliseconds"
        static let calibratedOnce = "calibratedOnce"
        static let lookDownDimEnabled = "lookDownDimEnabled"
        static let lookUpPanicEnabled = "lookUpPanicEnabled"
        static let pitchLookUpDegrees = "pitchLookUpDegrees"
        static let invertVerticalPitch = "invertVerticalPitch"
        static let panicCoverStyle = "panicCoverStyle"
        static let neckCareEnabled = "neckCareEnabled"
        static let stillnessMinutes = "stillnessMinutes"
        static let sustainedFlexEnabled = "sustainedFlexEnabled"
        static let flexPitchDegrees = "flexPitchDegrees"
        static let flexMinutes = "flexMinutes"
        static let displayCoverage = "displayCoverage"
        static let scheduleMode = "scheduleMode"
        static let scheduleStartHour = "scheduleStartHour"
        static let scheduleEndHour = "scheduleEndHour"
        static let workStartHour = "workStartHour"
        static let workEndHour = "workEndHour"
        static let autoRecalibratePrompt = "autoRecalibratePrompt"
        static let launchAtLogin = "launchAtLogin"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let singleEarMode = "singleEarMode"
        static let autoRecalibrateOnEarSwitch = "autoRecalibrateOnEarSwitch"
        static let neckExercisesEnabled = "neckExercisesEnabled"
        static let neckExerciseVoiceEnabled = "neckExerciseVoiceEnabled"
        static let lastNeckExerciseCompletedAt = "lastNeckExerciseCompletedAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
        migrateLookDownThresholdIfNeeded()
    }

    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var yawThresholdDegrees: Double {
        get { defaults.double(forKey: Key.yawThresholdDegrees) }
        set { defaults.set(newValue, forKey: Key.yawThresholdDegrees) }
    }

    var pitchLookDownDegrees: Double {
        get { defaults.double(forKey: Key.pitchLookDownDegrees) }
        set { defaults.set(newValue, forKey: Key.pitchLookDownDegrees) }
    }

    var blurIntensity: Double {
        get { defaults.double(forKey: Key.blurIntensity) }
        set { defaults.set(min(1, max(0, newValue)), forKey: Key.blurIntensity) }
    }

    var fadeMilliseconds: Int {
        get { defaults.integer(forKey: Key.fadeMilliseconds) }
        set { defaults.set(newValue, forKey: Key.fadeMilliseconds) }
    }

    var calibratedOnce: Bool {
        get { defaults.bool(forKey: Key.calibratedOnce) }
        set { defaults.set(newValue, forKey: Key.calibratedOnce) }
    }

    var lookDownDimEnabled: Bool {
        get { defaults.bool(forKey: Key.lookDownDimEnabled) }
        set { defaults.set(newValue, forKey: Key.lookDownDimEnabled) }
    }

    var lookUpPanicEnabled: Bool {
        get { defaults.bool(forKey: Key.lookUpPanicEnabled) }
        set { defaults.set(newValue, forKey: Key.lookUpPanicEnabled) }
    }

    var pitchLookUpDegrees: Double {
        get { defaults.double(forKey: Key.pitchLookUpDegrees) }
        set { defaults.set(newValue, forKey: Key.pitchLookUpDegrees) }
    }

    /// When true, flip up/down pitch so look-up / look-down match your AirPods.
    var invertVerticalPitch: Bool {
        get { defaults.bool(forKey: Key.invertVerticalPitch) }
        set { defaults.set(newValue, forKey: Key.invertVerticalPitch) }
    }

    var panicCoverStyle: PanicCoverStyle {
        get {
            PanicCoverStyle(rawValue: defaults.string(forKey: Key.panicCoverStyle) ?? "") ?? .solidBlack
        }
        set { defaults.set(newValue.rawValue, forKey: Key.panicCoverStyle) }
    }

    var neckCareEnabled: Bool {
        get { defaults.bool(forKey: Key.neckCareEnabled) }
        set { defaults.set(newValue, forKey: Key.neckCareEnabled) }
    }

    var stillnessMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.stillnessMinutes)
            return max(2, v == 0 ? 20 : v)
        }
        set { defaults.set(min(60, max(2, newValue)), forKey: Key.stillnessMinutes) }
    }

    var sustainedFlexEnabled: Bool {
        get { defaults.bool(forKey: Key.sustainedFlexEnabled) }
        set { defaults.set(newValue, forKey: Key.sustainedFlexEnabled) }
    }

    var flexPitchDegrees: Double {
        get { defaults.double(forKey: Key.flexPitchDegrees) }
        set { defaults.set(newValue, forKey: Key.flexPitchDegrees) }
    }

    var flexMinutes: Int {
        get { max(5, defaults.integer(forKey: Key.flexMinutes)) }
        set { defaults.set(min(60, max(5, newValue)), forKey: Key.flexMinutes) }
    }

    var displayCoverage: DisplayCoverage {
        get {
            DisplayCoverage(rawValue: defaults.string(forKey: Key.displayCoverage) ?? "") ?? .allDisplays
        }
        set { defaults.set(newValue.rawValue, forKey: Key.displayCoverage) }
    }

    var scheduleMode: ScheduleMode {
        get {
            ScheduleMode(rawValue: defaults.string(forKey: Key.scheduleMode) ?? "") ?? .always
        }
        set { defaults.set(newValue.rawValue, forKey: Key.scheduleMode) }
    }

    var scheduleStartHour: Int {
        get { defaults.integer(forKey: Key.scheduleStartHour) }
        set { defaults.set(min(23, max(0, newValue)), forKey: Key.scheduleStartHour) }
    }

    var scheduleEndHour: Int {
        get { defaults.integer(forKey: Key.scheduleEndHour) }
        set { defaults.set(min(23, max(0, newValue)), forKey: Key.scheduleEndHour) }
    }

    var workStartHour: Int {
        get { defaults.integer(forKey: Key.workStartHour) }
        set { defaults.set(min(23, max(0, newValue)), forKey: Key.workStartHour) }
    }

    var workEndHour: Int {
        get { defaults.integer(forKey: Key.workEndHour) }
        set { defaults.set(min(23, max(0, newValue)), forKey: Key.workEndHour) }
    }

    var autoRecalibratePrompt: Bool {
        get { defaults.bool(forKey: Key.autoRecalibratePrompt) }
        set { defaults.set(newValue, forKey: Key.autoRecalibratePrompt) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var hotkeyEnabled: Bool {
        get { defaults.bool(forKey: Key.hotkeyEnabled) }
        set { defaults.set(newValue, forKey: Key.hotkeyEnabled) }
    }

    /// Prefer single-bud use: longer disconnect grace + show which ear is streaming.
    var singleEarMode: Bool {
        get { defaults.bool(forKey: Key.singleEarMode) }
        set { defaults.set(newValue, forKey: Key.singleEarMode) }
    }

    /// When the streaming bud switches, reset calibration center (avoids a sudden veil jump).
    var autoRecalibrateOnEarSwitch: Bool {
        get { defaults.bool(forKey: Key.autoRecalibrateOnEarSwitch) }
        set { defaults.set(newValue, forKey: Key.autoRecalibrateOnEarSwitch) }
    }

    /// Remind every 2 hours to run the 6-move neck set once.
    var neckExercisesEnabled: Bool {
        get { defaults.bool(forKey: Key.neckExercisesEnabled) }
        set { defaults.set(newValue, forKey: Key.neckExercisesEnabled) }
    }

    var neckExerciseVoiceEnabled: Bool {
        get { defaults.bool(forKey: Key.neckExerciseVoiceEnabled) }
        set { defaults.set(newValue, forKey: Key.neckExerciseVoiceEnabled) }
    }

    var lastNeckExerciseCompletedAt: Date? {
        get { defaults.object(forKey: Key.lastNeckExerciseCompletedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastNeckExerciseCompletedAt) }
    }

    var fadeDuration: TimeInterval {
        Double(fadeMilliseconds) / 1_000.0
    }

    var yawThresholdRadians: Double {
        yawThresholdDegrees * .pi / 180.0
    }

    var pitchLookDownRadians: Double {
        pitchLookDownDegrees * .pi / 180.0
    }

    var pitchLookUpRadians: Double {
        pitchLookUpDegrees * .pi / 180.0
    }

    var flexPitchRadians: Double {
        flexPitchDegrees * .pi / 180.0
    }

    var stillnessInterval: TimeInterval {
        TimeInterval(stillnessMinutes * 60)
    }

    var flexInterval: TimeInterval {
        TimeInterval(flexMinutes * 60)
    }

    /// Whether protection overlays should run right now (enabled ∧ schedule).
    func isProtectionAllowed(at date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        switch scheduleMode {
        case .always:
            return true
        case .activeHours:
            return isHour(hour, inStart: scheduleStartHour, end: scheduleEndHour)
        case .outsideWorkHours:
            return !isHour(hour, inStart: workStartHour, end: workEndHour)
        }
    }

    private func isHour(_ hour: Int, inStart start: Int, end: Int) -> Bool {
        if start == end { return true }
        if start < end {
            return hour >= start && hour < end
        }
        // Wraps midnight
        return hour >= start || hour < end
    }

    private func migrateLookDownThresholdIfNeeded() {
        let flag = "migratedPitchLookDown18"
        guard !defaults.bool(forKey: flag) else { return }
        // Old default (28°) was too steep for laptop chin-tuck; ease existing installs once.
        if defaults.object(forKey: Key.pitchLookDownDegrees) != nil,
           defaults.double(forKey: Key.pitchLookDownDegrees) >= 26 {
            defaults.set(18.0, forKey: Key.pitchLookDownDegrees)
        }
        defaults.set(true, forKey: flag)
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.enabled: false,
            Key.yawThresholdDegrees: 22.5,
            Key.pitchLookDownDegrees: 18.0,
            Key.blurIntensity: 1.0,
            Key.fadeMilliseconds: 200,
            Key.calibratedOnce: false,
            Key.lookDownDimEnabled: true,
            Key.lookUpPanicEnabled: true,
            Key.pitchLookUpDegrees: 14.0,
            Key.invertVerticalPitch: false,
            Key.panicCoverStyle: PanicCoverStyle.solidBlack.rawValue,
            Key.neckCareEnabled: true,
            Key.stillnessMinutes: 20,
            Key.sustainedFlexEnabled: true,
            Key.flexPitchDegrees: 20.0,
            Key.flexMinutes: 15,
            Key.displayCoverage: DisplayCoverage.allDisplays.rawValue,
            Key.scheduleMode: ScheduleMode.always.rawValue,
            Key.scheduleStartHour: 8,
            Key.scheduleEndHour: 22,
            Key.workStartHour: 9,
            Key.workEndHour: 18,
            Key.autoRecalibratePrompt: true,
            Key.launchAtLogin: false,
            Key.hotkeyEnabled: true,
            Key.singleEarMode: true,
            Key.autoRecalibrateOnEarSwitch: true,
            Key.neckExercisesEnabled: true,
            Key.neckExerciseVoiceEnabled: true,
        ])
    }
}

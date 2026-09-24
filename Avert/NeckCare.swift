import Foundation

enum NeckCareEvent: Equatable {
    case stillness
    case sustainedFlex
}

/// Watches AirPods motion for prolonged stillness / flexed pitch while facing the screen.
/// Wellness nudge only — not a medical diagnosis.
///
/// Clinical / ergonomic anchors (not medical claims):
/// - Stillness reminder cadence ~20 min: Stanford EH&S microbreaks (30–60 s every ~20 min)
///   for static seated posture; OSHA also advises frequent short pauses (e.g. ~5 min/hour).
/// - Neck flexion risk band ~20°: systematic review in Ergonomics (2021) — 20° is the most
///   evidence-supported occupational cut-off separating higher- vs lower-risk neck flexion.
/// - “Still” angular-velocity offset ~5°/s (0.087 rad/s): human IMU literature commonly treats
///   ~0.1 rad/s as the voluntary-movement floor (e.g. Schwarz et al. reach segmentation);
///   values well below that are treated as stationary / micromotion.
/// - Pose deadband ~5° combined: ignores tiny corrective wobble; intentional look-aways exceed it.
/// - Short dwell (~5 s) before starting long timers: posture-feedback systems require sustained
///   non-neutral posture (not a flicker) before counting exposure.
@MainActor
final class NeckCareMonitor {
    private let settings: SettingsStore
    private var stillnessCandidateSince: Date?
    private var stillnessAccumStarted: Date?
    private var flexCandidateSince: Date?
    private var flexAccumStarted: Date?
    private var lastStillnessAlert: Date?
    private var lastFlexAlert: Date?
    /// Avoid nagging more than twice per hour.
    private let cooldown: TimeInterval = 30 * 60

    /// ~5°/s — below typical voluntary head turns; above quiet sensor noise.
    private let stillRateThreshold = 5.0 * .pi / 180.0
    /// ~5° combined Euler drift between samples counts as movement.
    private let stillPoseEpsilon = 5.0 * .pi / 180.0
    /// Must stay still / flexed this long before the long exposure clock starts.
    private let dwellSeconds: TimeInterval = 5

    private var lastPose: RelativePose?

    var onAlert: ((NeckCareEvent) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func reset() {
        stillnessCandidateSince = nil
        stillnessAccumStarted = nil
        flexCandidateSince = nil
        flexAccumStarted = nil
        lastPose = nil
    }

    func ingest(pose: RelativePose, facingScreen: Bool) {
        guard settings.neckCareEnabled || settings.sustainedFlexEnabled else {
            reset()
            return
        }

        let moving = isMoving(pose)
        let now = Date()

        if settings.neckCareEnabled {
            updateStillness(now: now, facingScreen: facingScreen, moving: moving)
        } else {
            stillnessCandidateSince = nil
            stillnessAccumStarted = nil
        }

        if settings.sustainedFlexEnabled {
            updateFlex(now: now, pitch: pose.pitch)
        } else {
            flexCandidateSince = nil
            flexAccumStarted = nil
        }

        lastPose = pose
    }

    private func updateStillness(now: Date, facingScreen: Bool, moving: Bool) {
        let qualifies = facingScreen && !moving
        if !qualifies {
            stillnessCandidateSince = nil
            stillnessAccumStarted = nil
            return
        }

        if stillnessCandidateSince == nil {
            stillnessCandidateSince = now
        }

        let candidateAge = now.timeIntervalSince(stillnessCandidateSince ?? now)
        guard candidateAge >= dwellSeconds else {
            stillnessAccumStarted = nil
            return
        }

        if stillnessAccumStarted == nil {
            stillnessAccumStarted = now
        }

        guard let start = stillnessAccumStarted,
              now.timeIntervalSince(start) >= settings.stillnessInterval,
              canFire(last: lastStillnessAlert, now: now)
        else { return }

        lastStillnessAlert = now
        // Keep candidate, restart accumulation so another reminder can fire after cooldown.
        stillnessAccumStarted = now
        onAlert?(.stillness)
    }

    private func updateFlex(now: Date, pitch: Double) {
        // |pitch| vs calibrated center — mirrors occupational neck-flexion exposure.
        let flexed = abs(pitch) >= settings.flexPitchRadians
        if !flexed {
            flexCandidateSince = nil
            flexAccumStarted = nil
            return
        }

        if flexCandidateSince == nil {
            flexCandidateSince = now
        }

        let candidateAge = now.timeIntervalSince(flexCandidateSince ?? now)
        guard candidateAge >= dwellSeconds else {
            flexAccumStarted = nil
            return
        }

        if flexAccumStarted == nil {
            flexAccumStarted = now
        }

        guard let start = flexAccumStarted,
              now.timeIntervalSince(start) >= settings.flexInterval,
              canFire(last: lastFlexAlert, now: now)
        else { return }

        lastFlexAlert = now
        flexAccumStarted = now
        onAlert?(.sustainedFlex)
    }

    private func isMoving(_ pose: RelativePose) -> Bool {
        if pose.rotationRateMagnitude >= stillRateThreshold {
            return true
        }
        guard let last = lastPose else { return false }
        let dy = abs(pose.yaw - last.yaw)
        let dp = abs(pose.pitch - last.pitch)
        let dr = abs(pose.roll - last.roll)
        return (dy + dp + dr) >= stillPoseEpsilon
    }

    private func canFire(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }
}

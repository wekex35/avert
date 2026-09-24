import Foundation

/// Half of a compound mobility cycle (out in one direction, then return to center).
enum ExerciseHalf: Equatable {
    case first
    case second
}

enum ExerciseMotionKind: String, Equatable {
    case vertical   // down then up
    case tilt       // left then right
    case turn       // left then right
}

private enum ExerciseBeat: Equatable {
    case holdCenter
    case goOut
    case holdOut
    case returnCenter
}

/// Guided neck mobility with timing aligned to common flexibility guidance:
/// - ACSM: static stretch 10–30s at tightness (not pain); 2–4 reps (~60s total / joint)
/// - ACE neck flexion: 15–30s; neck extension: 5–10s; move slow, shoulders down
/// - Center is only a short reset (2–3s), not a stretch hold
@MainActor
final class ExerciseRepTracker {
    private let enterDegrees: Double = 18
    private let returnDegrees: Double = 9
    /// Brief neutral reset between stretches (not a clinical stretch hold).
    private let centerHoldSeconds: TimeInterval = 2.5

    private var kind: ExerciseMotionKind = .vertical
    private var invertVertical = false

    private(set) var half: ExerciseHalf = .first
    private var beat: ExerciseBeat = .holdCenter
    private var centerAccum: TimeInterval = 0
    private var outAccum: TimeInterval = 0
    private var lastSampleAt: Date?

    func reset(kind: ExerciseMotionKind, invertVertical: Bool) {
        self.kind = kind
        self.invertVertical = invertVertical
        half = .first
        beat = .holdCenter
        centerAccum = 0
        outAccum = 0
        lastSampleAt = nil
    }

    /// Clinical outward hold for the current half.
    private var outboundHoldSeconds: TimeInterval {
        switch (kind, half) {
        case (.vertical, .first):
            // ACE neck flexion: 15–30s
            return 18
        case (.vertical, .second):
            // ACE neck extension: 5–10s (more cautious looking up)
            return 8
        case (.tilt, _), (.turn, _):
            // Side-bend / rotation stretches commonly 15–30s
            return 18
        }
    }

    var holdSecondsRemaining: TimeInterval {
        switch beat {
        case .holdCenter, .returnCenter:
            return max(0, centerHoldSeconds - centerAccum)
        case .holdOut:
            return max(0, outboundHoldSeconds - outAccum)
        case .goOut:
            return outboundHoldSeconds
        }
    }

    /// Whole seconds shown on the big timer and spoken for 3-2-1 (same value).
    var holdSecondsDisplay: Int {
        let remaining = holdSecondsRemaining
        guard remaining > 0.05 else { return 0 }
        return max(1, Int(ceil(remaining)))
    }

    @discardableResult
    func ingest(pose: RelativePose) -> Bool {
        let now = Date()
        let dt: TimeInterval
        if let last = lastSampleAt {
            dt = min(0.25, max(0, now.timeIntervalSince(last)))
        } else {
            dt = 1.0 / 60.0
        }
        lastSampleAt = now

        let value = axisDegrees(for: half, pose: pose)
        var completedRep = false

        switch beat {
        case .holdCenter:
            if value <= returnDegrees {
                centerAccum += dt
                if centerAccum >= centerHoldSeconds {
                    beat = .goOut
                    outAccum = 0
                }
            }
            // Stay put if briefly off-center — resetting made the timer jump 3→0→3.

        case .goOut:
            if value >= enterDegrees {
                beat = .holdOut
                outAccum = 0
            }

        case .holdOut:
            // Pause the clock when out of position; never rewind (that flickered the timer).
            if value >= enterDegrees * 0.65 {
                outAccum += dt
            }
            if outAccum >= outboundHoldSeconds {
                beat = .returnCenter
                centerAccum = 0
            }

        case .returnCenter:
            if value <= returnDegrees {
                centerAccum += dt
                if centerAccum >= centerHoldSeconds {
                    completedRep = finishHalf()
                }
            }
            // Same as holdCenter — don't wipe progress on a brief wobble.
        }

        return completedRep
    }

    private func finishHalf() -> Bool {
        centerAccum = 0
        outAccum = 0
        beat = .holdCenter

        switch half {
        case .first:
            half = .second
            return false
        case .second:
            half = .first
            return true
        }
    }

    func axisDegrees(for half: ExerciseHalf, pose: RelativePose) -> Double {
        let rad: Double
        switch (kind, half) {
        case (.vertical, .first):
            let vertical = invertVertical ? -pose.pitch : pose.pitch
            rad = -vertical
        case (.vertical, .second):
            let vertical = invertVertical ? -pose.pitch : pose.pitch
            rad = vertical
        case (.tilt, .first):
            rad = -pose.roll
        case (.tilt, .second):
            rad = pose.roll
        case (.turn, .first):
            rad = -pose.yaw
        case (.turn, .second):
            rad = pose.yaw
        }
        return rad * 180.0 / .pi
    }

    func axisDegrees(_ pose: RelativePose) -> Double {
        axisDegrees(for: half, pose: pose)
    }

    private var centerImageName: String {
        switch kind {
        case .vertical: return "look-center"
        case .tilt: return "tilt-center"
        case .turn: return "turn-center"
        }
    }

    private var outwardImageName: String {
        switch (kind, half) {
        case (.vertical, .first): return "look-down"
        case (.vertical, .second): return "look-up"
        case (.tilt, .first): return "tilt-left"
        case (.tilt, .second): return "tilt-right"
        case (.turn, .first): return "turn-left"
        case (.turn, .second): return "turn-right"
        }
    }

    var showingCenter: Bool {
        switch beat {
        case .holdCenter, .returnCenter: return true
        case .goOut, .holdOut: return false
        }
    }

    var coachHint: String {
        // Stable copy — live seconds live only in the big timer (avoids hint text thrash).
        switch beat {
        case .holdCenter:
            return "Neutral — shoulders down, hold center"
        case .goOut:
            switch (kind, half) {
            case (.vertical, .first):
                return "Slowly chin toward chest (don’t bounce)"
            case (.vertical, .second):
                return "Slowly look up — keep shoulders relaxed"
            case (.tilt, .first):
                return "Ear toward left shoulder — don’t shrug"
            case (.tilt, .second):
                return "Ear toward right shoulder — don’t shrug"
            case (.turn, .first):
                return "Slowly look over left shoulder"
            case (.turn, .second):
                return "Slowly look over right shoulder"
            }
        case .holdOut:
            return "Hold gentle stretch (tightness OK, not pain)"
        case .returnCenter:
            return "Return to center and hold"
        }
    }

    var phaseTitle: String {
        if showingCenter { return "Center" }
        switch (kind, half) {
        case (.vertical, .first): return "Look Down"
        case (.vertical, .second): return "Look Up"
        case (.tilt, .first): return "Tilt Left"
        case (.tilt, .second): return "Tilt Right"
        case (.turn, .first): return "Turn Left"
        case (.turn, .second): return "Turn Right"
        }
    }

    var phaseCue: String {
        if showingCenter {
            return "Face ahead, shoulders down"
        }
        switch (kind, half) {
        case (.vertical, .first):
            return "Chin to chest"
        case (.vertical, .second):
            return "Chin up, shoulders soft"
        case (.tilt, .first), (.tilt, .second):
            return "Ear to shoulder, no shrug"
        case (.turn, .first), (.turn, .second):
            return "Look over shoulder, slow"
        }
    }

    var phaseImageName: String {
        showingCenter ? centerImageName : outwardImageName
    }

    /// Tied to the visible image so voice only fires when the picture changes.
    var speechPhaseID: String {
        phaseImageName
    }

    /// Countdown only on the stretch hold — not on short center resets.
    var shouldSpeakHoldCountdown: Bool {
        beat == .holdOut
    }

    /// Same words as the on-screen phase title (kept short so image/voice stay locked).
    var spokenPrompt: String {
        switch beat {
        case .holdCenter, .returnCenter:
            return "Center"
        case .goOut, .holdOut:
            return phaseTitle
        }
    }
}

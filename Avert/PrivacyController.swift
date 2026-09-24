import Foundation

enum BlurSide: Equatable {
    case none
    case left
    case right
}

struct BlurIntent: Equatable {
    var side: BlurSide
    /// 0…1 strength for the directional veil.
    var intensity: Double
    /// 0…1 soft full-screen dim when looking down.
    var lookDownDim: Double
    /// When true, apply full-screen panic veil (look up).
    var lookUpPanic: Bool
    /// True when yaw is near center (facing the calibrated screen pose).
    var facingScreen: Bool

    static let clear = BlurIntent(
        side: .none,
        intensity: 0,
        lookDownDim: 0,
        lookUpPanic: false,
        facingScreen: true
    )
}

/// Maps relative pose → blur / dim with hysteresis.
@MainActor
final class PrivacyController {
    private let settings: SettingsStore
    private var lastSide: BlurSide = .none
    private var lookUpLatched = false
    private var lookDownLatched = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func reset() {
        lastSide = .none
        lookUpLatched = false
        lookDownLatched = false
    }

    func intent(pose: RelativePose) -> BlurIntent {
        let yaw = pose.yaw
        let pitch = pose.pitch
        let threshold = settings.yawThresholdRadians
        let hysteresis = 5.0 * .pi / 180.0
        let clearBand = max(0, threshold - hysteresis)
        let maxOpacity = settings.blurIntensity

        let facing = abs(yaw) < clearBand
        let lookDown = lookDownAmount(pitch: pitch)
        let lookUp = lookUpPanic(pitch: pitch)

        let sideIntent: (BlurSide, Double)
        switch lastSide {
        case .none:
            if yaw <= -threshold {
                lastSide = .left
                sideIntent = (.left, opacity(for: abs(yaw), threshold: threshold, max: maxOpacity))
            } else if yaw >= threshold {
                lastSide = .right
                sideIntent = (.right, opacity(for: abs(yaw), threshold: threshold, max: maxOpacity))
            } else {
                sideIntent = (.none, 0)
            }

        case .left:
            if yaw > -clearBand {
                lastSide = .none
                sideIntent = (.none, 0)
            } else if yaw >= threshold {
                lastSide = .right
                sideIntent = (.right, opacity(for: abs(yaw), threshold: threshold, max: maxOpacity))
            } else {
                sideIntent = (.left, opacity(for: abs(yaw), threshold: threshold, max: maxOpacity))
            }

        case .right:
            if yaw < clearBand {
                lastSide = .none
                sideIntent = (.none, 0)
            } else if yaw <= -threshold {
                lastSide = .left
                sideIntent = (.left, opacity(for: abs(yaw), threshold: threshold, max: maxOpacity))
            } else {
                sideIntent = (.right, opacity(for: abs(yaw), threshold: threshold, max: maxOpacity))
            }
        }

        return BlurIntent(
            side: lookUp ? .none : sideIntent.0,
            intensity: lookUp ? 0 : sideIntent.1,
            lookDownDim: lookUp ? 0 : lookDown,
            lookUpPanic: lookUp,
            facingScreen: facing && sideIntent.0 == .none && !lookUp
        )
    }

    /// Vertical pitch after optional invert. Positive = chin up / look toward ceiling.
    private func verticalPitch(_ pitch: Double) -> Double {
        settings.invertVerticalPitch ? -pitch : pitch
    }

    /// Looking up past threshold → full panic veil. Hysteresis clears when returning toward center.
    private func lookUpPanic(pitch: Double) -> Bool {
        guard settings.lookUpPanicEnabled else {
            lookUpLatched = false
            return false
        }
        let enter = settings.pitchLookUpRadians
        let exit = max(0, enter - (8.0 * .pi / 180.0))
        // Core Motion headphone pitch: chin up is typically positive after relative calibration.
        let up = verticalPitch(pitch)
        if lookUpLatched {
            if up < exit { lookUpLatched = false }
        } else if up > enter {
            lookUpLatched = true
        }
        return lookUpLatched
    }

    private func lookDownAmount(pitch: Double) -> Double {
        guard settings.lookDownDimEnabled else {
            lookDownLatched = false
            return 0
        }
        let enter = settings.pitchLookDownRadians
        // Exit a bit sooner so dim clears when you lift your chin back to the screen.
        let exit = max(0, enter - (6.0 * .pi / 180.0))
        // Looking down = negative pitch on the same axis as look-up.
        let down = max(0, -verticalPitch(pitch))

        if lookDownLatched {
            if down < exit {
                lookDownLatched = false
                return 0
            }
        } else if down > enter {
            lookDownLatched = true
        } else {
            return 0
        }

        // Ramp from ~30% → ~80% black as you tuck further past the threshold.
        let span = max(enter * 0.9, 8.0 * .pi / 180.0)
        let t = min(1, max(0, (down - enter) / span))
        return 0.30 + 0.50 * t
    }

    private func opacity(for absoluteYaw: Double, threshold: Double, max maxOpacity: Double) -> Double {
        guard threshold > 0 else { return maxOpacity }
        let t = min(1, max(0, (absoluteYaw - threshold) / (threshold * 0.5)))
        return (0.75 + 0.25 * t) * maxOpacity
    }
}

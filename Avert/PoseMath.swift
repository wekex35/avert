import CoreMotion
import Foundation

enum ActiveEar: String, Equatable {
    case unknown
    case left
    case right

    var title: String {
        switch self {
        case .unknown: return "Ear unknown"
        case .left: return "Left ear"
        case .right: return "Right ear"
        }
    }

    var shortTitle: String {
        switch self {
        case .unknown: return "—"
        case .left: return "L"
        case .right: return "R"
        }
    }

    init(sensorLocation: CMDeviceMotion.SensorLocation) {
        switch sensorLocation {
        case .headphoneLeft: self = .left
        case .headphoneRight: self = .right
        default: self = .unknown
        }
    }
}

struct RelativePose: Equatable {
    var yaw: Double
    var pitch: Double
    var roll: Double
    /// Magnitude of rotation rate (rad/s) — used for stillness detection.
    var rotationRateMagnitude: Double
    var activeEar: ActiveEar

    static let zero = RelativePose(
        yaw: 0,
        pitch: 0,
        roll: 0,
        rotationRateMagnitude: 0,
        activeEar: .unknown
    )
}

enum PoseMath {
    static func relative(
        current: CMAttitude,
        reference: CMAttitude,
        rotationRate: CMRotationRate,
        sensorLocation: CMDeviceMotion.SensorLocation
    ) -> RelativePose {
        let relative = current.copy() as! CMAttitude
        relative.multiply(byInverseOf: reference)
        let rate = sqrt(
            rotationRate.x * rotationRate.x +
            rotationRate.y * rotationRate.y +
            rotationRate.z * rotationRate.z
        )
        return RelativePose(
            yaw: relative.yaw,
            pitch: relative.pitch,
            roll: relative.roll,
            rotationRateMagnitude: rate,
            activeEar: ActiveEar(sensorLocation: sensorLocation)
        )
    }
}

import SwiftUI

enum CalibrationStep: Equatable {
    case waitingForMotion
    case faceScreen
    case practiceLeft
    case practiceRight
    case practiceDown
    case practiceUp
    case done
}

/// Full calibration dialog (sheet).
struct CalibrationFlowView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Calibrate Avert")
                .font(.title2.weight(.semibold))

            Text(title)
                .font(.title3.weight(.medium))

            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.calibrationStep == .waitingForMotion || model.calibrationStep == .faceScreen {
                Text(model.canCalibrate ? "Motion ready" : "Waiting for AirPods motion…")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack {
                if model.calibrationStep != .done {
                    Button("Cancel") {
                        model.cancelCalibrationFlow()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                Spacer()

                switch model.calibrationStep {
                case .waitingForMotion, .faceScreen:
                    Button("I’m facing the screen — Calibrate") {
                        model.confirmCalibrationInFlow()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canCalibrate)
                    .keyboardShortcut(.defaultAction)

                case .practiceLeft, .practiceRight, .practiceDown, .practiceUp:
                    Button("Skip") {
                        model.advanceCalibrationPractice()
                    }
                    .buttonStyle(.bordered)

                case .done:
                    Button("Done") {
                        model.finishCalibrationFlow()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 440, height: 300)
    }

    private var title: String {
        switch model.calibrationStep {
        case .waitingForMotion: return "Waiting for AirPods…"
        case .faceScreen: return "Face your screen"
        case .practiceLeft: return "Look left"
        case .practiceRight: return "Look right"
        case .practiceDown: return "Look down"
        case .practiceUp: return "Look up"
        case .done: return "Done"
        }
    }

    private var subtitle: String {
        switch model.calibrationStep {
        case .waitingForMotion:
            return "Keep an AirPod in. Avert will enable Calibrate when motion arrives."
        case .faceScreen:
            return "Sit normally, look at the display, then tap Calibrate. That pose becomes center."
        case .practiceLeft:
            return "Turn left — that side should soft-veil."
        case .practiceRight:
            return "Turn right — that side should soft-veil."
        case .practiceDown:
            return "Tilt your chin down — the screen should soft-dim."
        case .practiceUp:
            return "Look up — full cover stays until you tap Done or clear panic with ⌘⇧B."
        case .done:
            return "Calibration complete. Left/right veil, look-down dim, look-up panic are ready."
        }
    }
}

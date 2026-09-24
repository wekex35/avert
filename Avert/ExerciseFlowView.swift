import SwiftUI

/// Three compound moves: center → A → center → B → center, counted via AirPods.
struct ExerciseFlowView: View {
    @Bindable var model: AppModel

    private var exercises: [NeckExercise] { NeckExercise.catalog }
    private var stepIndex: Int { model.exerciseStepIndex }
    private var current: NeckExercise { exercises[min(stepIndex, exercises.count - 1)] }
    private var reps: Int { model.exerciseReps }
    private var setComplete: Bool { model.exerciseSetComplete }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 20)

            HStack(alignment: .top, spacing: 28) {
                phaseImage
                    .frame(width: 248, height: 248)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                coachingColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()
                .padding(.top, 24)
                .padding(.bottom, 16)

            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 680, height: 500)
        .transaction { $0.animation = nil }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Neck mobility")
                    .font(.title2.weight(.semibold))
                Text(current.title)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text("\(stepIndex + 1)/\(exercises.count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }

    private var coachingColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.exercisePhaseTitle)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .padding(.bottom, 8)

            Text(model.exerciseCoachHint)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .topLeading)
                .padding(.bottom, 16)

            Text(model.exerciseHoldSecondsDisplay > 0 ? "\(model.exerciseHoldSecondsDisplay)" : " ")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.primary.opacity(model.exerciseHoldSecondsDisplay > 0 ? 1 : 0))
                .frame(height: 64, alignment: .leading)
                .padding(.bottom, 12)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(min(reps, current.targetReps))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/ \(current.targetReps)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            ProgressView(
                value: Double(min(reps, current.targetReps)),
                total: Double(current.targetReps)
            )
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                halfChip("1", active: model.exerciseHalf == .first)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                halfChip("2", active: model.exerciseHalf == .second)
                Spacer(minLength: 8)
                Text(trackingLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                Button("Skip") {
                    model.skipExerciseMove()
                }
                .controlSize(.large)
                .disabled(setComplete)

                Spacer(minLength: 8)

                if setComplete {
                    Button("Done") {
                        model.finishExerciseSession(completed: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else if reps >= current.targetReps {
                    Button("Next") {
                        model.advanceExerciseMove()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 16) {
            Button("Not now") {
                model.finishExerciseSession(completed: false)
            }
            .keyboardShortcut(.cancelAction)

            Spacer(minLength: 12)

            Text("Slow · no bounce · stop if pain")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var trackingLine: String {
        let angle = String(format: "%+.0f°", model.exerciseAxisDegrees)
        let ear = model.activeEar == .unknown ? "—" : model.activeEar.shortTitle
        return "\(ear) \(angle)"
    }

    private func halfChip(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .frame(width: 22, height: 22)
            .background(
                Circle().fill(active ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
            )
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
    }

    @ViewBuilder
    private var phaseImage: some View {
        let name = model.exercisePhaseImageName
        if let image = NeckExercise.image(named: name) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .id(name)
        } else {
            ZStack {
                Color.primary.opacity(0.06)
                Image(systemName: "figure.cooldown")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

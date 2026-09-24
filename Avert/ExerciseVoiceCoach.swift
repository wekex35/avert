import AppKit
import AVFoundation
import Foundation

/// Voice locked to the current image/phase. Phase changes cut the queue so speech
/// never lags behind the on-screen cue; countdown digits match the big timer.
@MainActor
final class ExerciseVoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pendingAfterStop: String?
    private var isStopping = false
    private var lastPhaseID: String?
    private var lastCountdownSpoken: Int?

    var isEnabled = true

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func reset() {
        lastPhaseID = nil
        lastCountdownSpoken = nil
        pendingAfterStop = nil
        isStopping = false
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func stop() {
        pendingAfterStop = nil
        isStopping = false
        lastCountdownSpoken = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Speak when the visible phase/image changes. Replaces any in-flight speech.
    func announcePhase(id: String, prompt: String) {
        guard isEnabled else { return }
        guard id != lastPhaseID else { return }
        lastPhaseID = id
        lastCountdownSpoken = nil

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        playSoftChime()
        speakReplacing(trimmed)
    }

    /// Speak 3 / 2 / 1 in lockstep with the on-screen hold timer.
    func announceCountdown(displaySeconds: Int) {
        guard isEnabled else { return }
        guard (1...3).contains(displaySeconds) else { return }
        guard displaySeconds != lastCountdownSpoken else { return }
        lastCountdownSpoken = displaySeconds
        speakReplacing("\(displaySeconds)")
    }

    func announceRepComplete(_ rep: Int, target: Int) {
        guard isEnabled else { return }
        playSoftChime()
        if rep >= target {
            speakReplacing("Set complete.")
        } else {
            speakReplacing("Rep \(rep) done.")
        }
    }

    func announceSessionComplete() {
        guard isEnabled else { return }
        speakReplacing("Nice work. Neck set finished.")
    }

    private func speakReplacing(_ text: String) {
        pendingAfterStop = nil
        if synthesizer.isSpeaking {
            isStopping = true
            pendingAfterStop = text
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        speakNow(text)
    }

    private func speakNow(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.05
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    private func playSoftChime() {
        if let sound = NSSound(named: NSSound.Name("Tink")) ?? NSSound(named: NSSound.Name("Pop")) {
            sound.volume = 0.35
            sound.play()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isStopping = false
            if let next = self.pendingAfterStop {
                self.pendingAfterStop = nil
                self.speakNow(next)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isStopping = false
            if let next = self.pendingAfterStop {
                self.pendingAfterStop = nil
                self.speakNow(next)
            }
        }
    }
}

import AVFoundation
import Foundation

/// Spoken coaching using the on-device voices (no network). Ducks music while speaking and
/// still speaks when the ringer switch is on silent.
final class VoiceCoach: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    struct Accent: Identifiable {
        let code: String
        let label: String
        var id: String { code }
    }

    static let accents = [
        Accent(code: "en-IN", label: "English (India)"),
        Accent(code: "en-GB", label: "English (UK)"),
        Accent(code: "en-US", label: "English (US)"),
        Accent(code: "en-AU", label: "English (Australia)"),
    ]

    @Published private(set) var isSpeaking = false
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "voiceEnabled")
            if !enabled { stop() }
        }
    }
    @Published var accent: String {
        didSet { UserDefaults.standard.set(accent, forKey: "voiceAccent") }
    }

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        enabled = UserDefaults.standard.object(forKey: "voiceEnabled") as? Bool ?? true
        accent = UserDefaults.standard.string(forKey: "voiceAccent") ?? "en-IN"
        super.init()
        synthesizer.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
    }

    /// Queue `text`. With `interrupt`, anything still being said is dropped first.
    func say(_ text: String, interrupt: Bool = false) {
        guard enabled, !text.isEmpty else { return }
        if interrupt { synthesizer.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.98
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// The best-quality voice for the accent, preferring one that matches the coach on screen.
    private func bestVoice() -> AVSpeechSynthesisVoice? {
        let wanted: AVSpeechSynthesisVoiceGender = CoachLook.current == .male ? .male : .female
        let matches = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == accent }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int { v.quality.rawValue * 2 + (v.gender == wanted ? 1 : 0) }
        return matches.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: accent)
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishIfIdle()
    }

    private func finishIfIdle() {
        DispatchQueue.main.async {
            guard !self.synthesizer.isSpeaking else { return }
            self.isSpeaking = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

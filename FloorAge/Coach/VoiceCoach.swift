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
        Accent(code: String(localized: "en-IN"), label: String(localized: "English (India)")),
        Accent(code: String(localized: "en-GB"), label: String(localized: "English (UK)")),
        Accent(code: String(localized: "en-US"), label: String(localized: "English (US)")),
        Accent(code: String(localized: "en-AU"), label: String(localized: "English (Australia)")),
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
        accent = UserDefaults.standard.string(forKey: "voiceAccent") ?? Region.defaultAccent
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

    /// The app's language: "en", "hi" or "es".
    static var appLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// The voice language: the chosen English accent, or Hindi or Spanish when the app is in them.
    var voiceLanguage: String {
        switch Self.appLanguage {
        case "hi": return "hi-IN"
        case "es":
            let latinAmerica: Set<String> = ["MX", "AR", "CO", "CL", "PE", "VE", "EC", "GT", "CU", "BO", "DO", "HN", "PY", "SV", "NI", "CR", "PA", "UY", "PR"]
            if Region.code == "US" { return "es-US" }
            return latinAmerica.contains(Region.code) ? "es-MX" : "es-ES"
        default: return accent
        }
    }

    /// The best-quality voice for the language, preferring one that matches the coach on screen.
    private func bestVoice() -> AVSpeechSynthesisVoice? {
        let wanted: AVSpeechSynthesisVoiceGender = CoachLook.current == .male ? .male : .female
        let language = voiceLanguage
        let matches = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int { v.quality.rawValue * 2 + (v.gender == wanted ? 1 : 0) }
        return matches.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: language)
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

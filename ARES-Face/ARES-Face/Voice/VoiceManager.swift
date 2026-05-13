import AppKit
import AVFoundation

/// Voice manager — microphone input via NSSpeechRecognizer, output via AVSpeechSynthesizer.
/// macOS-native: no third-party dependencies.
@MainActor
class VoiceManager: NSObject, ObservableObject, NSSpeechRecognizerDelegate {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var permissionGranted = false

    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = NSSpeechRecognizer()

    override init() {
        super.init()
        // macOS gate is per-app mic permission, checked at first use
        permissionGranted = true
        recognizer?.delegate = self
        recognizer?.commands = nil // free-form dictation
        recognizer?.listensInForegroundOnly = false
    }

    func startListening() {
        guard !isListening else { return }
        isListening = true
        transcript = ""
        recognizer?.startListening()
        print("[VoiceManager] Listening started (NSSpeechRecognizer)")
    }

    func stopListening() {
        isListening = false
        recognizer?.stopListening()
        print("[VoiceManager] Listening stopped, transcript: \(transcript)")
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    // MARK: - NSSpeechRecognizerDelegate

    nonisolated func speechRecognizer(_ sender: NSSpeechRecognizer, didRecognizeCommand command: String) {
        Task { @MainActor in
            self.transcript = command
            self.isListening = false
        }
    }
}

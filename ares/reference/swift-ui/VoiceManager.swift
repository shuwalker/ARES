import AppKit
import AVFoundation

// ─── Voice Manager (macOS native) ──────────────────

@MainActor
class VoiceManager: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var permissionGranted = false
    
    // macOS uses NSSpeechRecognizer (AppKit), not SFSpeechRecognizer (iOS)
    private let recognizer = NSSpeechRecognizer()!
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        recognizer.delegate = self
        recognizer.commands = nil // Free-form recognition
        permissionGranted = true  // macOS gate is per-app mic permission, checked at first use
    }
    
    func startListening() {
        guard !isListening else { return }
        recognizer.startListening()
        isListening = true
        transcript = ""
    }
    
    func stopListening() {
        recognizer.stopListening()
        isListening = false
    }
    
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }
}

extension VoiceManager: NSSpeechRecognizerDelegate {
    func speechRecognizer(_ sender: NSSpeechRecognizer, didRecognizeCommand command: String) {
        transcript = command
        stopListening()
    }
}

import Foundation

/// Thin observable wrapper around `VoiceAdapter`.
///
/// The rest of the app talks to `VoiceManager` (it owns the adapter and exposes
/// `@Published` state for SwiftUI). TTS feedback to the brain is wired in the
/// view layer (`ARESRootView.onChange` of `isSpeaking`).
@MainActor
final class VoiceManager: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var audioLevel: Float = 0.0
    @Published var isSpeaking = false
    @Published var permissionGranted = false

    private let adapter: VoiceAdapter
    
    /// Queue of text segments waiting to be spoken (FIFO).
    private var speechQueue: [String] = []
    private var isProcessingQueue = false

    init(adapter: VoiceAdapter = MCPVoiceAdapter()) {
        self.adapter = adapter
        super.init()
        
        adapter.onTranscript = { [weak self] text in
            guard let self else { return }
            self.transcript = text
            self.isListening = false
            print("[VoiceManager] Transcript received: \(text)")
        }
        
        adapter.onSpeakingStateChange = { [weak self] speaking in
            guard let self else { return }
            self.isSpeaking = speaking
            print("[VoiceManager] Speaking state: \(speaking)")
        }
        
        adapter.onAudioLevelChange = { [weak self] level in
            guard let self else { return }
            self.audioLevel = level
        }
        
        // macOS mic permission isn't gated for AVAudioRecorder; we assume granted.
        permissionGranted = true
    }

    // MARK: - Listening

    func startListening() {
        guard !isListening else { return }
        isListening = true
        transcript = ""
        Task { await adapter.startListening() }
        print("[VoiceManager] Listening started")
    }

    func stopListening() {
        isListening = false
        adapter.stopListening()
        print("[VoiceManager] Listening stopped")
    }

    func toggleListening() {
        if isListening { stopListening() } else { startListening() }
    }

    // MARK: - Speech Queue

    /// Add text to the speech queue and begin processing if idle.
    func speak(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        speechQueue.append(clean)
        Task { await processQueue() }
    }

    /// Insert at the front of the queue (interruptive — not used by default).
    func speakImmediately(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        speechQueue.insert(clean, at: 0)
        Task { await processQueue() }
    }

    /// Cancel all pending speech and stop current playback.
    func stopSpeaking() {
        speechQueue.removeAll()
        adapter.stopListening()
        isSpeaking = false
    }

    /// Drain the FIFO speech queue, one utterance at a time.
    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        while !speechQueue.isEmpty {
            let text = speechQueue.removeFirst()
            await adapter.speak(text)
        }
    }
}

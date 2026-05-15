import Foundation
import AVFAudio

/// Voice adapter that connects to the Voice MCP server at localhost:9513.
///
/// STT: WebSocket stream — connect, send audio chunks, receive `transcript` events.
/// TTS: HTTP POST /tts/speak — returns audio data, played via AVAudioPlayer.
/// Audio level: real mic input via AVAudioRecorder metering, or simulated fallback.
///
/// If the server is unreachable, WebSocket auto-retries silently and TTS falls
/// back to AVSpeechSynthesizer so the UI never locks up.
@MainActor
final class MCPVoiceAdapter: NSObject, VoiceAdapter {
    // ── Config ──
    private let wsURL = URL(string: "ws://localhost:9513/ws")!
    private let ttsURL = URL(string: "http://localhost:9513/tts/speak")!
    
    // ── Callbacks ──
    var onTranscript: ((String) -> Void)?
    var onSpeakingStateChange: ((Bool) -> Void)?
    var onAudioLevelChange: ((Float) -> Void)?
    
    // ── Internal ──
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var isListening = false
    private var tmpRecordURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ares_level.raw")
    }
    
    /// Retains the speech delegate so ARC doesn't drop it mid-speech
    private var speechDelegate: NSObject?
    
    /// Strong reference to fallback synthesizer so ARC doesn't drop it mid-speech
    private var fallbackSynthesizer: AVSpeechSynthesizer?
    
    /// Key for objc_setAssociatedObject to retain the speech delegate
    private static var ttsDelegateKey: UInt8 = 0
    
    /// Stored task for audio level monitoring so it can be cancelled immediately
    private var audioLevelTask: Task<Void, Never>?
    private var simulatedLevelTask: Task<Void, Never>?
    
    // MARK: - VoiceAdapter conformance
    
    func startListening() async {
        guard !isListening else { return }
        isListening = true
        
        startAudioLevelMonitoring()
        connectWebSocket()
    }
    
    func stopListening() {
        isListening = false
        stopAudioLevelMonitoring()
        disconnectWebSocket()
    }
    
    func speak(_ text: String) async {
        guard !text.isEmpty else { return }
        
        onSpeakingStateChange?(true)
        defer { onSpeakingStateChange?(false) }
        
        do {
            let audioData = try await fetchTTS(text: text)
            try await playAudio(data: audioData)
        } catch {
            print("[MCPVoiceAdapter] TTS failed (\(error)). Fallback to system speech.")
            await speakFallback(text)
        }
    }
    
    // MARK: - WebSocket STT
    
    private func connectWebSocket() {
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 5
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveNext()
    }
    
    private func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    private func receiveNext() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                switch result {
                case .success(let message):
                    self.handleWebSocketMessage(message)
                    self.receiveNext()
                case .failure(let error):
                    print("[MCPVoiceAdapter] WS error: \(error.localizedDescription)")
                    self.scheduleReconnect()
                }
            }
        }
    }
    
    private func scheduleReconnect() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard self.isListening else { return }
            self.connectWebSocket()
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        
        if let transcript = json["transcript"] as? String ?? json["text"] as? String {
            onTranscript?(transcript)
        }
        
        if json["type"] as? String == "audio_level",
           let level = json["level"] as? Double {
            let normalized = Float(max(0, min(1, level)))
            onAudioLevelChange?(normalized)
        }
    }
    
    // MARK: - Audio Level (mic monitoring)
    
    private func startAudioLevelMonitoring() {
        audioLevelTask = Task { @MainActor in
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            let recorder: AVAudioRecorder?
            do {
                recorder = try AVAudioRecorder(url: tmpRecordURL, settings: settings)
                recorder?.isMeteringEnabled = true
                recorder?.record()
            } catch {
                print("[MCPVoiceAdapter] Mic monitoring failed: \(error). Using simulated levels.")
                startSimulatedLevels()
                return
            }
            audioRecorder = recorder

            while self.isListening {
                do {
                    try Task.checkCancellation()
                } catch {
                    break
                }
                recorder?.updateMeters()
                let level = recorder?.averagePower(forChannel: 0) ?? -160
                let normalized = max(0, min(1, (level + 60) / 60))
                self.onAudioLevelChange?(Float(normalized))
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func startSimulatedLevels() {
        simulatedLevelTask = Task { @MainActor in
            while self.isListening {
                do {
                    try Task.checkCancellation()
                } catch {
                    break
                }
                let noise = Float.random(in: -0.05...0.05)
                let level: Float = self.isListening ? max(0, min(1, 0.25 + noise)) : 0
                self.onAudioLevelChange?(level)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
    
    private func stopAudioLevelMonitoring() {
        audioLevelTask?.cancel()
        audioLevelTask = nil
        simulatedLevelTask?.cancel()
        simulatedLevelTask = nil
        audioRecorder?.stop()
        audioRecorder = nil
        onAudioLevelChange?(0.0)
        try? FileManager.default.removeItem(at: tmpRecordURL)
    }
    
    // MARK: - TTS
    
    private func fetchTTS(text: String) async throws -> Data {
        let payload: [String: Any] = ["text": text]
        var request = URLRequest(url: ttsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
    
    private func playAudio(data: Data) async throws {
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
        
        // Hold the task until playback finishes
        while let player = audioPlayer, player.isPlaying {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    
    private func speakFallback(_ text: String) async {
        let synthesizer = AVSpeechSynthesizer()
        fallbackSynthesizer = synthesizer
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        
        // Use a continuation that captures references weakly to avoid Sendable violations
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let delegate = SpeechSynthesizerDelegate { [weak self] in
                Task { @MainActor in
                    self?.fallbackSynthesizer?.delegate = nil
                    self?.fallbackSynthesizer = nil
                }
                continuation.resume()
            }
            synthesizer.delegate = delegate
            speechDelegate = delegate
            synthesizer.speak(utterance)
        }
    }
}

// MARK: - Delegate for system TTS completion

private final class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onComplete: @Sendable () -> Void
    init(_ onComplete: @escaping @Sendable () -> Void) { self.onComplete = onComplete }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                          didFinish utterance: AVSpeechUtterance) {
        onComplete()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                          didCancel utterance: AVSpeechUtterance) {
        onComplete()
    }
}

// MARK: - Voice Pipeline
// Speech-to-Speech pipeline: VAD → STT → LLM → TTS
// Ported from AIAvatarKit's STS pipeline architecture.
// Modular providers for each stage, async streaming throughout.

import Foundation
import AVFoundation
import Speech

// MARK: - Pipeline Models

/// Request through the voice pipeline
public struct VoiceRequest: Sendable {
    public let sessionId: String
    public let userId: String?
    public let text: String?
    public let audioData: Data?
    public let audioDuration: TimeInterval
    public let channel: String?
    public let metadata: [String: String]

    public init(sessionId: String, userId: String? = nil, text: String? = nil,
                audioData: Data? = nil, audioDuration: TimeInterval = 0,
                channel: String? = nil, metadata: [String: String] = [:]) {
        self.sessionId = sessionId
        self.userId = userId
        self.text = text
        self.audioData = audioData
        self.audioDuration = audioDuration
        self.channel = channel
        self.metadata = metadata
    }
}

/// Response from the voice pipeline
public struct VoiceResponse: Sendable {
    public let type: ResponseType
    public let sessionId: String
    public let text: String?
    public let voiceText: String?
    public let audioData: Data?
    public let language: String?
    public let metadata: [String: String]?

    public enum ResponseType: String, Sendable {
        case partial, final, error, toolCall
    }
}

// MARK: - VAD (Voice Activity Detection)

/// VAD provider protocol
public protocol VADProvider: AnyObject, Sendable {
    /// Process audio samples and return whether speech is detected
    func detectSpeech(samples: [Float], sampleRate: Double) -> Bool
    /// Get the current speech state
    var isSpeaking: Bool { get }
    /// Reset VAD state
    func reset()
}

/// Standard silence-based VAD
public final class StandardVAD: VADProvider, @unchecked Sendable {
    public private(set) var isSpeaking: Bool = false
    private let volumeThreshold: Float
    private let silenceDuration: TimeInterval
    private var lastSpeechTime: Date = .distantPast

    public init(volumeThreshold: Float = -30.0, silenceDuration: TimeInterval = 0.5) {
        self.volumeThreshold = volumeThreshold
        self.silenceDuration = silenceDuration
    }

    public func detectSpeech(samples: [Float], sampleRate: Double) -> Bool {
        guard !samples.isEmpty else { return false }

        var sum: Float = 0
        for sample in samples {
            sum += abs(sample)
        }

        let average = sum / Float(samples.count)
        let db = 20 * log10(max(average, 0.0001))

        if db > volumeThreshold {
            isSpeaking = true
            lastSpeechTime = Date()
        } else if Date().timeIntervalSince(lastSpeechTime) > silenceDuration {
            isSpeaking = false
        }

        return isSpeaking
    }

    public func reset() {
        isSpeaking = false
        lastSpeechTime = .distantPast
    }
}

// MARK: - STT (Speech to Text)

/// STT provider protocol
public protocol STTProvider: AnyObject, Sendable {
    /// Transcribe audio data to text
    func transcribe(audioData: Data, sampleRate: Int) async throws -> String
    /// Stream transcription (for real-time)
    func streamTranscribe() -> AsyncThrowingStream<String, Error>
}

/// Local STT using macOS Speech framework (SFSpeechRecognizer)
public final class LocalSTT: STTProvider, @unchecked Sendable {
    private let locale: Locale
    private let speechRecognizer: SFSpeechRecognizer?

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    public func transcribe(audioData: Data, sampleRate: Int) async throws -> String {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw VoicePipelineError.sttError("Speech recognizer not available for \(locale.identifier)")
        }

        // Convert raw PCM data into AVAudioPCMBuffer (float32 — what SFSpeech expects)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: Double(sampleRate),
                                    channels: 1, interleaved: false)!
        let frameCount = audioData.count / 2  // 16-bit input = 2 bytes per sample
        guard frameCount > 0 else {
            throw VoicePipelineError.sttError("Empty audio data")
        }

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        audioData.withUnsafeBytes { rawBuffer in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress!
            let floatChannel = buffer.floatChannelData![0]
            for i in 0..<frameCount {
                floatChannel[i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
            request.append(buffer)
            request.endAudio()
            // Stash task to prevent early deallocation
            objc_setAssociatedObject(self, &Self.taskKey, task, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    public func streamTranscribe() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: VoicePipelineError.notImplemented("Streaming STT requires live audio tap — use processStreaming on VoicePipeline"))
        }
    }

    nonisolated(unsafe) private static var taskKey: UInt8 = 0
}

// MARK: - LLM Service

/// LLM service for the voice pipeline
public protocol VoiceLLMProvider: AnyObject, Sendable {
    /// Send text to LLM and get response
    func complete(text: String, systemPrompt: String?, sessionId: String) async throws -> String
    /// Stream response from LLM
    func streamComplete(text: String, systemPrompt: String?, sessionId: String) -> AsyncThrowingStream<String, Error>
}

/// Default LLM provider using Hermes-compatible API
public final class DefaultVoiceLLM: VoiceLLMProvider, @unchecked Sendable {
    private let baseURL: String
    private let model: String
    private let apiKey: String

    public init(baseURL: String = "http://localhost:11434", model: String = "gemma4:e4b-mlx", apiKey: String = "") {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    public func complete(text: String, systemPrompt: String?, sessionId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 60

        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VoicePipelineError.llmError("HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
        }

        struct LLMResponse: Codable {
            let choices: [Choice]
            struct Choice: Codable { let message: Message }
            struct Message: Codable { let content: String? }
        }

        let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    public func streamComplete(text: String, systemPrompt: String?, sessionId: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await complete(text: text, systemPrompt: systemPrompt, sessionId: sessionId)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - TTS (Text to Speech)

/// TTS provider protocol
public protocol TTSProvider: AnyObject, Sendable {
    /// Synthesize text to audio data
    func synthesize(text: String, voice: String?) async throws -> Data
    /// Stream synthesized audio
    func streamSynthesize(text: String, voice: String?) -> AsyncThrowingStream<Data, Error>
}

/// Local TTS using macOS AVSpeechSynthesizer
/// Writes synthesized speech to a temporary AIFF file, reads it back as Data.
public final class LocalTTS: TTSProvider, @unchecked Sendable {
    private let synthesizer: AVSpeechSynthesizer
    private let defaultVoice: AVSpeechSynthesisVoice?

    public init(voiceIdentifier: String? = nil) {
        self.synthesizer = AVSpeechSynthesizer()
        if let identifier = voiceIdentifier {
            self.defaultVoice = AVSpeechSynthesisVoice(identifier: identifier)
        } else {
            self.defaultVoice = AVSpeechSynthesisVoice(language: "en-US")
        }
    }

    public func synthesize(text: String, voice: String? = nil) async throws -> Data {
        let utterance = AVSpeechUtterance(string: text)
        if let voiceId = voice, let v = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = v
        } else {
            utterance.voice = defaultVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        // Write to a temporary AIFF file, then read back
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ares_tts_\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Set up a delegate to know when synthesis finishes
            let delegate = TTSDelegate()
            delegate.onFinish = { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            // Hold delegate via associated object
            objc_setAssociatedObject(self, &Self.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)

            // AVSpeechSynthesizer doesn't write to file directly.
            // Use AVAudioFile + AVAudioEngine tap approach:
            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)

            let audioFile = try? AVAudioFile(forWriting: tempURL, settings: format.settings)
            let savedFileRef = audioFile
            _ = savedFileRef  // retain

            // Install tap on mixer to capture synthesized audio
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                try? savedFileRef?.write(from: buffer)
            }

            do {
                try engine.start()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Schedule the utterance through the engine's player node
            delegate.onFinish = { error in
                engine.mainMixerNode.removeTap(onBus: 0)
                engine.stop()
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }

            synthesizer.delegate = delegate
            synthesizer.speak(utterance)
        }

        return try Data(contentsOf: tempURL)
    }

    public func streamSynthesize(text: String, voice: String? = nil) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await synthesize(text: text, voice: voice)
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    nonisolated(unsafe) private static var delegateKey: UInt8 = 0
}

/// Delegate for AVSpeechSynthesizer completion
private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinish: ((Error?) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?(nil)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish?(VoicePipelineError.ttsError("Speech synthesis cancelled"))
    }
}

// MARK: - Pipeline Orchestrator

/// The main voice pipeline — VAD → STT → LLM → TTS
public actor VoicePipeline {
    public let vad: VADProvider
    public let stt: STTProvider
    public let llm: VoiceLLMProvider
    public let tts: TTSProvider

    private var isRunning: Bool = false
    private var currentSessionId: String?
    private let systemPrompt: String?

    public init(vad: VADProvider = StandardVAD(),
                stt: STTProvider = LocalSTT(),
                llm: VoiceLLMProvider = DefaultVoiceLLM(),
                tts: TTSProvider = LocalTTS(),
                systemPrompt: String? = nil) {
        self.vad = vad
        self.stt = stt
        self.llm = llm
        self.tts = tts
        self.systemPrompt = systemPrompt
    }

    /// Process a voice request through the full pipeline
    public func process(request: VoiceRequest) async throws -> VoiceResponse {
        let sessionId = request.sessionId
        currentSessionId = sessionId

        // 1. If we have audio, transcribe it
        var text = request.text
        if text == nil, let audioData = request.audioData {
            text = try await stt.transcribe(audioData: audioData, sampleRate: 16000)
        }

        guard let inputText = text, !inputText.isEmpty else {
            return VoiceResponse(type: .error, sessionId: sessionId, text: nil, voiceText: nil, audioData: nil, language: nil, metadata: ["error": "No input text or audio"])
        }

        // 2. Send to LLM
        let llmResponse = try await llm.complete(text: inputText, systemPrompt: systemPrompt, sessionId: sessionId)

        // 3. Synthesize speech
        let audioData = try await tts.synthesize(text: llmResponse, voice: nil)

        return VoiceResponse(
            type: .final,
            sessionId: sessionId,
            text: llmResponse,
            voiceText: llmResponse,
            audioData: audioData,
            language: "en",
            metadata: nil
        )
    }

    /// Process streaming — real-time VAD → STT → LLM → TTS
    public func processStreaming(audioStream: AsyncStream<[Float]>) -> AsyncThrowingStream<VoiceResponse, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var accumulatedText = ""

                for await buffer in audioStream {
                    // VAD
                    let hasSpeech = vad.detectSpeech(samples: buffer, sampleRate: 16000)

                    if hasSpeech {
                        // In a real implementation, accumulate audio and periodically
                        // send to STT for transcription
                        continuation.yield(VoiceResponse(
                            type: .partial,
                            sessionId: currentSessionId ?? "streaming",
                            text: "Listening...",
                            voiceText: nil,
                            audioData: nil,
                            language: nil,
                            metadata: nil
                        ))
                    }
                }

                continuation.finish()
            }
        }
    }

    /// Start the pipeline (continuous listening mode)
    public func start() {
        isRunning = true
    }

    /// Stop the pipeline
    public func stop() {
        isRunning = false
        vad.reset()
    }

    public var isActive: Bool { isRunning }
}

// MARK: - Audio Capture

/// Audio capture from microphone
public actor AudioCapture {
    private let audioEngine: AVAudioEngine
    private let inputNode: AVAudioInputNode
    private var isCapturing: Bool = false

    public init() {
        self.audioEngine = AVAudioEngine()
        self.inputNode = audioEngine.inputNode
    }

    /// Start capturing audio and return a stream of float channel data
    public func startCapture() -> AsyncStream<[Float]> {
        AsyncStream { continuation in
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = Int(buffer.frameLength)
                var samples = [Float](repeating: 0, count: frameLength)
                for i in 0..<frameLength {
                    samples[i] = channelData[0][i]
                }
                continuation.yield(samples)
            }

            do {
                try audioEngine.start()
                isCapturing = true
            } catch {
                continuation.finish()
            }
        }
    }

    /// Stop capturing audio
    public func stopCapture() {
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        isCapturing = false
    }

    public var isActive: Bool { isCapturing }
}

// MARK: - Errors

public enum VoicePipelineError: LocalizedError {
    case notImplemented(String)
    case llmError(String)
    case sttError(String)
    case ttsError(String)
    case audioError(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let detail): return "Not implemented: \(detail)"
        case .llmError(let detail): return "LLM error: \(detail)"
        case .sttError(let detail): return "STT error: \(detail)"
        case .ttsError(let detail): return "TTS error: \(detail)"
        case .audioError(let detail): return "Audio error: \(detail)"
        }
    }
}

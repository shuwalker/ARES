import Foundation
import AVFoundation
import Speech
import ARESCore

final class SystemVoiceEngine: NSObject, VoiceEngine, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var capabilities: Set<String> { ["TTS", "STT"] }

    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionCallback: ((String) -> Void)?
    
    private var synthesisContinuation: CheckedContinuation<ARESCore.AudioBuffer, Error>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Protocol Methods

    func synthesize(text: String, prosody: Prosody) async throws -> ARESCore.AudioBuffer {
        return try await withCheckedThrowingContinuation { continuation in
            let utterance = AVSpeechUtterance(string: text)

            // Map prosody values to AVSpeechUtterance properties
            utterance.rate = Float(prosody.rate * 0.5).clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
            utterance.pitchMultiplier = Float(prosody.pitch / 120.0).clamped(to: 0.5...2.0)
            utterance.volume = Float(prosody.energy).clamped(to: 0.0...1.0)

            self.synthesisContinuation = continuation
            
            // Speak to the speaker
            synthesizer.speak(utterance)
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let cont = synthesisContinuation {
            // The audio was genuinely synthesized and played to the output
            // device by AVSpeechSynthesizer — but it goes straight to the
            // speaker, so no PCM samples are captured. The protocol requires
            // an AudioBuffer return value, so we return an EMPTY buffer
            // (samples: []) meaning "playback complete, no samples captured".
            // Callers needing the raw PCM should use a capture-capable engine.
            cont.resume(returning: ARESCore.AudioBuffer(sampleRate: 44100, channels: 1, samples: []))
            synthesisContinuation = nil
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if let cont = synthesisContinuation {
            cont.resume(returning: ARESCore.AudioBuffer(sampleRate: 44100, channels: 1, samples: []))
            synthesisContinuation = nil
        }
    }

    func recognize(audio: ARESCore.AudioBuffer) async throws -> String {
        // Full-buffer recognition: convert the PCM buffer to AVAudioPCMBuffer
        // and run it through SFSpeechRecognizer in one shot.
        guard !audio.samples.isEmpty else {
            throw VoiceError.emptyAudioBuffer
        }

        // Authorization must be granted before recognition. Deny -> throw,
        // never return placeholder text.
        let authorized = await Self.requestSpeechAuthorization()
        guard authorized else {
            throw VoiceError.speechRecognitionDenied
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }

        let pcmBuffer = try Self.makePCMBuffer(from: audio)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.append(pcmBuffer)
        request.endAudio()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            // The recognition handler can fire multiple times; only resume once.
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                } else if let result = result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - STT Helpers

    /// Resolves speech-recognition authorization, prompting the user if undetermined.
    private static func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    /// Converts the contract's interleaved Float32 AudioBuffer into a
    /// deinterleaved AVAudioPCMBuffer suitable for SFSpeechRecognizer.
    private static func makePCMBuffer(from audio: ARESCore.AudioBuffer) throws -> AVAudioPCMBuffer {
        let channels = max(1, audio.channels)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(audio.sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ) else {
            throw VoiceError.audioFormatFailure
        }

        let frameCount = AVAudioFrameCount(audio.samples.count / channels)
        guard frameCount > 0, let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw VoiceError.audioFormatFailure
        }
        pcmBuffer.frameLength = frameCount

        guard let channelData = pcmBuffer.floatChannelData else {
            throw VoiceError.audioFormatFailure
        }
        // Deinterleave: samples are [L R L R ...] -> per-channel planes.
        for frame in 0..<Int(frameCount) {
            for channel in 0..<channels {
                channelData[channel][frame] = audio.samples[frame * channels + channel]
            }
        }
        return pcmBuffer
    }

    // MARK: - Live Mic Recognition (Used by PerceptionWidget)

    func startLiveRecognition(onResult: @escaping (String) -> Void) throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized {
            try beginLiveCapture(onResult: onResult)
        } else {
            SFSpeechRecognizer.requestAuthorization { newStatus in
                if newStatus == .authorized {
                    try? self.beginLiveCapture(onResult: onResult)
                }
            }
        }
    }

    private func beginLiveCapture(onResult: @escaping (String) -> Void) throws {
        // Initialize audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { throw VoiceError.audioEngineFailure }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { throw VoiceError.recognitionFailure }

        recognitionRequest.shouldReportPartialResults = true

        // Start recognition task
        recognitionCallback = onResult
        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                let bestString = result.bestTranscription.formattedString
                onResult(bestString)
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                self.stopLiveRecognition()
            }
        }

        // Tap the microphone
        // Note: outputFormat(forBus:) returns a non-optional AVAudioFormat in the
        // current SDK. The historical guard-let is preserved as a comment so a
        // future SDK regression to optional still has the right error path.
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        if inputNode.numberOfInputs == 0 {
            throw VoiceError.audioFormatFailure
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        print("✅ [VOICE] Live recognition started")
    }

    func stopLiveRecognition() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        recognitionCallback = nil

        print("✅ [VOICE] Live recognition stopped")
    }

}

// MARK: - Error

enum VoiceError: LocalizedError {
    case audioEngineFailure
    case recognitionFailure
    case audioFormatFailure
    case emptyAudioBuffer
    case speechRecognitionDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .audioEngineFailure:
            return "Failed to initialize audio engine"
        case .recognitionFailure:
            return "Failed to create speech recognition request"
        case .audioFormatFailure:
            return "Failed to get audio format"
        case .emptyAudioBuffer:
            return "Audio buffer is empty"
        case .speechRecognitionDenied:
            return "Speech recognition authorization denied"
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable"
        }
    }
}

// MARK: - Extension: Clamping

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound {
            return range.lowerBound
        } else if self > range.upperBound {
            return range.upperBound
        } else {
            return self
        }
    }
}

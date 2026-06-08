import Foundation
import AVFoundation
import Speech
import ARESCore

final class SystemVoiceEngine: VoiceEngine, @unchecked Sendable {
    var capabilities: Set<String> { ["TTS", "STT"] }

    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionCallback: ((String) -> Void)?

    // MARK: - Protocol Methods

    func synthesize(text: String, prosody: Prosody) async throws -> ARESCore.AudioBuffer {
        let utterance = AVSpeechUtterance(string: text)

        // Map prosody values to AVSpeechUtterance properties
        utterance.rate = Float(prosody.rate * 0.5).clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = Float(prosody.pitch / 120.0).clamped(to: 0.5...2.0)
        utterance.volume = Float(prosody.energy).clamped(to: 0.0...1.0)

        // Speak to the speaker
        synthesizer.speak(utterance)

        // Return a stub buffer (protocol requires AudioBuffer, but we don't need PCM roundtrip for TTS)
        return ARESCore.AudioBuffer(sampleRate: 44100, channels: 1, samples: [])
    }

    func recognize(audio: ARESCore.AudioBuffer) async throws -> String {
        // Full-buffer recognition (used in tests, not in the live mic flow)
        return "[recognition not implemented for buffer mode]"
    }

    // MARK: - Live Mic Recognition (Used by PerceptionWidget)

    func startLiveRecognition(onResult: @escaping (String) -> Void) throws {
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

    var errorDescription: String? {
        switch self {
        case .audioEngineFailure:
            return "Failed to initialize audio engine"
        case .recognitionFailure:
            return "Failed to create speech recognition request"
        case .audioFormatFailure:
            return "Failed to get audio format"
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

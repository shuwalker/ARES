import Foundation

/// No-op VoiceEngine for testing. No actual TTS/STT.
public final class DummyVoiceEngine: VoiceEngine, @unchecked Sendable {
    public nonisolated let capabilities: Set<String> = ["TTS", "STT"]

    public init() {}

    public func synthesize(text: String, prosody: Prosody) async throws -> AudioBuffer {
        print("🤖 [DUMMY] Synthesizing: \(text)")
        let sampleCount = Int(TimeInterval(44100) * 1.0)
        return AudioBuffer(
            sampleRate: 44100,
            channels: 1,
            samples: Array(repeating: 0.0, count: sampleCount)
        )
    }

    public func recognize(audio: AudioBuffer) async throws -> String {
        print("🤖 [DUMMY] Recognizing audio (\(String(format: "%.2f", audio.duration))s)")
        return "[dummy recognized text]"
    }
}

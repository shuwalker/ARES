import Foundation

/// VoiceEngine protocol: TTS, STT, and prosody extraction.
/// Conforming types: KokoroVoiceEngine, SystemVoiceEngine, KokoroLocalEngine
public protocol VoiceEngine: AnyObject, Sendable {
    /// Synthesize text to speech with prosody controls.
    /// Returns an audio buffer ready to play.
    func synthesize(text: String, prosody: Prosody) async throws -> AudioBuffer

    /// Recognize speech from audio buffer.
    /// Returns recognized text.
    func recognize(audio: AudioBuffer) async throws -> String

    /// What can this voice engine do?
    /// Examples: ["TTS", "STT", "prosodyControl", "streaming"]
    var capabilities: Set<String> { get }
}

/// Audio buffer: interleaved samples at known sample rate and channels.
public struct AudioBuffer: Codable, Sendable, Equatable {
    public let sampleRate: Int              // 44100, 48000, etc.
    public let channels: Int                // 1 (mono), 2 (stereo)
    public let samples: [Float]             // Interleaved PCM

    public init(
        sampleRate: Int = 44100,
        channels: Int = 1,
        samples: [Float]
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.samples = samples
    }

    /// Duration in seconds.
    public var duration: TimeInterval {
        TimeInterval(samples.count / channels) / TimeInterval(sampleRate)
    }
}

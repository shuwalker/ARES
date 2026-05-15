import Foundation

/// Abstract interface for speech-to-text and text-to-speech.
///
/// Implementations:
///   - `MCPVoiceAdapter` — talks to the Voice MCP server at :9513 (whisper-cpp + Piper TTS)
///   - `MockVoiceAdapter` — for SwiftUI previews / unit tests
@MainActor
protocol VoiceAdapter: AnyObject {
    /// Begin streaming/listening for speech. Results arrive via `onTranscript`.
    func startListening() async
    
    /// Stop listening and close the WebSocket connection.
    func stopListening()
    
    /// Convert text to speech, queue it, play it, and return when audio finishes.
    func speak(_ text: String) async
    
    /// Called with the finalized transcript text when STT produces it.
    var onTranscript: ((String) -> Void)? { get set }
    
    /// Called when TTS playback starts (true) or stops (false).
    var onSpeakingStateChange: ((Bool) -> Void)? { get set }
    
    /// Called when the mic audio level changes (0.0 = silent, 1.0 = clipping).
    var onAudioLevelChange: ((Float) -> Void)? { get set }
}

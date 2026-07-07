#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Perceiver protocol: defines what sensory inputs are available.
/// Conforming types: PerceptionClient (websocket), LocalPerceptionEngine, DummyPerceiver
public protocol Perceiver: AnyObject, Sendable {
    /// Async stream of face landmarks (468 MediaPipe points or 17 OpenPose).
    /// Landmarks arrive at sensor fps (typically 30 Hz).
    var landmarkStream: AsyncStream<FaceLandmarks> { get }

    /// Async stream of voice prosody (pitch, energy, rate).
    /// Prosody arrives as voice is detected/recorded.
    var prosodyStream: AsyncStream<Prosody> { get }

    /// Capture a single frame from the camera right now.
    /// Used by UI for snapshot or by avatar renderer for blitting.
    func captureFrame() async throws -> CGImage

    /// Start listening for speech (unmute mic, activate STT).
    func startListening() async throws

    /// Stop listening for speech (mute mic, deactivate STT).
    func stopListening() async throws

    /// Is the perceiver currently listening?
    var isListening: Bool { get async }
}

/// Face landmarks: 2D or 3D points + confidence + head rotation.
public struct FaceLandmarks: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let points: [CGPoint]           // 468 for MediaPipe, 17 for OpenPose
    public let confidence: [Double]        // 0...1 per point
    public let headRoll: Double            // radians, rotation around z-axis
    public let headPitch: Double           // radians, rotation around x-axis
    public let headYaw: Double             // radians, rotation around y-axis

    public init(
        timestamp: Date = Date(),
        points: [CGPoint],
        confidence: [Double],
        headRoll: Double = 0,
        headPitch: Double = 0,
        headYaw: Double = 0
    ) {
        self.timestamp = timestamp
        self.points = points
        self.confidence = confidence
        self.headRoll = headRoll
        self.headPitch = headPitch
        self.headYaw = headYaw
    }
}

/// Voice prosody: pitch, energy, rate extracted from audio stream.
public struct Prosody: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let energy: Double              // 0...1, loudness
    public let pitch: Double               // Hz
    public let rate: Double                // 0...1, speech speed relative to normal

    public init(
        timestamp: Date = Date(),
        energy: Double = 0.5,
        pitch: Double = 120,
        rate: Double = 1.0
    ) {
        self.timestamp = timestamp
        self.energy = max(0, min(1, energy))
        self.pitch = max(0, pitch)
        self.rate = max(0, rate)
    }
}

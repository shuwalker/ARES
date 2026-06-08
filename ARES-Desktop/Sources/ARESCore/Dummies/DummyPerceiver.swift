import CoreGraphics
import Foundation

/// No-op Perceiver for testing. Generates synthetic landmarks and prosody.
public final class DummyPerceiver: Perceiver, @unchecked Sendable {
    private var _isListening = false
    private let updateInterval: UInt64 = 33_000_000  // 30 fps

    public init() {}

    public var landmarkStream: AsyncStream<FaceLandmarks> {
        AsyncStream { continuation in
            Task {
                while true {
                    let synthetic = FaceLandmarks(
                        timestamp: Date(),
                        points: (0..<468).map { _ in CGPoint(
                            x: CGFloat.random(in: 0...512),
                            y: CGFloat.random(in: 0...512)
                        )},
                        confidence: (0..<468).map { _ in Double.random(in: 0.8...1.0) },
                        headRoll: Double.random(in: -0.2...0.2),
                        headPitch: Double.random(in: -0.2...0.2),
                        headYaw: Double.random(in: -0.2...0.2)
                    )
                    continuation.yield(synthetic)
                    try? await Task.sleep(nanoseconds: self.updateInterval)
                }
            }
        }
    }

    public var prosodyStream: AsyncStream<Prosody> {
        AsyncStream { continuation in
            Task {
                while true {
                    let synthetic = Prosody(
                        timestamp: Date(),
                        energy: Double.random(in: 0.3...0.8),
                        pitch: Double.random(in: 100...200),
                        rate: Double.random(in: 0.8...1.2)
                    )
                    continuation.yield(synthetic)
                    try? await Task.sleep(nanoseconds: self.updateInterval)
                }
            }
        }
    }

    public func captureFrame() async throws -> CGImage {
        let size = CGSize(width: 512, height: 512)
        let rect = CGRect(origin: .zero, size: size)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: 512 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "DummyPerceiver", code: -1)
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0))
        context.fill(rect)
        guard let image = context.makeImage() else {
            throw NSError(domain: "DummyPerceiver", code: -1)
        }
        return image
    }

    public func startListening() async throws {
        _isListening = true
        print("🤖 [DUMMY] Listening started")
    }

    public func stopListening() async throws {
        _isListening = false
        print("🤖 [DUMMY] Listening stopped")
    }

    public var isListening: Bool {
        get async { _isListening }
    }
}

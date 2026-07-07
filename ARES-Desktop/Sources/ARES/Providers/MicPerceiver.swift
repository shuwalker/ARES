import AVFoundation
import CoreGraphics
import Foundation
import os
import ARESCore

// MARK: - Mic-only Perceiver

/// Microphone-only Perceiver backed by AVAudioEngine.
///
/// Captures live audio from the system input device and publishes real
/// prosody values computed from each tap buffer (energy from RMS). This
/// perceiver has NO camera: the landmark stream finishes immediately and
/// `captureFrame()` throws — honest absence rather than synthetic data.
///
/// Pitch and speech-rate estimation are not implemented; those Prosody
/// fields are filled with documented neutral values (pitch 0 Hz = "not
/// measured", rate 1.0 = "normal").
public final class MicPerceiver: Perceiver, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.ares", category: "MicPerceiver")
    private let lock = NSLock()

    private var audioEngine: AVAudioEngine?
    private var _isListening = false

    /// Active prosody subscribers. Each call to `prosodyStream` registers a
    /// continuation here; tap buffers fan out to all of them.
    private var prosodyContinuations: [UUID: AsyncStream<Prosody>.Continuation] = [:]

    public init() {}

    deinit {
        // Best-effort teardown; finish all subscriber streams.
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        for continuation in prosodyContinuations.values {
            continuation.finish()
        }
    }

    // MARK: - Streams

    /// Mic-only perceivers have no camera, so no face landmarks are ever
    /// produced. The stream finishes immediately — consumers iterating it
    /// fall through cleanly instead of waiting on data that will never come.
    public var landmarkStream: AsyncStream<FaceLandmarks> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    /// Real prosody computed from live mic buffers (energy from RMS).
    /// Values are emitted only while listening; the stream stays open across
    /// start/stop cycles and finishes when the perceiver is deallocated.
    public var prosodyStream: AsyncStream<Prosody> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            prosodyContinuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.prosodyContinuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    // MARK: - Frame Capture

    /// Always throws: this perceiver has no visual sensor.
    public func captureFrame() async throws -> CGImage {
        throw PerceiverError.visualCaptureUnsupported
    }

    // MARK: - Listening Lifecycle

    public func startListening() async throws {
        let alreadyListening = lock.withLock { _isListening }
        if alreadyListening { return }

        // Request mic permission before touching the engine.
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            logger.error("Microphone permission denied")
            throw PerceiverError.microphonePermissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw PerceiverError.audioFormatUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            logger.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        lock.withLock {
            self.audioEngine = engine
            self._isListening = true
        }
        logger.info("Mic listening started (\(format.sampleRate, privacy: .public) Hz)")
    }

    public func stopListening() async throws {
        let engine: AVAudioEngine? = lock.withLock {
            let e = self.audioEngine
            self.audioEngine = nil
            self._isListening = false
            return e
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        logger.info("Mic listening stopped")
    }

    public var isListening: Bool {
        get async { lock.withLock { _isListening } }
    }

    // MARK: - Buffer Processing

    /// Compute RMS energy from a tap buffer and fan a Prosody value out to
    /// all subscribers. Energy is the only field measured here; pitch is
    /// reported as 0 (not measured) and rate as 1.0 (neutral).
    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return }

        let frameCount = Int(buffer.frameLength)
        let samples = channelData[0]
        var sumOfSquares: Float = 0
        for i in 0..<frameCount {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrt(sumOfSquares / Float(frameCount))

        // Speech RMS in float PCM typically sits well below 1.0; apply a
        // modest gain so conversational levels land mid-range, clamped 0...1.
        let energy = min(1.0, Double(rms) * 5.0)

        let prosody = Prosody(
            timestamp: Date(),
            energy: energy,
            pitch: 0,    // pitch tracking not implemented for this perceiver
            rate: 1.0    // speech-rate estimation not implemented; neutral
        )

        let continuations = lock.withLock { Array(prosodyContinuations.values) }
        for continuation in continuations {
            continuation.yield(prosody)
        }
    }
}

// MARK: - Errors

public enum PerceiverError: LocalizedError {
    /// This perceiver has no camera or other visual sensor.
    case visualCaptureUnsupported
    /// The user denied (or has not granted) microphone access.
    case microphonePermissionDenied
    /// The input device reported an unusable audio format.
    case audioFormatUnavailable

    public var errorDescription: String? {
        switch self {
        case .visualCaptureUnsupported:
            return "This perceiver is microphone-only and cannot capture visual frames"
        case .microphonePermissionDenied:
            return "Microphone access was denied — grant it in System Settings → Privacy & Security → Microphone"
        case .audioFormatUnavailable:
            return "The audio input device reported an unusable format (no input device connected?)"
        }
    }
}

// MARK: - NSLock Extension

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

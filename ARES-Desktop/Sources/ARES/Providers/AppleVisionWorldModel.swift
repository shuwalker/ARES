import Foundation
import AVFoundation
import Vision
import CoreGraphics
import ARESCore

final class AppleVisionWorldModel: NSObject, WorldPerception, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var capabilities: Set<String> { ["objectTracking", "faceDetection"] }

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let detectionQueue = DispatchQueue(label: "com.ares.vision.detection")
    
    private var latestState: SceneState = SceneState()
    private var isRunning = false

    override init() {
        super.init()
        setupCamera()
    }

    private func setupCamera() {
        captureSession.sessionPreset = .vga640x480

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("⚠️ [VISION] No front camera found for AppleVisionWorldModel")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: detectionQueue)

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
        } catch {
            print("⚠️ [VISION] Camera setup failed: \(error)")
        }
    }

    private func startIfNeeded() {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
            isRunning = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.global(qos: .background).async {
                        self.captureSession.startRunning()
                    }
                    self.isRunning = true
                }
            }
        default:
            print("⚠️ [VISION] Camera access denied.")
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest { [weak self] req, err in
            guard let self = self, let results = req.results as? [VNFaceObservation], err == nil else { return }
            
            var objects: [SceneObject] = []
            for face in results {
                let obj = SceneObject(
                    kind: "person",
                    label: "user",
                    boundingBox: face.boundingBox,
                    confidence: Double(face.confidence),
                    attributes: [:]
                )
                objects.append(obj)
            }
            
            // If we detect a face, confidence is high. Otherwise, scene is empty.
            self.latestState = SceneState(
                objects: objects,
                relationships: [],
                timestamp: Date(),
                confidence: objects.isEmpty ? 0.0 : 1.0
            )
        }

        // Use orientation appropriate for Mac webcam (mirrored)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("⚠️ [VISION] Vision request failed: \(error)")
        }
    }

    // MARK: - WorldPerception Methods

    func getState() async throws -> SceneState {
        startIfNeeded()
        return latestState
    }

    func updateFromPerception(_ landmarks: FaceLandmarks, _ prosody: Prosody) async throws {
        // Ignored. We run our own background capture.
    }

    func queryObjects(kind: String) async throws -> [SceneObject] {
        startIfNeeded()
        return latestState.objects.filter { $0.kind.lowercased() == kind.lowercased() }
    }

    func getRelationships() async throws -> [SpatialRelationship] {
        return latestState.relationships
    }
}

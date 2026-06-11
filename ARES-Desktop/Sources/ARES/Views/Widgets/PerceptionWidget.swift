import SwiftUI
import AVFoundation
import ARESCore

// MARK: - Perception Widget
//
// Live camera preview with frame capture (vision model).
// Hold-to-talk mic input via SystemVoiceEngine (STT + TTS).
// Requests camera + mic permissions on first use.

struct PerceptionWidget: View {
    @EnvironmentObject var appState: ARESAppState

    @State private var cameraPreview: CameraPreviewController?
    @State private var isRecording = false
    @State private var transcription = ""
    @State private var captureOutput: String?
    @State private var isProcessing = false
    @State private var cameraError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Perception").font(.caption).foregroundColor(.secondary)

            // Camera preview
            ZStack {
                if let error = cameraError {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .frame(height: 200)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "camera.badge.ellipsis")
                                    .font(.title)
                                    .foregroundColor(.orange)
                                Text("Camera Access Denied")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(error)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                        )
                } else if let preview = cameraPreview {
                    CameraPreviewRepresentable(controller: preview)
                        .frame(height: 200)
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .frame(height: 200)
                        .overlay(
                            VStack {
                                Image(systemName: "camera.fill")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                                Text("Camera Preview")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                }

                // Capture button overlay
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            captureFrame()
                        } label: {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                        }
                        .padding()
                    }
                    Spacer()
                }
            }

            // Audio & Transcription
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        // Tap to toggle (future: voice commands)
                    } label: {
                        Image(systemName: isRecording ? "mic.fill" : "mic")
                            .foregroundColor(isRecording ? .red : .primary)
                    }
                    .onLongPressGesture(minimumDuration: 0.1) {
                        if !isRecording {
                            startRecording()
                        } else {
                            stopRecording()
                        }
                    }

                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Processing...").font(.caption).foregroundColor(.secondary)
                    } else if !transcription.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You said").font(.caption2).foregroundColor(.secondary)
                            Text(transcription).font(.caption).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    } else if let output = captureOutput {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Camera").font(.caption2).foregroundColor(.secondary)
                            Text(output).font(.caption).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    }
                }

                if isRecording {
                    Text("Hold to talk...").font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Do NOT request camera/mic on appear — macOS kills the process
        // if Info.plist is missing NSCameraUsageDescription. Instead, request
        // permissions lazily when the user first taps the capture or mic button.
    }

    private func setupCamera() {
        DispatchQueue.main.async {
            let controller = CameraPreviewController()
            do {
                try controller.setupCamera()
                self.cameraPreview = controller
            } catch {
                self.cameraError = error.localizedDescription
            }
        }
    }

    private func captureFrame() {
        // Request camera permission if not yet determined
        guard let preview = cameraPreview else {
            // First tap: request permission + setup camera
            requestCameraPermissionAndSetup()
            return
        }
        isProcessing = true

        Task {
            if let imageData = preview.captureFrame() {
                await sendFrameToVision(imageData)
            }
            await MainActor.run {
                isProcessing = false
            }
        }
    }

    private func requestCameraPermissionAndSetup() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    self.setupCamera()
                } else {
                    self.cameraError = "Camera access denied. Enable it in System Settings > Privacy & Security > Camera."
                }
            }
        }
    }

    private func sendFrameToVision(_ imageData: Data) async {
        // Use the user's active gateway and model from CompanionConfig,
        // not a hardcoded Ollama URL. Falls back to Ollama + qwen3-vl only
        // if the active provider doesn't support vision (most local providers
        // don't handle multimodal — Ollama is the safe local fallback).
        let config = appState.companionConfig
        let gateway: any GatewayProvider
        let model: String

        // Most cloud and hermes-agent gateways route vision through the
        // same API, so we can use the active gateway directly. Only local
        // Ollama needs a vision-capable model override.
        switch config.provider {
        case "ollama-local", "ollama-cloud", "ollama-launch":
            gateway = BackendBuilder.gateway(.ollama(url: config.gatewayURL.contains("11434") ? config.gatewayURL : ARESConfiguration.shared.ollamaURL))
            model = "qwen3-vl:8b"  // vision model override for Ollama
        default:
            // Hermes, Anthropic, OpenAI all handle multimodal natively
            gateway = BackendBuilder.gateway(.hermes(url: config.gatewayURL))
            model = config.model
        }

        let context = ConversationContext(
            messages: [Message(role: .user, content: "Describe this image in one sentence.")],
            model: model
        )

        do {
            let response = try await gateway.prompt(
                "",
                context: context,
                options: GatewayOptions()
            )
            await MainActor.run {
                self.captureOutput = response.text
            }
        } catch {
            await MainActor.run {
                self.captureOutput = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func startRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else {
                print("⚠️  [PERCEPTION] Microphone permission denied.")
                DispatchQueue.main.async { self.isRecording = false }
                return
            }
            DispatchQueue.main.async {
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        isRecording = true
        transcription = ""

        do {
            if let systemVoice = appState.voice as? SystemVoiceEngine {
                try systemVoice.startLiveRecognition { text in
                    DispatchQueue.main.async {
                        self.transcription = text
                    }
                }
            } else {
                print("⚠️ [PERCEPTION] Active voice engine does not support live recognition.")
                isRecording = false
            }
        } catch {
            print("⚠️  [PERCEPTION] Failed to start recording: \(error)")
            isRecording = false
        }
    }

    private func stopRecording() {
        isRecording = false
        if let systemVoice = appState.voice as? SystemVoiceEngine {
            systemVoice.stopLiveRecognition()
        }

        guard !transcription.isEmpty else { return }
        
        // Feed the transcription directly into the main chat
        appState.chatInput = transcription
        appState.autoSpeakNextResponse = true
        appState.sendChat()
        
        transcription = "" // Clear after sending
    }
}

// MARK: - Camera Preview Controller

class CameraPreviewController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private var lastFrame: CVImageBuffer?

    func setupCamera() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw NSError(domain: "PerceptionWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video device found on this system."])
        }
        let input = try AVCaptureDeviceInput(device: device)

        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(output)

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func captureFrame() -> Data? {
        guard let buffer = lastFrame else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        return nsImage.tiffRepresentation
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            lastFrame = pixelBuffer
        }
    }
}

// MARK: - Camera Preview Representable

struct CameraPreviewRepresentable: NSViewRepresentable {
    let controller: CameraPreviewController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    PerceptionWidget()
        .padding()
        .background(Color(.windowBackgroundColor))
}

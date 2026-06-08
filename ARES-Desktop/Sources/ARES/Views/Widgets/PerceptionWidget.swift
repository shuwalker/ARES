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
    @State private var voiceEngine: SystemVoiceEngine?
    @State private var isRecording = false
    @State private var transcription = ""
    @State private var captureOutput: String?
    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Perception").font(.caption).foregroundColor(.secondary)

            // Camera preview
            ZStack {
                if let preview = cameraPreview {
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
        .onAppear {
            requestPermissions()
            setupCamera()
            voiceEngine = SystemVoiceEngine()
        }
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                DispatchQueue.main.async {
                    setupCamera()
                }
            }
        }

        AVAudioApplication.requestRecordPermission { granted in
            // Permission requested
        }
    }

    private func setupCamera() {
        DispatchQueue.main.async {
            let controller = CameraPreviewController()
            controller.setupCamera()
            self.cameraPreview = controller
        }
    }

    private func captureFrame() {
        guard let controller = cameraPreview else { return }
        isProcessing = true

        Task {
            if let imageData = controller.captureFrame() {
                await sendFrameToVision(imageData)
            }
            await MainActor.run {
                isProcessing = false
            }
        }
    }

    private func sendFrameToVision(_ imageData: Data) async {
        let gateway = BackendBuilder.gateway(.ollama(url: "http://localhost:11434"))
        let context = ConversationContext(
            messages: [Message(role: .user, content: "Describe this image in one sentence.")],
            model: "qwen3-vl:8b"
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
        isRecording = true
        transcription = ""
        guard let engine = voiceEngine else { return }

        do {
            try engine.startLiveRecognition { text in
                DispatchQueue.main.async {
                    self.transcription = text
                }
            }
        } catch {
            print("⚠️  [PERCEPTION] Failed to start recording: \(error)")
            isRecording = false
        }
    }

    private func stopRecording() {
        isRecording = false
        guard let engine = voiceEngine else { return }
        engine.stopLiveRecognition()

        guard !transcription.isEmpty else { return }
        sendTranscription(transcription)
    }

    private func sendTranscription(_ text: String) {
        isProcessing = true
        let msg = GatewayMessage(role: "user", content: text)

        Task {
            do {
                let result = try await CompanionChatService.shared.sendMessageStream(
                    messages: [msg],
                    sessionID: nil,
                    onToken: { partial, finished in
                        if finished {
                            // Speak the response
                            let prosody = Prosody(timestamp: Date(), energy: 0.8, pitch: 120, rate: 0.9)
                            Task {
                                do {
                                    _ = try await self.voiceEngine?.synthesize(text: partial, prosody: prosody)
                                } catch {
                                    print("⚠️  [PERCEPTION] TTS error: \(error)")
                                }
                            }
                        }
                    }
                )

                await MainActor.run {
                    isProcessing = false
                    transcription = ""  // Clear transcription after sending
                    print("✅ [PERCEPTION] Chat response received")
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    captureOutput = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Camera Preview Controller

class CameraPreviewController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private var lastFrame: CVImageBuffer?

    func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }

        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(output)

        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
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

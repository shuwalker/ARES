import AVFoundation
import Speech

// MARK: - SpeechRecognitionService

/// Wraps SFSpeechRecognizer and AVAudioEngine to provide live speech-to-text.
/// Must be used from the MainActor; callbacks are delivered on the main actor.
@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - State

    private(set) var isRecording = false

    // Callback invoked with incremental transcription text
    var onTranscriptionUpdate: ((String) -> Void)?

    // Callback invoked when an error prevents recording
    var onRecordingError: ((String) -> Void)?

    // MARK: - Private

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)

    // Timer used to auto-stop after silence
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0

    // Observer token for audio interruptions
    private var interruptionObserver: NSObjectProtocol?

    // MARK: - Authorization

    /// Requests speech recognition authorization.
    /// Returns `true` if authorized.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Recording control

    func startRecording() throws {
        guard !isRecording else { return }

        // Verify permissions before attempting to start
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            let message = "Speech recognition not authorized. Please grant permission in System Settings."
            onRecordingError?(message)
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            let message = "Microphone access not authorized. Please grant permission in System Settings."
            onRecordingError?(message)
            return
        }

        // Reset any previous task
        stopRecording()

        // Register for audio session interruptions.
        // AVAudioSession interruption notifications are iOS/tvOS only;
        // macOS handles audio preemption at the engine level automatically.
        #if os(iOS) || os(tvOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .began {
                Task { @MainActor [weak self] in
                    self?.stopRecording()
                }
            }
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            // Reset silence timer on every audio chunk
            Task { @MainActor [weak self] in
                self?.resetSilenceTimer()
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.onTranscriptionUpdate?(text)
                }
                if error != nil || (result?.isFinal == true) {
                    self.stopRecording()
                }
            }
        }

        isRecording = true
        resetSilenceTimer()
    }

    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
    }

    // MARK: - Silence detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopRecording()
            }
        }
    }
}

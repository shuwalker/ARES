import AVFoundation
import Speech

// MARK: - SpeechRecognitionService

/// Wraps SFSpeechRecognizer and AVAudioEngine to provide live speech-to-text.
/// Must be used from the MainActor; callbacks are delivered on the main actor.
@MainActor
final class SpeechRecognitionService: NSObject, @unchecked Sendable {

    // MARK: - State

    private(set) var isRecording = false

    // Callback invoked with incremental transcription text
    var onTranscriptionUpdate: ((String) -> Void)?

    // MARK: - Private

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)

    // Timer used to auto-stop after silence
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0

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

        // Reset any previous task
        stopRecording()

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

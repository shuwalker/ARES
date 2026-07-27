// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: Copyright (c) 2025 Andrew Wyatt (Fewtarius) & ARES Contributors

import AVFoundation
import Combine
import Logging

/// Text-to-speech service using AVSpeechSynthesizer (modern macOS TTS).
/// Supports streaming TTS by queuing sentences as they arrive.
@MainActor
public class SpeechSynthesisService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published public private(set) var isSpeaking: Bool = false

    private var synthesizer: AVSpeechSynthesizer
    private var currentCompletionHandler: (() -> Void)?
    private let logger = Logger(label: "com.sam.voice.synthesis")

    /// Audio device manager for voice selection
    private var audioDeviceManager: AudioDeviceManager?
    /// Track last applied voice/rate to avoid unnecessary reconfiguration
    private var lastVoiceIdentifier: String?
    private var lastSpeechRate: Float?

    /// Active utterance voice/rate applied on the next speak call
    private var preferredVoiceIdentifier: String?
    private var preferredRateMultiplier: Float = 1.0

    /// Callbacks for TTS lifecycle events
    public var onSpeakingStarted: (() -> Void)?
    public var onSpeakingFinished: (() -> Void)?

    /// Sentence queue for streaming TTS
    private var sentenceQueue: [String] = []
    private var isProcessingQueue = false
    private var streamingCompletionHandler: (() -> Void)?

    public override init() {
        self.synthesizer = AVSpeechSynthesizer()
        super.init()
        self.synthesizer.delegate = self
    }

    /// Set the audio device manager for voice selection
    public func setAudioDeviceManager(_ manager: AudioDeviceManager) {
        self.audioDeviceManager = manager
        logger.debug("AudioDeviceManager configured for speech synthesis")
        updateSynthesizerVoice()
    }

    /// Update preferred voice/rate from the audio device manager
    private func updateSynthesizerVoice() {
        preferredVoiceIdentifier = audioDeviceManager?.selectedVoiceIdentifier
        preferredRateMultiplier = audioDeviceManager?.speechRate ?? 1.0
        logger.info(
            "updateSynthesizerVoice: voiceId=\(preferredVoiceIdentifier ?? "nil"), rate=\(preferredRateMultiplier), hasManager=\(audioDeviceManager != nil)"
        )
    }

    private func makeUtterance(from text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)

        if let voiceId = preferredVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else if let voiceId = preferredVoiceIdentifier {
            // Fall back to language match if the stored identifier is from a
            // previous NSSpeechSynthesizer-era preference.
            let english = AVSpeechSynthesisVoice.speechVoices().first {
                $0.language.hasPrefix("en") && ($0.name.localizedCaseInsensitiveContains(voiceId) || $0.identifier == voiceId)
            }
            utterance.voice = english ?? AVSpeechSynthesisVoice(language: "en-US")
            if english == nil {
                logger.error("Failed to resolve voice: \(voiceId), falling back to system English")
            }
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        // AVSpeechUtterance rate is 0.0...1.0 (default ≈ 0.5). Multiply the
        // default by the user preference multiplier and clamp to a natural range.
        let base = AVSpeechUtteranceDefaultSpeechRate
        let scaled = base * preferredRateMultiplier
        utterance.rate = min(max(scaled, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        return utterance
    }

    /// Speak text aloud with optional completion handler
    public func speak(_ text: String, completion: (() -> Void)? = nil) {
        logger.info("speak() called: isSpeaking=\(isSpeaking), text.count=\(text.count)")

        synthesizer.stopSpeaking(at: .immediate)

        let currentVoice = audioDeviceManager?.selectedVoiceIdentifier
        let currentRate = audioDeviceManager?.speechRate
        if currentVoice != lastVoiceIdentifier || currentRate != lastSpeechRate {
            updateSynthesizerVoice()
            lastVoiceIdentifier = currentVoice
            lastSpeechRate = currentRate
        }

        let cleanText = stripMarkdown(text)
        currentCompletionHandler = completion

        isSpeaking = true
        onSpeakingStarted?()

        synthesizer.speak(makeUtterance(from: cleanText))
        logger.info("Speech started successfully")
    }

    /// Stop speaking immediately
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentCompletionHandler = nil
        sentenceQueue.removeAll()
        isProcessingQueue = false
        streamingCompletionHandler = nil
        isSpeaking = false
    }

    /// Pause speaking
    public func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Resume speaking
    public func resume() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Streaming TTS Methods

    /// Queue a sentence for streaming TTS
    public func queueSentence(_ sentence: String) {
        let cleanText = stripMarkdown(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleanText.isEmpty else { return }

        logger.debug("Queueing sentence for TTS: \(cleanText.prefix(50))...")
        sentenceQueue.append(cleanText)

        if !isProcessingQueue {
            processNextSentence()
        }
    }

    /// Mark streaming as complete — will call completion after queue finishes
    public func finishStreaming(completion: (() -> Void)? = nil) {
        streamingCompletionHandler = completion

        if sentenceQueue.isEmpty && !isSpeaking {
            logger.info("Streaming complete, no sentences pending")
            onSpeakingFinished?()
            streamingCompletionHandler?()
            streamingCompletionHandler = nil
        } else {
            logger.info("Streaming marked complete, \(sentenceQueue.count) sentences pending")
        }
    }

    /// Clear the sentence queue (for cancellation)
    public func clearQueue() {
        sentenceQueue.removeAll()
        streamingCompletionHandler = nil
        logger.debug("Sentence queue cleared")
    }

    /// Check if there are queued sentences
    public var hasQueuedSentences: Bool {
        !sentenceQueue.isEmpty || isSpeaking
    }

    /// Process the next sentence in the queue
    private func processNextSentence() {
        guard !sentenceQueue.isEmpty else {
            isProcessingQueue = false

            if let completion = streamingCompletionHandler {
                logger.info("Queue empty, calling streaming completion")
                onSpeakingFinished?()
                completion()
                streamingCompletionHandler = nil
            }
            return
        }

        isProcessingQueue = true
        let sentence = sentenceQueue.removeFirst()

        logger.debug("Speaking queued sentence: \(sentence.prefix(50))...")

        updateSynthesizerVoice()

        isSpeaking = true
        if sentenceQueue.isEmpty && streamingCompletionHandler == nil {
            onSpeakingStarted?()
        }

        synthesizer.speak(makeUtterance(from: sentence))
    }

    /// Strip markdown formatting for cleaner TTS
    private func stripMarkdown(_ text: String) -> String {
        var cleaned = text

        cleaned = cleaned.replacingOccurrences(of: "```[^`]*```", with: "code block", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "^#+\\s+", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)

        return cleaned
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            logger.info("TTS finished")
            isSpeaking = false

            if !sentenceQueue.isEmpty {
                logger.debug("Processing next queued sentence (\(sentenceQueue.count) remaining)")
                processNextSentence()
            } else if isProcessingQueue {
                logger.info("Sentence queue empty")
                onSpeakingFinished?()
                isProcessingQueue = false

                if let completion = streamingCompletionHandler {
                    logger.info("Executing streaming completion handler")
                    completion()
                    streamingCompletionHandler = nil
                }
            } else {
                onSpeakingFinished?()

                if let completion = currentCompletionHandler {
                    logger.info("Executing completion handler")
                    completion()
                    currentCompletionHandler = nil
                }
            }
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            logger.info("TTS cancelled")
            isSpeaking = false
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        // Available for word highlighting in future
    }
}

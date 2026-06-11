import Foundation

// MARK: - Streaming Throttle
//
/// Buffers streaming text updates and flushes to the UI at a maximum of 30 fps.
/// Prevents SwiftUI from re-rendering on every token arrival while still feeling live.
@MainActor
final class StreamingThrottle {
    private var pending: (bubbleID: UUID, text: String)?
    private var displayed: [UUID: String] = [:]
    private var flushTask: Task<Void, Never>?
    private let onFlush: (UUID, String) -> Void

    init(onFlush: @escaping (UUID, String) -> Void) {
        self.onFlush = onFlush
    }

    /// Enqueue a text update. The throttle simulates human typing cadence
    /// by trickling characters to the UI at variable speeds.
    func enqueue(bubbleID: UUID, text: String) {
        pending = (bubbleID, text)
        if flushTask == nil {
            flushTask = Task { @MainActor in
                while !Task.isCancelled, let next = self.pending {
                    let current = self.displayed[next.bubbleID] ?? ""
                    let target = next.text
                    
                    if current.count < target.count && target.hasPrefix(current) {
                        // Trickle next character
                        let nextCharIndex = target.index(target.startIndex, offsetBy: current.count)
                        let nextChar = target[nextCharIndex]
                        
                        let newDisplayed = current + String(nextChar)
                        self.displayed[next.bubbleID] = newDisplayed
                        self.onFlush(next.bubbleID, newDisplayed)
                        
                        // Simulated typing cadence
                        var delayNanos: UInt64 = 15_000_000 // 15ms base
                        if nextChar.isWhitespace {
                            delayNanos = 30_000_000
                        } else if nextChar.isPunctuation {
                            delayNanos = 120_000_000
                        } else {
                            delayNanos += UInt64.random(in: 0...20_000_000)
                        }
                        
                        try? await Task.sleep(nanoseconds: delayNanos)
                        
                        // Keep trickling if not done and no new pending replaced it
                        if newDisplayed.count < target.count {
                            if self.pending?.text == target {
                                self.pending = (next.bubbleID, target)
                            }
                        } else {
                            // Done
                            if self.pending?.text == target {
                                self.pending = nil
                            }
                        }
                    } else {
                        // Just flush immediately if the prefix doesn't match or it's shorter
                        self.displayed[next.bubbleID] = target
                        self.onFlush(next.bubbleID, target)
                        if self.pending?.text == target {
                            self.pending = nil
                        }
                        try? await Task.sleep(nanoseconds: 16_000_000)
                    }
                }
                self.flushTask = nil
            }
        }
    }

    /// Cancel the flush loop. Performs one final flush of any buffered text.
    func cancel() {
        flushTask?.cancel()
        flushTask = nil
        if let last = pending {
            pending = nil
            displayed[last.bubbleID] = last.text
            onFlush(last.bubbleID, last.text)
        }
    }
}
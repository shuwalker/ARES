import Foundation

// MARK: - Streaming Throttle
//
/// Buffers streaming text updates and flushes to the UI at a maximum of 30 fps.
/// Prevents SwiftUI from re-rendering on every token arrival while still feeling live.
@MainActor
final class StreamingThrottle {
    private var pending: (bubbleID: UUID, text: String)?
    private var flushTask: Task<Void, Never>?
    private let intervalNanos: UInt64 = 33_000_000  // ~30 fps
    private let onFlush: (UUID, String) -> Void

    init(onFlush: @escaping (UUID, String) -> Void) {
        self.onFlush = onFlush
    }

    /// Enqueue a text update. Only the latest text per bubble is kept;
    /// the throttle flushes at most once per `intervalNanos` to the UI.
    func enqueue(bubbleID: UUID, text: String) {
        pending = (bubbleID, text)
        if flushTask == nil {
            flushTask = Task { @MainActor in
                while !Task.isCancelled, let next = self.pending {
                    self.pending = nil
                    self.onFlush(next.bubbleID, next.text)
                    try? await Task.sleep(nanoseconds: self.intervalNanos)
                }
                self.flushTask = nil
            }
        }
    }

    /// Cancel the flush loop. Performs one final flush of any buffered text,
    /// then cleans up the task.
    func cancel() {
        flushTask?.cancel()
        flushTask = nil
        // Final flush: ensure the last buffered text is written to the UI
        if let last = pending {
            pending = nil
            onFlush(last.bubbleID, last.text)
        }
    }
}
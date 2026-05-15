import SwiftUI

/// Caption bar that shows real-time assistant speech text — like AIRI's caption overlay.
///
/// Reads from BrainConnection.captionText (set by chat stream events and face state
/// changes in BrainConnection). Shows animated dots while thinking, the caption text
/// while speaking/responding, and auto-fades out when captionText goes empty.
/// Hover reveals a drag handle (future drag-to-reposition).
struct CaptionOverlay: View {
    @EnvironmentObject var brain: BrainConnection

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                captionBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: brain.agentState)
    }

    /// Whether the bar should be visible — has content or is actively thinking.
    private var isVisible: Bool {
        !brain.captionText.isEmpty || brain.agentState == .thinking || brain.agentState == .speaking
    }

    /// Whether the brain is generating a response (thinking dots shown instead of text).
    private var isThinking: Bool {
        brain.agentState == .thinking && brain.captionText.isEmpty
    }

    private var captionBar: some View {
        HStack(spacing: 10) {
            // ── Speaker icon ──
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(.cyan.opacity(0.8))

            // ── Caption content ──
            if isThinking {
                // Animated typing indicator while waiting for first token
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 5, height: 5)
                            .offset(y: -3)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.15),
                                value: isThinking
                            )
                    }
                }
            } else {
                Text(brain.captionText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            // ── Drag handle (future: drag to reposition) ──
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        )
        .padding(.horizontal, 20)
        .opacity(brain.captionText.isEmpty && !isThinking ? 0 : 0.9)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                // Hover reveals full opacity (handled by scheduleCaptionClear delay)
            }
        }
    }
}

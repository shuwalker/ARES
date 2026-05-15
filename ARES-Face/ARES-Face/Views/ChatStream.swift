import SwiftUI

/// Chat stream with Hermes-inspired message bubbles, auto-scroll, and streaming placeholder.
///
/// Patterns from Hermes Web UI:
///   - User messages right-aligned, colored background
///   - Assistant messages left-aligned, dark glass material
///   - Avatars on assistant messages (ARES icon)
///   - Status indicators (thinking, streaming)
///   - Auto-scroll in Avatar Twin mode, free-scroll in Manual mode
///   - Markdown rendering for assistant messages (code blocks, tables, links, bold, italic)
struct ChatStream: View {
    @EnvironmentObject var brain: BrainConnection

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(brain.messages) { msg in
                        MessageRow(msg: msg)
                            .id(msg.id)
                    }

                    // Streaming indicator while thinking (before first token)
                    if brain.agentState == .thinking && (brain.messages.last?.isUser ?? true) {
                        ThinkingIndicator()
                            .id("streaming")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: brain.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: brain.streamTokenCount) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: brain.agentState) { _, newState in
                if newState == .thinking {
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if brain.shouldAutoScroll {
            if let last = brain.messages.last {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let msg: ARESMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if msg.isUser { Spacer(minLength: 60) }

            if !msg.isUser {
                // Assistant avatar
                assistantAvatar
                    .padding(.trailing, 8)
            }

            VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 2) {
                // ── Sender label ──
                senderLabel

                // ── Message bubble ──
                messageBubble
            }

            if !msg.isUser { Spacer(minLength: 60) }
        }
        .transition(.opacity)
    }

    private var assistantAvatar: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ARESPalette.accent)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ARESPalette.accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ARESPalette.accent.opacity(0.2), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var senderLabel: some View {
        if !msg.isUser {
            Text("ARES")
                .font(.system(size: 10, weight: .semibold).lowercaseSmallCaps())
                .foregroundStyle(ARESPalette.accent.opacity(0.7))
                .padding(.leading, 12)
        }
    }

    @ViewBuilder
    private var messageBubble: some View {
        if msg.isUser {
            Text(msg.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ARESPalette.accent.opacity(0.65))
                )
                .frame(maxWidth: 420, alignment: .trailing)
        } else {
            MarkdownView(markdown: msg.text, fontSize: 13)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ARESPalette.surfaceBorder, lineWidth: 0.5)
                        )
                )
                .frame(maxWidth: 520, alignment: .leading)
        }
    }
}

// MARK: - Thinking Indicator

/// Animated typing indicator shown while the assistant is generating a response.
struct ThinkingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            assistantAvatar
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("ARES")
                    .font(.system(size: 10, weight: .semibold).lowercaseSmallCaps())
                    .foregroundStyle(ARESPalette.accent.opacity(0.7))

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(ARESPalette.accent.opacity(0.6))
                            .frame(width: 6, height: 6)
                            .offset(y: isAnimating ? -4 : 2)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.12),
                                value: isAnimating
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ARESPalette.surfaceBorder, lineWidth: 0.5)
                        )
                )
            }

            Spacer(minLength: 60)
        }
        .padding(.leading, 2)
        .onAppear { isAnimating = true }
    }

    private var assistantAvatar: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ARESPalette.accent)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ARESPalette.accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ARESPalette.accent.opacity(0.2), lineWidth: 0.5)
            )
    }
}

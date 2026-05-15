import SwiftUI

/// Chat stream with AIRI-style message bubbles, auto-scroll, and streaming placeholder.
///
/// Patterns from AIRI (stage-tamagotchi InteractiveArea):
///   - User messages right-aligned, blue accent
///   - Assistant messages left-aligned, translucent material
///   - Error messages centered, red tint
///   - Streaming placeholder with animated dots
///   - Auto-scroll in Avatar Twin mode, free-scroll in Manual mode
///   - Markdown rendering for assistant messages (code blocks, tables, links, bold, italic)
///   - Slash command autocomplete in input bar
struct ChatStream: View {
    @EnvironmentObject var brain: BrainConnection

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(brain.messages) { msg in
                        ChatBubble(msg: msg)
                            .id(msg.id)
                    }

                    // Streaming indicator while thinking (before first token)
                    if brain.agentState == .thinking && (brain.messages.last?.isUser ?? true) {
                        StreamingIndicator()
                            .id("streaming")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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

// MARK: - Chat Bubble

struct ChatBubble: View {
    let msg: ARESMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if msg.isUser { Spacer(minLength: 40) }

            VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 2) {
                // ── Sender label ──
                if !msg.isUser {
                    Text("ARES")
                        .font(.system(size: 10, weight: .semibold).lowercaseSmallCaps())
                        .foregroundStyle(.cyan.opacity(0.7))
                        .padding(.leading, 12)
                }

                // ── Message content ──
                // User messages: plain text
                // ARES messages: full markdown rendering
                if msg.isUser {
                    Text(msg.text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: 360, alignment: .trailing)
                } else {
                    MarkdownView(markdown: msg.text, fontSize: 13)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: 480, alignment: .leading)
                }
            }

            if !msg.isUser { Spacer(minLength: 40) }
        }
        .transition(.move(edge: msg.isUser ? .trailing : .leading).combined(with: .opacity))
    }

    private var bubbleBackground: some View {
        Group {
            if msg.isUser {
                Color.accentColor.opacity(0.65)
            } else {
                Color.white.opacity(0.08)
            }
        }
    }
}

// MARK: - Streaming Indicator

/// Animated typing dots shown while the assistant is generating a response.
struct StreamingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.cyan.opacity(0.6))
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
        .padding(.leading, 12)
        .onAppear { isAnimating = true }
    }
}
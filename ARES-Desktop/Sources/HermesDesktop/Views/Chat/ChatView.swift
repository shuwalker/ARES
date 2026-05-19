import SwiftUI

// MARK: - ChatView

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.5)

            if appState.chatMessages.isEmpty {
                emptyState
            } else {
                messageList
            }

            Divider().opacity(0.5)

            inputArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: appState.activeConnectionID) {
            appState.chatMessages = []
            appState.chatSessionID = nil
            appState.chatError = nil
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Chat"))
                .font(.headline)

            Spacer()

            if appState.isStreamingChat {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8, anchor: .center)
            }

            Button {
                appState.chatMessages = []
                appState.chatSessionID = nil
                appState.chatError = nil
            } label: {
                Label(L10n.string("New Chat"), systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isStreamingChat)
            .help(L10n.string("Start a new chat session"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text(L10n.string("Start a conversation"))
                .font(.headline)

            Text(L10n.string("Type a message below to chat with Hermes on the active host."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.chatMessages) { message in
                        StreamingChatMessageRow(message: message)
                            .id(message.id)
                    }

                    if let error = appState.chatError {
                        ChatErrorRow(message: error)
                            .id("chat-error")
                    }
                }
                .padding(14)
            }
            .onChange(of: appState.chatMessages.count) { _, _ in
                if let last = appState.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: appState.chatMessages.last?.content) { _, _ in
                if let last = appState.chatMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: appState.chatError) { _, newValue in
                if newValue != nil {
                    withAnimation { proxy.scrollTo("chat-error", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Input area

    private var inputArea: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $inputText)
                    .font(.body)
                    .frame(minHeight: 40, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help(L10n.string("Send message"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.03))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.isStreamingChat
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !appState.isStreamingChat else { return }

        inputText = ""

        Task {
            await appState.streamChatMessage(trimmed)
        }
    }
}

// MARK: - StreamingChatMessageRow

private struct StreamingChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 40)

                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                    }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Hermes"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    assistantBubble
                }

                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var assistantBubble: some View {
        Text(message.content + (message.isStreaming ? "\u{258A}" : ""))
            .font(.body)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

// MARK: - ChatErrorRow

private struct ChatErrorRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
        }
    }
}

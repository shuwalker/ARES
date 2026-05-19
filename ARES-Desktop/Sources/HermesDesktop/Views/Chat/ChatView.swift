import SwiftUI

// MARK: - ChatView

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @State private var inputText = ""
    @State private var autoApproveCommands = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.5)

            if appState.sessionMessages.isEmpty && appState.pendingSessionTurn == nil {
                emptyState
            } else {
                messageList
            }

            Divider().opacity(0.5)

            inputArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Chat"))
                .font(.headline)

            Spacer()

            if appState.isSendingSessionMessage {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8, anchor: .center)
            }

            Button {
                appState.selectedSessionID = nil
                appState.sessionConversationError = nil
            } label: {
                Label(L10n.string("New Chat"), systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isSendingSessionMessage)
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
                    ForEach(appState.sessionMessages) { message in
                        ChatMessageRow(message: message)
                            .id(message.id)
                    }

                    if let pending = appState.pendingSessionTurn {
                        ChatPendingRow(turn: pending)
                            .id("pending")
                    }

                    if let error = appState.sessionConversationError {
                        ChatErrorRow(message: error)
                            .id("error")
                    }
                }
                .padding(14)
            }
            .onChange(of: appState.sessionMessages.count) { _, _ in
                if let last = appState.sessionMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: appState.pendingSessionTurn) { _, newValue in
                if newValue != nil {
                    withAnimation { proxy.scrollTo("pending", anchor: .bottom) }
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

            HStack(spacing: 10) {
                Toggle(L10n.string("Auto-approve commands"), isOn: $autoApproveCommands)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.03))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.isSendingSessionMessage
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !appState.isSendingSessionMessage else { return }

        let text = trimmed
        inputText = ""

        Task {
            if appState.selectedSessionID != nil {
                _ = await appState.sendMessageToSelectedSession(text, autoApproveCommands: autoApproveCommands)
            } else {
                _ = await appState.startNewSession(with: text, autoApproveCommands: autoApproveCommands)
            }
        }
    }
}

// MARK: - ChatMessageRow

private struct ChatMessageRow: View {
    let message: SessionMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 40)

                Text(message.content ?? "")
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
                    Text(message.role.displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(message.content ?? "")
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

                Spacer(minLength: 40)
            }
        }
    }

    private var isUser: Bool {
        message.role == .user
    }
}

// MARK: - ChatPendingRow

private struct ChatPendingRow: View {
    let turn: PendingSessionTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Spacer(minLength: 40)

                Text(turn.prompt)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                    }
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(L10n.string("Hermes is thinking…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
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

import AVFoundation
import AppKit
import Speech
import SwiftUI

// MARK: - Slash command definitions

private struct SlashCommand: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    /// Completion text inserted into the field (without leading /)
    let completion: String
}

private let allSlashCommands: [SlashCommand] = [
    SlashCommand(id: "clear", name: "/clear", description: "Clear the conversation", icon: "trash", completion: "/clear"),
    SlashCommand(id: "new", name: "/new", description: "Start a new chat session", icon: "square.and.pencil", completion: "/new"),
    SlashCommand(id: "remember", name: "/remember", description: "Save something to memory", icon: "brain", completion: "/remember "),
    SlashCommand(id: "skill", name: "/skill", description: "Run a named skill", icon: "wand.and.stars", completion: "/skill "),
]

// MARK: - ChatView

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @State private var inputText = ""
    @State private var showSlashPopover = false
    @State private var isRecording = false
    @State private var micAuthDenied = false
    @StateObject private var speechService = SpeechRecognitionService()

    // Filtered commands based on what follows the /
    private var filteredCommands: [SlashCommand] {
        guard inputText.hasPrefix("/") else { return [] }
        let query = String(inputText.dropFirst()).lowercased()
        if query.isEmpty { return allSlashCommands }
        return allSlashCommands.filter { $0.id.hasPrefix(query) || $0.id == query.split(separator: " ").first.map(String.init) ?? "" }
    }

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
                ZStack(alignment: .bottom) {
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
                        .onChange(of: inputText) { _, newValue in
                            let shouldShow = newValue.hasPrefix("/") && !filteredCommands.isEmpty
                            if showSlashPopover != shouldShow {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showSlashPopover = shouldShow
                                }
                            } else if showSlashPopover && filteredCommands.isEmpty {
                                showSlashPopover = false
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if showSlashPopover && !filteredCommands.isEmpty {
                                slashCommandPopover
                                    .offset(y: -48) // position above the text editor
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }

                }

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

    // MARK: - Slash command popover

    private var slashCommandPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(filteredCommands) { command in
                Button {
                    applySlashCommand(command)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: command.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(command.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(command.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.clear)
                .onHover { inside in
                    // highlight handled by macOS default hover feedback via .plain style
                    _ = inside
                }

                if command.id != filteredCommands.last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: -3)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func applySlashCommand(_ command: SlashCommand) {
        withAnimation(.easeInOut(duration: 0.1)) {
            showSlashPopover = false
        }
        inputText = command.completion
        // If the command ends with a space it expects additional text — leave cursor at end.
        // If it's a standalone command, send immediately.
        if !command.completion.hasSuffix(" ") {
            sendMessage()
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.isStreamingChat
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !appState.isStreamingChat else { return }

        // Handle built-in slash commands locally
        if trimmed == "/clear" {
            inputText = ""
            showSlashPopover = false
            appState.chatMessages = []
            appState.chatSessionID = nil
            appState.chatError = nil
            return
        }
        if trimmed == "/new" {
            inputText = ""
            showSlashPopover = false
            appState.chatMessages = []
            appState.chatSessionID = nil
            appState.chatError = nil
            return
        }

        inputText = ""
        showSlashPopover = false

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

                    // Tool calls above assistant text
                    if !message.toolCalls.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(message.toolCalls) { toolCall in
                                ToolCallRow(toolCall: toolCall)
                            }
                        }
                    }

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

// MARK: - ToolCallRow

private struct ToolCallRow: View {
    let toolCall: ChatToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(toolCall.name.isEmpty ? "tool" : toolCall.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                switch toolCall.status {
                case .running:
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)

                case .done:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)

                        if !toolCall.input.isEmpty || toolCall.output != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            // Expanded detail
            if isExpanded && toolCall.status == .done {
                VStack(alignment: .leading, spacing: 4) {
                    if !toolCall.input.isEmpty {
                        Group {
                            Text("Input")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)

                            Text(toolCall.input)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.06))
                        }
                    }

                    if let output = toolCall.output, !output.isEmpty {
                        Group {
                            Text("Output")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)

                            Text(output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.06))
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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

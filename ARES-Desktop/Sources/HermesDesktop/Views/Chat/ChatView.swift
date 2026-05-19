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

    // Input history
    @State private var inputHistory: [String] = []
    @State private var historyIndex: Int = -1
    /// Draft text saved before the user navigates history
    @State private var draftText: String = ""

    // IME composition guard
    @State private var isComposing: Bool = false

    // Fast Mode toggle
    @State private var fastMode: Bool = false

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

            if !appState.pendingApprovals.isEmpty {
                approvalCards
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            inputArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: appState.pendingApprovals.count)
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

            // Thinking level segmented control
            Picker("", selection: $appState.thinkingLevel) {
                ForEach(ThinkingLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.system(size: 11))
            .frame(width: 168)
            .help(L10n.string("Extended thinking level: Off / Low / Adaptive"))
            .disabled(appState.isStreamingChat)

            if appState.isStreamingChat {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8, anchor: .center)
            }

            // Fast Mode toggle
            Button {
                fastMode.toggle()
            } label: {
                Image(systemName: fastMode ? "bolt.fill" : "bolt")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(fastMode ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(fastMode ? .yellow : nil)
            .help(fastMode ? L10n.string("Fast Mode is ON — disable fast mode") : L10n.string("Enable Fast Mode for quicker responses"))

            // Export conversation button
            Button {
                exportConversation()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.chatMessages.isEmpty)
            .help(L10n.string("Export conversation as Markdown"))

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

    // MARK: - Export

    private func exportConversation() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        var markdown = ""
        for message in appState.chatMessages {
            switch message.role {
            case .user:
                markdown += "## User\n\n\(message.content)\n\n"
            case .assistant:
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    markdown += "## Claude's Thinking\n\n\(thinking)\n\n"
                }
                markdown += "## Assistant\n\n\(message.content)\n\n"
            }
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "chat-\(dateString).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
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
        VStack(spacing: 6) {
            if micAuthDenied {
                Text(L10n.string("Microphone access required"))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .transition(.opacity)
            }

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
                        .onSubmit {
                            if !isComposing { sendMessage() }
                        }
                        .onChange(of: inputText) { _, newValue in
                            // Reset history navigation when user types fresh content
                            if historyIndex != -1 {
                                // Only reset if the text differs from what history would supply
                                let historyText = historyIndex < inputHistory.count ? inputHistory[historyIndex] : ""
                                if newValue != historyText {
                                    historyIndex = -1
                                }
                            }
                            let shouldShow = newValue.hasPrefix("/") && !filteredCommands.isEmpty
                            if showSlashPopover != shouldShow {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showSlashPopover = shouldShow
                                }
                            } else if showSlashPopover && filteredCommands.isEmpty {
                                showSlashPopover = false
                            }
                        }
                        .onKeyPress(.upArrow) {
                            guard !inputHistory.isEmpty else { return .ignored }
                            let nextIndex = historyIndex + 1
                            guard nextIndex < inputHistory.count else { return .handled }
                            if historyIndex == -1 {
                                // Save current draft before entering history navigation
                                draftText = inputText
                            }
                            historyIndex = nextIndex
                            inputText = inputHistory[historyIndex]
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            guard historyIndex != -1 else { return .ignored }
                            let nextIndex = historyIndex - 1
                            if nextIndex < 0 {
                                // Restore draft
                                historyIndex = -1
                                inputText = draftText
                            } else {
                                historyIndex = nextIndex
                                inputText = inputHistory[historyIndex]
                            }
                            return .handled
                        }
                        .overlay(alignment: .bottom) {
                            if showSlashPopover && !filteredCommands.isEmpty {
                                slashCommandPopover
                                    .offset(y: -48) // position above the text editor
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                }

                // Microphone button
                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isRecording ? Color.red : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(isRecording ? L10n.string("Stop recording") : L10n.string("Start voice input"))

                // Send button
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
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.03))
    }

    // MARK: - Voice input

    private func toggleRecording() {
        if isRecording {
            speechService.stopRecording()
            isRecording = false
        } else {
            Task {
                let authorized = await speechService.requestAuthorization()
                guard authorized else {
                    withAnimation { micAuthDenied = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        withAnimation { micAuthDenied = false }
                    }
                    return
                }
                micAuthDenied = false
                speechService.onTranscriptionUpdate = { text in
                    self.inputText = text
                }
                do {
                    try speechService.startRecording()
                    isRecording = true
                } catch {
                    isRecording = false
                }
            }
        }
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

    // MARK: - Approval cards

    private var approvalCards: some View {
        VStack(spacing: 6) {
            ForEach(appState.pendingApprovals) { approval in
                ToolApprovalCard(approval: approval) { action in
                    Task {
                        if action == .approve {
                            await appState.approveToolCall(approval)
                        } else {
                            await appState.denyToolCall(approval)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.03))
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
            && !isComposing
    }

    private func sendMessage() {
        guard !isComposing else { return }
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

        // Prepend to input history (keep last 50, no consecutive duplicates)
        if inputHistory.first != trimmed {
            inputHistory.insert(trimmed, at: 0)
            if inputHistory.count > 50 {
                inputHistory = Array(inputHistory.prefix(50))
            }
        }
        historyIndex = -1
        draftText = ""

        inputText = ""
        showSlashPopover = false

        let currentFastMode = fastMode
        Task {
            await appState.streamChatMessage(trimmed, fastMode: currentFastMode)
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

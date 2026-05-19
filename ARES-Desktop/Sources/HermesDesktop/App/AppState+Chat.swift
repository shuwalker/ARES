import Foundation

extension AppState {
    // MARK: - Streaming chat

    func streamChatMessage(_ prompt: String, fastMode: Bool = false) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreamingChat else { return }

        let baseURL = dashboardAPIService.baseURL

        chatError = nil
        isStreamingChat = true

        // Append user message
        chatMessages.append(ChatMessage(role: .user, content: trimmed))

        // Append placeholder assistant message
        let assistantID = UUID()
        chatMessages.append(ChatMessage(
            id: assistantID,
            role: .assistant,
            content: "",
            isStreaming: true
        ))

        let budgetTokens = thinkingLevel.budgetTokens
        do {
            _ = try await hermesChatService.streamMessage(
                trimmed,
                sessionID: chatSessionID,
                baseURL: baseURL,
                thinkingBudgetTokens: budgetTokens,
                fastMode: fastMode,
                onChunk: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantID }) {
                            self.chatMessages[idx].content += delta
                        }
                    }
                },
                onSessionID: { [weak self] sid in
                    Task { @MainActor [weak self] in
                        self?.chatSessionID = sid
                    }
                },
                onToolCall: { [weak self] toolCall in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantID }) {
                            self.chatMessages[idx].toolCalls.append(toolCall)
                        }
                    }
                },
                onToolCallDone: { [weak self] toolCallID in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let msgIdx = self.chatMessages.firstIndex(where: { $0.id == assistantID }),
                           let tcIdx = self.chatMessages[msgIdx].toolCalls.firstIndex(where: { $0.id == toolCallID }) {
                            self.chatMessages[msgIdx].toolCalls[tcIdx].status = .done
                        }
                    }
                },
                onThinkingDelta: { [weak self] thinkingDelta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantID }) {
                            self.chatMessages[idx].thinkingContent = (self.chatMessages[idx].thinkingContent ?? "") + thinkingDelta
                        }
                    }
                }
            )
            // Mark streaming complete
            if let idx = chatMessages.firstIndex(where: { $0.id == assistantID }) {
                chatMessages[idx].isStreaming = false
                // Mark any still-running tool calls as done
                for tcIdx in chatMessages[idx].toolCalls.indices where chatMessages[idx].toolCalls[tcIdx].status == .running {
                    chatMessages[idx].toolCalls[tcIdx].status = .done
                }
            }
            isStreamingChat = false
        } catch {
            // Streaming failed — try SSH fallback if we have an active connection
            if let idx = chatMessages.firstIndex(where: { $0.id == assistantID }) {
                chatMessages.remove(at: idx)
            }
            isStreamingChat = false

            if let profile = activeConnection {
                do {
                    let result = try await hermesChatService.sendMessage(
                        trimmed,
                        sessionID: chatSessionID,
                        connection: profile,
                        autoApproveCommands: false
                    )
                    if let sid = result.sessionID {
                        chatSessionID = sid
                    }
                    let responseText = [result.stdout, result.stderr]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    chatMessages.append(ChatMessage(
                        role: .assistant,
                        content: responseText.isEmpty ? "(No response)" : responseText
                    ))
                } catch {
                    chatError = error.localizedDescription
                    // Remove the user message we already appended so the conversation is clean
                    if let userIdx = chatMessages.lastIndex(where: { $0.role == .user && $0.content == trimmed }) {
                        chatMessages.remove(at: userIdx)
                    }
                }
            } else {
                chatError = error.localizedDescription
                if let userIdx = chatMessages.lastIndex(where: { $0.role == .user && $0.content == trimmed }) {
                    chatMessages.remove(at: userIdx)
                }
            }
        }
    }
}

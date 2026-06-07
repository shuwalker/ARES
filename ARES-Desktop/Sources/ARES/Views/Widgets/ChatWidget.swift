import SwiftUI
import ARESCore

// MARK: - Chat Widget
//
// Standalone chat interface extracted from CompanionView.
// No imports of other widgets — self-contained.

struct ChatWidget: View {
    @State private var messageText: String = ""
    @State private var messages: [CompanionChatBubble] = []
    @State private var isStreaming = false
    @State private var scrollPosition: String?

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { bubble in
                            CompanionChatBubbleView(bubble: bubble)
                                .id(bubble.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                TextField("Type a message...", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isStreaming)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 300)
    }

    private func sendMessage() {
        let userMessage = messageText.trimmingCharacters(in: .whitespaces)
        guard !userMessage.isEmpty else { return }

        // Add user bubble
        let userBubble = CompanionChatBubble(
            id: UUID().uuidString,
            role: .user,
            content: userMessage,
            timestamp: Date()
        )
        messages.append(userBubble)
        messageText = ""

        // Send via gateway
        isStreaming = true
        let gatewayMessages = messages.dropLast().map { bubble in
            GatewayMessage(
                role: bubble.role == .user ? "user" : "assistant",
                content: bubble.content
            )
        }

        Task {
            do {
                let result = try await CompanionChatService.shared.sendMessageStream(
                    messages: Array(gatewayMessages),
                    sessionID: nil,
                    onToken: { accumulated, isFinished in
                        if messages.last?.role == .assistant {
                            messages[messages.count - 1].content = accumulated
                        } else if accumulated.count > 0 {
                            let assistantBubble = CompanionChatBubble(
                                id: UUID().uuidString,
                                role: .assistant,
                                content: accumulated,
                                timestamp: Date()
                            )
                            messages.append(assistantBubble)
                        }
                    }
                )

                await MainActor.run {
                    isStreaming = false
                    CompanionChatService.shared.appendTurn(
                        role: "user",
                        content: userMessage,
                        sessionID: result.sessionID,
                        model: ""
                    )
                    CompanionChatService.shared.appendTurn(
                        role: "assistant",
                        content: result.responseText,
                        sessionID: result.sessionID,
                        model: ""
                    )
                }
            } catch {
                await MainActor.run {
                    isStreaming = false
                    let errorBubble = CompanionChatBubble(
                        id: UUID().uuidString,
                        role: .assistant,
                        content: "Error: \(error.localizedDescription)",
                        timestamp: Date()
                    )
                    messages.append(errorBubble)
                }
            }
        }
    }
}

// MARK: - Chat Bubble View

struct CompanionChatBubbleView: View {
    let bubble: CompanionChatBubble

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if bubble.role == .assistant {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bubble.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                }
                Spacer()
            } else {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(bubble.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Chat Bubble Model

struct CompanionChatBubble: Identifiable {
    let id: String
    enum Role {
        case user
        case assistant
    }
    let role: Role
    var content: String
    let timestamp: Date
}

#Preview {
    ChatWidget()
        .padding()
}

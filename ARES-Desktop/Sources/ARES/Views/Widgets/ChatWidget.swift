import SwiftUI
import ARESCore

// MARK: - Chat Widget
//
// Standalone chat interface for the Dashboard.
// Routes through ARESAppState to use the active reasoning brain.

struct ChatWidget: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var messageText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.chatMessages) { bubble in
                            ChatWidgetBubbleView(bubble: bubble)
                                .id(bubble.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: appState.chatMessages.count) { old, new in
                    if let lastId = appState.chatMessages.last?.id {
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

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 300)
    }

    private func sendMessage() {
        let userMessage = messageText.trimmingCharacters(in: .whitespaces)
        guard !userMessage.isEmpty else { return }
        
        appState.chatInput = userMessage
        messageText = ""
        
        // Let AppState handle the pipeline (memory refs, gateway switching, streaming, TTS, UI updates)
        appState.sendChat()
    }
}

// MARK: - Chat Bubble View

struct ChatWidgetBubbleView: View {
    let bubble: ChatBubble

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

#Preview {
    ChatWidget()
        .padding()
}

import Foundation
import SwiftUI

@MainActor
final class AresAppState: ObservableObject {
    let api = AresAPI()

    @Published var status: AresAPI.Status?
    @Published var identity: AresAPI.Identity?
    @Published var faceState: AresAPI.FaceState?
    @Published var memory: [AresAPI.MemoryHit] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatInput = ""

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isConnected = false

    struct ChatMessage: Identifiable {
        let id = UUID()
        let isUser: Bool
        let text: String
        let timestamp: Date = Date()
    }

    init() {
        Task {
            await checkConnection()
        }
    }

    func checkConnection() async {
        do {
            let status = try await api.getStatus()
            self.status = status
            self.isConnected = true
            self.errorMessage = nil
        } catch {
            self.isConnected = false
            self.errorMessage = "ARES daemon not reachable. Is it running? Try: ares start"
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            self.status = try await api.getStatus()
            self.identity = try await api.getIdentity()
            self.faceState = try await api.getFaceState()
            self.memory = try await api.getMemory()
            self.isConnected = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Error: \(error.localizedDescription)"
        }
    }

    func sendMessage() async {
        guard !chatInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let userMessage = chatInput
        chatInput = ""

        chatMessages.append(ChatMessage(isUser: true, text: userMessage))

        do {
            let response = try await api.chat(message: userMessage)
            chatMessages.append(ChatMessage(isUser: false, text: response.text))
        } catch {
            chatMessages.append(ChatMessage(isUser: false, text: "Error: \(error.localizedDescription)"))
        }
    }
}

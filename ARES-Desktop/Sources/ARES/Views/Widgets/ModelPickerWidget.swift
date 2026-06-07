import SwiftUI
import ARESCore

// MARK: - Model Picker Widget
//
// Displays available local Ollama models and cloud options.
// User selection switches the active gateway provider.
// Vision models and cloud models are badged.

struct ModelPickerWidget: View {
    @State private var localModels: [String] = [
        "gemma4:e4b",
        "qwen3-8b-ares",
        "gemma4-ares",
        "qwen3-vl:8b",
        "qwen3:8b",
        "gemma4:e4b-mlx"
    ]
    @State private var selectedModel: String = "gemma4:e4b"
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model").font(.caption).foregroundColor(.secondary)

            HStack(spacing: 8) {
                Menu {
                    Section("Local (Ollama)") {
                        ForEach(localModels, id: \.self) { model in
                            Button {
                                selectedModel = model
                                switchToOllama(model)
                            } label: {
                                HStack {
                                    Text(model)
                                    if model.contains("vl") {
                                        Label("Vision", systemImage: "eye")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }

                    Section("Cloud") {
                        Button("Hermes Agent") {
                            selectedModel = "hermes-agent"
                            switchToHermes()
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(modelDisplay(selectedModel))
                                .font(.system(.body, design: .monospaced))
                            Text(modelProvider(selectedModel))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func modelDisplay(_ model: String) -> String {
        if model == "hermes-agent" {
            return "Hermes Agent"
        }
        return model.split(separator: ":").first.map(String.init) ?? model
    }

    private func modelProvider(_ model: String) -> String {
        if model == "hermes-agent" {
            return "Cloud • Multi-turn"
        }
        if model.contains("vl") {
            return "Local • Vision"
        }
        return "Local"
    }

    private func switchToOllama(_ model: String) {
        isLoading = true
        Task {
            let gateway = OllamaGatewayProvider(
                baseURL: URL(string: "http://localhost:11434")!
            )
            CompanionChatService.shared.switchProvider(gateway)
            CompanionChatService.shared.reconfigure(
                provider: "ollama",
                gatewayURL: "http://localhost:11434"
            )
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func switchToHermes() {
        isLoading = true
        Task {
            let apiKey = ProcessInfo.processInfo.environment["API_SERVER_KEY"] ?? ""
            let gateway = HermesGatewayProvider(
                baseURL: URL(string: "http://localhost:8642")!,
                apiKey: apiKey
            )
            CompanionChatService.shared.switchProvider(gateway)
            CompanionChatService.shared.reconfigure(
                provider: "hermes",
                gatewayURL: "http://localhost:8642"
            )
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

#Preview {
    ModelPickerWidget()
        .padding()
        .background(Color(.windowBackgroundColor))
}

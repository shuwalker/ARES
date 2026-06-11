import SwiftUI
import ARESCore

// MARK: - Backend Picker Widget
//
// Clarifies the architectural choice between two fundamentally different systems:
//
// OLLAMA (Pure LLM, No Tools):
//   - Raw language model inference only
//   - No memory, no tools, no services
//   - Fast, lightweight, runs locally
//   - Use when: you want a thinking engine, not an agentic system
//   - Gateway: OllamaGatewayProvider → localhost:11434
//
// HERMES (Independent Agentic Framework):
//   - Full agent with tools, memory, skills, multi-turn reasoning
//   - Can invoke filesystem, web, code execution, custom tools
//   - Persistent sessions and episodic memory
//   - Can delegate to Ollama or other LLMs internally
//   - Use when: you want an autonomous system that acts, not just thinks
//   - Gateway: HermesGatewayProvider → localhost:8642

struct BackendPickerWidget: View {
    @EnvironmentObject var appState: ARESAppState
    @State private var selectedOllamaModel: String = "gemma4:e4b"
    @State private var selectedBackend: Backend = .ollama(model: "gemma4:e4b")
    @State private var isLoading = false

    enum Backend {
        case ollama(model: String)
        case hermes
        case claude
        case openai

        var label: String {
            switch self {
            case .ollama(let model):
                return model.split(separator: ":").first.map(String.init) ?? model
            case .hermes: return "Hermes Agent"
            case .claude: return "Claude 3.5 Sonnet"
            case .openai: return "GPT-4o"
            }
        }

        var description: String {
            switch self {
            case .ollama(let model):
                if model.contains("vl") { return "LLM • Vision • Local" }
                return "LLM • Local • No tools"
            case .hermes: return "Agent • Tools • Memory"
            case .claude: return "Cloud LLM • Anthropic"
            case .openai: return "Cloud LLM • OpenAI"
            }
        }
    }

    let ollamaModels = [
        "gemma4:e4b",
        "qwen3-8b-ares",
        "gemma4-ares",
        "qwen3-vl:8b",
        "qwen3:8b",
        "gemma4:e4b-mlx"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backend").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)

            Menu {
                Section("Pure LLM (Local)") {
                    ForEach(ollamaModels, id: \.self) { model in
                        Button {
                            selectedOllamaModel = model
                            selectedBackend = .ollama(model: model)
                            switchBackend(to: .ollama(url: "http://localhost:11434"))
                            appState.companionConfig.model = model
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model).font(.system(.body, design: .monospaced))
                                    Text("Ollama").font(.caption2).foregroundColor(.secondary)
                                }
                                if model.contains("vl") {
                                    Spacer()
                                    Label("Vision", systemImage: "eye").font(.caption2).foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section("Cloud LLMs") {
                    Button {
                        selectedBackend = .claude
                        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ProcessInfo.processInfo.environment["API_SERVER_KEY"] ?? ""
                        switchBackend(to: .anthropic(apiKey: apiKey))
                        appState.companionConfig.model = "claude-3-5-sonnet-20240620"
                    } label: {
                        Text("Claude 3.5 Sonnet").font(.system(.body, design: .monospaced))
                    }
                    
                    Button {
                        selectedBackend = .openai
                        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ProcessInfo.processInfo.environment["API_SERVER_KEY"] ?? ""
                        switchBackend(to: .openai(apiKey: apiKey))
                        appState.companionConfig.model = "gpt-4o"
                    } label: {
                        Text("GPT-4o").font(.system(.body, design: .monospaced))
                    }
                }

                Section("Agentic Framework (With Tools)") {
                    Button {
                        selectedBackend = .hermes
                        switchBackend(to: .hermes(url: "http://localhost:8642"))
                        appState.companionConfig.model = "hermes"
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hermes Agent").font(.system(.body, design: .monospaced))
                            HStack(spacing: 4) {
                                Label("Tools", systemImage: "wrench.and.hammer")
                                Label("Memory", systemImage: "brain")
                                Label("Skills", systemImage: "bolt")
                            }
                            .font(.caption2)
                            .foregroundColor(.green)
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedBackend.label)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Text(selectedBackend.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.down").foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            }
            .disabled(isLoading)

            VStack(alignment: .leading, spacing: 6) {
                switch selectedBackend {
                case .ollama:
                    Label("Local Model", systemImage: "cpu").font(.caption).foregroundColor(.blue)
                    Text("Fast inference, runs locally. No tools or memory.").font(.caption2).foregroundColor(.secondary)
                case .hermes:
                    Label("Independent Agent", systemImage: "gear").font(.caption).foregroundColor(.green)
                    Text("Autonomous system with tools, memory, skills.").font(.caption2).foregroundColor(.secondary)
                case .claude, .openai:
                    Label("Cloud Model", systemImage: "cloud").font(.caption).foregroundColor(.purple)
                    Text("Powerful cloud reasoning. No local tools.").font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.windowBackgroundColor))
            .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func switchBackend(to impl: GatewayImpl) {
        isLoading = true
        Task {
            await MainActor.run {
                appState.switchGateway(impl)
                isLoading = false
            }
        }
    }
}

#Preview {
    BackendPickerWidget()
        .padding()
        .background(Color(.windowBackgroundColor))
}

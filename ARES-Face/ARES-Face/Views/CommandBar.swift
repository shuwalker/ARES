import SwiftUI

/// Command bar with slash commands, model selector, and voice input.
///
/// Features:
/// - Slash command autocomplete (/, /clear, /compact, /model, /run)
/// - Model selector dropdown (switch between configured models)
/// - Voice input button
/// - Send button with visual state
struct CommandBar: View {
    @EnvironmentObject var brain: BrainConnection
    @EnvironmentObject var voice: VoiceManager
    @FocusState private var focused: Bool
    @State private var showSlashCommands = false
    @State private var showModelSelector = false
    @State private var slashFilter = ""

    /// Available slash commands
    private let slashCommands: [(name: String, desc: String, icon: String)] = [
        ("/clear", "Clear conversation history", "trash"),
        ("/compact", "Summarize and compress context", "arrow.triangle.merge"),
        ("/model", "Switch AI model", "cpu"),
        ("/run", "Run a terminal command", "terminal"),
        ("/skills", "List available skills", "wrench.and.screwdriver"),
        ("/sessions", "Browse conversation history", "clock.arrow.circlepath"),
        ("/memory", "Search agent memory", "brain.head.profile"),
        ("/help", "Show available commands", "questionmark.circle"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(.white.opacity(0.08))

            // Slash command autocomplete popup
            if showSlashCommands {
                slashCommandList
            }

            // Model selector popup
            if showModelSelector {
                modelSelectorDropdown
            }

            HStack(spacing: 8) {
                // Slash command trigger
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showSlashCommands.toggle()
                        showModelSelector = false
                        if showSlashCommands {
                            focused = true
                        }
                    }
                } label: {
                    Image(systemName: "slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(showSlashCommands ? .cyan : .secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(showSlashCommands ? 0.1 : 0.04))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Commands")

                // Model selector button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showModelSelector.toggle()
                        showSlashCommands = false
                    }
                } label: {
                    Image(systemName: "cpu")
                        .font(.system(size: 13))
                        .foregroundStyle(showModelSelector ? .cyan : .secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(showModelSelector ? 0.1 : 0.04))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Switch model")

                // Text input
                TextField("Talk to ARES... (type / for commands)", text: $brain.inputText)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .onChange(of: brain.inputText) { _, newValue in
                        updateSlashFilter(newValue)
                    }
                    .onSubmit {
                        handleSend()
                    }

                // Voice button
                Button {
                    if voice.isListening {
                        voice.stopListening()
                        if !voice.transcript.isEmpty {
                            brain.sendMessage(voice.transcript)
                        }
                    } else {
                        voice.startListening()
                    }
                } label: {
                    Image(systemName: voice.isListening ? "waveform.circle.fill" : "mic.circle")
                        .font(.title2)
                        .foregroundStyle(voice.isListening ? .green : .secondary)
                }
                .buttonStyle(.plain)

                // Send button
                Button {
                    handleSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? .blue : .secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Computed

    private var canSend: Bool {
        !brain.inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Slash Command List

    private var slashCommandList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(filteredCommands, id: \.name) { cmd in
                Button {
                    executeSlashCommand(cmd.name)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: cmd.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(.cyan)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cmd.name)
                                .font(.system(size: 12, weight: .medium))
                            Text(cmd.desc)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var filteredCommands: [(name: String, desc: String, icon: String)] {
        if slashFilter.isEmpty {
            return slashCommands
        }
        return slashCommands.filter { $0.name.contains(slashFilter.lowercased()) }
    }

    // MARK: - Model Selector Dropdown

    private var modelSelectorDropdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Switch Model")
                .font(.system(size: 11, weight: .semibold).lowercaseSmallCaps())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            ForEach(brain.availableModels, id: \.self) { model in
                Button {
                    switchModel(model)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model == brain.currentModel ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(model == brain.currentModel ? .cyan : .secondary)
                        Text(model)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(model == brain.currentModel ? Color.cyan.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func handleSend() {
        let text = brain.inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        if text.hasPrefix("/") {
            executeSlashCommand(text)
        } else {
            brain.sendMessage(text)
        }
    }

    private func executeSlashCommand(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 1)
        let cmd = parts.first.map(String.init) ?? command
        let args = parts.count > 1 ? String(parts[1]) : ""

        switch cmd {
        case "/clear", "/c":
            brain.messages.removeAll(keepingCapacity: true)
            brain.inputText = ""
        case "/compact":
            brain.sendMessage("/compact")
            brain.inputText = ""
        case "/model":
            if !args.isEmpty {
                switchModel(args)
            } else {
                showModelSelector = true
            }
            brain.inputText = ""
        case "/run":
            if !args.isEmpty {
                brain.sendMessage("Run this terminal command: \(args)")
            }
            brain.inputText = ""
        case "/skills":
            brain.sendMessage("List all available skills and their descriptions.")
            brain.inputText = ""
        case "/sessions":
            brain.sendMessage("Show my recent conversation sessions.")
            brain.inputText = ""
        case "/memory":
            brain.sendMessage(args.isEmpty ? "Search my memory for recent entries." : "Search my memory for: \(args)")
            brain.inputText = ""
        case "/help":
            showSlashCommands = true
            brain.inputText = ""
        default:
            brain.sendMessage(command)
            brain.inputText = ""
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            showSlashCommands = false
        }
    }

    private func switchModel(_ model: String) {
        brain.currentModel = model
        // Send model switch message to backend
        brain.sendMessage("Switch to model \(model)")
        withAnimation(.easeInOut(duration: 0.15)) {
            showModelSelector = false
        }
    }

    private func updateSlashFilter(_ text: String) {
        if text.hasPrefix("/") {
            showSlashCommands = true
            slashFilter = String(text.dropFirst())
        } else {
            showSlashCommands = false
            slashFilter = ""
        }
    }
}
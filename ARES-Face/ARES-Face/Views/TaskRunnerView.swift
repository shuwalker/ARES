import SwiftUI

/// Quick-action task runner — shortcut buttons that trigger Hermes capabilities.
///
/// Not a terminal emulator. This is a curated set of actions that send
/// structured prompts through BrainConnection and show streaming responses.
/// Each action creates an ARESMessage and sends it via brain.sendMessage().
struct TaskRunnerView: View {
    @EnvironmentObject var brain: BrainConnection
    @State private var customPrompt = ""
    @State private var terminalCommand = ""
    @State private var isRunning = false
    @State private var showingCronSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // ── Quick Actions Grid ──
                    quickActionsGrid

                    // ── Custom Prompt ──
                    customPromptSection

                    // ── Terminal Command ──
                    terminalSection

                    // ── System ──
                    systemSection
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingCronSheet) {
            CronCreationSheet(brain: brain)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.fill")
                .foregroundStyle(.cyan)
            Text("Task Runner")
                .font(.title3.weight(.semibold))
            Spacer()
            if isRunning {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text(brain.agentState.rawValue.capitalized)
                .font(.caption2.weight(.medium).lowercaseSmallCaps())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(stateColor.opacity(0.15))
                .cornerRadius(4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var stateColor: Color {
        switch brain.agentState {
        case .idle:      return .blue
        case .awakened:  return .cyan
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .purple
        case .sleeping:  return .gray
        }
    }

    // MARK: - Quick Actions Grid

    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Quick Actions")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                actionCard("Start Project", icon: "folder.badge.plus", color: .cyan) {
                    sendMessage("Start a new project. What do you need built?")
                }
                actionCard("Search Web", icon: "globe", color: .blue) {
                    sendMessage("Search the web for current information about")
                }
                actionCard("Analyze Code", icon: "doc.text.magnifyingglass", color: .orange) {
                    sendMessage("Analyze the codebase and report on architecture, issues, and improvements.")
                }
                actionCard("Write Docs", icon: "doc.richtext", color: .green) {
                    sendMessage("Write documentation for this project. Cover setup, usage, and architecture.")
                }
                actionCard("Debug Issue", icon: "ladybug", color: .red) {
                    sendMessage("I'm experiencing an issue. Let me describe it: ")
                }
                actionCard("Brainstorm", icon: "lightbulb.fill", color: .yellow) {
                    sendMessage("Brainstorm creative solutions for: ")
                }
                actionCard("Summarize", icon: "doc.text.bullets", color: .purple) {
                    sendMessage("Summarize the current state of work and key decisions made.")
                }
                actionCard("Deploy", icon: "cloud.upload.fill", color: .mint) {
                    sendMessage("Prepare and deploy the current project. Check for issues first.")
                }
            }
        }
    }

    // MARK: - Custom Prompt

    private var customPromptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Custom Prompt")
            HStack(spacing: 8) {
                TextField("Ask anything...", text: $customPrompt)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .onSubmit { sendCustomPrompt() }

                Button {
                    sendCustomPrompt()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(customPrompt.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.cyan)
                }
                .buttonStyle(.plain)
                .disabled(customPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Terminal Section

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Terminal")
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 14, design: .monospaced).weight(.bold))
                    .foregroundStyle(.green)
                TextField("Run command...", text: $terminalCommand)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .onSubmit { runTerminalCommand() }

                Button {
                    runTerminalCommand()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(6)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(terminalCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - System Section

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("System")
            HStack(spacing: 8) {
                systemButton("Health Check", icon: "heart.text.square", color: .green) {
                    sendMessage("Run a full system health check. Report on all services, memory usage, disk space, and running processes.")
                }
                systemButton("Check Cron", icon: "timer", color: .orange) {
                    showingCronSheet = true
                }
                systemButton("Memory Stats", icon: "brain.head.profile", color: .purple) {
                    sendMessage("Report on memory usage: how many entries, categories, oldest/newest, and any stale data to clean up.")
                }
            }
        }
    }

    // MARK: - Action Card

    private func actionCard(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(color.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - System Button

    private func systemButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(color.opacity(0.08))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Label

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold).lowercaseSmallCaps())
            .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        isRunning = true
        brain.sendMessage(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRunning = false
        }
    }

    private func sendCustomPrompt() {
        let text = customPrompt.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        brain.sendMessage(text)
        customPrompt = ""
    }

    private func runTerminalCommand() {
        let cmd = terminalCommand.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        brain.sendMessage("Run this terminal command and show me the output: \(cmd)")
        terminalCommand = ""
    }
}

// MARK: - Cron Creation Sheet

struct CronCreationSheet: View {
    @ObservedObject var brain: BrainConnection
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var schedule = ""
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Cron Job")
                .font(.headline)

            VStack(spacing: 10) {
                TextField("Job name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Schedule (e.g. 'every 2h', '0 9 * * *')", text: $schedule)
                    .textFieldStyle(.roundedBorder)
                TextField("Prompt (what should ARES do?)", text: $prompt)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Create") {
                    brain.sendMessage("Create a cron job named '\(name)' with schedule '\(schedule)' that does: \(prompt)")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || prompt.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
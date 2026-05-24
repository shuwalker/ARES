import SwiftUI

struct CompanionView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var personalityExpanded = false

    var body: some View {
        HSplitView {
            // Left: Avatar + voice
            avatarPanel
                .frame(minWidth: 280, idealWidth: 340)

            // Right: Personality + status
            detailPanel
                .frame(minWidth: 360)
        }
    }

    // MARK: - Avatar panel

    private var avatarPanel: some View {
        VStack(spacing: 20) {
            Spacer()

            // Avatar
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 180, height: 180)

                Image(systemName: "person.fill.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, isActive: appState.voiceState == .thinking)
            }
            .overlay(alignment: .bottomTrailing) {
                voiceDot
            }

            // Greeting
            Text(appState.companionGreeting)
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            // Voice state
            Label(appState.voiceState.label, systemImage: "waveform")
                .font(.subheadline)
                .foregroundStyle(appState.voiceState.color)

            Spacer()

            // Quick actions
            HStack(spacing: 12) {
                Button(action: startListening) {
                    Label("Talk", systemImage: "mic.fill")
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.voiceState == .listening)

                Button(action: {}) {
                    Label("Type", systemImage: "keyboard")
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 32)
        }
        .padding(24)
        .background(.regularMaterial)
    }

    private var voiceDot: some View {
        Circle()
            .fill(appState.voiceState.color)
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .stroke(appState.voiceState.color.opacity(0.3), lineWidth: 4)
                    .scaleEffect(appState.voiceState == .speaking ? 1.8 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(),
                               value: appState.voiceState == .speaking)
            )
            .padding(6)
    }

    // MARK: - Detail panel

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Status cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatusCard(
                        title: "Skills",
                        value: "\(appState.skillCount) optimized",
                        systemImage: "book.closed.fill",
                        color: .blue
                    )
                    StatusCard(
                        title: "Sessions",
                        value: "\(appState.sessionCount) today",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        color: .purple
                    )
                    StatusCard(
                        title: "Memory",
                        value: "\(appState.memoryPercent)% full",
                        systemImage: "brain.head.profile.fill",
                        color: .orange
                    )
                    StatusCard(
                        title: "Hermes",
                        value: appState.hermesRunning ? "Online" : "Offline",
                        systemImage: appState.hermesRunning ? "bolt.fill" : "bolt.slash.fill",
                        color: appState.hermesRunning ? .green : .red
                    )
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Personality panel
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: { personalityExpanded.toggle() }) {
                        HStack {
                            Label("What ARES Knows About You", systemImage: "person.text.rectangle.fill")
                                .font(.headline)
                            Spacer()
                            Image(systemName: personalityExpanded
                                  ? "chevron.down" : "chevron.right")
                        }
                    }
                    .buttonStyle(.plain)

                    if personalityExpanded {
                        if appState.selfModelContent.isEmpty {
                            Text("Self-model not yet generated.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)

                            Text("Run the self-reflection engine to build your profile.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 8)
                        } else {
                            Text(appState.selfModelContent)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(personalityExpanded ? nil : 3)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Quick links
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Links")
                        .font(.headline)
                        .padding(.horizontal)

                    LinkButton("Hermes WebUI", url: "http://localhost:9119")
                    LinkButton("SearXNG Search", url: "http://localhost:8080")
                    LinkButton("Ollama Models", url: "http://localhost:11434")
                }
                .padding(.horizontal)

                Spacer(minLength: 24)
            }
            .padding(.vertical, 20)
        }
        .background(.regularMaterial)
    }

    // MARK: - Actions

    private func startListening() {
        appState.voiceState = .listening
        // Phase 4: wire Speech framework here
    }
}

// MARK: - Status card

struct StatusCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Spacer()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Link button

struct LinkButton: View {
    let label: String
    let url: String

    init(_ label: String, url: String) {
        self.label = label
        self.url = url
    }

    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            Label(label, systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

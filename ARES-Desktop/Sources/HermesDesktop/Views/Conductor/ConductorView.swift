import SwiftUI

struct ConductorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedOutputCard: ConductorWorkerCard?

    var body: some View {
        if !appState.dashboardAPIAvailable {
            ContentUnavailableView(
                "Dashboard Unavailable",
                systemImage: "wand.and.stars",
                description: Text("Connect to a local Hermes instance to use the Conductor.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HermesPageContainer(width: .dashboard) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    // Error banner
                    if let error = appState.conductorError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.callout)
                            Spacer()
                            Button("Dismiss") { appState.conductorError = nil }
                                .font(.callout)
                        }
                        .padding()
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    goalInputPanel
                    if !appState.conductorWorkerCards.isEmpty {
                        workersGrid
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HermesPageHeader(
            title: "Conductor",
            subtitle: "Describe a goal and dispatch AI workers to accomplish it."
        )
    }

    // MARK: - Goal Input

    private var goalInputPanel: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mission Goal")
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    if appState.conductorGoal.isEmpty {
                        Text("Describe your goal…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(
                        get: { appState.conductorGoal },
                        set: { newValue in
                            appState.conductorGoal = String(newValue.prefix(1000))
                        }
                    ))
                    .font(.body)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                }
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .disabled(appState.conductorMissionActive)

                HStack {
                    Spacer()
                    Text("\(appState.conductorGoal.count)/1000")
                        .font(.caption2)
                        .foregroundStyle(appState.conductorGoal.count >= 950 ? .orange : .secondary)
                }

                modelPicker

                presetButtons

                HStack {
                    Spacer()
                    if appState.conductorMissionActive {
                        Button(role: .destructive) {
                            appState.stopConductorMission()
                        } label: {
                            Label("Stop Mission", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button {
                            Task { await appState.launchConductorMission() }
                        } label: {
                            Label("Launch Mission", systemImage: "wand.and.stars")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(appState.conductorGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        HStack(spacing: 12) {
            Text("Model")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if appState.conductorSelectedModel.isEmpty {
                Text("(default)")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                Text(appState.conductorSelectedModel)
                    .font(.subheadline)
            }
        }
    }

    private var presetButtons: some View {
        HStack(spacing: 8) {
            Text("Quick:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(ConductorPreset.allCases) { preset in
                Button(preset.label) {
                    applyPreset(preset)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.conductorMissionActive)
            }
        }
    }

    private func applyPreset(_ preset: ConductorPreset) {
        appState.conductorGoal = preset.promptTemplate
    }

    // MARK: - Workers Grid

    private var workersGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Workers")
                    .font(.headline)
                Spacer()
                if appState.conductorMissionActive {
                    Label("Running", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(appState.conductorWorkerCards) { card in
                    ConductorWorkerCardView(card: card) {
                        selectedOutputCard = card
                    }
                }
            }
        }
        .sheet(item: $selectedOutputCard) { card in
            ConductorOutputSheet(card: card)
        }
    }
}

// MARK: - Worker Card

private struct ConductorWorkerCardView: View {
    let card: ConductorWorkerCard
    let onViewOutput: () -> Void

    var body: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(card.workerName, systemImage: workerIcon)
                        .font(.headline)
                    Spacer()
                    statusBadge
                }

                HStack(spacing: 16) {
                    Label("\(card.tokenCount)", systemImage: "circle.hexagongrid")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(elapsedTime, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !outputPreview.isEmpty {
                    Text(outputPreview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }

                Button("View Output") {
                    onViewOutput()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(card.output.isEmpty)
            }
            .padding(14)
        }
    }

    private var workerIcon: String {
        switch card.workerName.lowercased() {
        case "orchestrator": return "wand.and.stars"
        case "builder": return "hammer"
        case "reviewer": return "checkmark.seal"
        case "devops": return "server.rack"
        default: return "person.crop.circle"
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, isActive: card.status == "Running" || card.status == "Thinking")
            Text(card.status)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
        }
    }

    private var statusIcon: String {
        switch card.status {
        case "Thinking": return "ellipsis.circle"
        case "Running": return "play.circle.fill"
        case "Done": return "checkmark.circle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch card.status {
        case "Thinking": return .orange
        case "Running": return .green
        case "Done": return .blue
        default: return .secondary
        }
    }

    private var elapsedTime: String {
        guard let start = card.startTime else { return "—" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private var outputPreview: String {
        let lines = card.output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.suffix(2).joined(separator: "\n")
    }
}

// MARK: - Output Sheet

private struct ConductorOutputSheet: View {
    let card: ConductorWorkerCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(card.workerName, systemImage: "person.crop.circle")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                Text(card.output.isEmpty ? "(No output yet)" : card.output)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(width: 640, height: 480)
    }
}

// MARK: - Presets

private enum ConductorPreset: String, CaseIterable, Identifiable {
    case research
    case build
    case review
    case deploy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .research: "Research"
        case .build: "Build"
        case .review: "Review"
        case .deploy: "Deploy"
        }
    }

    var promptTemplate: String {
        switch self {
        case .research:
            return "Research and summarize the current state of the art for: "
        case .build:
            return "Build and implement a solution for: "
        case .review:
            return "Review the code and provide a detailed quality audit for: "
        case .deploy:
            return "Deploy and release the following to production: "
        }
    }
}

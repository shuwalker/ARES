import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var models: ModelsResponse?
    @State private var analytics: ModelsAnalyticsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedModel: String?
    @State private var showModelConfirmation = false
    @State private var pendingModelSwitch: String?
    @State private var auxiliaryAssignments: [String: String] = [:]

    var body: some View {
        HermesPageContainer(width: .analytics) {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Models",
                    subtitle: "View and manage the active model and auxiliary model assignments for this Hermes instance."
                )

                modelsContent
            }
            .overlay(alignment: .topTrailing) {
                if isLoading && models == nil {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadModels()
        }
        .alert("Switch Model", isPresented: $showModelConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Switch") {
                if let model = pendingModelSwitch {
                    Task { await switchModel(to: model) }
                }
            }
        } message: {
            if let model = pendingModelSwitch {
                Text("Switch the active model to \(model)? This will affect all new sessions.")
            }
        }
    }

    @ViewBuilder
    private var modelsContent: some View {
        if isLoading && models == nil {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading models…", minHeight: 320)
            }
        } else if let error = errorMessage {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load models",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if let models = models {
            modelsLoadedView(models: models)
        } else {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading models…", minHeight: 320)
            }
        }
    }

    private func modelsLoadedView(models: ModelsResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            activeModelPanel(models: models)
            auxiliaryModelsPanel(models: models)

            if let analytics = analytics, let modelData = analytics.models, !modelData.isEmpty {
                analyticsPanel(analytics: modelData)
            }
        }
    }

    private func activeModelPanel(models: ModelsResponse) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Active Model")
                    .font(.headline)

                HStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(models.current)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        if models.available.isEmpty {
                            Text("No alternative models available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                if !models.available.isEmpty {
                    Divider()

                    Text("Switch Model")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(models.available) { option in
                                Button {
                                    pendingModelSwitch = option.id
                                    showModelConfirmation = true
                                } label: {
                                    HStack {
                                        if option.id == models.current {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundStyle(.secondary)
                                        }

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(option.name ?? option.id)
                                                .font(.body)
                                            if let provider = option.provider {
                                                Text(provider)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(option.id == models.current ? Color.accentColor.opacity(0.1) : Color.clear)
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
        }
    }

    private func auxiliaryModelsPanel(models: ModelsResponse) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Auxiliary Models")
                    .font(.headline)

                Text("Assign specialized models for tasks like vision, compression, and search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let auxEntries = auxiliaryAssignments.sorted(by: { $0.key < $1.key })

                if auxEntries.isEmpty {
                    Text("No auxiliary model assignments configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(auxEntries, id: \.key) { key, value in
                        HStack {
                            Text(auxiliaryLabel(for: key))
                                .font(.subheadline)
                            Spacer()
                            Text(value.isEmpty ? "(default)" : value)
                                .font(.subheadline)
                                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func analyticsPanel(analytics: [ModelAnalytics]) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Model Analytics")
                    .font(.headline)

                ForEach(analytics) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.model)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let sessions = entry.sessionCount, sessions > 0 {
                                Text("\(sessions) session\(sessions == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let cost = entry.totalCost, cost > 0 {
                                Text(String(format: "$%.4f", cost))
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                            }
                            if let input = entry.inputTokens, let output = entry.outputTokens {
                                Text("\(formatTokens(input))in / \(formatTokens(output))out")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func auxiliaryLabel(for key: String) -> String {
        switch key {
        case "vision": return "Vision"
        case "compression": return "Compression"
        case "session_search": return "Session Search"
        case "web_extract": return "Web Extract"
        case "skills_hub": return "Skills Hub"
        case "approval": return "Smart Approval"
        case "mcp": return "MCP Routing"
        case "title_generation": return "Title Generation"
        case "curator": return "Skill Curator"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(n)
    }

    // MARK: - Data Loading

    private func loadModels() async {
        guard let connection = appState.activeConnection, connection.transportKind == .local else {
            errorMessage = "Models management requires a local Hermes connection."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let modelsData = try await appState.dashboardAPIService.fetchModels()
            models = modelsData
            auxiliaryAssignments = modelsData.auxiliary ?? [:]

            if let analyticsData = try? await appState.dashboardAPIService.fetchModelsAnalytics() {
                analytics = analyticsData
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func switchModel(to model: String) async {
        isLoading = true
        do {
            try await appState.dashboardAPIService.setModel(model)
            // Refresh models after switching
            await loadModels()
        } catch {
            errorMessage = "Failed to switch model: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
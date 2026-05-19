import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var modelInfo: ModelInfoResponse?
    @State private var modelOptions: ModelOptionsResponse?
    @State private var auxiliaryModels: AuxiliaryModelsResponse?
    @State private var analytics: ModelsAnalyticsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingModelSwitch: String?
    @State private var pendingProviderSwitch: String?
    @State private var showModelConfirmation = false

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
                if isLoading && modelInfo == nil {
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
                    Task { await switchModel(to: model, provider: pendingProviderSwitch) }
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
        if isLoading && modelInfo == nil {
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
        } else if let modelInfo = modelInfo {
            modelsLoadedView(info: modelInfo)
        } else {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading models…", minHeight: 320)
            }
        }
    }

    private func modelsLoadedView(info: ModelInfoResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            activeModelPanel(info: info)
            auxiliaryModelsPanel()

            if let analytics = analytics, let modelData = analytics.models, !modelData.isEmpty {
                analyticsPanel(analytics: modelData)
            }
        }
    }

    private func activeModelPanel(info: ModelInfoResponse) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Active Model")
                    .font(.headline)

                HStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.model)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        if let provider = info.provider {
                            Text(provider)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let ctx = info.effectiveContextLength, ctx > 0 {
                            Text("\(formatTokens(ctx)) token context")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                if let options = modelOptions, !options.providers.isEmpty {
                    Divider()

                    Text("Switch Model")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(options.providers) { provider in
                                if let models = provider.models {
                                    Section(provider.name) {
                                        ForEach(models, id: \.self) { model in
                                            Button {
                                                pendingModelSwitch = model
                                                pendingProviderSwitch = provider.slug
                                                showModelConfirmation = true
                                            } label: {
                                                HStack {
                                                    if model == info.model && provider.isCurrent == true {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(.green)
                                                    } else {
                                                        Image(systemName: "circle")
                                                            .foregroundStyle(.secondary)
                                                    }

                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text(model)
                                                            .font(.body)
                                                        Text(provider.name)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
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
                                                    .fill(model == info.model && provider.isCurrent == true ? Color.accentColor.opacity(0.1) : Color.clear)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
    }

    private func auxiliaryModelsPanel() -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Auxiliary Models")
                    .font(.headline)

                Text("Assign specialized models for tasks like vision, compression, and search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let aux = auxiliaryModels, let tasks = aux.tasks, !tasks.isEmpty {
                    ForEach(tasks) { task in
                        HStack {
                            Text(auxiliaryLabel(for: task.task))
                                .font(.subheadline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(task.model ?? "(default)")
                                    .font(.subheadline)
                                    .foregroundStyle(task.model != nil ? .primary : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let provider = task.provider {
                                    Text(provider)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("No auxiliary model assignments configured")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                            if let provider = entry.provider {
                                Text(provider)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let sessions = entry.sessions, sessions > 0 {
                                Text("\(sessions) session\(sessions == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let cost = entry.estimatedCost, cost > 0 {
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
        guard appState.activeConnection != nil, appState.dashboardAPIAvailable else {
            errorMessage = "Models management requires a local Hermes connection or an active SSH tunnel."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let infoTask = appState.dashboardAPIService.fetchModelInfo()
            async let optionsTask = appState.dashboardAPIService.fetchModelOptions()
            async let auxTask = appState.dashboardAPIService.fetchAuxiliaryModels()

            let (info, options, aux) = try await (infoTask, optionsTask, auxTask)
            modelInfo = info
            modelOptions = options
            auxiliaryModels = aux

            if let analyticsData = try? await appState.dashboardAPIService.fetchModelsAnalytics() {
                analytics = analyticsData
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func switchModel(to model: String, provider: String?) async {
        isLoading = true
        do {
            try await appState.dashboardAPIService.setModel(model: model, provider: provider)
            // Refresh models after switching
            await loadModels()
        } catch {
            errorMessage = "Failed to switch model: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
import SwiftUI

// MARK: - Config Tab Enum

private enum ConfigTab: String, CaseIterable {
    case general = "General"
    case providers = "Providers"
    case models = "Models"
    case memory = "Memory"
}

struct ConfigView: View {
    @EnvironmentObject private var appState: AppState
    @State private var configDict: [String: JSONValue] = [:]
    @State private var rawYAML: String = ""
    @State private var editedYAML: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isEditMode = false
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var searchText = ""
    @State private var selectedTab: ConfigTab = .general

    // Providers tab state
    @State private var providers: [ProviderEntry] = ProviderEntry.defaults
    @State private var showAddProviderSheet = false

    // Models tab state
    @State private var defaultModel: String = ""
    @State private var fallbackChain: [String] = []

    // Memory tab state
    @State private var embeddingProvider: String = ""
    @State private var memoryConsolidation: Bool = false

    private let categories: [ConfigCategory] = [
        ConfigCategory(name: "General", icon: "gearshape", fields: []),
        ConfigCategory(name: "Agent", icon: "cpu", fields: []),
        ConfigCategory(name: "Terminal", icon: "macwindow", fields: []),
        ConfigCategory(name: "Display", icon: "paintbrush", fields: []),
        ConfigCategory(name: "Delegation", icon: "person.2", fields: []),
        ConfigCategory(name: "Memory", icon: "brain", fields: []),
        ConfigCategory(name: "Compression", icon: "arrow.triangle.2.circlepath", fields: []),
        ConfigCategory(name: "Security", icon: "lock.shield", fields: []),
        ConfigCategory(name: "Browser", icon: "globe", fields: []),
        ConfigCategory(name: "Voice", icon: "mic", fields: []),
        ConfigCategory(name: "TTS", icon: "speaker.wave.2", fields: []),
        ConfigCategory(name: "STT", icon: "ear", fields: []),
        ConfigCategory(name: "Logging", icon: "list.clipboard", fields: []),
        ConfigCategory(name: "Discord", icon: "message", fields: []),
        ConfigCategory(name: "Auxiliary", icon: "wrench", fields: []),
    ]

    var body: some View {
        HermesPageContainer(width: .analytics) {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Config",
                    subtitle: "View and edit the Hermes configuration. Changes take effect after session reset or gateway restart."
                ) {
                    Picker("Section", selection: $selectedTab) {
                        ForEach(ConfigTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                tabContent
            }
            .overlay(alignment: .topTrailing) {
                if isLoading && configDict.isEmpty && selectedTab == .general {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadConfig()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            configContent
        case .providers:
            providersTabContent
        case .models:
            modelsTabContent
        case .memory:
            memoryTabContent
        }
    }

    @ViewBuilder
    private var configContent: some View {
        if isLoading && configDict.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading configuration…", minHeight: 320)
            }
        } else if let error = errorMessage {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load config",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if configDict.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No configuration available",
                    systemImage: "doc.text",
                    description: Text("Connect to a local Hermes instance to view its configuration.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            configLoadedView
        }
    }

    private var configLoadedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()

                Picker("Mode", selection: $isEditMode) {
                    Text("Structured").tag(false)
                    Text("Raw YAML").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if isEditMode {
                rawYAMLView
            } else {
                structuredView
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var rawYAMLView: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Raw Configuration")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await saveRawConfig() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }

                TextEditor(text: $editedYAML)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 400)
                    .scrollContentBackground(.visible)
            }
        }
    }

    private var structuredView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search config keys…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            ForEach(categorizedConfig) { category in
                if !category.fields.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(category.fields) { field in
                                configRow(field: field)
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(category.name)
                                .font(.subheadline.weight(.semibold))
                            Text("\(category.fields.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func configRow(field: ConfigField) -> some View {
        HStack {
            Text(field.key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(field.value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
    }

    private var categorizedConfig: [ConfigCategory] {
        let filteredKeys: [(String, JSONValue)]
        if searchText.isEmpty {
            filteredKeys = configDict.sorted { $0.key < $1.key }
        } else {
            filteredKeys = configDict.filter { $0.key.localizedCaseInsensitiveCompare(searchText) == .orderedSame || $0.key.contains(searchText) }
                .sorted { $0.key < $1.key }
        }

        var result = categories.map { cat in
            var modified = cat
            modified = ConfigCategory(
                name: cat.name,
                icon: cat.icon,
                fields: cat.fields
            )
            return modified
        }

        for (key, value) in filteredKeys {
            let category = categorize(key: key)
            let section = result.firstIndex(where: { $0.name == category })
            if let idx = section {
                result[idx] = ConfigCategory(
                    name: result[idx].name,
                    icon: result[idx].icon,
                    fields: result[idx].fields + [ConfigField(
                        key: key,
                        value: value.displayString,
                        originalValue: value.displayString,
                        typeHint: nil
                    )]
                )
            }
        }

        return result.filter { !$0.fields.isEmpty }
    }

    private func categorize(key: String) -> String {
        let lower = key.lowercased()
        if lower.hasPrefix("model") || lower.hasPrefix("agent") { return "Agent" }
        if lower.hasPrefix("terminal") || lower.hasPrefix("shell") { return "Terminal" }
        if lower.hasPrefix("display") || lower.hasPrefix("skin") { return "Display" }
        if lower.hasPrefix("delegation") { return "Delegation" }
        if lower.hasPrefix("memory") { return "Memory" }
        if lower.hasPrefix("compression") { return "Compression" }
        if lower.hasPrefix("security") || lower.hasPrefix("tirith") { return "Security" }
        if lower.hasPrefix("browser") { return "Browser" }
        if lower.hasPrefix("voice") { return "Voice" }
        if lower.hasPrefix("tts") { return "TTS" }
        if lower.hasPrefix("stt") { return "STT" }
        if lower.hasPrefix("log") { return "Logging" }
        if lower.hasPrefix("discord") { return "Discord" }
        if lower.hasPrefix("auxiliary") { return "Auxiliary" }
        return "General"
    }

    // MARK: - Data Loading

    private func loadConfig() async {
        guard appState.activeConnection != nil, appState.dashboardAPIAvailable else {
            errorMessage = "Config editing requires a local Hermes connection or an active SSH tunnel."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let config = try await appState.dashboardAPIService.fetchConfig()
            configDict = config

            let raw = try await appState.dashboardAPIService.fetchRawConfig()
            rawYAML = raw
            editedYAML = raw
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func saveRawConfig() async {
        isSaving = true
        saveMessage = nil

        do {
            try await appState.dashboardAPIService.updateRawConfig(yaml: editedYAML)
            rawYAML = editedYAML
            saveMessage = "Configuration saved. Restart or /reset to apply."

            // Refresh structured view
            let config = try await appState.dashboardAPIService.fetchConfig()
            configDict = config
        } catch {
            saveMessage = "Save failed: \(error.localizedDescription)"
        }

        isSaving = false
    }

    // MARK: - Providers Tab

    private var providersTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("API Providers")
                    .font(.headline)
                Spacer()
                Button {
                    showAddProviderSheet = true
                } label: {
                    Label("Add Provider", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            HermesSurfacePanel {
                VStack(spacing: 0) {
                    ForEach($providers) { $provider in
                        providerRow(provider: $provider)
                        Divider()
                    }
                }
                .padding(.vertical, 4)
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .sheet(isPresented: $showAddProviderSheet) {
            AddProviderSheet { newProvider in
                providers.append(newProvider)
            }
        }
    }

    private func providerRow(provider: Binding<ProviderEntry>) -> some View {
        ProviderRowView(provider: provider) { entry in
            Task { await saveProviderKey(entry) }
        }
    }

    private func saveProviderKey(_ provider: ProviderEntry) async {
        guard appState.dashboardAPIAvailable else { return }
        isSaving = true
        saveMessage = nil
        do {
            let envKey = "\(provider.name.uppercased())_API_KEY"
            try await appState.dashboardAPIService.setEnvVar(key: envKey, value: provider.apiKey)
            if let idx = providers.firstIndex(where: { $0.id == provider.id }) {
                providers[idx].hasKey = !provider.apiKey.isEmpty
            }
            saveMessage = "\(provider.name) API key saved."
        } catch {
            saveMessage = "Failed: \(error.localizedDescription)"
        }
        isSaving = false
    }

    // MARK: - Models Tab

    private var modelsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HermesSurfacePanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Model Preferences")
                        .font(.headline)
                        .padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Model")
                            .font(.subheadline.weight(.semibold))
                        TextField("e.g. claude-opus-4-5", text: $defaultModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Fallback Chain")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                fallbackChain.append("")
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Models tried in order if the default is unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        List {
                            ForEach(Array(fallbackChain.enumerated()), id: \.offset) { index, _ in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    TextField("Model ID", text: Binding(
                                        get: { fallbackChain[index] },
                                        set: { fallbackChain[index] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))
                                    Button {
                                        fallbackChain.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .onMove { from, to in
                                fallbackChain.move(fromOffsets: from, toOffset: to)
                            }
                        }
                        .listStyle(.inset)
                        .frame(minHeight: 80, maxHeight: 200)
                    }

                    HStack {
                        Spacer()
                        Button("Save Model Preferences") {
                            Task { await saveModelPreferences() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                }
                .padding(16)
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func saveModelPreferences() async {
        guard appState.dashboardAPIAvailable else { return }
        isSaving = true
        saveMessage = nil
        var fields: [String: Any] = [:]
        if !defaultModel.isEmpty { fields["default_model"] = defaultModel }
        if !fallbackChain.isEmpty { fields["fallback_chain"] = fallbackChain.filter { !$0.isEmpty } }
        do {
            try await appState.dashboardAPIService.patchClaudeConfig(fields)
            saveMessage = "Model preferences saved."
        } catch {
            saveMessage = "Failed: \(error.localizedDescription)"
        }
        isSaving = false
    }

    // MARK: - Memory Tab

    private var memoryTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HermesSurfacePanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Memory Settings")
                        .font(.headline)
                        .padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Embedding Provider")
                            .font(.subheadline.weight(.semibold))
                        TextField("e.g. openai, local", text: $embeddingProvider)
                            .textFieldStyle(.roundedBorder)
                        Text("Provider used to generate memory embeddings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Toggle("Memory Consolidation", isOn: $memoryConsolidation)
                    Text("Automatically consolidate and deduplicate memory entries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("Save Memory Settings") {
                            Task { await saveMemorySettings() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                }
                .padding(16)
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func saveMemorySettings() async {
        guard appState.dashboardAPIAvailable else { return }
        isSaving = true
        saveMessage = nil
        let fields: [String: Any] = [
            "embedding_provider": embeddingProvider,
            "memory_consolidation": memoryConsolidation
        ]
        do {
            try await appState.dashboardAPIService.patchClaudeConfig(fields)
            saveMessage = "Memory settings saved."
        } catch {
            saveMessage = "Failed: \(error.localizedDescription)"
        }
        isSaving = false
    }
}

// MARK: - ProviderRowView

private struct ProviderRowView: View {
    @Binding var provider: ProviderEntry
    let onSave: (ProviderEntry) -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let baseURL = provider.baseURL {
                    HStack {
                        Text("Base URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(baseURL)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    SecureField("Enter API key…", text: $provider.apiKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: 240)
                }
                Button("Save Key") {
                    onSave(provider)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(provider.hasKey ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(provider.name)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - ProviderEntry model

struct ProviderEntry: Identifiable {
    let id: UUID
    var name: String
    var baseURL: String?
    var apiKey: String
    var hasKey: Bool

    static let defaults: [ProviderEntry] = [
        ProviderEntry(id: UUID(), name: "Anthropic", baseURL: "https://api.anthropic.com", apiKey: "", hasKey: false),
        ProviderEntry(id: UUID(), name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "", hasKey: false),
        ProviderEntry(id: UUID(), name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", apiKey: "", hasKey: false),
        ProviderEntry(id: UUID(), name: "Ollama", baseURL: "http://localhost:11434", apiKey: "", hasKey: true)
    ]
}

// MARK: - Add Provider Sheet

private struct AddProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (ProviderEntry) -> Void

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""

    private let presets = ["Anthropic", "OpenAI", "OpenRouter", "Ollama", "Custom"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Provider")
                .font(.title3.weight(.semibold))

            Picker("Type", selection: $name) {
                ForEach(presets, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: name) { _, newValue in
                switch newValue {
                case "Anthropic": baseURL = "https://api.anthropic.com"
                case "OpenAI": baseURL = "https://api.openai.com/v1"
                case "OpenRouter": baseURL = "https://openrouter.ai/api/v1"
                case "Ollama": baseURL = "http://localhost:11434"
                default: baseURL = ""
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.caption.weight(.semibold))
                TextField("Provider name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Base URL").font(.caption.weight(.semibold))
                TextField("https://…", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key").font(.caption.weight(.semibold))
                SecureField("sk-…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(ProviderEntry(
                        id: UUID(),
                        name: name.isEmpty ? "Provider" : name,
                        baseURL: baseURL.isEmpty ? nil : baseURL,
                        apiKey: apiKey,
                        hasKey: !apiKey.isEmpty
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
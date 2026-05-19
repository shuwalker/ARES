import SwiftUI

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
                )

                configContent
            }
            .overlay(alignment: .topTrailing) {
                if isLoading && configDict.isEmpty {
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
}
import SwiftUI

struct KeysView: View {
    @EnvironmentObject private var appState: AppState
    @State private var envEntries: [EnvEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var editedValues: [String: String] = [:]

    var body: some View {
        HermesPageContainer(width: .analytics) {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Keys",
                    subtitle: "View and manage environment variables stored in .env. Secrets are masked by default — click the eye icon to reveal."
                )

                keysContent
            }
            .overlay(alignment: .topTrailing) {
                if isLoading && envEntries.isEmpty {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadEnv()
        }
    }

    @ViewBuilder
    private var keysContent: some View {
        if isLoading && envEntries.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading environment variables…", minHeight: 320)
            }
        } else if let error = errorMessage {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load keys",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if envEntries.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No environment variables",
                    systemImage: "key",
                    description: Text("Connect to a local Hermes instance to view its .env file.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            keysLoadedView
        }
    }

    private var keysLoadedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search keys…", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Text("\(envEntries.count) variable\(envEntries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    envEntries.indices.forEach { i in envEntries[i].isRevealed = true }
                } label: {
                    Label("Reveal All", systemImage: "eye")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    envEntries.indices.forEach { i in envEntries[i].isRevealed = false }
                } label: {
                    Label("Mask All", systemImage: "eye.slash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HermesSurfacePanel {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        keyRow(entry: entry)
                        if entry.id != filteredEntries.last?.id {
                            Divider()
                        }
                    }
                }
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func keyRow(entry: EnvEntry) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(entry.isSet ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            // Key name
            Text(entry.key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 200, alignment: .leading)
                .textSelection(.enabled)

            Spacer()

            // Value (masked or revealed)
            if entry.isRevealed {
                TextField("Value", text: Binding(
                    get: { editedValues[entry.key] ?? entry.value ?? "" },
                    set: { editedValues[entry.key] = $0 }
                ))
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            } else {
                Text(entry.displayValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Reveal/hide toggle
            Button {
                if let idx = envEntries.firstIndex(where: { $0.key == entry.key }) {
                    envEntries[idx].isRevealed.toggle()
                }
            } label: {
                Image(systemName: entry.isRevealed ? "eye.slash" : "eye")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var filteredEntries: [EnvEntry] {
        if searchText.isEmpty {
            return envEntries
        }
        return envEntries.filter { $0.key.localizedCaseInsensitiveCompare(searchText) == .orderedSame || $0.key.contains(searchText) }
    }

    // MARK: - Data Loading

    private func loadEnv() async {
        guard appState.activeConnection != nil, appState.dashboardAPIAvailable else {
            errorMessage = "Keys management requires a local Hermes connection or an active SSH tunnel."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await appState.dashboardAPIService.fetchEnv()
            envEntries = response.map { key, info in
                EnvEntry(key: key, value: info.redactedValue, isRevealed: false)
            }.sorted { $0.key < $1.key }
            editedValues = [:]
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
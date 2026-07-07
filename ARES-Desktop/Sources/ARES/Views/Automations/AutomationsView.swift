import ARESCore
import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject private var appState: ARESWorkspaceState
    @State private var splitLayout: ARESSplitLayout = ARESSplitLayout(
        minPrimaryWidth: 260,
        defaultPrimaryWidth: 340,
        maxPrimaryWidth: 600
    )

    @State private var searchText = ""
    @State private var filterMode: AutomationFilterMode = .all
    @State private var automations: [Automation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedAutomationID: String?
    @State private var logContent: String?
    @State private var stateContent: String?
    @State private var sourceContent: String?
    @State private var showSource = false
    @State private var isRefreshing = false

    private let service = AutomationBrowserService()

    enum AutomationFilterMode: String, CaseIterable {
        case all = "All"
        case running = "Running"
        case idle = "Idle"
    }

    var body: some View {
        ARESCollapsibleHSplitView(layout: $splitLayout, detailMinWidth: 460) {
            VStack(alignment: .leading, spacing: 18) {
                ARESPageHeader(
                    title: "Automations",
                    subtitle: "Manage runnable scripts, view logs, and control automation processes."
                ) {
                    ARESExpandableSearchField(
                        text: $searchText,
                        prompt: L10n.string("Search automations"),
                        expandedWidth: 220,
                        focusRequestID: appState.searchFocusRequestID
                    )
                    .fixedSize(horizontal: true, vertical: false)

                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                }

                filterBar
                automationsContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        } detail: {
            detailContent
                .hermesSplitDetailColumn(minWidth: 460, idealWidth: 580)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await refresh()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker(L10n.string("Filter"), selection: $filterMode) {
                ForEach(AutomationFilterMode.allCases, id: \.self) { mode in
                    Text(L10n.string(mode.rawValue)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - List Content

    @ViewBuilder
    private var automationsContent: some View {
        if isLoading && automations.isEmpty {
            ARESSurfacePanel {
                ARESLoadingState(
                    label: "Discovering scripts…",
                    minHeight: 300
                )
            }
        } else if let errorMessage, automations.isEmpty {
            ARESSurfacePanel {
                ContentUnavailableView(
                    "Unable to discover automations",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if automations.isEmpty {
            ARESSurfacePanel {
                ContentUnavailableView(
                    "No scripts found",
                    systemImage: "gearshape",
                    description: Text("No runnable Python or shell scripts were found in ~/.hermes/scripts/.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            ARESSurfacePanel(
                title: panelTitle,
                subtitle: "Select a script to inspect its status, logs, and companion files."
            ) {
                if filteredAutomations.isEmpty {
                    ContentUnavailableView(
                        L10n.string("No matching automations"),
                        systemImage: "magnifyingglass",
                        description: Text(L10n.string("Try searching by name, filename, or description."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(filteredAutomations) { automation in
                                AutomationCardRow(
                                    automation: automation,
                                    isSelected: selectedAutomationID == automation.id
                                ) {
                                    selectedAutomationID = automation.id
                                    loadDetail(for: automation)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isRefreshing {
                    ARESLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let automation = selectedAutomation {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    ARESSurfacePanel {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(automation.name)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    Text(automation.filePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 12)
                                AutomationStatusBadge(automation: automation)
                            }

                            if let desc = automation.description {
                                Text(desc)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                // Start / Stop
                                if automation.status == .running {
                                    Button(L10n.string("Stop")) {
                                        stopAutomation(automation)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                } else {
                                    Button(L10n.string("Start")) {
                                        startAutomation(automation)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                Button(L10n.string("Restart")) {
                                    stopAutomation(automation)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        startAutomation(automation)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(automation.status != .running)

                                Button(L10n.string("View Source")) {
                                    showSource = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    // Metadata
                    ARESSurfacePanel(
                        title: "Details",
                        subtitle: "Script metadata and runtime information."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ARESLabeledValue(
                                label: "Language",
                                value: automation.displayLanguage
                            )
                            if let lastModified = automation.lastModified {
                                ARESLabeledValue(
                                    label: "Last Modified",
                                    value: lastModified.formatted(.dateTime.month().day().year().hour().minute())
                                )
                            }
                            if let size = automation.fileSize {
                                ARESLabeledValue(
                                    label: "File Size",
                                    value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                                )
                            }
                            if let pid = automation.runningPID {
                                ARESLabeledValue(
                                    label: "PID",
                                    value: "\(pid)",
                                    isMonospaced: true
                                )
                            }
                        }
                    }

                    // Companion Files
                    if !automation.companionFiles.isEmpty {
                        ARESSurfacePanel(
                            title: "Companion Files",
                            subtitle: "Logs, state, and configuration files alongside this script."
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(automation.companionFiles) { companion in
                                    CompanionFileRow(
                                        companion: companion,
                                        logContent: companion.kind == .log ? logContent : nil,
                                        stateContent: companion.kind == .state ? stateContent : nil
                                    )
                                }
                            }
                        }
                    }

                    // Inline Log Preview (if log available)
                    if let logContent, !logContent.isEmpty {
                        ARESSurfacePanel(
                            title: "Recent Log Output",
                            subtitle: "Last 100 lines from the log companion file."
                        ) {
                            ScrollView {
                                Text(logContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 300)
                        }
                    }

                    // Inline State Preview (if state available)
                    if let stateContent, !stateContent.isEmpty {
                        ARESSurfacePanel(
                            title: "State",
                            subtitle: "Current state data from the companion file."
                        ) {
                            ScrollView {
                                Text(stateContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .sheet(isPresented: $showSource) {
                if let source = sourceContent {
                    NavigationStack {
                        ScrollView {
                            Text(source)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .navigationTitle(automation.filename)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.string("Done")) { showSource = false }
                            }
                        }
                    }
                    .frame(minWidth: 600, minHeight: 400)
                }
            }
        } else {
            ARESSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Select an automation"),
                    systemImage: "gearshape",
                    description: Text(L10n.string("Choose a script from the list to inspect its status, logs, and companion files."))
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
    }

    // MARK: - Computed

    private var filteredAutomations: [Automation] {
        automations.filter { automation in
            switch filterMode {
            case .all: break
            case .running: guard automation.status == .running else { return false }
            case .idle: guard automation.status != .running else { return false }
            }
            return automation.matchesSearch(searchText)
        }
    }

    private var panelTitle: String {
        let total = automations.count
        let filtered = filteredAutomations.count
        let isFiltering = filterMode != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isFiltering {
            return L10n.string("Automations (%@ of %@)", "\(filtered)", "\(total)")
        }
        return L10n.string("Automations (%@)", "\(total)")
    }

    private var selectedAutomation: Automation? {
        guard let id = selectedAutomationID else { return nil }
        return automations.first(where: { $0.id == id })
    }

    // MARK: - Actions

    private func refresh() async {
        isRefreshing = true
        let discovered = await service.discoverAutomations()
        automations = discovered
        isLoading = false
        isRefreshing = false
        errorMessage = nil

        // Reload detail if an automation is selected
        if let id = selectedAutomationID,
           let automation = automations.first(where: { $0.id == id }) {
            loadDetail(for: automation)
        }
    }

    private func loadDetail(for automation: Automation) {
        logContent = nil
        stateContent = nil
        sourceContent = nil

        // Load log
        if let logCompanion = automation.companionFiles.first(where: { $0.kind == .log }) {
            logContent = service.readLog(for: logCompanion)
        }

        // Load state
        if let stateCompanion = automation.companionFiles.first(where: { $0.kind == .state }) {
            stateContent = service.readState(for: stateCompanion)
        }

        // Load source
        sourceContent = service.readSource(automation)
    }

    private func startAutomation(_ automation: Automation) {
        do {
            try service.start(automation)
            // Refresh after a short delay to pick up the new PID
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task { await refresh() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAutomation(_ automation: Automation) {
        do {
            try service.stop(automation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task { await refresh() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Card Row

private struct AutomationCardRow: View {
    let automation: Automation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(automation.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(automation.filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    AutomationStatusBadge(automation: automation)
                    ARESBadge(text: automation.displayLanguage, tint: .secondary)
                }

                if automation.companionFiles.count > 0 {
                    HStack(spacing: 6) {
                        ForEach(automation.companionFiles.prefix(3)) { companion in
                            ARESBadge(text: companion.kind.displayLabel, tint: .secondary)
                        }
                        if automation.companionFiles.count > 3 {
                            ARESBadge(text: "+\(automation.companionFiles.count - 3)", tint: .secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.12 : 0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

private struct AutomationStatusBadge: View {
    let automation: Automation

    private var tintColor: Color {
        switch automation.status {
        case .running: return .green
        case .idle:    return .secondary
        case .stopped: return .orange
        case .error:   return .red
        case .unknown: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tintColor)
                .frame(width: 6, height: 6)
            Text(automation.statusLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(tintColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tintColor.opacity(0.12), in: Capsule())
    }
}

// MARK: - Companion File Row

private struct CompanionFileRow: View {
    let companion: AutomationCompanionFile
    let logContent: String?
    let stateContent: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: companion.kind.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(companion.filename)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    if let size = companion.fileSize {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                ARESBadge(text: companion.kind.displayLabel, tint: .secondary)
            }

            // Inline preview for state files
            if companion.kind == .state, let stateContent, !stateContent.isEmpty {
                Text(String(stateContent.prefix(200)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 6)
    }
}
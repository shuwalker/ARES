import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.5)

            if appState.isLoadingTools && appState.tools.isEmpty {
                HermesLoadingState(label: "Loading tools…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.toolsError, appState.tools.isEmpty {
                errorView(error)
            } else if appState.tools.isEmpty {
                emptyState
            } else {
                toolList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if appState.tools.isEmpty {
                await appState.loadTools()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Tools"))
                .font(.headline)

            Spacer()

            if appState.isLoadingTools && !appState.tools.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8, anchor: .center)
            }

            Text(L10n.string("%@ tools", "\(appState.tools.count)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                Task { await appState.loadTools() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Refresh tools"))
            .disabled(appState.isLoadingTools)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Tool list

    private var toolList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let error = appState.toolsError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)

                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                ForEach(appState.tools) { tool in
                    ToolRow(tool: tool) { enabled in
                        Task {
                            await appState.setToolEnabled(name: tool.name, enabled: enabled)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text(L10n.string("No tools found"))
                .font(.headline)

            Text(L10n.string("Available Hermes tools will appear here once discovered."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(L10n.string("Unable to load tools"))
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                Task { await appState.loadTools() }
            } label: {
                Label(L10n.string("Try Again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ToolRow

private struct ToolRow: View {
    let tool: ToolSummary
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wrench")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let description = tool.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { tool.enabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(HermesTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
    }
}

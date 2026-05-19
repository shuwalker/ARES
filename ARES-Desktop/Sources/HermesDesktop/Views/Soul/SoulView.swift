import SwiftUI

struct SoulView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editableContent = ""
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.5)

            if !hasLoaded && appState.soulContent == nil && appState.soulError == nil {
                HermesLoadingState(label: "Loading SOUL.md…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.soulError {
                errorView(error)
            } else {
                editorArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !hasLoaded else { return }
            await appState.loadSoul()
            if let content = appState.soulContent {
                editableContent = content
            }
            hasLoaded = true
        }
        .onChange(of: appState.soulContent) { _, newValue in
            if let newValue, !appState.isSavingSoul {
                editableContent = newValue
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Soul"))
                .font(.headline)

            Spacer()

            Text(L10n.string("%@ characters", "\(editableContent.count)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if appState.isSavingSoul {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8, anchor: .center)
            }

            Button {
                Task {
                    await appState.loadSoul()
                    if let content = appState.soulContent {
                        editableContent = content
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Reload SOUL.md"))
            .disabled(appState.isSavingSoul)

            Button {
                Task {
                    await appState.saveSoul(editableContent)
                }
            } label: {
                Label(L10n.string("Save"), systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isSavingSoul || editableContent == (appState.soulContent ?? ""))
            .help(L10n.string("Save SOUL.md to the remote host"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    // MARK: - Editor

    private var editorArea: some View {
        VStack(spacing: 0) {
            if let error = appState.soulError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            TextEditor(text: $editableContent)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(L10n.string("Unable to load SOUL.md"))
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                Task {
                    await appState.loadSoul()
                    if let content = appState.soulContent {
                        editableContent = content
                    }
                }
            } label: {
                Label(L10n.string("Try Again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingEntry: MemoryEntry?
    @State private var editDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.5)

            if appState.isLoadingMemory && appState.memoryEntries.isEmpty {
                HermesLoadingState(label: "Loading memory…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.memoryError, appState.memoryEntries.isEmpty {
                errorView(error)
            } else if appState.memoryEntries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingEntry) { entry in
            EditMemorySheet(
                entry: entry,
                draft: $editDraft
            ) { newContent in
                Task {
                    await appState.updateMemoryEntry(id: entry.id, content: newContent)
                }
            }
        }
        .task {
            if appState.memoryEntries.isEmpty {
                await appState.loadMemory()
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Memory"))
                .font(.headline)

            Spacer()

            if appState.isLoadingMemory && !appState.memoryEntries.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8, anchor: .center)
            }

            Text(L10n.string("%@ entries", "\(appState.memoryEntries.count)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                Task { await appState.loadMemory() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Refresh memory entries"))
            .disabled(appState.isLoadingMemory)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Entry list

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let error = appState.memoryError {
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

                ForEach(appState.memoryEntries) { entry in
                    MemoryEntryRow(
                        entry: entry,
                        onEdit: {
                            editDraft = entry.content
                            editingEntry = entry
                        },
                        onDelete: {
                            Task { await appState.deleteMemoryEntry(id: entry.id) }
                        }
                    )
                }
            }
            .padding(14)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "brain")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text(L10n.string("No memory entries"))
                .font(.headline)

            Text(L10n.string("Memory entries saved by Hermes will appear here."))
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

            Text(L10n.string("Unable to load memory"))
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                Task { await appState.loadMemory() }
            } label: {
                Label(L10n.string("Try Again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - MemoryEntryRow

private struct MemoryEntryRow: View {
    let entry: MemoryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(entry.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if isHovering {
                    HStack(spacing: 4) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.string("Edit entry"))

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.string("Delete entry"))
                    }
                    .transition(.opacity)
                }
            }

            if let source = entry.source, !source.isEmpty {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let createdAt = entry.createdAt, !createdAt.isEmpty {
                Text(createdAt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
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
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .contextMenu {
            Button(L10n.string("Edit"), action: onEdit)
            Button(L10n.string("Delete"), role: .destructive, action: onDelete)
        }
    }
}

// MARK: - EditMemorySheet

private struct EditMemorySheet: View {
    let entry: MemoryEntry
    @Binding var draft: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("Edit Memory Entry"))
                .font(.headline)

            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }

            HStack {
                Spacer()

                Button(L10n.string("Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string("Save")) {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

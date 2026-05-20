import SwiftUI

// MARK: - WorkflowPresetsView

/// Displays locally-stored workflow prompt presets and allows the user to create,
/// delete, and launch them into the chat section.
struct WorkflowPresetsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var presets: [StoredWorkflowPreset] = []
    @State private var showNewPresetSheet = false
    @State private var presetToDelete: StoredWorkflowPreset?
    @State private var showDeleteConfirmation = false

    @StateObject private var store = WorkflowPresetStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HermesPageHeader(
                title: "Workflows",
                subtitle: "Saved prompt presets that open in the Chat section with a single tap."
            ) {
                Button {
                    showNewPresetSheet = true
                } label: {
                    Label(L10n.string("New Preset"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            presetsContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .onAppear {
            presets = store.load()
        }
        .sheet(isPresented: $showNewPresetSheet) {
            NewWorkflowPresetSheet(
                availableSkills: appState.skills.map(\.slug),
                onSave: { preset in
                    store.add(preset)
                    presets = store.load()
                }
            )
            .task {
                if appState.skills.isEmpty {
                    await appState.loadSkills()
                }
            }
        }
        .alert(L10n.string("Delete preset?"), isPresented: $showDeleteConfirmation, presenting: presetToDelete) { preset in
            Button(L10n.string("Delete"), role: .destructive) {
                store.delete(id: preset.id)
                presets = store.load()
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { preset in
            Text(L10n.string("%@ will be removed from this Mac. This cannot be undone.", preset.name))
        }
    }

    @ViewBuilder
    private var presetsContent: some View {
        if presets.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No saved presets"),
                    systemImage: "checklist",
                    description: Text(L10n.string("Create a reusable prompt preset to quickly populate the Chat input."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            HermesSurfacePanel(title: L10n.string("Presets (%@)", "\(presets.count)")) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(presets) { preset in
                            WorkflowPresetCard(preset: preset) {
                                launchPreset(preset)
                            } onDelete: {
                                presetToDelete = preset
                                showDeleteConfirmation = true
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func launchPreset(_ preset: StoredWorkflowPreset) {
        appState.pendingChatInput = preset.prompt
        appState.requestSectionSelection(.chat)
    }
}

// MARK: - WorkflowPresetCard

private struct WorkflowPresetCard: View {
    let preset: StoredWorkflowPreset
    let onLaunch: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !preset.promptPreview.isEmpty {
                    Text(preset.promptPreview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                if !preset.attachedSkills.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(preset.attachedSkills.prefix(4)), id: \.self) { skill in
                            SkillChip(text: skill)
                        }

                        if preset.attachedSkills.count > 4 {
                            Text(L10n.string("+%@", "\(preset.attachedSkills.count - 4)"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onLaunch) {
                Label(L10n.string("Use"), systemImage: "arrow.up.right.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help(L10n.string("Load this preset into Chat"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(isHovering ? Color.secondary.opacity(0.07) : HermesTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(L10n.string("Use in Chat"), action: onLaunch)
            Divider()
            Button(L10n.string("Delete"), role: .destructive, action: onDelete)
        }
    }
}

// MARK: - NewWorkflowPresetSheet

private struct NewWorkflowPresetSheet: View {
    let availableSkills: [String]
    let onSave: (StoredWorkflowPreset) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var prompt = ""
    @State private var selectedSkills: Set<String> = []
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string("New Workflow Preset"))
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Name"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(L10n.string("Preset name"), text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Prompt"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 120, maxHeight: 240)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    }
            }

            if !availableSkills.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("Skills"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(availableSkills, id: \.self) { skill in
                                Toggle(skill, isOn: Binding(
                                    get: { selectedSkills.contains(skill) },
                                    set: { isOn in
                                        if isOn {
                                            selectedSkills.insert(skill)
                                        } else {
                                            selectedSkills.remove(skill)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.subheadline)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                    .padding(8)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            if let error = validationError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button(L10n.string("Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string("Save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            validationError = L10n.string("Preset name is required.")
            return
        }

        guard !trimmedPrompt.isEmpty else {
            validationError = L10n.string("Prompt text is required.")
            return
        }

        let preset = StoredWorkflowPreset(
            name: trimmedName,
            prompt: trimmedPrompt,
            attachedSkills: selectedSkills.sorted()
        )
        onSave(preset)
        dismiss()
    }
}


private struct SkillChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
    }
}

import AppKit
import SwiftUI

struct KanbanBoardEditorView: View {
    @Binding var draft: KanbanBoardDraft
    let errorMessage: String?
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HermesSurfacePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.string("New Kanban Board"))
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(L10n.string("The board will be created on the active Hermes host over SSH."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button(L10n.string("Create Board")) {
                                Task { await onSave() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving || draft.validationError != nil)

                            Button(L10n.string("Cancel"), action: onCancel)
                                .buttonStyle(.bordered)
                                .disabled(isSaving)

                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if let validationError = draft.validationError {
                            HermesValidationMessage(text: validationError)
                        }
                    }
                }

                if let errorMessage {
                    KanbanWarningBanner(message: errorMessage)
                }

                HermesSurfacePanel(title: "Board") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            KanbanFormField(label: "Slug") {
                                TextField(L10n.string("project-alpha"), text: $draft.slug)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }

                            KanbanFormField(label: "Name") {
                                TextField(L10n.string("Project Alpha"), text: $draft.name)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        KanbanFormField(label: "Description") {
                            TextEditor(text: $draft.description)
                                .font(.body)
                                .frame(minHeight: 96)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                }
                        }

                        Toggle(L10n.string("Make remote current board"), isOn: $draft.switchAfterCreate)
                            .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }
}

struct KanbanTaskEditorView: View {
    @Binding var draft: KanbanTaskDraft
    let errorMessage: String?
    let isSaving: Bool
    let assignees: [String]
    let onCancel: () -> Void
    let onSave: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HermesSurfacePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.string("New Kanban Task"))
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(L10n.string("The task will be created in the selected Hermes Kanban board over SSH."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button(L10n.string("Create Task")) {
                                Task { await onSave() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving || draft.validationError != nil)

                            Button(L10n.string("Cancel"), action: onCancel)
                                .buttonStyle(.bordered)
                                .disabled(isSaving)

                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if let validationError = draft.validationError {
                            HermesValidationMessage(text: validationError)
                        }
                    }
                }

                if let errorMessage {
                    KanbanWarningBanner(message: errorMessage)
                }

                HermesSurfacePanel(
                    title: "Task",
                    subtitle: "Describe the work and optionally assign it to a Hermes profile."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        KanbanFormField(label: "Title") {
                            TextField(L10n.string("Investigate failing release check"), text: $draft.title)
                                .textFieldStyle(.roundedBorder)
                        }

                        KanbanFormField(label: "Body") {
                            TextEditor(text: $draft.body)
                                .font(.body)
                                .frame(minHeight: 160)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                }
                        }

                        HStack(alignment: .top, spacing: 14) {
                            KanbanFormField(label: "Assignee") {
                                ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "researcher")
                            }

                            KanbanFormField(label: "Tenant") {
                                TextField(L10n.string("optional"), text: $draft.tenant)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(alignment: .top, spacing: 16) {
                            KanbanFormField(label: "Priority") {
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField("0", value: $draft.priority, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 96)

                                    Text(L10n.string("Higher values sort first. 0 is the Hermes default."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            KanbanFormField(label: "Max retries") {
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField(L10n.string("board default"), text: $draft.maxRetriesText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 120)

                                    Text(L10n.string("Leave empty to inherit the board failure limit. Set a value above 0 to override it for this task."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Toggle(L10n.string("Start in triage"), isOn: $draft.startsInTriage)
                            .toggleStyle(.checkbox)

                        KanbanFormField(label: "Skills") {
                            TextField(L10n.string("deploy-check, release-notes"), text: $draft.skillsText)
                                .textFieldStyle(.roundedBorder)
                        }

                        KanbanFormField(label: "Parents") {
                            TextField(L10n.string("t_parent_a, t_parent_b"), text: $draft.parentIDsText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }
}

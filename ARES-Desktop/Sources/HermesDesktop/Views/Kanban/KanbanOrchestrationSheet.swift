import AppKit
import SwiftUI

struct KanbanOrchestrationDraft: Equatable {
    var maxConcurrentTasksText: String = ""
    var autoDispatch: Bool = false
    var dispatchIntervalSecondsText: String = ""

    init() {}

    init(from config: KanbanOrchestrationConfig?) {
        maxConcurrentTasksText = config?.maxConcurrentTasks.map(String.init) ?? ""
        autoDispatch = config?.autoDispatch ?? false
        dispatchIntervalSecondsText = config?.dispatchIntervalSeconds.map(String.init) ?? ""
    }

    func toConfig() -> KanbanOrchestrationConfig {
        KanbanOrchestrationConfig(
            maxConcurrentTasks: Int(maxConcurrentTasksText.trimmingCharacters(in: .whitespacesAndNewlines)),
            autoDispatch: autoDispatch,
            dispatchIntervalSeconds: Int(dispatchIntervalSecondsText.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }
}

struct KanbanOrchestrationSheet: View {
    @Binding var draft: KanbanOrchestrationDraft
    let config: KanbanOrchestrationConfig?
    let isLoading: Bool
    let errorMessage: String?
    let onSave: (KanbanOrchestrationDraft) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Orchestration"))
                        .font(.title3.weight(.semibold))

                    Text(L10n.string("Configure how agents dispatch and run Kanban tasks."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            if isLoading && config == nil {
                HermesLoadingState(label: "Loading orchestration config…", minHeight: 180)
                    .padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let errorMessage {
                            KanbanWarningBanner(message: errorMessage)
                        }

                        HermesSurfacePanel(title: "Settings") {
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle(L10n.string("Auto-dispatch"), isOn: $draft.autoDispatch)
                                    .toggleStyle(.switch)

                                KanbanFormField(label: "Max concurrent tasks") {
                                    TextField(L10n.string("e.g. 4"), text: $draft.maxConcurrentTasksText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 140)
                                }

                                KanbanFormField(label: "Dispatch interval (seconds)") {
                                    TextField(L10n.string("e.g. 30"), text: $draft.dispatchIntervalSecondsText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 140)
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Button(L10n.string("Save")) {
                                onSave(draft)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isLoading)

                            Button(L10n.string("Cancel"), action: onDismiss)
                                .buttonStyle(.bordered)

                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 460, maxWidth: 520, minHeight: 340)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

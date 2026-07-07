import SwiftUI
import ARESCore

struct EventBusPickerWidget: View {
    @EnvironmentObject var appState: ARESAppState
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Bus (Nervous System)").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)

            Menu {
                Section("Native") {
                    Button {
                        switchEventBus(to: .local)
                    } label: {
                        Text("Local NotificationCenter").font(.system(.body, design: .monospaced))
                    }
                }
                
                Section("Distributed") {
                    Button {
                        switchEventBus(to: .jros(socketPath: "/tmp/ares_jros.sock"))
                    } label: {
                        Text("JROS Bridge").font(.system(.body, design: .monospaced))
                    }
                }

                Section("Testing") {
                    Button {
                        switchEventBus(to: .dummy)
                    } label: {
                        Text("Dummy Fallback").font(.system(.body, design: .monospaced))
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label(for: appState.activeEventBusImpl))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Text(description(for: appState.activeEventBusImpl))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.down").foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            }
            .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func label(for impl: EventBusImpl) -> String {
        switch impl {
        case .dummy: return "Dummy Fallback"
        case .local: return "Local EventBus"
        case .jros: return "JROS Bridge"
        }
    }

    private func description(for impl: EventBusImpl) -> String {
        switch impl {
        case .dummy: return "Isolated dummy for testing."
        case .local: return "Native NotificationCenter for fast UI updates."
        case .jros: return "Unix-socket bridge to the JROS runtime."
        }
    }

    private func switchEventBus(to impl: EventBusImpl) {
        isLoading = true
        Task {
            await MainActor.run {
                appState.switchEventBus(impl)
                isLoading = false
            }
        }
    }
}

import SwiftUI

struct BootstrapView: View {
    @EnvironmentObject private var appState: ARESAppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.linearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("Welcome to ARES")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Checking your system before we begin.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            Divider()

            // Dependency list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ARESDependency.allCases) { dep in
                        DependencyRow(
                            name: dep.name,
                            status: appState.dependencies[dep] ?? .checking
                        )
                        Divider().padding(.leading, 44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }

            Spacer()

            // Error message
            if let error = appState.installError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Skip") {
                    appState.completeBootstrap()
                }
                .keyboardShortcut(.escape)

                Spacer()

                if !appState.isScanning && !appState.isInstalling {
                    Button("Scan") {
                        Task { await appState.scanDependencies() }
                    }
                    .buttonStyle(.bordered)

                    Button("Install Missing") {
                        Task { await appState.installMissing() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.dependencies.isEmpty)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Launch ARES") {
                    appState.completeBootstrap()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(24)
        }
        .frame(width: 560, height: 480)
        .task {
            await appState.scanDependencies()
        }
    }
}

// MARK: - Dependency Row

private struct DependencyRow: View {
    let name: String
    let status: DependencyStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.systemImage)
                .foregroundStyle(statusColor)
                .font(.title3)
                .frame(width: 20)

            Text(name)
                .font(.body)

            Spacer()

            statusLabel
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch status {
        case .installed: return .green
        case .missing:   return .secondary
        case .checking:  return .blue
        case .failed:    return .red
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .installed:
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.green)
        case .missing:
            Text("Not found")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }
}

import SwiftUI
import ARESCore

struct VisionPickerWidget: View {
    @EnvironmentObject var appState: ARESAppState
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vision Engine (Eyes)").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)

            Menu {
                Section("Native") {
                    Button {
                        switchWorld(to: .appleVision)
                    } label: {
                        Text("Apple Vision (Face Tracking)").font(.system(.body, design: .monospaced))
                    }
                    Button {
                        switchWorld(to: .screenCapture)
                    } label: {
                        Text("ScreenCaptureKit (Desktop)").font(.system(.body, design: .monospaced))
                    }
                }

                Section("Testing") {
                    Button {
                        switchWorld(to: .dummy)
                    } label: {
                        Text("Dummy Fallback").font(.system(.body, design: .monospaced))
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label(for: appState.activeWorldImpl))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Text(description(for: appState.activeWorldImpl))
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

    private func label(for impl: WorldImpl) -> String {
        switch impl {
        case .dummy: return "Dummy Fallback"
        case .appleVision: return "Apple Vision"
        case .screenCapture: return "ScreenCaptureKit"
        }
    }

    private func description(for impl: WorldImpl) -> String {
        switch impl {
        case .dummy: return "Blind dummy for testing."
        case .appleVision: return "Native face detection via webcam."
        case .screenCapture: return "Native desktop context sharing."
        }
    }

    private func switchWorld(to impl: WorldImpl) {
        isLoading = true
        Task {
            await MainActor.run {
                appState.switchWorld(impl)
                isLoading = false
            }
        }
    }
}

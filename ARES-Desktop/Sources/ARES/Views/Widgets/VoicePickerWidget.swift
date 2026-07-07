import SwiftUI
import ARESCore

struct VoicePickerWidget: View {
    @EnvironmentObject var appState: ARESAppState
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Engine (TTS & STT)").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)

            Menu {
                Section("Native") {
                    Button {
                        switchVoice(to: .system)
                    } label: {
                        Text("Apple System Voice (SFSpeech)").font(.system(.body, design: .monospaced))
                    }
                }

                Section("Testing") {
                    Button {
                        switchVoice(to: .dummy)
                    } label: {
                        Text("Dummy Fallback").font(.system(.body, design: .monospaced))
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label(for: appState.activeVoiceImpl))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Text(description(for: appState.activeVoiceImpl))
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

    private func label(for impl: VoiceImpl) -> String {
        switch impl {
        case .dummy: return "Dummy Fallback"
        case .system: return "Apple System Voice"
        }
    }

    private func description(for impl: VoiceImpl) -> String {
        switch impl {
        case .dummy: return "Silent dummy for testing."
        case .system: return "Native AVSpeechSynthesizer & SFSpeechRecognizer."
        }
    }

    private func switchVoice(to impl: VoiceImpl) {
        isLoading = true
        Task {
            await MainActor.run {
                appState.switchVoice(impl)
                isLoading = false
            }
        }
    }
}

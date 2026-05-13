import SwiftUI

struct CommandBar: View {
    @EnvironmentObject var brain: BrainConnection
    @EnvironmentObject var voice: VoiceManager
    @FocusState private var focused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Divider().background(.white.opacity(0.08))
            HStack(spacing: 10) {
                TextField("Talk to ARES...", text: $brain.inputText)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(.ultraThinMaterial)
                    .cornerRadius(9)
                    .onSubmit { brain.sendMessage(brain.inputText) }
                
                Button {
                    if voice.isListening {
                        voice.stopListening()
                        if !voice.transcript.isEmpty {
                            brain.sendMessage(voice.transcript)
                        }
                    } else {
                        voice.startListening()
                    }
                } label: {
                    Image(systemName: voice.isListening ? "waveform.circle.fill" : "mic.circle")
                        .font(.title2)
                        .foregroundColor(voice.isListening ? .green : .secondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    brain.sendMessage(brain.inputText)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(brain.inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary.opacity(0.4) : .blue)
                }
                .buttonStyle(.plain)
                .disabled(brain.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}
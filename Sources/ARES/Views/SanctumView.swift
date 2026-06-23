import SwiftUI
import WebKit

struct SanctumView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            SanctumRendererView(renderer: state.renderer)
                .ignoresSafeArea()
                .background(Color.white)

            VStack {
                Spacer()
                if state.isListening {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.black.opacity(0.3))
                        Text("Listening")
                            .font(.caption2)
                            .foregroundColor(.black.opacity(0.3))
                    }
                    .padding(.bottom, 4)
                }
            }

            VStack {
                Spacer()
                HStack(spacing: 0) {
                    TextField("", text: $state.inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(.black.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                        .padding(.horizontal, 40)
                        .onSubmit {
                            let t = state.inputText.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            state.send(t)
                        }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            state.renderer.showFloatingText("...", role: "system")
            state.speech.startListening { text in
                state.send(text)
            }
        }
    }
}

struct SanctumRendererView: NSViewRepresentable {
    let renderer: ThreeJsAvatarRenderer
    func makeNSView(context: Context) -> NSView { renderer.view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

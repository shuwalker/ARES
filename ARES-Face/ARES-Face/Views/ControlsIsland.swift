import SwiftUI

/// Floating control bar that appears in Avatar Twin mode.
///
/// Patterns from AIRI (stage-tamagotchi ControlsIsland):
///   - Compact horizontal pill with mic + mode + status
///   - Voice toggle with active/inactive states
///   - Connection indicator dot
///   - Hover to reveal expanded controls
///
/// In Manual mode this is hidden; the sidebar handles controls.
struct ControlsIsland: View {
    @EnvironmentObject var brain: BrainConnection
    @EnvironmentObject var voice: VoiceManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // ── Voice toggle ──
            voiceButton

            // ── Mic level indicator (animated when listening) ──
            if voice.isListening {
                micLevelIndicator
            }

            // ── Connection dot ──
            connectionDot

            // ── State label (hover-expands) ──
            if isHovered {
                Text(brain.agentState.rawValue.capitalized)
                    .font(.system(size: 11, weight: .medium).lowercaseSmallCaps())
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Voice Button

    private var voiceButton: some View {
        Button {
            voice.toggleListening()
        } label: {
            ZStack {
                // Active glow ring when listening
                if voice.isListening {
                    Circle()
                        .stroke(Color.green.opacity(0.4), lineWidth: 2)
                        .frame(width: 28, height: 28)
                }

                Image(systemName: voice.isListening ? "mic.fill" : "mic.slash")
                    .font(.system(size: 16, weight: voice.isListening ? .semibold : .regular))
                    .foregroundStyle(voice.isListening ? .green : .secondary)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mic Level

    /// Mic level bar driven by real audio input levels.
    private var micLevelIndicator: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.green.opacity(0.5 + Double(voice.audioLevel) * 0.5))
                    .frame(height: max(2, CGFloat(voice.audioLevel) * geo.size.height))
                    .animation(.easeInOut(duration: 0.05), value: voice.audioLevel)
            }
        }
        .frame(width: 3, height: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .stroke(Color.green.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Connection

    private var connectionDot: some View {
        Circle()
            .fill(brain.backendConnected ? Color.green : Color.red.opacity(0.7))
            .frame(width: 6, height: 6)
            .shadow(color: brain.backendConnected ? Color.green.opacity(0.5) : Color.red.opacity(0.3), radius: 3)
    }
}
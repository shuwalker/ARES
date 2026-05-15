import SwiftUI

/// Top bar with a two-position immersion slider and status indicators.
///
/// The slider has exactly two stops:
///   - **Manual**: AI as tool. Full operator dashboard visible.
///   - **Avatar Twin**: AI as person. Face fills screen, voice-first, minimal chrome.
///
/// Tapping the slider thumb or dragging it snaps to the nearest stop.
/// Status badges (connection, state, expression) sit on the right.
struct ImmersionBar: View {
    @EnvironmentObject var brain: BrainConnection
    @Binding var cognitiveExpanded: Bool

    var body: some View {
        HStack(spacing: 10) {
            // ── Immersion Slider ──
            immersionSlider

            Spacer()

            // ── Status Indicators ──
            CognitiveHeartbeatPill(isExpanded: $cognitiveExpanded)

            Text(brain.agentState.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(brain.avatarExpression.rawValue.capitalized)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))

            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    // MARK: - Immersion Slider

    /// A segmented slider with two labeled stops.
    /// Thumb position is bound to `brain.immersionLevel`.
    /// Tapping either label or dragging snaps to the nearest stop.
    private var immersionSlider: some View {
        HStack(spacing: 0) {
            // Manual label
            immersionLabel(
                level: .manual,
                icon: ImmersionLevel.manual.icon,
                text: ImmersionLevel.manual.label
            )

            // Track + thumb
            immersionTrack

            // Avatar Twin label
            immersionLabel(
                level: .avatarTwin,
                icon: ImmersionLevel.avatarTwin.icon,
                text: ImmersionLevel.avatarTwin.label
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func immersionLabel(level: ImmersionLevel, icon: String, text: String) -> some View {
        let isSelected = brain.immersionLevel == level
        return Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                brain.immersionLevel = level
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                Text(text)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    /// The sliding thumb between the two labels.
    /// 0 = manual (left), 1 = avatarTwin (right).
    private var immersionTrack: some View {
        GeometryReader { geo in
            let isManual = brain.immersionLevel == .manual
            let thumbX: CGFloat = isManual ? 0 : geo.size.width - 4

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)

                // Animated thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: .accentColor.opacity(0.5), radius: 3)
                    .offset(x: thumbX)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: brain.immersionLevel)
            }
            .frame(width: geo.size.width, height: 10)
        }
        .frame(width: 24, height: 10)
    }

    // MARK: - State Color

    var stateColor: Color {
        switch brain.agentState {
        case .idle:      return .blue
        case .awakened:  return .cyan
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .purple
        case .sleeping:  return .gray
        }
    }
}
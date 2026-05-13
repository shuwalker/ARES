import SwiftUI

// Collapsed pill that lives inside ImmersionBar. Tap to expand into the
// full panel below. Reads from `BrainConnection.cognitive`, which is
// pushed by the server on every phase transition.

struct CognitiveHeartbeatPill: View {
    @EnvironmentObject var brain: BrainConnection
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                phaseDot
                Text(phaseLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if brain.cognitive.running {
                    Text("· c\(brain.cognitive.loop.cycle)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Cognitive activity")
    }

    private var phaseLabel: String {
        brain.cognitive.running
            ? brain.cognitive.loop.phase.uppercased()
            : "IDLE"
    }

    private var phaseDot: some View {
        Circle()
            .fill(phaseColor)
            .frame(width: 6, height: 6)
            .shadow(color: phaseColor.opacity(0.7), radius: 2)
    }

    private var phaseColor: Color {
        if !brain.cognitive.running { return .gray }
        switch brain.cognitive.loop.phase {
        case "perceive": return .cyan
        case "think":    return .orange
        case "act":      return .purple
        case "reflect":  return .green
        default:         return .blue
        }
    }
}

// Full panel, shown below the ImmersionBar when expanded. Four lines:
//   ARES is THINKING
//       cycle 47 · urgency: med · 2.1s
//       budget: 73%
//       errors: 0
//
// More fields can be added as the snapshot schema grows — the panel
// renders only what it knows.

struct CognitiveActivityPanel: View {
    @EnvironmentObject var brain: BrainConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.headline.monospaced())
                .foregroundStyle(headlineColor)

            HStack(spacing: 10) {
                Label("cycle \(brain.cognitive.loop.cycle)", systemImage: "arrow.triangle.2.circlepath")
                Label(brain.cognitive.loop.urgency, systemImage: "gauge.with.dots.needle.50percent")
                Label(elapsedLabel, systemImage: "clock")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            BudgetBar(remaining: brain.cognitive.loop.budgetRemaining)

            if !brain.cognitive.errors.isEmpty {
                Text("errors: \(brain.cognitive.errors.count)")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private var headline: String {
        if !brain.cognitive.running { return "ARES is IDLE" }
        let phase = brain.cognitive.loop.phase.uppercased()
        return "ARES is \(phase)"
    }

    private var headlineColor: Color {
        brain.cognitive.running ? .primary : .secondary
    }

    private var elapsedLabel: String {
        let ms = brain.cognitive.loop.elapsedMs
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }
}

private struct BudgetBar: View {
    let remaining: Double  // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, remaining))))
            }
        }
        .frame(height: 3)
    }

    private var barColor: Color {
        if remaining < 0.15 { return .red }
        if remaining < 0.4  { return .orange }
        return .blue
    }
}

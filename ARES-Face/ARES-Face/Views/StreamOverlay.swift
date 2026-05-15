import SwiftUI

/// Floating overlay for Avatar Twin mode showing real-time agent state.
///
/// Compact pill that auto-expands on hover. Shows:
/// - State indicator (thinking, listening, speaking) with colored dot + label
/// - Tool calls in progress as badges
/// - Memory recall count
/// - Streaming token counter
/// - Expandable to show the last message or tool output
struct StreamOverlay: View {
    @EnvironmentObject var brain: BrainConnection
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // ── Main pill ──
            mainPill

            // ── Expanded detail (hover to reveal) ──
            if isExpanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Main Pill

    private var mainPill: some View {
        HStack(spacing: 8) {
            // State dot
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(stateColor.opacity(0.4), lineWidth: 2)
                        .scaleEffect(brain.agentState == .thinking ? 1.5 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: brain.agentState == .thinking)
                )

            // State label
            Text(brain.agentState.rawValue.capitalized)
                .font(.system(size: 11, weight: .medium).lowercaseSmallCaps())
                .foregroundStyle(.primary)

            // Tool call badge
            if activeToolCount > 0 {
                toolBadge
            }

            // Memory badge
            if !brain.cognitive.memoryRecall.isEmpty {
                memoryBadge
            }

            // Token count
            if brain.agentState == .thinking || brain.agentState == .speaking {
                tokenCounter
            }

            // Expand button
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
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
            if !hovering && isExpanded {
                withAnimation(.easeInOut(duration: 0.3).delay(2)) {
                    isExpanded = false
                }
            }
        }
    }

    // MARK: - Tool Badge

    private var toolBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 9))
            Text("\(activeToolCount)")
                .font(.system(size: 10, design: .monospaced).weight(.medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(4)
    }

    // MARK: - Memory Badge

    private var memoryBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 9))
            Text("\(brain.cognitive.memoryRecall.count)")
                .font(.system(size: 10, design: .monospaced).weight(.medium))
        }
        .foregroundStyle(.cyan)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.cyan.opacity(0.12))
        .cornerRadius(4)
    }

    // MARK: - Token Counter

    private var tokenCounter: some View {
        Text("\(brain.streamTokenCount)t")
            .font(.system(size: 10, design: .monospaced).weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    // MARK: - Expanded Detail

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Last tool output
            if let lastTool = lastActiveTool {
                HStack(spacing: 6) {
                    Circle()
                        .fill(branchColor(lastTool.status))
                        .frame(width: 6, height: 6)
                    Text(lastTool.label)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(lastTool.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if lastTool.durationMs > 0 {
                    Text("\(lastTool.durationMs)ms")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
            }

            // Last message
            if let lastMsg = brain.messages.last {
                HStack(spacing: 4) {
                    Image(systemName: lastMsg.isUser ? "person.fill" : "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(lastMsg.isUser ? .blue : .cyan)
                    Text(String(lastMsg.text.prefix(120)))
                        .font(.system(size: 11))
                        .lineLimit(3)
                }
            }

            // Memory recall tags
            if !brain.cognitive.memoryRecall.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(brain.cognitive.memoryRecall.prefix(5)) { hit in
                            Text(hit.kind)
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        )
    }

    // MARK: - Computed Properties

    private var stateColor: Color {
        switch brain.agentState {
        case .idle:      return .blue
        case .awakened:  return .cyan
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .purple
        case .sleeping:  return .gray
        }
    }

    private var activeToolCount: Int {
        brain.cognitive.thought?.branches.filter { $0.status == "running" }.count ?? 0
    }

    private var lastActiveTool: ThoughtNode? {
        brain.cognitive.thought?.branches.last
    }

    private func branchColor(_ status: String) -> Color {
        switch status {
        case "running":  return .orange
        case "success":  return .green
        case "failed":   return .red
        default:         return .secondary
        }
    }
}
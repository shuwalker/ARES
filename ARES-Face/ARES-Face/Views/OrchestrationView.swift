import SwiftUI

/// Real-time orchestration view showing what ARES is doing RIGHT NOW.
///
/// This is NOT a log viewer. It's a live cockpit:
/// - Cognitive pipeline bar (thinking → tool → response)
/// - Tool calls with expand/collapse for command, stdout, exit code
/// - Memory recall hits as tags
/// - Active tasks as a progress checklist
/// - Streaming tokens counter
///
/// Driven entirely by BrainConnection's published properties.
struct OrchestrationView: View {
    @EnvironmentObject var brain: BrainConnection
    @State private var expandedTools: Set<String> = []
    @State private var showMemoryHits = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ──
            orchestraHeader
            Divider().background(.white.opacity(0.08))

            // ── Pipeline Bar ──
            pipelineBar
                .padding(.vertical, 8)
                .padding(.horizontal, 14)

            Divider().background(.white.opacity(0.06))

            // ── Content ──
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Tool call timeline (Gantt chart)
                    toolTimelineSection

                    // Tool call details
                    toolCallsSection

                    // Memory recall
                    memoryRecallSection

                    // Recent messages
                    recentMessagesSection
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var orchestraHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(stateColor)
            Text("Orchestration")
                .font(.title3.weight(.semibold))
            Spacer()
            stateBadge
            if brain.streamTokenCount > 0 {
                Text("\(brain.streamTokenCount) tokens")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var stateBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
            Text(brain.agentState.rawValue.capitalized)
                .font(.caption.weight(.medium).lowercaseSmallCaps())
                .foregroundStyle(.secondary)
        }
    }

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

    // MARK: - Pipeline Bar

    private var pipelineBar: some View {
        HStack(spacing: 2) {
            pipelineStage("Think", icon: "brain", active: brain.agentState == .thinking)
            pipelineConnector
            pipelineStage("Tool", icon: "wrench.and.screwdriver", active: hasActiveTool)
            pipelineConnector
            pipelineStage("Respond", icon: "text.bubble", active: brain.agentState == .speaking)
        }
    }

    private func pipelineStage(_ label: String, icon: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(active ? .cyan : .secondary)
            Text(label)
                .font(.caption2.weight(active ? .bold : .regular))
                .foregroundStyle(active ? .white : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(active ? Color.cyan.opacity(0.15) : Color.white.opacity(0.04))
        .cornerRadius(6)
    }

    private var pipelineConnector: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.5))
    }

    private var hasActiveTool: Bool {
        brain.cognitive.thought?.branches.contains { $0.status == "running" } ?? false
    }

    // MARK: - Tool Timeline (Gantt Chart)

    /// Visual timeline showing concurrent tool calls as horizontal bars.
    /// Each bar represents a tool call, with length proportional to duration.
    /// Running tools pulse, completed tools are solid, failed tools are red.
    private var toolTimelineSection: some View {
        Group {
            if let thought = brain.cognitive.thought, !thought.branches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Timeline", icon: "timeline.view", count: thought.branches.count)
                    toolTimelineChart(branches: thought.branches)
                }
            }
        }
    }

    private func toolTimelineChart(branches: [ThoughtNode]) -> some View {
        let maxDuration = branches.map(\.durationMs).max().map { max($0, 100) } ?? 1000

        return VStack(alignment: .leading, spacing: 3) {
            ForEach(branches) { node in
                toolTimelineRow(node: node, maxDuration: maxDuration)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.15))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func toolTimelineRow(node: ThoughtNode, maxDuration: Int) -> some View {
        HStack(spacing: 6) {
            // Label
            Text(node.label.prefix(20))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
                .lineLimit(1)

            // Bar — simplified to avoid type-check timeout
            ToolTimelineBar(
                durationMs: node.durationMs,
                maxDuration: maxDuration,
                status: node.status
            )
            .frame(height: 14)

            // Duration label
            timelineDurationLabel(node: node)
        }
        .frame(height: 20)
    }

    @ViewBuilder
    private func timelineDurationLabel(node: ThoughtNode) -> some View {
        if node.durationMs > 0 {
            Text("\(node.durationMs)ms")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 42, alignment: .leading)
        } else if node.status == "running" {
            Text("...")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 42, alignment: .leading)
        }
    }

    // MARK: - Tool Calls Section

    private var toolCallsSection: some View {
        Group {
            if let thought = brain.cognitive.thought, !thought.branches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Tool Calls", icon: "terminal", count: thought.branches.count)
                    ForEach(thought.branches) { node in
                        toolCallRow(node)
                    }
                }
            }
        }
    }

    private func toolCallRow(_ node: ThoughtNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(branchColor(node.status))
                    .frame(width: 6, height: 6)
                Text(node.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if node.status == "running" {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                if node.durationMs > 0 {
                    Text("\(node.durationMs)ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expandedTools.contains(node.id) {
                            expandedTools.remove(node.id)
                        } else {
                            expandedTools.insert(node.id)
                        }
                    }
                } label: {
                    Image(systemName: expandedTools.contains(node.id) ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if expandedTools.contains(node.id) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.status)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !node.parentIds.isEmpty {
                        Text("Depends on: \(node.parentIds.joined(separator: ", "))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.03))
                .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }

    private func branchColor(_ status: String) -> Color {
        switch status {
        case "running":  return .orange
        case "success":  return .green
        case "failed":   return .red
        default:         return .secondary
        }
    }

    // MARK: - Memory Recall

    private var memoryRecallSection: some View {
        Group {
            if !brain.cognitive.memoryRecall.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Memory Recall", icon: "brain.head.profile", count: brain.cognitive.memoryRecall.count)

                    if showMemoryHits {
                        ForEach(brain.cognitive.memoryRecall) { hit in
                            memoryHitRow(hit)
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(brain.cognitive.memoryRecall.prefix(5)) { hit in
                                    memoryHitTag(hit)
                                }
                                if brain.cognitive.memoryRecall.count > 5 {
                                    Text("+\(brain.cognitive.memoryRecall.count - 5)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Button(showMemoryHits ? "Collapse" : "Show all") {
                        withAnimation { showMemoryHits.toggle() }
                    }
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                }
            }
        }
    }

    private func memoryHitTag(_ hit: MemoryHitBlock) -> some View {
        Text(hit.kind)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.cyan.opacity(0.12))
            .cornerRadius(4)
    }

    private func memoryHitRow(_ hit: MemoryHitBlock) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.kind)
                .font(.system(size: 12, weight: .medium))
            if !hit.text.isEmpty {
                Text(hit.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                Text(hit.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if hit.score > 0 {
                    Text("\(Int(hit.score * 100))% match")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.cyan.opacity(0.7))
                }
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(4)
    }

    // MARK: - Recent Messages

    private var recentMessagesSection: some View {
        Group {
            if !brain.messages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Recent", icon: "bubble.left.and.bubble.right", count: brain.messages.count)
                    ForEach(brain.messages.suffix(3)) { msg in
                        HStack(spacing: 6) {
                            Image(systemName: msg.isUser ? "person.fill" : "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(msg.isUser ? .blue : .cyan)
                            Text(msg.text)
                                .font(.caption)
                                .lineLimit(2)
                            Spacer()
                            Text(msg.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let count {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(3)
            }
        }
    }
}
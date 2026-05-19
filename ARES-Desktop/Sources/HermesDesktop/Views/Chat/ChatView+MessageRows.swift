import SwiftUI

// MARK: - DiffCodeBlockView

struct DiffCodeBlockView: View {
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(code.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(lineColor(for: line))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .textSelection(.enabled)
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return Color(nsColor: .systemPurple) }
        return .primary
    }
}

// MARK: - Markdown diff/patch block parser

/// Parses a markdown-style fenced code block with a diff or patch language tag from the
/// beginning of `text`. Returns the code content and the remainder of the string, or nil
/// if no such block is found at the start.
private func parseDiffBlock(from text: String) -> (code: String, remainder: String)? {
    // Match ``` followed by diff or patch (case-insensitive), then a newline
    let lines = text.components(separatedBy: "\n")
    guard let firstLine = lines.first else { return nil }
    let tag = firstLine.trimmingCharacters(in: .whitespaces).lowercased()
    guard tag == "```diff" || tag == "```patch" else { return nil }

    // Find the closing ```
    var codeLines: [String] = []
    var closingIndex: Int? = nil
    for i in 1..<lines.count {
        if lines[i].trimmingCharacters(in: .whitespaces) == "```" {
            closingIndex = i
            break
        }
        codeLines.append(lines[i])
    }

    guard let closing = closingIndex else {
        // Unclosed block — treat everything after the opening as code (streaming)
        let code = Array(lines.dropFirst()).joined(separator: "\n")
        return (code: code, remainder: "")
    }

    let code = codeLines.joined(separator: "\n")
    let remainder = Array(lines[(closing + 1)...]).joined(separator: "\n")
    return (code: code, remainder: remainder)
}

// MARK: - StreamingChatMessageRow

struct StreamingChatMessageRow: View {
    let message: ChatMessage
    @State private var isThinkingExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 40)

                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                    }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Hermes"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    // Extended thinking block
                    if let thinking = message.thinkingContent {
                        thinkingBlock(thinking: thinking)
                    } else if message.isStreaming {
                        // Pulsing "Thinking…" while no thinking content yet and streaming
                        streamingThinkingLabel
                    }

                    // Tool calls above assistant text
                    if !message.toolCalls.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(message.toolCalls) { toolCall in
                                ToolCallRow(toolCall: toolCall)
                            }
                        }
                    }

                    assistantBubble
                }

                Spacer(minLength: 40)
            }
        }
    }

    // Animated label shown only while the stream is active and no thinking text yet arrived
    @ViewBuilder
    private var streamingThinkingLabel: some View {
        EmptyView()
    }

    @ViewBuilder
    private func thinkingBlock(thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header / toggle row
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isThinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(message.isStreaming ? L10n.string("Thinking\u{2026}") : L10n.string("Claude's thinking"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    if message.isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    }
                    Spacer()
                    if !message.isStreaming {
                        Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(message.isStreaming)

            if isThinkingExpanded && !message.isStreaming {
                ScrollView {
                    Text(thinking)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color.secondary.opacity(0.05))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var assistantBubble: some View {
        let fullText = message.content + (message.isStreaming ? "\u{258A}" : "")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(assistantSegments(from: fullText).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let t):
                    if !t.isEmpty {
                        Text(t)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .diff(let code):
                    DiffCodeBlockView(code: code)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private enum AssistantSegment {
        case text(String)
        case diff(String)
    }

    private func assistantSegments(from text: String) -> [AssistantSegment] {
        var segments: [AssistantSegment] = []
        var remaining = text

        while !remaining.isEmpty {
            // Look for the next diff/patch fence
            let lines = remaining.components(separatedBy: "\n")
            var fenceLineIndex: Int? = nil
            for (i, line) in lines.enumerated() {
                let tag = line.trimmingCharacters(in: .whitespaces).lowercased()
                if tag == "```diff" || tag == "```patch" {
                    fenceLineIndex = i
                    break
                }
            }

            guard let fenceIdx = fenceLineIndex else {
                // No more diff blocks
                segments.append(.text(remaining))
                break
            }

            // Emit text before the fence
            let beforeLines = Array(lines[..<fenceIdx])
            let beforeText = beforeLines.joined(separator: "\n")
            if !beforeText.isEmpty {
                segments.append(.text(beforeText))
            }

            // Try to parse a diff block starting at fenceIdx
            let fromFence = Array(lines[fenceIdx...]).joined(separator: "\n")
            if let parsed = parseDiffBlock(from: fromFence) {
                segments.append(.diff(parsed.code))
                remaining = parsed.remainder
            } else {
                // Could not parse — emit the fence line as text and continue
                segments.append(.text(lines[fenceIdx]))
                remaining = Array(lines[(fenceIdx + 1)...]).joined(separator: "\n")
            }
        }

        return segments
    }
}

// MARK: - ToolCallRow

struct ToolCallRow: View {
    let toolCall: ChatToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(toolCall.name.isEmpty ? "tool" : toolCall.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                switch toolCall.status {
                case .running:
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)

                case .done:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)

                        if !toolCall.input.isEmpty || toolCall.output != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            // Expanded detail
            if isExpanded && toolCall.status == .done {
                VStack(alignment: .leading, spacing: 4) {
                    if !toolCall.input.isEmpty {
                        Group {
                            Text("Input")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)

                            Text(toolCall.input)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.06))
                        }
                    }

                    if let output = toolCall.output, !output.isEmpty {
                        Group {
                            Text("Output")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)

                            Text(output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.06))
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

// MARK: - ToolApprovalCard

enum ApprovalAction {
    case approve
    case deny
}

struct ToolApprovalCard: View {
    let approval: ToolApprovalRequest
    let onAction: (ApprovalAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.yellow)

                Text("Approve tool call")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(approval.toolName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
            }

            // Input preview
            Text(approval.toolInput)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Action buttons
            HStack(spacing: 8) {
                Spacer()

                Button {
                    onAction(.deny)
                } label: {
                    Text("Deny")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onAction(.approve)
                } label: {
                    Text("Approve")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.yellow.opacity(0.25), lineWidth: 1)
        }
    }
}

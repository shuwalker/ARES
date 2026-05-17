import SwiftUI

/// A sliding panel that shows real-time tool call activity from the Hermes gateway.
/// Toggle it on to see what tools the agent is using as they execute —
/// just like watching the TUI in terminal.
struct LiveToolActivityView: View {
    @ObservedObject var model: LiveToolActivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            eventList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "wrench.and screwdriver")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Live Tool Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            // Connection indicator
            connectionIndicator

            // Clear button
            if !model.events.isEmpty {
                Button {
                    model.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear tool activity")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.isActive ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(model.isActive ? "Connected" : "Disconnected")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Event List

    @ViewBuilder
    private var eventList: some View {
        if model.events.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.events) { event in
                            ToolEventRow(event: event)
                                .id(event.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.events.count) { _, _ in
                    // Auto-scroll to newest event
                    if let lastID = model.events.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "wrench")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No tool activity yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Tool calls will appear here in real-time\nas the agent works on your request.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tool Event Row

private struct ToolEventRow: View {
    let event: LiveToolEvent

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            statusIcon
                .frame(width: 14, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(toolDisplayName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)

                    if let context = event.context, !context.isEmpty {
                        Text("— \(context)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if case .progress(let preview) = event.status, let preview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(timeAgo)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(rowBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch event.status {
        case .started:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.cyan)
        case .progress:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Helpers

    private var toolDisplayName: String {
        // Convert snake_case tool names to readable form
        event.name
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(event.timestamp)
        if interval < 2 { return "now" }
        if interval < 60 { return "\(Int(interval))s" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(Int(interval / 3600))h"
    }

    private var rowBackground: Color {
        switch event.status {
        case .started:
            return Color.cyan.opacity(0.06)
        case .progress:
            return Color.secondary.opacity(0.04)
        case .completed:
            return Color.green.opacity(0.04)
        }
    }
}
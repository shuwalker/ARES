import SwiftUI

/// Self-improvement timeline — entity-framed view of ARES's activities.
///
/// Not a log viewer. This shows what ARES learned, what it did, what's in progress.
/// Think: Instagram Stories for an AI — glanceable, human-narrated.
struct ActivityTimelineView: View {
    @EnvironmentObject var activity: ActivityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(.white.opacity(0.08))

            // Active goals section
            if !activity.activeGoals.isEmpty {
                goalsSection
                Divider().background(.white.opacity(0.08))
            }

            // Event timeline
            if activity.events.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .task { await activity.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "timeline.view")
            Text("Activity")
                .font(.title3.weight(.semibold))
            Spacer()
            if activity.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }
            Button {
                Task { await activity.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Goals

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active Goals")
                .font(.caption.weight(.semibold).lowercaseSmallCaps())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)

            ForEach(activity.activeGoals) { goal in
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundStyle(.cyan)
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.description)
                            .font(.system(size: 12, weight: .medium))
                        Text(goal.completionCondition)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Event List

    private var eventList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(activity.events) { event in
                    EventRow(event: event)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bird")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Nothing happened yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Activity will appear here as ARES works, learns, and responds to events.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Kind icon
            Circle()
                .fill(iconColor.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(iconColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                Text(event.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Timestamp
            Text(event.timestamp, style: .relative)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var icon: String {
        switch event.kind {
        case .cronCompleted:    return "checkmark.clock"
        case .skillWritten:     return "sparkles"
        case .memoryChange:     return "brain.head.profile"
        case .goalProgress:     return "target"
        case .feedAlert:        return "exclamationmark.triangle"
        case .sessionEvent:     return "person.wave.2"
        case .selfImprovement:  return "arrow.up.circle"
        }
    }

    private var iconColor: Color {
        switch event.status {
        case .success:     return .green
        case .failure:     return .red
        case .inProgress:  return .yellow
        }
    }
}
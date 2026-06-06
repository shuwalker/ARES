import SwiftUI

struct SessionHistoryListView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var hoveredID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header with "+ New Chat" button
            historyHeader
            Divider().background(ARESColors.divider)

            // History list or empty state
            if appState.sessionHistory.isEmpty && !appState.isLoadingHistory {
                emptyState
            } else {
                historyList
            }
        }
        .background(ARESColors.background)
        .onAppear {
            appState.refreshSessionHistory()
        }
    }

    // MARK: - Header

    private var historyHeader: some View {
        VStack(spacing: 8) {
            Text("HISTORY")
                .font(.system(size: 10))
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(ARESColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { appState.startNewChat() }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("New Chat")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(ARESColors.gold)
            .foregroundStyle(.black)
        }
        .padding(12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title)
                .foregroundStyle(ARESColors.textTertiary)
            Text("No conversations yet.")
                .font(.subheadline)
                .foregroundStyle(ARESColors.textSecondary)
            Text("Start chatting with ARES.")
                .font(.caption)
                .foregroundStyle(ARESColors.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if appState.isLoadingHistory {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 20)
                }

                ForEach(appState.sessionHistory) { session in
                    SessionHistoryRow(
                        session: session,
                        isSelected: appState.viewingHistoricalSessionID == session.id,
                        isHovered: hoveredID == session.id
                    )
                    .onTapGesture {
                        appState.viewHistoricalSession(session)
                    }
                    .onHover { hovering in
                        hoveredID = hovering ? session.id : nil
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Session History Row

private struct SessionHistoryRow: View {
    let session: CompanionChatService.SessionSummary
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? ARESColors.gold : ARESColors.textPrimary)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                Text(formattedDate)
                    .font(.system(size: 10))
                    .foregroundStyle(ARESColors.textTertiary)

                if session.messageCount > 0 {
                    Text("\(session.messageCount) messages")
                        .font(.system(size: 10))
                        .foregroundStyle(ARESColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
    }

    private var formattedDate: String {
        DateFormatters.shortDateTimeString(from: session.updatedAt)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            ARESColors.gold.opacity(0.12)
        } else if isHovered {
            ARESColors.surface
        } else {
            Color.clear
        }
    }
}
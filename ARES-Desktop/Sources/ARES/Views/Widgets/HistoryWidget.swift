import SwiftUI
import ARESCore

// MARK: - History Widget
//
// Session history list.
// Shows recent conversations from ARESAppState, with real data.

struct HistoryWidget: View {
    @EnvironmentObject private var appState: ARESAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").font(.caption).foregroundColor(.secondary)

            if appState.sessionHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No sessions yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.sessionHistory.prefix(10)) { session in
                            SessionRowView(
                                title: session.title,
                                date: session.updatedAt,
                                preview: session.preview,
                                messageCount: session.messageCount
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 200)
        .onAppear {
            appState.refreshSessionHistory()
        }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let title: String
    let date: Date
    let preview: String
    let messageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDate(date))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("\(messageCount) msgs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

#Preview {
    HistoryWidget()
        .padding()
        .background(Color(.windowBackgroundColor))
}
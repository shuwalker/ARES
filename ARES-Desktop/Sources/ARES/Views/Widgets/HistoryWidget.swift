import SwiftUI
import ARESCore

// MARK: - History Widget
//
// Session history list.
// Shows recent conversations with dates and previews.

struct HistoryWidget: View {
    @State private var sessions: [SessionItem] = [
        SessionItem(
            id: "session-001",
            title: "About ARES Architecture",
            date: Date().addingTimeInterval(-3600),
            preview: "Can you explain how the modular brick pattern works?",
            messageCount: 8
        ),
        SessionItem(
            id: "session-002",
            title: "Protocol Design Discussion",
            date: Date().addingTimeInterval(-86400),
            preview: "How do we ensure Sendable conformance...",
            messageCount: 12
        ),
        SessionItem(
            id: "session-003",
            title: "Gateway Implementation",
            date: Date().addingTimeInterval(-172800),
            preview: "What's the difference between Ollama and Hermes...",
            messageCount: 5
        )
    ]
    @State private var selectedSession: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").font(.caption).foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            isSelected: selectedSession == session.id
                        )
                        .onTapGesture {
                            selectedSession = session.id
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 200)
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: SessionItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(session.preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDate(session.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("\(session.messageCount) msgs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor)
        )
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

// MARK: - Session Item Model

struct SessionItem: Identifiable {
    let id: String
    let title: String
    let date: Date
    let preview: String
    let messageCount: Int
}

#Preview {
    HistoryWidget()
        .padding()
        .background(Color(.windowBackgroundColor))
}

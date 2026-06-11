import SwiftUI
import ARESCore

struct ThoughtLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

struct ThoughtStreamWidget: View {
    @State private var logs: [ThoughtLog] = []
    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                Text("Thought Stream")
                    .font(.headline)
                Spacer()
                Text("Live")
                    .font(.caption)
                    .foregroundColor(.red)
                    .opacity(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(logs) { log in
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatTime(log.timestamp))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(log.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .id(log.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: logs.count) { oldValue, newValue in
                    if let lastId = logs.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 150)
            .padding(8)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
        }
        .padding()
        .onReceive(timer) { time in
            let mockThoughts = [
                "Evaluating context for query...",
                "Running tool: search_web('swiftui grids')",
                "Parsing search results...",
                "Synthesizing response from 3 sources.",
                "Executing local inference step."
            ]
            logs.append(ThoughtLog(timestamp: time, message: mockThoughts.randomElement()!))
            if logs.count > 50 { logs.removeFirst() }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

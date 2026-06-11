import SwiftUI
import ARESCore

struct ThoughtLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

/// Collects real activity from the EventBus (reasoning, embodiment, memory)
/// and exposes it as a rolling log for the dashboard.
@MainActor
final class ThoughtStreamModel: ObservableObject {
    @Published var logs: [ThoughtLog] = []
    private var tasks: [Task<Void, Never>] = []

    func start(bus: any EventBus) {
        guard tasks.isEmpty else { return }
        tasks.append(Task { [weak self] in
            for await event in bus.subscribe(ReasoningEvent.self) {
                let prompt = event.prompt.prefix(60)
                self?.append("Brain responded to: \(prompt)\(event.prompt.count > 60 ? "…" : "")")
            }
        })
        tasks.append(Task { [weak self] in
            for await event in bus.subscribe(EmbodimentEvent.self) {
                self?.append("Embodiment \(event.action): \(event.success ? "ok" : "failed")")
            }
        })
        tasks.append(Task { [weak self] in
            for await event in bus.subscribe(MemoryEvent.self) {
                self?.append("Memory \(event.action): \(event.memoryId)")
            }
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func append(_ message: String) {
        logs.append(ThoughtLog(timestamp: Date(), message: message))
        if logs.count > 50 { logs.removeFirst() }
    }
}

struct ThoughtStreamWidget: View {
    @Environment(\.eventBus) private var eventBus
    @StateObject private var model = ThoughtStreamModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                Text("Thought Stream")
                    .font(.headline)
                Spacer()
                Text(eventBus == nil ? "Offline" : "Live")
                    .font(.caption)
                    .foregroundColor(eventBus == nil ? .secondary : .red)
                    .opacity(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((eventBus == nil ? Color.secondary : Color.red).opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if model.logs.isEmpty {
                            Text("No activity yet — events appear here as ARES thinks, speaks, and remembers.")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        ForEach(model.logs) { log in
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
                .onChange(of: model.logs.count) { oldValue, newValue in
                    if let lastId = model.logs.last?.id {
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
        .onAppear {
            if let eventBus {
                model.start(bus: eventBus)
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

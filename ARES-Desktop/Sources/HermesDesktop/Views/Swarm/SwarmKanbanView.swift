import SwiftUI
import UniformTypeIdentifiers

// MARK: - Swarm Kanban Column

enum SwarmKanbanColumn: String, CaseIterable {
    case backlog = "backlog"
    case ready = "ready"
    case running = "running"
    case review = "review"
    case blocked = "blocked"
    case done = "done"

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .backlog: return .secondary
        case .ready: return .blue
        case .running: return HermesTheme.aresPrimary
        case .review: return .orange
        case .blocked: return .red
        case .done: return .green
        }
    }
}

struct SwarmKanbanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showNewCardSheet = false
    @State private var draggingCard: SwarmKanbanCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Swarm Kanban")
                    .font(.title3.weight(.semibold))
                    .padding(.leading, 20)
                Spacer()
                Button {
                    showNewCardSheet = true
                } label: {
                    Label("New Card", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.trailing, 20)
            }
            .padding(.vertical, 14)

            // Error banner
            if let error = appState.swarmError {
                SwarmErrorBanner(message: error) { appState.swarmError = nil }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if appState.swarmKanbanCards.isEmpty && appState.swarmError != nil {
                SwarmFeatureUnavailableView(
                    message: appState.swarmError ?? "",
                    onRetry: { Task { await appState.loadSwarmKanban() } }
                )
                .padding(.horizontal, 20)
            } else {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(SwarmKanbanColumn.allCases, id: \.rawValue) { col in
                        SwarmKanbanColumnView(
                            column: col,
                            cards: appState.swarmKanbanCards.filter { $0.column == col.rawValue },
                            draggingCard: $draggingCard
                        ) { card, targetColumn in
                            Task { await appState.moveSwarmKanbanCard(card, toColumn: targetColumn) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxHeight: .infinity)
            } // end else
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            await appState.loadSwarmKanban()
        }
        .sheet(isPresented: $showNewCardSheet) {
            SwarmNewCardSheet()
        }
    }
}

struct SwarmKanbanColumnView: View {
    let column: SwarmKanbanColumn
    let cards: [SwarmKanbanCard]
    @Binding var draggingCard: SwarmKanbanCard?
    let onDrop: (SwarmKanbanCard, String) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(column.color)
                    .frame(width: 8, height: 8)
                Text(column.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(cards.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(cards) { card in
                SwarmKanbanCardView(card: card)
                    .onDrag {
                        draggingCard = card
                        return NSItemProvider(object: card.id as NSString)
                    }
            }

            if cards.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
                    .frame(height: 60)
                    .overlay(
                        Text("Drop here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    )
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 220, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                .fill(isDropTargeted ? column.color.opacity(0.12) : HermesTheme.insetFill)
        )
        .onDrop(of: [UTType.plainText], isTargeted: $isDropTargeted) { providers in
            guard let dragging = draggingCard else { return false }
            onDrop(dragging, column.rawValue)
            draggingCard = nil
            return true
        }
    }
}

struct SwarmKanbanCardView: View {
    let card: SwarmKanbanCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.caption.weight(.medium))
                .lineLimit(3)

            HStack(spacing: 6) {
                if let worker = card.worker {
                    Text(worker)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let priority = card.priority {
                    priorityBadge(priority)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HermesTheme.panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke)
        )
    }

    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = {
            switch priority.lowercased() {
            case "high", "urgent": return .red
            case "medium", "normal": return .orange
            default: return .secondary
            }
        }()
        return Text(priority.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct SwarmNewCardSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var worker = ""
    @State private var priority = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Kanban Card")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Card title…", text: $title)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(HermesTheme.insetFill, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Assign Worker (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Worker", selection: $worker) {
                    Text("Unassigned").tag("")
                    ForEach(appState.swarmWorkers) { w in
                        Text(w.name).tag(w.name)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Priority (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Priority", selection: $priority) {
                    Text("None").tag("")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                    Text("Urgent").tag("urgent")
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task {
                        await appState.createSwarmKanbanCard(
                            title: title,
                            worker: worker.isEmpty ? nil : worker,
                            priority: priority.isEmpty ? nil : priority
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

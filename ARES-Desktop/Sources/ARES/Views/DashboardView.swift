import SwiftUI
import ARESCore

// MARK: - Widget Type

enum DashboardWidgetType: String, Codable, CaseIterable, Identifiable {
    case avatar
    case chat
    case history
    case metrics
    case perception
    case thoughtStream
    case agentStatus

    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .avatar: return "Agent Avatar"
        case .chat: return "Live Chat"
        case .history: return "Event History"
        case .metrics: return "System Metrics"
        case .perception: return "Live Perception"
        case .thoughtStream: return "Thought Stream"
        case .agentStatus: return "Agent Status"
        }
    }
}

// MARK: - Dashboard Layout Config

struct DashboardSlot: Codable, Identifiable, Equatable {
    let id: UUID
    var type: DashboardWidgetType
    var span: Int
    
    init(id: UUID = UUID(), type: DashboardWidgetType, span: Int = 1) {
        self.id = id
        self.type = type
        self.span = span
    }
}

// MARK: - Dashboard View Model

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var slots: [DashboardSlot] = []
    
    init() {
        loadLayout()
    }
    
    func loadLayout() {
        if let data = UserDefaults.standard.data(forKey: "ares_dashboard_layout"),
           let saved = try? JSONDecoder().decode([DashboardSlot].self, from: data) {
            self.slots = saved
        } else {
            self.slots = [
                DashboardSlot(type: .metrics, span: 2),
                DashboardSlot(type: .thoughtStream, span: 2),
                DashboardSlot(type: .agentStatus, span: 1),
                DashboardSlot(type: .avatar, span: 1),
                DashboardSlot(type: .chat, span: 1),
                DashboardSlot(type: .perception, span: 1),
                DashboardSlot(type: .history, span: 2)
            ]
        }
    }
    
    func saveLayout() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: "ares_dashboard_layout")
        }
    }
    
    func move(from source: DashboardSlot, to destination: DashboardSlot) {
        guard let sourceIdx = slots.firstIndex(of: source),
              let destIdx = slots.firstIndex(of: destination) else { return }
        
        var newSlots = slots
        newSlots.remove(at: sourceIdx)
        newSlots.insert(source, at: destIdx)
        
        withAnimation(.spring()) {
            slots = newSlots
        }
        saveLayout()
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var isEditing = false
    @State private var draggingItem: DashboardSlot?

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Mission Control")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    withAnimation { isEditing.toggle() }
                } label: {
                    Label(isEditing ? "Done" : "Edit Dashboard", systemImage: isEditing ? "checkmark.circle.fill" : "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
                .tint(isEditing ? .green : .accentColor)
            }
            .padding()
            .background(.ultraThinMaterial)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.slots) { slot in
                        WidgetContainer(slot: slot, isEditing: isEditing, isDragging: draggingItem == slot) {
                            switch slot.type {
                            case .avatar: AvatarWidget()
                            case .chat: ChatWidget()
                            case .history: HistoryWidget()
                            case .metrics: MetricsWidget()
                            case .perception: PerceptionWidget()
                            case .thoughtStream: ThoughtStreamWidget()
                            case .agentStatus: AgentStatusWidget()
                            }
                        }
                        .gridCellColumns(slot.span)
                        .draggable(slot.id.uuidString) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(ARESColors.surface)
                                .frame(width: 200, height: 100)
                                .overlay(Text(slot.type.displayName))
                                .onAppear { draggingItem = slot }
                        }
                        .dropDestination(for: String.self) { items, location in
                            draggingItem = nil
                            return true
                        } isTargeted: { targeted in
                            if targeted, let draggingItem = draggingItem, draggingItem != slot {
                                viewModel.move(from: draggingItem, to: slot)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(ARESColors.background)
    }
}

// MARK: - Widget Container
struct WidgetContainer<Content: View>: View {
    let slot: DashboardSlot
    let isEditing: Bool
    let isDragging: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .opacity(isDragging ? 0.3 : 1.0)
            
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(8)
            }
        }
    }
}

#Preview {
    DashboardView()
}

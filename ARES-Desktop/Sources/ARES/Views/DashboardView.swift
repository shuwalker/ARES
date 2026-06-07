import SwiftUI
import ARESCore

// MARK: - Dashboard Layout Config

struct DashboardLayout: Codable {
    struct Slot: Codable, Identifiable {
        let id: String
        let widget: WidgetType
        var row: Int
        var column: Int
        let rowSpan: Int
        let columnSpan: Int

        enum WidgetType: String, Codable {
            case avatar
            case chat
            case history
            case modelPicker
            case perception
        }
    }

    var slots: [Slot]
    var name: String = "default"

    static let `default` = DashboardLayout(
        slots: [
            Slot(id: "avatar", widget: .avatar, row: 0, column: 0, rowSpan: 3, columnSpan: 1),
            Slot(id: "chat", widget: .chat, row: 0, column: 1, rowSpan: 3, columnSpan: 2),
            Slot(id: "history", widget: .history, row: 0, column: 3, rowSpan: 3, columnSpan: 1),
            Slot(id: "modelPicker", widget: .modelPicker, row: 3, column: 0, rowSpan: 1, columnSpan: 4),
            Slot(id: "perception", widget: .perception, row: 4, column: 0, rowSpan: 2, columnSpan: 4)
        ]
    )
}

// MARK: - DashboardView

struct DashboardView: View {
    @State private var layout: DashboardLayout = DashboardLayout.default
    @State private var isEditing = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Text("ARES Dashboard")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Button {
                        isEditing.toggle()
                    } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                            .foregroundColor(isEditing ? .green : .blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.controlBackgroundColor))

                Divider()

                // Dashboard grid
                ScrollView {
                    VStack(spacing: 12) {
                        // Group slots by row
                        let rowCount = layout.slots.map { $0.row }.max() ?? 0
                        ForEach(0...rowCount, id: \.self) { row in
                            HStack(spacing: 12) {
                                let rowSlots = layout.slots.filter { $0.row == row }
                                    .sorted { $0.column < $1.column }

                                ForEach(rowSlots) { slot in
                                    Group {
                                        switch slot.widget {
                                        case .avatar:
                                            AvatarWidget()
                                        case .chat:
                                            ChatWidget()
                                        case .history:
                                            HistoryWidget()
                                        case .modelPicker:
                                            ModelPickerWidget()
                                        case .perception:
                                            PerceptionWidget()
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.windowBackgroundColor))
                                    .cornerRadius(8)
                                    .contextMenu {
                                        if isEditing {
                                            Button("Move Up") {
                                                moveSlot(slot, direction: .up)
                                            }
                                            Button("Move Down") {
                                                moveSlot(slot, direction: .down)
                                            }
                                            Divider()
                                            Button("Remove", role: .destructive) {
                                                removeSlot(slot)
                                            }
                                        }
                                    }
                                }

                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }

            if isEditing {
                VStack {
                    HStack {
                        Text("Edit Layout")
                            .font(.headline)
                        Spacer()
                        Button("Done") {
                            isEditing = false
                            saveLayout()
                        }
                        .fontWeight(.semibold)
                    }
                    .padding()

                    List {
                        Section("Widgets") {
                            ForEach(layout.slots) { slot in
                                HStack {
                                    Text(slot.widget.rawValue.capitalized)
                                    Spacer()
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .foregroundColor(.gray)
                                }
                            }
                            .onMove { from, to in
                                layout.slots.move(fromOffsets: from, toOffset: to)
                            }
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: 300)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 8)
                .padding()
            }
        }
        .onAppear {
            loadLayout()
        }
    }

    private func moveSlot(_ slot: DashboardLayout.Slot, direction: MoveDirection) {
        guard let index = layout.slots.firstIndex(where: { $0.id == slot.id }) else { return }

        var updatedSlot = layout.slots[index]
        if direction == .up && updatedSlot.row > 0 {
            updatedSlot.row -= 1
        } else if direction == .down {
            updatedSlot.row += 1
        }
        layout.slots[index] = updatedSlot
    }

    private func removeSlot(_ slot: DashboardLayout.Slot) {
        layout.slots.removeAll { $0.id == slot.id }
    }

    private func saveLayout() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(layout),
           let json = String(data: data, encoding: .utf8) {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ares")
                .appendingPathComponent("dashboard_layout.json")

            try? FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? json.write(to: path, atomically: true, encoding: .utf8)
        }
    }

    private func loadLayout() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ares")
            .appendingPathComponent("dashboard_layout.json")

        if let data = try? Data(contentsOf: path),
           let loaded = try? JSONDecoder().decode(DashboardLayout.self, from: data) {
            layout = loaded
        }
    }

    enum MoveDirection {
        case up, down
    }
}

#Preview {
    DashboardView()
}

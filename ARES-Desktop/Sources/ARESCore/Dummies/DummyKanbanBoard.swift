import Foundation

/// In-memory kanban for testing.
public final class DummyWorkflow: Workflow, @unchecked Sendable {
    private var _boards: [String: Board] = [:]

    public let capabilities: Set<String> = ["multiBoard", "customColumns"]

    public init() {
        // Create default boards
        let columns = [
            Column(id: "col-0", name: "todo", displayName: "To Do"),
            Column(id: "col-1", name: "doing", displayName: "In Progress"),
            Column(id: "col-2", name: "done", displayName: "Done")
        ]
        _boards["inbox"] = Board(name: "inbox", displayName: "Inbox", columns: columns)
        print("🤖 [DUMMY] Workflow: initialized with inbox")
    }

    public func listBoards() async throws -> [Board] {
        Array(_boards.values)
    }

    public func getBoard(_ name: String) async throws -> Board {
        _boards[name] ?? Board(name: name, displayName: name)
    }

    public func moveCard(_ cardId: String, toBoard: String, toColumn: String) async throws -> Board {
        print("🤖 [DUMMY] Workflow move: \(cardId) → \(toBoard)/\(toColumn)")
        return _boards[toBoard] ?? Board(name: toBoard, displayName: toBoard)
    }

    public func createCard(in board: String, column: String, title: String, description: String?) async throws -> Card {
        print("🤖 [DUMMY] Workflow create: \(title) in \(board)/\(column)")
        return Card(title: title, description: description, columnId: column)
    }

    public func updateCard(_ cardId: String, title: String?, description: String?, metadata: [String: AnyCodable]?) async throws -> Card {
        print("🤖 [DUMMY] Workflow update: \(cardId)")
        return Card(id: cardId, title: title ?? "untitled", description: description, columnId: "col-0")
    }

    public func deleteCard(_ cardId: String, from board: String) async throws {
        print("🤖 [DUMMY] Workflow delete: \(cardId) from \(board)")
    }
}

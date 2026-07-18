import Foundation

/// In-memory kanban for testing.
public final class DummyWorkflow: Workflow, @unchecked Sendable {
    private let lock = NSLock()
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
        lock.withLock { Array(_boards.values) }
    }

    public func getBoard(_ name: String) async throws -> Board {
        lock.withLock { _boards[name] ?? Board(name: name, displayName: name) }
    }

    public func moveCard(_ cardId: String, toBoard: String, toColumn: String) async throws -> Board {
        print("🤖 [DUMMY] Workflow move: \(cardId) → \(toBoard)/\(toColumn)")
        return lock.withLock {
            var movedCard: Card?
            for (boardName, board) in _boards {
                guard let card = board.cards.first(where: { $0.id == cardId }) else { continue }
                movedCard = Card(
                    id: card.id,
                    title: card.title,
                    description: card.description,
                    columnId: toColumn,
                    priority: card.priority,
                    dueDate: card.dueDate,
                    assignee: card.assignee,
                    tags: card.tags,
                    metadata: card.metadata,
                    createdAt: card.createdAt,
                    updatedAt: Date()
                )
                _boards[boardName] = board.replacingCards(board.cards.filter { $0.id != cardId })
                break
            }

            let target = _boards[toBoard] ?? Self.emptyBoard(name: toBoard)
            if let movedCard {
                _boards[toBoard] = target.replacingCards(target.cards + [movedCard])
            } else if _boards[toBoard] == nil {
                _boards[toBoard] = target
            }
            return _boards[toBoard] ?? target
        }
    }

    public func createCard(in board: String, column: String, title: String, description: String?) async throws -> Card {
        print("🤖 [DUMMY] Workflow create: \(title) in \(board)/\(column)")
        return lock.withLock {
            let card = Card(title: title, description: description, columnId: column)
            let existingBoard = _boards[board] ?? Self.emptyBoard(name: board)
            _boards[board] = existingBoard.replacingCards(existingBoard.cards + [card])
            return card
        }
    }

    public func updateCard(_ cardId: String, title: String?, description: String?, metadata: [String: AnyCodable]?) async throws -> Card {
        print("🤖 [DUMMY] Workflow update: \(cardId)")
        return try lock.withLock {
            for (boardName, board) in _boards {
                guard let index = board.cards.firstIndex(where: { $0.id == cardId }) else { continue }
                let card = board.cards[index]
                let updated = Card(
                    id: card.id,
                    title: title ?? card.title,
                    description: description ?? card.description,
                    columnId: card.columnId,
                    priority: card.priority,
                    dueDate: card.dueDate,
                    assignee: card.assignee,
                    tags: card.tags,
                    metadata: metadata ?? card.metadata,
                    createdAt: card.createdAt,
                    updatedAt: Date()
                )
                var cards = board.cards
                cards[index] = updated
                _boards[boardName] = board.replacingCards(cards)
                return updated
            }
            throw NSError(domain: "DummyWorkflow", code: -1, userInfo: ["message": "Card not found"])
        }
    }

    public func deleteCard(_ cardId: String, from board: String) async throws {
        print("🤖 [DUMMY] Workflow delete: \(cardId) from \(board)")
        lock.withLock {
            guard let existingBoard = _boards[board] else { return }
            _boards[board] = existingBoard.replacingCards(existingBoard.cards.filter { $0.id != cardId })
        }
    }

    private static func emptyBoard(name: String) -> Board {
        Board(
            name: name,
            displayName: name,
            columns: [
                Column(id: "col-0", name: "todo", displayName: "To Do"),
                Column(id: "col-1", name: "doing", displayName: "In Progress"),
                Column(id: "col-2", name: "done", displayName: "Done")
            ]
        )
    }
}

private extension Board {
    func replacingCards(_ cards: [Card]) -> Board {
        Board(
            name: name,
            displayName: displayName,
            columns: columns,
            cards: cards,
            metadata: metadata
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

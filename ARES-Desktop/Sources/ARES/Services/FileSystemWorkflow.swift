import ARESCore
import Foundation
import os

// MARK: - FileSystem-backed Workflow
//
// Persists kanban boards as JSON files on disk — one file per board
// (`<board-name>.json`) inside the directory given at init. Boards are
// kept in an in-memory cache guarded by an NSLock; every mutation is
// written back synchronously with an atomic file write.
//
// On first launch (empty directory), a default "main" board is created
// with todo / in-progress / done columns and persisted immediately.

/// JSON-file-backed Workflow implementation (kanban boards on disk).
public final class FileSystemWorkflow: Workflow, @unchecked Sendable {
    public let capabilities: Set<String> = ["multiBoard", "customColumns"]

    private let directoryURL: URL
    private let lock = NSLock()
    private var boards: [String: Board] = [:]
    private let logger = Logger(subsystem: "com.ares", category: "FileSystemWorkflow")

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Init

    public init(path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        self.directoryURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // Load every board file already on disk.
        let files = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let board = try decoder.decode(Board.self, from: data)
                boards[board.name] = board
            } catch {
                logger.error("Skipping unreadable board file \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // First run: seed a default "main" board.
        if boards.isEmpty {
            let main = Board(
                name: "main",
                displayName: "Main",
                columns: [
                    Column(name: "todo", displayName: "To Do", order: 0),
                    Column(name: "in-progress", displayName: "In Progress", order: 1),
                    Column(name: "done", displayName: "Done", order: 2)
                ]
            )
            boards["main"] = main
            try writeToDisk(main)
            logger.info("Created default board 'main' at \(self.directoryURL.path, privacy: .public)")
        } else {
            logger.info("Loaded \(self.boards.count) board(s) from \(self.directoryURL.path, privacy: .public)")
        }
    }

    // MARK: - Workflow Protocol

    public func listBoards() async throws -> [Board] {
        lock.withLock { Array(boards.values).sorted { $0.name < $1.name } }
    }

    public func getBoard(_ name: String) async throws -> Board {
        try lock.withLock {
            guard let board = boards[name] else {
                throw WorkflowFSError.boardNotFound(name)
            }
            return board
        }
    }

    public func moveCard(_ cardId: String, toBoard: String, toColumn: String) async throws -> Board {
        try lock.withLock {
            guard let target = boards[toBoard] else {
                throw WorkflowFSError.boardNotFound(toBoard)
            }
            guard let column = target.columns.first(where: { $0.id == toColumn || $0.name == toColumn }) else {
                throw WorkflowFSError.columnNotFound(toColumn, board: toBoard)
            }
            // Locate the card — it may live on the target board or another one.
            guard let (sourceName, sourceBoard, card) = findCard(cardId) else {
                throw WorkflowFSError.cardNotFound(cardId)
            }

            // Card is immutable: rebuild it with the new column and fresh updatedAt.
            let moved = Card(
                id: card.id,
                title: card.title,
                description: card.description,
                columnId: column.id,
                priority: card.priority,
                dueDate: card.dueDate,
                assignee: card.assignee,
                tags: card.tags,
                metadata: card.metadata,
                createdAt: card.createdAt,
                updatedAt: Date()
            )

            if sourceName == toBoard {
                var cards = sourceBoard.cards.filter { $0.id != cardId }
                cards.append(moved)
                let updated = sourceBoard.replacingCards(cards)
                boards[toBoard] = updated
                try writeToDisk(updated)
                return updated
            } else {
                let updatedSource = sourceBoard.replacingCards(sourceBoard.cards.filter { $0.id != cardId })
                let updatedTarget = target.replacingCards(target.cards + [moved])
                boards[sourceName] = updatedSource
                boards[toBoard] = updatedTarget
                try writeToDisk(updatedSource)
                try writeToDisk(updatedTarget)
                return updatedTarget
            }
        }
    }

    public func createCard(in board: String, column: String, title: String, description: String?) async throws -> Card {
        try lock.withLock {
            guard let existing = boards[board] else {
                throw WorkflowFSError.boardNotFound(board)
            }
            guard let resolvedColumn = existing.columns.first(where: { $0.id == column || $0.name == column }) else {
                throw WorkflowFSError.columnNotFound(column, board: board)
            }
            let card = Card(title: title, description: description, columnId: resolvedColumn.id)
            let updated = existing.replacingCards(existing.cards + [card])
            boards[board] = updated
            try writeToDisk(updated)
            return card
        }
    }

    public func updateCard(_ cardId: String, title: String?, description: String?, metadata: [String: AnyCodable]?) async throws -> Card {
        try lock.withLock {
            guard let (boardName, board, card) = findCard(cardId) else {
                throw WorkflowFSError.cardNotFound(cardId)
            }
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
            if let index = cards.firstIndex(where: { $0.id == cardId }) {
                cards[index] = updated
            }
            let updatedBoard = board.replacingCards(cards)
            boards[boardName] = updatedBoard
            try writeToDisk(updatedBoard)
            return updated
        }
    }

    public func deleteCard(_ cardId: String, from board: String) async throws {
        try lock.withLock {
            guard let existing = boards[board] else {
                throw WorkflowFSError.boardNotFound(board)
            }
            guard existing.cards.contains(where: { $0.id == cardId }) else {
                throw WorkflowFSError.cardNotFound(cardId)
            }
            let updated = existing.replacingCards(existing.cards.filter { $0.id != cardId })
            boards[board] = updated
            try writeToDisk(updated)
        }
    }

    // MARK: - Private helpers (call only while holding the lock)

    /// Finds a card anywhere across boards. Returns (boardName, board, card).
    private func findCard(_ cardId: String) -> (String, Board, Card)? {
        for (name, board) in boards {
            if let card = board.cards.first(where: { $0.id == cardId }) {
                return (name, board, card)
            }
        }
        return nil
    }

    /// Atomically writes a board to `<board-name>.json` in the storage directory.
    private func writeToDisk(_ board: Board) throws {
        let data = try encoder.encode(board)
        try data.write(to: fileURL(for: board.name), options: .atomic)
    }

    private func fileURL(for boardName: String) -> URL {
        // Board names become filenames — strip path separators defensively.
        let safeName = boardName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent("\(safeName).json")
    }
}

// MARK: - Errors

public enum WorkflowFSError: LocalizedError {
    case boardNotFound(String)
    case cardNotFound(String)
    case columnNotFound(String, board: String)

    public var errorDescription: String? {
        switch self {
        case .boardNotFound(let name):
            return "Board '\(name)' not found"
        case .cardNotFound(let id):
            return "Card '\(id)' not found on any board"
        case .columnNotFound(let column, let board):
            return "Column '\(column)' not found on board '\(board)'"
        }
    }
}

// MARK: - Board Rebuilding

private extension Board {
    /// Board is immutable — rebuild it with a new card list, keeping everything else.
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

// MARK: - NSLock Extension

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

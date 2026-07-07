import Foundation

/// Workflow protocol: task visualization and workflow management.
/// Not a data store (memory-svc owns that). This is the *view model* for tasks.
/// Conforming types: FileSystemKanban, HermesKanban, DummyKanban
public protocol Workflow: AnyObject, Sendable {
    /// List all boards (e.g., "inbox", "in-progress", "done").
    func listBoards() async throws -> [Board]

    /// Get a specific board and its cards.
    func getBoard(_ name: String) async throws -> Board

    /// Move a card between columns.
    /// Returns updated board state.
    func moveCard(_ cardId: String, toBoard: String, toColumn: String) async throws -> Board

    /// Create a new card.
    func createCard(in board: String, column: String, title: String, description: String?) async throws -> Card

    /// Update card metadata.
    func updateCard(_ cardId: String, title: String?, description: String?, metadata: [String: AnyCodable]?) async throws -> Card

    /// Delete a card.
    func deleteCard(_ cardId: String, from board: String) async throws

    /// What can this board do?
    /// Examples: ["multiBoard", "customColumns", "swimlanes", "automation"]
    var capabilities: Set<String> { get }
}

/// A workflow board (e.g., "Daily Tasks").
public struct Board: Codable, Sendable, Equatable {
    public let name: String                    // "inbox", "in-progress", "done", etc.
    public let displayName: String
    public let columns: [Column]
    public let cards: [Card]
    public let metadata: [String: AnyCodable]

    public init(
        name: String,
        displayName: String,
        columns: [Column] = [],
        cards: [Card] = [],
        metadata: [String: AnyCodable] = [:]
    ) {
        self.name = name
        self.displayName = displayName
        self.columns = columns
        self.cards = cards
        self.metadata = metadata
    }
}

/// A column in the board (e.g., "todo", "doing", "done").
public struct Column: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let displayName: String
    public let order: Int
    public let wip: Int?                       // Work in progress limit, if any

    public init(id: String = UUID().uuidString, name: String, displayName: String, order: Int = 0, wip: Int? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.order = order
        self.wip = wip
    }
}

/// A card on the board.
public struct Card: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let description: String?
    public let columnId: String
    public let priority: Priority?
    public let dueDate: Date?
    public let assignee: String?
    public let tags: [String]
    public let metadata: [String: AnyCodable]
    public let createdAt: Date
    public let updatedAt: Date

    public enum Priority: String, Codable, Sendable {
        case low
        case medium
        case high
        case urgent
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        columnId: String,
        priority: Priority? = nil,
        dueDate: Date? = nil,
        assignee: String? = nil,
        tags: [String] = [],
        metadata: [String: AnyCodable] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.columnId = columnId
        self.priority = priority
        self.dueDate = dueDate
        self.assignee = assignee
        self.tags = tags
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

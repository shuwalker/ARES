import Foundation

public enum WorkspaceFileLimits {
    public static let maxEditableFileBytes: Int64 = 10 * 1_000_000

    public static func decimalMegabytes(for byteCount: Int64) -> String {
        String(format: "%.1f MB", Double(byteCount) / 1_000_000)
    }
}

public struct WorkspaceFileBookmark: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var workspaceScopeFingerprint: String
    public var remotePath: String
    public var title: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        workspaceScopeFingerprint: String,
        remotePath: String,
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceScopeFingerprint = workspaceScopeFingerprint
        self.remotePath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var fileID: String {
        "bookmark:\(id.uuidString)"
    }

    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        return Self.displayTitle(for: remotePath)
    }

    public static func displayTitle(for remotePath: String) -> String {
        let trimmed = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled file" }

        let withoutTrailingSlash = trimmed.hasSuffix("/") && trimmed.count > 1
            ? String(trimmed.dropLast())
            : trimmed
        return withoutTrailingSlash.split(separator: "/").last.map(String.init) ?? withoutTrailingSlash
    }
}

public struct WorkspaceFileReference: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case canonical(RemoteTrackedFile)
        case bookmark(UUID)
    }

    public let id: String
    public let title: String
    public let subtitle: String
    public let remotePath: String
    public let kind: Kind
    public let systemImage: String

    public var bookmarkID: UUID? {
        guard case .bookmark(let id) = kind else { return nil }
        return id
    }

    public var isRemovable: Bool {
        bookmarkID != nil
    }

    public static func canonical(_ trackedFile: RemoteTrackedFile, remotePath: String) -> WorkspaceFileReference {
        WorkspaceFileReference(
            id: trackedFile.workspaceFileID,
            title: trackedFile.title,
            subtitle: remotePath,
            remotePath: remotePath,
            kind: .canonical(trackedFile),
            systemImage: "doc.text"
        )
    }

    public static func bookmark(_ bookmark: WorkspaceFileBookmark) -> WorkspaceFileReference {
        WorkspaceFileReference(
            id: bookmark.fileID,
            title: bookmark.displayTitle,
            subtitle: bookmark.remotePath,
            remotePath: bookmark.remotePath,
            kind: .bookmark(bookmark.id),
            systemImage: "bookmark.fill"
        )
    }
}

public struct WorkspaceFileBookmarkGroup: Identifiable, Hashable, Sendable {
    public let directoryPath: String
    public let title: String
    public let references: [WorkspaceFileReference]

    public var id: String {
        directoryPath
    }

    public static func groups(for references: [WorkspaceFileReference]) -> [WorkspaceFileBookmarkGroup] {
        let bookmarks = references.filter { $0.bookmarkID != nil }
        let groupedReferences = Dictionary(grouping: bookmarks) { reference in
            parentDirectoryPath(for: reference.remotePath)
        }

        return groupedReferences
            .map { directoryPath, references in
                WorkspaceFileBookmarkGroup(
                    directoryPath: directoryPath,
                    title: displayTitle(forDirectoryPath: directoryPath),
                    references: references.sorted(by: compareReferences)
                )
            }
            .sorted(by: compareGroups)
    }

    public static func parentDirectoryPath(for remotePath: String) -> String {
        let trimmed = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmingTrailingSlashes(from: trimmed)
        guard !normalized.isEmpty else { return "." }
        guard normalized != "/" else { return "/" }
        guard let slashIndex = normalized.lastIndex(of: "/") else { return "." }
        guard slashIndex != normalized.startIndex else { return "/" }

        return String(normalized[..<slashIndex])
    }

    public static func displayTitle(forDirectoryPath directoryPath: String) -> String {
        let trimmed = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmingTrailingSlashes(from: trimmed)
        guard !normalized.isEmpty else { return "." }
        guard normalized != "/" else { return "/" }

        return normalized.split(separator: "/").last.map(String.init) ?? normalized
    }

    private static func compareGroups(
        _ lhs: WorkspaceFileBookmarkGroup,
        _ rhs: WorkspaceFileBookmarkGroup
    ) -> Bool {
        let pathComparison = lhs.directoryPath.localizedCaseInsensitiveCompare(rhs.directoryPath)
        if pathComparison != .orderedSame {
            return pathComparison == .orderedAscending
        }

        return lhs.directoryPath < rhs.directoryPath
    }

    private static func compareReferences(
        _ lhs: WorkspaceFileReference,
        _ rhs: WorkspaceFileReference
    ) -> Bool {
        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        let pathComparison = lhs.remotePath.localizedCaseInsensitiveCompare(rhs.remotePath)
        if pathComparison != .orderedSame {
            return pathComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private static func trimmingTrailingSlashes(from path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

public struct RemoteDirectoryListing: Decodable, Sendable {
    public let requestedPath: String
    public let resolvedPath: String
    public let displayPath: String
    public let parentPath: String?
    public let parentDisplayPath: String?
    public let entries: [RemoteDirectoryEntry]
    public let totalEntryCount: Int
    public let isTruncated: Bool

    enum CodingKeys: String, CodingKey {
        case requestedPath = "requested_path"
        case resolvedPath = "resolved_path"
        case displayPath = "display_path"
        case parentPath = "parent_path"
        case parentDisplayPath = "parent_display_path"
        case entries
        case totalEntryCount = "total_entry_count"
        case isTruncated = "is_truncated"
    }
}

public struct RemoteDirectoryEntry: Decodable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case directory
        case file
        case symlink
        case other
    }

    public let name: String
    public let path: String
    public let displayPath: String
    public let kind: Kind
    public let size: Int64?
    public let modifiedAt: Double?
    public let isReadable: Bool
    public let isWritable: Bool
    public let isSymlink: Bool

    public var id: String { path }

    public var modifiedDate: Date? {
        modifiedAt.map { Date(timeIntervalSince1970: $0) }
    }

    public var canOpenDirectory: Bool {
        kind == .directory && isReadable
    }

    public var canBookmark: Bool {
        kind == .file && isReadable && !isTooLargeToEdit
    }

    public var isTooLargeToEdit: Bool {
        guard kind == .file, let size else { return false }
        return size > WorkspaceFileLimits.maxEditableFileBytes
    }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case displayPath = "display_path"
        case kind
        case size
        case modifiedAt = "modified_at"
        case isReadable = "is_readable"
        case isWritable = "is_writable"
        case isSymlink = "is_symlink"
    }
}

public extension RemoteTrackedFile {
    public var workspaceFileID: String {
        "canonical:\(rawValue)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
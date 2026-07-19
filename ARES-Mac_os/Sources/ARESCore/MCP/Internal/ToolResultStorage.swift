// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: Copyright (c) 2025 Andrew Wyatt (Fewtarius) & ARES Contributors

import Foundation
import Logging

/// Manages persistent storage of large tool results that exceed inline token limits.
/// Results are stored on disk and retrieved on demand via ReadToolResultTool.
public final class ToolResultStorage: @unchecked Sendable {
    private let logger = Logger(label: "com.ares.toolresultstorage")
    private let fileManager = FileManager.default
    private let lock = NSLock()

    /// Directory where tool results are persisted
    private let storageDirectory: String

    /// Token threshold above which results are persisted to disk
    public static let persistenceThreshold: Int = 500

    /// Token limit for preview/summary of large results
    public static let previewTokenLimit: Int = 200

    /// Default chunk size for paginated reading
    public static func defaultChunkSize() -> Int { 2000 }

    /// Model-aware chunk sizing
    public static func chunkSizeForModel(_ modelName: String) -> Int {
        // Larger context models get bigger chunks
        if modelName.contains("claude-3") || modelName.contains("gpt-4") {
            return 4000
        }
        return 2000
    }

    /// Maximum chunk size (hard limit)
    public static let maxChunkSize: Int = 8000

    public init(storageDirectory: String? = nil) {
        let dir = storageDirectory ?? (NSTemporaryDirectory() + "com.ares.toolresults/")
        self.storageDirectory = dir
        do {
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
        } catch {
            logger.error("Failed to prepare tool result storage: \(error)")
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func validatedComponent(_ value: String, field: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !value.isEmpty,
              value.utf8.count <= 180,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ToolResultStorageError.invalidIdentifier(field: field)
        }
        return value
    }

    private func resultURL(toolCallId: String, conversationId: String?) throws -> URL {
        let conversation = try validatedComponent(conversationId ?? "global", field: "conversationId")
        let call = try validatedComponent(toolCallId, field: "toolCallId")
        return URL(fileURLWithPath: storageDirectory, isDirectory: true)
            .appendingPathComponent("\(conversation)_\(call)", isDirectory: false)
    }

    private func write(_ result: String, to url: URL) throws {
        try result.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Store

    /// Store a tool result and return a unique ID for retrieval.
    @discardableResult
    public func store(_ result: String, toolCallId: String, conversationId: String? = nil) -> String {
        do {
            let url = try resultURL(toolCallId: toolCallId, conversationId: conversationId)
            try withLock { try write(result, to: url) }
            logger.debug("Stored tool result for \(toolCallId), size=\(result.count) chars")
            return toolCallId
        } catch {
            logger.error("Failed to store tool result for \(toolCallId): \(error)")
            return toolCallId
        }
    }

    // MARK: - Retrieve

    /// Store a tool result, persist it, and return metadata.
    public func persistResult(content: String, toolCallId: String, conversationId: String?) throws -> ToolResultMetadata {
        let url = try resultURL(toolCallId: toolCallId, conversationId: conversationId)
        try withLock { try write(content, to: url) }
        return ToolResultMetadata(
            filePath: url.path,
            toolCallId: toolCallId,
            conversationId: conversationId
        )
    }

    /// Retrieve a stored tool result by ID.
    public func retrieve(toolCallId: String, conversationId: String? = nil) throws -> String {
        let url = try resultURL(toolCallId: toolCallId, conversationId: conversationId)
        do {
            return try withLock { try String(contentsOf: url, encoding: .utf8) }
        } catch {
            if let storageError = error as? ToolResultStorageError { throw storageError }
            throw ToolResultStorageError.resultNotFound(toolCallId: toolCallId)
        }
    }

    /// Retrieve a chunk of a stored result with offset and length.
    public func retrieveChunk(toolCallId: String, offset: Int = 0, length: Int? = nil, conversationId: String? = nil) throws -> ToolResultChunk {
        let fullResult = try retrieve(toolCallId: toolCallId, conversationId: conversationId)
        guard offset >= 0, offset <= fullResult.count else {
            throw ToolResultStorageError.invalidOffset(offset: offset, totalLength: fullResult.count)
        }
        if let length, length < 0 {
            throw ToolResultStorageError.invalidLength(length: length)
        }
        let startIndex = fullResult.index(fullResult.startIndex, offsetBy: offset)
        let endIndex: String.Index
        if let length = length {
            let clampedLength = min(length, fullResult.count - offset)
            endIndex = fullResult.index(startIndex, offsetBy: clampedLength)
        } else {
            endIndex = fullResult.endIndex
        }
        let chunk = String(fullResult[startIndex..<endIndex])
        let hasMore = endIndex < fullResult.endIndex
        return ToolResultChunk(
            toolCallId: toolCallId,
            content: chunk,
            offset: offset,
            length: chunk.count,
            totalLength: fullResult.count,
            hasMore: hasMore
        )
    }

    // MARK: - Delete

    /// Delete a stored tool result.
    public func delete(toolCallId: String, conversationId: String? = nil) {
        guard let url = try? resultURL(toolCallId: toolCallId, conversationId: conversationId) else { return }
        withLock { try? fileManager.removeItem(at: url) }
    }

    /// Clean up old results older than the specified interval.
    public func cleanup(olderThan interval: TimeInterval = 3600) {
        withLock {
            guard let enumerator = fileManager.enumerator(atPath: storageDirectory) else { return }
            let cutoff = Date().addingTimeInterval(-interval)
            for case let file as String in enumerator {
                let url = URL(fileURLWithPath: storageDirectory).appendingPathComponent(file)
                if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate < cutoff {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }
}

/// Metadata for a persisted tool result.
public struct ToolResultMetadata: Sendable {
    public let filePath: String
    public let toolCallId: String
    public let conversationId: String?

    public init(filePath: String, toolCallId: String, conversationId: String?) {
        self.filePath = filePath
        self.toolCallId = toolCallId
        self.conversationId = conversationId
    }
}

/// A chunk of a tool result retrieved from storage.
public struct ToolResultChunk: Sendable {
    public let toolCallId: String
    public let content: String
    public let offset: Int
    public let length: Int
    public let totalLength: Int
    public let hasMore: Bool
}

/// Errors for tool result storage operations.
public enum ToolResultStorageError: Error, LocalizedError {
    case resultNotFound(toolCallId: String)
    case resultNotFoundWithSuggestions(toolCallId: String, suggestions: [String])
    case invalidOffset(offset: Int, totalLength: Int)
    case invalidLength(length: Int)
    case invalidIdentifier(field: String)

    public var errorDescription: String? {
        switch self {
        case .resultNotFound(let toolCallId):
            return "Tool result not found for ID: \(toolCallId)"
        case .resultNotFoundWithSuggestions(let toolCallId, let suggestions):
            return "Tool result not found for ID: \(toolCallId). Did you mean: \(suggestions.joined(separator: ", "))?"
        case .invalidOffset(let offset, let totalLength):
            return "Invalid offset \(offset) for result of length \(totalLength)"
        case .invalidLength(let length):
            return "Invalid chunk length \(length)"
        case .invalidIdentifier(let field):
            return "Invalid \(field) for tool result storage"
        }
    }
}

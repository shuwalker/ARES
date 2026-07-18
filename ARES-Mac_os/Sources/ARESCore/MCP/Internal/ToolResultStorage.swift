// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: Copyright (c) 2025 Andrew Wyatt (Fewtarius) & ARES Contributors

import Foundation
import Logging

/// Manages persistent storage of large tool results that exceed inline token limits.
/// Results are stored on disk and retrieved on demand via ReadToolResultTool.
public final class ToolResultStorage: Sendable {
    private let logger = Logger(label: "com.ares.toolresultstorage")
    private let fileManager = FileManager.default

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
        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    // MARK: - Store

    /// Store a tool result and return a unique ID for retrieval.
    @discardableResult
    public func store(_ result: String, toolCallId: String) -> String {
        let url = URL(fileURLWithPath: storageDirectory).appendingPathComponent(toolCallId)
        do {
            try result.write(to: url, atomically: true, encoding: .utf8)
            logger.debug("Stored tool result for \(toolCallId), size=\(result.count) chars")
            return toolCallId
        } catch {
            logger.error("Failed to store tool result for \(toolCallId): \(error)")
            return toolCallId
        }
    }

    // MARK: - Retrieve

    /// Retrieve a stored tool result by ID.
    public func retrieve(toolCallId: String) throws -> String {
        let url = URL(fileURLWithPath: storageDirectory).appendingPathComponent(toolCallId)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ToolResultStorageError.resultNotFound(toolCallId: toolCallId)
        }
    }

    /// Retrieve a chunk of a stored result with offset and length.
    public func retrieveChunk(toolCallId: String, offset: Int = 0, length: Int? = nil) throws -> ToolResultChunk {
        let fullResult = try retrieve(toolCallId: toolCallId)
        let startIndex = fullResult.index(fullResult.startIndex, offsetBy: min(offset, fullResult.count))
        let endIndex: String.Index
        if let length = length {
            endIndex = fullResult.index(startIndex, offsetBy: min(length, fullResult.count - offset))
        } else {
            endIndex = fullResult.endIndex
        }
        let chunk = String(fullResult[startIndex..<endIndex])
        let hasMore = fullResult.index(startIndex, offsetBy: chunk.count) < fullResult.endIndex
        return ToolResultChunk(
            content: chunk,
            offset: offset,
            totalLength: fullResult.count,
            hasMore: hasMore
        )
    }

    // MARK: - Delete

    /// Delete a stored tool result.
    public func delete(toolCallId: String) {
        let url = URL(fileURLWithPath: storageDirectory).appendingPathComponent(toolCallId)
        try? FileManager.default.removeItem(at: url)
    }

    /// Clean up old results older than the specified interval.
    public func cleanup(olderThan interval: TimeInterval = 3600) {
        guard let enumerator = FileManager.default.enumerator(atPath: storageDirectory) else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        for case let file as String in enumerator {
            let url = URL(fileURLWithPath: storageDirectory).appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

/// A chunk of a tool result retrieved from storage.
public struct ToolResultChunk: Sendable {
    public let content: String
    public let offset: Int
    public let totalLength: Int
    public let hasMore: Bool
}

/// Errors for tool result storage operations.
public enum ToolResultStorageError: Error, LocalizedError {
    case resultNotFound(toolCallId: String)
    case resultNotFoundWithSuggestions(toolCallId: String, suggestions: [String])
    case invalidOffset(offset: Int, totalLength: Int)

    public var errorDescription: String? {
        switch self {
        case .resultNotFound(let toolCallId):
            return "Tool result not found for ID: \(toolCallId)"
        case .resultNotFoundWithSuggestions(let toolCallId, let suggestions):
            return "Tool result not found for ID: \(toolCallId). Did you mean: \(suggestions.joined(separator: ", "))?"
        case .invalidOffset(let offset, let totalLength):
            return "Invalid offset \(offset) for result of length \(totalLength)"
        }
    }
}
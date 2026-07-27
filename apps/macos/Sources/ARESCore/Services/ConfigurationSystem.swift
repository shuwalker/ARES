// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: Copyright (c) 2025 Andrew Wyatt (Fewtarius) & ARES Contributors

import Foundation

// MARK: - Top-Level Type Aliases
// These aliases make the nested ConfigurationSystem types available without the prefix,
// since most code in ARESCore references them directly (e.g., EnhancedMessage, not ConfigurationSystem.EnhancedMessage).

public typealias EnhancedMessage = ConfigurationSystem.EnhancedMessage
public typealias MessageType = ConfigurationSystem.MessageType
public typealias ToolStatus = ConfigurationSystem.ToolStatus
public typealias MessagePerformanceMetrics = ConfigurationSystem.MessagePerformanceMetrics
public typealias APIPerformanceMetrics = ConfigurationSystem.APIPerformanceMetrics
public typealias ToolDisplayData = ConfigurationSystem.ToolDisplayData
public typealias ToolDisplayMode = ConfigurationSystem.ToolDisplayMode
public typealias SimpleToolCall = ConfigurationSystem.SimpleToolCall
public typealias MessageContentPart = ConfigurationSystem.MessageContentPart
public typealias ContentPartType = ConfigurationSystem.ContentPartType
public typealias SystemPromptManager = ConfigurationSystem.SystemPromptManager
public typealias WorkingDirectoryConfiguration = ConfigurationSystem.WorkingDirectoryConfiguration

/// Namespace for configuration and messaging types that were previously in the SAM ConfigurationSystem module.
/// These types are now consolidated into ARESCore to eliminate the external module dependency.
/// The enum acts as a namespace — it cannot be instantiated.
public enum ConfigurationSystem {
    // Namespace only — no instances.
}

// MARK: - MessageType

extension ConfigurationSystem {
    /// Types of messages in a conversation.
    public enum MessageType: String, Codable, Sendable, CaseIterable {
        case user = "user"
        case assistant = "assistant"
        case thinking = "thinking"
        case toolExecution = "tool_execution"
        case system = "system"
    }
}

// MARK: - ToolStatus

extension ConfigurationSystem {
    /// Status of a tool execution.
    public enum ToolStatus: String, Codable, Sendable {
        case running = "running"
        case success = "success"
        case error = "error"
        case timeout = "timeout"
        case cancelled = "cancelled"
    }
}

// MARK: - MessagePerformanceMetrics

extension ConfigurationSystem {
    /// Performance metrics for a single message.
    public struct MessagePerformanceMetrics: Codable, Sendable {
        public let tokensPerSecond: Double?
        public let totalTokens: Int?
        public let promptTokens: Int?
        public let completionTokens: Int?
        public let timeToFirstToken: TimeInterval?
        public let modelIdentifier: String?
        public let cost: Double?

        public init(
            tokensPerSecond: Double? = nil,
            totalTokens: Int? = nil,
            promptTokens: Int? = nil,
            completionTokens: Int? = nil,
            timeToFirstToken: TimeInterval? = nil,
            modelIdentifier: String? = nil,
            cost: Double? = nil
        ) {
            self.tokensPerSecond = tokensPerSecond
            self.totalTokens = totalTokens
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.timeToFirstToken = timeToFirstToken
            self.modelIdentifier = modelIdentifier
            self.cost = cost
        }
    }
}

// MARK: - APIPerformanceMetrics

extension ConfigurationSystem {
    /// Performance metrics aggregated at the API level for a conversation.
    public struct APIPerformanceMetrics: Codable, Sendable, Identifiable {
        public let id: UUID
        public let model: String
        public let timestamp: Date
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int
        public let latencyMs: Double
        public let tokensPerSecond: Double?
        public let cost: Double?

        public init(
            id: UUID = UUID(),
            model: String,
            timestamp: Date = Date(),
            promptTokens: Int,
            completionTokens: Int,
            totalTokens: Int,
            latencyMs: Double,
            tokensPerSecond: Double? = nil,
            cost: Double? = nil
        ) {
            self.id = id
            self.model = model
            self.timestamp = timestamp
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
            self.latencyMs = latencyMs
            self.tokensPerSecond = tokensPerSecond
            self.cost = cost
        }
    }
}

// MARK: - ToolDisplayData

extension ConfigurationSystem {
    /// Structured display data for tool execution results in the UI.
    public struct ToolDisplayData: Codable, Sendable {
        public let title: String?
        public let summary: String?
        public let icon: String?
        public let category: String?
        public let details: [String]?
        public let isCollapsible: Bool
        public let displayMode: ToolDisplayMode

        public init(
            title: String? = nil,
            summary: String? = nil,
            icon: String? = nil,
            category: String? = nil,
            details: [String]? = nil,
            isCollapsible: Bool = true,
            displayMode: ToolDisplayMode = .default
        ) {
            self.title = title
            self.summary = summary
            self.icon = icon
            self.category = category
            self.details = details
            self.isCollapsible = isCollapsible
            self.displayMode = displayMode
        }
    }

    /// Display mode for tool results.
    public enum ToolDisplayMode: String, Codable, Sendable {
        case `default` = "default"
        case expanded = "expanded"
        case minimal = "minimal"
        case inline = "inline"
    }
}

// MARK: - SimpleToolCall

extension ConfigurationSystem {
    /// Simplified tool call representation for message metadata.
    public struct SimpleToolCall: Codable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let arguments: String?

        public init(id: String = UUID().uuidString, name: String, arguments: String? = nil) {
            self.id = id
            self.name = name
            self.arguments = arguments
        }
    }
}

// MARK: - MessageContentPart

extension ConfigurationSystem {
    /// A content part within an enhanced message (for multi-part messages, images, etc.).
    public struct MessageContentPart: Codable, Sendable {
        public let type: ContentPartType
        public let text: String?
        public let imageUrl: String?

        public init(type: ContentPartType, text: String? = nil, imageUrl: String? = nil) {
            self.type = type
            self.text = text
            self.imageUrl = imageUrl
        }
    }

    /// Type of content part.
    public enum ContentPartType: String, Codable, Sendable {
        case text = "text"
        case image = "image"
    }
}

// MARK: - EnhancedMessage

extension ConfigurationSystem {
    /// The primary message type for conversation messages with full metadata support.
    public struct EnhancedMessage: Codable, Identifiable, Sendable {
        public let id: UUID
        public var type: MessageType
        public var content: String
        public var contentParts: [MessageContentPart]?
        public var isFromUser: Bool
        public var timestamp: Date
        public var toolName: String?
        public var toolStatus: ToolStatus?
        public var toolDisplayData: ToolDisplayData?
        public var toolDetails: [String]?
        public var toolDuration: TimeInterval?
        public var toolIcon: String?
        public var toolCategory: String?
        public var parentToolName: String?
        public var toolMetadata: [String: String]?
        public var toolCalls: [SimpleToolCall]?
        public var toolCallId: String?
        public var processingTime: TimeInterval?
        public var reasoningContent: String?
        public var showReasoning: Bool
        public var performanceMetrics: MessagePerformanceMetrics?
        public var isStreaming: Bool
        public var isToolMessage: Bool
        public var githubCopilotResponseId: String?
        public var isPinned: Bool
        public var importance: Double
        public var lastModified: Date?
        public var isSystemGenerated: Bool

        public var hasReasoning: Bool {
            return reasoningContent != nil && !(reasoningContent?.isEmpty ?? true)
        }

        public init(
            id: UUID = UUID(),
            type: MessageType = .user,
            content: String,
            contentParts: [MessageContentPart]? = nil,
            isFromUser: Bool = true,
            timestamp: Date = Date(),
            toolName: String? = nil,
            toolStatus: ToolStatus? = nil,
            toolDisplayData: ToolDisplayData? = nil,
            toolDetails: [String]? = nil,
            toolDuration: TimeInterval? = nil,
            toolIcon: String? = nil,
            toolCategory: String? = nil,
            parentToolName: String? = nil,
            toolMetadata: [String: String]? = nil,
            toolCalls: [SimpleToolCall]? = nil,
            toolCallId: String? = nil,
            processingTime: TimeInterval? = nil,
            reasoningContent: String? = nil,
            showReasoning: Bool = false,
            performanceMetrics: MessagePerformanceMetrics? = nil,
            isStreaming: Bool = false,
            isToolMessage: Bool = false,
            githubCopilotResponseId: String? = nil,
            isPinned: Bool = false,
            importance: Double = 0.5,
            lastModified: Date? = nil,
            isSystemGenerated: Bool = false
        ) {
            self.id = id
            self.type = type
            self.content = content
            self.contentParts = contentParts
            self.isFromUser = isFromUser
            self.timestamp = timestamp
            self.toolName = toolName
            self.toolStatus = toolStatus
            self.toolDisplayData = toolDisplayData
            self.toolDetails = toolDetails
            self.toolDuration = toolDuration
            self.toolIcon = toolIcon
            self.toolCategory = toolCategory
            self.parentToolName = parentToolName
            self.toolMetadata = toolMetadata
            self.toolCalls = toolCalls
            self.toolCallId = toolCallId
            self.processingTime = processingTime
            self.reasoningContent = reasoningContent
            self.showReasoning = showReasoning
            self.performanceMetrics = performanceMetrics
            self.isStreaming = isStreaming
            self.isToolMessage = isToolMessage
            self.githubCopilotResponseId = githubCopilotResponseId
            self.isPinned = isPinned
            self.importance = importance
            self.lastModified = lastModified
            self.isSystemGenerated = isSystemGenerated
        }

        // MARK: - Codable

        private enum CodingKeys: String, CodingKey {
            case id, type, content, contentParts, isFromUser, timestamp
            case toolName, toolStatus, toolDisplayData, toolDetails
            case toolDuration, toolIcon, toolCategory, parentToolName
            case toolMetadata, toolCalls, toolCallId, processingTime
            case reasoningContent, showReasoning, performanceMetrics
            case isStreaming, isToolMessage, githubCopilotResponseId
            case isPinned, importance, lastModified, isSystemGenerated
        }
    }
}

// MARK: - SystemPromptManager

extension ConfigurationSystem {
    /// Manages system prompts for conversations.
    /// Stub implementation — the real implementation lives in the app layer.
    @MainActor
    public class SystemPromptManager: ObservableObject, Sendable {
        public static let shared = SystemPromptManager()

        @Published public var selectedConfigurationId: UUID?
        @Published public var configurations: [SystemPromptConfiguration] = []

        public var defaultSystemPromptId: String {
            "00000000-0000-0000-0000-000000000001"
        }

        private init() {}

        public func scanWorkspaceForAIInstructions(at path: String) {
            // Stub — no-op at core level
        }
    }

    /// A system prompt configuration.
    public struct SystemPromptConfiguration: Codable, Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let content: String
        public let isDefault: Bool

        public init(id: UUID = UUID(), name: String, content: String, isDefault: Bool = false) {
            self.id = id
            self.name = name
            self.content = content
            self.isDefault = isDefault
        }
    }
}

// MARK: - WorkingDirectoryConfiguration

extension ConfigurationSystem {
    /// Configuration for working directory paths.
    /// Stub — the real implementation lives in the app layer.
    public struct WorkingDirectoryConfiguration: Sendable {
        public static let shared = WorkingDirectoryConfiguration()

        public func buildPath(subdirectory: String) -> String {
            let basePath = NSString(string: "~/SAM/").expandingTildeInPath
            return (basePath as NSString).appendingPathComponent(subdirectory)
        }

        private init() {}
    }
}

// MARK: - LocationManager

extension ConfigurationSystem {
    /// Location manager for coordinates.
    /// Stub — the real implementation lives in the app layer.
    @MainActor
    public class LocationManager: Sendable {
        public static let shared = LocationManager()

        public var currentLatitude: Double = 0.0
        public var currentLongitude: Double = 0.0

        private init() {}
    }
}

// MARK: - Agent System
// Extracted from AutoGen's agent architecture + CrewAI's agent lifecycle

import Foundation

// MARK: - Agent Protocol (AutoGen pattern)

public protocol Agent: AnyObject {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    func handle(message: AgentMessage) async throws -> AgentMessage
    func saveState() async throws -> [String: Any]
    func loadState(_ state: [String: Any]) async throws
}

// MARK: - Message Types (AutoGen pattern)

public struct AgentMessage: Codable, Sendable {
    public let id: String
    public let type: MessageType
    public let source: String
    public let target: String?
    public let content: String
    public let metadata: [String: String]

    public init(id: String = UUID().uuidString, type: MessageType, source: String, target: String? = nil,
                content: String, metadata: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.source = source
        self.target = target
        self.content = content
        self.metadata = metadata
    }
}

public enum MessageType: String, Codable, Sendable {
    case text
    case handoff       // Swarm pattern: pass to another agent
    case toolCall
    case toolResult
    case system
    case error
}

// MARK: - Agent Runtime (AutoGen SingleThreadedAgentRuntime pattern)

public final class AgentRuntime: @unchecked Sendable {
    public static let shared = AgentRuntime()
    private var agents: [String: Agent] = [:]
    private var subscriptions: [String: Set<String>] = [:] // topic → agent IDs

    public func register(_ agent: Agent) {
        agents[agent.id] = agent
    }

    public func subscribe(agentId: String, to topic: String) {
        subscriptions[topic, default: []].insert(agentId)
    }

    public func send(message: AgentMessage) async throws -> AgentMessage? {
        if let target = message.target, let agent = agents[target] {
            return try await agent.handle(message: message)
        }
        // Publish to topic subscribers
        if let subscribers = subscriptions[message.type.rawValue] {
            for agentId in subscribers {
                if let agent = agents[agentId] {
                    return try await agent.handle(message: message)
                }
            }
        }
        return nil
    }

    public func broadcast(message: AgentMessage) async throws -> [AgentMessage] {
        var results: [AgentMessage] = []
        for (_, agent) in agents {
            let response = try await agent.handle(message: message)
            results.append(response)
        }
        return results
    }
}

// MARK: - Base Agent (AutoGen BaseAgent pattern)

open class BaseAgent: Agent {
    public let id: String
    public let name: String
    public let description: String

    public init(id: String, name: String, description: String = "") {
        self.id = id
        self.name = name
        self.description = description
    }

    open func handle(message: AgentMessage) async throws -> AgentMessage {
        AgentMessage(type: .text, source: id, target: message.source, content: "Received: \(message.content)")
    }

    open func saveState() async throws -> [String: Any] { [:] }
    open func loadState(_ state: [String: Any]) async throws {}
}

// MARK: - LLM Agent (AutoGen AssistantAgent pattern)

public final class LLMAgent: BaseAgent {
    private let llm: LLMProvider
    private let systemMessage: String
    private var conversationHistory: [[String: String]] = []

    public init(id: String, name: String, llm: LLMProvider, systemMessage: String = "You are a helpful assistant.") {
        self.llm = llm
        self.systemMessage = systemMessage
        super.init(id: id, name: name, description: systemMessage)
    }

    public override func handle(message: AgentMessage) async throws -> AgentMessage {
        conversationHistory.append(["role": "user", "content": message.content])

        var messages = [["role": "system", "content": systemMessage]]
        messages.append(contentsOf: conversationHistory)

        let response = try await llm.complete(messages: messages, tools: nil)
        conversationHistory.append(["role": "assistant", "content": response.content])

        return AgentMessage(type: .text, source: id, target: message.source, content: response.content)
    }

    public override func saveState() async throws -> [String: Any] {
        ["conversationHistory": conversationHistory]
    }

    public override func loadState(_ state: [String: Any]) async throws {
        if let history = state["conversationHistory"] as? [[String: String]] {
            conversationHistory = history
        }
    }
}

// MARK: - Group Chat (AutoGen GroupChat pattern)

public final class GroupChat {
    private let agents: [Agent]
    private let runtime: AgentRuntime
    private var messageThread: [AgentMessage] = []

    public init(agents: [Agent]) {
        self.agents = agents
        self.runtime = AgentRuntime.shared
        for agent in agents {
            runtime.register(agent)
        }
    }

    public func run(task: String) async throws -> [AgentMessage] {
        let startMessage = AgentMessage(type: .text, source: "user", target: agents.first?.id, content: task)
        messageThread.append(startMessage)

        var currentSpeaker = 0
        var result = try await runtime.send(message: startMessage)

        while let response = result {
            messageThread.append(response)
            currentSpeaker = (currentSpeaker + 1) % agents.count
            let nextMessage = AgentMessage(type: .text, source: agents[currentSpeaker].id,
                                           target: agents[(currentSpeaker + 1) % agents.count].id,
                                           content: response.content)
            result = try await runtime.send(message: nextMessage)
        }

        return messageThread
    }
}

// MARK: - Swarm Pattern (AutoGen Swarm pattern)

public final class Swarm {
    private let agents: [String: Agent]
    private let runtime: AgentRuntime

    public init(agents: [Agent]) {
        self.agents = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        self.runtime = AgentRuntime.shared
        for agent in agents {
            runtime.register(agent)
        }
    }

    public func run(task: String, entryAgent: String) async throws -> [AgentMessage] {
        var currentAgent = entryAgent
        var thread: [AgentMessage] = []
        var message = AgentMessage(type: .text, source: "user", target: currentAgent, content: task)

        for _ in 0..<50 { // max 50 turns
            guard let response = try await runtime.send(message: message) else { break }
            thread.append(response)

            // Check for handoff
            if response.type == .handoff, let target = response.metadata["target"] {
                currentAgent = target
                message = AgentMessage(type: .text, source: response.source, target: target, content: response.content)
            } else {
                break
            }
        }

        return thread
    }
}

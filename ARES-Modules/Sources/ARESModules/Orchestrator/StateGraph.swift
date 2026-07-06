// MARK: - State Graph System
// Extracted from LangGraph's StateGraph + Pregel execution model

import Foundation

public protocol StateGraphNode: AnyObject {
    var id: String { get }
    func process(state: [String: Any]) async throws -> [String: Any]
}

// MARK: - Edge Types (LangGraph pattern)

public enum Edge {
    case direct(from: String, to: String)
    case conditional(from: String, router: StateRouter)
    case fanIn(from: [String], to: String)
}

public protocol StateRouter: AnyObject {
    func route(state: [String: Any]) -> String
}

// MARK: - State Graph

public final class StateGraph {
    public private(set) var nodes: [String: StateGraphNode] = [:]
    public private(set) var edges: [Edge] = []
    public var entryPoint: String = ""

    public init() {}

    public func addNode(_ node: StateGraphNode) {
        nodes[node.id] = node
    }

    public func addEdge(_ edge: Edge) {
        edges.append(edge)
    }

    public func compile() -> CompiledStateGraph {
        CompiledStateGraph(graph: self)
    }
}

// MARK: - Compiled State Graph (LangGraph Pregel pattern)

public final class CompiledStateGraph {
    private let graph: StateGraph

    init(graph: StateGraph) {
        self.graph = graph
    }

    public func run(initialState: [String: Any]) async throws -> [String: Any] {
        var state = initialState
        var currentNode = graph.entryPoint

        while currentNode != "__end__" {
            guard let node = graph.nodes[currentNode] else {
                throw GraphError.nodeNotFound(currentNode)
            }

            state = try await node.process(state: state)

            // Find next node via edges
            let outgoingEdges = graph.edges.filter { edge in
                switch edge {
                case .direct(let from, _): return from == currentNode
                case .conditional(let from, _): return from == currentNode
                case .fanIn(let from, _): return from.contains(currentNode)
                }
            }

            guard let nextEdge = outgoingEdges.first else {
                currentNode = "__end__"
                continue
            }

            switch nextEdge {
            case .direct(_, let to):
                currentNode = to
            case .conditional(_, let router):
                currentNode = router.route(state: state)
            case .fanIn(_, let to):
                currentNode = to
            }
        }

        return state
    }
}

public enum GraphError: LocalizedError {
    case nodeNotFound(String)
    public var errorDescription: String? {
        switch self {
        case .nodeNotFound(let id): return "Node not found: \(id)"
        }
    }
}

// MARK: - ReAct Agent (LangGraph prebuilt pattern)

public final class ReActAgent {
    public let graph: StateGraph
    private let llm: LLMProvider
    private let tools: [String: Tool]

    public init(llm: LLMProvider, tools: [Tool] = []) {
        self.llm = llm
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        let graph = StateGraph()
        graph.entryPoint = "agent"

        let agentNode = AgentNode(llm: llm, tools: tools)
        let toolNode = ToolExecutionNode(tools: tools)

        graph.addNode(agentNode)
        graph.addNode(toolNode)
        graph.addEdge(.conditional(from: "agent", router: ToolRouter(tools: tools)))
        graph.addEdge(.direct(from: "tools", to: "agent"))

        self.graph = graph
    }

    public func run(messages: [[String: String]]) async throws -> String {
        let result = try await graph.compile().run(initialState: ["messages": messages])
        return (result["response"] as? String) ?? ""
    }
}

// MARK: - Supporting Types

public protocol Tool: AnyObject {
    var name: String { get }
    var description: String { get }
    func execute(args: [String: Any]) async throws -> String
}

final class AgentNode: StateGraphNode {
    let id = "agent"
    private let llm: LLMProvider
    private let tools: [Tool]

    init(llm: LLMProvider, tools: [Tool]) {
        self.llm = llm
        self.tools = tools
    }

    func process(state: [String: Any]) async throws -> [String: Any] {
        var newState = state
        let messages = state["messages"] as? [[String: String]] ?? []

        let toolSchemas = tools.map { tool -> [String: Any] in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": ["type": "object", "properties": [:]]
                ] as [String: Any]
            ]
        }

        let response = try await llm.complete(messages: messages, tools: toolSchemas.isEmpty ? nil : toolSchemas)
        newState["response"] = response.content
        newState["needs_tools"] = response.finishReason == "tool_calls"
        return newState
    }
}

final class ToolExecutionNode: StateGraphNode {
    let id = "tools"
    private let tools: [String: Tool]

    init(tools: [Tool]) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    func process(state: [String: Any]) async throws -> [String: Any] {
        var newState = state
        // Execute tools based on state
        newState["tool_results"] = []
        return newState
    }
}

final class ToolRouter: StateRouter {
    private let tools: [String: Tool]

    init(tools: [Tool]) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    func route(state: [String: Any]) -> String {
        (state["needs_tools"] as? Bool == true) ? "tools" : "__end__"
    }
}

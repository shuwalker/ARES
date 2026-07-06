# Extraction Report: SAM

**Source:** SAM
**Language:** Swift
**Files:** 260
**Date:** 2026-06-23 12:48

## Architecture Patterns
- Package.swift: Async/Await
- AIProvider.swift: Async/Await
- ALICEImageGenerationService.swift: Async/Await
- ALICEProvider.swift: MVVM/Observable
- ALICEProvider.swift: Async/Await
- AgentOrchestrator+ContextManagement.swift: Async/Await
- AgentOrchestrator+LLMCalls.swift: Async/Await
- AgentOrchestrator+ToolExecution.swift: Swift Actor
- AgentOrchestrator+ToolExecution.swift: Async/Await
- AgentOrchestrator.swift: MVVM/Observable
- AgentOrchestrator.swift: Swift Actor
- AgentOrchestrator.swift: Async/Await
- CopilotTokenStore.swift: MVVM/Observable
- CopilotTokenStore.swift: Async/Await

## Protocols
- AIProvider.swift

## Key Types & Patterns
- `public struct ModelCapabilities {`
- `public protocol AIProvider {`
- `public protocol LoadBalancer {`
- `public struct ResponseNormalizer {`
- `public struct ALICEHealthResponse: Codable {`
- `enum CodingKeys: String, CodingKey {`
- `public struct ALICEModelsResponse: Codable, Sendable {`
- `public struct ALICEModel: Codable, Identifiable, Sendable {`
- `enum CodingKeys: String, CodingKey {`
- `public struct ALICEChatResponse: Codable {`
- `enum CodingKeys: String, CodingKey {`
- `struct LLMResponse {`
- `public struct IterationResponse {`
- `public enum CompletionReason: String, Codable {`

## Key Files
- SAM/Package.swift
- SAM/Sources/APIFramework/AIProvider.swift
- SAM/Sources/APIFramework/ALICEImageGenerationService.swift
- SAM/Sources/APIFramework/ALICEProvider.swift
- SAM/Sources/APIFramework/AgentOrchestrator+ContextManagement.swift
- SAM/Sources/APIFramework/AgentOrchestrator+LLMCalls.swift
- SAM/Sources/APIFramework/AgentOrchestrator+ToolExecution.swift
- SAM/Sources/APIFramework/AgentOrchestrator.swift
- SAM/Sources/APIFramework/AgentResult.swift
- SAM/Sources/APIFramework/CopilotTokenStore.swift

---
*Auto-extracted by extraction pipeline*

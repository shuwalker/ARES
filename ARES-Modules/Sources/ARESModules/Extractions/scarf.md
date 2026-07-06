# Extraction Report: Scarf

**Source:** scarf
**Language:** Swift
**Files:** 483
**Date:** 2026-06-23 12:47

## Architecture Patterns
- Package.swift: MVVM/Observable
- Package.swift: Swift Actor
- ACPChannel.swift: Swift Actor
- ACPChannel.swift: Async/Await
- ACPClient.swift: Swift Actor
- ACPClient.swift: Async/Await
- ProcessACPChannel.swift: Swift Actor
- ProcessACPChannel.swift: Async/Await
- ScarfMon.swift: Async/Await
- ScarfMonBoot.swift: Swift Actor
- ACPMessages.swift: Swift Actor

## Protocols
- ACPChannel.swift
- ScarfMon.swift

## Key Types & Patterns
- `public protocol ACPChannel: Sendable {`
- `public enum ScarfMon {`
- `public enum Kind: String, Sendable, Codable {`
- `public protocol ScarfMonBackend: Sendable {`
- `public enum ScarfMonBoot {`
- `public enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }`
- `public enum CodingKeys: String, CodingKey { case jsonrpc, id, method, result, error, params }`
- `public enum CodingKeys: String, CodingKey { case code, message }`
- `public enum ACPEvent: Sendable {`
- `public enum ACPEventParser {`

## Key Files
- scarf/scarf/Packages/ScarfCore/Package.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/ACP/ACPChannel.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/ACP/ACPClient.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/ACP/ProcessACPChannel.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/Diagnostics/ScarfMon.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/Diagnostics/ScarfMonBoot.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/Diagnostics/ScarfMonLoggerBackend.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/Diagnostics/ScarfMonRingBuffer.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/Diagnostics/ScarfMonSignpostBackend.swift
- scarf/scarf/Packages/ScarfCore/Sources/ScarfCore/Models/ACPMessages.swift

---
*Auto-extracted by extraction pipeline*

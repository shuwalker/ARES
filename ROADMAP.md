# ARES Roadmap

## v1 — Current Release

- Native macOS app with 4 tabs: Companion, Hub, Office (stub), Settings
- SAM-powered companion chat connected to Hermes gateway (`localhost:8642`)
- Hub tab: Hermes agent web dashboard + Dodo native management views
- Python daemon with ZeroMQ IPC foundation (server live, Swift client stubbed)
- Non-blocking OSC telemetry emitter (disabled by default, config-driven)
- Centralized SQLite WAL connection layer across all daemon storage
- Runtime-configurable Lilith integration points (toggleable via Settings)

## v2 — Companion Depth

- SAM submodule promoted to full copy — ConversationEngine customizable
- Agent selector dropdown in Companion (Hermes / Ollama / custom endpoint)
- Settings AI config panel: gateway URL, model, API key editable in-app
- Prompt cache priming on daemon startup (Lilith fast-path pattern)
- Fast-path routing gate: llama3.2:3b handles simple turns, Hermes-3 for reasoning

## v3 — Native Hub + Full IPC

- Hub tab fully native SwiftUI — replaces WKWebView with daemon-backed views
- ZeroMQ Swift client fully wired (SwiftZMQ + swift-protobuf)
- Bidirectional daemon ↔ app state sync via ConfigUpdate/StateChange messages
- Hermes MCP bridge on port 9501 connected and exercised
- Multi-device support: ARES on MacBook routes to Mac Studio agent via TCP ZeroMQ

## v4 — Embodiment + Autonomy

- Office tab: autonomous task execution UI with approval loop
- CognitionState bus: reasoning depth, confidence, memory load → OSC avatar params
- Full expressive avatar: PhysBones, lipsync visemes, visor brightness mapped to agent state
- 3DGS / VR companion rendering phase
- Tool registration across devices: MacBook ARES registers local tools to Mac Studio Hermes

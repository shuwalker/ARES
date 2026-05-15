# Open-LLM-VTuber Architecture Audit

**Repository:** `/Users/matthewjenkins/Documents/GitHub/Open-LLM-VTuber/`  
**Date:** 2026-05-15  
**Scope:** Live2D integration, frontend architecture, backend pipeline, config system, and actionable patterns for ARES-Face Swift app.

---

## 1. Live2D Integration

### 1.1 Model Loading (moc3)
- **Runtime:** The backend does **not** render Live2D directly. It relies on the **frontend** to load `.moc3` models via the `Live2DFramework` JavaScript runtime (Cubism SDK for Web).
- **Discovery:** The backend exposes a REST endpoint `GET /live2d-models/info` that scans the `live2d-models/` directory. It looks for subfolders containing a `{folder}.model3.json` file and an optional avatar image (`{folder}.png|jpg`).
- **Frontend:** The frontend requests the model list from `/live2d-models/info` and loads the selected model by path. All rendering, lip-sync, and motion playback happen in the browser using the Cubism JS SDK.

### 1.2 Emotion / Expression Mapping System
- **Model-centric keywords:** `Live2dModel` (`src/open_llm_vtuber/live2d_model.py`) loads a model’s `emotion_keywords.json` from `live2d-models/<model_name>/emotion_keywords.json`.  
  Example structure (inferred from code):
  ```json
  {
    "keyword1": ["exp1", "exp2"],
    "keyword2": ["exp3"]
  }
  ```
- **Reverse lookup dictionary:** At init, the class builds `self._keywords` as a `Dict[str, List[str]]` mapping each expression string back to all keywords that trigger it.
- **LLM Prompt Injection:** Before every chat completion, the system injects a prompt snippet (`prompts/utils/live2d_expression_prompt.txt`) that tells the LLM:  
  > *"Use the keywords provided below to express facial expressions... Here are all the expression keywords you can use: [happy, sad, angry, …]"*
  The list is dynamically populated from the model’s available keyword keys.

### 1.3 How AI Responses Drive Live2D Expressions
1. **Generation:** The LLM receives the system prompt with the bracketed keyword list and is instructed to embed expressions inline, e.g. `"Hi! [happy] Nice to meet you!"`.
2. **Extraction:** The `actions_extractor` decorator (`src/open_llm_vtuber/agent/transformers.py`) calls `live2d_model.extract_emotion(sentence_text)`.
   - It uses a compiled regex pattern: `r'\[(' + '|'.join(keywords) + r')\]'`.
   - Matching keywords are mapped through the reverse dictionary to produce a `List[str]` of expression IDs.
   - Removes the bracket keywords from the TTS/display text.
3. **Downstream:** The resulting `Actions` object (with `expressions: List[str]`) is packaged into the `SentenceOutput` and sent to the frontend via WebSocket.
4. **Frontend Playback:** When the frontend receives an audio payload with `actions.expressions`, it triggers the corresponding Live2D expressions via the Cubism SDK API.

---

## 2. Frontend Architecture

### 2.1 Web UI Structure
- **Build:** A modern **React SPA** (Vite-based). The compiled bundle sits in `frontend/assets/` (`main-nu7uwxNJ.js`, `main-QEkl09-0.css`).
- **Entry:** `frontend/index.html` loads the bundled JS/CSS.
- **Features observed in JS bundle snippets:**
  - ONNX runtime usage (voice conversion or ASR models running in-browser).
  - WebRTC / WebGL context creation for microphone/video streams.
  - WebSocket message handling for real-time chat and audio.

### 2.2 Chat Interface
- **Input modes:**
  - **Text** (typed).
  - **Voice** (microphone → audio buffer sent over WebSocket binary frames).
- **Output modes:**
  - **Text display** — streaming sentence-by-sentence.
  - **Audio playback** — base64-encoded MP3/Opus or file URLs.
  - **Live2D expressions** — triggered alongside each sentence segment.

### 2.3 State Management
- **No Redux / Zustand visible** in the minified bundle; likely uses **React hooks** (`useState`, `useRef`, `useEffect`) and possibly a lightweight context provider for:
  - Microphone recording state.
  - WebSocket connection status.
  - Audio playback queue.
  - Live2D model reference.
- **Audio queue:** The frontend maintains an ordered playback queue because the backend sends audio out-of-order but labels each payload with a sequence number for reassembly.

---

## 3. Backend Pipeline

### 3.1 Audio → LLM → Response → Animation Flow

```
┌──────────┐     ┌──────────┐     ┌──────────────┐     ┌──────────┐
│  Client  │────▶│  ASR     │────▶│  LLM Agent   │────▶│ Sentence │
│  Audio   │     │  Engine  │     │  (streaming) │     │ Divider  │
└──────────┘     └──────────┘     └──────────────┘     └────┬─────┘
                                                            │
                       ┌──────────────────────────────────────┘
                       ▼
              ┌─────────────────────────────────────┐
              │  Pipeline Decorators (transformers) │
              │  1. actions_extractor                │
              │  2. display_processor                  │
              │  3. tts_filter                       │
              └────────────────┬────────────────────┘
                               │
                               ▼
              ┌─────────────────────────────────────┐
              │  TTS Task Manager (ordered queue)    │
              │  One TTS job per sentence segment    │
              └────────────────┬────────────────────┘
                               │
                               ▼
              ┌─────────────────────────────────────┐
              │  WebSocket JSON Payload              │
              │  { audio, display_text, actions }    │
              └────────────────┬────────────────────┘
                               │
                               ▼
              ┌─────────────────────────────────────┐
              │  Client (plays audio + expressions)  │
              └─────────────────────────────────────┘
```

### 3.2 Key Python Modules

| File | Role |
|------|------|
| `server.py` | FastAPI bootstrap, static file serving, CORS, mounts `frontend/` |
| `routes.py` | `/client-ws` (main WS), `/proxy-ws`, `/asr`, `/tts-ws`, `/live2d-models/info` |
| `websocket_handler.py` | Core I/O loop: receives audio/text, handles interrupts, sends ordered payloads, manages sessions |
| `service_context.py` | **Factory:** initializes ASR, TTS, VAD, LLM, translator, Live2D model per character config |
| `live2d_model.py` | Emotion keyword loading, regex extraction of bracketed expressions |
| `agent/transformers.py` | Decorator pipeline: `sentence_divider`, `actions_extractor`, `display_processor`, `tts_filter` |
| `conversations/tts_manager.py` | `TTSTaskManager`: parallel TTS generation with **sequence-number ordered delivery** |
| `agent/agents/basic_memory_agent.py` | Chat agent with memory, tool calling (MCP), interrupt handling |
| `conversations/single_conversation.py` | Orchestrates the full chat round (ASR → agent → TTS → WS send) |
| `agent/output_types.py` | Typed dataclasses: `SentenceOutput`, `DisplayText`, `Actions` |

### 3.3 Streaming & Interrupt Handling
- **WebSocket binary frames** are used for microphone audio chunks.
- **Interrupts:** If the user speaks while the AI is talking, a VAD event triggers `handle_interrupt()`:
  1. Cancels pending TTS tasks (`tts_manager.clear()`).
  2. Sends a `stop-audio-playback` command to the client.
  3. Truncates the assistant’s memory with `"..."` or injects `[Interrupted by user]`.
- **Faster first response:** The `sentence_divider` yields the first sentence as soon as possible rather than waiting for the full LLM response.

---

## 4. Config System

### 4.1 Configuration Layers
1. **Base config:** `config_templates/conf.default.yaml` (~29 KB). Defines every possible setting with defaults.
2. **User override:** `conf.yaml` (if present) selectively overrides defaults.
3. **Character configs:** `characters/<name>.yaml` (e.g., `en_unhelpful_ai.yaml`). Each specifies:
   - `live2d_model_name`
   - `persona_prompt`
   - `avatar`
   - Any per-character overrides (TTS voice, LLM params, etc.)

### 4.2 Supported Model Providers

#### LLM (via `model_dict.json` & factory)
- OpenAI-compatible (`gpt-4o`, `gpt-4o-mini`, custom endpoints)
- Claude (`claude-3-5-sonnet`, `claude-3-opus`, etc.)
- DeepSeek (`deepseek-chat`, `deepseek-reasoner`)
- Gemini (`gemini-2.0-flash`, etc.)
- Ollama (local models via `ollama_chat`)
- Mem0 (memory-augmented layer via `mem0 wrapper`)

#### TTS (factory-created from config string)
- Edge TTS, ElevenLabs, OpenAI TTS, Azure TTS
- Coqui TTS, XTTS, MeloTTS, GPT-SoVITS, Fish Audio
- Google, AWS, SiliconFlow, Minimax, Cartesia
- Piper, Bark, Sherpa-ONNX, Spark TTS, CosyVoice

#### ASR
- **Faster-whisper** (local/offline)
- **Whisper** (OpenAI API)
- **Azure Speech**

#### VAD
- **Silero VAD** (default, ONNX-based)
- WebRTC VAD

### 4.3 Factory Pattern
- `service_context.py` uses string-based factory methods:
  ```python
  tts_engine = tts_factory(new_config)
  asr_engine = asr_factory(new_config)
  llm = stateless_llm_factory(new_config)
  ```
- This allows switching models entirely via YAML without code changes.

---

## 5. Useful Patterns for ARES-Face Swift App

### 5.1 🏆 Expression-as-Text Injection (Highest Value)
**What they do:** Instead of building a complex emotion classifier, they **prompt the LLM to output bracketed emotion keywords** inline with its response.

**Why it’s brilliant:**
- Zero latency (no secondary model inference).
- Works with any LLM.
- Keywords are fully model-configurable per character.

**How to adapt for ARES-Face:**
- Maintain a Swift `ExpressionMap: [String: [String]]` (e.g. `"happy" -> ["smile_morph", "eye_bright"]`).
- Inject into the system prompt:  
  ````
  You are ARES-Face. Express emotions using these exact keywords in brackets: [happy], [concerned], [curious].
  Example: "[happy] Good morning! What can I help you with today?"
  ````
- Stream-parse the LLM tokens with a simple regex `\[[a-z_]+\]` and trigger ARKit / Live2D / morph targets in real time.

### 5.2 🏆 Ordered Audio Queue with Parallel TTS
**What they do:** TTS tasks run in parallel (one per sentence), but a `sequence_counter` ensures they are **delivered to the client in strict sentence order**, even if later sentences finish TTS first.

**How to adapt for ARES-Face:**
- Swift concurrency: spawn `Task` per sentence for TTS generation.
- Use an `AsyncSequence` or `OrderedQueue` with sequence IDs.
- The UI/audio player always consumes in order, preventing jumbled playback on slower networks.

### 5.3 🏆 Sentence-Level Streaming Pipeline (Decorator Chain)
**What they do:** Token streams from the LLM are piped through a chain of async generators:
1. `sentence_divider` — groups tokens into grammatical sentences.
2. `actions_extractor` — extracts expressions.
3. `display_processor` — formats text for UI.
4. `tts_filter` — strips think tags / special chars for speech.

**How to adapt for ARES-Face:**
- Build a **Swift AsyncSequence pipeline** using `AsyncStream` or `AsyncThrowingStream` chained with `.map`/`.flatMap`.
- Each stage is an isolated `struct` conforming to a `PipelineTransform` protocol.
- Benefits: interruptible at any stage, unit-testable, and pluggable (e.g. swap sentence divider for Chinese vs. English).

### 5.4 🏆 Service Context & Factory Initialization
**What they do:** All heavy dependencies (LLM, TTS, ASR) are created once per configuration and cached. Switching characters just swaps the `ServiceContext` instance.

**How to adapt for ARES-Face:**
- Create a Swift `ServiceContext` `@Observable` or `actor` that holds:
  - `LLMClient`
  - `TTSClient`
  - `ASREngine`
  - `ExpressionMap`
- Use a factory: `ServiceContext.create(from: CharacterConfig) -> ServiceContext`.
- Inject `ServiceContext` into SwiftUI environment for global access.

### 5.5 🏆 Interrupt & State Reset
**What they do:** Interruption cleanly halts the TTS queue, sends a `stop-audio-playback` signal, and appends a system/user interruption marker to memory so the LLM knows it was cut off.

**How to adapt for ARES-Face:**
- SwiftUI: expose `isInterrupted` state.
- On user tap / voice barge-in: cancel all `Task.checkCancellation()` loops, flush STT buffer, and send `[Interrupted by user]` to the LLM context.
- Reset `sequence_counter` and audio buffer to prevent stale playback.

### 5.6 Character YAML Configs
**What they do:** Characters are lightweight YAML files that only override differing fields from the master `conf.default.yaml`.

**How to adapt for ARES-Face:**
- Store character configs as JSON/YAML in app bundle or iCloud sync.
- Fields: `systemPrompt`, `live2dModelName`, `avatarAssetName`, `expressionMapName`, `ttsVoiceID`.
- Enables downloadable / user-created characters without an app update.

---

## 6. File Index

| Path | Purpose |
|------|---------|
| `src/open_llm_vtuber/live2d_model.py` | Emotion keyword loading & extraction |
| `src/open_llm_vtuber/server.py` | FastAPI entrypoint |
| `src/open_llm_vtuber/routes.py` | REST / WebSocket routes |
| `src/open_llm_vtuber/websocket_handler.py` | Main WebSocket I/O & audio streaming |
| `src/open_llm_vtuber/service_context.py` | Dependency factory & init |
| `src/open_llm_vtuber/agent/transformers.py` | Pipeline decorators |
| `src/open_llm_vtuber/agent/agents/basic_memory_agent.py` | LLM agent with memory + tools |
| `src/open_llm_vtuber/agent/output_types.py` | Typed pipeline data structures |
| `src/open_llm_vtuber/conversations/tts_manager.py` | Ordered TTS queue |
| `src/open_llm_vtuber/conversations/single_conversation.py` | Conversation orchestration |
| `config_templates/conf.default.yaml` | Full default configuration |
| `model_dict.json` | LLM provider registry |
| `characters/*.yaml` | Per-character overrides |
| `prompts/utils/live2d_expression_prompt.txt` | Dynamic LLM prompt for expressions |
| `frontend/assets/` | Compiled React SPA (minified) |

---

## 7. Summary & Recommendations

1. **Expression system:** The prompt-injection + regex extraction is the single most elegant pattern here. It offloads emotion selection to the LLM itself, avoiding a separate classifier network. **Implement this verbatim in ARES-Face.**
2. **Pipeline architecture:** Use Swift’s `AsyncSequence` to replicate the Python generator decorator chain. It gives clean separation between LLM output, sentence splitting, expression extraction, and TTS preprocessing.
3. **Ordered concurrency:** Parallel TTS with sequence-number ordering is critical for fluid multi-sentence responses. Swift `TaskGroup` or an actor-based queue works well.
4. **Config factory:** A single `ServiceContext` factory makes swapping characters, voices, and LLMs instantaneous—ideal for a modular Swift app.
5. **Interrupt handling:** Always send an explicit interruption marker to the LLM context. This dramatically improves multi-turn coherence after user barges in.

---

*End of Audit Report*

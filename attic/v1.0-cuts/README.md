# attic/v1.0-cuts

Code cut from the ARES-Desktop app during the "cut or finish" pass for the
**production/v1.0** branch on **2026-06-10**. Nothing here is lost — every
preserved file is byte-identical to what was removed from
`ARES-Desktop/Sources/`.

## Preserved files

### `MLXAgentBrain.swift`
- **Was:** `ARES-Desktop/Sources/ARES/Providers/MLXAgentBrain.swift` — the
  `BrainImpl.local(model:)` backend, a `ReasoningBrain` intended to run LLM
  inference natively on Apple Silicon via the MLX Swift package.
- **Why cut:** placeholder methods only — no real MLX inference. `plan()`
  returned an empty array, `reflect()` was a no-op, and `respond()` allocated
  a zeros tensor and then "streamed" a hardcoded string
  ("I am the local MLX Brain. I would run ... right now!") word by word with
  artificial sleeps. It demonstrated that MLX arrays link, nothing more.
  Real local inference needs the MLXLLM package from mlx-swift-examples (or a
  hand-ported transformer stack), which was never wired in.
- **How to restore:**
  1. Move the file back to `ARES-Desktop/Sources/ARES/Providers/MLXAgentBrain.swift`.
  2. Re-add `case local(model: String)` to `BrainImpl` in
     `ARES-Desktop/Sources/ARES/Services/WiringBuilder.swift`, and a matching
     builder case in `BackendBuilder.brain(_:)` that constructs
     `MLXAgentBrain(modelPath: model)`.
  3. Re-add the "Apple Silicon (MLX)" section to
     `ARES-Desktop/Sources/ARES/Views/Widgets/ModelPickerWidget.swift`
     (the `.mlx` backend case) so the UI can select it again.
  4. Implement actual generation before shipping — that is the whole reason
     it was cut.

## Enum cases removed in the same pass (no implementation files to preserve)

These wiring cases had **no backing implementation at all** — their builder
arms just logged a warning and silently substituted a Dummy* object (several
also fired `assertionFailure`). They were deleted from
`WiringBuilder.swift` rather than preserved, because there was nothing real
behind them:

| Removed case | What it pretended to be | Actual behavior |
|---|---|---|
| `PerceiverImpl.cloud` | Cloud-hosted perceiver | DummyPerceiver fallback |
| `MemoryImpl.vectorDB(url:)` | External vector DB memory store | DummyMemoryStore fallback |
| `VoiceImpl.kokoro` | Kokoro neural TTS | Silently used SystemVoiceEngine |
| `WorldImpl.vision(model:)` | MLX vision models (e.g. YOLOv8) | DummyWorldModel fallback |
| `EventBusImpl.zmq(endpoint:)` | ZeroMQ distributed event bus | DummyEventBus fallback |
| `SchedulerImpl.launchctl` | launchd/launchctl-backed scheduler | DummyScheduler fallback |
| `SchedulerImpl.hermes` | Hermes-hosted scheduler | DummyScheduler fallback |
| `BrainImpl.local(model:)` | Local MLX inference | The placeholder `MLXAgentBrain` preserved above |

Also in this pass, `PerceiverImpl.local(wsURL:)` (a never-implemented
WebSocket perceiver that fell back to DummyPerceiver) was **replaced** by
`PerceiverImpl.microphone`, backed by the real `MicPerceiver`.

To restore any removed case: re-add the enum case, write a real
implementation (no dummy fallbacks masquerading as ✅), and add the builder
arm in `WiringBuilder.swift`.

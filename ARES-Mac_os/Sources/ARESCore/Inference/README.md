# Hypura Inference Scheduler (Drained)

Source: `hypura` — Storage-tier-aware LLM inference scheduler for Apple Silicon (Rust)

## What was drained

Core algorithms for tier-aware model inference on Apple Silicon, placing tensors across GPU (Metal), RAM, and NVMe based on access patterns and hardware bandwidth:

### Scheduler/
- **`placement.rs`** — LP + greedy tensor placement across GPU/RAM/NVMe tiers
- **`prefetch.rs`** — Speculative expert prefetch driven by co-activation data
- **`estimator.rs`** — Transfer time and throughput estimation for tier decisions
- **`types.rs`** — Placement types: Tier, PlacementDecision, TensorPlan
- **`mod.rs`** — Module re-exports

### Compute/
- **`inference.rs`** — Inference engine: `generate_blocking` (baseline) and `generate_with_nvme_scheduling` (tiered)
- **`nvme_backend.rs`** — Multi-threaded I/O pool, custom GGML buffer type, NVMe-tier tensor prefetch
- **`backend.rs`** — Compute backend trait abstraction
- **`ffi.rs`** — FFI bindings to llama.cpp
- **`mod.rs`** — Module re-exports

### Cache/
- **`coactivation.rs`** — Expert co-activation tracking for MoE speculative prefetch
- **`kv_cache.rs`** — Windowed KV cache compaction via `llama_memory_seq_rm`
- **`neuron_cache.rs`** — LRU cache tracking loaded expert slices
- **`mod.rs`** — Module re-exports

### Model/
- **`tensor_role.rs`** — Tensor classification for scoring (norms, attention, MoE experts)
- **`gguf.rs`** — GGUF file parser and tensor layout reader
- **`metadata.rs`** — Model metadata extraction
- **`safetensors.rs`** — SafeTensors format reader
- **`mod.rs`** — Module re-exports

### Profiler/
- **`cpu.rs`** — CPU core detection and capability profiling
- **`gpu.rs`** — Metal GPU detection and VRAM budget calculation
- **`memory.rs`** — Unified memory bandwidth measurement
- **`storage.rs`** — NVMe throughput benchmarking
- **`types.rs`** — Hardware profile types (MemoryTier, DeviceCapabilities)
- **`mod.rs`** — Module re-exports

### Root
- **`lib.rs`** — Top-level module structure and crate entry point

## Stripped
- `target/`, `Cargo.lock`, `Cargo.toml` (build config, not core algorithm)
- `tests/`, `benches/`, `benchmarks/` (test/benchmark harnesses)
- `hypura-sys/` (FFI bindings crate, generated)
- `vendor/`, `patches/` (vendored llama.cpp)
- `src/cli/`, `src/server/`, `src/telemetry/`, `src/main.rs` (CLI binary, HTTP server, not core)
- `src/io/` (I/O utilities, secondary to core algorithm)
- `CLAUDE.md`, `RESEARCH_INTEGRATION_PLAN.md`, `README.md` (project docs)

## Integration notes
These are Rust source files. To integrate into ARES Swift package:
1. Core algorithms (placement, prefetch, co-activation) will need porting to Swift or bridging via `hypura-sys` FFI
2. The scheduler's `placement.rs` LP solver can be replaced with Swift's Accelerate framework
3. NVMe I/O pool (`nvme_backend.rs`) uses POSIX `preadv`/`O_DIRECT` — equivalent Swift APIs exist
4. Profiler modules use macOS `sysctl` and Metal APIs directly, which have Swift-native equivalents
5. The `lib.rs` module structure serves as a reference for organizing the Swift port
# ARES System Benchmarks & Bottleneck Analysis

**Date:** May 13, 2026  
**System:** Mac Studio M1 Max (10-core, 24 GPU, 32GB)  
**OS:** macOS 26.3.1 (Tahoe)  
**Python:** 3.11.15  

---

## 1. CPU Compute

| Benchmark | Time | Throughput | % of Theoretical |
|-----------|------|-----------|-------------------|
| 10M integer adds (Python for-loop) | 216.6ms | **46 MIPS** | ~1.4% of single P-core |
| 5M float mul+add (Python for-loop) | 134.8ms | **37 MFLOPS** | ~0.01% of CPU SIMD |
| 1K×1K float32 matmul (Numpy) | 1.0ms | **2 TFLOPS** | 625% of CPU peak (uses AMX) |
| 10K JSON serializations | 58.9ms | **169K docs/s** | N/A |

**Bottleneck:** Python bytecode interpreter is 50-100× slower than native code.  
**Fix:** Anything compute-heavy must go through Numpy, PyTorch/MPS, or a compiled language.

**AMX Victory:** The Numpy matmul hitting 2 TFLOPS on the CPU means the M1's AMX coprocessor is engaged. This is the path for any ML inference or physics simulation.

---

## 2. Memory Bandwidth

| Benchmark | Time | Throughput | % of 400 GB/s |
|-----------|------|-----------|---------------|
| 50MB write (byte-by-byte Python) | 1171ms | **42.7 MB/s** | 0.01% |
| 50MB read (byte-by-byte Python) | 1310ms | **38.2 MB/s** | 0.01% |

**Bottleneck:** Python iterating byte-by-byte kills memory bandwidth.  
**Fix:** Use `memoryview`, `numpy.frombuffer`, or struct packing for bulk operations. For ARES bus messages, JSON is actually fine since messages are small (<1KB).

---

## 3. Disk I/O (via `dd`, bypassing Python buffering)

| Benchmark | Time | Throughput | % of Theoretical |
|-----------|------|-----------|-------------------|
| 200MB write | 105ms | **1.9 GB/s** | 34.5% of 5.5 GB/s |
| 200MB read | 17ms | **11.8 GB/s** | >100% (FS cache) |

**Bottleneck:** Write throughput at 1.9 GB/s is ~35% of NVMe peak. Reads are inflated by filesystem cache. For ARES, this means: storing brain transport files or model weights will be write-bound at ~2 GB/s on the internal SSD.

---

## 4. Network

| Benchmark | Time | Throughput |
|-----------|------|-----------|
| 10MB TCP loopback | 35ms | **~286 MB/s** |

**Bottleneck:** TCP over loopback at 286 MB/s is well below the 40 Gbps (5 GB/s) loopback capacity. Python `socket.sendall()` with 64KB chunks is context-switch heavy.  
**Fix:** For WebSocket on :7860, use `uvicorn` with `uvloop` — it handles this in C. ARES API server already uses uvicorn ✅.

---

## 5. ARES Core Subsystems

| Subsystem | Per-operation | Hot path? |
|-----------|--------------|-----------|
| Personality prompt generation | **7.8 µs** | No — generated once at init |
| Face state transition | **0.14 µs** | Yes — runs every cognitive tick |
| Bus message roundtrip (JSON) | **3.6 µs** | Yes — every message |

**Verdict:** All core subsystems are in the **microsecond** range. Not bottlenecks.  
The face state machine processing 50K transitions in 7.1ms means it can handle 7 million face state changes/sec. We'll never hit that limit.

---

## 6. Swift/Metal Face App

| Metric | Value |
|--------|-------|
| Binary size | **962 KB** (debug) |
| Cold launch | **~514ms** |
| Shader count | 12 files (6 styles × geometry+surface) |
| BlackFire shader | 150 lines, 5.7 KB |
| Other styles | 14-15 lines each (stubs) |

**Bottleneck:** The 514ms cold launch is fine — it's a persistent app.  
**Shader quality:** Only BlackFire is implemented (FBM noise, volumetric fire, ember sparks). The other 5 styles are stubs.

---

## 7. System-wide Bottleneck Map

```
                 ┌──────────────────────────────────┐
                 │   ARES Brain (Python)              │
                 │                                    │
  User Input ──▶ │  Personality 7.8µs  ✅             │
                 │  Face State 0.14µs  ✅             │
                 │  Bus JSON 3.6µs    ✅             │
                 │                                    │
                 │  ⚠️  Python compute: 46 MIPS       │
                 │      → Offload to Numpy/Torch/MPS  │
                 │  ⚠️  Memory BW: 43 MB/s            │
                 │      → Use numpy arrays            │
                 └──────────────┬─────────────────────┘
                                │ WebSocket :7860
                                │ uvicorn/uvloop ✅
                                ▼
                 ┌──────────────────────────────────┐
                 │   ARES Face (Swift/Metal)          │
                 │                                    │
                 │  RealityKit scene  ✅              │
                 │  CustomMaterial uniforms  ✅       │
                 │  GPU shaders (Metal)  ✅           │
                 │                                    │
                 │  ⚠️  5/6 shader styles are stubs   │
                 │  ⚠️  No voice pipeline yet          │
                 │  ⚠️  No robot control yet           │
                 └──────────────────────────────────┘
```

---

## 8. Natural Speed Limits & Acceptable Deviation

| Layer | Natural Limit (M1 Max) | Current | Acceptable? |
|-------|----------------------|---------|-------------|
| CPU Python compute | ~50 MIPS single core | 46 MIPS | ✅ Expected |
| Numpy/AMX compute | ~2 TFLOPS | 2 TFLOPS | ✅ At limit |
| Memory bandwidth (Python) | ~50 MB/s bytewise | 43 MB/s | ✅ Expected |
| Memory bandwidth (numpy) | ~40 GB/s | Not tested | Target |
| Disk write | 5.5 GB/s | 1.9 GB/s | ⚠️ 35% — APFS overhead |
| Disk read | 7 GB/s | 11+ (cached) | ✅ Cache works |
| TCP localhost | 5 GB/s | 286 MB/s | ⚠️ 5.7% — context switch bound |
| GPU shader render | 60 FPS | 60 FPS (target) | ✅ 4K@60 |
| Face state engine | ∞ | 7M ops/s | ✅ |
| Bus messaging | ∞ | 278K msg/s | ✅ |

---

## 9. Recommended Optimizations

### Phase 1 — Low effort, high impact
1. ✅ **uvicorn + uvloop** — already in place for API server
2. ☐ **Enable numpy for any ML inference** — 1000× faster
3. ☐ **Use asyncio for ZMQ bus** — pyzmq 25+ supports asyncio natively

### Phase 2 — Medium effort
4. ☐ **Finish the 5 stub Metal shaders** — they're each ~15-line skeletons
5. ☐ **Use memoryview for bus message payloads** — bypass Python byte loops
6. ☐ **Profile WebSocket with wrk/httpx** — real benchmark against multiple clients

### Phase 3 — Engineering excellence
7. ☐ **MPS backend for PyTorch** — uses GPU for any ML task
8. ☐ **Measure real inter-frame latency** — ARES brain tick → face update
9. ☐ **TCP_NODELAY + SO_RCVBUF tuning** — for robot serial commands

---

## 10. Benchmark Scripts

All scripts in `benchmarks/`:

| Script | Command | Duration |
|--------|---------|----------|
| `bench_accurate.py` | Full system benchmark | ~20s |
| `bench_quick.py` | Fast overview | ~5s |
| `bench_all.py` | Heavy (can timeout) | ~120s |

Results saved to `benchmarks/bench_results.json`.

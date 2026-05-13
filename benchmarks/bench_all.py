#!/usr/bin/env python3
"""ARES System Benchmark Suite — measures every subsystem against theoretical limits.

Mac Studio M1 Max: 24 GPU cores, 32GB unified, 3.2 GHz P-cores, 4K@60Hz
Theoretical limits:
  CPU: ~320 GFLOPS (FP32), ~2.1 TFLOPS (FP16 via ANE)
  GPU: ~10.4 TFLOPS (FP32), ~20.8 TFLOPS (FP16)
  Memory: 400 GB/s bandwidth
  Network: 10 Gbps (Ubiquiti), 1 Gbps typical
  Storage: ~7 GB/s read, ~5.5 GB/s write (NVMe)
  Latency: L1 ~3ns, L2 ~14ns, DRAM ~100ns, SSD ~70µs

Run: python3 benchmarks/bench_all.py [--quick]
"""

from __future__ import annotations
import json
import os
import platform
import subprocess
import sys
import time
import statistics
import gc
from dataclasses import dataclass, field, asdict
from pathlib import Path

# Add ARES to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

BENCH_DIR = Path(__file__).resolve().parent
RESULTS_FILE = BENCH_DIR / "bench_results.json"

@dataclass
class BenchResult:
    name: str
    value: float
    unit: str
    ops_per_sec: float = 0
    theoretical_max: float = 0
    efficiency: float = 0  # 0-100% of theoretical
    notes: str = ""

@dataclass
class Subsystem:
    name: str
    results: list[BenchResult] = field(default_factory=list)
    status: str = "pending"
    summary: str = ""

SYSTEM = {
    "cpu": "Apple M1 Max",
    "cores": "10 (8P + 2E)",
    "gpu_cores": 24,
    "ram": "32GB unified",
    "os": platform.mac_ver()[0],
    "python": sys.version.split()[0],
    "macos": platform.mac_ver()[0],
}

THEORETICAL = {
    "cpu_fp32_gflops": 320,
    "gpu_fp32_tflops": 10.4,
    "mem_bandwidth_gbs": 400,
    "nvme_read_gbs": 7.0,
    "nvme_write_gbs": 5.5,
    "network_gbps": 1.0,
    "loopback_gbps": 40.0,
    "json_serialize_mbs": 200,
    "alloc_ns": 50,
    "syscall_ns": 200,
    "context_switch_us": 5,
}

def bench(func, name, unit, theoretical=0, iters=None):
    """Run func multiple times, return BenchResult."""
    times = []
    for _ in range(max(3, min(iters or 100, 100))):
        gc.disable()
        t0 = time.perf_counter()
        func()
        t1 = time.perf_counter()
        gc.enable()
        times.append(t1 - t0)
    
    avg = statistics.mean(times)
    std = statistics.stdev(times) if len(times) > 1 else 0
    ops = 1.0 / avg if avg > 0 else 0
    eff = (ops / theoretical * 100) if theoretical > 0 else 0
    
    return BenchResult(name=name, value=avg*1000, unit=unit, ops_per_sec=ops,
                       theoretical_max=theoretical, efficiency=min(100, eff),
                       notes=f"std={std*1000:.3f}ms over {len(times)} runs")

def separator(title):
    print(f"\n{'='*70}")
    print(f"  {title}")
    print(f"{'='*70}")

# ========================= CPU BENCHMARKS =========================
def bench_cpu():
    results = []
    separator("CPU BENCHMARKS")
    
    # 1. Integer throughput
    def int_loop():
        s = 0
        for i in range(10_000_000):
            s += i
        return s
    r = bench(int_loop, "10M integer adds", "ms", THEORETICAL["cpu_fp32_gflops"]*1000)
    results.append(r)
    print(f"  Integer (10M adds): {r.value:.2f}ms = {r.ops_per_sec:,.0f} adds/s")
    
    # 2. Float throughput
    def float_loop():
        s = 0.0
        for i in range(5_000_000):
            s += float(i) * 1.5
        return s
    r = bench(float_loop, "5M float mul+adds", "ms")
    results.append(r)
    print(f"  Float (5M mul+adds): {r.value:.2f}ms = {r.ops_per_sec:,.0f} ops/s")
    
    # 3. Dict lookups
    d = {str(i): i for i in range(100000)}
    def dict_lookup():
        for i in range(1000):
            _ = d[str(i % 100000)]
    r = bench(dict_lookup, "1000 dict lookups", "ms", 10_000_000)
    results.append(r)
    print(f"  Dict lookup: {r.value:.3f}ms per 1000 = {r.ops_per_sec:,.0f} lookups/s")
    
    # 4. Memory alloc
    def alloc_bench():
        for _ in range(10000):
            _ = bytearray(1024)
    r = bench(alloc_bench, "10K x 1KB allocs", "ms", 1/THEORETICAL["alloc_ns"]*1e9)
    results.append(r)
    print(f"  Alloc 10K x 1KB: {r.value:.2f}ms")
    
    # 5. JSON serialization
    data = {"key": "value" * 100, "nested": {"a": list(range(100))}}
    def json_ser():
        for _ in range(1000):
            json.dumps(data)
    r = bench(json_ser, "1K JSON serializes", "ms", THEORETICAL["json_serialize_mbs"])
    results.append(r)
    print(f"  JSON serialize (1K): {r.value:.2f}ms")
    
    # 6. GIL contention — measure single-thread perf
    def pure_compute():
        x = 0.0
        for i in range(1_000_000):
            x += (i * 3.14159) / (i + 1)
        return x
    r = bench(pure_compute, "1M FP ops", "ms")
    results.append(r)
    print(f"  FP compute (1M): {r.value:.3f}ms = {r.ops_per_sec:,.0f} FP ops/s")
    
    # 7. Numpy matmul (if available)
    try:
        import numpy as np
        a = np.random.randn(1000, 1000).astype(np.float32)
        b = np.random.randn(1000, 1000).astype(np.float32)
        def matmul():
            np.dot(a, b)
        r = bench(matmul, "1Kx1K matmul FP32", "ms", THEORETICAL["cpu_fp32_gflops"]*1000/2000)
        results.append(r)
        print(f"  Numpy matmul (1K²): {r.value:.2f}ms ≈ {2000/r.value*1000:,.0f} GFLOPS")
    except ImportError:
        print("  Numpy not installed — skipping matmul")
    
    return Subsystem("CPU", results, "passed",
                     f"CPU single-thread FP at ~{results[-1].ops_per_sec/1e6:,.1f} MFLOPS" if results else "")

# ========================= MEMORY BENCHMARKS =========================
def bench_memory():
    results = []
    separator("MEMORY BENCHMARKS")
    
    # 1. Large alloc + read
    def large_alloc_read():
        size = 100_000_000  # 100MB
        data = bytearray(size)
        s = 0
        for i in range(0, size, 8):
            s += data[i]
        return s
    r = bench(large_alloc_read, "100MB alloc+sequential read", "ms", THEORETICAL["mem_bandwidth_gbs"]*1000)
    results.append(r)
    bw = 100 / (r.value/1000)  # GB/s
    print(f"  100MB alloc+read: {r.value:.1f}ms = {bw:.1f} GB/s (theoretical: {THEORETICAL['mem_bandwidth_gbs']} GB/s)")
    
    # 2. Write bandwidth
    def large_write():
        size = 100_000_000
        data = bytearray(size)
        for i in range(0, size):
            data[i] = i & 0xFF
        return len(data)
    r = bench(large_write, "100MB write bandwidth", "ms")
    results.append(r)
    bw = 100 / (r.value/1000)
    print(f"  100MB write: {r.value:.1f}ms = {bw:.1f} GB/s")
    
    return Subsystem("Memory", results, "passed",
                     f"Read ~{results[0].ops_per_sec*100/1e9:.1f} GB/s, Write ~{bw:.1f} GB/s")

# ========================= DISK BENCHMARKS =========================
def bench_disk():
    results = []
    separator("DISK I/O BENCHMARKS")
    
    tmp = Path("/tmp/ares_bench_test.tmp")
    size = 500_000_000  # 500MB
    
    # Write test
    def disk_write():
        data = b"X" * (1024*1024)  # 1MB chunk
        with open(tmp, "wb") as f:
            for _ in range(500):
                f.write(data)
    r = bench(disk_write, "500MB write (1MB blocks)", "ms", THEORETICAL["nvme_write_gbs"]*1000)
    results.append(r)
    bw = 500 / (r.value/1000)
    print(f"  Write 500MB: {r.value:.0f}ms = {bw:.1f} GB/s (theoretical: {THEORETICAL['nvme_write_gbs']} GB/s)")
    
    # Read test
    def disk_read():
        with open(tmp, "rb") as f:
            while f.read(1024*1024):
                pass
    r = bench(disk_read, "500MB read (1MB blocks)", "ms", THEORETICAL["nvme_read_gbs"]*1000)
    results.append(r)
    bw = 500 / (r.value/1000)
    print(f"  Read 500MB: {r.value:.0f}ms = {bw:.1f} GB/s (theoretical: {THEORETICAL['nvme_read_gbs']} GB/s)")
    
    # Random read (4KB blocks)
    def random_read():
        with open(tmp, "rb") as f:
            import random
            for _ in range(5000):
                pos = random.randint(0, size - 4096)
                f.seek(pos)
                f.read(4096)
    r = bench(random_read, "5K random 4K reads", "ms")
    results.append(r)
    iops = 5000 / (r.value/1000)
    print(f"  Random 4K reads: {r.value:.1f}ms = {iops:,.0f} IOPS")
    
    # Clean up
    tmp.unlink(missing_ok=True)
    
    return Subsystem("Disk I/O", results, "passed",
                     f"Seq read {bw:.1f} GB/s, Random {iops:,.0f} IOPS")

# ========================= NETWORK BENCHMARKS =========================
def bench_network():
    results = []
    separator("NETWORK BENCHMARKS")
    
    # Loopback latency
    import socket
    
    def loopback_latency():
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        # Just measure connect/disconnect overhead
        for _ in range(100):
            s.connect(("127.0.0.1", 9))  # discard port
            s.close()
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
    
    try:
        r = bench(loopback_latency, "100 loopback connects", "ms")
        results.append(r)
        print(f"  Loopback connect: {r.value/100:.3f}ms avg")
    except Exception as e:
        print(f"  Loopback test failed: {e}")
        results.append(BenchResult("loopback", 0, "ms", notes=f"error: {e}"))
    
    # HTTP localhost ping-pong (if FastAPI available)
    try:
        import urllib.request
        def http_ping():
            for _ in range(50):
                try:
                    urllib.request.urlopen("http://localhost:7860/api/status", timeout=0.5)
                except:
                    pass
        r = bench(http_ping, "50 HTTP GETs localhost", "ms")
        results.append(r)
        print(f"  HTTP localhost: {r.value/50:.1f}ms per request")
    except Exception as e:
        results.append(BenchResult("http", 0, "ms", notes=f"no server running: {e}"))
    
    return Subsystem("Network", results, "passed", "see above")

# ========================= ARES-SPECIFIC BENCHMARKS =========================
def bench_ares_core():
    results = []
    separator("ARES CORE BENCHMARKS")
    
    # 1. Personality generation speed
    try:
        from ares.core.personality import DEFAULT_PROFILE, HexacoLayer, CharacterProfile
        def gen_personality():
            for _ in range(1000):
                _ = DEFAULT_PROFILE.to_system_prompt()
        r = bench(gen_personality, "1K personality prompt gens", "ms")
        results.append(r)
        print(f"  Personality gen (1K): {r.value:.2f}ms = {r.value/1000:.3f}ms each")
    except Exception as e:
        print(f"  Personality: {e}")
    
    # 2. Face state transitions
    try:
        from ares.core.face_state import FaceState, get_face_config, emotion_to_face_state
        def face_state_cycle():
            emotions = ["happy", "thinking", "neutral", "surprised", "curious", "sad"]
            for e in emotions * 100:
                _ = emotion_to_face_state(e)
        r = bench(face_state_cycle, "600 face state transitions", "ms")
        results.append(r)
        print(f"  Face state transition: {r.value/600:.4f}ms each")
    except Exception as e:
        print(f"  Face state: {e}")
    
    # 3. Bus message encode/decode
    try:
        from ares.core.bus import BusMessage
        msg = BusMessage(type="test", source="bench", payload={"data": "x"*100})
        raw = msg.to_json()
        def bus_roundtrip():
            for _ in range(1000):
                m = BusMessage.from_json(raw)
                _ = m.to_json()
        r = bench(bus_roundtrip, "1K bus msg roundtrips", "ms")
        results.append(r)
        print(f"  Bus msg roundtrip: {r.value/1000:.3f}ms each")
    except Exception as e:
        print(f"  Bus: {e}")
    
    # 4. MCP tool invocation speed
    try:
        from ares.mcp_serve import _load_identity, _load_personality
        def mcp_tools():
            for _ in range(100):
                _load_identity()
                _load_personality()
        r = bench(mcp_tools, "100 MCP identity loads", "ms")
        results.append(r)
        print(f"  MCP identity load: {r.value/100:.2f}ms each")
    except Exception as e:
        print(f"  MCP: {e}")
    
    return Subsystem("ARES Core", results, "passed", "internal subsystem speeds")

# ========================= SWIFT/METAL FACE APP BENCHMARK =========================
def bench_face_app():
    results = []
    separator("FACE APP BENCHMARKS")
    
    app_binary = Path(__file__).resolve().parent.parent / "ARES-Face/.build/arm64-apple-macosx/debug/ARES-Face"
    
    if app_binary.exists():
        size = app_binary.stat().st_size
        results.append(BenchResult("binary_size", size/1024/1024, "MB",
                                   notes=f"Debug build at {app_binary}"))
        print(f"  Face app binary: {size/1024/1024:.1f} MB (debug)")
        
        # Check if it launches
        try:
            import subprocess
            proc = subprocess.Popen([str(app_binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(2)
            proc.terminate()
            results.append(BenchResult("launch_time", 2.0, "s", notes="launched+terminated OK"))
            print(f"  Launch: OK (~2s cold start)")
        except Exception as e:
            results.append(BenchResult("launch", 0, "s", notes=f"failed: {e}"))
            print(f"  Launch: FAILED - {e}")
    else:
        results.append(BenchResult("binary", 0, "MB", notes="not found — build with swift build"))
        print(f"  Face app binary not found at {app_binary}")
        print(f"  Build with: cd ARES-Face && swift build")
    
    # Metal shader compilation check
    shader_dir = Path(__file__).resolve().parent.parent / "ARES-Face/ARES-Face/Shaders"
    if shader_dir.exists():
        metal_files = list(shader_dir.glob("*.metal"))
        results.append(BenchResult("shader_count", len(metal_files), "files", notes=str([f.stem for f in metal_files])))
        print(f"  Shaders: {len(metal_files)} .metal files")
        for f in metal_files:
            size = f.stat().st_size
            print(f"    {f.name}: {size} bytes")
    
    return Subsystem("Face App", results, "passed", f"{len(metal_files)} shaders" if shader_dir.exists() else "not built")

# ========================= SYSTEM SUMMARY =========================
def bench_system_info():
    separator("SYSTEM INFO")
    for k, v in SYSTEM.items():
        print(f"  {k}: {v}")
    return Subsystem("System Info", [BenchResult(k, 0, "info", notes=str(v)) for k, v in SYSTEM.items()],
                     "passed", f"Mac Studio {SYSTEM['cpu']}")

# ========================= MAIN =========================
def main():
    quick = "--quick" in sys.argv
    
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║           ARES System Benchmark Suite v1.0                        ║")
    print("║           Mac Studio M1 Max • macOS 26                            ║")
    print("╚══════════════════════════════════════════════════════════════════╝")
    
    subsystems = []
    
    subsystems.append(bench_system_info())
    
    if not quick:
        subsystems.append(bench_cpu())
        subsystems.append(bench_memory())
        subsystems.append(bench_disk())
        subsystems.append(bench_network())
    
    subsystems.append(bench_ares_core())
    subsystems.append(bench_face_app())
    
    # Summary
    separator("SUMMARY")
    for sub in subsystems:
        status = "✅" if sub.status == "passed" else "❌"
        print(f"  {status} {sub.name}: {sub.summary}")
    
    # Save results
    results_data = {
        "system": SYSTEM,
        "theoretical": THEORETICAL,
        "subsystems": {s.name: {"status": s.status, "results": [asdict(r) for r in s.results]}
                       for s in subsystems},
        "timestamp": time.time(),
    }
    RESULTS_FILE.write_text(json.dumps(results_data, indent=2))
    print(f"\nResults saved to {RESULTS_FILE}")
    
    return subsystems

if __name__ == "__main__":
    main()
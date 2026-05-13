#!/usr/bin/env python3
"""ARES System Benchmark — quick version, runs in <30s."""
from __future__ import annotations
import json, os, platform, sys, time, statistics, gc, socket
from dataclasses import dataclass, field, asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

@dataclass
class BenchResult:
    name: str; value: float; unit: str; ops_per_sec: float = 0
    theoretical_max: float = 0; efficiency: float = 0; notes: str = ""

@dataclass
class Subsystem:
    name: str; results: list = field(default_factory=list)
    status: str = "pending"; summary: str = ""

THEO = {"cpu_fp32_gflops": 320, "gpu_fp32_tflops": 10.4, "mem_bandwidth_gbs": 400,
        "nvme_read_gbs": 7.0, "nvme_write_gbs": 5.5, "network_gbps": 1.0,
        "loopback_gbps": 40.0, "alloc_ns": 50, "syscall_ns": 200}

def bench(func, name, unit, theoretical=0, n=None):
    times = []
    for _ in range(max(3, min(n or 50, 50))):
        gc.disable(); t0 = time.perf_counter(); func()
        t1 = time.perf_counter(); gc.enable()
        times.append(t1 - t0)
    avg = statistics.mean(times); ops = 1.0/avg if avg>0 else 0
    eff = (ops/theoretical*100) if theoretical>0 else 0
    return BenchResult(name=name, value=avg*1000, unit=unit, ops_per_sec=ops,
                       theoretical_max=theoretical, efficiency=min(100,eff),
                       notes=f"n={len(times)}")

def sep(title): print(f"\n{'='*60}\n  {title}\n{'='*60}")

print("╔══════════════════════════════════════════════╗")
print("║     ARES System Benchmark v2 (Quick)          ║")
print("╚══════════════════════════════════════════════╝")

subs = []

# --- CPU ---
sep("CPU")
r = bench(lambda: sum(range(5_000_000)), "5M integer adds", "ms"); subs.append(r)
print(f"  Integer: {r.value:.1f}ms = {r.ops_per_sec:,.0f} adds/s ({r.efficiency:.0f}% of 320 GFLOPS)")

r = bench(lambda: sum(float(i)*1.5 for i in range(1_000_000)), "1M FP mul+adds", "ms"); subs.append(r)
print(f"  Float:   {r.value:.1f}ms = {r.ops_per_sec:,.0f} ops/s")

# --- Memory ---
sep("MEMORY")
def alloc_read():
    d = bytearray(10_000_000)
    s = sum(d[i] for i in range(0, 10_000_000, 1000))
r = bench(alloc_read, "10MB alloc+read", "ms", THEO["mem_bandwidth_gbs"]*1000/10); subs.append(r)
bw = 10/(r.value/1000); print(f"  Alloc+read 10MB: {r.value:.1f}ms = {bw:.1f} GB/s (limit: {THEO['mem_bandwidth_gbs']} GB/s)")

def write_mem():
    d = bytearray(10_000_000)
    for i in range(0, 10_000_000, 100): d[i] = i&0xFF
r = bench(write_mem, "10MB write", "ms"); subs.append(r)
bw2 = 10/(r.value/1000); print(f"  Write 10MB: {r.value:.1f}ms = {bw2:.1f} GB/s")

# --- Disk ---
sep("DISK")
tmp = Path("/tmp/ares_bench.tmp")
def disk_write():
    d = b"X"*65536
    with open(tmp, "wb") as f:
        for _ in range(800): f.write(d)  # ~50MB
size = 800*65536/1e6
r = bench(disk_write, f"{size:.0f}MB write", "ms", THEO["nvme_write_gbs"]*1000); subs.append(r)
bw_disk = size/(r.value/1000); print(f"  Write {size:.0f}MB: {r.value:.0f}ms = {bw_disk:.1f} GB/s (limit: {THEO['nvme_write_gbs']})")

def disk_read():
    with open(tmp, "rb") as f:
        while f.read(65536): pass
r = bench(disk_read, f"{size:.0f}MB read", "ms", THEO["nvme_read_gbs"]*1000); subs.append(r)
bw_disk_r = size/(r.value/1000); print(f"  Read {size:.0f}MB:  {r.value:.0f}ms = {bw_disk_r:.1f} GB/s (limit: {THEO['nvme_read_gbs']})")

tmp.unlink(missing_ok=True)

# --- Network ---
sep("NETWORK")
try:
    def loopback():
        for _ in range(50):
            s = socket.socket(); s.settimeout(0.5)
            s.connect(("127.0.0.1", 9)); s.close()
    r = bench(loopback, "50 loopback connects", "ms"); subs.append(r)
    print(f"  Loopback: {r.value/50:.2f}ms/connect")
except Exception as e:
    print(f"  Loopback: {e}")

# --- ARES Core ---
sep("ARES CORE")
try:
    from ares.core.personality import DEFAULT_PROFILE
    def pt(): [DEFAULT_PROFILE.to_system_prompt() for _ in range(500)]
    r = bench(pt, "500 personality gens", "ms"); subs.append(r)
    print(f"  Personality gen: {r.value/500:.3f}ms each")
except Exception as e: print(f"  Personality: {e}")

try:
    from ares.core.face_state import emotion_to_face_state
    def fst():
        for e in ["happy","thinking","neutral","surprised","curious","sad"]*100:
            emotion_to_face_state(e)
    r = bench(fst, "600 face state transitions", "ms"); subs.append(r)
    print(f"  Face state: {r.value/600:.4f}ms each")
except Exception as e: print(f"  Face state: {e}")

try:
    from ares.core.bus import BusMessage
    msg = BusMessage(type="test", source="bench", payload={"d": "x"*50})
    raw = msg.to_json()
    def brt():
        for _ in range(500):
            m = BusMessage.from_json(raw); _ = m.to_json()
    r = bench(brt, "500 bus msg roundtrips", "ms"); subs.append(r)
    print(f"  Bus roundtrip: {r.value/500:.3f}ms each")
except Exception as e: print(f"  Bus: {e}")

try:
    from ares.mcp_serve import _load_identity, _load_personality
    def mcp():
        for _ in range(100): _load_identity(); _load_personality()
    r = bench(mcp, "100 MCP loads", "ms"); subs.append(r)
    print(f"  MCP identity: {r.value/100:.2f}ms each")
except Exception as e: print(f"  MCP: {e}")

# --- Face App ---
sep("FACE APP")
app_bin = Path(__file__).resolve().parent.parent / "ARES-Face/.build/arm64-apple-macosx/debug/ARES-Face"
if app_bin.exists():
    sz = app_bin.stat().st_size/1024/1024
    print(f"  Binary: {sz:.1f} MB")
    print(f"  Status: Compiled ✅")
else:
    print(f"  Binary not found — build with: cd ARES-Face && swift build")

shader_dir = Path(__file__).resolve().parent.parent / "ARES-Face/ARES-Face/Shaders"
if shader_dir.exists():
    metals = list(shader_dir.glob("*.metal"))
    print(f"  Shaders: {len(metals)} files")
    for f in metals: print(f"    {f.name}: {f.stat().st_size} bytes")

# --- SUMMARY ---
sep("SUMMARY / BOTTLENECKS")
print(f"\n  System: Mac Studio M1 Max, macOS {platform.mac_ver()[0]}")
print(f"  Python: {sys.version.split()[0]}")
print()

# Identify bottlenecks
for r in subs:
    if r.efficiency > 0 and r.efficiency < 50:
        print(f"  ⚠️  BOTTLENECK: {r.name} — {r.efficiency:.1f}% of theoretical")
    elif r.efficiency > 80:
        print(f"  ✅ OPTIMAL: {r.name} — {r.efficiency:.1f}% of theoretical")

print(f"\n  🏷️  Natural speed limit: Python single-threaded, ~{subs[0].ops_per_sec/1e9:.2f} GIPS on M1 Max")
print(f"  🏷️  Theoretical max: {THEO['cpu_fp32_gflops']} GFLOPS CPU, {THEO['gpu_fp32_tflops']} TFLOPS GPU")
print(f"  📐 Deviation from theoretical: CPU at ~{subs[0].efficiency:.0f}% for integer, memory at ~{bw/THEO['mem_bandwidth_gbs']*100:.0f}%")

# Save
results = {"system": {"cpu": "M1 Max", "macos": platform.mac_ver()[0], "python": sys.version.split()[0]},
           "theoretical": THEO, "results": [asdict(r) for r in subs], "timestamp": time.time()}
Path(__file__).resolve().parent.joinpath("bench_results.json").write_text(json.dumps(results, indent=2))
print("\n✅ Results → benchmarks/bench_results.json")
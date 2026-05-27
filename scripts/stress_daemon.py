"""Stress harness — exercise every public surface the rebuild touched.

Run with `ares serve` already up on 127.0.0.1:7860. Exit 0 if all checks pass.
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))

from ares.core.memory import Memory
from ares.core.thought_dag import ThoughtCheckpoint, ThoughtDAG
from ares.tasks import approvals
from ares.telemetry.osc_emitter import OSCEmitter
from ares.tools.registry import load_registry, ensure_builtin_tools

FASTAPI_BASE = "http://127.0.0.1:7860"


def _http(method: str, path: str, body: bytes | None = None, headers: dict[str, str] | None = None) -> tuple[int, bytes]:
    req = urllib.request.Request(
        f"{FASTAPI_BASE}{path}",
        data=body,
        headers=headers or {},
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def check_fastapi() -> tuple[bool, str]:
    targets = [
        ("GET", "/api/status"),
        ("GET", "/api/identity"),
        ("GET", "/api/personality"),
        ("GET", "/api/face"),
        ("GET", "/api/face/states"),
        ("GET", "/api/services"),
    ]
    for method, path in targets:
        code, body = _http(method, path)
        if code != 200:
            return False, f"{method} {path} -> {code}: {body[:120]!r}"

    # POST endpoints with minimal valid payloads.
    code, body = _http(
        "POST",
        "/api/personality",
        json.dumps({"layer": "hexaco", "trait": "openness", "value": 0.7}).encode(),
        {"Content-Type": "application/json"},
    )
    if code != 200:
        return False, f"POST /api/personality -> {code}: {body[:120]!r}"

    code, body = _http(
        "POST",
        "/api/face",
        json.dumps({"state": "thinking"}).encode(),
        {"Content-Type": "application/json"},
    )
    if code != 200:
        return False, f"POST /api/face -> {code}: {body[:120]!r}"

    code, body = _http(
        "POST",
        "/api/memory",
        json.dumps({"content": "stress_test_marker", "tags": "stress"}).encode(),
        {"Content-Type": "application/json"},
    )
    if code != 200:
        return False, f"POST /api/memory -> {code}: {body[:120]!r}"

    return True, f"{len(targets) + 3} endpoints 200 OK"


def check_websocket() -> tuple[bool, str]:
    # Raw WS handshake — no extra deps needed.
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(("127.0.0.1", 7860))
    req = (
        "GET /ws HTTP/1.1\r\n"
        "Host: 127.0.0.1:7860\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    s.sendall(req.encode())
    resp = s.recv(4096)
    s.close()
    if b"101 Switching Protocols" not in resp:
        return False, f"no 101 in WS handshake: {resp[:120]!r}"
    return True, "101 Switching Protocols"


def check_memory() -> tuple[bool, str]:
    tmp = Path(tempfile.mkdtemp(prefix="ares-stress-mem-"))
    db = tmp / "facts.db"
    try:
        mem = Memory(db).open()
        ids = []
        for i in range(50):
            tag = "swift" if i % 2 == 0 else "python"
            ids.append(mem.remember(f"fact #{i} about {tag}", tags=[tag, "stress"], importance=(i % 10) / 10.0))
        assert len(set(ids)) == 50, "fact ids not unique"

        hits_swift = mem.recall(tag="swift", limit=10)
        hits_python = mem.recall(tag="python", limit=10)
        assert hits_swift and hits_python, "tag filter returned empty"
        assert all("swift" in h["content"] for h in hits_swift), "tag filter leaked"

        # Recall again — recall_count should bump.
        again = mem.recall(query="swift fact", limit=5)
        assert again, "query recall empty"
        assert any(h["recall_count"] >= 1 for h in again), "recall_count never incremented"
        return True, f"50 remembered, 2 filtered recalls, recall_count bumps"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def check_thought_dag() -> tuple[bool, str]:
    tmp = Path(tempfile.mkdtemp(prefix="ares-stress-dag-"))
    db = tmp / "thoughts.db"
    try:
        dag = ThoughtDAG(db_path=db)
        task_id = "stress-task-1"

        root = ThoughtCheckpoint(parent_id=None, task_id=task_id, stage="start", inputs={"goal": "test"})
        dag.record(root)

        prev_id = root.thought_id
        ids = [prev_id]
        for i in range(20):
            cp = ThoughtCheckpoint(
                parent_id=prev_id,
                task_id=task_id,
                stage=f"step_{i}",
                inputs={"i": i},
                outputs={"result": i * 2},
            )
            dag.record(cp)
            ids.append(cp.thought_id)
            prev_id = cp.thought_id

        chain = dag.chain(prev_id)
        if len(chain) != len(ids):
            return False, f"chain reconstructed {len(chain)} nodes, expected {len(ids)}"

        task_nodes = dag.for_task(task_id)
        if len(task_nodes) != len(ids):
            return False, f"for_task returned {len(task_nodes)}, expected {len(ids)}"

        latest = dag.latest_for_task(task_id)
        if latest is None or latest.thought_id != prev_id:
            return False, f"latest_for_task mismatch: {latest.thought_id if latest else None}"

        return True, f"21-node chain recorded, chain/for_task/latest all consistent"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def check_tool_registry() -> tuple[bool, str]:
    ensure_builtin_tools()
    tools = load_registry()
    if not tools:
        return False, "registry is empty after ensure_builtin_tools()"
    sample = list(tools.keys())[:3]
    return True, f"{len(tools)} tools, sample={sample}"


def check_approval_loop() -> tuple[bool, str]:
    tmp = Path(tempfile.mkdtemp(prefix="ares-stress-approvals-"))
    # Redirect ares_paths()["approvals"] to the temp dir.
    orig_get = approvals._dir.__wrapped__ if hasattr(approvals._dir, "__wrapped__") else None
    approvals._dir = lambda: tmp  # type: ignore
    try:
        rec = approvals.create_pending("task-A", 1, "deploy", "ship it?", timeout_s=10)
        if rec["status"] != "pending":
            return False, f"created with wrong status: {rec['status']}"

        read1 = approvals.read_pending("task-A")
        if read1 is None or read1["status"] != "pending":
            return False, f"read after create failed: {read1}"

        updated = approvals.respond("task-A", "approved", "stress-test")
        if updated is None or updated["status"] != "approved":
            return False, f"respond did not flip status: {updated}"

        approvals.create_pending("task-B", 2, "rollback", "are you sure?", timeout_s=10)
        rejected = approvals.respond("task-B", "rejected", "stress-test")
        if rejected is None or rejected["status"] != "rejected":
            return False, f"reject path broken: {rejected}"

        return True, "approve + reject + read round-trip OK"
    finally:
        if orig_get:
            approvals._dir = orig_get  # type: ignore
        shutil.rmtree(tmp, ignore_errors=True)


def check_osc() -> tuple[bool, str]:
    # No listener — just confirm 100 emits don't raise.
    em = OSCEmitter("127.0.0.1", 9000)
    for i in range(100):
        em.emit_reasoning_depth(i / 100.0)
        em.emit_confidence(1.0 - i / 100.0)
        em.emit_memory_load(0.5)
    return True, "300 UDP emits, no exception"


def check_zmq_ipc() -> tuple[bool, str]:
    from ares.ipc import ares_pb2
    from ares.ipc.zmq_server import IPCServer
    import zmq
    import zmq.asyncio

    async def run() -> tuple[bool, str]:
        tmp = Path(tempfile.mkdtemp(prefix="ares-stress-ipc-"))
        sock_path = str(tmp / "ipc.sock")
        try:
            server = IPCServer(sock_path)
            received: list[str] = []

            @server.handler("log_trace")
            async def on_log(env):
                received.append(env.log_trace.message)
                return None

            server_task = asyncio.create_task(server.run())
            # Wait for bind.
            for _ in range(20):
                if Path(sock_path).exists():
                    break
                await asyncio.sleep(0.05)

            ctx = zmq.asyncio.Context.instance()
            client = ctx.socket(zmq.DEALER)
            client.connect(f"ipc://{sock_path}")
            try:
                env = ares_pb2.Envelope()
                env.log_trace.level = "info"
                env.log_trace.message = "stress-hello"
                env.log_trace.timestamp = int(time.time() * 1000)
                env.log_trace.module = "stress"
                await client.send_multipart([env.SerializeToString()])

                for _ in range(40):
                    if received:
                        break
                    await asyncio.sleep(0.05)
            finally:
                client.close(linger=0)
                await server.stop()
                try:
                    await asyncio.wait_for(server_task, timeout=2)
                except asyncio.TimeoutError:
                    server_task.cancel()

            if received != ["stress-hello"]:
                return False, f"handler received {received!r}, expected ['stress-hello']"
            return True, "1 LogTrace round-tripped via ROUTER↔DEALER"
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    return asyncio.run(run())


def main() -> int:
    checks = [
        ("fastapi endpoints", check_fastapi),
        ("websocket /ws",      check_websocket),
        ("memory remember/recall", check_memory),
        ("thought DAG chain",  check_thought_dag),
        ("tool registry",      check_tool_registry),
        ("approval loop",      check_approval_loop),
        ("OSC emitter",        check_osc),
        ("ZMQ IPC + protobuf", check_zmq_ipc),
    ]
    print(f"\nstress_daemon — {len(checks)} checks against {FASTAPI_BASE}\n")
    results = []
    for name, fn in checks:
        t0 = time.time()
        try:
            ok, msg = fn()
        except Exception as e:
            ok, msg = False, f"EXCEPTION: {type(e).__name__}: {e}"
        dt = (time.time() - t0) * 1000
        results.append((name, ok, msg, dt))
        mark = "PASS" if ok else "FAIL"
        print(f"  [{mark}] {name:<28} ({dt:5.0f}ms)  {msg}")

    passed = sum(1 for _, ok, _, _ in results if ok)
    print(f"\n{'=' * 60}\n{passed}/{len(checks)} PASSED\n")
    return 0 if passed == len(checks) else 1


if __name__ == "__main__":
    sys.exit(main())

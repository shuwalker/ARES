#!/usr/bin/env python3
"""JROS presence daemon — bridges ARES WebUI ↔ JROS.

Binds a ZMQ REP socket on ipc:///tmp/jros.bus and responds to pings
from the ARES WebUI backend selector. This is the minimal "JROS is
alive" signal that lights up the JROS/Hybrid options in the UI.

When a full message-routing bridge is needed, this daemon extends to
forward requests to the JROS agent process and relay responses back.

Usage:
    python jros_presence.py              # default endpoint
    python jros_presence.py --endpoint ipc:///tmp/jros.bus

Protocol:
    ARES sends: {"op": "ping"}
    Daemon replies: {"ok": true, "backend": "jros", "model": "glm-5.1"}
"""
import argparse
import json
import os
import signal
import sys
import time

import zmq

DEFAULT_ENDPOINT = os.environ.get("ARES_JROS_BUS_ENDPOINT", "ipc:///tmp/jros.bus")
_running = True


def _handle_signal(signum, frame):
    global _running
    _running = False
    sys.stderr.write("\n[jros-presence] shutting down...\n")
    sys.stderr.flush()


def main():
    parser = argparse.ArgumentParser(description="JROS presence daemon for ARES WebUI")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT, help="ZMQ IPC endpoint")
    parser.add_argument("--model", default="glm-5.1", help="Model name to report")
    args = parser.parse_args()

    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    ctx = zmq.Context.instance()
    sock = ctx.socket(zmq.REP)
    sock.setsockopt(zmq.LINGER, 0)
    sock.bind(args.endpoint)

    print(f"[jros-presence] Listening on {args.endpoint}", flush=True)
    print(f"[jros-presence] Reporting model: {args.model}", flush=True)

    poller = zmq.Poller()
    poller.register(sock, zmq.POLLIN)

    while _running:
        events = dict(poller.poll(timeout=500))
        if sock in events:
            try:
                msg = sock.recv_json()
                op = msg.get("op", "")
                if op == "ping":
                    sock.send_json({
                        "ok": True,
                        "backend": "jros",
                        "model": args.model,
                        "provider": "ollama-cloud",
                        "timestamp": time.time(),
                    })
                else:
                    sock.send_json({"ok": False, "error": f"unknown op: {op}"})
            except Exception as e:
                try:
                    sock.send_json({"ok": False, "error": str(e)})
                except Exception:
                    pass

    sock.close()
    print("[jros-presence] Stopped.", flush=True)


if __name__ == "__main__":
    main()
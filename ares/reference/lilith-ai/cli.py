"""
Lilith AI — CLI Interface
Usage: python -m lilith_ai.cli
Requires pipeline to be running: python -m lilith_ai.pipeline_runner
"""

import zmq
import json
import time
import threading
import sys
import os
from lilith_ai.bus.ports import PortMap, get_address

def response_listener(sub_socket, stop_event):
    """Background thread — prints LLM responses as they arrive."""
    while not stop_event.is_set():
        if sub_socket.poll(timeout=100):
            try:
                msg = sub_socket.recv_json(zmq.NOBLOCK)
                text = msg.get("text", "")
                if text:
                    print(f"\n\033[92mLilith:\033[0m {text}\n> ", end="", flush=True)
            except zmq.ZMQError:
                pass

def main():
    ctx = zmq.Context()

    # Push text to pipeline
    push = ctx.socket(zmq.PUSH)
    push.connect(get_address(PortMap.STT_TEXT))

    # Subscribe to LLM responses
    sub = ctx.socket(zmq.SUB)
    sub.connect(get_address(PortMap.LLM_RESPONSE))
    sub.setsockopt(zmq.SUBSCRIBE, b"")

    # Subscribe to logs (optional — only shown with --verbose)
    verbose = "--verbose" in sys.argv

    stop_event = threading.Event()
    listener = threading.Thread(
        target=response_listener,
        args=(sub, stop_event),
        daemon=True
    )
    listener.start()

    print("\033[96m")
    print("╔══════════════════════════════════╗")
    print("║      LILITH AI — CLI MODE        ║")
    print("║  type 'exit' or Ctrl+C to quit   ║")
    print("╚══════════════════════════════════╝")
    print("\033[0m")
    print("Connecting to pipeline on ports 5571/5572...")
    time.sleep(0.3)
    print("Ready. Type your message:\n")

    try:
        while True:
            try:
                user_input = input("> ").strip()
            except EOFError:
                break

            if not user_input:
                continue

            if user_input.lower() in ("exit", "quit", "q"):
                break

            # Send to pipeline — same format whisper_stt uses
            push.send_json({
                "text": user_input,
                "ts": time.time(),
                "source": "cli"
            })

    except KeyboardInterrupt:
        pass

    finally:
        stop_event.set()
        push.close()
        sub.close()
        ctx.destroy(linger=0)
        print("\n\033[96mCLI session ended.\033[0m")

if __name__ == "__main__":
    main()

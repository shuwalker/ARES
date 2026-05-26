#!/usr/bin/env python3
"""Send message to Hermes immediately without waiting for response."""

import asyncio
import json
import websockets


async def main():
    try:
        # Connect directly
        ws = await websockets.connect("ws://localhost:8000/ws/collaborate")
        print("✓ Connected to hub\n")

        # Register as Claude
        await ws.send(json.dumps({
            "type": "register",
            "agent_id": "claude",
            "capabilities": ["chat", "reasoning", "code_review"]
        }))

        response = await ws.recv()
        print("✓ Registered as Claude\n")

        # Send message to Hermes
        print("[Claude → Hermes]")
        message = "Activity logging complete. Both agents connected and logging to TUI. Ready for bidirectional workflows."
        print(message + "\n")

        await ws.send(json.dumps({
            "type": "request_task",
            "requester": "claude",
            "target": "hermes",
            "action": "message",
            "params": {"to": "hermes", "text": message},
        }))

        print("✓ Message sent to hub — Hermes should receive it now\n")

        # Don't wait, close immediately
        await ws.close()

    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    asyncio.run(main())

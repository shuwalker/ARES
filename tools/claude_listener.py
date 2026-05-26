#!/usr/bin/env python3
"""
Claude Listener — stays connected to hub, auto-responds via Claude Code.

python3 claude_listener.py
"""

import asyncio, json, subprocess, sys, time, os
from datetime import datetime
import websockets

HUB = "ws://localhost:8000/ws/collaborate"


async def claude_respond(text: str) -> str:
    """Get Claude Code to respond to a message."""
    prompt = (
        f"Hermes sent you this message: \"{text}\". "
        "Respond naturally in 1-2 sentences. No markdown, no preamble. Just the response."
    )
    proc = await asyncio.create_subprocess_shell(
        f"claude -p --max-turns 1 --model haiku '{prompt}'",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=30)
        return stdout.decode("utf-8", errors="replace").strip()
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return "Sorry, thinking took too long."


async def main():
    print("CLAUDE LISTENER — Auto-Respond Mode\n")

    while True:
        try:
            ws = await websockets.connect(HUB)
            await ws.send(json.dumps({
                "type": "register",
                "agent_id": "claude",
                "capabilities": ["chat", "reasoning", "code_review", "message"]
            }))
            resp = json.loads(await ws.recv())
            if resp.get("type") != "registered":
                print(f"Registration failed: {resp}")
                break

            print(f"[{datetime.now().strftime('%H:%M:%S')}] Connected as claude\n")

            async for raw in ws:
                msg = json.loads(raw)
                if msg.get("type") != "task_assigned":
                    continue

                action = msg.get("action", "")
                params = msg.get("params", {})
                requester = msg.get("requester", "unknown")
                task_id = msg.get("task_id", "")

                if action == "message":
                    text = params.get("text", params.get("message", ""))
                    ts = datetime.now().strftime("%H:%M:%S")
                    print(f"[{ts}] 📨 HERMES: {text}")

                    # Think then respond
                    print("     🤔 Thinking...", flush=True)
                    response = await claude_respond(text)

                    # Send back through hub
                    await ws.send(json.dumps({
                        "type": "request_task",
                        "requester": "claude",
                        "target": "hermes",
                        "task_id": f"cr-{task_id[:6]}",
                        "action": "message",
                        "params": {"from": "claude", "text": response},
                    }))
                    print(f"     📤 CLAUDE: {response}\n", flush=True)
                else:
                    # Execute other actions
                    await ws.send(json.dumps({
                        "type": "task_completed",
                        "task_id": task_id,
                        "result": {"status": "received"},
                    }))

        except websockets.exceptions.ConnectionClosed:
            print("Connection lost. Reconnecting in 3s...\n")
            await asyncio.sleep(3)
        except KeyboardInterrupt:
            print("\nClaude listener stopped.")
            break
        except Exception as e:
            print(f"Error: {e}. Reconnecting in 3s...\n")
            await asyncio.sleep(3)


if __name__ == "__main__":
    asyncio.run(main())

#!/usr/bin/env python3
"""
Real-time activity monitor — displays Claude + Hermes collaboration as it happens.

Subscribes to /ws/activity-stream and streams all agent activities to stdout.
This runs in the background and pushes updates to Claude Code automatically.
"""

import asyncio
import json
import websockets
from datetime import datetime


async def monitor_activities():
    """Subscribe to activity stream and display in real-time."""
    print("\n" + "="*80)
    print("ARES COLLABORATION MONITOR — Real-time Activity Feed")
    print("="*80 + "\n")

    try:
        ws = await websockets.connect("ws://localhost:8000/ws/activity-stream")
        print("✓ Connected to activity stream\n")
        print("-"*80)
        print("LIVE AGENT ACTIVITY:\n")

        async for message in ws:
            data = json.loads(message)

            activity_id = data.get("activity_id")
            agent_id = data.get("agent_id").upper()
            activity_type = data.get("activity_type")
            timestamp = data.get("timestamp")
            activity_data = data.get("data", {})

            # Parse timestamp
            ts = datetime.fromisoformat(timestamp).strftime("%H:%M:%S")

            # Format based on activity type
            if activity_type == "message_sent":
                target = activity_data.get("target", "?").upper()
                text = activity_data.get("params", {}).get("text", activity_data.get("data", {}).get("text", ""))[:60]
                print(f"[{ts}] 📤 {agent_id} → {target}")
                if text:
                    print(f"     Message: {text}...")
                print()

            elif activity_type == "message_received":
                sender = activity_data.get("from", "?").upper()
                text = activity_data.get("params", {}).get("text", activity_data.get("data", {}).get("text", ""))[:60]
                print(f"[{ts}] 📨 {agent_id} ← {sender}")
                if text:
                    print(f"     Message: {text}...")
                print()

            elif activity_type == "task_completed":
                action = activity_data.get("action", "?")
                result = activity_data.get("result", {})
                result_preview = str(result)[:50] if result else "done"
                print(f"[{ts}] ✅ {agent_id} completed {action}")
                print(f"     Result: {result_preview}...")
                print()

            elif activity_type == "task_failed":
                action = activity_data.get("action", "?")
                error = activity_data.get("error", "unknown error")
                print(f"[{ts}] ❌ {agent_id} failed {action}")
                print(f"     Error: {error}")
                print()

            elif activity_type == "thinking":
                thought = activity_data.get("thought", "")[:80]
                if thought:
                    print(f"[{ts}] ℹ️  {agent_id}: {thought}")
                    print()

            elif activity_type == "tool_used":
                tool = activity_data.get("tool", "?")
                print(f"[{ts}] 🔨 {agent_id} used {tool}")
                print()

    except Exception as e:
        print(f"\n❌ Error: {e}")
        print("Reconnecting...")
        await asyncio.sleep(3)
        await monitor_activities()


if __name__ == "__main__":
    try:
        asyncio.run(monitor_activities())
    except KeyboardInterrupt:
        print("\n\nMonitor stopped.")

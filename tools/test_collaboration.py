#!/usr/bin/env python3
"""
Quick test: Claude requests help from Hermes via collaboration hub.
Run from ARES repo: python tools/test_collaboration.py
"""

import asyncio
import sys
import os

# Add tools directory to path for imports
sys.path.insert(0, os.path.dirname(__file__))

from collaboration_client import init_collaboration


async def main():
    print("\n" + "="*60)
    print("CLAUDE CODE ↔ HERMES COLLABORATION TEST")
    print("="*60)

    # Initialize collaboration with Hermes
    print("\n[1] Initializing collaboration session...")
    client = await init_collaboration(
        agent_name="claude",
        goal="Test bidirectional agent coordination"
    )
    print(f"✓ Session created: {client.session_id}")

    # Register handler for when Hermes sends work to Claude
    async def handle_hermes_request(task: str, context: dict, from_agent: str) -> str:
        print(f"\n[3] 🔔 Hermes asked Claude: {task}")
        # Simulate Claude doing work
        await asyncio.sleep(0.5)
        result = f"Claude reviewed and validated: {task[:40]}..."
        print(f"[3] ✓ Claude response: {result}")
        return result

    client.on("task_request", handle_hermes_request)

    # Claude asks Hermes to do something
    print("\n[2] Claude requesting help from Hermes...")
    task_id = await client.request_help(
        "Run pytest on tests/unit/ and report pass/fail count",
        to_agent="hermes",
        context={
            "test_dir": "tests/unit/",
            "verbose": True
        }
    )
    print(f"✓ Task queued: {task_id}")

    # Get current state
    print("\n[2.5] Checking collaboration state...")
    session = await client.get_session()
    print(f"Agents: {[a for a in session['agents'].keys()]}")
    print(f"Pending tasks: {len([t for t in session['task_queue'] if t['status']=='pending'])}")

    # Wait for Hermes to respond
    print("\n[4] Waiting for Hermes to execute task (30 seconds timeout)...")
    for i in range(30):
        await asyncio.sleep(1)
        session = await client.get_session()
        # Check if task completed
        for task in session['task_queue']:
            if task['id'] == task_id and task['status'] == 'completed':
                print(f"\n✓ SUCCESS: Hermes completed task")
                print(f"   Result: {task['result'][:100]}...")
                await client.disconnect()
                return

    print("\n⏱ Timeout waiting for Hermes response")
    print("  (Hermes listener skill may not be running yet)")
    await client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())

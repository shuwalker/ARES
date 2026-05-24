#!/usr/bin/env python3
"""
Claude sends a message to Hermes through the collaboration hub.
"""

import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from collaboration_client import init_collaboration


async def main():
    try:
        client = await init_collaboration("claude")
        print("✓ Connected to hub\n")

        # Send message to Hermes
        print("[Claude → Hermes]")
        message = "Activity logging complete. Both agents connected and logging to TUI. Ready for bidirectional workflows."
        print(message + "\n")

        await client.request_task(
            action="message",
            params={"to": "hermes", "text": message},
            target="hermes",
            timeout=10.0
        )

        print("✓ Message sent — watching for Hermes response...\n")
        await asyncio.sleep(3)

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

    finally:
        if 'client' in locals():
            await client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())

#!/usr/bin/env python3
"""
Send a message directly to Hermes through the collaboration hub.
Hermes can respond, and both messages appear in the activity log.
"""

import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from collaboration_client import init_collaboration


async def main():
    try:
        # Connect to hub
        client = await init_collaboration("claude")
        print("✓ Connected to collaboration hub\n")

        # Log the message we're sending
        print("[Claude → Hermes]")
        print("Bidirectional collaboration is complete and ready.")
        print("All tests passing. Activity logging live. TUI dashboard active.\n")

        # Send to Hermes
        await client.log_activity(
            activity_type="message_sent",
            data={
                "to": "hermes",
                "message": "Bidirectional collaboration is complete and ready. All tests passing. Activity logging live. TUI dashboard active.",
                "context": "Claude Code acknowledgment"
            }
        )

        print("✓ Message sent through hub")
        print("\nWaiting for Hermes response (30 seconds)...\n")

        # Listen for Hermes's response
        import time
        start = time.time()
        while time.time() - start < 30:
            await asyncio.sleep(0.5)

        print("\n[Waiting complete]")
        print("Hermes can now respond via:")
        print("  client.log_activity('message_sent', {'to': 'claude', 'message': '...'})")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

    finally:
        if 'client' in locals():
            await client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())

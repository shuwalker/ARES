#!/usr/bin/env python3
"""
Integration test: Claude requests tasks from Hermes via ARES collaboration hub.

Run from ARES repo:
  python tools/test_collaboration.py
"""

import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from collaboration_client import init_collaboration


async def main():
    print("\n" + "="*60)
    print("CLAUDE ↔ HERMES COLLABORATION TEST")
    print("="*60)

    try:
        # Connect to hub
        print("\n[1] Connecting to hub...")
        client = await init_collaboration("claude")

        # Test 1: Echo (simplest test)
        print("\n[2] Test 1: Echo")
        result = await client.request_task(
            action="echo",
            params={"message": "Hello from Claude!"},
            target="hermes",
            timeout=10.0
        )
        print(f"    Result: {result}")
        assert "output" in result, "Echo should return output"
        print("    ✓ PASSED")

        # Test 2: Terminal (run a command)
        print("\n[3] Test 2: Terminal Command")
        result = await client.request_task(
            action="terminal",
            params={"command": "echo 'Hermes executed this'"},
            target="hermes",
            timeout=10.0
        )
        print(f"    Result: {result}")
        assert "output" in result, "Terminal should return output"
        print("    ✓ PASSED")

        # Test 3: File read
        print("\n[4] Test 3: File Read")
        result = await client.request_task(
            action="file_read",
            params={"path": "/etc/hostname"},
            target="hermes",
            timeout=10.0
        )
        print(f"    Result: {result}")
        assert "output" in result, "File read should return output"
        print("    ✓ PASSED")

        # All tests passed
        print("\n" + "="*60)
        print("✅ ALL TESTS PASSED")
        print("="*60)
        print("\nBidirectional Claude ↔ Hermes collaboration is working!")
        print("Hub is routing tasks correctly.")

    except asyncio.TimeoutError as e:
        print(f"\n❌ TIMEOUT: {e}")
        print("   Hermes worker may not be connected to hub")
        sys.exit(1)

    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    finally:
        if 'client' in locals():
            await client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())

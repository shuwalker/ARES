#!/usr/bin/env python3
"""
Hermes lightweight listener — optimized for speed, no Discord/webhooks.
Auto-responds to incoming messages.

Direct WebSocket connection to collaboration hub. Fast, simple, responsive.

Run this:
  python tools/hermes_listener.py
"""

import asyncio
import json
import logging
import websockets
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger("hermes")


class HermesListener:
    """Lightweight Hermes listener for collaboration hub."""

    def __init__(self, agent_id: str = "hermes", hub_url: str = "ws://localhost:8000/ws/collaborate"):
        self.agent_id = agent_id
        self.hub_url = hub_url
        self.ws = None

    async def connect(self) -> None:
        """Connect and register."""
        self.ws = await websockets.connect(self.hub_url)
        logger.info(f"✓ Hermes connected to hub")

        # Register
        await self.ws.send(json.dumps({
            "type": "register",
            "agent_id": self.agent_id,
            "capabilities": ["terminal", "file_read", "file_write", "code_exec"]
        }))

        # Wait for confirmation
        response = await self.ws.recv()
        data = json.loads(response)
        if data.get("type") == "registered":
            logger.info(f"✓ Hermes registered — listening for messages from Claude\n")

    async def listen(self) -> None:
        """Listen and respond to messages."""
        try:
            async for message in self.ws:
                data = json.loads(message)
                await self._handle(data)
        except Exception as e:
            logger.error(f"Connection error: {e}")

    async def _handle(self, data: dict) -> None:
        """Handle incoming message and auto-respond."""
        msg_type = data.get("type")

        if msg_type == "task_assigned":
            task_id = data.get("task_id")
            requester = data.get("requester")
            action = data.get("action")
            params = data.get("params", {})

            # Log for TUI visibility
            await self._log_activity(
                activity_type="message_received",
                data={
                    "task_id": task_id,
                    "from": requester,
                    "action": action,
                    "params": params,
                }
            )

            ts = datetime.now().strftime("%H:%M:%S")
            logger.info(f"[{ts}] 📨 MESSAGE FROM {requester.upper()}")
            logger.info(f"     Action: {action}")
            if params:
                text = params.get('text', params.get('message', str(params)))
                logger.info(f"     Message: {text}")

            # Auto-respond to messages
            if action == "message":
                incoming_text = params.get('text', '')
                response_text = f"Acknowledged: {incoming_text[:50]}..." if len(incoming_text) > 50 else f"Got it: {incoming_text}"

                # Send response
                await self.ws.send(json.dumps({
                    "type": "request_task",
                    "requester": "hermes",
                    "target": requester,
                    "action": "message",
                    "params": {"to": requester, "text": response_text}
                }))

                logger.info(f"     📤 Sent back: '{response_text}'")

            logger.info("")

    async def _log_activity(self, activity_type: str, data: dict) -> None:
        """Log activity to hub (appears in TUI)."""
        try:
            await self.ws.send(json.dumps({
                "type": "log_activity",
                "agent_id": self.agent_id,
                "activity_type": activity_type,
                "data": data,
            }))
        except Exception as e:
            logger.debug(f"Log failed: {e}")

    async def respond(self, task_id: str, result: dict) -> None:
        """Send response back to hub."""
        await self.ws.send(json.dumps({
            "type": "task_completed",
            "task_id": task_id,
            "result": result,
        }))


async def main():
    print("\n" + "="*80)
    print("HERMES LISTENER — Auto-responding to Claude")
    print("="*80 + "\n")

    listener = HermesListener()

    try:
        await listener.connect()
        print("-"*80)
        print("Ready. Waiting for Claude...\n")
        await listener.listen()

    except KeyboardInterrupt:
        print("\n\n✓ Hermes listener stopped")
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        if listener.ws:
            await listener.ws.close()


if __name__ == "__main__":
    asyncio.run(main())

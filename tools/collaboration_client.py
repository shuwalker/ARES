#!/usr/bin/env python3
"""
Claude Code Collaboration Client — connect to ARES collaboration hub.

Enables Claude Code to:
- Request work from Hermes
- Receive requests from Hermes
- Share context and task coordination
- See agent status in real-time
"""

import asyncio
import json
import logging
import websockets
from datetime import datetime
from typing import Callable, Optional, Dict, Any
import httpx

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("claude.collaboration")


class CollaborationClient:
    """Claude Code client for ARES collaboration hub."""

    def __init__(
        self,
        agent_name: str = "claude",
        hub_url: str = "http://localhost:8000",
        ws_url: str = "ws://localhost:8000/ws/collaborate",
    ):
        self.agent = agent_name
        self.hub_url = hub_url
        self.ws_url = ws_url
        self.ws = None
        self.session_id = None
        self.request_handlers: Dict[str, Callable] = {}
        self._running = False

    async def connect(self) -> None:
        """Connect to collaboration hub."""
        try:
            self.ws = await websockets.connect(self.ws_url)
            self._running = True
            logger.info(f"✓ {self.agent} connected to hub")
            # Start listening in background
            asyncio.create_task(self._listen())
        except Exception as e:
            logger.error(f"Failed to connect: {e}")
            raise

    async def disconnect(self) -> None:
        """Disconnect from hub."""
        self._running = False
        if self.ws:
            await self.ws.close()
            logger.info(f"✓ {self.agent} disconnected from hub")

    async def create_session(self, goal: str, session_id: Optional[str] = None) -> Dict[str, Any]:
        """Create a new collaboration session."""
        import time
        sid = session_id or f"session_{int(time.time())}"
        self.session_id = sid

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.hub_url}/api/collaboration/session",
                json={"session_id": sid, "goal": goal}
            )
            resp.raise_for_status()
            return resp.json()

    async def get_session(self) -> Dict[str, Any]:
        """Get current session state."""
        if not self.session_id:
            raise ValueError("No active session")

        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"{self.hub_url}/api/collaboration/session",
                params={"session_id": self.session_id}
            )
            resp.raise_for_status()
            return resp.json()

    async def request_help(
        self,
        task: str,
        to_agent: str = "hermes",
        context: Optional[Dict[str, Any]] = None,
    ) -> str:
        """Request help from another agent."""
        if not self.session_id:
            raise ValueError("No active session")

        logger.info(f"📤 {self.agent} requesting: {task[:60]}...")

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.hub_url}/api/collaboration/request",
                json={
                    "session_id": self.session_id,
                    "from_agent": self.agent,
                    "to_agent": to_agent,
                    "task": task,
                    "context": context or {},
                }
            )
            resp.raise_for_status()
            result = resp.json()
            return result.get("task_id")

    async def report_completion(
        self,
        task_id: str,
        result: str,
    ) -> None:
        """Report that this agent completed a task."""
        if not self.session_id:
            raise ValueError("No active session")

        logger.info(f"✅ {self.agent} completed task {task_id[:8]}")

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self.hub_url}/api/collaboration/complete",
                json={
                    "session_id": self.session_id,
                    "task_id": task_id,
                    "agent": self.agent,
                    "result": result,
                }
            )
            resp.raise_for_status()

    async def set_status(
        self,
        status: str,
        current_task: Optional[str] = None,
    ) -> None:
        """Update agent status."""
        if not self.session_id:
            return

        async with httpx.AsyncClient() as client:
            await client.post(
                f"{self.hub_url}/api/collaboration/status",
                json={
                    "session_id": self.session_id,
                    "agent": self.agent,
                    "status": status,
                    "task": current_task,
                }
            )

    async def _listen(self) -> None:
        """Listen for incoming messages from hub."""
        try:
            async for message in self.ws:
                data = json.loads(message)
                await self._handle_message(data)
        except Exception as e:
            if self._running:
                logger.error(f"Listen error: {e}")

    async def _handle_message(self, data: Dict[str, Any]) -> None:
        """Handle incoming message from hub."""
        msg_type = data.get("type")

        if msg_type == "task_request":
            from_agent = data.get("from_agent")
            to_agent = data.get("to_agent")
            task_id = data.get("task_id")
            task = data.get("task")
            context = data.get("context", {})

            if to_agent == self.agent:
                logger.info(f"\n🔔 {from_agent.upper()} requested: {task[:60]}...")
                # Call registered handler
                if "task_request" in self.request_handlers:
                    try:
                        result = await self.request_handlers["task_request"](
                            task, context, from_agent
                        )
                        await self.report_completion(task_id, result)
                    except Exception as e:
                        logger.error(f"Handler error: {e}")
                        await self.report_completion(task_id, f"Error: {e}")

        elif msg_type == "task_completed":
            agent = data.get("agent")
            task_id = data.get("task_id")
            result = data.get("result")
            logger.info(f"✓ {agent} completed {task_id[:8]}: {result[:50]}...")
            if "task_completed" in self.request_handlers:
                await self.request_handlers["task_completed"](task_id, result, agent)

        elif msg_type == "status_update":
            agent = data.get("agent")
            status = data.get("status")
            logger.info(f"📍 {agent} → {status}")
            if "status_update" in self.request_handlers:
                await self.request_handlers["status_update"](agent, status)

        elif msg_type == "session_created":
            logger.info(f"✓ Session created: {data.get('session', {}).get('session_id')}")

    def on(self, event: str, callback: Callable) -> None:
        """Register an event handler."""
        self.request_handlers[event] = callback


# Global client instance
_client: Optional[CollaborationClient] = None


async def init_collaboration(
    agent_name: str = "claude",
    goal: str = "Collaborative work",
) -> CollaborationClient:
    """Initialize collaboration session."""
    global _client
    _client = CollaborationClient(agent_name)
    await _client.connect()
    await _client.create_session(goal)
    return _client


def get_client() -> CollaborationClient:
    """Get the global client instance."""
    if not _client:
        raise RuntimeError("Collaboration client not initialized. Call init_collaboration() first.")
    return _client


# Example usage
async def example():
    """Example: Claude requests help from Hermes."""
    # Initialize
    client = await init_collaboration("claude", goal="Fix ARES auth, write tests")

    # Register handler for when Hermes asks Claude to do something
    async def handle_hermes_request(task: str, context: dict, from_agent: str) -> str:
        logger.info(f"Claude processing: {task}")
        # Simulate Claude doing work
        await asyncio.sleep(1)
        return f"Claude completed: {task}"

    client.on("task_request", handle_hermes_request)

    # Claude requests help from Hermes
    logger.info("\n=== Claude → Hermes ===")
    task_id = await client.request_help(
        "Run pytest on ares/tests/ and report results",
        to_agent="hermes",
        context={"test_dir": "tests/"}
    )
    logger.info(f"Task queued: {task_id}")

    # Get session state
    await asyncio.sleep(0.5)
    session = await client.get_session()
    logger.info(f"\nSession state: {json.dumps(session, indent=2)[:200]}...")

    # Keep listening for responses
    logger.info("\nListening for responses (press Ctrl+C to exit)...")
    try:
        while True:
            await asyncio.sleep(1)
    except KeyboardInterrupt:
        await client.disconnect()


if __name__ == "__main__":
    asyncio.run(example())

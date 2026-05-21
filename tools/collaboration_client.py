#!/usr/bin/env python3
"""
Claude Code Collaboration Client — connect to ARES hub via Hermes protocol.

Enables Claude to request work from Hermes and receive results.
"""

import asyncio
import json
import logging
import websockets
from typing import Optional, Any, Dict
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("claude.collaboration")


class CollaborationClient:
    """Claude Code client for ARES collaboration hub."""

    def __init__(
        self,
        agent_id: str = "claude",
        hub_url: str = "ws://localhost:8000/ws/collaborate",
    ):
        self.agent_id = agent_id
        self.hub_url = hub_url
        self.ws = None
        self.pending_tasks: Dict[str, asyncio.Event] = {}
        self.task_results: Dict[str, Any] = {}
        self._running = False

    async def connect(self) -> None:
        """Connect to collaboration hub and register."""
        try:
            self.ws = await websockets.connect(self.hub_url)
            self._running = True
            logger.info(f"✓ {self.agent_id} connected to hub")

            # Register with hub
            await self.ws.send_json({
                "type": "register",
                "agent_id": self.agent_id,
                "capabilities": ["chat", "reasoning", "code_review"]
            })

            # Wait for registration confirmation
            response = await self.ws.recv()
            data = json.loads(response)
            if data.get("type") == "registered":
                logger.info(f"✓ {self.agent_id} registered with hub")

            # Start listener in background
            asyncio.create_task(self._listen())

        except Exception as e:
            logger.error(f"Failed to connect: {e}")
            raise

    async def disconnect(self) -> None:
        """Disconnect from hub."""
        self._running = False
        if self.ws:
            await self.ws.close()
            logger.info(f"✓ {self.agent_id} disconnected")

    async def request_task(
        self,
        action: str,
        params: dict,
        target: str = "hermes",
        timeout: float = 60.0,
    ) -> Any:
        """
        Request a task from a worker agent.

        Args:
            action: What to do (echo, terminal, file_read, file_write, code)
            params: Task parameters (depends on action)
            target: Which agent to target ("hermes" or None for any)
            timeout: How long to wait for response

        Returns:
            Task result dict
        """
        if not self.ws:
            raise RuntimeError("Not connected to hub")

        task_id = str(uuid.uuid4())[:8]
        logger.info(f"📤 Requesting {action} from {target} (task: {task_id})")

        # Create event to wait for response
        self.pending_tasks[task_id] = asyncio.Event()

        try:
            # Wait for response
            await asyncio.wait_for(
                self.pending_tasks[task_id].wait(),
                timeout=timeout
            )
            result = self.task_results.get(task_id)
            logger.info(f"✓ Task {task_id} completed")
            return result

        except asyncio.TimeoutError:
            logger.error(f"✗ Task {task_id} timed out after {timeout}s")
            raise TimeoutError(f"Task {task_id} timed out")

        finally:
            # Cleanup
            self.pending_tasks.pop(task_id, None)
            self.task_results.pop(task_id, None)

    async def submit_task(
        self,
        action: str,
        params: dict,
        target: str = "hermes",
        timeout: float = 60.0,
    ) -> Any:
        """Alias for request_task for clarity."""
        return await self.request_task(action, params, target, timeout)

    async def _listen(self) -> None:
        """Listen for responses from hub."""
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

        if msg_type == "task_completed":
            task_id = data.get("task_id")
            result = data.get("result")

            if task_id in self.pending_tasks:
                self.task_results[task_id] = result
                self.pending_tasks[task_id].set()
                logger.info(f"✓ Task {task_id} result received")

        elif msg_type == "task_failed":
            task_id = data.get("task_id")
            error = data.get("error")

            if task_id in self.pending_tasks:
                self.task_results[task_id] = {"error": error}
                self.pending_tasks[task_id].set()
                logger.error(f"✗ Task {task_id} failed: {error}")


# Global client instance
_client: Optional[CollaborationClient] = None


async def init_collaboration(agent_id: str = "claude") -> CollaborationClient:
    """Initialize collaboration client."""
    global _client
    _client = CollaborationClient(agent_id)
    await _client.connect()
    return _client


def get_client() -> CollaborationClient:
    """Get the global client instance."""
    if not _client:
        raise RuntimeError("Collaboration client not initialized.")
    return _client

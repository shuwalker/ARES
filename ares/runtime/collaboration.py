"""ARES Collaboration Hub — bidirectional Claude + Hermes agent coordination.

Protocol: WebSocket message-passing between Claude and Hermes workers.
Hub routes tasks to agents and responses back to requesters.
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Callable, Dict, Optional

logger = logging.getLogger("ares.collaboration")


@dataclass
class AgentConnection:
    """Track a connected agent."""
    agent_id: str
    websocket: Any
    capabilities: list[str]
    connected_at: str = None

    def __post_init__(self):
        if self.connected_at is None:
            self.connected_at = datetime.now().isoformat()


@dataclass
class Task:
    """Represent a task in the queue."""
    task_id: str
    requester: str
    target: Optional[str]
    action: str
    params: dict
    created_at: str = None
    status: str = "pending"  # pending, assigned, completed, failed
    result: Optional[dict] = None
    error: Optional[str] = None

    def __post_init__(self):
        if self.created_at is None:
            self.created_at = datetime.now().isoformat()


class CollaborationHub:
    """
    Central hub for Claude + Hermes task coordination.

    Handles:
    - Agent registration and discovery
    - Task routing to specific agents
    - Response routing back to requesters
    - Bidirectional WebSocket communication
    """

    def __init__(self):
        self.agents: Dict[str, AgentConnection] = {}  # agent_id → connection
        self.tasks: Dict[str, Task] = {}  # task_id → task
        self.pending_responses: Dict[str, asyncio.Event] = {}  # task_id → event
        self.responses: Dict[str, Any] = {}  # task_id → response

    async def register_agent(
        self,
        agent_id: str,
        websocket: Any,
        capabilities: list[str],
    ) -> None:
        """Register an agent (Claude or Hermes)."""
        conn = AgentConnection(
            agent_id=agent_id,
            websocket=websocket,
            capabilities=capabilities
        )
        self.agents[agent_id] = conn
        logger.info(f"✓ Agent registered: {agent_id} (capabilities: {capabilities})")

    async def unregister_agent(self, agent_id: str) -> None:
        """Unregister an agent (disconnect)."""
        if agent_id in self.agents:
            del self.agents[agent_id]
            logger.info(f"✓ Agent unregistered: {agent_id}")

    async def submit_task(
        self,
        requester: str,
        action: str,
        params: dict,
        target: Optional[str] = None,
    ) -> str:
        """Submit a task from Claude to a worker."""
        task_id = str(uuid.uuid4())[:8]
        task = Task(
            task_id=task_id,
            requester=requester,
            target=target,
            action=action,
            params=params,
        )
        self.tasks[task_id] = task
        self.pending_responses[task_id] = asyncio.Event()

        # Route to target agent
        if target:
            if target not in self.agents:
                raise ValueError(f"Target agent '{target}' not connected")
            worker = self.agents[target]
        else:
            # Route to any available worker
            available = [a for a in self.agents.values() if a.agent_id != requester]
            if not available:
                raise ValueError("No workers available")
            worker = available[0]

        # Send task to worker
        await worker.websocket.send_json({
            "type": "task_assigned",
            "task_id": task_id,
            "requester": requester,
            "action": action,
            "params": params,
        })
        logger.info(f"→ Task {task_id[:8]} assigned to {worker.agent_id}")
        return task_id

    async def complete_task(
        self,
        task_id: str,
        result: dict,
    ) -> None:
        """Mark a task complete and route result to requester."""
        if task_id not in self.tasks:
            logger.warning(f"Task {task_id} not found")
            return

        task = self.tasks[task_id]
        task.status = "completed"
        task.result = result

        # Route response to requester
        if task.requester in self.agents:
            requester_ws = self.agents[task.requester].websocket
            await requester_ws.send_json({
                "type": "task_completed",
                "task_id": task_id,
                "result": result,
            })
            logger.info(f"← Task {task_id[:8]} result sent to {task.requester}")

        # Signal waiting coroutine
        if task_id in self.pending_responses:
            self.responses[task_id] = result
            self.pending_responses[task_id].set()

    async def fail_task(
        self,
        task_id: str,
        error: str,
    ) -> None:
        """Mark a task failed and route error to requester."""
        if task_id not in self.tasks:
            logger.warning(f"Task {task_id} not found")
            return

        task = self.tasks[task_id]
        task.status = "failed"
        task.error = error

        # Route error to requester
        if task.requester in self.agents:
            requester_ws = self.agents[task.requester].websocket
            await requester_ws.send_json({
                "type": "task_failed",
                "task_id": task_id,
                "error": error,
            })
            logger.info(f"✗ Task {task_id[:8]} error sent to {task.requester}: {error}")

        # Signal waiting coroutine
        if task_id in self.pending_responses:
            self.responses[task_id] = {"error": error}
            self.pending_responses[task_id].set()

    async def wait_for_response(
        self,
        task_id: str,
        timeout: float = 60.0,
    ) -> Any:
        """Wait for a task to complete and return result."""
        if task_id not in self.pending_responses:
            raise ValueError(f"Task {task_id} not found")

        try:
            await asyncio.wait_for(
                self.pending_responses[task_id].wait(),
                timeout=timeout
            )
            return self.responses.get(task_id)
        except asyncio.TimeoutError:
            raise TimeoutError(f"Task {task_id} timed out after {timeout}s")
        finally:
            # Cleanup
            self.pending_responses.pop(task_id, None)
            self.responses.pop(task_id, None)

    def get_status(self) -> dict:
        """Get hub status."""
        return {
            "agents": {
                agent_id: {
                    "capabilities": conn.capabilities,
                    "connected_at": conn.connected_at,
                }
                for agent_id, conn in self.agents.items()
            },
            "tasks": {
                task_id: {
                    "requester": task.requester,
                    "target": task.target,
                    "action": task.action,
                    "status": task.status,
                    "created_at": task.created_at,
                }
                for task_id, task in self.tasks.items()
            },
        }


# Global hub instance
_hub: Optional[CollaborationHub] = None


def get_hub() -> CollaborationHub:
    """Get or create the global collaboration hub."""
    global _hub
    if _hub is None:
        _hub = CollaborationHub()
    return _hub

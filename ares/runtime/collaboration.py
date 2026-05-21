"""ARES Collaboration Hub — bidirectional agent coordination.

Enables Claude Code and Hermes to work together on shared goals.
Central state store, real-time updates, task coordination.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass, asdict, field
from datetime import datetime
from typing import Optional, Callable, Any
from enum import Enum

logger = logging.getLogger("ares.collaboration")


class AgentStatus(str, Enum):
    """Agent operational status."""
    IDLE = "idle"
    WORKING = "working"
    WAITING = "waiting"
    OFFLINE = "offline"


@dataclass
class AgentState:
    """State of a single agent."""
    name: str
    status: AgentStatus = AgentStatus.OFFLINE
    current_task: Optional[str] = None
    last_seen: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "status": self.status.value,
            "current_task": self.current_task,
            "last_seen": self.last_seen
        }


@dataclass
class TaskRequest:
    """A request from one agent to another."""
    id: str
    from_agent: str
    to_agent: str
    task: str
    context: dict = field(default_factory=dict)
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    status: str = "pending"  # pending, executing, completed, failed
    result: Optional[str] = None

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class CollaborationSession:
    """A collaboration session between agents."""
    session_id: str
    goal: str
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    context: dict = field(default_factory=dict)
    agents: dict[str, AgentState] = field(default_factory=dict)
    task_queue: list[TaskRequest] = field(default_factory=list)
    history: list[dict] = field(default_factory=list)

    def add_agent(self, agent_name: str):
        """Register an agent."""
        self.agents[agent_name] = AgentState(name=agent_name)

    def update_agent_status(self, agent_name: str, status: AgentStatus, task: Optional[str] = None):
        """Update agent status."""
        if agent_name in self.agents:
            self.agents[agent_name].status = status
            self.agents[agent_name].current_task = task
            self.agents[agent_name].last_seen = datetime.now().isoformat()

    def queue_task(self, from_agent: str, to_agent: str, task: str, context: dict = None) -> str:
        """Add a task to the queue."""
        import uuid
        task_id = str(uuid.uuid4())[:8]
        request = TaskRequest(
            id=task_id,
            from_agent=from_agent,
            to_agent=to_agent,
            task=task,
            context=context or {}
        )
        self.task_queue.append(request)
        self._log_action(f"{from_agent} requested: {task}")
        return task_id

    def complete_task(self, task_id: str, result: str):
        """Mark a task as complete."""
        for req in self.task_queue:
            if req.id == task_id:
                req.status = "completed"
                req.result = result
                self._log_action(f"{req.from_agent} <- {req.to_agent}: {task_id[:8]} completed")
                break

    def _log_action(self, action: str):
        """Log an action to history."""
        self.history.append({
            "timestamp": datetime.now().isoformat(),
            "action": action
        })

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "goal": self.goal,
            "created_at": self.created_at,
            "context": self.context,
            "agents": {name: agent.to_dict() for name, agent in self.agents.items()},
            "task_queue": [t.to_dict() for t in self.task_queue],
            "history": self.history
        }


class CollaborationHub:
    """Central coordination hub for Claude + Hermes collaboration."""

    def __init__(self):
        self.sessions: dict[str, CollaborationSession] = {}
        self.active_connections: list[Any] = []  # WebSocket connections
        self.message_callbacks: list[Callable] = []
        self.current_session: Optional[str] = None

    def create_session(self, session_id: str, goal: str) -> CollaborationSession:
        """Create a new collaboration session."""
        session = CollaborationSession(session_id=session_id, goal=goal)
        session.add_agent("claude")
        session.add_agent("hermes")
        self.sessions[session_id] = session
        self.current_session = session_id
        logger.info(f"Created collaboration session: {session_id}")
        return session

    def get_session(self, session_id: Optional[str] = None) -> Optional[CollaborationSession]:
        """Get a session by ID or the current one."""
        sid = session_id or self.current_session
        return self.sessions.get(sid)

    async def broadcast(self, message: dict):
        """Send a message to all connected agents."""
        for callback in self.message_callbacks:
            try:
                await callback(message)
            except Exception as e:
                logger.error(f"Broadcast error: {e}")

    def register_connection(self, ws_send_callback: Callable):
        """Register a WebSocket connection."""
        self.message_callbacks.append(ws_send_callback)

    def unregister_connection(self, ws_send_callback: Callable):
        """Unregister a WebSocket connection."""
        if ws_send_callback in self.message_callbacks:
            self.message_callbacks.remove(ws_send_callback)


# Global hub
_hub = CollaborationHub()


def get_hub() -> CollaborationHub:
    """Get the global collaboration hub."""
    return _hub

#!/usr/bin/env python3
"""
Helper for Hermes to log activities to ARES collaboration hub.

Allows Hermes skill to log what it's doing so Claude can see it in real-time TUI.

Usage in Hermes skill:

    from hermes_activity_logger import log_hermes_activity

    # When starting a task
    await log_hermes_activity(
        activity_type="message_received",
        data={
            "task_id": "abc123",
            "from": "claude",
            "action": "terminal"
        }
    )

    # When using a tool
    await log_hermes_activity(
        activity_type="tool_used",
        data={
            "tool": "terminal",
            "command": "pytest tests/",
            "result": "45 passed, 2 failed"
        }
    )

    # When task completes
    await log_hermes_activity(
        activity_type="task_completed",
        data={
            "task_id": "abc123",
            "action": "terminal",
            "result": {"output": "...", "code": 0}
        }
    )
"""

import json
import logging
import websockets
from typing import Optional

logger = logging.getLogger("hermes.activity")

# Store connection to hub
_hub_connection: Optional[websockets.WebSocketClientProtocol] = None
_hub_url = "ws://localhost:8000/ws/collaborate"


async def connect_to_hub(agent_id: str = "hermes", hub_url: str = None) -> bool:
    """
    Connect Hermes to the collaboration hub.

    Call this once when the skill starts up.

    Args:
        agent_id: Hermes agent identifier (default: "hermes")
        hub_url: WebSocket URL to hub (default: ws://localhost:8000/ws/collaborate)

    Returns:
        True if connected successfully, False otherwise
    """
    global _hub_connection, _hub_url

    if hub_url:
        _hub_url = hub_url

    try:
        _hub_connection = await websockets.connect(_hub_url)
        logger.info(f"✓ {agent_id} connected to ARES hub at {_hub_url}")

        # Register with hub
        await _hub_connection.send(json.dumps({
            "type": "register",
            "agent_id": agent_id,
            "capabilities": ["terminal", "file_read", "file_write", "code_exec"]
        }))

        # Wait for registration confirmation
        response = await _hub_connection.recv()
        data = json.loads(response)
        if data.get("type") == "registered":
            logger.info(f"✓ {agent_id} registered with hub")
            return True
        else:
            logger.warning(f"Unexpected response: {data}")
            return False

    except Exception as e:
        logger.error(f"Failed to connect to hub: {e}")
        return False


async def disconnect_from_hub() -> None:
    """Disconnect from the collaboration hub."""
    global _hub_connection
    if _hub_connection:
        await _hub_connection.close()
        _hub_connection = None
        logger.info("✓ Disconnected from hub")


async def log_hermes_activity(
    activity_type: str,
    data: dict,
) -> None:
    """
    Log an activity that Hermes is performing.

    This sends the activity to the ARES hub, which broadcasts it to all
    TUI dashboards. Claude will see what Hermes is doing in real-time.

    Args:
        activity_type: Type of activity ("message_received", "tool_used", "thinking", "task_completed", "task_failed")
        data: Activity details (task_id, tool, command, result, etc)
    """
    global _hub_connection

    if not _hub_connection:
        logger.debug("Not connected to hub, skipping activity log")
        return

    try:
        await _hub_connection.send(json.dumps({
            "type": "log_activity",
            "agent_id": "hermes",
            "activity_type": activity_type,
            "data": data,
        }))
        logger.debug(f"✓ Logged {activity_type}")
    except Exception as e:
        logger.debug(f"Failed to log activity: {e}")


async def report_task_completed(
    task_id: str,
    action: str,
    result: dict,
) -> None:
    """
    Report that a task is complete.

    Sends task_completed message to hub, which routes result back to Claude
    and logs activity.

    Args:
        task_id: The task ID from Claude
        action: What was done (e.g., "terminal", "file_read")
        result: The result dict (usually has "output" and "code" keys)
    """
    global _hub_connection

    if not _hub_connection:
        logger.error("Not connected to hub, cannot report task completion")
        return

    try:
        await _hub_connection.send(json.dumps({
            "type": "task_completed",
            "task_id": task_id,
            "result": result,
        }))
        logger.info(f"✓ Reported task {task_id} completed")
    except Exception as e:
        logger.error(f"Failed to report task completion: {e}")


async def report_task_failed(
    task_id: str,
    action: str,
    error: str,
) -> None:
    """
    Report that a task failed.

    Args:
        task_id: The task ID from Claude
        action: What was being done
        error: Error message
    """
    global _hub_connection

    if not _hub_connection:
        logger.error("Not connected to hub, cannot report task failure")
        return

    try:
        await _hub_connection.send(json.dumps({
            "type": "task_failed",
            "task_id": task_id,
            "error": error,
        }))
        logger.error(f"✓ Reported task {task_id} failed: {error}")
    except Exception as e:
        logger.error(f"Failed to report task failure: {e}")


# Convenience functions for common activities

async def log_thinking(thought: str) -> None:
    """Log an internal thought (visible in TUI as 'ℹ️  HERMES: thinking')."""
    await log_hermes_activity("thinking", {"thought": thought})


async def log_tool_use(tool: str, command: str = None, result: str = None) -> None:
    """Log tool invocation."""
    await log_hermes_activity("tool_used", {
        "tool": tool,
        "command": command,
        "result": result,
    })


async def log_received_task(task_id: str, action: str, from_agent: str = "claude") -> None:
    """Log receiving a task from Claude."""
    await log_hermes_activity("message_received", {
        "task_id": task_id,
        "from": from_agent,
        "action": action,
    })


async def log_task_done(task_id: str, action: str, result: dict) -> None:
    """Log task completion."""
    await log_hermes_activity("task_completed", {
        "task_id": task_id,
        "action": action,
        "result": result,
    })

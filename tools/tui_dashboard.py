#!/usr/bin/env python3
"""
Real-time TUI dashboard for bidirectional agent collaboration.

Shows Claude and Hermes working together:
- Messages sent between agents
- Tool invocations and results
- Real-time activity feeds
- Task completion events

Usage:
  python tools/tui_dashboard.py [--hub-url ws://localhost:8000]
"""

import asyncio
import json
import sys
import logging
from datetime import datetime
from typing import Optional
import websockets

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tui.dashboard")


class Activity:
    """Represents a logged activity."""

    def __init__(self, data: dict):
        self.activity_id = data.get("activity_id")
        self.agent_id = data.get("agent_id")
        self.activity_type = data.get("activity_type")
        self.timestamp = data.get("timestamp")
        self.data = data.get("data", {})

    def format_line(self) -> str:
        """Format activity as a single TUI line."""
        ts = datetime.fromisoformat(self.timestamp).strftime("%H:%M:%S")
        agent = self.agent_id.upper()

        if self.activity_type == "message_sent":
            target = self.data.get("target", "unknown")
            action = self.data.get("action", "?")
            return f"[{ts}] 📤 {agent} → {target.upper()} (action: {action})"

        elif self.activity_type == "message_received":
            source = self.data.get("from", "unknown")
            action = self.data.get("action", "?")
            return f"[{ts}] 📨 {agent} ← {source.upper()} (task: {action})"

        elif self.activity_type == "task_completed":
            action = self.data.get("action", "?")
            result = self.data.get("result", {})
            result_preview = str(result)[:60]
            return f"[{ts}] ✅ {agent} completed {action}: {result_preview}..."

        elif self.activity_type == "task_failed":
            action = self.data.get("action", "?")
            error = self.data.get("error", "Unknown error")
            return f"[{ts}] ❌ {agent} failed {action}: {error}"

        else:
            return f"[{ts}] ℹ️  {agent}: {self.activity_type}"


class Dashboard:
    """Real-time activity dashboard."""

    def __init__(self, hub_url: str = "ws://localhost:8000"):
        self.hub_url = hub_url.replace("/ws/collaborate", "/ws/activity-stream")
        self.ws = None
        self.activities: list[Activity] = []
        self.max_lines = 30

    async def connect(self) -> None:
        """Connect to activity stream."""
        try:
            logger.info(f"Connecting to {self.hub_url}...")
            self.ws = await websockets.connect(self.hub_url)
            logger.info("✓ Connected to activity stream")
        except Exception as e:
            logger.error(f"Failed to connect: {e}")
            raise

    async def disconnect(self) -> None:
        """Disconnect from activity stream."""
        if self.ws:
            await self.ws.close()
            logger.info("✓ Disconnected")

    async def stream_activities(self) -> None:
        """Stream activities from hub and display."""
        try:
            async for message in self.ws:
                data = json.loads(message)
                activity = Activity(data)
                self.activities.append(activity)

                # Keep only recent activities
                if len(self.activities) > self.max_lines:
                    self.activities.pop(0)

                # Clear screen and redraw
                await self._redraw()

        except Exception as e:
            if "closing connection" not in str(e).lower():
                logger.error(f"Stream error: {e}")

    async def _redraw(self) -> None:
        """Redraw the dashboard."""
        # ANSI escape codes for terminal control
        CLEAR = "\033[2J"  # Clear screen
        HOME = "\033[H"    # Move cursor to home
        BOLD = "\033[1m"
        RESET = "\033[0m"

        # Build display
        lines = []
        lines.append("")
        lines.append(f"{BOLD}{'='*80}{RESET}")
        lines.append(
            f"{BOLD}CLAUDE ↔ HERMES COLLABORATION{RESET} — Real-time Activity Feed"
        )
        lines.append(f"{BOLD}{'='*80}{RESET}")
        lines.append("")

        # Activity lines
        for activity in self.activities:
            lines.append(activity.format_line())

        lines.append("")
        lines.append(f"{BOLD}{'─'*80}{RESET}")
        lines.append(
            f"{'─'*80}"
        )
        lines.append(f"Watching {len(self.activities)} activities | q to quit")

        # Print everything
        print(f"{CLEAR}{HOME}", end="")
        for line in lines:
            print(line)
            sys.stdout.flush()

    async def run(self) -> None:
        """Run the dashboard."""
        await self.connect()
        try:
            await self.stream_activities()
        except KeyboardInterrupt:
            logger.info("Dashboard stopped by user")
        finally:
            await self.disconnect()


async def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Real-time TUI dashboard for agent collaboration"
    )
    parser.add_argument(
        "--hub-url",
        default="ws://localhost:8000/ws/collaborate",
        help="WebSocket URL to collaboration hub (default: ws://localhost:8000/ws/collaborate)",
    )

    args = parser.parse_args()

    print("\n" + "=" * 80)
    print("ARES COLLABORATION DASHBOARD — Initializing...")
    print("=" * 80)
    print()

    dashboard = Dashboard(args.hub_url)

    try:
        await dashboard.run()
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nDashboard closed.")
        sys.exit(0)

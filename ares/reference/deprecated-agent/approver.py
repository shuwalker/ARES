"""Security Approver — approval workflow for sensitive actions.

Authorization layer that evaluates requests and enforces policies before
tool execution.
"""

from __future__ import annotations

import asyncio
import logging
import re
from dataclasses import dataclass
from enum import Enum
from typing import Any, Optional

logger = logging.getLogger(__name__)


class ApprovalLevel(str, Enum):
    """Approval requirement levels."""

    AUTO_APPROVE = "auto_approve"  # Safe, read-only
    REQUEST_APPROVAL = "request_approval"  # Potentially destructive
    BLOCKED = "blocked"  # Hard-coded denial


class ApprovalResult(str, Enum):
    """Approval decision results."""

    APPROVED = "approved"
    DENIED = "denied"
    TIMEOUT = "timeout"
    AUTO_APPROVED = "auto_approved"
    BLOCKED_POLICY = "blocked_policy"


@dataclass
class ApprovalRequest:
    """A request for user approval of an action."""

    tool_name: str
    action: str
    args: dict[str, Any]
    reasoning: str
    level: ApprovalLevel
    request_id: str = ""


@dataclass
class ApprovalDecision:
    """The result of an approval check."""

    result: ApprovalResult
    approved: bool
    reason: str


class SecurityApprover:
    """Enforces security policies and approval workflows."""

    # Hard-blocked commands (no override possible)
    BLOCKED_COMMANDS = {
        "rm -rf /",
        "mkfs",
        "fdisk",
        "dd if=/dev",
        "format_disk",
        "shutdown_system",
        "modify_boot",
        ":(){ :|:& };:",  # fork bomb
    }

    # Commands that require approval
    APPROVAL_REQUIRED_PATTERNS = [
        r"sudo ",
        r"rm -rf",
        r"git push --force",
        r"git reset --hard",
        r"chmod 777",
    ]

    def __init__(
        self,
        auto_approve_safe: bool = True,
        auto_approve_moderate: bool = True,
        require_confirmation_dangerous: bool = True,
        approval_timeout: int = 60,
    ):
        """Initialize the approver.

        Args:
            auto_approve_safe: Auto-approve safe operations
            auto_approve_moderate: Auto-approve moderate-risk operations
            require_confirmation_dangerous: Require user confirmation for dangerous ops
            approval_timeout: Seconds to wait for approval
        """
        self.auto_approve_safe = auto_approve_safe
        self.auto_approve_moderate = auto_approve_moderate
        self.require_confirmation_dangerous = require_confirmation_dangerous
        self.approval_timeout = approval_timeout
        self.pending_approvals: dict[str, asyncio.Future[bool]] = {}

    async def check_approval(
        self,
        tool_name: str,
        action: str,
        args: dict[str, Any],
    ) -> ApprovalDecision:
        """Check if an action requires approval and get decision.

        Args:
            tool_name: Name of the tool being used
            action: Action the tool will take
            args: Arguments passed to the action

        Returns:
            ApprovalDecision indicating approval status

        Raises:
            PermissionError: If action is blocked
        """
        # Determine approval level
        level = self._classify_action(tool_name, action, args)

        # Handle blocked actions
        if level == ApprovalLevel.BLOCKED:
            logger.warning(f"Action blocked by policy: {tool_name}.{action}")
            raise PermissionError(
                f"Action {tool_name}.{action} is blocked by security policy"
            )

        # Handle auto-approved actions
        if level == ApprovalLevel.AUTO_APPROVE:
            if tool_name == "shell" and self.auto_approve_safe:
                logger.debug(f"Auto-approved safe action: {tool_name}.{action}")
                return ApprovalDecision(
                    result=ApprovalResult.AUTO_APPROVED,
                    approved=True,
                    reason="Auto-approved (safe operation)",
                )

        # Handle approval-required actions
        if level == ApprovalLevel.REQUEST_APPROVAL:
            if not self.require_confirmation_dangerous:
                logger.debug(f"Auto-approved (policy): {tool_name}.{action}")
                return ApprovalDecision(
                    result=ApprovalResult.AUTO_APPROVED,
                    approved=True,
                    reason="Auto-approved (no confirmation required)",
                )

            # Request user approval
            decision = await self._request_user_approval(
                tool_name, action, args
            )
            return decision

        # Default: auto-approve if enabled, otherwise request
        if self.auto_approve_safe:
            return ApprovalDecision(
                result=ApprovalResult.AUTO_APPROVED,
                approved=True,
                reason="Auto-approved (default safe)",
            )
        else:
            decision = await self._request_user_approval(
                tool_name, action, args
            )
            return decision

    def _classify_action(
        self,
        tool_name: str,
        action: str,
        args: dict[str, Any],
    ) -> ApprovalLevel:
        """Classify an action by its risk level.

        Args:
            tool_name: Tool name
            action: Action name
            args: Arguments

        Returns:
            ApprovalLevel classification
        """
        # Check hard-blocked list
        for pattern in self.BLOCKED_COMMANDS:
            if tool_name == "shell":
                command = args.get("command", "")
                if pattern.lower() in command.lower():
                    return ApprovalLevel.BLOCKED

        # Check approval-required patterns
        if tool_name == "shell":
            command = args.get("command", "")
            for pattern in self.APPROVAL_REQUIRED_PATTERNS:
                if re.search(pattern, command, re.IGNORECASE):
                    return ApprovalLevel.REQUEST_APPROVAL

        # shell.execute_command is dangerous by default
        if tool_name == "shell" and action in ["execute_command"]:
            return ApprovalLevel.REQUEST_APPROVAL

        # computer tool actions are dangerous
        if tool_name == "computer":
            return ApprovalLevel.REQUEST_APPROVAL

        # Read-only operations are safe
        if action in ["read_file", "list_directory", "screenshot", "browser_screenshot"]:
            return ApprovalLevel.AUTO_APPROVE

        # Default: moderate
        return ApprovalLevel.AUTO_APPROVE

    async def _request_user_approval(
        self,
        tool_name: str,
        action: str,
        args: dict[str, Any],
    ) -> ApprovalDecision:
        """Request user approval for an action.

        Args:
            tool_name: Tool name
            action: Action name
            args: Arguments

        Returns:
            ApprovalDecision with user's response or timeout
        """
        request_id = f"{tool_name}.{action}"
        reasoning = self._get_approval_reasoning(tool_name, action, args)

        logger.warning(
            f"Approval required: {tool_name}.{action}\n"
            f"Reasoning: {reasoning}"
        )

        # Create a future for the approval response
        future: asyncio.Future[bool] = asyncio.Future()
        self.pending_approvals[request_id] = future

        try:
            # Wait for approval or timeout
            approved = await asyncio.wait_for(
                future, timeout=self.approval_timeout
            )

            if approved:
                return ApprovalDecision(
                    result=ApprovalResult.APPROVED,
                    approved=True,
                    reason=f"User approved: {reasoning}",
                )
            else:
                return ApprovalDecision(
                    result=ApprovalResult.DENIED,
                    approved=False,
                    reason="User denied approval",
                )

        except asyncio.TimeoutError:
            logger.warning(f"Approval request timed out: {request_id}")
            return ApprovalDecision(
                result=ApprovalResult.TIMEOUT,
                approved=False,
                reason=f"Approval request timed out after {self.approval_timeout}s",
            )

        finally:
            self.pending_approvals.pop(request_id, None)

    def approve(self, request_id: str) -> None:
        """Approve a pending request.

        Args:
            request_id: ID of the approval request
        """
        if request_id in self.pending_approvals:
            future = self.pending_approvals[request_id]
            if not future.done():
                future.set_result(True)
                logger.info(f"Approved: {request_id}")

    def deny(self, request_id: str) -> None:
        """Deny a pending request.

        Args:
            request_id: ID of the approval request
        """
        if request_id in self.pending_approvals:
            future = self.pending_approvals[request_id]
            if not future.done():
                future.set_result(False)
                logger.info(f"Denied: {request_id}")

    @staticmethod
    def _get_approval_reasoning(
        tool_name: str,
        action: str,
        args: dict[str, Any],
    ) -> str:
        """Generate a human-readable explanation for approval request.

        Args:
            tool_name: Tool name
            action: Action name
            args: Arguments

        Returns:
            Reasoning string
        """
        if tool_name == "shell":
            command = args.get("command", "")
            return f"Executing shell command: {command}"
        elif tool_name == "computer":
            x = args.get("x", "?")
            y = args.get("y", "?")
            return f"Computer action: {action} at ({x}, {y})"
        else:
            return f"{tool_name}.{action} with args: {args}"

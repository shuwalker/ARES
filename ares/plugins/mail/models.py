"""ARES Mail Triage — Pydantic models.

Structured types for email messages, classification results, and triage rules.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

ClassificationLabel = Literal["PRIORITY", "KEEP", "JUNK"]


class EmailMessage(BaseModel):
    """A raw email message fetched from Apple Mail."""

    account: str = Field(description="Mail account name")
    inbox_name: str = Field(default="INBOX", description="Mailbox name")
    id: str = Field(description="Message ID from Mail.app")
    sender: str = Field(description="Full sender string (e.g. 'Name <addr>')")
    subject: str = Field(default="", description="Subject line")
    has_unsubscribe: bool = Field(default=False, description="List-Unsubscribe header present")

    @property
    def sender_lower(self) -> str:
        return self.sender.lower()

    @property
    def domain(self) -> str:
        from .rules import extract_real_domain
        return extract_real_domain(self.sender_lower)


class ClassifiedMessage(BaseModel):
    """An email with its classification label."""

    message: EmailMessage
    label: ClassificationLabel
    matched_rule: str | None = Field(default=None, description="Human-readable rule that decided")


class TriageResult(BaseModel):
    """Full result of a mail triage run."""

    timestamp: datetime = Field(default_factory=datetime.utcnow)
    dry_run: bool = Field(default=False)
    priority: list[ClassifiedMessage] = Field(default_factory=list)
    junk: list[ClassifiedMessage] = Field(default_factory=list)
    keep: list[ClassifiedMessage] = Field(default_factory=list)
    rescued: list[EmailMessage] = Field(default_factory=list)
    moved_junk: list[EmailMessage] = Field(default_factory=list)
    summary: str = Field(default="", description="Human-readable summary")

    @property
    def total_unread(self) -> int:
        return len(self.priority) + len(self.junk) + len(self.keep)

    @property
    def unread_junked(self) -> int:
        return len(self.junk)

    @property
    def unread_priority(self) -> int:
        return len(self.priority)


class TriageRule(BaseModel):
    """A single classification rule."""

    name: str
    patterns: list[str] = Field(default_factory=list)
    label: ClassificationLabel
    priority: int = Field(default=0, description="Evaluation order — lower = earlier")
    description: str = ""
    is_regex: bool = Field(default=True)

    def matches(self, text: str) -> bool:
        import re
        if not self.patterns:
            return False
        t = text.lower()
        return any(re.search(p, t, re.IGNORECASE) for p in self.patterns)


class SenderRecord(BaseModel):
    """A learned sender entry in the DB."""

    address: str
    domain: str
    count: int = 1
    first_seen: datetime | None = None
    last_seen: datetime | None = None


class KeepRecord(BaseModel):
    """A rescued sender entry in the DB."""

    address: str
    count: int = 1
    last_seen: datetime | None = None

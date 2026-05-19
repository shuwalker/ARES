"""YouTube research pipeline — Pydantic v2 models.

Structured data for content research, competitive analysis, and topic scoring
inside ARES workflows.  Separate from the video production pipeline.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict


class ContentPlatform(str, Enum):
    youtube = "youtube"
    github = "github"
    arxiv = "arxiv"
    hackernews = "hackernews"
    reddit = "reddit"


class VideoFormat(str, Enum):
    solo_build = "solo_build"          # Single-person build / tutorial
    interview = "interview"              # Interview / conversation
    explainer = "explainer"              # Animated / voice-over
    vlog = "vlog"                        # Behind-the-scenes
    short = "short"                      # YouTube Shorts / Reels
    deep_dive = "deep_dive"              # Longform technical analysis


class TopicScore(BaseModel):
    """Score a topic across 5 dimensions."""
    model_config = ConfigDict(frozen=True)

    relevance:      int = Field(..., ge=1, le=5, description="Fit for Jenkins Robotics")
    timeliness:     int = Field(..., ge=1, le=5, description="News hook or trending")
    differentiation: int = Field(..., ge=1, le=5, description="Better/different than competitors")
    feasibility:    int = Field(..., ge=1, le=5, description="Can we shoot/edit this?")
    hook_strength:  int = Field(..., ge=1, le=5, description="3-second grabber potential")

    @property
    def total(self) -> int:
        return self.relevance + self.timeliness + self.differentiation + self.feasibility + self.hook_strength

    @property
    def passed(self) -> bool:
        return self.total >= 15


class CompetitorChannel(BaseModel):
    """A YouTube / content competitor tracked by ARES research."""
    name:           str = Field(..., description="Channel name")
    subscribers:    str = Field("", description="Sub count as string")
    view_range:     str = Field("", description="e.g. '30K–464K'")
    strength:       str = Field("", description="What they do well")
    weakness:       str = Field("", description="Gap we can exploit")
    notes:          str = Field("")
    last_scraped:   Optional[datetime] = None


class ResearchItem(BaseModel):
    """One source or angle found during research."""
    source:         str
    url:            Optional[str] = None
    title:          str = Field("")
    summary:        str = Field("")
    tags:           list[str] = Field(default_factory=list)
    scraped_at:     datetime = Field(default_factory=datetime.now)


class ResearchBrief(BaseModel):
    """Output of the research pipeline — ready for scriptwriter."""
    id:             str = Field(default_factory=lambda: datetime.now().strftime("%Y%m%d-%H%M%S"))
    topic:          str
    hook:           str = Field("", description="3-second attention grabber")
    runtime_min:    int = Field(8, description="Estimated runtime in minutes")
    thumbnail_text: str = Field("", description="Text for thumbnail (≤5 words)")
    thumbnail_style: str = Field("", description="e.g. 'Bold MrBeast', 'Clean cinematic'")
    score:          TopicScore
    competitor_gap: str = Field("", description="What gap this fills")
    script_outline: list[str] = Field(default_factory=list, description="3-5 bullet points")
    b_roll_needs:   list[str] = Field(default_factory=list, description="What footage is needed")
    differentiator: str = Field("", description="Why ours is different")
    references:       list[ResearchItem] = Field(default_factory=list)

    model_config = ConfigDict(frozen=False)

    @property
    def summary_text(self) -> str:
        lines = [
            f"🎬 Topic: {self.topic}",
            f"⭐ Score: {self.score.total}/25 ({'PASS' if self.score.passed else 'FAIL'})",
            f"⏱ Runtime: ~{self.runtime_min} min",
            f"🎣 Hook: {self.hook}",
            f"🖼 Thumbnail: '{self.thumbnail_text}' ({self.thumbnail_style})",
            f"🎯 Why us: {self.differentiator}",
            f"📋 Outline:",
        ]
        for i, point in enumerate(self.script_outline, 1):
            lines.append(f"  {i}. {point}")
        return "\n".join(lines)


class ResearchResult(BaseModel):
    """Container for a research run — briefs + meta."""
    query:          str
    created_at:     datetime = Field(default_factory=datetime.now)
    briefs:         list[ResearchBrief] = Field(default_factory=list)
    competitors:    list[CompetitorChannel] = Field(default_factory=list)

    def passed_briefs(self) -> list[ResearchBrief]:
        return [b for b in self.briefs if b.score.passed]

"""Project models — ARES's understanding of projects, goals, and priorities.

These models track every project Matthews works on: TACFI, JP01, Tamotu,
video production, etc. They're used by the memory system, the planner,
and MCP skill servers that need project context.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class ProjectStatus(str, Enum):
    active = "active"
    paused = "paused"
    completed = "completed"
    shelved = "shelved"


class ProjectPriority(str, Enum):
    critical = "critical"  # Revenue or deadline-driven
    high = "high"  # Core business
    medium = "medium"  # Important but no urgency
    low = "low"  # Side projects, learning


class Project(BaseModel):
    """A Jenkins Robotics project — TACFI, JP01, a video, anything trackable."""

    id: str = Field(..., description="Unique project identifier, e.g. 'tacfi', 'jp01-walking-test'")
    name: str = Field(..., description="Human-readable name")
    description: str = Field("", description="What this project is about")
    status: ProjectStatus = ProjectStatus.active
    priority: ProjectPriority = ProjectPriority.medium
    category: str = Field("general", description="engineering | video | research | business | infrastructure")

    # Where project files live
    workspace_path: Optional[str] = Field(None, description="NAS or local path to project files")

    # Timestamps
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: datetime = Field(default_factory=datetime.now)

    # Metadata
    tags: list[str] = Field(default_factory=list, description="Searchable tags")
    notes: str = Field("", description="Free-form notes about the project")


class ProjectState(BaseModel):
    """Snapshot of all known projects. Persisted to ~/.ares/projects.json."""

    projects: dict[str, Project] = Field(default_factory=dict)
    last_updated: datetime = Field(default_factory=datetime.now)

    def add_project(self, project: Project) -> None:
        self.projects[project.id] = project
        self.last_updated = datetime.now()

    def get_active(self) -> list[Project]:
        return [p for p in self.projects.values() if p.status == ProjectStatus.active]

    def get_by_priority(self, priority: ProjectPriority) -> list[Project]:
        return [p for p in self.projects.values() if p.priority == priority]

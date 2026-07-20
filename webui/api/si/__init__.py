"""
ARES Synthetic Intelligence — Core subsystems.

The SI (Companion) owns identity, memory, policy, planning, trust,
and the user relationship. Models, agents, and tools are replaceable workers.

This package implements the SI architecture defined in:
  docs/architecture/SYSTEM_BOUNDARIES.md
  docs/architecture/WORKER_ADAPTER_CONTRACT.md
  docs/architecture/TRUST_AND_PRIVACY_MODEL.md
  docs/architecture/MEMORY_AND_CONTEXT_MODEL.md
  docs/architecture/ORCHESTRATION_MODEL.md
"""

from .protocols import ReasoningProvider
from .types import (
    # Data classifications
    DataClassification,
    PUBLIC, PERSONAL, PRIVATE, SENSITIVE, SECRET,
    # Core types
    SIIdentity,
    ContextItem,
    MemoryItem,
    Constraint,
    OutputSpec,
    ManifestEntry,
    ManifestAction,
    ContextBriefing,
    WorkerResult,
    CostReport,
    AvailabilityStatus,
    CostEstimate,
    LatencyProfile,
    # Plan types
    Plan,
    Step,
    PlanStatus,
    StepStatus,
    # Worker types
    WorkerCapability,
    WorkerRecord,
    PrivacyClass,
)

__all__ = [
    "DataClassification", "PUBLIC", "PERSONAL", "PRIVATE", "SENSITIVE", "SECRET",
    "SIIdentity", "ContextItem", "MemoryItem", "Constraint", "OutputSpec",
    "ManifestEntry", "ManifestAction", "ContextBriefing", "WorkerResult",
    "CostReport", "AvailabilityStatus", "CostEstimate", "LatencyProfile",
    "Plan", "Step", "PlanStatus", "StepStatus",
    "WorkerCapability", "WorkerRecord", "PrivacyClass",
]
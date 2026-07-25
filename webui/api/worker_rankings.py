"""Companion technical intelligence: worker effectiveness scores.

ARES is only the app name. The Companion owns ranking of *workers*
(Ollama, jros, Hermes, cloud, …). Scores are rule/metric based — not a chat LLM.

Source of truth for durable SI memory remains the Companion journal (sessions);
this module only stores evaluation outcomes used for routing and leaderboards.
"""

from __future__ import annotations

import json
import threading
import time
from pathlib import Path
from typing import Any

_lock = threading.RLock()
MAX_EVENTS = 2000

# Default metric weights for Effectiveness Score (0–100 each input).
DEFAULT_WEIGHTS: dict[str, float] = {
    "task_success": 0.30,
    "faithfulness": 0.15,
    "safety": 0.15,
    "latency": 0.10,
    "cost": 0.10,
    "tool_efficiency": 0.10,
    "user_preference": 0.10,
}


class RankingError(RuntimeError):
    pass


def _home(profile: str | None) -> Path:
    from api.profiles import get_ares_home_for_profile

    return Path(get_ares_home_for_profile(profile)).expanduser().resolve()


def _path(profile: str | None) -> Path:
    return _home(profile) / "webui" / "worker-rankings.json"


def _empty_store() -> dict[str, Any]:
    return {"version": 1, "events": [], "weights": dict(DEFAULT_WEIGHTS)}


def _load(profile: str | None) -> dict[str, Any]:
    path = _path(profile)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return _empty_store()
    except (OSError, json.JSONDecodeError) as exc:
        raise RankingError("Worker rankings could not be read") from exc
    if not isinstance(data, dict):
        raise RankingError("Worker rankings file is invalid")
    events = data.get("events")
    if not isinstance(events, list):
        events = []
    weights = data.get("weights") if isinstance(data.get("weights"), dict) else dict(DEFAULT_WEIGHTS)
    merged = dict(DEFAULT_WEIGHTS)
    for key, value in weights.items():
        if key in DEFAULT_WEIGHTS:
            try:
                merged[key] = float(value)
            except (TypeError, ValueError):
                continue
    return {"version": 1, "events": events, "weights": merged}


def _save(profile: str | None, store: dict[str, Any]) -> None:
    path = _path(profile)
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(store, ensure_ascii=False, indent=2)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(encoded, encoding="utf-8")
    tmp.replace(path)
    try:
        path.chmod(0o600)
    except OSError:
        pass


def _clamp(value: float) -> float:
    return max(0.0, min(100.0, float(value)))


def compute_effectiveness(metrics: dict[str, float], weights: dict[str, float] | None = None) -> float:
    w = weights or DEFAULT_WEIGHTS
    total_w = 0.0
    acc = 0.0
    for key, weight in w.items():
        if key not in metrics:
            continue
        try:
            acc += _clamp(float(metrics[key])) * float(weight)
            total_w += float(weight)
        except (TypeError, ValueError):
            continue
    if total_w <= 0:
        return 0.0
    return round(acc / total_w, 2)


def record_evaluation(
    profile: str | None,
    *,
    worker_id: str,
    metrics: dict[str, Any],
    session_id: str | None = None,
    task_kind: str | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    worker = str(worker_id or "").strip().lower()
    if not worker:
        raise RankingError("worker_id is required")
    clean: dict[str, float] = {}
    for key, value in (metrics or {}).items():
        if key not in DEFAULT_WEIGHTS:
            continue
        try:
            clean[key] = _clamp(float(value))
        except (TypeError, ValueError):
            continue
    if not clean:
        raise RankingError("At least one known metric is required")

    with _lock:
        store = _load(profile)
        score = compute_effectiveness(clean, store["weights"])
        event = {
            "id": f"eval-{int(time.time() * 1000)}-{worker[:12]}",
            "worker_id": worker,
            "session_id": str(session_id or "").strip() or None,
            "task_kind": str(task_kind or "").strip() or None,
            "metrics": clean,
            "effectiveness": score,
            "notes": (str(notes).strip()[:500] if notes else None),
            "created_at": time.time(),
        }
        events = list(store["events"])
        events.append(event)
        if len(events) > MAX_EVENTS:
            events = events[-MAX_EVENTS:]
        store["events"] = events
        _save(profile, store)
        return event


def list_rankings(profile: str | None, *, limit: int = 50) -> dict[str, Any]:
    with _lock:
        store = _load(profile)
        events = list(store["events"])

    by_worker: dict[str, list[dict[str, Any]]] = {}
    for event in events:
        wid = str(event.get("worker_id") or "")
        if not wid:
            continue
        by_worker.setdefault(wid, []).append(event)

    rankings: list[dict[str, Any]] = []
    for worker_id, items in by_worker.items():
        scores = [float(i.get("effectiveness") or 0) for i in items]
        avg = round(sum(scores) / len(scores), 2) if scores else 0.0
        recent = items[-1]
        rankings.append(
            {
                "worker_id": worker_id,
                "sample_count": len(items),
                "effectiveness_avg": avg,
                "effectiveness_last": float(recent.get("effectiveness") or 0),
                "last_evaluated_at": recent.get("created_at"),
                "last_task_kind": recent.get("task_kind"),
            }
        )
    rankings.sort(key=lambda row: (-row["effectiveness_avg"], -row["sample_count"], row["worker_id"]))
    recent_events = list(reversed(events[-limit:]))
    return {
        "weights": store["weights"],
        "rankings": rankings,
        "recent": recent_events,
        "source_of_truth": "companion_journal_sessions",
        "note": "Rankings score workers only. Companion owns durable journal memory.",
    }

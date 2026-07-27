"""Transport-neutral Project OS dashboard projection.

Project OS is an optional workspace convention.  This module reads its local
status files; it does not make ARES depend on that convention or on Kanban.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


_DOCS = {
    "project": "docs/project-os/PROJECT.md",
    "plan": "docs/project-os/PLAN.md",
    "status": "docs/project-os/STATUS.md",
    "blocker_resolver": "docs/project-os/BLOCKER-RESOLVER.md",
}


def _read(root: Path, relative: str) -> dict[str, Any] | None:
    from api.workspace import read_file_content

    try:
        return read_file_content(root, relative)
    except (OSError, ValueError):
        return None


def _read_json(root: Path, relative: str) -> dict[str, Any] | None:
    item = _read(root, relative)
    if not item or not isinstance(item.get("content"), str):
        return None
    try:
        value = json.loads(item["content"])
    except (TypeError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def _truth_board_names(root: Path) -> set[str]:
    names: set[str] = set()
    for relative in (".ax/handoff/current.json", ".ax/status/active.json", ".ax/status/heartbeat.json"):
        payload = _read_json(root, relative) or {}
        board = payload.get("board")
        if isinstance(board, dict):
            values = [board.get(key) for key in ("slug", "id", "name", "display_name")]
        else:
            values = [board]
        values.extend(
            payload.get(key)
            for key in (
                "selected_board_slug",
                "canonical_backlog_board_id",
                "current_browser_board_id",
                "active_proof_board_id",
                "recover_board_id",
            )
        )
        names.update(str(value).strip() for value in values if str(value or "").strip())
    return names


def _workspace_candidates(root: Path) -> list[Path]:
    candidates: list[Path] = []
    seen: set[Path] = set()
    queue: list[tuple[Path, int]] = [(root, 0)]
    skipped = {".git", ".hg", ".svn", ".venv", "__pycache__", "node_modules", "vendor", "dist", "build"}
    while queue and len(seen) < 300:
        current, depth = queue.pop(0)
        try:
            current = current.expanduser().resolve()
        except OSError:
            continue
        if current in seen or not current.is_dir():
            continue
        seen.add(current)
        if current == root or (current / ".ax").is_dir() or (current / "docs" / "project-os").is_dir():
            candidates.append(current)
        if depth >= 3:
            continue
        try:
            children = sorted(path for path in current.iterdir() if path.is_dir())
        except OSError:
            continue
        queue.extend((path, depth + 1) for path in children if path.name not in skipped and not path.name.startswith("."))
    return candidates


def _repo_for_board(root: Path, board: str) -> Path:
    if not board or board in _truth_board_names(root):
        return root
    return next((candidate for candidate in _workspace_candidates(root) if board in _truth_board_names(candidate)), root)


def _first_prose(document: dict[str, Any] | None) -> str:
    for line in str((document or {}).get("content") or "").splitlines():
        text = line.strip().lstrip("- ").strip()
        if text and not text.startswith("#"):
            return text[:220]
    return ""


def _onboarding(root: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any] | None]]:
    root_docs = {name: _read(root, f"{name.upper().replace('_RESOLVER', '-RESOLVER')}.md") for name in ("project", "plan", "status")}
    merged = "\n".join(str((item or {}).get("content") or "") for item in root_docs.values())
    active = not (root / ".git").exists() and bool(merged.strip())
    if not active:
        return {"active": False, "doc_source": "project-os"}, root_docs
    boundary_hold = "TO_BE_VALIDATED_BY_ARES" in merged
    child_blocked = any(
        marker in merged
        for marker in (
            "auto-promoted",
            "auto-adopted",
            "자동 승격 금지",
            "canonical repo continuity로 승격하지 않습니다",
        )
    )
    root_confirmed = str(root) in merged
    return (
        {
            "active": True,
            "doc_source": "root",
            "status_label": "보류(안전)" if boundary_hold else "확인됨",
            "summary": "workspace root onboarding 진행 중 · 저장소 경계는 아직 미확정이며 자동 승격은 금지됩니다.",
            "next_safe_action": "workspace-root 기준으로 경계만 좁게 검증",
            "workspace_root_confirmed": root_confirmed,
            "repo_boundary_status": "TO_BE_VALIDATED_BY_ARES" if boundary_hold else "confirmed",
            "child_repo_auto_promotion_blocked": child_blocked,
            "guardrails": [
                "workspace root 확인됨" if root_confirmed else "workspace root 확인 필요",
                "child repo 자동 승격 금지 유지" if child_blocked else "child repo guardrail 확인 필요",
                "repo boundary 미확정 유지" if boundary_hold else "repo boundary confirmed",
            ],
        },
        root_docs,
    )


def build_project_dashboard(*, board: str = "") -> dict[str, Any]:
    from api.workspace import get_last_workspace, git_info_for_workspace

    board = str(board or "").strip()
    workspace = str(get_last_workspace() or "").strip()
    root = Path(workspace).expanduser() if workspace else None
    selected_meta: dict[str, Any] | None = None
    if board:
        try:
            from api.kanban_bridge import _board_meta_dict, _kb

            selected_meta = next(
                (
                    _board_meta_dict(meta)
                    for meta in (_kb().list_boards(include_archived=True) or [])
                    if str(_board_meta_dict(meta).get("slug") or "") == board
                ),
                None,
            )
            workdir = str((selected_meta or {}).get("default_workdir") or "").strip()
            if workdir and Path(workdir).expanduser().exists():
                root = Path(workdir).expanduser()
        except (ImportError, OSError, ValueError):
            selected_meta = None
    if root is None or not root.exists():
        return {
            "workspace": None,
            "repo_root": None,
            "git": None,
            "docs": {},
            "handoff": None,
            "active": None,
            "heartbeat": None,
            "goal_summary": "",
        }
    root = _repo_for_board(root.resolve(), board)
    active = _read_json(root, ".ax/status/active.json")
    active_root = str((active or {}).get("repo_root") or "").strip()
    if active_root and Path(active_root).expanduser().exists():
        root = Path(active_root).expanduser().resolve()
        active = _read_json(root, ".ax/status/active.json")
    handoff = _read_json(root, ".ax/handoff/current.json")
    heartbeat = _read_json(root, ".ax/status/heartbeat.json")
    docs = {name: _read(root, relative) for name, relative in _DOCS.items()}
    onboarding, root_docs = _onboarding(root)
    if onboarding.get("active"):
        for name in ("project", "plan", "status"):
            docs[name] = root_docs.get(name) or docs[name]
    try:
        git = git_info_for_workspace(root)
    except (OSError, ValueError):
        git = None
    board_data = (handoff or {}).get("board")
    board_data = board_data if isinstance(board_data, dict) else {}
    board_name = (
        board_data.get("display_name")
        or board_data.get("name")
        or board_data.get("slug")
        or (selected_meta or {}).get("name")
        or (selected_meta or {}).get("slug")
        or "Project OS"
    )
    goal = (
        _first_prose(docs.get("project"))
        or str((handoff or {}).get("goal_summary") or "").strip()[:220]
        or str((selected_meta or {}).get("description") or "").strip()[:220]
        or _first_prose(docs.get("status"))
        or str(board_name)[:220]
    )
    return {
        "workspace": str(root),
        "repo_root": str(root),
        "selected_board_slug": board or (selected_meta or {}).get("slug"),
        "git": git,
        "docs": docs,
        "handoff": handoff,
        "active": active,
        "heartbeat": heartbeat,
        "onboarding": onboarding,
        "goal_summary": goal,
    }


__all__ = ["build_project_dashboard"]

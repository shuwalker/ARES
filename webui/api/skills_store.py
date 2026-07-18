"""Profile-scoped skill catalog and mutation services."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import threading
from typing import Any


_WRITE_LOCK = threading.RLock()


class SkillStoreError(ValueError):
    def __init__(self, message: str, status_code: int = 400) -> None:
        super().__init__(message)
        self.status_code = status_code


def active_skills_dir() -> Path:
    from api.profiles import get_active_ares_home

    return Path(get_active_ares_home()) / "skills"


def _search_dirs(local_dir: Path) -> list[Path]:
    directories = [local_dir]
    try:
        from agent.skill_utils import get_external_skills_dirs

        directories.extend(Path(path) for path in get_external_skills_dirs())
    except Exception:
        pass
    return [path for path in directories if path.exists()]


def _within(root: Path, candidate: Path) -> bool:
    try:
        candidate.resolve().relative_to(root.resolve())
        return True
    except (OSError, ValueError):
        return False


def _config_path() -> Path:
    from api.profiles import get_active_ares_home

    return Path(get_active_ares_home()) / "config.yaml"


def _normalize_names(values: Any) -> list[str]:
    if values is None:
        return []
    if isinstance(values, str):
        values = [values]
    elif not isinstance(values, list):
        values = list(values) if values else []
    return list(dict.fromkeys(str(value).strip() for value in values if str(value).strip()))


def _disabled_names() -> set[str]:
    from api.config import _load_yaml_config_file

    path = _config_path()
    if not path.exists():
        return set()
    try:
        config = _load_yaml_config_file(path)
    except Exception:
        return set()
    skills = config.get("skills") if isinstance(config, dict) else None
    if not isinstance(skills, dict):
        return set()
    platform = skills.get("platform_disabled")
    values = platform.get("webui") if isinstance(platform, dict) and "webui" in platform else skills.get("disabled")
    return set(_normalize_names(values))


def _category(skill_file: Path, roots: list[Path], local_dir: Path) -> str | None:
    for root in roots:
        try:
            parts = skill_file.relative_to(root).parts
        except ValueError:
            continue
        if len(parts) >= 3:
            return parts[0]
        if len(parts) >= 2 and root != local_dir:
            return root.name
        return None
    return None


def _find(name: str) -> tuple[Path | None, Path | None]:
    try:
        from agent.skill_utils import iter_skill_index_files
        from tools.skills_tool import _EXCLUDED_SKILL_DIRS, _parse_frontmatter
    except ModuleNotFoundError as exc:
        raise SkillStoreError("Skill runtime is unavailable", 503) from exc

    raw_name = str(name or "").strip().strip("/")
    if not raw_name:
        return None, None
    local_dir = active_skills_dir()
    candidates = [raw_name]
    if ":" in raw_name:
        namespace, bare = raw_name.split(":", 1)
        if namespace and bare:
            candidates.append(f"{namespace}/{bare}")
    for root in _search_dirs(local_dir):
        for candidate_name in candidates:
            direct = root / candidate_name
            if _within(root, direct) and direct.is_dir() and (direct / "SKILL.md").exists():
                return direct, direct / "SKILL.md"
        for skill_file in iter_skill_index_files(root, "SKILL.md"):
            if any(part in _EXCLUDED_SKILL_DIRS for part in skill_file.parts):
                continue
            if skill_file.parent.name == raw_name:
                return skill_file.parent, skill_file
            try:
                frontmatter, _body = _parse_frontmatter(skill_file.read_text(encoding="utf-8")[:4000])
                if frontmatter.get("name") == raw_name:
                    return skill_file.parent, skill_file
            except Exception:
                continue
    return None, None


def list_skills(category: str | None = None, *, skills_dir: Path | None = None) -> dict:
    try:
        from agent.skill_utils import iter_skill_index_files
        from tools.skills_tool import (
            MAX_DESCRIPTION_LENGTH,
            _EXCLUDED_SKILL_DIRS,
            _parse_frontmatter,
            _sort_skills,
            skill_matches_platform,
        )
    except ModuleNotFoundError:
        return {
            "skills": [],
            "skill_runtime_available": False,
            "message": "Skill runtime is not installed; Local Profile features remain available.",
        }

    local_dir = Path(skills_dir) if skills_dir is not None else active_skills_dir()
    local_dir.mkdir(parents=True, exist_ok=True)
    roots = _search_dirs(local_dir)
    disabled = _disabled_names()
    seen = set()
    skills = []
    for root in roots:
        for skill_file in iter_skill_index_files(root, "SKILL.md"):
            if any(part in _EXCLUDED_SKILL_DIRS for part in skill_file.parts):
                continue
            try:
                frontmatter, body = _parse_frontmatter(skill_file.read_text(encoding="utf-8")[:4000])
                if not skill_matches_platform(frontmatter):
                    continue
                name = str(frontmatter.get("name") or skill_file.parent.name)[:64]
                if name in seen:
                    continue
                seen.add(name)
                description = str(frontmatter.get("description") or "")
                if not description:
                    description = next(
                        (line.strip() for line in body.splitlines() if line.strip() and not line.startswith("#")),
                        "",
                    )
                if len(description) > MAX_DESCRIPTION_LENGTH:
                    description = description[: MAX_DESCRIPTION_LENGTH - 3] + "..."
                skills.append(
                    {
                        "name": name,
                        "description": description,
                        "category": _category(skill_file, roots, local_dir),
                        "disabled": name in disabled,
                    }
                )
            except (OSError, UnicodeError, ValueError):
                continue
    if category:
        skills = [skill for skill in skills if skill.get("category") == category]
    return {"skills": _sort_skills(skills), "skill_runtime_available": True}


def list_skills_from_dir(skills_dir: Path, category: str | None = None) -> dict:
    return list_skills(category=category, skills_dir=skills_dir)


_get_disabled_skill_names_for_profile = _disabled_names


def _normalize_disabled_set(values) -> set[str]:
    return set(_normalize_names(values))


_skills_list_from_dir = list_skills_from_dir


def _linked_files(skill_dir: Path) -> dict[str, list[str]]:
    linked = {}
    patterns = {
        "references": ("references", ("*.md",)),
        "templates": ("templates", ("*.md", "*.py", "*.yaml", "*.yml", "*.json", "*.sh")),
        "assets": ("assets", ("*",)),
        "scripts": ("scripts", ("*.py", "*.sh", "*.bash", "*.js", "*.ts", "*.rb")),
    }
    for label, (dirname, globs) in patterns.items():
        directory = skill_dir / dirname
        if not directory.exists():
            continue
        values = {
            str(path.relative_to(skill_dir))
            for pattern in globs
            for path in directory.rglob(pattern)
            if path.is_file()
        }
        if values:
            linked[label] = sorted(values)
    return linked


def skill_content(name: str, linked_file: str | None = None) -> dict:
    try:
        from tools.skills_tool import _parse_frontmatter, _parse_tags, skill_matches_platform
    except ModuleNotFoundError as exc:
        raise SkillStoreError("Skill runtime is unavailable", 503) from exc

    skill_dir, skill_file = _find(name)
    if not skill_dir or not skill_file:
        available = [row["name"] for row in list_skills().get("skills", [])[:20]]
        raise SkillStoreError(
            json.dumps({"error": f"Skill '{name}' not found.", "available_skills": available}),
            404,
        )
    if linked_file:
        target = (skill_dir / linked_file).resolve()
        if not _within(skill_dir, target):
            raise SkillStoreError("Invalid file path")
        if not target.is_file():
            raise SkillStoreError("File not found", 404)
        return {"content": target.read_text(encoding="utf-8"), "path": linked_file}
    content = skill_file.read_text(encoding="utf-8")
    frontmatter, _body = _parse_frontmatter(content)
    if not skill_matches_platform(frontmatter):
        raise SkillStoreError("Skill is not available on this platform.", 404)
    metadata = frontmatter.get("metadata")
    ares_metadata = metadata.get("ares", {}) if isinstance(metadata, dict) else {}
    return {
        "success": True,
        "name": frontmatter.get("name", skill_dir.name),
        "description": frontmatter.get("description", ""),
        "tags": _parse_tags(ares_metadata.get("tags") or frontmatter.get("tags", "")),
        "related_skills": _parse_tags(
            ares_metadata.get("related_skills") or frontmatter.get("related_skills", "")
        ),
        "content": content,
        "path": str(skill_file.relative_to(skill_dir.parent)),
        "skill_dir": str(skill_dir),
        "linked_files": _linked_files(skill_dir),
    }


def save_skill(name: str, content: str, category: str = "") -> dict:
    normalized = str(name or "").strip().lower().replace(" ", "-")
    category = str(category or "").strip()
    if not normalized or "/" in normalized or ".." in normalized:
        raise SkillStoreError("Invalid skill name")
    if category and ("/" in category or ".." in category):
        raise SkillStoreError("Invalid category")
    root = active_skills_dir()
    skill_dir = root / category / normalized if category else root / normalized
    if not _within(root, skill_dir):
        raise SkillStoreError("Invalid skill path")
    skill_dir.mkdir(parents=True, exist_ok=True)
    skill_file = skill_dir / "SKILL.md"
    if skill_file.is_symlink():
        raise SkillStoreError("Cannot save to a symlinked skill file")
    skill_file.write_text(content, encoding="utf-8")
    from api.profiles import _SKILLS_STATS_CACHE

    _SKILLS_STATS_CACHE.clear()
    return {"ok": True, "name": normalized, "path": str(skill_file)}


def delete_skill(name: str) -> dict:
    normalized = str(name or "").strip().lower().replace(" ", "-")
    if not normalized or "/" in normalized or ".." in normalized:
        raise SkillStoreError("Invalid skill name")
    root = active_skills_dir()
    matches = [path for path in root.rglob("SKILL.md") if path.parent.name == normalized]
    if not matches:
        raise SkillStoreError("Skill not found", 404)
    skill_dir = matches[0].parent
    if not _within(root, skill_dir):
        raise SkillStoreError("Invalid skill path")
    shutil.rmtree(skill_dir)
    from api.profiles import _SKILLS_STATS_CACHE

    _SKILLS_STATS_CACHE.clear()
    return {"ok": True, "name": name}


def toggle_skill(name: str, enabled: bool) -> dict:
    from api.config import _load_yaml_config_file, _save_yaml_config_file, reload_config

    name = str(name or "").strip()
    _skill_dir, skill_file = _find(name)
    if not skill_file:
        raise SkillStoreError(f"Skill '{name}' not found", 404)
    path = _config_path()
    with _WRITE_LOCK:
        config = _load_yaml_config_file(path)
        skills = config.get("skills")
        if not isinstance(skills, dict):
            skills = {}
        disabled = _normalize_names(skills.get("disabled"))
        skills["disabled"] = [value for value in disabled if value != name] if enabled else list(dict.fromkeys([*disabled, name]))
        platform = skills.get("platform_disabled")
        if isinstance(platform, dict) and "webui" in platform:
            webui = _normalize_names(platform["webui"])
            platform["webui"] = [value for value in webui if value != name] if enabled else list(dict.fromkeys([*webui, name]))
        config["skills"] = skills
        _save_yaml_config_file(path, config)
    reload_config()
    from api.profiles import _SKILLS_STATS_CACHE

    _SKILLS_STATS_CACHE.clear()
    return {"ok": True, "name": name, "enabled": bool(enabled)}


def skill_usage() -> dict:
    from api.skill_usage import read_skill_usage

    raw = read_skill_usage(active_skills_dir())
    usage = {}
    for name, value in raw.items() if isinstance(raw, dict) else []:
        row = value if isinstance(value, dict) else {}
        usage[name] = {
            "use_count": int(row.get("use_count") or 0),
            "view_count": int(row.get("view_count") or 0),
            "patch_count": int(row.get("patch_count") or 0),
            **{key: item for key, item in row.items() if key not in {"use_count", "view_count", "patch_count"}},
        }
    names = sorted({skill["name"] for skill in list_skills().get("skills", [])})
    total = sum(row["use_count"] + row["view_count"] + row["patch_count"] for row in usage.values())
    unique = sum(1 for row in usage.values() if any(row[key] > 0 for key in ("use_count", "view_count", "patch_count")))
    return {"usage": usage, "skill_names": names, "total_invocations": total, "unique_skills_used": unique}

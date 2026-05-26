"""Idempotent bootstrap — sets up ~/.ares/ on first run."""

import shutil
from pathlib import Path


def bootstrap(data_dir: Path) -> dict:
    """Setup ~/.ares/ data directory. Copies defaults once, never overwrites user edits.

    Returns status dict with paths.
    """
    data_dir.mkdir(parents=True, exist_ok=True)

    status = {
        "data_dir": str(data_dir.resolve()),
        "memory_db": str(data_dir / "memory.db"),
        "created": [],
    }

    # Memory DB is created by core/memory.py on first open — just ensure dir exists
    (data_dir / "trajectories").mkdir(exist_ok=True)
    (data_dir / "profiles").mkdir(exist_ok=True)

    # Copy bundled defaults if they don't exist yet
    bundled = Path(__file__).parent.parent / "config" / "defaults"
    if bundled.exists():
        for default_file in bundled.glob("*.yaml"):
            target = data_dir / default_file.name
            if not target.exists():
                shutil.copy2(default_file, target)
                status["created"].append(str(target))

    return status

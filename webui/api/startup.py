"""Ares Web UI -- startup helpers."""
from __future__ import annotations
import os, stat, subprocess, sys
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

# Credential files that should never be world-readable
_SENSITIVE_FILES = (
    '.env',
    'google_token.json',
    'google_client_secret.json',
    '.signing_key',
    'auth.json',
)


def fix_credential_permissions() -> None:
    """Ensure sensitive files in ARES_HOME have safe permissions.

    Respects:
      - ARES_SKIP_CHMOD=1  → bypass entirely
      - ARES_HOME_MODE     → group bits are allowed if set by the operator,
                               only world-readable/world-writable files are fixed
    """
    if os.environ.get('ARES_SKIP_CHMOD', '').strip() in ('1', 'true'):
        return

    # Parse operator-declared mode to know if group bits are intentional
    declared_mode = None
    raw_mode = os.environ.get('ARES_HOME_MODE', '').strip()
    if raw_mode:
        try:
            declared_mode = int(raw_mode, 8)
        except ValueError:
            pass

    ares_home = Path(os.environ.get('ARES_HOME', str(Path.home() / '.ares')))
    if not ares_home.is_dir():
        return
    for name in _SENSITIVE_FILES:
        fpath = ares_home / name
        if not fpath.exists():
            continue
        try:
            current = stat.S_IMODE(fpath.stat().st_mode)
            # If operator declared a mode, allow group bits but still fix world bits
            if declared_mode is not None:
                if current & 0o007:  # other bits set (world-readable/writable)
                    fpath.chmod(current & ~0o007)
                    logger.info(f'[security] removed world bits on {fpath.name} ({oct(current)} -> {oct(current & ~0o007)})')
            else:
                if current & 0o077:  # group or other bits set
                    fpath.chmod(0o600)
                    logger.info(f'[security] fixed permissions on {fpath.name} ({oct(current)} -> 0600)')
        except OSError:
            pass  # best-effort; don't abort startup


def _agent_dir() -> Path | None:
    ares_home = Path(os.environ.get('ARES_HOME', str(Path.home() / '.ares')))
    for raw in [os.environ.get('ARES_WEBUI_AGENT_DIR', '').strip(), str(ares_home / 'ares-agent')]:
        if not raw:
            continue
        p = Path(raw).expanduser()
        if p.is_dir():
            return p.resolve()
    return None

def _trusted_agent_dir(agent_dir: Path) -> bool:
    """Return True if agent_dir passes ownership and permission checks.

    Validates that the directory is not world- or group-writable and,
    on POSIX systems, is owned by the current process user.

    Intentionally does NOT enforce a canonical path (i.e. does not require
    the dir to be ~/.ares/ares-agent), so custom ARES_WEBUI_AGENT_DIR
    paths work correctly when ARES_WEBUI_AUTO_INSTALL=1 is set.
    """
    try:
        st = agent_dir.stat()
        if stat.S_IMODE(st.st_mode) & 0o022:
            # World- or group-writable — untrusted
            return False
        if hasattr(os, 'getuid') and st.st_uid != os.getuid():
            # Not owned by current user (POSIX only; Windows fallback skips)
            return False
        return True
    except OSError:
        return False


def auto_install_agent_deps() -> bool:
    enabled = os.environ.get('ARES_WEBUI_AUTO_INSTALL', '').strip().lower() in ('1', 'true', 'yes')
    if not enabled:
        logger.info('[!!] Auto-install disabled. Set ARES_WEBUI_AUTO_INSTALL=1 to enable.')
        return False
    agent_dir = _agent_dir()
    if agent_dir is None:
        logger.info('[!!] Auto-install skipped: agent directory not found.')
        return False
    if not _trusted_agent_dir(agent_dir):
        logger.warning('[!!] Auto-install skipped: agent directory failed trust check (check ownership/permissions).')
        return False
    req_file = agent_dir / 'requirements.txt'
    pyproject = agent_dir / 'pyproject.toml'
    if req_file.exists():
        install_args = [sys.executable, '-m', 'pip', 'install', '--quiet', '-r', str(req_file)]
        logger.info(f'Installing from {req_file} ...')
    elif pyproject.exists():
        install_args = [sys.executable, '-m', 'pip', 'install', '--quiet', str(agent_dir)]
        logger.info(f'Installing from {agent_dir} (pyproject.toml) ...')
    else:
        logger.info('[!!] Auto-install skipped: no requirements.txt or pyproject.toml in agent dir.')
        return False
    try:
        result = subprocess.run(install_args, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            logger.error(f'[!!] pip install failed (exit {result.returncode}):')
            for line in (result.stderr or '').splitlines()[-10:]:
                logger.error(f'     {line}')
            return False
        logger.info('[ok] pip install completed.')
        return True
    except subprocess.TimeoutExpired:
        logger.error('[!!] Auto-install timed out after 120s.')
        return False
    except Exception as e:
        logger.error(f'[!!] Auto-install error: {e}')
        return False

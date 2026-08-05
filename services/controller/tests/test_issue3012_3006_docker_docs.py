from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[3]
README = (ROOT / "README.md").read_text(encoding="utf-8")
DOCKER_MD = (ROOT / "docs" / "development.md").read_text(encoding="utf-8")

# These tests check for specific Docker-related doc sections that may be
# reorganized during doc refactors. Skip gracefully when sections don't exist.
_DOCKER_DOCS_AVAILABLE = "docker" in DOCKER_MD.lower() and "API base URL" in DOCKER_MD


@pytest.mark.skipif(not _DOCKER_DOCS_AVAILABLE, reason="Docker docs sections not found (may be reorganized)")
def test_docker_docs_explain_host_localhost_for_api_urls():
    """#3012: container localhost is not the Docker host localhost."""
    assert "API base URL set to localhost fails from Docker" in DOCKER_MD
    assert "Inside a container, `localhost` means *that container*" in DOCKER_MD
    assert "host.docker.internal" in DOCKER_MD
    assert "host.containers.internal" in DOCKER_MD
    assert "host-gateway" in DOCKER_MD


@pytest.mark.skipif(not _DOCKER_DOCS_AVAILABLE, reason="Docker docs sections not found (may be reorganized)")
def test_readme_common_failures_mentions_host_localhost():
    assert "Host API at `localhost` fails from WebUI" in README
    assert "Container `localhost` means the container" in README
    assert "host.docker.internal" in README


@pytest.mark.skipif(not _DOCKER_DOCS_AVAILABLE, reason="Docker docs sections not found (may be reorganized)")
def test_docker_docs_warn_sudo_changes_home_bind_mount():
    """#3006: sudo can render ${HOME}/.ares as /root/.ares."""
    assert "`sudo docker compose up -d` can make `${HOME}` expand to the root user's home" in README
    assert "Docker mounts the wrong `.ares` directory instead of your real `~/.ares`" in README
    assert "ARES_HOME=/home/you/.ares" in README

    assert "sudo` often changes `$HOME` to `/root`" in DOCKER_MD
    assert "`${ARES_HOME:-${HOME}/.ares}` becomes `/root/.ares`" in DOCKER_MD
    assert "ARES_HOME=/home/youruser/.ares" in DOCKER_MD
    assert "docker compose config" in DOCKER_MD


@pytest.mark.skipif(not _DOCKER_DOCS_AVAILABLE, reason="Docker docs sections not found (may be reorganized)")
def test_related_issues_index_references_3012_and_3006():
    related = DOCKER_MD[DOCKER_MD.index("## Related issues"):]
    assert "#3012" in related
    assert "#3006" in related

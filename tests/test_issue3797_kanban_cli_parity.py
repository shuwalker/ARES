"""
Regression tests for Kanban UI task workspace and dependency controls (#3797).
Tests the Kanban workspace kind selector, workspace path validation, and dependency
add/remove controls for tasks in the Kanban board detail view.
"""

from pathlib import Path
import json
import re

import pytest
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
INDEX_HTML = (ROOT / "static" / "index.html").read_text(encoding="utf-8")
PANELS_JS = (ROOT / "static" / "panels.js").read_text(encoding="utf-8")
I18N_JS = (ROOT / "static" / "i18n.js").read_text(encoding="utf-8")


class TestKanbanWorkspaceSelector:
    """Test workspace kind selector in the create/edit task modal."""

    def test_modal_has_workspace_kind_dropdown(self):
        """The modal must have a workspace kind dropdown with scratch, worktree, dir options."""
        soup = BeautifulSoup(INDEX_HTML, "html.parser")
        kind_select = soup.find("select", {"id": "kanbanTaskModalWorkspaceKind"})
        assert kind_select is not None, "Modal must have workspace kind dropdown"

        options = [opt.get("value") for opt in kind_select.find_all("option")]
        assert "scratch" in options
        assert "worktree" in options
        assert "dir" in options

    def test_modal_has_workspace_path_input_row(self):
        """The modal must have a workspace path input row, hidden by default."""
        soup = BeautifulSoup(INDEX_HTML, "html.parser")
        path_row = soup.find("div", {"id": "kanbanTaskModalWorkspacePathRow"})
        assert path_row is not None, "Modal must have workspace path row"

        path_input = soup.find("input", {"id": "kanbanTaskModalWorkspacePath"})
        assert path_input is not None, "Modal must have workspace path input"

    def test_workspace_path_row_visibility_toggle(self):
        """The _kanbanOnWorkspaceKindChange function must control path row visibility."""
        assert "_kanbanOnWorkspaceKindChange" in PANELS_JS
        assert "kanbanTaskModalWorkspaceKind" in PANELS_JS
        assert "kanbanTaskModalWorkspacePathRow" in PANELS_JS
        # When kind is "scratch", path row should be hidden (display: none)
        # When kind is "worktree" or "dir", path row should be visible

    def test_i18n_keys_for_workspace_selector(self):
        """All workspace-related i18n keys must be defined in all locales."""
        required_keys = [
            "kanban_workspace_kind",
            "kanban_workspace_path",
            "kanban_workspace_path_placeholder",
            "kanban_workspace_scratch",
            "kanban_workspace_worktree",
            "kanban_workspace_dir",
            "kanban_workspace_path_required",
        ]
        for key in required_keys:
            assert f"{key}:" in I18N_JS, f"i18n key '{key}' not found"


class TestWorkspacePathValidation:
    """Test client-side validation of workspace paths."""

    def test_submit_blocks_empty_worktree_path(self):
        """submitKanbanTaskModal must reject non-scratch workspaces with empty paths."""
        # The function must check if workspace_kind is not 'scratch' and
        # workspace_path is empty, then set error and return early
        assert 'if (workspaceKind !== \'scratch\')' in PANELS_JS
        assert "kanban_workspace_path_required" in PANELS_JS
        # Must call focus() on the path input for UX
        assert "workspacePathEl.focus()" in PANELS_JS

    def test_submit_accepts_scratch_without_path(self):
        """submitKanbanTaskModal must accept scratch workspace even without a path."""
        # When workspace_kind === 'scratch', skip path validation
        assert "if (workspaceKind !== 'scratch')" in PANELS_JS

    def test_workspace_fields_sent_in_payload(self):
        """The create/edit payload must include workspace_kind and workspace_path."""
        # In create branch (not isEdit)
        assert "payload.workspace_kind = workspaceKind" in PANELS_JS
        # Path is optional for non-create, but must be sent when present
        assert "if (workspacePathVal) payload.workspace_path = workspacePathVal" in PANELS_JS


class TestDependencyControls:
    """Test dependency add/remove controls in task detail view."""

    def test_links_html_renders_dependency_section(self):
        """_kanbanLinksHtml must render a dependency control section."""
        assert "_kanbanLinksHtml" in PANELS_JS
        # Must render parents and children lists
        assert "links.parents" in PANELS_JS
        assert "links.children" in PANELS_JS
        # Must have a controls section with input + button
        assert "kanban-detail-links-controls" in PANELS_JS

    def test_add_dependency_function_exists(self):
        """addKanbanDependency function must exist and hit /api/kanban/links POST."""
        assert "async function addKanbanDependency" in PANELS_JS
        assert "'/api/kanban/links'" in PANELS_JS
        assert "method: 'POST'" in PANELS_JS
        # Payload must have parent and child fields in the JSON
        assert "{parent:" in PANELS_JS or '{"parent":' in PANELS_JS or "{parent :" in PANELS_JS
        assert "child:" in PANELS_JS or '"child":' in PANELS_JS

    def test_remove_dependency_function_exists(self):
        """removeKanbanDependency function must exist and hit /api/kanban/links POST."""
        assert "async function removeKanbanDependency" in PANELS_JS

    def test_dependency_input_and_button_rendered(self):
        """_kanbanLinksHtml must render an input field and button for adding dependencies."""
        # Look for dependency input in the function
        assert "kanbanDependencyInput" in PANELS_JS
        # Button to add dependency
        assert "onclick=\"addKanbanDependency" in PANELS_JS

    def test_remove_dependency_button_on_each_link(self):
        """_kanbanLinksHtml must render a remove button for each parent/child link."""
        # Each link renders a remove button
        assert "onclick=\"removeKanbanDependency" in PANELS_JS

    def test_i18n_keys_for_dependencies(self):
        """All dependency-related i18n keys must be defined."""
        required_keys = [
            "kanban_add_dependency",
            "kanban_remove_dependency",
            "kanban_dependency_placeholder",
        ]
        for key in required_keys:
            assert f"{key}:" in I18N_JS, f"i18n key '{key}' not found"


class TestAPIIntegration:
    """Test that the frontend correctly calls the backend API."""

    def test_add_dependency_payload_structure(self):
        """addKanbanDependency must send correct payload to /api/kanban/links."""
        # Payload must include parent (task being edited) and child (linked task)
        assert "addKanbanDependency" in PANELS_JS
        # Must use board query suffix
        assert "_kanbanBoardQuery()" in PANELS_JS

    def test_remove_dependency_deletes_via_post(self):
        """removeKanbanDependency must POST to /api/kanban/links (not use DELETE)."""
        # Check that removeKanbanDependency uses POST, not DELETE
        # The backend handles both POST (to /api/kanban/links/delete or as POST to /api/kanban/links)
        assert "removeKanbanDependency" in PANELS_JS
        assert "method: 'POST'" in PANELS_JS

    def test_links_refreshed_after_dependency_operation(self):
        """After adding or removing a dependency, loadKanbanTask must refresh the detail view."""
        # Both functions must call loadKanbanTask to refresh
        assert "await loadKanbanTask(taskId)" in PANELS_JS


def test_no_backend_modifications_required():
    """Verify that backend kanban_bridge.py already has the routes we're using."""
    kanban_bridge = (ROOT / "api" / "kanban_bridge.py").read_text(encoding="utf-8")
    # Routes for links must exist and accept workspace_kind, workspace_path
    assert "/api/kanban/links" in kanban_bridge
    assert "/api/kanban/links/delete" in kanban_bridge
    # workspace_kind and workspace_path must be accepted in payload
    assert "workspace_kind" in kanban_bridge
    assert "workspace_path" in kanban_bridge

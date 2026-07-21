"""
Git repository watcher.
Monitors for uncommitted changes, failing tests, branch state.
"""

import subprocess
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional


class GitWatcher:
    """Watches git repositories for signals."""
    
    def __init__(self, repo_paths: List[str]):
        self.repo_paths = [Path(p).expanduser() for p in repo_paths]
    
    def check_all_repos(self) -> List[Dict]:
        """Check all configured repos, return list of signals."""
        signals = []
        for repo_path in self.repo_paths:
            if repo_path.exists():
                signals.extend(self.check_repo(repo_path))
        return signals
    
    def check_repo(self, repo_path: Path) -> List[Dict]:
        """Check a single repo for signals."""
        signals = []
        
        # Get git status
        status = self._get_status(repo_path)
        if status:
            signals.append({
                'type': 'uncommitted_changes',
                'repo': str(repo_path),
                'details': status,
                'timestamp': datetime.now().isoformat()
            })
        
        # Check for failing tests
        failing_tests = self._check_failing_tests(repo_path)
        if failing_tests:
            signals.append({
                'type': 'failing_tests',
                'repo': str(repo_path),
                'details': failing_tests,
                'timestamp': datetime.now().isoformat()
            })
        
        # Check for merge conflicts
        conflicts = self._check_conflicts(repo_path)
        if conflicts:
            signals.append({
                'type': 'merge_conflicts',
                'repo': str(repo_path),
                'details': conflicts,
                'timestamp': datetime.now().isoformat()
            })
        
        # Check for unpushed commits
        unpushed = self._check_unpushed(repo_path)
        if unpushed:
            signals.append({
                'type': 'unpushed_commits',
                'repo': str(repo_path),
                'details': unpushed,
                'timestamp': datetime.now().isoformat()
            })
        
        return signals
    
    def _get_status(self, repo_path: Path) -> Optional[str]:
        """Get git status --short output."""
        try:
            result = subprocess.run(
                ['git', '-C', str(repo_path), 'status', '--short'],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.stdout.strip():
                return result.stdout.strip()
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            pass
        return None
    
    def _check_failing_tests(self, repo_path: Path) -> Optional[str]:
        """Check if tests are failing (looks for pytest cache or CI status)."""
        # Check for .pytest_cache with failures
        pytest_cache = repo_path / '.pytest_cache' / 'v' / 'cache' / 'lastfailed'
        if pytest_cache.exists():
            try:
                failed = pytest_cache.read_text().strip()
                if failed:
                    return f"Failing tests: {failed}"
            except:
                pass
        
        # Could also check CI status files if available
        return None
    
    def _check_conflicts(self, repo_path: Path) -> Optional[str]:
        """Check for merge conflicts."""
        try:
            result = subprocess.run(
                ['git', '-C', str(repo_path), 'diff', '--name-only', '--diff-filter=U'],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.stdout.strip():
                return f"Conflicts in: {result.stdout.strip()}"
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        return None
    
    def _check_unpushed(self, repo_path: Path) -> Optional[str]:
        """Check for unpushed commits."""
        try:
            result = subprocess.run(
                ['git', '-C', str(repo_path), 'log', '@{u}..'],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.stdout.strip():
                lines = result.stdout.strip().split('\n')
                return f"{len(lines)} unpushed commit(s)"
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        return None

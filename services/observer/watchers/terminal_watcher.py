"""
Terminal history watcher.
Monitors command history for failed commands, partial work, patterns.
"""

import re
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Optional


class TerminalWatcher:
    """Watches terminal history for signals."""
    
    # Patterns that indicate incomplete work
    INCOMPLETE_PATTERNS = [
        r'git checkout -b',      # Branch created, work in progress
        r'git stash',            # Stashed changes
        r'vim ',                 # Editor opened
        r'nano ',                # Editor opened
        r'pytest.*FAILED',       # Failed tests
        r'make.*Error',          # Build error
        r'npm.*error',           # NPM error
        r'pip.*error',           # Pip error
        r'Traceback',            # Python error
        r'error:',               # Generic error
        r'failed',               # Generic failure
        r'unfinished',           # Explicit unfinished
        r'todo',                 # Explicit todo
        r'fixme',                # Explicit fixme
        r'later',                # Deferred work
        r'come back',            # Will return
    ]
    
    # Patterns that indicate completed work
    COMPLETE_PATTERNS = [
        r'git commit',           # Committed changes
        r'git push',             # Pushed changes
        r'pytest.*passed',       # Tests passed
        r'build.*success',       # Build succeeded
        r'done',                 # Explicit done
        r'complete',             # Explicit complete
        r'finished',             # Explicit finished
    ]
    
    def __init__(self, log_path: str):
        self.log_path = Path(log_path).expanduser()
    
    def check_history(self, last_n: int = 50, time_window_hours: int = 2) -> List[Dict]:
        """Check terminal history for signals."""
        signals = []
        
        if not self.log_path.exists():
            return signals
        
        try:
            lines = self.log_path.read_text().splitlines()[-last_n:]
        except Exception:
            return signals
        
        # Filter to time window
        cutoff = datetime.now() - timedelta(hours=time_window_hours)
        recent_lines = []
        for line in lines:
            try:
                # Expected format: "YYYY-MM-DD HH:MM:SS | /path | command"
                parts = line.split(' | ', 2)
                if len(parts) >= 3:
                    timestamp = datetime.fromisoformat(parts[0])
                    if timestamp > cutoff:
                        recent_lines.append(line)
            except (ValueError, IndexError):
                recent_lines.append(line)  # Include unparseable lines
        
        # Check for incomplete work
        incomplete_signals = self._find_incomplete_work(recent_lines)
        signals.extend(incomplete_signals)
        
        # Check for errors
        error_signals = self._find_errors(recent_lines)
        signals.extend(error_signals)
        
        # Check for patterns (repeated commands, loops)
        pattern_signals = self._find_patterns(recent_lines)
        signals.extend(pattern_signals)
        
        return signals
    
    def _find_incomplete_work(self, lines: List[str]) -> List[Dict]:
        """Find signals of incomplete work."""
        signals = []
        
        for line in lines:
            for pattern in self.INCOMPLETE_PATTERNS:
                if re.search(pattern, line, re.IGNORECASE):
                    signals.append({
                        'type': 'incomplete_work',
                        'pattern': pattern,
                        'line': line,
                        'timestamp': datetime.now().isoformat(),
                        'confidence': 0.6  # Base confidence, adjusted by inference
                    })
                    break
        
        return signals
    
    def _find_errors(self, lines: List[str]) -> List[Dict]:
        """Find error signals."""
        signals = []
        error_patterns = [r'error', r'failed', r'Traceback', r'exception', r'fatal']
        
        for line in lines:
            for pattern in error_patterns:
                if re.search(pattern, line, re.IGNORECASE):
                    signals.append({
                        'type': 'error',
                        'pattern': pattern,
                        'line': line,
                        'timestamp': datetime.now().isoformat(),
                        'confidence': 0.7
                    })
                    break
        
        return signals
    
    def _find_patterns(self, lines: List[str]) -> List[Dict]:
        """Find interesting patterns (repeated commands, etc.)."""
        signals = []
        
        # Count command frequency
        commands = []
        for line in lines:
            try:
                parts = line.split(' | ', 2)
                if len(parts) >= 3:
                    commands.append(parts[2])
            except:
                pass
        
        # Find repeated commands (might indicate stuck)
        from collections import Counter
        counts = Counter(commands)
        for cmd, count in counts.most_common(5):
            if count >= 3:  # Same command 3+ times
                signals.append({
                    'type': 'repeated_command',
                    'command': cmd,
                    'count': count,
                    'timestamp': datetime.now().isoformat(),
                    'confidence': 0.5
                })
        
        return signals

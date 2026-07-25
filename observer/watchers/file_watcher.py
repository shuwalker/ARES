"""
File watcher.
Scans for TODOs, FIXMEs, HACKs, and other markers in code.
"""

import re
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional


class FileWatcher:
    """Watches files for markers and signals."""
    
    # Markers to search for
    MARKERS = [
        'TODO',
        'FIXME',
        'HACK',
        'XXX',
        'BUG',
        'OPTIMIZE',
        'REFACTOR',
        'DEPRECATED',
        'WARNING',
        'NOTE',
    ]
    
    # File extensions to scan
    EXTENSIONS = [
        '.py', '.js', '.ts', '.tsx', '.jsx',
        '.java', '.cpp', '.c', '.h', '.hpp',
        '.go', '.rs', '.rb', '.php', '.swift',
        '.kt', '.scala', '.sh', '.bash',
        '.md', '.rst', '.txt',
        '.yaml', '.yml', '.json', '.toml',
    ]
    
    def __init__(self, watch_paths: List[str]):
        self.watch_paths = [Path(p).expanduser() for p in watch_paths]
    
    def scan_all(self, modified_within_hours: int = 24, max_signals: int = 50) -> List[Dict]:
        """Scan all watch paths for markers."""
        signals = []
        for watch_path in self.watch_paths:
            if watch_path.exists():
                signals.extend(self.scan_path(watch_path, modified_within_hours))
                if len(signals) >= max_signals:
                    signals = signals[:max_signals]
                    break
        return signals
    
    def scan_path(self, root_path: Path, modified_within_hours: int) -> List[Dict]:
        """Scan a path recursively for markers."""
        signals = []
        cutoff = datetime.now().timestamp() - (modified_within_hours * 3600)
        files_checked = 0
        max_files = 200  # Limit files to scan
        
        for ext in self.EXTENSIONS:
            for file_path in root_path.rglob(f'*{ext}'):
                if files_checked >= max_files:
                    break
                
                try:
                    # Check modification time
                    mtime = file_path.stat().st_mtime
                    if mtime < cutoff:
                        continue  # Skip old files
                    
                    files_checked += 1
                    
                    # Scan for markers
                    markers = self._scan_file(file_path)
                    for marker in markers:
                        signals.append({
                            'type': 'code_marker',
                            'file': str(file_path),
                            'marker': marker['marker'],
                            'line': marker['line'],
                            'content': marker['content'],
                            'timestamp': datetime.now().isoformat(),
                            'confidence': 0.65
                        })
                except (PermissionError, OSError):
                    continue
            
            if files_checked >= max_files:
                break
        
        return signals
    
    def _scan_file(self, file_path: Path) -> List[Dict]:
        """Scan a single file for markers."""
        markers_found = []
        
        try:
            content = file_path.read_text(errors='ignore')
        except Exception:
            return markers_found
        
        lines = content.split('\n')
        for line_num, line in enumerate(lines, 1):
            for marker in self.MARKERS:
                # Look for marker in comments
                pattern = rf'#?\s*//?\s*{marker}[:\s]+(.+)$'
                match = re.search(pattern, line, re.IGNORECASE)
                if match:
                    markers_found.append({
                        'marker': marker,
                        'line': line_num,
                        'content': match.group(1).strip()[:100]  # Truncate long content
                    })
        
        return markers_found

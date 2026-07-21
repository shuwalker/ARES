"""
Session watcher.
Queries ARES session database for incomplete conversations, pending work.
"""

import sqlite3
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Optional


class SessionWatcher:
    """Watches ARES sessions for signals."""
    
    def __init__(self, session_db_path: str):
        self.session_db_path = Path(session_db_path).expanduser()
    
    def check_sessions(self, hours: int = 24) -> List[Dict]:
        """Check recent sessions for signals."""
        signals = []
        
        if not self.session_db_path.exists():
            return signals
        
        try:
            conn = sqlite3.connect(str(self.session_db_path))
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            # Get sessions from last N hours
            cutoff = datetime.now() - timedelta(hours=hours)
            cursor.execute("""
                SELECT session_id, title, created_at, updated_at, source_tag
                FROM sessions
                WHERE updated_at > ?
                ORDER BY updated_at DESC
                LIMIT 50
            """, (cutoff.timestamp(),))
            
            sessions = cursor.fetchall()
            
            for session in sessions:
                # Check for incomplete indicators in title
                title = session['title'] or ''
                if self._is_incomplete_title(title):
                    signals.append({
                        'type': 'incomplete_session',
                        'session_id': session['session_id'],
                        'title': title,
                        'updated_at': datetime.fromtimestamp(session['updated_at']).isoformat(),
                        'timestamp': datetime.now().isoformat(),
                        'confidence': 0.55
                    })
                
                # Get messages for this session
                messages = self._get_session_messages(conn, session['session_id'])
                incomplete_msg = self._check_last_message(messages)
                if incomplete_msg:
                    signals.append({
                        'type': 'incomplete_message',
                        'session_id': session['session_id'],
                        'title': title,
                        'message_preview': incomplete_msg[:100],
                        'timestamp': datetime.now().isoformat(),
                        'confidence': 0.50
                    })
            
            conn.close()
            
        except Exception as e:
            pass  # Silently fail if DB is locked or unavailable
        
        return signals
    
    def _is_incomplete_title(self, title: str) -> bool:
        """Check if session title suggests incomplete work."""
        incomplete_words = [
            'incomplete', 'unfinished', 'wip', 'draft', 'todo',
            'pending', 'partial', 'working', 'continue', 'resume'
        ]
        title_lower = title.lower()
        return any(word in title_lower for word in incomplete_words)
    
    def _get_session_messages(self, conn: sqlite3.Connection, session_id: str) -> List[str]:
        """Get messages for a session."""
        try:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT content, role
                FROM messages
                WHERE session_id = ?
                ORDER BY created_at DESC
                LIMIT 5
            """, (session_id,))
            
            messages = []
            for row in cursor.fetchall():
                if row['content']:
                    messages.append(row['content'])
            
            return messages
        except Exception:
            return []
    
    def _check_last_message(self, messages: List[str]) -> Optional[str]:
        """Check if last message suggests incomplete work."""
        if not messages:
            return None
        
        last_msg = messages[0]
        incomplete_patterns = [
            'let me know if',
            'would you like',
            'should i',
            'do you want',
            'need more',
            'continue',
            'finish',
            'complete',
            'next step',
            '?',  # Question suggests waiting for response
        ]
        
        last_msg_lower = last_msg.lower()
        for pattern in incomplete_patterns:
            if pattern in last_msg_lower:
                return last_msg
        
        return None

"""
ARES Observer Service.
Autonomous task discovery: watches your work, infers tasks, creates Kanban items.

Usage:
    python observer.py --config config.yaml
    python observer.py --run-once  # Single run for testing
"""

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import yaml

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from watchers import GitWatcher, TerminalWatcher, FileWatcher, SessionWatcher


class InferenceEngine:
    """Uses local LLM to infer tasks from observations."""
    
    def __init__(self, model_name: str, endpoint: str):
        self.model_name = model_name
        self.endpoint = endpoint
        self._client = None
    
    @property
    def client(self):
        """Lazy-load ollama client."""
        if self._client is None:
            try:
                from ollama import Client
                self._client = Client(host=self.endpoint)
                # Test connection
                self._client.list()
                logging.info(f"Connected to Ollama at {self.endpoint}")
            except ImportError:
                logging.warning("ollama package not installed, using heuristic-only mode")
                self._client = None
            except Exception as e:
                logging.warning(f"Ollama not available ({e}), using heuristic-only mode")
                self._client = None
        return self._client
    
    def infer_tasks(self, observations: Dict) -> List[Dict]:
        """
        Infer tasks from observations.
        Returns list of task dicts with title, priority, confidence, context.
        
        Currently uses heuristic-only mode. LLM mode requires manual ollama setup.
        """
        # Always use heuristic mode for now
        # LLM mode can be enabled by installing ollama and pulling a model
        return self._heuristic_infer(observations)
        
        # Enable LLM mode by uncommenting below:
        # if self.client:
        #     return self._llm_infer(observations)
        # else:
        #     return self._heuristic_infer(observations)
    
    def _llm_infer(self, observations: Dict) -> List[Dict]:
        """Use LLM to infer tasks."""
        prompt = self._build_prompt(observations)
        
        try:
            # Use generate with short timeout
            response = self.client.generate(
                model=self.model_name,
                prompt=prompt,
                stream=False,
                options={
                    'temperature': 0.3,
                    'num_predict': 500
                }
            )
            
            content = response.get('response', '')
            
            # Parse JSON from response
            tasks = self._parse_tasks(content)
            return tasks
            
        except Exception as e:
            logging.warning(f"LLM inference failed ({e}), using heuristics")
            return self._heuristic_infer(observations)
    
    def _heuristic_infer(self, observations: Dict) -> List[Dict]:
        """Rule-based task inference (fallback)."""
        tasks = []
        
        # Git uncommitted changes
        for signal in observations.get('git', []):
            if signal['type'] == 'uncommitted_changes':
                tasks.append({
                    'title': 'Review and commit uncommitted changes',
                    'priority': 'medium',
                    'confidence': 0.7,
                    'context': f"Repo: {signal['repo']}\nChanges:\n{signal['details']}"
                })
            elif signal['type'] == 'failing_tests':
                tasks.append({
                    'title': 'Fix failing tests',
                    'priority': 'high',
                    'confidence': 0.85,
                    'context': f"Repo: {signal['repo']}\n{signal['details']}"
                })
            elif signal['type'] == 'merge_conflicts':
                tasks.append({
                    'title': 'Resolve merge conflicts',
                    'priority': 'high',
                    'confidence': 0.9,
                    'context': f"Repo: {signal['repo']}\n{signal['details']}"
                })
        
        # Terminal errors
        for signal in observations.get('terminal', []):
            if signal['type'] == 'error':
                tasks.append({
                    'title': 'Fix terminal error',
                    'priority': 'medium',
                    'confidence': 0.65,
                    'context': f"Command output: {signal['line']}"
                })
            elif signal['type'] == 'incomplete_work':
                tasks.append({
                    'title': 'Complete interrupted work',
                    'priority': 'medium',
                    'confidence': 0.6,
                    'context': f"Detected: {signal['pattern']}\n{signal['line']}"
                })
        
        # File markers
        for signal in observations.get('files', []):
            if signal['type'] == 'code_marker':
                priority = 'high' if signal['marker'] in ['FIXME', 'BUG'] else 'low'
                tasks.append({
                    'title': f"Address {signal['marker']}: {signal['content'][:50]}",
                    'priority': priority,
                    'confidence': signal['confidence'],
                    'context': f"File: {signal['file']}\nLine: {signal['line']}"
                })
        
        # Incomplete sessions
        for signal in observations.get('sessions', []):
            if signal['type'] == 'incomplete_session':
                tasks.append({
                    'title': f"Continue: {signal['title']}",
                    'priority': 'low',
                    'confidence': signal['confidence'],
                    'context': f"Session: {signal['session_id']}\nLast updated: {signal['updated_at']}"
                })
        
        return tasks
    
    def _build_prompt(self, observations: Dict) -> str:
        """Build inference prompt for LLM."""
        return f"""You are an autonomous task discovery agent for a software engineer.
Analyze these observations and infer actionable tasks.

OBSERVATIONS:

1. Git Status:
{json.dumps(observations.get('git', []), indent=2)}

2. Terminal History:
{json.dumps(observations.get('terminal', []), indent=2)}

3. File Markers (TODOs, FIXMEs, etc.):
{json.dumps(observations.get('files', []), indent=2)}

4. Session Activity:
{json.dumps(observations.get('sessions', []), indent=2)}

INFERENCE RULES:
- If uncommitted changes exist → "Review and commit changes"
- If failing tests → "Fix failing tests" (high priority)
- If merge conflicts → "Resolve conflicts" (high priority)
- If TODO/FIXME markers → "Address [marker]" (priority by severity)
- If incomplete session → "Continue [session topic]"
- If errors in terminal → "Fix error"
- If repeated commands → "Investigate stuck point"

Return ONLY a JSON array of tasks in this exact format:
[
  {{
    "title": "Clear task title",
    "priority": "high|medium|low",
    "confidence": 0.0-1.0,
    "context": "Detailed context for execution"
  }}
]

Only include tasks with confidence >= 0.5. Be specific and actionable."""
    
    def _parse_tasks(self, content: str) -> List[Dict]:
        """Parse task list from LLM response."""
        try:
            # Try to extract JSON from response
            start = content.find('[')
            end = content.rfind(']') + 1
            if start >= 0 and end > start:
                json_str = content[start:end]
                tasks = json.loads(json_str)
                
                # Validate and normalize
                validated = []
                for task in tasks:
                    if all(k in task for k in ['title', 'priority', 'confidence', 'context']):
                        validated.append({
                            'title': str(task['title']),
                            'priority': task['priority'] if task['priority'] in ['high', 'medium', 'low'] else 'medium',
                            'confidence': float(task['confidence']),
                            'context': str(task['context'])
                        })
                return validated
        except Exception as e:
            logging.error(f"Failed to parse LLM response: {e}")
        
        return []


class Observer:
    """Main observer service."""
    
    def __init__(self, config_path: str):
        self.config = self._load_config(config_path)
        self.setup_logging()
        
        # Initialize watchers
        self.git_watcher = GitWatcher(self.config['watch']['repos'])
        self.terminal_watcher = TerminalWatcher(self.config['watch']['terminal_log'])
        self.file_watcher = FileWatcher(self.config['watch']['repos'])
        self.session_watcher = SessionWatcher(self.config['watch']['session_db'])
        
        # Initialize inference engine
        self.inference = InferenceEngine(
            model_name=self.config['model']['name'],
            endpoint=self.config['model']['endpoint']
        )
    
    def _load_config(self, config_path: str) -> Dict:
        """Load configuration."""
        with open(config_path) as f:
            return yaml.safe_load(f)
    
    def setup_logging(self):
        """Configure logging."""
        log_config = self.config.get('logging', {})
        log_file = Path(log_config.get('file', '~/.ares/observer/observer.log')).expanduser()
        log_file.parent.mkdir(parents=True, exist_ok=True)
        
        logging.basicConfig(
            level=getattr(logging, log_config.get('level', 'INFO')),
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(str(log_file)),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('ares-observer')
    
    def observe(self) -> Dict:
        """Gather all observations."""
        self.logger.info("Gathering observations...")
        
        observations = {
            'git': self.git_watcher.check_all_repos(),
            'terminal': self.terminal_watcher.check_history(),
            'files': self.file_watcher.scan_all(),
            'sessions': self.session_watcher.check_sessions()
        }
        
        self.logger.info(f"Found {sum(len(v) for v in observations.values())} signals")
        return observations
    
    def infer_tasks(self, observations: Dict) -> List[Dict]:
        """Infer tasks from observations."""
        self.logger.info("Inferring tasks...")
        tasks = self.inference.infer_tasks(observations)
        self.logger.info(f"Inferred {len(tasks)} tasks")
        return tasks
    
    def create_kanban_tasks(self, tasks: List[Dict]):
        """Create tasks in ARES Kanban board."""
        import requests
        
        api_url = self.config['kanban']['api_url']
        auto_create = self.config['kanban'].get('auto_create', True)
        thresholds = self.config['confidence']
        
        if not tasks:
            self.logger.info("No tasks to create")
            return
        
        for task in tasks:
            confidence = task['confidence']
            
            # Filter by confidence
            if confidence < thresholds.get('queue_for_approval', 0.6):
                self.logger.info(f"Skipping low-confidence task: {task['title']} ({confidence})")
                continue
            
            if not auto_create and confidence < thresholds.get('auto_start', 0.85):
                self.logger.info(f"Task requires approval: {task['title']}")
                continue
            
            # Create task via API
            try:
                response = requests.post(
                    f"{api_url}/tasks",
                    json={
                        'title': task['title'],
                        'priority': task['priority'],
                        'context': task['context'],
                        'auto_generated': True,
                        'confidence': confidence,
                        'generated_at': datetime.now().isoformat()
                    },
                    timeout=10
                )
                
                if response.status_code in [200, 201]:
                    self.logger.info(f"✓ Created task: {task['title']}")
                elif response.status_code == 404:
                    self.logger.warning(f"Kanban API not found at {api_url}/tasks - ARES WebUI may need Kanban endpoint")
                    # Log task for manual review
                    self.logger.info(f"  Task (manual): [{task['priority']}] {task['title']}")
                else:
                    self.logger.error(f"API error: {response.status_code} - {response.text}")
                    
            except requests.ConnectionError as e:
                self.logger.error(f"Cannot connect to ARES API at {api_url} - is the WebUI running?")
                # Log task for manual review
                self.logger.info(f"  Task (manual): [{task['priority']}] {task['title']}")
            except requests.RequestException as e:
                self.logger.error(f"Failed to create task: {e}")
    
    def run_once(self):
        """Single observation-inference-creation cycle."""
        self.logger.info("Starting observer run...")
        
        observations = self.observe()
        tasks = self.infer_tasks(observations)
        self.create_kanban_tasks(tasks)
        
        self.logger.info("Observer run complete")
    
    def run_daemon(self):
        """Run as continuous daemon."""
        self.logger.info("Starting observer daemon...")
        
        intervals = self.config['intervals']
        
        last_git = 0
        last_terminal = 0
        last_files = 0
        last_sessions = 0
        
        while True:
            now = time.time()
            
            try:
                # Run watchers on their intervals
                if now - last_git >= intervals['git']:
                    last_git = now
                
                if now - last_terminal >= intervals['terminal']:
                    last_terminal = now
                
                if now - last_files >= intervals['files']:
                    last_files = now
                    observations = self.observe()
                    tasks = self.infer_tasks(observations)
                    self.create_kanban_tasks(tasks)
                
                if now - last_sessions >= intervals['sessions']:
                    last_sessions = now
                
                time.sleep(30)  # Check every 30 seconds
                
            except KeyboardInterrupt:
                self.logger.info("Shutting down...")
                break
            except Exception as e:
                self.logger.error(f"Error in daemon: {e}")
                time.sleep(60)  # Wait a minute before retry


def main():
    parser = argparse.ArgumentParser(description='ARES Observer Service')
    parser.add_argument('--config', default='config.yaml', help='Config file path')
    parser.add_argument('--run-once', action='store_true', help='Run once and exit')
    parser.add_argument('--daemon', action='store_true', help='Run as daemon')
    
    args = parser.parse_args()
    
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = Path(__file__).parent / config_path
    
    observer = Observer(str(config_path))
    
    if args.run_once or not args.daemon:
        observer.run_once()
    else:
        observer.run_daemon()


if __name__ == '__main__':
    main()

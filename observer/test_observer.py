#!/usr/bin/env python3
"""
Quick test of ARES Observer.
Run once and show inferred tasks.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from observer import Observer

# Run single observation cycle
observer = Observer('config.yaml')

print("=" * 60)
print("ARES Observer - Test Run")
print("=" * 60)

print("\n1. Gathering observations...")
observations = observer.observe()

print(f"   Git signals: {len(observations['git'])}")
print(f"   Terminal signals: {len(observations['terminal'])}")
print(f"   File signals: {len(observations['files'])}")
print(f"   Session signals: {len(observations['sessions'])}")

print("\n2. Inferring tasks...")
tasks = observer.infer_tasks(observations)

print(f"   Inferred {len(tasks)} tasks:\n")

for i, task in enumerate(tasks, 1):
    print(f"   {i}. [{task['priority'].upper()}] {task['title']}")
    print(f"      Confidence: {task['confidence']:.2f}")
    print(f"      Context: {task['context'][:100]}...")
    print()

print("=" * 60)
print("Test complete. Check ~/.ares/observer/observer.log for details.")
print("=" * 60)

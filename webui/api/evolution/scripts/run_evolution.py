#!/usr/bin/env python3
"""Run hermes-agent-self-evolution with Ollama Cloud backend.

This wrapper translates ollama-cloud model names → DSPy-compatible config,
loading OLLAMA_API_KEY from ~/.hermes/.env and routing through ollama.com/v1.

Usage — identical to the upstream evolve_skill, but with ollama-cloud model names:

    python scripts/run_evolution.py --skill github-code-review --iterations 5
    python scripts/run_evolution.py --skill arxiv --eval-source golden --dataset datasets/skills/arxiv/

    # Override models (use ollama-cloud/ prefix):
    python scripts/run_evolution.py --skill safari --optimizer-model ollama-cloud/deepseek-v4-flash --eval-model ollama-cloud/glm-5.1

Environment: reads OLLAMA_API_KEY from ~/.hermes/.env or current env.
"""

import os
import sys
import subprocess
from pathlib import Path

def load_ollama_key() -> str:
    """Load OLLAMA_API_KEY from ~/.hermes/.env or current environment."""
    # Check current env first
    key = os.environ.get("OLLAMA_API_KEY", "")
    if key:
        return key

    # Try loading from .env file
    env_file = Path.home() / ".hermes" / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line.startswith("OLLAMA_API_KEY="):
                parts = line.split("=", 1)
                if len(parts) == 2:
                    val = parts[1].strip().strip('"').strip("'")
                    if val and not val.startswith("#"):
                        return val
    return ""


def translate_model(model: str) -> str:
    """Translate ollama-cloud/ prefix to openai/ for DSPy compatibility.

    DSPy's openai/ provider hits OPENAI_BASE_URL which we set to ollama.com/v1.
    """
    if model.startswith("ollama-cloud/"):
        return "openai/" + model.split("/", 1)[1]
    if model.startswith("ollama/"):
        return "openai/" + model.split("/", 1)[1]
    # If it's a raw model name (no prefix), assume ollama-cloud
    return "openai/" + model


def main():
    # Load API key
    api_key = load_ollama_key()
    if not api_key:
        print("ERROR: OLLAMA_API_KEY not found in environment or ~/.hermes/.env")
        print("Set it via: export OLLAMA_API_KEY=<your_key>")
        sys.exit(1)

    # Configure environment for DSPy's openai provider to hit ollama cloud
    env = os.environ.copy()
    env["OPENAI_API_KEY"] = api_key
    env["OPENAI_BASE_URL"] = "https://ollama.com/v1"

    # Parse args and translate model names
    args = sys.argv[1:]

    # Translate --optimizer-model and --eval-model values
    translated = []
    skip_next = False
    for i, arg in enumerate(args):
        if skip_next:
            skip_next = False
            continue
        if arg == "--optimizer-model" and i + 1 < len(args):
            translated.append(arg)
            translated.append(translate_model(args[i + 1]))
            skip_next = True
        elif arg == "--eval-model" and i + 1 < len(args):
            translated.append(arg)
            translated.append(translate_model(args[i + 1]))
            skip_next = True
        elif arg.startswith("--optimizer-model="):
            _, model = arg.split("=", 1)
            translated.append(f"--optimizer-model={translate_model(model)}")
        elif arg.startswith("--eval-model="):
            _, model = arg.split("=", 1)
            translated.append(f"--eval-model={translate_model(model)}")
        else:
            translated.append(arg)

    # Set defaults if no model flags provided
    import argparse
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--optimizer-model", default=None)
    parser.add_argument("--eval-model", default=None)
    known, _ = parser.parse_known_args(args)

    if not known.optimizer_model:
        translated.extend(["--optimizer-model", "openai/deepseek-v4-flash"])
    if not known.eval_model:
        translated.extend(["--eval-model", "openai/glm-5.1"])

    # Run the evolution
    repo_dir = Path(__file__).resolve().parent.parent
    cmd = [
        sys.executable, "-m", "evolution.skills.evolve_skill",
        *translated,
    ]

    print(f"[ollama-cloud] Running with models: "
          f"optimizer={next((t.split('=')[1] if '=' in t else translated[translated.index('--optimizer-model')+1] for t in translated if t == '--optimizer-model'), 'openai/deepseek-v4-flash')}, "
          f"eval={next((t.split('=')[1] if '=' in t else translated[translated.index('--eval-model')+1] for t in translated if t == '--eval-model'), 'openai/glm-5.1')}")

    result = subprocess.run(cmd, env=env, cwd=str(repo_dir))
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()

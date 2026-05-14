"""LLM endpoint detection — MLX on Apple Silicon, llama.cpp fallback.

Local-first non-negotiable. No cloud fallback in default code path.
"""

import os
import platform
from dataclasses import dataclass
from typing import Literal

LLMBackend = Literal["mlx", "llama_cpp"]


@dataclass
class EndpointSpec:
    """Pure data — what backend and how to reach it."""

    backend: LLMBackend
    base_url: str
    model: str


def is_apple_silicon() -> bool:
    """True on M-series Macs."""
    return platform.processor() == "arm" and platform.system() == "Darwin"


def detect_local_endpoint() -> EndpointSpec:
    """Detect the best local LLM endpoint for this machine.

    MLX on Apple Silicon (1.5-2× faster than llama.cpp on M-series).
    llama.cpp everywhere else.

    Override with env vars:
    - LILITH_LLM_BACKEND: 'mlx' | 'llama_cpp'
    - LILITH_LLM_BASE_URL: override the default port
    - LILITH_LLM_MODEL: override the default model
    """
    backend_str = os.environ.get("LILITH_LLM_BACKEND")

    if backend_str == "mlx":
        backend: LLMBackend = "mlx"
    elif backend_str == "llama_cpp":
        backend = "llama_cpp"
    elif is_apple_silicon():
        backend = "mlx"
    else:
        backend = "llama_cpp"

    base_url = os.environ.get("LILITH_LLM_BASE_URL", "http://127.0.0.1:8080/v1")
    model = os.environ.get(
        "LILITH_LLM_MODEL", "mlx-community/gemma-3-12b-it-4bit" if backend == "mlx" else "gemma-3-12b-it"
    )

    return EndpointSpec(backend=backend, base_url=base_url, model=model)

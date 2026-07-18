"""ARES Hardware Fitting — model recommendation and serving profile engine.

Ported from Odysseus services/hwfit/ and modular-extracts/hwfit/.
Adapted for ARES: uses ARES config paths, ARES model catalog, ARES Ollama integration.

This module answers:
  "Given this hardware (RAM, GPU, VRAM), what local models can I run, and how?"
  "What quantization, context length, and serving profile should I use?"

The core fitting algorithm is hardware-agnostic and model-format-agnostic.
It works with GGUF, MLX, AWQ, GPTQ, and other quantization formats.

License: AGPL-3.0 (matches both projects)
"""

from api.hwfit.models import (
    QUANT_BPP, QUANT_HIERARCHY, QUANT_SPEED_MULT, QUANT_QUALITY_PENALTY,
    QUANT_BYTES_PER_PARAM, PREQUANTIZED_PREFIXES,
    params_b, estimate_memory_gb, infer_use_case, is_prequantized,
    best_quant_for_budget, _active_params_b, infer_quantization_from_name,
)
from api.hwfit.hardware import detect_hardware, HardwareSpec
from api.hwfit.fit import rank_models, analyze_model, _estimate_speed, _quality_score, _fit_score
from api.hwfit.profiles import compute_serve_profiles

__all__ = [
    # Model math
    "QUANT_BPP", "QUANT_HIERARCHY", "QUANT_SPEED_MULT", "QUANT_QUALITY_PENALTY",
    "QUANT_BYTES_PER_PARAM", "PREQUANTIZED_PREFIXES",
    "params_b", "estimate_memory_gb", "infer_use_case", "is_prequantized",
    "best_quant_for_budget", "_active_params_b", "infer_quantization_from_name",
    # Hardware
    "detect_hardware", "HardwareSpec",
    # Fitting
    "rank_models", "analyze_model",
    # Profiles
    "compute_serve_profiles",
]
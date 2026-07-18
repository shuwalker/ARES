"""
neuron_steer.py - Neuron Circuit Discovery and Steering for Language Models

LRP rules for linearized backward attribution:
  1. LN-rule: RMSNorm coefficient (weight * rsqrt) detached but preserved in backward
  2. AH-rule: Eager attention (no SDPA/Flash) for full autograd through Q/K/V/O
  3. Half-rule: Shapley attribution for gate*up elementwise multiply in MLP

Core insight: ~0.1% of MLP neurons form complete circuits. No SAE needed.
Attribution via single forward+backward pass.

Usage:
    steerer = NeuronSteerer("meta-llama/Llama-3.1-8B-Instruct")
    circuit = steerer.discover_circuit("What is the capital of Texas?", " Austin")
    steered = steerer.steer_and_generate("What is the capital of Texas?", circuit, multiplier=0.0)
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from typing import List, Tuple, Optional, Dict, NamedTuple, Set
from contextlib import contextmanager, nullcontext
from dataclasses import dataclass, field
from collections import defaultdict


# ============================================================
# Data Structures
# ============================================================

class NeuronIdx(NamedTuple):
    """Identifies a specific MLP neuron activation."""
    layer: int
    position: int
    neuron: int


# ============================================================
# Universal Neuron Blacklists
# Hard-coded from TransluceAI circuits repo (jvp.py) for Llama-3.1-8B.
# These fire universally across tasks, not task-specific.
# Format: (layer, neuron) - position-independent.
# ============================================================

def _get_model_layers(model):
    """Get decoder layers from any model architecture (Llama, Qwen, Gemma4, etc.)."""
    if hasattr(model.model, 'layers'):
        return model.model.layers
    elif hasattr(model.model, 'language_model') and hasattr(model.model.language_model, 'layers'):
        return model.model.language_model.layers
    else:
        raise AttributeError(
            f"Cannot find layers in model architecture: {type(model.model).__name__}. "
            f"Supported: .model.layers or .model.language_model.layers"
        )


BLACKLIST_LLAMA3_8B = {
    (23, 306), (20, 3972), (18, 7417), (16, 1241),
    (13, 4208), (11, 11321), (10, 11570), (9, 4255),
    (7, 6673), (6, 5866), (5, 7012), (2, 4786),
}


def detect_universal_neurons(
    model, tokenizer, device="cuda",
    n_prompts: int = 20, top_k: int = 50,
    threshold_fraction: float = 0.8,
):
    """Auto-detect universal neurons by finding neurons that appear
    in top-k attribution across diverse prompts.

    Returns set of (layer, neuron) tuples.
    """
    diverse_prompts = [
        "The capital of France is",
        "Once upon a time there was a",
        "The best programming language is",
        "In the year 2024, the world",
        "The key to the cabinets",
        "How do I bake a cake?",
        "What is photosynthesis?",
        "The CEO of Apple is",
        "My favorite color is",
        "The largest ocean on Earth is",
        "Yesterday I went to the",
        "The speed of light is approximately",
        "In machine learning, a neural network",
        "The president of the United States",
        "Water freezes at a temperature of",
        "The meaning of life is",
        "To solve this math problem,",
        "The Great Wall of China was",
        "An electron has a charge of",
        "The chemical formula for water is",
    ][:n_prompts]

    # Count how many prompts each neuron appears in
    from collections import Counter
    neuron_counts: Counter = Counter()

    for prompt in diverse_prompts:
        input_ids = tokenizer(prompt, return_tensors="pt").input_ids.to(device)

        # Collect activations via hooks (no linearization needed)
        layer_acts = {}
        hooks = []
        for i, layer in enumerate(_get_model_layers(model)):
            def make_hook(layer_idx):
                def hook_fn(module, args):
                    layer_acts[layer_idx] = args[0][0, -1].detach()
                return hook_fn
            h = layer.mlp.down_proj.register_forward_pre_hook(make_hook(i))
            hooks.append(h)

        try:
            with torch.no_grad():
                model(input_ids)
        finally:
            for h in hooks:
                h.remove()

        # Find top-k activated neurons per layer
        for layer_idx, act in layer_acts.items():
            top_vals, top_idxs = act.abs().topk(min(top_k, act.shape[0]))
            for idx in top_idxs:
                neuron_counts[(layer_idx, idx.item())] += 1

    # Neurons that appear in >= threshold_fraction of prompts are universal
    threshold = int(n_prompts * threshold_fraction)
    universal = {ln for ln, count in neuron_counts.items() if count >= threshold}
    return universal


@dataclass
class Circuit:
    """A set of neurons with their attributions."""
    neurons: Dict[NeuronIdx, float]
    prompt: str
    target_token: str
    total_logit_diff: float

    def top(self, k: int = 20) -> List[Tuple[NeuronIdx, float]]:
        """Return top-k neurons by attribution magnitude."""
        return sorted(self.neurons.items(), key=lambda x: abs(x[1]), reverse=True)[:k]

    def by_layer(self) -> Dict[int, List[Tuple[NeuronIdx, float]]]:
        """Group neurons by layer."""
        result: Dict[int, list] = {}
        for nidx, attr in self.neurons.items():
            result.setdefault(nidx.layer, []).append((nidx, attr))
        for l in result:
            result[l].sort(key=lambda x: abs(x[1]), reverse=True)
        return result

    def unique_neurons(self) -> Dict[int, Set[int]]:
        """Get unique neuron indices per layer (collapsing positions)."""
        result: Dict[int, Set[int]] = {}
        for nidx in self.neurons:
            result.setdefault(nidx.layer, set()).add(nidx.neuron)
        return result

    def save(self, path: str):
        """Save circuit to file."""
        import json
        data = {
            "neurons": {f"{n.layer},{n.position},{n.neuron}": v for n, v in self.neurons.items()},
            "prompt": self.prompt,
            "target_token": self.target_token,
            "total_logit_diff": self.total_logit_diff,
        }
        with open(path, "w") as f:
            json.dump(data, f, indent=2)

    @classmethod
    def load(cls, path: str) -> "Circuit":
        """Load circuit from file."""
        import json
        with open(path) as f:
            data = json.load(f)
        neurons = {}
        for key, val in data["neurons"].items():
            l, p, n = key.split(",")
            neurons[NeuronIdx(int(l), int(p), int(n))] = val
        return cls(neurons=neurons, prompt=data["prompt"],
                   target_token=data["target_token"],
                   total_logit_diff=data["total_logit_diff"])

    def summary(self) -> str:
        lines = [
            f"Circuit: {len(self.neurons)} neurons, logit_diff={self.total_logit_diff:.4f}",
            f"Prompt: {self.prompt[:80]}",
            f"Target: {self.target_token}",
            f"Layers touched: {sorted(set(n.layer for n in self.neurons))}",
        ]
        by_layer = self.by_layer()
        for l in sorted(by_layer.keys()):
            neurons = by_layer[l]
            lines.append(f"  L{l}: {len(neurons)} neurons, top={neurons[0][1]:.6f}")
        return "\n".join(lines)


# ============================================================
# LRP Rule 1: LN-rule (RMSNorm)
# Forward = real RMSNorm, Backward = identity through normalization
# ============================================================

class LinearizedRMSNorm(nn.Module):
    """Wraps RMSNorm with LN-rule.

    Forward = real RMSNorm value.
    Backward = grad * (weight * rsqrt(mean(x²) + eps)), where the coefficient
    is DETACHED (treated as constant, but its per-token value is preserved).

    coeff = weight * rsqrt(mean(x²) + eps), detached, then y = x * coeff. Since coeff is detached, backward = grad * coeff.
    """
    def __init__(self, original):
        super().__init__()
        self.weight = original.weight
        # Llama uses variance_epsilon, Qwen/Gemma/Mistral use eps
        if hasattr(original, 'variance_epsilon'):
            self.eps = original.variance_epsilon
        elif hasattr(original, 'eps'):
            self.eps = original.eps
        else:
            self.eps = 1e-6  # safe default
        self._original = original

    def forward(self, x):
        # Compute normalization coefficient: weight * rsqrt(mean(x²) + eps)
        # DETACH it so backward treats it as constant (LN-rule)
        input_dtype = x.dtype
        variance = x.float().pow(2).mean(-1, keepdim=True)
        coeff = self.weight.float() * torch.rsqrt(variance + self.eps)
        coeff = coeff.detach().to(input_dtype)  # key: treat as constant in backward
        return x * coeff


# ============================================================
# LRP Rule 3: Half-rule (Gated MLP)
# Shapley attribution for elementwise multiply: each factor gets 50% gradient
# ============================================================

class _HalfRuleMultiply(torch.autograd.Function):
    @staticmethod
    def forward(ctx, a, b):
        ctx.save_for_backward(a, b)
        return a * b

    @staticmethod
    def backward(ctx, grad_output):
        a, b = ctx.saved_tensors
        # Shapley value: each factor gets half credit
        return grad_output * b * 0.5, grad_output * a * 0.5


class LinearizedMLP(nn.Module):
    """Wraps LlamaMLP with detached sigmoid + half-rule.

    only the sigmoid is detached while the linear component of SiLU 
    (x * sigmoid(x)) keeps gradient flow, then the half-rule distributes
    credit evenly between gate and up projections.

    Standard Llama MLP:
        hidden = SiLU(gate_proj(x)) * up_proj(x)
        output = down_proj(hidden)

    Linearized version:
        gate = gate_proj(x)
        sigmoid_gate = sigmoid(gate).detach()  # treat sigmoid as constant
        gate_act = gate * sigmoid_gate          # linearized SiLU
        hidden = HalfRule(gate_act, up_proj(x)) # Shapley attribution
        output = down_proj(hidden)

    The `hidden` tensor (input to down_proj) = "neuron activation".
    This is what we attribute and steer.
    """
    def __init__(self, original):
        super().__init__()
        self.gate_proj = original.gate_proj
        self.up_proj = original.up_proj
        self.down_proj = original.down_proj
        self._original = original
        self.neuron_act = None  # saved during forward for attribution

    def forward(self, x):
        gate = self.gate_proj(x)
        up = self.up_proj(x)

        # Linearized SiLU: detach the sigmoid coefficient
        sigmoid_gate = torch.sigmoid(gate).detach()
        gate_act = gate * sigmoid_gate

        # Half-rule on elementwise multiply
        hidden = _HalfRuleMultiply.apply(gate_act, up)

        # Save neuron activation for attribution
        hidden.retain_grad()
        self.neuron_act = hidden

        return self.down_proj(hidden)


# ============================================================
# Model Linearization
# ============================================================

def _linearize_model(model):
    """Apply LRP rules to a Llama-family model.

    Rule 1 (LN): Replace RMSNorm with LinearizedRMSNorm (detached coeff)
    Rule 2 (AH): Force eager attention (no SDPA/Flash) for autograd compatibility
    Rule 3 (Half): Replace MLP with LinearizedMLP (linearized SiLU + half-rule)

    Returns dict for restoration.
    """
    originals = {"modules": {}, "hooks": []}

    # Rule 2: Force eager attention
    # This ensures gradient flows through all attention paths including Q/K.
    originals["attn_impl"] = model.config._attn_implementation
    model.config._attn_implementation = "eager"

    # Rule 1: RMSNorm → LinearizedRMSNorm
    originals["modules"]["model.norm"] = model.model.norm
    model.model.norm = LinearizedRMSNorm(model.model.norm)

    for i, layer in enumerate(_get_model_layers(model)):
        # Input layernorm
        originals["modules"][f"layer.{i}.input_layernorm"] = layer.input_layernorm
        layer.input_layernorm = LinearizedRMSNorm(layer.input_layernorm)

        # Post-attention layernorm
        originals["modules"][f"layer.{i}.post_attention_layernorm"] = layer.post_attention_layernorm
        layer.post_attention_layernorm = LinearizedRMSNorm(layer.post_attention_layernorm)

        # Rule 2: AH-rule — replace SDPA/Flash with eager attention
        # (not fused SDPA/Flash) for autograd compatibility. Gradient DOES flow
        # through Q/K — the class name is misleading. We match their behavior.

        # Rule 3: MLP → LinearizedMLP
        originals["modules"][f"layer.{i}.mlp"] = layer.mlp
        layer.mlp = LinearizedMLP(layer.mlp)

    return originals


def _restore_model(model, originals):
    """Restore original model modules."""
    # Remove backward hooks
    for hook in originals["hooks"]:
        hook.remove()

    # Restore attention implementation
    if "attn_impl" in originals:
        model.config._attn_implementation = originals["attn_impl"]

    # Restore modules
    model.model.norm = originals["modules"]["model.norm"]
    for i, layer in enumerate(_get_model_layers(model)):
        layer.input_layernorm = originals["modules"][f"layer.{i}.input_layernorm"]
        layer.post_attention_layernorm = originals["modules"][f"layer.{i}.post_attention_layernorm"]
        layer.mlp = originals["modules"][f"layer.{i}.mlp"]


@contextmanager
def linearized(model):
    """Context manager: apply LRP rules for attribution, restore after."""
    originals = _linearize_model(model)
    try:
        yield model
    finally:
        _restore_model(model, originals)


# ============================================================
# Attribution
# ============================================================

def compute_attribution(
    model,
    input_ids: torch.Tensor,
    target_token_id: int,
    counterfactual_token_id: Optional[int] = None,
    position: int = -1,
    top_k_per_layer: int = 200,
    filter_bos: bool = True,
    last_n_positions: Optional[int] = None,
    blacklist_layers: Optional[Set[int]] = None,
    blacklist_neurons: Optional[Set[Tuple[int, int]]] = None,
    target_only: bool = False,
    verbose: bool = False,
) -> Tuple[Dict[NeuronIdx, float], float]:
    """Compute per-neuron attribution.

    Args:
        model: Linearized Llama model (inside `linearized()` context)
        input_ids: [1, T] input token ids
        target_token_id: Token to attribute toward
        counterfactual_token_id: Alternative token for logit diff (None = auto or target_only)
        position: Token position for logit measurement (default: last)
        top_k_per_layer: Keep top-k neurons per layer per position (sparsification)
        filter_bos: If True, exclude position 0 (BOS) neurons
        last_n_positions: If set, only keep neurons from the last N token positions.
        blacklist_layers: Set of layer indices to exclude entirely
        blacklist_neurons: Set of (layer, neuron) tuples to exclude
        target_only: If True, backward from target logit alone.
            If False and no counterfactual given, auto-detects 2nd highest logit.
            Use target_only=True for percentage_threshold selection.
        verbose: Print diagnostic info about attribution distribution

    Returns:
        (attributions dict, metric_value scalar)
        metric_value is target_logit when target_only=True, else logit_diff
    """
    blacklist_layers = blacklist_layers or set()
    blacklist_neurons = blacklist_neurons or set()
    model.eval()
    model.zero_grad()

    # Clear any saved neuron activations
    for layer in _get_model_layers(model):
        if hasattr(layer.mlp, "neuron_act"):
            layer.mlp.neuron_act = None

    with torch.enable_grad():
        outputs = model(input_ids)
        logits = outputs.logits[0, position]  # [vocab_size]

        target_logit = logits[target_token_id]

        if target_only:
            metric = target_logit
        elif counterfactual_token_id is None:
            sorted_logits, sorted_ids = logits.sort(descending=True)
            if sorted_ids[0].item() == target_token_id:
                counterfactual_logit = sorted_logits[1]
            else:
                counterfactual_logit = sorted_logits[0]
            metric = target_logit - counterfactual_logit
        else:
            counterfactual_logit = logits[counterfactual_token_id]
            metric = target_logit - counterfactual_logit

        # Backward through linearized model
        metric.backward()

    # Collect attributions from saved neuron activations
    attributions = {}
    layer_stats = {}  # diagnostic info

    for i, layer in enumerate(_get_model_layers(model)):
        if i in blacklist_layers:
            continue

        mlp = layer.mlp
        if not hasattr(mlp, "neuron_act") or mlp.neuron_act is None:
            continue
        if mlp.neuron_act.grad is None:
            continue

        act = mlp.neuron_act.detach()   # [1, T, intermediate_size]
        grad = mlp.neuron_act.grad      # [1, T, intermediate_size]

        # Attribution = gradient * activation (element-wise)
        attr = (grad * act)[0]  # [T, intermediate_size]
        T = attr.shape[0]

        # NaN-safe statistics (exclude NaN from sums)
        valid_mask = ~torch.isnan(attr)
        valid_attr = attr[valid_mask]
        if valid_attr.numel() > 0:
            layer_total = valid_attr.abs().sum().item()
            layer_max = valid_attr.abs().max().item()
            nan_frac = 1.0 - valid_mask.float().mean().item()
        else:
            layer_total = 0.0
            layer_max = 0.0
            nan_frac = 1.0
        layer_stats[i] = {"total": layer_total, "max": layer_max, "nan_frac": nan_frac}

        if last_n_positions is not None:
            start_pos = max(0, T - last_n_positions)
        elif filter_bos:
            start_pos = 1
        else:
            start_pos = 0
        for p in range(start_pos, T):
            pos_attr = attr[p]
            abs_attr = pos_attr.abs()

            # NaN-safe topk: replace NaN with 0 so they don't crowd out valid values
            nan_mask = torch.isnan(abs_attr)
            if nan_mask.any():
                abs_attr = abs_attr.clone()
                abs_attr[nan_mask] = 0.0

            # Keep top-k neurons at this position
            k = min(top_k_per_layer, abs_attr.shape[0])
            top_vals, top_idxs = abs_attr.topk(k)

            for val, idx in zip(top_vals, top_idxs):
                if val.item() > 1e-8:
                    n = idx.item()
                    if (i, n) in blacklist_neurons:
                        continue
                    nidx = NeuronIdx(layer=i, position=p, neuron=n)
                    attributions[nidx] = pos_attr[idx].item()

    # Free GPU memory - clear saved activations after collection
    for layer in _get_model_layers(model):
        if hasattr(layer.mlp, "neuron_act"):
            layer.mlp.neuron_act = None

    if verbose:
        print(f"  Attribution distribution by layer:")
        has_nan = False
        for l in sorted(layer_stats.keys()):
            s = layer_stats[l]
            nan_str = f" [NaN: {s['nan_frac']:.1%}]" if s['nan_frac'] > 0.01 else ""
            print(f"    L{l:2d}: total={s['total']:.4f}, max={s['max']:.4f}{nan_str}")
            if s['nan_frac'] > 0.01:
                has_nan = True
        total_attr = sum(abs(v) for v in attributions.values())
        print(f"  Total (filtered): {total_attr:.4f}, {len(attributions)} neurons")
        if has_nan:
            print(f"  WARNING: NaN in gradients detected. LRP rules may not be compatible with this model.")

    return attributions, metric.item()


def select_circuit(
    attributions: Dict[NeuronIdx, float],
    method: str = "threshold",
    threshold: float = 0.005,
    top_k: Optional[int] = None,
    per_layer_topk: Optional[int] = None,
    reference_value: Optional[float] = None,
) -> Dict[NeuronIdx, float]:
    """Select circuit neurons from attributions.

    Methods:
        'threshold': Select neurons until cumulative |attribution| >= threshold * total
        'topk': Select top-k neurons by |attribution| (globally)
        'percentage': Keep neurons with INDIVIDUAL
            |attribution| >= threshold * |reference_value|.
            When percentage_threshold=0.005, keeps neurons contributing >= 0.5%
            of the logit diff. This filters noise while preserving all significant neurons.
            Requires reference_value (typically logit_diff).
        'per_layer_topk': Select top-N from EACH layer, then take global top_k.
            Essential for models like Qwen where early layers dominate by 10^10.
    """
    if not attributions:
        return {}

    total = sum(abs(v) for v in attributions.values())
    if total < 1e-10:
        return {}

    if method == "per_layer_topk" and per_layer_topk is not None:
        # Group by layer, take top-N from each, then global top_k
        by_layer: Dict[int, List] = {}
        for nidx, attr in attributions.items():
            by_layer.setdefault(nidx.layer, []).append((nidx, attr))

        selected = {}
        for layer_idx, neurons in by_layer.items():
            neurons.sort(key=lambda x: abs(x[1]), reverse=True)
            for nidx, attr in neurons[:per_layer_topk]:
                selected[nidx] = attr

        # If also top_k specified, trim globally
        if top_k is not None and len(selected) > top_k:
            sorted_sel = sorted(selected.items(), key=lambda x: abs(x[1]), reverse=True)
            selected = dict(sorted_sel[:top_k])
        return selected

    sorted_attrs = sorted(attributions.items(), key=lambda x: abs(x[1]), reverse=True)

    if method == "topk" and top_k is not None:
        return dict(sorted_attrs[:top_k])

    if method == "percentage" and reference_value is not None:
        abs_threshold = threshold * abs(reference_value)
        selected = {nidx: attr for nidx, attr in attributions.items()
                    if abs(attr) >= abs_threshold}
        return selected

    # Default: cumulative threshold
    selected = {}
    cumulative = 0.0
    for nidx, attr in sorted_attrs:
        selected[nidx] = attr
        cumulative += abs(attr)
        if cumulative >= threshold * total:
            break

    return selected


# ============================================================
# Steering
# ============================================================

@contextmanager
def steer_neurons(
    model,
    neurons: Dict[NeuronIdx, float],
    multiplier: float = 0.0,
    all_positions: bool = True,
):
    """Apply steering hooks to specific neurons during forward pass.

    Modifies neuron activations (input to down_proj) by multiplying with `multiplier`.
    multiplier=0.0 → ablate, 1.0 → no change, 2.0 → amplify

    If all_positions=True, steers the neuron at ALL positions (for generation).
    If False, only steers at the specific positions from the circuit.
    """
    hooks = []

    if all_positions:
        # Group by layer, collect unique neuron indices
        by_layer: Dict[int, List[int]] = {}
        for nidx in neurons:
            by_layer.setdefault(nidx.layer, set()).add(nidx.neuron)
        by_layer = {l: sorted(ns) for l, ns in by_layer.items()}

        for layer_idx, neuron_indices in by_layer.items():
            idx_tensor = torch.tensor(neuron_indices, dtype=torch.long)

            def make_hook(idx_t):
                def pre_hook(module, args):
                    x = args[0].clone()
                    device_idx = idx_t.to(x.device)
                    x[:, :, device_idx] *= multiplier
                    return (x,)
                return pre_hook

            hook = _get_model_layers(model)[layer_idx].mlp.down_proj.register_forward_pre_hook(
                make_hook(idx_tensor)
            )
            hooks.append(hook)
    else:
        # Group by (layer, position)
        by_layer_pos: Dict[Tuple[int, int], List[int]] = {}
        for nidx in neurons:
            key = (nidx.layer, nidx.position)
            by_layer_pos.setdefault(key, []).append(nidx.neuron)

        # Group by layer for efficient hooking
        layer_pos_map: Dict[int, Dict[int, List[int]]] = {}
        for (l, p), ns in by_layer_pos.items():
            layer_pos_map.setdefault(l, {})[p] = ns

        for layer_idx, pos_map in layer_pos_map.items():
            def make_hook(pm):
                def pre_hook(module, args):
                    x = args[0].clone()
                    for pos, neuron_indices in pm.items():
                        idx_t = torch.tensor(neuron_indices, dtype=torch.long, device=x.device)
                        x[:, pos, idx_t] *= multiplier
                    return (x,)
                return pre_hook

            hook = _get_model_layers(model)[layer_idx].mlp.down_proj.register_forward_pre_hook(
                make_hook(pos_map)
            )
            hooks.append(hook)

    try:
        yield model
    finally:
        for hook in hooks:
            hook.remove()


# ============================================================
# High-Level API
# ============================================================

class NeuronSteerer:
    """End-to-end neuron circuit discovery and steering.

    Pipeline:
        1. Load model (eager attention for compatibility)
        2. discover_circuit(): linearize → forward → backward → select neurons
        3. steer_and_generate(): hook neurons → generate with modified activations

    """

    def __init__(self, model_name: str, device: str = "cuda", dtype=torch.bfloat16,
                 auto_blacklist: bool = True, max_memory: dict = None):
        from transformers import AutoModelForCausalLM, AutoTokenizer

        print(f"Loading {model_name}...")
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        if self.tokenizer.pad_token is None:
            self.tokenizer.pad_token = self.tokenizer.eos_token
        self.model = AutoModelForCausalLM.from_pretrained(
            model_name,
            device_map="auto",
            attn_implementation="eager",
            dtype=dtype,
            **({"max_memory": max_memory} if max_memory else {}),
        )
        self.model.eval()
        self.device = device
        self.model_name = model_name
        self.is_instruct = "instruct" in model_name.lower() or "chat" in model_name.lower()
        print(f"Loaded {model_name} on {device} (instruct={self.is_instruct})")

        # Auto-detect layer path for different architectures (Llama, Qwen, Gemma4, etc.)
        if hasattr(self.model.model, 'layers'):
            self._layers_ref = self.model.model.layers
        elif hasattr(self.model.model, 'language_model') and hasattr(self.model.model.language_model, 'layers'):
            self._layers_ref = self.model.model.language_model.layers
        else:
            raise AttributeError(
                f"Cannot find layers in model architecture: {type(self.model.model).__name__}. "
                f"Supported: .model.layers or .model.language_model.layers"
            )
        print(f"  Layers: {len(self._layers_ref)} (via {'model.layers' if hasattr(self.model.model, 'layers') else 'model.language_model.layers'})")

        # Auto-detect config path for multimodal models (Gemma4, etc.)
        if hasattr(self.model.config, 'text_config'):
            self._text_config = self.model.config.text_config
        else:
            self._text_config = self.model.config

        # Feature cache: name -> Circuit for reuse across steer() calls
        self._feature_cache: Dict[str, Circuit] = {}

        # Universal neuron blacklist (model-conditional)
        is_llama_8b = "llama" in model_name.lower() and ("8b" in model_name.lower() or "8B" in model_name)
        if is_llama_8b:
            self.blacklist: Set[Tuple[int, int]] = set(BLACKLIST_LLAMA3_8B)
            known_str = f"{len(BLACKLIST_LLAMA3_8B)} from TransluceAI"
        else:
            self.blacklist: Set[Tuple[int, int]] = set()
            known_str = "0 known (non-Llama-8B model)"

        if auto_blacklist:
            print("Detecting universal neurons...")
            detected = detect_universal_neurons(
                self.model, self.tokenizer, device,
                n_prompts=10, top_k=20, threshold_fraction=0.8,
            )
            new_detected = detected - self.blacklist
            self.blacklist |= detected
            print(f"  Blacklist: {len(self.blacklist)} universal neurons "
                  f"({known_str} + {len(new_detected)} new auto-detected)")

    def _format_prompt(self, prompt: str, seed_response: str = "") -> str:
        """Format prompt for instruct models using chat template."""
        if self.is_instruct and hasattr(self.tokenizer, "apply_chat_template"):
            messages = [{"role": "user", "content": prompt}]
            formatted = self.tokenizer.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True
            )
            return formatted + seed_response
        return prompt + seed_response

    def discover_circuit(
        self,
        prompt: str,
        target_token: str,
        counterfactual_token: Optional[str] = None,
        threshold: float = 0.005,
        top_k: Optional[int] = None,
        selection_method: Optional[str] = None,
        seed_response: str = "",
        filter_bos: bool = True,
        filter_infrastructure: bool = False,
        last_n_positions: Optional[int] = None,
        blacklist_neurons: Optional[Set[Tuple[int, int]]] = None,
        use_chat_template: bool = True,
        verbose: bool = False,
    ) -> Circuit:
        """Discover the neuron circuit for predicting target_token.

        Selection methods:
            top_k=N: Select exactly N neurons by |attribution|
            selection_method='percentage': keep neurons with
                |attribution| >= threshold * |logit_diff|. Default threshold=0.005.
            Default: cumulative threshold

        Args:
            prompt: Input text (auto-formatted for instruct models)
            target_token: Target output token (e.g., " Austin")
            counterfactual_token: Alternative token (auto if None)
            threshold: Attribution threshold (meaning depends on selection_method)
            top_k: Select exactly top_k neurons (overrides threshold)
            selection_method: 'percentage' for individual neuron threshold
            seed_response: Text to append before target (e.g., "Answer:")
            filter_bos: Filter out BOS position neurons
            filter_infrastructure: Filter out L0-L1, or pass set of layer indices
            use_chat_template: Use chat template for instruct models (False for raw completion like SVA)
            verbose: Print attribution diagnostics
        """
        if use_chat_template:
            formatted = self._format_prompt(prompt, seed_response)
        else:
            formatted = prompt + seed_response
        input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)

        # Tokenization validation
        target_ids = self.tokenizer.encode(target_token, add_special_tokens=False)
        target_id = target_ids[-1]
        if len(target_ids) > 1 and verbose:
            print(f"  WARNING: target '{target_token}' encodes to {len(target_ids)} tokens "
                  f"{target_ids}. Using last token ({target_id}) for attribution.")

        cf_id = None
        if counterfactual_token:
            cf_ids = self.tokenizer.encode(counterfactual_token, add_special_tokens=False)
            cf_id = cf_ids[-1]
            if len(cf_ids) > 1 and verbose:
                print(f"  WARNING: counterfactual '{counterfactual_token}' encodes to {len(cf_ids)} tokens "
                      f"{cf_ids}. Using last token ({cf_id}).")
            if cf_id == target_id:
                print(f"  ERROR: target and counterfactual share first token ({target_id})! "
                      f"Logit diff will be 0. Fix your token strings.")

        bl_layers = filter_infrastructure if isinstance(filter_infrastructure, set) else ({0, 1} if filter_infrastructure else set())
        bl_neurons = blacklist_neurons if blacklist_neurons is not None else self.blacklist

        # Use target_only when doing percentage selection
        use_target_only = (selection_method == "percentage")

        with linearized(self.model):
            attributions, metric_value = compute_attribution(
                self.model, input_ids, target_id, cf_id,
                filter_bos=filter_bos, verbose=verbose,
                last_n_positions=last_n_positions,
                blacklist_layers=bl_layers,
                blacklist_neurons=bl_neurons,
                target_only=use_target_only,
            )

        # Select circuit
        if top_k:
            method = "topk"
        elif selection_method == "percentage":
            method = "percentage"
        else:
            method = "threshold"
        circuit_neurons = select_circuit(
            attributions, method=method, threshold=threshold, top_k=top_k,
            reference_value=metric_value,
        )

        return Circuit(
            neurons=circuit_neurons,
            prompt=formatted,
            target_token=target_token,
            total_logit_diff=metric_value,
        )

    def discover_circuit_multi(
        self,
        prompts: List[str],
        target_tokens: List[str],
        counterfactual_tokens: Optional[List[str]] = None,
        threshold: float = 0.005,
        top_k: Optional[int] = None,
        selection_method: Optional[str] = None,
        seed_response: str = "",
        filter_bos: bool = True,
        filter_infrastructure: bool = False,
        last_n_positions: Optional[int] = None,
        blacklist_neurons: Optional[Set[Tuple[int, int]]] = None,
        batch_aggregation: str = "mean",
        use_chat_template: bool = True,
        verbose: bool = False,
        precomputed_attributions: Optional[Tuple[Dict, float]] = None,
        return_raw_attributions: bool = False,
        target_only: Optional[bool] = None,
    ) -> "Circuit | Tuple[Circuit, Dict, float]":
        """Discover circuit over multiple prompts.

        batch_aggregation modes:
            'mean': Average attributions across all prompts (default)
            'any': Keep neuron if it's important in ANY prompt (union)
                   Preserves prompt-specific neurons

        selection_method='percentage' + threshold=0.005: keep neurons with |attr| >= 0.5% of |reference_value|.
        When no counterfactual tokens given, auto-enables target_only (backprop from target
        logit alone, not logit_diff)

        precomputed_attributions: (aggregated_dict, avg_ld) from a prior call with
            return_raw_attributions=True. Skips all LRP computation — only does selection.
        return_raw_attributions: if True, returns (Circuit, aggregated_dict, avg_ld) so
            you can call again with different top_k without recomputing LRP.
        """
        # Fast path: use precomputed attributions (skip all LRP)
        if precomputed_attributions is not None:
            aggregated, avg_ld = precomputed_attributions
            if top_k:
                circuit_neurons = select_circuit(aggregated, method="topk", top_k=top_k)
            elif selection_method == "percentage":
                circuit_neurons = select_circuit(
                    aggregated, method="percentage", threshold=threshold,
                    reference_value=avg_ld)
            else:
                circuit_neurons = select_circuit(
                    aggregated, method="threshold", threshold=threshold)
            circuit = Circuit(
                neurons=circuit_neurons,
                prompt=f"[{len(prompts)} prompts, agg={batch_aggregation}]",
                target_token=str(target_tokens[:3]),
                total_logit_diff=avg_ld,
            )
            if return_raw_attributions:
                return circuit, aggregated, avg_ld
            return circuit

        all_attributions: Dict[NeuronIdx, List[float]] = defaultdict(list)
        logit_diffs = []
        bl_layers = filter_infrastructure if isinstance(filter_infrastructure, set) else ({0, 1} if filter_infrastructure else set())
        bl_neurons = blacklist_neurons if blacklist_neurons is not None else self.blacklist

        # Use target_only when doing percentage selection or explicitly requested
        use_target_only = target_only if target_only is not None else (selection_method == "percentage")

        # For percentage + "any": apply threshold PER PROMPT
        # Each prompt gets its own threshold = percentage * that_prompt's_target_logit
        # Then union across prompts
        per_prompt_filter = (selection_method == "percentage" and batch_aggregation == "any")

        for i, (prompt, target) in enumerate(zip(prompts, target_tokens)):
            cf = counterfactual_tokens[i] if counterfactual_tokens else None

            if use_chat_template:
                formatted = self._format_prompt(prompt, seed_response)
            else:
                formatted = prompt + seed_response
            input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)
            target_id = self.tokenizer.encode(target, add_special_tokens=False)[-1]
            cf_id = self.tokenizer.encode(cf, add_special_tokens=False)[-1] if cf else None

            with linearized(self.model):
                attrs, ld = compute_attribution(
                    self.model, input_ids, target_id, cf_id,
                    filter_bos=filter_bos, verbose=False,
                    last_n_positions=last_n_positions,
                    blacklist_layers=bl_layers,
                    blacklist_neurons=bl_neurons,
                    target_only=use_target_only,
                )

            if per_prompt_filter:
                abs_thresh = threshold * abs(ld)
                filtered = {nidx: attr for nidx, attr in attrs.items()
                            if abs(attr) >= abs_thresh}
                for nidx, attr in filtered.items():
                    all_attributions[nidx].append(attr)
                if verbose:
                    print(f"  Prompt {i+1}/{len(prompts)}: {len(filtered)} neurons "
                          f"(of {len(attrs)} raw), ld={ld:.4f}, thresh={abs_thresh:.6f}")
            else:
                for nidx, attr in attrs.items():
                    all_attributions[nidx].append(attr)
                if verbose:
                    print(f"  Prompt {i+1}/{len(prompts)}: {len(attrs)} neurons, ld={ld:.4f}")

            logit_diffs.append(ld)

        # Aggregate attributions
        if batch_aggregation == "any":
            aggregated = {}
            for nidx, attr_list in all_attributions.items():
                aggregated[nidx] = max(attr_list, key=abs)
        else:
            aggregated = {}
            for nidx, attr_list in all_attributions.items():
                aggregated[nidx] = sum(attr_list) / len(prompts)

        avg_ld = sum(logit_diffs) / len(logit_diffs)

        # Select circuit
        if per_prompt_filter:
            # Already filtered per-prompt, just use what we have
            circuit_neurons = aggregated
        elif top_k:
            circuit_neurons = select_circuit(
                aggregated, method="topk", top_k=top_k)
        elif selection_method == "percentage":
            circuit_neurons = select_circuit(
                aggregated, method="percentage", threshold=threshold,
                reference_value=avg_ld)
        else:
            circuit_neurons = select_circuit(
                aggregated, method="threshold", threshold=threshold)

        circuit = Circuit(
            neurons=circuit_neurons,
            prompt=f"[{len(prompts)} prompts, agg={batch_aggregation}]",
            target_token=str(target_tokens[:3]),
            total_logit_diff=avg_ld,
        )

        if return_raw_attributions:
            return circuit, aggregated, avg_ld
        return circuit

    def discover_contrastive(
        self,
        positive_prompts: List[str],
        negative_prompts: List[str],
        top_k: int = 200,
        filter_infrastructure: bool = True,
        verbose: bool = False,
    ) -> Circuit:
        """Discover neurons by contrasting activations between two prompt sets.

        This is better for behavioral steering (refusal, tone, style) where
        there's no clean target/counterfactual token pair.

        Runs all prompts through the model, collects MLP neuron activations
        at the last token position, then finds neurons with largest activation
        difference between positive and negative sets.

        Args:
            positive_prompts: Prompts exhibiting the target behavior (e.g., harmful prompts that get refused)
            negative_prompts: Prompts NOT exhibiting it (e.g., benign prompts that get answered)
            top_k: Number of neurons to select
            filter_infrastructure: Exclude L0-L1
        """
        # filter_infrastructure: True={0,1}, or pass a set like {0,1,2,3,4} for Qwen
        bl_layers = filter_infrastructure if isinstance(filter_infrastructure, set) else ({0, 1} if filter_infrastructure else set())

        def collect_activations(prompts):
            """Run prompts and collect last-position neuron activations per layer.

            Uses forward pre-hooks on down_proj to capture the input (= neuron activations)
            without requiring linearization or gradients.
            """
            all_acts = []
            for prompt in prompts:
                formatted = self._format_prompt(prompt)
                input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)

                # Hook into down_proj to capture neuron activations
                layer_acts = {}
                hooks = []
                for i, layer in enumerate(self._layers_ref):
                    if i in bl_layers:
                        continue
                    def make_hook(layer_idx):
                        def hook_fn(module, args):
                            layer_acts[layer_idx] = args[0][0, -1].detach().cpu()
                        return hook_fn
                    h = layer.mlp.down_proj.register_forward_pre_hook(make_hook(i))
                    hooks.append(h)

                try:
                    with torch.no_grad():
                        self.model(input_ids)
                finally:
                    for h in hooks:
                        h.remove()

                all_acts.append(layer_acts)
            return all_acts

        print(f"  Collecting activations for {len(positive_prompts)} positive prompts...")
        pos_acts = collect_activations(positive_prompts)
        print(f"  Collecting activations for {len(negative_prompts)} negative prompts...")
        neg_acts = collect_activations(negative_prompts)

        # Compute mean activation per neuron for each set
        all_layers = set()
        for acts in pos_acts + neg_acts:
            all_layers.update(acts.keys())

        neurons_with_diff = {}
        for layer_idx in sorted(all_layers):
            pos_mean = torch.stack([a[layer_idx] for a in pos_acts if layer_idx in a]).mean(0)
            neg_mean = torch.stack([a[layer_idx] for a in neg_acts if layer_idx in a]).mean(0)

            diff = pos_mean - neg_mean  # positive = more active in positive set

            for n in range(diff.shape[0]):
                d = diff[n].item()
                if abs(d) > 1e-6:
                    nidx = NeuronIdx(layer=layer_idx, position=-1, neuron=n)
                    neurons_with_diff[nidx] = d

        # Select top-k by absolute difference
        sorted_neurons = sorted(neurons_with_diff.items(), key=lambda x: abs(x[1]), reverse=True)
        circuit_neurons = dict(sorted_neurons[:top_k])

        if verbose:
            print(f"  Found {len(neurons_with_diff)} neurons with nonzero difference")
            by_layer_count = defaultdict(int)
            for nidx in circuit_neurons:
                by_layer_count[nidx.layer] += 1
            for l in sorted(by_layer_count.keys()):
                print(f"    L{l:2d}: {by_layer_count[l]} neurons")

        return Circuit(
            neurons=circuit_neurons,
            prompt=f"[contrastive: {len(positive_prompts)} pos vs {len(negative_prompts)} neg]",
            target_token="[contrastive]",
            total_logit_diff=0.0,
        )

    # ============================================================
    # CAA ↔ Neuron Circuit Connection (Novel)
    # ============================================================

    def compute_control_vector(
        self,
        positive_prompts: List[str],
        negative_prompts: List[str],
        layer_idx: Optional[int] = None,
        seed_response: str = "",
        use_chat_template: bool = True,
    ) -> Dict[int, torch.Tensor]:
        """Compute a Contrastive Activation Addition (CAA) control vector.

        v = mean(activations_positive) - mean(activations_negative)
        at the residual stream after each MLP layer.

        Args:
            positive_prompts: Prompts that elicit target behavior
            negative_prompts: Prompts that elicit opposite behavior
            layer_idx: If set, only compute for this layer. Otherwise all layers.
            seed_response: Appended after prompt
            use_chat_template: Use chat template formatting

        Returns:
            Dict[layer_idx, control_vector] where each CV is [d_model]
        """
        layers = [layer_idx] if layer_idx is not None else list(range(len(self._layers_ref)))

        def collect_residual(prompts):
            """Collect residual stream activations after MLP for each layer."""
            all_acts = {l: [] for l in layers}
            for prompt in prompts:
                if use_chat_template:
                    formatted = self._format_prompt(prompt, seed_response)
                else:
                    formatted = prompt + seed_response
                input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)

                # Hook to capture post-MLP residual at last token position
                captured = {}
                hooks = []
                for l in layers:
                    def make_hook(layer_idx):
                        def hook_fn(module, input, output):
                            # output is tuple or BaseModelOutput — extract hidden states
                            hs = output[0] if isinstance(output, tuple) else output
                            if hasattr(hs, 'last_hidden_state'):
                                hs = hs.last_hidden_state
                            captured[layer_idx] = hs[0, -1].detach().clone()
                        return hook_fn
                    h = self._layers_ref[l].register_forward_hook(make_hook(l))
                    hooks.append(h)

                try:
                    with torch.no_grad():
                        self.model(input_ids)
                finally:
                    for h in hooks:
                        h.remove()

                for l in layers:
                    if l in captured:
                        all_acts[l].append(captured[l])

            return {l: torch.stack(acts) for l, acts in all_acts.items() if acts}

        pos_acts = collect_residual(positive_prompts)
        neg_acts = collect_residual(negative_prompts)

        control_vectors = {}
        for l in layers:
            if l in pos_acts and l in neg_acts:
                cv = pos_acts[l].mean(dim=0) - neg_acts[l].mean(dim=0)
                control_vectors[l] = cv

        return control_vectors

    def compute_mlp_control_vector(
        self,
        positive_prompts: List[str],
        negative_prompts: List[str],
        layer_idx: Optional[int] = None,
        seed_response: str = "",
        use_chat_template: bool = True,
    ) -> Dict[int, torch.Tensor]:
        """Compute control vector from MLP outputs ONLY (not attention).

        Unlike compute_control_vector which captures full residual stream
        (attention + MLP), this hooks the MLP sublayer directly. 

        Returns:
            Dict[layer_idx, mlp_control_vector] where each CV is [d_model]
        """
        layers = [layer_idx] if layer_idx is not None else list(range(len(self._layers_ref)))

        def collect_mlp_output(prompts):
            all_acts = {l: [] for l in layers}
            for prompt in prompts:
                if use_chat_template:
                    formatted = self._format_prompt(prompt, seed_response)
                else:
                    formatted = prompt + seed_response
                input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)

                captured = {}
                hooks = []
                for l in layers:
                    def make_hook(layer_idx):
                        def hook_fn(module, input, output):
                            # MLP output is a tensor, not tuple
                            out = output[0] if isinstance(output, tuple) else output
                            captured[layer_idx] = out[0, -1].detach().clone()
                        return hook_fn
                    h = self._layers_ref[l].mlp.register_forward_hook(make_hook(l))
                    hooks.append(h)

                try:
                    with torch.no_grad():
                        self.model(input_ids)
                finally:
                    for h in hooks:
                        h.remove()

                for l in layers:
                    if l in captured:
                        all_acts[l].append(captured[l])

            return {l: torch.stack(acts) for l, acts in all_acts.items() if acts}

        pos_acts = collect_mlp_output(positive_prompts)
        neg_acts = collect_mlp_output(negative_prompts)

        control_vectors = {}
        for l in layers:
            if l in pos_acts and l in neg_acts:
                cv = pos_acts[l].mean(dim=0) - neg_acts[l].mean(dim=0)
                control_vectors[l] = cv

        return control_vectors

    def compute_activation_weighted_cv(
        self,
        positive_prompts: List[str],
        negative_prompts: List[str],
        layer_idx: Optional[int] = None,
        seed_response: str = "",
        use_chat_template: bool = True,
    ) -> Dict[int, Dict[int, float]]:
        """Compute per-neuron control contributions weighted by actual activations.

        Instead of projecting a residual-level CV onto W_down columns (which
        loses information about which neurons actually fired), this directly
        captures the intermediate MLP activations (post gate*up, pre down_proj)
        and computes per-neuron behavioral differences.

        neuron_contribution[i] = mean(act_pos[i]) - mean(act_neg[i])

        Returns:
            Dict[layer_idx, Dict[neuron_idx, activation_difference]]
        """
        layers = [layer_idx] if layer_idx is not None else list(range(len(self._layers_ref)))

        def collect_intermediate(prompts):
            all_acts = {l: [] for l in layers}
            for prompt in prompts:
                if use_chat_template:
                    formatted = self._format_prompt(prompt, seed_response)
                else:
                    formatted = prompt + seed_response
                input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)

                captured = {}
                hooks = []
                for l in layers:
                    def make_hook(layer_idx):
                        def hook_fn(module, input, output):
                            # down_proj input = gate * up (the intermediate activation)
                            # input to down_proj is a tuple, first element is the tensor
                            inp = input[0] if isinstance(input, tuple) else input
                            captured[layer_idx] = inp[0, -1].detach().clone()
                        return hook_fn
                    h = self._layers_ref[l].mlp.down_proj.register_forward_hook(make_hook(l))
                    hooks.append(h)

                try:
                    with torch.no_grad():
                        self.model(input_ids)
                finally:
                    for h in hooks:
                        h.remove()

                for l in layers:
                    if l in captured:
                        all_acts[l].append(captured[l])

            return {l: torch.stack(acts) for l, acts in all_acts.items() if acts}

        pos_acts = collect_intermediate(positive_prompts)
        neg_acts = collect_intermediate(negative_prompts)

        per_layer_neurons = {}
        for l in layers:
            if l in pos_acts and l in neg_acts:
                diff = pos_acts[l].mean(dim=0) - neg_acts[l].mean(dim=0)  # [d_mlp]
                result = {}
                for i in range(diff.shape[0]):
                    v = diff[i].item()
                    if abs(v) > 1e-8:
                        result[i] = v
                per_layer_neurons[l] = dict(sorted(result.items(), key=lambda x: abs(x[1]), reverse=True))

        return per_layer_neurons

    def decompose_cv_to_neurons(
        self,
        control_vector: torch.Tensor,
        layer_idx: int,
    ) -> Dict[int, float]:
        """Decompose a control vector into per-neuron contributions.

        Projects the control vector onto each neuron's output column in W_down.
        CV contribution of neuron i = dot(CV, W_down[:, i]) / ||W_down[:, i]||

        Args:
            control_vector: [d_model] control vector at this layer
            layer_idx: Which layer's MLP to decompose against

        Returns:
            Dict[neuron_idx, projection_weight] sorted by |weight|
        """
        W_down = self._layers_ref[layer_idx].mlp.down_proj.weight  # [d_model, d_mlp]

        # Each column of W_down is a neuron's output direction
        # Project CV onto each column
        cv = control_vector.float()
        W = W_down.float()

        # projections[i] = dot(cv, W[:, i]) = how much neuron i contributes to CV direction
        projections = torch.matmul(cv, W)  # [d_mlp]

        # Normalize by column norms for interpretability
        col_norms = torch.norm(W, dim=0)  # [d_mlp]
        normalized = projections / (col_norms + 1e-8)

        result = {}
        for i in range(projections.shape[0]):
            if abs(normalized[i].item()) > 1e-6:
                result[i] = normalized[i].item()

        return dict(sorted(result.items(), key=lambda x: abs(x[1]), reverse=True))

    def compare_circuit_to_cv(
        self,
        circuit: Circuit,
        control_vectors: Dict[int, torch.Tensor],
        top_k: int = 50,
        verbose: bool = True,
    ) -> Dict[str, float]:
        """Compare CNA neuron circuit to CAA control vector decomposition.

        For each layer, compute how much of the control vector's variance
        is explained by the circuit neurons.

        Args:
            circuit: Neuron circuit from discover_circuit
            control_vectors: From compute_control_vector
            top_k: Number of top CV neurons to compare
            verbose: Print comparison

        Returns:
            Dict with overlap metrics
        """
        circuit_by_layer = circuit.unique_neurons()
        total_overlap = 0
        total_cv_neurons = 0
        total_variance_explained = 0.0
        n_layers = 0

        for layer_idx, cv in control_vectors.items():
            cv_decomp = self.decompose_cv_to_neurons(cv, layer_idx)
            top_cv = list(cv_decomp.keys())[:top_k]
            circuit_neurons = circuit_by_layer.get(layer_idx, set())

            overlap = len(set(top_cv) & circuit_neurons)
            total_overlap += overlap
            total_cv_neurons += min(top_k, len(cv_decomp))

            # Variance explained: sum of squared projections for circuit neurons
            all_proj_sq = sum(v ** 2 for v in cv_decomp.values())
            circuit_proj_sq = sum(cv_decomp.get(n, 0) ** 2 for n in circuit_neurons)
            var_expl = circuit_proj_sq / (all_proj_sq + 1e-8) if all_proj_sq > 1e-8 else 0

            if verbose and circuit_neurons:
                print(f"  L{layer_idx:2d}: {len(circuit_neurons)} circuit neurons, "
                      f"{overlap}/{min(top_k, len(cv_decomp))} overlap with top-{top_k} CV, "
                      f"variance_explained={var_expl:.4f}")

            total_variance_explained += var_expl
            n_layers += 1

        # Rank correlation: do circuit attribution ranks match CV decomposition ranks?
        # Flatten both to neuron lists
        circuit_ranked = [(n.layer, n.neuron, abs(a)) for n, a in circuit.top(200)]
        cv_ranked = []
        for l, cv in control_vectors.items():
            decomp = self.decompose_cv_to_neurons(cv, l)
            for neuron, weight in list(decomp.items())[:top_k]:
                cv_ranked.append((l, neuron, abs(weight)))
        cv_ranked.sort(key=lambda x: x[2], reverse=True)

        # Compute overlap at top-50
        circuit_set = {(l, n) for l, n, _ in circuit_ranked[:50]}
        cv_set = {(l, n) for l, n, _ in cv_ranked[:50]}
        top50_overlap = len(circuit_set & cv_set)

        metrics = {
            "total_overlap": total_overlap,
            "total_cv_neurons_checked": total_cv_neurons,
            "mean_variance_explained": total_variance_explained / max(n_layers, 1),
            "top50_overlap": top50_overlap,
        }

        if verbose:
            print(f"\n  Total overlap: {total_overlap}/{total_cv_neurons}")
            print(f"  Mean variance explained: {metrics['mean_variance_explained']:.4f}")
            print(f"  Top-50 neuron overlap (circuit vs CV): {top50_overlap}/50")

        return metrics

    def steer_and_generate(
        self,
        prompt: str,
        circuit: Circuit,
        multiplier: float = 0.0,
        max_new_tokens: int = 50,
        all_positions: bool = True,
        use_chat_template: bool = True,
    ) -> str:
        """Generate text with neuron steering applied.

        multiplier=0.0 → ablate circuit neurons (suppress behavior)
        multiplier=1.0 → no change (baseline)
        multiplier=2.0 → amplify circuit neurons (enhance behavior)
        """
        if use_chat_template:
            formatted = self._format_prompt(prompt)
        else:
            formatted = prompt
        input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)

        with steer_neurons(self.model, circuit.neurons, multiplier, all_positions):
            with torch.no_grad():
                outputs = self.model.generate(
                    input_ids,
                    max_new_tokens=max_new_tokens,
                    do_sample=False,
                    pad_token_id=self.tokenizer.pad_token_id,
                )

        return self.tokenizer.decode(outputs[0][input_ids.shape[1]:], skip_special_tokens=True)

    def generate(self, prompt: str, max_new_tokens: int = 50, use_chat_template: bool = True) -> str:
        """Normal generation without steering."""
        if use_chat_template:
            formatted = self._format_prompt(prompt)
        else:
            formatted = prompt
        input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)
        with torch.no_grad():
            outputs = self.model.generate(
                input_ids,
                max_new_tokens=max_new_tokens,
                do_sample=False,
                pad_token_id=self.tokenizer.pad_token_id,
            )
        return self.tokenizer.decode(outputs[0][input_ids.shape[1]:], skip_special_tokens=True)

    def next_token_probs(
        self,
        prompt: str,
        tokens: List[str],
        circuit: Optional[Circuit] = None,
        multiplier: float = 1.0,
        seed_response: str = "",
        use_chat_template: bool = True,
    ) -> Dict[str, float]:
        """Get next-token probabilities for specific tokens.

        Useful for measuring steering effects on specific outputs.
        """
        if use_chat_template:
            formatted = self._format_prompt(prompt, seed_response)
        else:
            formatted = prompt + seed_response
        input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)

        ctx = steer_neurons(self.model, circuit.neurons, multiplier) if circuit else nullcontext()
        with ctx:
            with torch.no_grad():
                outputs = self.model(input_ids)
                logits = outputs.logits[0, -1]
                probs = F.softmax(logits, dim=-1)

        result = {}
        for token in tokens:
            tid = self.tokenizer.encode(token, add_special_tokens=False)[-1]
            result[token] = probs[tid].item()
        return result

    def compute_mean_activations(
        self,
        prompts: Optional[List[str]] = None,
        seed_response: str = "",
        use_chat_template: bool = True,
    ) -> Dict[int, torch.Tensor]:
        """Compute mean MLP neuron activations across prompts.

        Args:
            prompts: List of prompts to compute mean from. If None, uses
                     20 diverse prompts (less accurate but works as fallback).
            seed_response: Seed response to append (for chat template).
            use_chat_template: Whether to use chat template formatting.

        Returns:
            Dict mapping layer_idx -> mean activation tensor (intermediate_size,)
        """
        if prompts is None:
            prompts = [
                "The capital of France is",
                "Once upon a time there was a",
                "The best programming language is",
                "In the year 2024, the world",
                "How do I bake a cake?",
                "What is photosynthesis?",
                "The CEO of Apple is",
                "My favorite color is",
                "The largest ocean on Earth is",
                "The speed of light is approximately",
                "In machine learning, a neural network",
                "The president of the United States",
                "Water freezes at a temperature of",
                "The meaning of life is",
                "To solve this math problem,",
                "The Great Wall of China was",
                "An electron has a charge of",
                "The chemical formula for water is",
                "Yesterday I went to the",
                "The key to the cabinets",
            ]
            use_chat_template = False  # raw prompts, no template

        # Accumulate activations across all prompts and ALL positions
        mean_acts: Dict[int, torch.Tensor] = {}
        total_tokens = 0

        for prompt in prompts:
            if use_chat_template:
                formatted = self._format_prompt(prompt, seed_response)
            else:
                formatted = prompt + seed_response
            input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)
            seq_len = input_ids.shape[1]
            layer_acts = {}
            hooks = []
            for i, layer in enumerate(self._layers_ref):
                def make_hook(layer_idx):
                    def hook_fn(module, args):
                        # Capture ALL positions: args[0] shape (1, seq_len, intermediate_size)
                        # Sum over seq_len dimension for running average
                        layer_acts[layer_idx] = args[0][0].detach().sum(dim=0)  # (intermediate_size,)
                    return hook_fn
                h = layer.mlp.down_proj.register_forward_pre_hook(make_hook(i))
                hooks.append(h)

            try:
                with torch.no_grad():
                    self.model(input_ids)
            finally:
                for h in hooks:
                    h.remove()

            for layer_idx, act_sum in layer_acts.items():
                if layer_idx not in mean_acts:
                    mean_acts[layer_idx] = act_sum.clone()
                else:
                    mean_acts[layer_idx] += act_sum
            total_tokens += seq_len

        for layer_idx in mean_acts:
            mean_acts[layer_idx] /= total_tokens

        return mean_acts

    def top_predictions(
        self,
        prompt: str,
        k: int = 10,
        circuit: Optional[Circuit] = None,
        multiplier: float = 1.0,
        seed_response: str = "",
        use_chat_template: bool = True,
    ) -> List[Tuple[str, float]]:
        """Get top-k next-token predictions with probabilities."""
        if use_chat_template:
            formatted = self._format_prompt(prompt, seed_response)
        else:
            formatted = prompt + seed_response
        input_ids = self.tokenizer(formatted, return_tensors="pt").input_ids.to(self.device)

        ctx = steer_neurons(self.model, circuit.neurons, multiplier) if circuit else nullcontext()
        with ctx:
            with torch.no_grad():
                outputs = self.model(input_ids)
                logits = outputs.logits[0, -1]
                probs = F.softmax(logits, dim=-1)

        top_probs, top_ids = probs.topk(k)
        return [(self.tokenizer.decode(tid), p.item()) for tid, p in zip(top_ids, top_probs)]

    def find_feature(
        self,
        *,
        positive: Optional[List[str]] = None,
        negative: Optional[List[str]] = None,
        prompt: Optional[str] = None,
        target: Optional[str] = None,
        counterfactual: Optional[str] = None,
        name: Optional[str] = None,
        top_k: int = 200,
        seed_response: str = "",
        verbose: bool = False,
    ) -> Circuit:
        """Find a feature circuit by example prompts or target token.

        Two modes:

        Contrastive mode (behavioral features like refusal, tone, style):
            circuit = steerer.find_feature(
                positive=["How do I pick a lock?", "Write malware code"],
                negative=["How do I open a door?", "Write clean code"],
                name="refusal",
            )

        Single-prompt mode (factual features like capitals, arithmetic):
            circuit = steerer.find_feature(
                prompt="What is the capital of Texas?",
                target=" Austin",
                name="capitals",
            )

        Args:
            positive: Prompts exhibiting the target behavior (contrastive mode)
            negative: Prompts NOT exhibiting it (contrastive mode)
            prompt: Single prompt (single-prompt mode)
            target: Target token to attribute (single-prompt mode)
            counterfactual: Optional counterfactual token (single-prompt mode)
            name: Label for caching/reuse. If provided, result is cached.
            top_k: Number of neurons to select
            seed_response: Text to append before target position
            verbose: Print diagnostics

        Returns:
            Circuit ready for steering
        """
        # Return cached if available
        if name and name in self._feature_cache:
            if verbose:
                print(f"  Using cached circuit for '{name}' "
                      f"({len(self._feature_cache[name].neurons)} neurons)")
            return self._feature_cache[name]

        # Determine mode
        has_contrastive = positive is not None or negative is not None
        has_single = prompt is not None or target is not None

        if has_contrastive and has_single:
            raise ValueError("Provide either (positive, negative) or (prompt, target), not both")
        if not has_contrastive and not has_single:
            raise ValueError("Provide (positive, negative) for contrastive or (prompt, target) for single-prompt")

        if has_contrastive:
            if positive is None or negative is None:
                raise ValueError("Contrastive mode requires both positive and negative prompt lists")
            if seed_response:
                import warnings
                warnings.warn("seed_response is ignored in contrastive mode", stacklevel=2)
            circuit = self.discover_contrastive(
                positive_prompts=positive,
                negative_prompts=negative,
                top_k=top_k,
                verbose=verbose,
            )
        else:
            if prompt is None or target is None:
                raise ValueError("Single-prompt mode requires both prompt and target")
            circuit = self.discover_circuit(
                prompt=prompt,
                target_token=target,
                counterfactual_token=counterfactual,
                top_k=top_k,
                seed_response=seed_response,
                verbose=verbose,
            )

        if name:
            self._feature_cache[name] = circuit
            if verbose:
                print(f"  Cached circuit as '{name}' ({len(circuit.neurons)} neurons)")

        return circuit

    def steer(
        self,
        prompt: str,
        *,
        feature: Optional[str] = None,
        circuit: Optional[Circuit] = None,
        multiplier: float = 0.0,
        max_new_tokens: int = 50,
        all_positions: bool = True,
        use_chat_template: bool = True,
    ) -> str:
        """Generate text with a named feature or circuit applied.

        Convenience wrapper around steer_and_generate that uses cached features.

        Examples:
            # Using a previously discovered feature by name
            steerer.find_feature(prompt="Capital of Texas?", target=" Austin", name="capitals")
            output = steerer.steer("Capital of Ohio?", feature="capitals", multiplier=0.0)

            # Using a circuit directly
            output = steerer.steer("Capital of Ohio?", circuit=my_circuit, multiplier=2.0)

        Args:
            prompt: The prompt to generate from
            feature: Name of a cached feature (from find_feature with name=)
            circuit: Circuit object to use directly (alternative to feature name)
            multiplier: 0.0=ablate, 1.0=baseline, 2.0=amplify
            max_new_tokens: Max tokens to generate
            all_positions: Apply steering at all positions (not just circuit positions)
            use_chat_template: Format prompt for instruct models

        Returns:
            Generated text with steering applied
        """
        if feature is not None and circuit is not None:
            raise ValueError("Provide either feature name or circuit, not both")
        if feature is None and circuit is None:
            raise ValueError("Provide either feature (name string) or circuit (Circuit object)")

        if feature is not None:
            if feature not in self._feature_cache:
                available = list(self._feature_cache.keys())
                raise KeyError(
                    f"Feature '{feature}' not found. "
                    f"Available: {available}. Use find_feature() first."
                )
            circuit = self._feature_cache[feature]

        return self.steer_and_generate(
            prompt=prompt,
            circuit=circuit,
            multiplier=multiplier,
            max_new_tokens=max_new_tokens,
            all_positions=all_positions,
            use_chat_template=use_chat_template,
        )

    # ============================================================
    # Interactive REPL
    # ============================================================

    def interactive(self):
        """Launch interactive REPL for live neuron circuit exploration.

        Commands:
            prompt <text>           — Run a prompt, show output
            discover [target]       — Find circuit (auto-detects target if omitted)
            ablate [spec]           — Ablate neurons (L23/N8079, top10, all)
            amplify [spec] [mult]   — Amplify neurons (default 2.0x)
            sweep [m1 m2 ...]       — Multiplier sweep
            top [k]                 — Top-k next-token predictions
            save <name>             — Save circuit to file
            load [name]             — Load circuit (no arg = list available)
            multiplier [value]      — Get/set steering multiplier for 'top'
            info                    — Show current state
            quit / exit             — Exit REPL
        """
        import cmd
        import os
        import re

        steerer = self

        class NeuronREPL(cmd.Cmd):
            intro = (
                "\n"
                "===== Neuron Steering REPL =====\n"
                f"Model: {steerer.model_name}\n"
                f"Blacklist: {len(steerer.blacklist)} universal neurons\n"
                "Type 'help' for commands, 'quit' to exit.\n"
            )
            prompt = "neuron> "

            def __init__(self):
                super().__init__()
                self._prompt = None
                self._prompt_is_formatted = False  # True if prompt already has chat template
                self._circuit = None
                self._graph = None
                self._multiplier = 1.0
                self._saved = {}
                self._last_output = None

            # ---- prompt ----
            def do_prompt(self, arg):
                """prompt <text> — Run a prompt through the model and show output."""
                if not arg.strip():
                    if self._prompt:
                        print(f"Current prompt: {self._prompt}")
                    else:
                        print("Usage: prompt <text>")
                    return
                self._prompt = arg.strip()
                self._prompt_is_formatted = False
                self._circuit = None
                self._graph = None
                try:
                    uct = not self._prompt_is_formatted
                    self._last_output = steerer.generate(
                        self._prompt, max_new_tokens=100, use_chat_template=uct)
                    print(f"\nOutput: {self._last_output}")
                except Exception as e:
                    print(f"Error: {e}")

            # ---- discover ----
            def do_discover(self, arg):
                """discover [target_token] — Discover circuit for current prompt."""
                if not self._prompt:
                    print("Set a prompt first: prompt <text>")
                    return
                target = arg.strip() if arg.strip() else None
                uct = not self._prompt_is_formatted
                try:
                    if target is None:
                        preds = steerer.top_predictions(self._prompt, k=1,
                                                         use_chat_template=uct)
                        if preds:
                            target = preds[0][0]
                            print(f"Auto-target: '{target}' (p={preds[0][1]:.4f})")
                        else:
                            print("Could not auto-detect target. Provide one: discover <token>")
                            return
                    self._circuit = steerer.discover_circuit(
                        self._prompt, target,
                        top_k=200, filter_bos=True, verbose=False,
                        use_chat_template=uct,
                    )
                    self._graph = None
                    print(f"\n{self._circuit.summary()}")
                    print(f"\nTop 10 neurons:")
                    for nidx, attr in self._circuit.top(10):
                        print(f"  L{nidx.layer:2d}/N{nidx.neuron:5d} (pos {nidx.position:2d})  attr={attr:+.6f}")
                except Exception as e:
                    print(f"Error: {e}")

            # ---- ablate ----
            def do_ablate(self, arg):
                """ablate [L<layer>/N<neuron> | top<N> | all] — Ablate neurons and regenerate."""
                if not self._prompt:
                    print("Set a prompt first.")
                    return
                if not self._circuit:
                    print("Discover a circuit first.")
                    return
                try:
                    circuit = self._select_neurons(arg.strip(), "ablate")
                    if circuit is None:
                        return
                    uct = not self._prompt_is_formatted
                    output = steerer.steer_and_generate(
                        self._prompt, circuit, multiplier=0.0, max_new_tokens=100,
                        use_chat_template=uct,
                    )
                    print(f"\nAblated output (x0.0): {output}")
                except Exception as e:
                    print(f"Error: {e}")

            # ---- amplify ----
            def do_amplify(self, arg):
                """amplify [L<layer>/N<neuron> | top<N> | all] [multiplier] — Amplify neurons."""
                if not self._prompt:
                    print("Set a prompt first.")
                    return
                if not self._circuit:
                    print("Discover a circuit first.")
                    return
                try:
                    parts = arg.strip().split()
                    multiplier = 2.0
                    neuron_spec = ""
                    # First non-float arg is neuron spec, last float is multiplier
                    non_floats = []
                    for p in parts:
                        try:
                            multiplier = float(p)
                        except ValueError:
                            non_floats.append(p)
                    if len(non_floats) > 1:
                        print(f"Warning: using last spec '{non_floats[-1]}', ignoring {non_floats[:-1]}")
                    neuron_spec = non_floats[-1] if non_floats else ""
                    circuit = self._select_neurons(neuron_spec, "amplify")
                    if circuit is None:
                        return
                    uct = not self._prompt_is_formatted
                    output = steerer.steer_and_generate(
                        self._prompt, circuit, multiplier=multiplier, max_new_tokens=100,
                        use_chat_template=uct,
                    )
                    print(f"\nAmplified output (x{multiplier}): {output}")
                except Exception as e:
                    print(f"Error: {e}")

            # ---- sweep ----
            def do_sweep(self, arg):
                """sweep [m1 m2 ...] — Multiplier sweep over current circuit."""
                if not self._prompt:
                    print("Set a prompt first.")
                    return
                if not self._circuit:
                    print("Discover a circuit first.")
                    return
                parts = arg.strip().split()
                if not parts:
                    parts = ["0.0", "0.5", "1.0", "1.5", "2.0"]
                try:
                    multipliers = [float(m) for m in parts]
                except ValueError:
                    print("Usage: sweep <m1> <m2> ... (e.g., sweep 0.0 0.5 1.0 2.0)")
                    return
                try:
                    uct = not self._prompt_is_formatted
                    for m in multipliers:
                        output = steerer.steer_and_generate(
                            self._prompt, self._circuit,
                            multiplier=m, max_new_tokens=100,
                            use_chat_template=uct,
                        )
                        print(f"  x{m}: {output}")
                except Exception as e:
                    print(f"Error: {e}")

            # ---- top ----
            def do_top(self, arg):
                """top [k] — Show top-k next-token predictions."""
                k = 10
                if arg.strip():
                    try:
                        k = int(arg.strip())
                    except ValueError:
                        print("Usage: top [k]")
                        return
                if not self._prompt:
                    print("Set a prompt first.")
                    return
                uct = not self._prompt_is_formatted
                try:
                    preds = steerer.top_predictions(
                        self._prompt, k=k,
                        circuit=self._circuit,
                        multiplier=self._multiplier,
                        use_chat_template=uct,
                    )
                    print(f"\nTop-{k} predictions (multiplier={self._multiplier}):")
                    for tok, prob in preds:
                        bar = "#" * int(prob * 50)
                        print(f"  {prob:.4f} {bar} '{tok}'")
                except Exception as e:
                    print(f"Error: {e}")

            # ---- save / load ----
            def do_save(self, arg):
                """save <name> — Save current circuit to file."""
                name = arg.strip()
                if not name:
                    print("Usage: save <name>")
                    return
                if not self._circuit:
                    print("No circuit to save. Run discover first.")
                    return
                try:
                    circuits_dir = os.path.join(
                        os.path.dirname(os.path.abspath(__file__)), "circuits"
                    )
                    os.makedirs(circuits_dir, exist_ok=True)
                    path = os.path.join(circuits_dir, f"{name}.json")
                    self._circuit.save(path)
                    self._saved[name] = self._circuit
                    print(f"Saved to {path}")
                except Exception as e:
                    print(f"Error: {e}")

            def do_load(self, arg):
                """load [name] — Load a saved circuit (no arg lists available)."""
                name = arg.strip()
                circuits_dir = os.path.join(
                    os.path.dirname(os.path.abspath(__file__)), "circuits"
                )
                if not name:
                    if os.path.isdir(circuits_dir):
                        files = [f[:-5] for f in os.listdir(circuits_dir) if f.endswith(".json")]
                        if files:
                            print(f"Available: {', '.join(sorted(files))}")
                        else:
                            print("No saved circuits.")
                    else:
                        print("No saved circuits.")
                    return
                try:
                    path = os.path.join(circuits_dir, f"{name}.json")
                    self._circuit = Circuit.load(path)
                    self._graph = None
                    self._prompt = self._circuit.prompt
                    self._prompt_is_formatted = True  # already has chat template
                    print(f"Loaded from {path}")
                    print(f"\n{self._circuit.summary()}")
                except FileNotFoundError:
                    print(f"'{name}' not found. Use 'load' to list available.")
                except Exception as e:
                    print(f"Error: {e}")

            # ---- multiplier ----
            def do_multiplier(self, arg):
                """multiplier [value] — Get/set the steering multiplier for 'top' command."""
                if not arg.strip():
                    print(f"Current multiplier: {self._multiplier}")
                    return
                try:
                    self._multiplier = float(arg.strip())
                    print(f"Multiplier set to {self._multiplier}")
                except ValueError:
                    print("Usage: multiplier <float>")

            # ---- info ----
            def do_info(self, arg):
                """info — Show current REPL state."""
                print(f"\nPrompt:     {self._prompt or '(none)'}")
                n = len(self._circuit.neurons) if self._circuit else 0
                print(f"Circuit:    {n} neurons")
                if self._circuit:
                    print(f"  Target:   {self._circuit.target_token}")
                    print(f"  LogitD:   {self._circuit.total_logit_diff:.4f}")
                print(f"Multiplier: {self._multiplier}")
                saved = ', '.join(self._saved.keys()) if self._saved else '(none)'
                print(f"Saved:      {saved}")

            # ---- quit / exit ----
            def do_quit(self, arg):
                """quit — Exit the REPL."""
                print("Bye!")
                return True

            def do_exit(self, arg):
                """exit — Exit the REPL."""
                return self.do_quit(arg)

            do_EOF = do_quit

            # ---- helpers ----
            def _select_neurons(self, spec, action):
                """Parse neuron spec: 'L23/N8079', 'top10', 'all', or '' (= all)."""
                if not spec or spec == "all":
                    return self._circuit
                if spec.startswith("top"):
                    try:
                        k = int(spec[3:])
                    except ValueError:
                        print(f"Usage: {action} top<N>")
                        return None
                    top_neurons = self._circuit.top(k)
                    return Circuit(
                        neurons=dict(top_neurons),
                        prompt=self._circuit.prompt,
                        target_token=self._circuit.target_token,
                        total_logit_diff=self._circuit.total_logit_diff,
                    )
                m = re.match(r"L(\d+)/N(\d+)", spec)
                if m:
                    layer, neuron = int(m.group(1)), int(m.group(2))
                    matched = {n: a for n, a in self._circuit.neurons.items()
                               if n.layer == layer and n.neuron == neuron}
                    if not matched:
                        print(f"Neuron L{layer}/N{neuron} not in current circuit.")
                        return None
                    return Circuit(
                        neurons=matched,
                        prompt=self._circuit.prompt,
                        target_token=self._circuit.target_token,
                        total_logit_diff=self._circuit.total_logit_diff,
                    )
                print(f"Unknown spec '{spec}'. Use: L<layer>/N<neuron>, top<N>, or all")
                return None

            def emptyline(self):
                pass

            def default(self, line):
                print(f"Unknown command: {line.split()[0]}. Type 'help' for commands.")

        repl = NeuronREPL()
        while True:
            try:
                repl.cmdloop()
                break  # normal exit via quit/exit/EOF
            except KeyboardInterrupt:
                print("\n(Ctrl+C — command cancelled. Type 'quit' to exit)")
                repl.intro = ""
                continue
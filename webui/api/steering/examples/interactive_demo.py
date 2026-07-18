"""Interactive neuron steering REPL.

Commands: prompt, discover, ablate, amplify, sweep, edges, top, save, load, info, quit
"""
import torch
from neuron_steer import NeuronSteerer

steerer = NeuronSteerer("meta-llama/Llama-3.1-8B-Instruct", dtype=torch.bfloat16)
steerer.interactive()

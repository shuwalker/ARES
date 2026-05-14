import os
import streamlit as st
from llama_cpp import Llama

@st.cache_resource
def get_llm(model_path: str, n_gpu_layers: int = -1):
    """Lazily loads and caches the model based on the selected path."""
    if not model_path or not os.path.exists(model_path):
        return None
    return Llama(
        model_path=model_path,
        n_ctx=4096,
        n_gpu_layers=n_gpu_layers,
        verbose=False
    )

def chat_with_lilith(system_prompt: str, history: list, user_input: str, model_path: str | None = None, n_gpu_layers: int = -1) -> str:
    """Invokes llama_cpp manually building the chat template."""
    llm = get_llm(model_path, n_gpu_layers)
    if llm is None:
        return "Connection error: No valid model selected or found. Please select an available model from the sidebar."
        
    def fmt_turn(role, content):
        return f"{role}\n{content}\n"
        
    prompt = fmt_turn("user", system_prompt)
    for h in history:
        # Map assistant to model
        role = "model" if h["role"] == "assistant" else h["role"]
        prompt += fmt_turn(role, h["content"])
        
    prompt += fmt_turn("user", user_input)
    prompt += "model\n"
    
    try:
        output = llm(
            prompt,
            max_tokens=1024,
            temperature=0.7,
            stop=["<|im_end|>", "user\n", "model\n"]
        )
        return output["choices"][0]["text"].strip()
    except Exception as e:
        return f"Inference error: {e}"

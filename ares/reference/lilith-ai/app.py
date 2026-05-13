import streamlit as st
import random
import os
import threading
import zmq
import json
import time

import sys

# Ensure the root of the project is in the python path so 'src' packages can be resolved without requiring 'pip install -e .'
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from lilith_ai.core.personality import CharacterProfile, save_profile, load_profile, generate_system_prompt
from lilith_ai.core.character_library import CharacterLibrary
from lilith_ai.core.character_generator import CharacterGenerator
from lilith_ai.core.memory import ConversationMemory
from lilith_ai.core.lm_studio_utils import get_lm_studio_models
from lilith_ai.ui.radar_chart import render_radar_chart
from lilith_ai.lilith_status import PipelineStatus
from lilith_ai.bus.ports import PortMap, get_address
from lilith_ai.core.inference import chat_with_lilith

from llama_cpp import Llama

def get_llm_response(prompt: str) -> str:
    """
    Calls the LLM for one-shot generation tasks (character generation).
    Uses the same llama-cpp-python logic.
    """
    model_path = st.session_state.get("selected_model_path")
    if not model_path:
        raise ValueError("Please select an Inference Engine model from the sidebar first.")
        
    st.session_state.llm_cache = getattr(st.session_state, "llm_cache", {})
    if model_path not in st.session_state.llm_cache:
        st.session_state.llm_cache[model_path] = Llama(
            model_path=model_path,
            n_ctx=4096,
            n_gpu_layers=-1,
            verbose=False
        )
        
    llm = st.session_state.llm_cache[model_path]
    output = llm(
        prompt,
        max_tokens=1500,
        temperature=0.7,
        stop=["<|im_end|>"]
    )
    return output["choices"][0]["text"].strip()

def start_pipeline_process(model_path, mode="full"):
    if not PipelineStatus.is_model_loaded(model_path):
        st.error(f"Could not start pipeline. GGUF model not found at models/.")
        return False
        
    if not st.session_state.voice_mode:
        config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pipeline_config.json")
        try:
             with open(config_path, "r") as f:
                 cfg = json.load(f)
             
             # Dynamic UX Routing
             if mode == "tts_only":
                  cfg["pipeline"]["input"] = "" # Skip Whisper STT entirely
                  st.session_state.active_voice_mode = "Speak Responses (TTS Only)"
             else:
                  # Restore input plugin if we are in full mode
                  cfg["pipeline"]["input"] = "whisper_stt"
                  st.session_state.active_voice_mode = "Full Voice Chat (STT + TTS)"
                  
             # Save the temporary config state for the pipeline subprocess to pick up
             with open(config_path, "w") as f:
                  json.dump(cfg, f, indent=2)
                  
        except Exception as e:
             st.error(f"Could not prepare pipeline config: {e}")
             return False
             
        import subprocess
        import sys
        
        proc = subprocess.Popen(
            [sys.executable, "-m", "lilith_ai.pipeline_" + "runner"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            cwd=os.getcwd()
        )
        st.session_state.pipeline_proc = proc
        st.session_state.voice_mode = True
        return True
    return False

def stop_pipeline_process():
    """Send SIGTERM to pipeline process."""
    proc = st.session_state.get("pipeline_proc")
    if proc and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            
    st.session_state.pipeline_proc = None
    st.session_state.voice_mode = False
    st.session_state.active_voice_mode = "OFFLINE"

def is_pipeline_running() -> bool:
    proc = st.session_state.get("pipeline_proc")
    return proc is not None and proc.poll() is None

def save_active_profile():
    """Callback to save the active profile whenever a slider changes."""
    st.session_state.character_library.set_active(st.session_state.active_profile)
    # Also save to its library file if it's an original/variant/clone so it's not lost
    st.session_state.character_library.save(st.session_state.active_profile)

def check_llm_response() -> str | None:
    sub = st.session_state.get("llm_sub")
    if not sub:
        return None
    # Non-blocking — return immediately if nothing waiting
    if sub.poll(timeout=0):
        try:
            msg = sub.recv_json(zmq.NOBLOCK)
            return msg.get("text", "")
        except zmq.ZMQError:
            return None
    return None

def main():
    st.set_page_config(page_title="Lilith AI", layout="wide", page_icon="⚡")

    # Initialize State
    if "memory" not in st.session_state:
        st.session_state.memory = ConversationMemory()
        
    if "zmq_context" not in st.session_state:
        st.session_state.zmq_context = zmq.Context()
        
        st.session_state.bus_push = st.session_state.zmq_context.socket(zmq.PUSH)
        st.session_state.bus_push.connect(get_address(PortMap.STT_TEXT))
        
        st.session_state.llm_sub = st.session_state.zmq_context.socket(zmq.SUB)
        st.session_state.llm_sub.connect(get_address(PortMap.LLM_RESPONSE))
        st.session_state.llm_sub.setsockopt(zmq.SUBSCRIBE, b"")
        st.session_state.llm_sub.setsockopt(zmq.RCVTIMEO, 50)
        
        st.session_state.log_sub = st.session_state.zmq_context.socket(zmq.SUB)
        st.session_state.log_sub.connect(get_address(PortMap.PIPELINE_LOG))
        st.session_state.log_sub.setsockopt(zmq.SUBSCRIBE, b"")
        st.session_state.log_sub.setsockopt(zmq.RCVTIMEO, 50)

    # Character System State
    if "character_library" not in st.session_state:
        st.session_state.character_library = CharacterLibrary()
        
    if "active_profile" not in st.session_state:
        try:
            st.session_state.active_profile = st.session_state.character_library.get_active()
        except FileNotFoundError:
            st.session_state.active_profile = CharacterProfile()
            
    if "generator_preview" not in st.session_state:
        st.session_state.generator_preview = None

    if "character_search" not in st.session_state:
        st.session_state.character_search = ""

    if "voice_mode" not in st.session_state:
        st.session_state.voice_mode = False


    # --- SIDEBAR ---
    with st.sidebar:
        # Header dynamically reflecting active profile
        p_meta = st.session_state.active_profile.meta
        cat_colors = {"original": "orange", "clone": "blue", "variant": "violet"}
        cat_col = cat_colors.get(p_meta.category, "gray")
        
        st.markdown(f"## ⚡ {p_meta.name} <span style='color:{cat_col}; font-size:12px; vertical-align:middle; border:1px solid {cat_col}; padding:2px 6px; border-radius:10px;'>{p_meta.category.upper()}</span>", unsafe_allow_html=True)
        
        # Tabs for the Studio UI
        tab_studio, tab_library, tab_generate = st.tabs(["🧬 Studio", "📚 Library", "⚡ Generate"])
        
        # ==================== TAB 1: STUDIO ====================
        with tab_studio:
            st.markdown("Edit personality layers directly in VRAM latency.")
            
            # --- HEXACO Expander ---
            with st.expander("🧬 HEXACO — Core Identity"):
                hex_dict = {
                    "Openness": st.session_state.active_profile.hexaco.openness,
                    "Conscientious": st.session_state.active_profile.hexaco.conscientiousness,
                    "Extraversion": st.session_state.active_profile.hexaco.extraversion,
                    "Agreeable": st.session_state.active_profile.hexaco.agreeableness,
                    "Neuroticism": st.session_state.active_profile.hexaco.neuroticism,
                    "Honesty": st.session_state.active_profile.hexaco.honesty_humility
                }
                st.pyplot(render_radar_chart(hex_dict, color='#3b82f6', bg_color='#0f172a'))
                
                def hex_cb(): save_active_profile()
                h = st.session_state.active_profile.hexaco
                h.openness = st.slider(f"Openness [{h.openness:.2f}]", 0.0, 1.0, h.openness, 0.05, help="Curiosity & imagination", on_change=hex_cb)
                h.conscientiousness = st.slider(f"Conscientiousness [{h.conscientiousness:.2f}]", 0.0, 1.0, h.conscientiousness, 0.05, help="Discipline & organization", on_change=hex_cb)
                h.extraversion = st.slider(f"Extraversion [{h.extraversion:.2f}]", 0.0, 1.0, h.extraversion, 0.05, help="Social energy & assertiveness", on_change=hex_cb)
                h.agreeableness = st.slider(f"Agreeableness [{h.agreeableness:.2f}]", 0.0, 1.0, h.agreeableness, 0.05, help="Cooperation & trust", on_change=hex_cb)
                h.neuroticism = st.slider(f"Neuroticism [{h.neuroticism:.2f}]", 0.0, 1.0, h.neuroticism, 0.05, help="Emotional volatility", on_change=hex_cb)
                h.honesty_humility = st.slider(f"Honesty-Humility [{h.honesty_humility:.2f}]", 0.0, 1.0, h.honesty_humility, 0.05, help="Sincerity & fairness", on_change=hex_cb)
                
            # --- SPECIAL Expander ---
            with st.expander("⚡ S.P.E.C.I.A.L. — Capabilities"):
                spec_dict = {
                    "Strength": st.session_state.active_profile.special.strength,
                    "Perception": st.session_state.active_profile.special.perception,
                    "Endurance": st.session_state.active_profile.special.endurance,
                    "Charisma": st.session_state.active_profile.special.charisma,
                    "Intelligence": st.session_state.active_profile.special.intelligence,
                    "Agility": st.session_state.active_profile.special.agility,
                    "Luck": st.session_state.active_profile.special.luck
                }
                st.pyplot(render_radar_chart(spec_dict, color='#f59e0b', bg_color='#1c1008'))
                
                def spec_cb(): save_active_profile()
                s = st.session_state.active_profile.special
                s.strength = st.slider(f"Strength [{s.strength:.2f}]", 0.0, 1.0, s.strength, 0.05, help="Forcefulness & conviction", on_change=spec_cb)
                s.perception = st.slider(f"Perception [{s.perception:.2f}]", 0.0, 1.0, s.perception, 0.05, help="Awareness & detail", on_change=spec_cb)
                s.endurance = st.slider(f"Endurance [{s.endurance:.2f}]", 0.0, 1.0, s.endurance, 0.05, help="Patience & persistence", on_change=spec_cb)
                s.charisma = st.slider(f"Charisma [{s.charisma:.2f}]", 0.0, 1.0, s.charisma, 0.05, help="Magnetism & persuasion", on_change=spec_cb)
                s.intelligence = st.slider(f"Intelligence [{s.intelligence:.2f}]", 0.0, 1.0, s.intelligence, 0.05, help="Reasoning & knowledge", on_change=spec_cb)
                s.agility = st.slider(f"Agility [{s.agility:.2f}]", 0.0, 1.0, s.agility, 0.05, help="Adaptability & quick thinking", on_change=spec_cb)
                s.luck = st.slider(f"Luck [{s.luck:.2f}]", 0.0, 1.0, s.luck, 0.05, help="Optimism & positive framing", on_change=spec_cb)
                
            # --- EXPRESSION Expander ---
            with st.expander("🎭 Expression — Comm. Style"):
                exp_dict = {
                    "Sarcasm": st.session_state.active_profile.expression.sarcasm,
                    "Warmth": st.session_state.active_profile.expression.warmth,
                    "Verbosity": st.session_state.active_profile.expression.verbosity,
                    "Formality": st.session_state.active_profile.expression.formality,
                    "Directness": st.session_state.active_profile.expression.directness,
                    "Humor": st.session_state.active_profile.expression.humor,
                    "Empathy": st.session_state.active_profile.expression.empathy,
                    "Aggression": st.session_state.active_profile.expression.aggression
                }
                st.pyplot(render_radar_chart(exp_dict, color='#2dd4bf', bg_color='#071a18'))
                
                def exp_cb(): save_active_profile()
                e = st.session_state.active_profile.expression
                e.sarcasm = st.slider(f"Sarcasm [{e.sarcasm:.2f}]", 0.0, 1.0, e.sarcasm, 0.05, help="Irony & wit", on_change=exp_cb)
                e.warmth = st.slider(f"Warmth [{e.warmth:.2f}]", 0.0, 1.0, e.warmth, 0.05, help="Friendliness", on_change=exp_cb)
                e.verbosity = st.slider(f"Verbosity [{e.verbosity:.2f}]", 0.0, 1.0, e.verbosity, 0.05, help="Response length", on_change=exp_cb)
                e.formality = st.slider(f"Formality [{e.formality:.2f}]", 0.0, 1.0, e.formality, 0.05, help="Register", on_change=exp_cb)
                e.directness = st.slider(f"Directness [{e.directness:.2f}]", 0.0, 1.0, e.directness, 0.05, help="Bluntness", on_change=exp_cb)
                e.humor = st.slider(f"Humor [{e.humor:.2f}]", 0.0, 1.0, e.humor, 0.05, help="Playfulness", on_change=exp_cb)
                e.empathy = st.slider(f"Empathy [{e.empathy:.2f}]", 0.0, 1.0, e.empathy, 0.05, help="Emotional mirroring", on_change=exp_cb)
                e.aggression = st.slider(f"Aggression [{e.aggression:.2f}]", 0.0, 1.0, e.aggression, 0.05, help="Confrontation", on_change=exp_cb)
                
            # --- DOMAINS ---
            st.markdown("### 🧠 Knowledge Domains")
            d = st.session_state.active_profile.domains
            dcol1, dcol2 = st.columns(2)
            with dcol1: 
                d.science = st.slider("Science", 0.0, 1.0, d.science, 0.1, label_visibility="collapsed", on_change=save_active_profile); st.caption("Science")
                d.combat = st.slider("Combat", 0.0, 1.0, d.combat, 0.1, label_visibility="collapsed", on_change=save_active_profile); st.caption("Combat")
                d.politics = st.slider("Politics", 0.0, 1.0, d.politics, 0.1, label_visibility="collapsed", on_change=save_active_profile); st.caption("Politics")
                d.nature = st.slider("Nature", 0.0, 1.0, d.nature, 0.1, label_visibility="collapsed", on_change=save_active_profile); st.caption("Nature")
            with dcol2:
                d.philosophy = st.slider("Philosophy", 0.0, 1.0, d.philosophy, 0.1, label_visibility="collapsed", on_change=save_active_profile); st.caption("Philosophy")
                d.art = st.slider("Art", 0.0, 1.0, d.art, 0.1, label_visibility="collapsed", on_change=save_active_profile); st.caption("Art")
                d.technology = st.slider("Technology", 0.0, 1.0, d.technology, 0.1, label_visibility="collapsed", on_change=save_active_profile); st.caption("Technology")
                d.psychology = st.slider("Psychology", 0.0, 1.0, d.psychology, 0.1, label_visibility="collapsed", on_change=save_active_profile); st.caption("Psychology")
                
            # --- MOOD ---
            st.markdown("### 🌡 Mood")
            mood = st.session_state.active_profile.mood
            st.write(f"Current: **{mood.current_emotion}**")
            st.progress(mood.intensity, text=f"Intensity: {mood.intensity:.0%}")
            if st.button("Reset Mood"):
                st.session_state.active_profile.mood.current_emotion = "neutral"
                st.session_state.active_profile.mood.intensity = 0.0
                st.rerun()

            # --- INSTRUCTIONS ---
            custom_inst = st.text_area(
                "✍ Character Override Instructions", 
                value=st.session_state.active_profile.meta.custom_instructions,
                placeholder="Force specific behaviors here. These override all trait settings.",
                height=100
            )

            speech_pats = st.text_area(
                "💬 Speech Patterns (one per line)",
                value="\n".join(st.session_state.active_profile.meta.speech_patterns),
                height=80
            )

            # Detect changes on text areas
            if custom_inst != st.session_state.active_profile.meta.custom_instructions or speech_pats != "\n".join(st.session_state.active_profile.meta.speech_patterns):
                st.session_state.active_profile.meta.custom_instructions = custom_inst
                st.session_state.active_profile.meta.speech_patterns = [p.strip() for p in speech_pats.split("\n") if p.strip()]
                save_active_profile()

            if st.button("💾 Save Character Data", use_container_width=True):
                save_active_profile()
                st.success("Saved to active.json & library!")
                
        # ==================== TAB 2: LIBRARY ====================
        with tab_library:
            search_query = st.text_input("Search characters...", value=st.session_state.character_search)
            st.session_state.character_search = search_query
            
            cat_filter = st.radio("Category Filter", ["All", "Originals", "Clones", "Variants"], horizontal=True)
            
            lib = st.session_state.character_library
            if search_query:
                char_list = lib.search(search_query)
            else:
                cat_map = {"All": None, "Originals": "originals", "Clones": "clones", "Variants": "variants"}
                filter_val = cat_map[cat_filter]
                if filter_val:
                    char_list = lib.list_by_category(filter_val)
                else:
                    char_list = lib.list_all()
                    
            st.write(f"Characters in library: {len(char_list)}")
            
            for char_meta in char_list:
                with st.container(border=True):
                    c_col = cat_colors.get(char_meta['category'], "gray")
                    st.markdown(f"**{char_meta['name']}** <span style='color:{c_col}; font-size:10px; border:1px solid {c_col}; padding:1px 4px; border-radius:4px;'>{char_meta['category']}</span>", unsafe_allow_html=True)
                    st.caption(char_meta['description'] or "No description")
                    if char_meta['tags']:
                        st.markdown(" ".join([f"`{t}`" for t in char_meta['tags']]))
                    
                    b1, b2 = st.columns([1, 1])
                    if b1.button("Load", key=f"load_{char_meta['name']}_{char_meta['category']}", use_container_width=True):
                        st.session_state.active_profile = lib.load(char_meta['name'], char_meta['category'])
                        lib.set_active(st.session_state.active_profile)
                        st.rerun()
                        
                    if b2.button("Fork", key=f"fork_{char_meta['name']}_{char_meta['category']}", use_container_width=True):
                        st.session_state.forking = char_meta['name']
                        st.rerun()
                        
            if "forking" in st.session_state:
                st.markdown("---")
                st.write(f"Forking: **{st.session_state.forking}**")
                new_name = st.text_input("New Variant Name", placeholder="e.g. Broken TARS")
                if st.button("Save Variant"):
                    lib.fork(st.session_state.forking, new_name)
                    del st.session_state.forking
                    st.success("Variant created!")
                    st.rerun()
                
        # ==================== TAB 3: GENERATE ====================
        with tab_generate:
            st.markdown("### ⚡ AI Character Generator")
            st.caption("Describe a person, character, or archetype")
            
            gen_desc = st.text_area(
                "Description", 
                placeholder="Examples:\n• Nikola Tesla\n• A cynical noir detective from 1940s Chicago\n• Marcus Aurelius\n• A cheerful Buddhist monk who secretly loves metal music",
                height=80, 
                label_visibility="collapsed"
            )
            
            if st.button("Generate Character", use_container_width=True):
                if not st.session_state.get("selected_model_path"):
                    st.error("Please select an Inference Engine model from the sidebar below first.")
                elif not gen_desc:
                    st.warning("Please enter a description.")
                else:
                    with st.spinner("Lilith is analyzing the character..."):
                        generator = CharacterGenerator(llm_callable=get_llm_response)
                        try:
                            st.session_state.generator_preview = generator.generate(gen_desc)
                            st.success("Generation complete!")
                        except Exception as e:
                            st.error(f"Generation failed: {e}")
                            
            if st.session_state.get("generator_preview"):
                st.markdown("---")
                p = st.session_state.generator_preview
                st.markdown(f"### Preview: {p.meta.name}")
                st.caption(p.meta.description)
                
                gc1, gc2, gc3 = st.columns(3)
                hex_dict = {"O": p.hexaco.openness, "C": p.hexaco.conscientiousness, "E": p.hexaco.extraversion, "A": p.hexaco.agreeableness, "N": p.hexaco.neuroticism, "H": p.hexaco.honesty_humility}
                gc1.pyplot(render_radar_chart(hex_dict, color='#3b82f6', bg_color='#0f172a', figsize=(1.5, 1.5)))
                
                spec_dict = {"S": p.special.strength, "P": p.special.perception, "E": p.special.endurance, "C": p.special.charisma, "I": p.special.intelligence, "A": p.special.agility, "L": p.special.luck}
                gc2.pyplot(render_radar_chart(spec_dict, color='#f59e0b', bg_color='#1c1008', figsize=(1.5, 1.5)))
                
                exp_dict = {"S": p.expression.sarcasm, "W": p.expression.warmth, "V": p.expression.verbosity, "F": p.expression.formality, "D": p.expression.directness, "H": p.expression.humor, "E": p.expression.empathy, "A": p.expression.aggression}
                gc3.pyplot(render_radar_chart(exp_dict, color='#2dd4bf', bg_color='#071a18', figsize=(1.5, 1.5)))
                
                if p.meta.speech_patterns:
                    st.markdown("**Speech Patterns:**")
                    for pat in p.meta.speech_patterns:
                        st.markdown(f"- {pat}")
                        
                l1, l2, l3 = st.columns(3)
                if l1.button("Load This Character"):
                    st.session_state.active_profile = st.session_state.generator_preview
                    st.session_state.character_library.set_active(st.session_state.active_profile)
                    st.session_state.character_library.save(st.session_state.active_profile)
                    st.session_state.generator_preview = None
                    st.rerun()
                if l2.button("Save to Library"):
                    st.session_state.character_library.save(st.session_state.generator_preview)
                    st.success("Saved!")
                if l3.button("Discard"):
                    st.session_state.generator_preview = None
                    st.rerun()
                    
            if st.session_state.active_profile.meta.name:
                st.markdown("---")
                st.markdown("**Fork with modification**")
                mod_desc = st.text_input("e.g. same but more aggressive and less formal")
                if st.button("Generate Variant"):
                     if not st.session_state.get("selected_model_path"):
                         st.error("Please select an Inference Engine model from the sidebar below first.")
                     elif not mod_desc:
                         st.warning("Please enter a modification.")
                     else:
                         with st.spinner(f"Generating variant of {st.session_state.active_profile.meta.name}..."):
                             generator = CharacterGenerator(llm_callable=get_llm_response)
                             try:
                                 st.session_state.generator_preview = generator.generate_variant(st.session_state.active_profile, mod_desc)
                             except Exception as e:
                                 st.error(f"Generation failed: {e}")
                                 
        st.markdown("---")
        
        # --- MODEL SELECTOR ---
        st.markdown("### Inference Engine")
        models_dict = get_lm_studio_models()
        model_names = list(models_dict.keys())
        
        if not model_names:
            st.error("No GGUF models found in LM Studio (~/.lmstudio/models).")
            selected_model_path = None
        else:
            if "selected_model" not in st.session_state or st.session_state.selected_model not in model_names:
                st.session_state.selected_model = model_names[0]
                
            selected_model_name = st.selectbox(
                "LM Studio Models (via Llama-cpp)", 
                model_names, 
                index=model_names.index(st.session_state.selected_model)
            )
            st.session_state.selected_model = selected_model_name
            st.session_state.selected_model_path = models_dict[selected_model_name]
            selected_model_path = st.session_state.selected_model_path
            
            config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pipeline_config.json")
            try:
                with open(config_path, "r") as f:
                    cfg = json.load(f)
                if cfg["plugins"]["llama_cpp_llm"]["model_path"] != selected_model_path:
                    cfg["plugins"]["llama_cpp_llm"]["model_path"] = selected_model_path
                    with open(config_path, "w") as f:
                        json.dump(cfg, f, indent=2)
            except Exception:
                pass
            
        st.markdown("---")
        
        # --- VOICE PIPELINE ---
        st.markdown("### ⚡ Voice Pipeline")
        
        if not is_pipeline_running():
            st.session_state.voice_mode = False
            st.session_state.active_voice_mode = "OFFLINE"
            
            if st.button("🔈 START VOICE MODE (TTS)", use_container_width=True):
                if selected_model_path:
                    start_pipeline_process(selected_model_path, mode="tts_only")
                    st.rerun()
                else:
                    st.error("Select an Inference Engine model first.")
                    
            if st.button("🎙 START VOICE CHAT (STT + TTS)", use_container_width=True):
                 if selected_model_path:
                     start_pipeline_process(selected_model_path, mode="full")
                     st.rerun()
                 else:
                     st.error("Select an Inference Engine model first.")
        else:
            st.session_state.voice_mode = True
            st.info(f"Active: **{st.session_state.get('active_voice_mode', 'UNKNOWN')}**")
            if st.button("🔴 STOP VOICE MODE", use_container_width=True):
                stop_pipeline_process()
                st.rerun()
                
            st.success("🟢 Pipeline Subprocess is Running")
        
        with st.expander("Voice Settings"):
            cfg_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pipeline_config.json")
            try:
                with open(cfg_path, "r") as f:
                    cfg = json.load(f)
            except:
                cfg = {"plugins": {"kokoro_tts": {"voice": "af_heart", "speed": 1.0, "volume": 1.0}}}
                
            tts_cfg = cfg.get("plugins", {}).get("kokoro_tts", {})
            current_voice = str(tts_cfg.get("voice", "af_heart"))
            
            voices = ["af_heart", "af_sky", "am_echo", "bf_emma"]
            if current_voice not in voices: voices.append(current_voice)
            
            new_voice = st.selectbox("Voice", voices, index=voices.index(current_voice))
            new_speed = st.slider("Speed", 0.5, 2.0, float(tts_cfg.get("speed", 1.0)), 0.05)
            new_volume = st.slider("Volume", 0.1, 1.0, float(tts_cfg.get("volume", 1.0)), 0.05)
            
            if new_voice != current_voice or new_speed != float(tts_cfg.get("speed", 1.0)) or new_volume != float(tts_cfg.get("volume", 1.0)):
                try:
                    with open(cfg_path, "r") as f:
                        save_cfg = json.load(f)
                    save_cfg["plugins"]["kokoro_tts"]["voice"] = new_voice
                    save_cfg["plugins"]["kokoro_tts"]["speed"] = new_speed
                    save_cfg["plugins"]["kokoro_tts"]["volume"] = new_volume
                    with open(cfg_path, "w") as f:
                        json.dump(save_cfg, f, indent=2)
                except Exception:
                    pass

        with st.expander("📡 Pipeline Log"):
            if "pipe_logs" not in st.session_state:
                st.session_state.pipe_logs = []
            
            try:
                for _ in range(20):
                     msg = st.session_state.log_sub.recv_json()
                     log_str = f"[{msg.get('level', 'INFO')}] {msg.get('source', '')}: {msg.get('msg', '')}"
                     st.session_state.pipe_logs.append(log_str)
            except zmq.error.Again:
                pass
                
            st.session_state.pipe_logs = st.session_state.pipe_logs[-20:]
            
            if st.session_state.pipe_logs:
                st.code("\n".join(st.session_state.pipe_logs))
            else:
                st.write("No pipeline activity yet.")
                
            if st.button("Refresh Logs"):
                 pass 

    # --- MAIN PANEL ---
    st.title("Lilith AI")
    st.markdown("---")
    
    # Voice Mode Chat Passthrough
    if st.session_state.voice_mode:
        needs_rerun = False
        try:
            for _ in range(10): 
                msg = st.session_state.llm_sub.recv_json()
                if msg.get("text") and msg.get("source") == "llama_cpp_llm":
                    st.session_state.memory.add_message("assistant", msg["text"])
                    needs_rerun = True
        except zmq.error.Again:
            pass
            
        if needs_rerun:
            st.rerun()
    
    # Render chat history
    for msg in st.session_state.memory.get_history():
        role = msg["role"]
        content = msg["content"]
        
        if role == "assistant":
            with st.chat_message("assistant", avatar="👾"):
                st.markdown(f"<div style='background-color: #E9E9EB; color: #000000; padding: 10px 15px; border-radius: 18px; display: inline-block; max-width: 85%; font-family: -apple-system, BlinkMacSystemFont, sans-serif;'>{content}</div>", unsafe_allow_html=True)
        else:
            with st.chat_message("user", avatar="👤"):
                st.markdown(f"<div style='display: flex; justify-content: flex-end;'><div style='background-color: #0B84FF; color: #FFFFFF; padding: 10px 15px; border-radius: 18px; display: inline-block; max-width: 85%; font-family: -apple-system, BlinkMacSystemFont, sans-serif;'>{content}</div></div>", unsafe_allow_html=True)
                
    # Chat Input
    user_input = st.chat_input("Speak to Lilith...")
    if user_input:
        if not selected_model_path:
             st.error("Please select an Inference Engine model from the sidebar first.")
             return
             
        st.session_state.memory.add_message("user", user_input)
        
        if st.session_state.voice_mode:
            payload = {
                "text": user_input,
                "confidence": 1.0,
                "source": "streamlit_ui",
                "ts": time.time()
            }
            st.session_state.bus_push.send(json.dumps(payload).encode("utf-8"))
        else:
            system_prompt = generate_system_prompt(st.session_state.active_profile)
            with st.spinner("Lilith is thinking..."):
                history_excluding_new_input = st.session_state.memory.get_history()[:-1]
                response = chat_with_lilith(
                    system_prompt=system_prompt,
                    history=history_excluding_new_input,
                    user_input=user_input,
                    model_path=selected_model_path
                )
            st.session_state.memory.add_message("assistant", response)

        # Triggers active character resaving in case memory affects mood state in future iterations
        save_active_profile()
        st.rerun()

    # --- Check for LLM responses non-blockingly ---
    llm_text = check_llm_response()
    if llm_text:
        st.session_state.memory.add_message("assistant", llm_text)
        st.rerun()

if __name__ == "__main__":
    main()

import json
import datetime
import re
from lilith_ai.core.personality import CharacterProfile, dict_to_profile

class CharacterGenerator:
    """
    Uses the running LLM to generate character trait values
    from a name or description. Returns a CharacterProfile
    ready for review and manual adjustment before saving.
    """

    GENERATION_PROMPT_TEMPLATE = """
You are a personality analyst. Given a character name or description,
return a JSON object representing their personality traits.

CHARACTER: {character_description}

Return ONLY valid JSON with exactly this structure. No preamble,
no explanation, no markdown. Raw JSON only:

{{
  "meta": {{
    "name": "",
    "category": "clone",
    "source": "",
    "description": "<2 sentence character description>",
    "tags": ["", "", ""],
    "backstory": "<3-4 sentence backstory>",
    "speech_patterns": [
      "",
      "",
      ""
    ],
    "custom_instructions": "<1-2 sentences of critical character rules>"
  }},
  "hexaco": {{
    "openness": <0.0-1.0>,
    "conscientiousness": <0.0-1.0>,
    "extraversion": <0.0-1.0>,
    "agreeableness": <0.0-1.0>,
    "neuroticism": <0.0-1.0>,
    "honesty_humility": <0.0-1.0>
  }},
  "special": {{
    "strength": <0.0-1.0>,
    "perception": <0.0-1.0>,
    "endurance": <0.0-1.0>,
    "charisma": <0.0-1.0>,
    "intelligence": <0.0-1.0>,
    "agility": <0.0-1.0>,
    "luck": <0.0-1.0>
  }},
  "expression": {{
    "sarcasm": <0.0-1.0>,
    "warmth": <0.0-1.0>,
    "verbosity": <0.0-1.0>,
    "formality": <0.0-1.0>,
    "directness": <0.0-1.0>,
    "humor": <0.0-1.0>,
    "empathy": <0.0-1.0>,
    "aggression": <0.0-1.0>
  }},
  "domains": {{
    "science": <0.0-1.0>,
    "philosophy": <0.0-1.0>,
    "combat": <0.0-1.0>,
    "art": <0.0-1.0>,
    "politics": <0.0-1.0>,
    "technology": <0.0-1.0>,
    "nature": <0.0-1.0>,
    "psychology": <0.0-1.0>
  }}
}}

IMPORTANT GUIDELINES for trait values. Clamp all floats between 0.0 and 1.0:
- openness: curiosity, imagination, embrace of novel ideas (0=concrete/traditional, 1=wildly creative)
- conscientiousness: discipline, organization, reliability (0=chaotic/impulsive, 1=methodical/precise)
- extraversion: social energy, assertiveness (0=deeply introverted, 1=highly extraverted)
- agreeableness: cooperation, trust, kindness (0=antagonistic, 1=deeply cooperative)
- neuroticism: emotional volatility, anxiety (0=unshakeable calm, 1=highly reactive)
- honesty_humility: sincerity, fairness (0=manipulative/deceptive, 1=radically honest)
- strength: forcefulness of will and presence (not physical)
- perception: noticing details, reading people and situations
- endurance: patience, persistence, not giving up
- charisma: social magnetism, persuasion, drawing people in
- intelligence: reasoning depth, knowledge breadth
- agility: adaptability, quick thinking, pivoting
- luck: optimism, tendency toward positive framing
Base all values on documented personality traits, behaviors, and
historical/fictional accounts of this character.
"""

    VARIANT_PROMPT_TEMPLATE = """
You are a personality analyst. Given an existing character profile and a desired modification, return an updated JSON object.

ORIGINAL CHARACTER JSON:
{base_json}

MODIFICATION REQUESTED:
{modification}

Return ONLY valid JSON with exactly the same structure. No preamble, no markdown. Update the traits, description, and speech patterns to match the requested modification.
"""

    def __init__(self, llm_callable):
        """
        llm_callable: a function that accepts a prompt string and
        returns a response string. This keeps CharacterGenerator
        decoupled from the specific LLM backend.
        Example: generator = CharacterGenerator(llm_callable=my_llm.generate)
        """
        self.llm = llm_callable

    def _extract_json(self, text: str) -> dict:
        """Attempt to parse JSON from LLM output, stripping markdown blocks if present."""
        text = text.strip()
        if text.startswith("```json"):
            text = text[len("```json"):]
        elif text.startswith("```"):
            text = text[len("```"):]
        if text.endswith("```"):
            text = text[:-len("```")]
        
        # Use regex to find the outermost braces in case there is text before/after
        match = re.search(r'(\{.*\})', text.strip(), re.DOTALL)
        if match:
            text = match.group(1)
            
        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            raise ValueError(f"Failed to parse JSON from LLM response. Output snippet: {text[:100]}... Error: {e}")

    def generate(self, character_description: str) -> CharacterProfile:
        """
        Main generation method.
        """
        prompt = self.GENERATION_PROMPT_TEMPLATE.format(character_description=character_description)
        response = self.llm(prompt)
        
        parsed_dict = self._extract_json(response)
        
        profile = dict_to_profile(parsed_dict)
        profile.meta.created = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        return profile

    def generate_variant(self, base_profile: CharacterProfile, modification: str) -> CharacterProfile:
        """
        Generate a variant of an existing character.
        """
        from lilith_ai.core.personality import profile_to_dict
        
        base_json_str = json.dumps(profile_to_dict(base_profile), indent=2)
        prompt = self.VARIANT_PROMPT_TEMPLATE.format(base_json=base_json_str, modification=modification)
        
        response = self.llm(prompt)
        parsed_dict = self._extract_json(response)
        
        new_profile = dict_to_profile(parsed_dict)
        new_profile.meta.category = "variants"
        new_profile.meta.name = f"{base_profile.meta.name} ({modification[:20]})"
        new_profile.meta.created = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        return new_profile

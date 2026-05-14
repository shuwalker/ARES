import os
import json
import uuid
from typing import List, Dict, Optional
from lilith_ai.core.personality import CharacterProfile, profile_to_dict, load_profile

class CharacterLibrary:
    """Manages the full library of saved character profiles."""

    LIBRARY_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "profiles", "_library")
    CATEGORIES = ["originals", "clones", "variants"]
    
    # Active path relative to project root
    ACTIVE_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "profiles", "active.json")

    def __init__(self, library_root: Optional[str] = None):
        if library_root:
            self.library_root = library_root
        else:
            self.library_root = self.LIBRARY_ROOT
            
        # Create category subdirectories if they don't exist
        for category in self.CATEGORIES:
            os.makedirs(os.path.join(self.library_root, category), exist_ok=True)
            
        # Ensure active.json exists by creating a default if missing
        if not os.path.exists(self.ACTIVE_PATH):
            os.makedirs(os.path.dirname(self.ACTIVE_PATH), exist_ok=True)
            default_profile = CharacterProfile()
            with open(self.ACTIVE_PATH, 'w', encoding='utf-8') as f:
                json.dump(profile_to_dict(default_profile), f, indent=2)

    def _get_filename(self, name: str) -> str:
        safe_name = name.lower().replace(" ", "_").replace("/", "_").replace("\\", "_")
        return f"{safe_name}.json"

    def list_all(self) -> List[Dict]:
        """Return list of dicts with keys: name, category, path, tags, description
        Sorted alphabetically by name within each category."""
        results = []
        for category in self.CATEGORIES:
            results.extend(self.list_by_category(category))
        # Sort by name
        return sorted(results, key=lambda x: x["name"].lower())

    def list_by_category(self, category: str) -> List[Dict]:
        """Return characters filtered by category: originals | clones | variants"""
        if category not in self.CATEGORIES:
            return []
            
        cat_dir = os.path.join(self.library_root, category)
        results = []
        if os.path.exists(cat_dir):
            for filename in os.listdir(cat_dir):
                if filename.endswith(".json"):
                    path = os.path.join(cat_dir, filename)
                    try:
                        profile = load_profile(path)
                        results.append({
                            "name": profile.meta.name,
                            "category": profile.meta.category,
                            "path": path,
                            "tags": profile.meta.tags,
                            "description": profile.meta.description
                        })
                    except Exception:
                        pass
        return sorted(results, key=lambda x: x["name"].lower())

    def load(self, name: str, category: Optional[str] = None) -> CharacterProfile:
        """Load a character by name. Searches all categories if category=None.
        Raises FileNotFoundError with helpful message if not found."""
        filename = self._get_filename(name)
        
        categories_to_search = [category] if category else self.CATEGORIES
        
        for cat in categories_to_search:
            filepath = os.path.join(self.library_root, cat, filename)
            if os.path.exists(filepath):
                return load_profile(filepath)
                
        raise FileNotFoundError(f"Character '{name}' not found in library.")

    def save(self, profile: CharacterProfile, category: Optional[str] = None) -> str:
        """Save a profile to the library.
        category defaults to profile.meta.category.
        Filename derived from profile.meta.name (lowercase, spaces→underscores).
        Returns the saved file path."""
        save_category = category or profile.meta.category
        if save_category not in self.CATEGORIES:
            save_category = "variants"
            
        # Force meta.category to match where it's saved
        profile.meta.category = save_category
            
        filename = self._get_filename(profile.meta.name)
        path = os.path.join(self.library_root, save_category, filename)
        
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(profile_to_dict(profile), f, indent=2)
            
        return path

    def fork(self, name: str, new_name: str, category: str = "variants") -> CharacterProfile:
        """Load an existing character, change its name, save as new variant.
        Returns the new profile without modifying the original."""
        original = self.load(name)
        
        # We deserialize/serialize to deep clone and apply migration safely
        as_dict = profile_to_dict(original)
        new_profile = load_profile("dummy_path") # To get dict_to_profile via standard flow
        
        # Override name and category
        from lilith_ai.core.personality import dict_to_profile
        new_profile = dict_to_profile(as_dict)
        new_profile.meta.name = new_name
        new_profile.meta.category = category
        
        self.save(new_profile, category)
        return new_profile

    def delete(self, name: str, category: str) -> bool:
        """Delete a character file. Returns True on success."""
        filename = self._get_filename(name)
        path = os.path.join(self.library_root, category, filename)
        if os.path.exists(path):
            os.remove(path)
            return True
        return False

    def set_active(self, profile: CharacterProfile) -> None:
        """Write profile to profiles/active.json.
        This is what the pipeline reads on every message."""
        os.makedirs(os.path.dirname(self.ACTIVE_PATH), exist_ok=True)
        with open(self.ACTIVE_PATH, 'w', encoding='utf-8') as f:
            json.dump(profile_to_dict(profile), f, indent=2)

    def get_active(self) -> CharacterProfile:
        """Load and return the current active character."""
        return load_profile(self.ACTIVE_PATH)

    def search(self, query: str) -> List[Dict]:
        """Search characters by name, tags, or description.
        Case-insensitive substring match."""
        query = query.lower()
        all_chars = self.list_all()
        results = []
        
        for char in all_chars:
            if (query in char["name"].lower() or
                query in char["description"].lower() or
                any(query in tag.lower() for tag in char["tags"])):
                results.append(char)
                
        return results

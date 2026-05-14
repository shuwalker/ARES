import os
import json
import importlib.util
from typing import Dict, List, Type
from lilith_ai.plugins.base_plugin import BasePlugin
from lilith_ai.bus.zmq_bus import LilithBus

class PluginRegistry:
    """Discovers, loads, and manages lifecycle of Lilith pipeline plugins."""

    def __init__(self, plugins_dir: str = "src/lilith_ai/plugins"):
        self.plugins_dir = plugins_dir
        self.available: Dict[str, dict] = {}    # name -> manifest
        self.loaded: Dict[str, BasePlugin] = {} # name -> instance

    def discover(self) -> List[str]:
        """Finds all plugin.json manifests in subdirectories."""
        self.available.clear()
        
        if not os.path.exists(self.plugins_dir):
            return []
            
        for d in os.listdir(self.plugins_dir):
            plugin_path = os.path.join(self.plugins_dir, d)
            if not os.path.isdir(plugin_path) or d == "__pycache__":
                continue
                
            manifest_path = os.path.join(plugin_path, "plugin.json")
            if os.path.exists(manifest_path):
                try:
                    with open(manifest_path, 'r', encoding='utf-8') as f:
                        manifest = json.load(f)
                        
                    name = manifest.get("name")
                    if name:
                        manifest["_path"] = plugin_path
                        self.available[name] = manifest
                except Exception as e:
                    print(f"Error loading manifest {manifest_path}: {e}")
                    
        return list(self.available.keys())

    def load(self, plugin_name: str, bus: LilithBus, config: dict) -> BasePlugin:
        """Dynamically instantiates a plugin subclass from a discovered folder."""
        if plugin_name not in self.available:
            raise ValueError(f"Plugin '{plugin_name}' not found in registry.")
            
        manifest = self.available[plugin_name]
        plugin_path = manifest["_path"]
        main_py = os.path.join(plugin_path, "main.py")
        
        if not os.path.exists(main_py):
            raise FileNotFoundError(f"Missing main.py for plugin '{plugin_name}'")
            
        import sys
        import importlib.machinery
        
        # Dynamically create the plugin package namespace so relative imports work
        pkg_name = f"lilith_plugins.{plugin_name}"
        if pkg_name not in sys.modules:
            pkg_spec = importlib.machinery.ModuleSpec(pkg_name, None, is_package=True)
            pkg_module = importlib.util.module_from_spec(pkg_spec)
            pkg_module.__path__ = [plugin_path]
            sys.modules[pkg_name] = pkg_module

        # Dynamically import the main.py module within this package namespace
        module_name = f"{pkg_name}.main"
        spec = importlib.util.spec_from_file_location(module_name, main_py)
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        spec.loader.exec_module(module)
        
        # Find the class inheriting from BasePlugin
        plugin_class = None
        for obj_name in dir(module):
            obj = getattr(module, obj_name)
            if isinstance(obj, type) and issubclass(obj, BasePlugin) and obj is not BasePlugin:
                plugin_class = obj
                break
                
        if plugin_class is None:
            raise TypeError(f"Could not find a BasePlugin subclass in {main_py}")
            
        instance = plugin_class(bus, config)
        self.loaded[plugin_name] = instance
        return instance

    def load_from_config(self, pipeline_config: dict, bus: LilithBus) -> None:
        """Loads all active plugins defined in the master configuration."""
        active_plugins = []
        
        # Load from the 'pipeline' map
        pipeline_defs = pipeline_config.get("pipeline", {})
        for role, p_name in pipeline_defs.items():
            if p_name: 
                active_plugins.append(p_name)
                
        # Remove duplicates
        active_plugins = list(set(active_plugins))
        
        for name in active_plugins:
            cfg = pipeline_config.get("plugins", {}).get(name, {})
            self.load(name, bus, cfg)

    def start_all(self) -> None:
        """Starts all loaded plugins in order."""
        for name, plugin in self.loaded.items():
            plugin.start()

    def stop_all(self) -> None:
        """Stops all loaded plugins in reverse initialization order."""
        # Reverse order teardown
        for name, plugin in reversed(list(self.loaded.items())):
            plugin.stop()

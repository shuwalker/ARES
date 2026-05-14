"""
Main memory manager for ARES.

This module orchestrates the different memory stores (episodic, semantic)
to provide a unified interface for the agent.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from agent.memory.stores.lancedb_store import LanceDBStore
from agent.memory.stores.kuzu_store import KuzuStore
from agent.memory.episodic import read_recent

class MemoryManager:
    """
    Orchestrates different memory stores to provide a unified memory interface.
    """
    def __init__(self, brain_path: str = "brain"):
        """
        Initializes the MemoryManager.

        Args:
            brain_path: The path to the brain directory.
        """
        self.brain_path = brain_path
        self.episodic_store = LanceDBStore(db_path=f"{self.brain_path}/lancedb")
        self.semantic_store = KuzuStore(db_path=f"{self.brain_path}/kuzu_db")
        self._bootstrap_if_empty()

    async def initialize(self):
        """Asynchronously initializes the memory manager."""
        pass

    async def shutdown(self):
        """Asynchronously shuts down the memory manager."""
        pass

    def get_context_for_prompt(self, task_description: str, person_name: str = "matthew") -> str:
        """
        Gets relevant memory context for a given task description, including relationship guidance.

        Args:
            task_description: The description of the task.
            person_name: Name of the person to get relationship context for (default: matthew)

        Returns:
            A string containing the formatted relevant memories and relationship guidance.
        """
        # Try to load relationship context
        relationship_guidance = ""
        try:
            from agent.identity.relationship_model import RelationshipModel
            rm = RelationshipModel(relationships_dir=f"{self.brain_path}/character/relationships")
            relationship_guidance = rm.get_communication_guidance(person_name)
        except Exception as e:
            # Log error but don't fail
            import sys
            print(f"Warning: Could not load relationship model: {e}", file=sys.stderr)

        memories = self.search_relevant_memories(task_description)
        context_parts = []

        # Add relationship guidance first if available
        if relationship_guidance:
            context_parts.append(relationship_guidance)

        # Add relevant memories
        if memories:
            mem_str = "Relevant past interactions:"
            for mem in memories:
                mem_str += f"\n- [{mem['timestamp']}] {mem['role']}: {mem['text']}"
            context_parts.append(mem_str)
        else:
            context_parts.append("No relevant memories found.")

        return "\n\n".join(context_parts)


    def _bootstrap_if_empty(self):
        """
        Bootstraps the LanceDB and Kuzu databases from old episodic memory
        files if the new stores are empty.
        """
        # Check if the LanceDB table has any records.
        if self.episodic_store.table.count_rows() == 0:
            print("Bootstrapping memory from old episodic files...")
            # Read old entries from JSONL files.
            old_entries = read_recent(n=1000, brain_path=self.brain_path)
            for entry in old_entries:
                # Add each stage of the old entry as an interaction.
                for stage in entry.stages:
                    role = stage.get("role", "agent")
                    text = stage.get("content", "")
                    if text:
                        self.add_interaction(
                            role=role,
                            text=text,
                            task_id=entry.task_id
                        )
            print(f"Bootstrap complete. Added {self.episodic_store.table.count_rows()} interactions.")


    def add_interaction(self, role: str, text: str, task_id: str):
        """
        Adds a new interaction to all memory stores.

        Args:
            role: The role of the speaker ('user' or 'agent').
            text: The text content of the interaction.
            task_id: The ID of the task this interaction is part of.
        """
        interaction_id = str(uuid.uuid4())
        timestamp = datetime.now().isoformat()

        # Add to episodic store (LanceDB)
        self.episodic_store.add_interaction(
            text=text,
            role=role,
            task_id=task_id,
            timestamp=timestamp
        )

        # Add to semantic store (Kuzu)
        self.semantic_store.add_interaction(
            interaction_id=interaction_id,
            role=role,
            text=text,
            timestamp=timestamp
        )

    def search_relevant_memories(self, query: str, limit: int = 10) -> list[dict]:
        """
        Searches for memories relevant to a query using the episodic vector store.

        Args:
            query: The query text to search for.
            limit: The maximum number of memories to return.

        Returns:
            A list of the most relevant memories.
        """
        return self.episodic_store.search_relevant_interactions(query, limit)

    def get_interactions_mentioning(self, entity_name: str, limit: int = 10) -> list[dict]:
        """
        Retrieves interactions that mention a specific entity from the semantic store.

        Args:
            entity_name: The name of the entity to search for.
            limit: The maximum number of interactions to return.

        Returns:
            A list of interactions that mention the entity.
        """
        return self.semantic_store.get_interactions_mentioning(entity_name, limit)

if __name__ == '__main__':
    # Example usage of the MemoryManager.
    print("Initializing Memory Manager...")
    memory_manager = MemoryManager()

    print("\\nAdding a new interaction...")
    memory_manager.add_interaction(
        role="user",
        text="This is a test interaction about ARES.",
        task_id="task-test"
    )

    print("\\nSearching for relevant memories to 'ARES test'...")
    memories = memory_manager.search_relevant_memories("ARES test")
    for mem in memories:
        print(f"  - [{mem['timestamp']}] {mem['role']}: {mem['text']} (Similarity: {mem['_distance']:.4f})")

    print("\\nQuerying for interactions mentioning 'ARES'...")
    ares_mentions = memory_manager.get_interactions_mentioning("ARES")
    for mention in ares_mentions:
        print(f"  - [{mention['i.timestamp']}] {mention['i.role']}: {mention['i.text']}")

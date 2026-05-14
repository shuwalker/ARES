"""
LanceDB store for ARES episodic memory.

This module handles the storage and retrieval of LLM interactions as vector embeddings.
"""

from __future__ import annotations

import lancedb
import pandas as pd
from lancedb.pydantic import LanceModel, Vector
from sentence_transformers import SentenceTransformer
from pathlib import Path

# The path to the LanceDB database.
DB_PATH = Path(".data/lancedb")

class Interaction(LanceModel):
    """
    Pydantic model for an interaction stored in LanceDB.
    Each entry represents a single message from a user or the agent.
    """
    # The dimension of the vector embedding. 'all-MiniLM-L6-v2' produces 384-dimensional vectors.
    vector: Vector(384)
    # The text content of the message.
    text: str
    # The role of the speaker, e.g., 'user' or 'agent'.
    role: str
    # The timestamp of the interaction.
    timestamp: str
    # The ID of the task this interaction belongs to.
    task_id: str

class LanceDBStore:
    """
    A class to manage the LanceDB episodic memory store.
    """
    def __init__(self, db_path: str | Path = DB_PATH):
        """
        Initializes the LanceDBStore.

        Args:
            db_path: The path to the LanceDB database.
        """
        self.db_path = Path(db_path)
        self.db_path.mkdir(parents=True, exist_ok=True)
        self.db = lancedb.connect(self.db_path)
        # Load the sentence transformer model for creating embeddings.
        self.model = SentenceTransformer('all-MiniLM-L6-v2')
        self.table = self.db.create_table("interactions", schema=Interaction, exist_ok=True)

    def add_interaction(self, text: str, role: str, task_id: str, timestamp: str) -> None:
        """
        Adds a new interaction to the LanceDB store.

        Args:
            text: The text content of the interaction.
            role: The role of the speaker ('user' or 'agent').
            task_id: The ID of the task this interaction is part of.
            timestamp: The timestamp of the interaction.
        """
        # Create the vector embedding for the text.
        vector = self.model.encode(text, convert_to_tensor=False)
        # Create a new interaction object.
        interaction = {
            "vector": vector,
            "text": text,
            "role": role,
            "timestamp": timestamp,
            "task_id": task_id,
        }
        # Add the interaction to the table.
        self.table.add([interaction])

    def search_relevant_interactions(self, query: str, limit: int = 10) -> list[dict]:
        """
        Searches for the most relevant interactions to a given query.

        Args:
            query: The query text to search for.
            limit: The maximum number of interactions to return.

        Returns:
            A list of the most relevant interactions.
        """
        # Create an embedding for the query.
        query_vector = self.model.encode(query, convert_to_tensor=False)
        # Search the table for similar vectors.
        results = self.table.search(query_vector).limit(limit).to_pandas()
        return results.to_dict('records')

if __name__ == '__main__':
    # Example usage of the LanceDBStore.
    # This will only run when the script is executed directly.
    from datetime import datetime

    print("Initializing LanceDB store...")
    store = LanceDBStore()
    
    # Clear previous data for a clean run
    # In a real app, you might not want to do this
    store.db.drop_table("interactions")
    store.table = store.db.create_table("interactions", schema=Interaction, exist_ok=True)


    print("Adding example interactions...")
    # Add some example interactions.
    interactions = [
        ("What is the status of the ARES project?", "user", "task-001"),
        ("The ARES project is on track. We are currently implementing the memory system.", "agent", "task-001"),
        ("What are the next steps?", "user", "task-001"),
        ("The next steps are to implement the Kuzu knowledge graph and integrate it with the memory manager.", "agent", "task-001"),
        ("How do I install the dependencies?", "user", "task-002"),
        ("You can install the dependencies with 'pip install lancedb kuzu sentence-transformers'.", "agent", "task-002"),
    ]

    for text, role, task_id in interactions:
        store.add_interaction(text, role, task_id, datetime.now().isoformat())

    print(f"Total interactions in table: {store.table.count_rows()}")

    # Search for relevant interactions.
    query = "How is the ARES project going?"
    print(f"\\nSearching for interactions relevant to: '{query}'")
    relevant_interactions = store.search_relevant_interactions(query)

    # Print the results.
    for interaction in relevant_interactions:
        print(f"  - [{interaction['timestamp']}] {interaction['role']}: {interaction['text']} (Similarity: {interaction['_distance']:.4f})")

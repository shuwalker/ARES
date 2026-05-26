"""
KuzuDB store for ARES semantic memory (knowledge graph).

This module handles the storage and retrieval of factual and semantic information
as a graph.
"""
from __future__ import annotations

import kuzu
import re
from pathlib import Path
from datetime import datetime

# The path to the Kuzu database.
DB_PATH = Path(".data/kuzu_db")

class KuzuStore:
    """
    A class to manage the KuzuDB knowledge graph.
    """
    def __init__(self, db_path: str | Path = DB_PATH):
        """
        Initializes the KuzuStore.

        Args:
            db_path: The path to the Kuzu database.
        """
        self.db_path = Path(db_path)
        # Initialize the database and connection.
        self.db = kuzu.Database(self.db_path)
        self.conn = kuzu.Connection(self.db)
        self._create_schema()

    def _create_schema(self):
        """
        Creates the knowledge graph schema if it doesn't already exist.
        """
        # Node tables: Interaction, Entity
        self.conn.execute("CREATE NODE TABLE IF NOT EXISTS Interaction(id STRING, role STRING, text STRING, timestamp STRING, PRIMARY KEY (id))")
        self.conn.execute("CREATE NODE TABLE IF NOT EXISTS Entity(name STRING, PRIMARY KEY (name))")
        
        # Relationship tables: MENTIONS
        self.conn.execute("CREATE REL TABLE IF NOT EXISTS Mentions(FROM Interaction TO Entity)")

    def _extract_entities(self, text: str) -> list[str]:
        """
        A simple entity extractor using regex to find proper nouns (capitalized words).
        
        NOTE: This is a very basic implementation. For a more robust solution,
        consider using a proper NLP library like spaCy or NLTK.
        """
        # Find all capitalized words or all-caps words (of length 2 or more).
        entities = re.findall(r'\b([A-Z][a-z]+|[A-Z]{2,})\b', text)
        return list(set(entities))

    def add_interaction(self, interaction_id: str, role: str, text: str, timestamp: str):
        """
        Adds a new interaction to the knowledge graph, extracting and linking entities.

        Args:
            interaction_id: The unique ID for the interaction.
            role: The role of the speaker ('user' or 'agent').
            text: The text content of the interaction.
            timestamp: The timestamp of the interaction.
        """
        # Add the interaction node to the graph.
        self.conn.execute(
            "CREATE (i:Interaction {id: $id, role: $role, text: $text, timestamp: $timestamp})",
            {"id": interaction_id, "role": role, "text": text, "timestamp": timestamp}
        )

        # Extract and process entities from the text.
        entities = self._extract_entities(text)
        for entity_name in entities:
            # Create the entity node if it doesn't exist.
            self.conn.execute("MERGE (e:Entity {name: $name})", {"name": entity_name})
            # Create a relationship from the interaction to the entity.
            self.conn.execute(
                "MATCH (i:Interaction {id: $id}), (e:Entity {name: $name}) CREATE (i)-[:Mentions]->(e)",
                {"id": interaction_id, "name": entity_name}
            )

    def get_interactions_mentioning(self, entity_name: str, limit: int = 10) -> list[dict]:
        """
        Retrieves interactions that mention a specific entity.

        Args:
            entity_name: The name of the entity to search for.
            limit: The maximum number of interactions to return.

        Returns:
            A list of interactions that mention the entity.
        """
        query = """
            MATCH (i:Interaction)-[:Mentions]->(e:Entity)
            WHERE e.name = $entity_name
            RETURN i.id, i.role, i.text, i.timestamp
            ORDER BY i.timestamp DESC
            LIMIT $limit
        """
        results = self.conn.execute(query, {"entity_name": entity_name, "limit": limit})
        return results.get_as_df().to_dict('records')


if __name__ == '__main__':
    # Example usage of the KuzuStore.
    import os
    
    print("Initializing Kuzu store...")
    store = KuzuStore()

    print("Adding example interactions...")
    interactions = [
        ("task-001-1", "user", "What is the status of the ARES project?"),
        ("task-001-2", "agent", "The ARES project is on track. We are currently implementing the memory system for ARES."),
        ("task-001-3", "user", "What are the next steps for ARES?"),
        ("task-001-4", "agent", "The next steps are to implement the Kuzu knowledge graph and integrate it with the memory manager."),
    ]

    for id, role, text in interactions:
        store.add_interaction(id, role, text, datetime.now().isoformat())

    print("\\nQuerying for interactions mentioning 'ARES'...")
    ares_interactions = store.get_interactions_mentioning("ARES")
    for interaction in ares_interactions:
        print(f"  - [{interaction['i.timestamp']}] {interaction['i.role']}: {interaction['i.text']}")
        
    print("\\nQuerying for interactions mentioning 'Kuzu'...")
    kuzu_interactions = store.get_interactions_mentioning("Kuzu")
    for interaction in kuzu_interactions:
        print(f"  - [{interaction['i.timestamp']}] {interaction['i.role']}: {interaction['i.text']}")


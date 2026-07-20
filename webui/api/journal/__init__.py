"""
ARES Journal — unified conversation importer and store.

Indexes conversations from every AI tool on the machine into a single
searchable database so the SI can reference past context across all agents.

Storage: ~/.ares/journal/
Schema:  journal.db (SQLite with FTS5)
Imports: Hermes, Claude Code, Grok, Gemini, Codex, SAM, iMessage

Each imported conversation is normalized into a common schema:
  - source: which tool produced it (hermes, claude_code, grok, gemini, codex, sam, imessage)
  - session_id: original session identifier
  - title: human-readable session title
  - model: AI model used
  - workspace: working directory or context
  - created_at, updated_at: timestamps
  - messages: ordered list of {role, content, timestamp, metadata}

The importer also creates embeddings-ready text chunks and FTS5 indexes
for instant keyword search across all conversations.
"""
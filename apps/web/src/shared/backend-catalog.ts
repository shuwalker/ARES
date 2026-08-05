export const JAEGER_BACKEND_ID = "jaeger_local";

export interface BackendMeta {
  label: string;
  color: string;
}

// Must stay in sync with services/controller/api/backend_catalog.py::BACKEND_META
// See services/controller/tests/test_backend_catalog_ts_parity.py
export const BACKEND_META: Readonly<Record<string, BackendMeta>> = {
  hermes_local:   { label: "Hermes Agent", color: "#08EBF1" },
  jaeger_local:   { label: "Jaeger AI", color: "#3889FD" },
  claude_local:   { label: "Claude Code", color: "#D97706" },
  codex_local:    { label: "OpenAI Codex", color: "#10B981" },
  gemini_local:   { label: "Google Gemini", color: "#6366F1" },
  gemini_cloud:   { label: "Google Gemini API", color: "#6366F1" },
  gemini_antigravity: { label: "Gemini (Antigravity IDE)", color: "#6366F1" },
  grok_local:     { label: "xAI Grok", color: "#8B5CF6" },
  opencode_local: { label: "OpenCode", color: "#EC4899" },
  cursor_local:   { label: "Cursor", color: "#06B6D4" },
  ollama_local:   { label: "Ollama", color: "#F59E0B" },
  openai_cloud:   { label: "OpenAI", color: "#10A37F" },
  xai_cloud:      { label: "xAI Grok", color: "#8B5CF6" },
  pi_local:       { label: "Pi Coding Agent", color: "#F472B6" },
};

const BACKEND_ALIASES: Readonly<Record<string, string>> = {
  jaeger: JAEGER_BACKEND_ID,
  jaegerai: JAEGER_BACKEND_ID,
  jaeger_ai: JAEGER_BACKEND_ID,
  jros: JAEGER_BACKEND_ID,
  jros_local: JAEGER_BACKEND_ID,
  hermes: "hermes_local",
};

/** Normalize API, imported-session, and saved legacy values at the UI edge. */
export function normalizeBackendId(value: unknown): string {
  const raw = String(value ?? "").trim().toLowerCase();
  return BACKEND_ALIASES[raw] ?? raw;
}

export function backendLabel(value: unknown): string {
  const id = normalizeBackendId(value);
  return BACKEND_META[id]?.label
    ?? id.replace(/_/g, " ").replace(/\b\w/g, (character) => character.toUpperCase());
}

export function backendColor(value: unknown): string {
  return BACKEND_META[normalizeBackendId(value)]?.color ?? "#6b7194";
}

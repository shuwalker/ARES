import type {
  AgentHealth,
  BackendSettings,
  ConversationMessage,
  ConversationRole,
  ConversationSession,
  RuntimeConnection,
  SessionSummary,
  ToolInventory,
  UsageBreakdownRow,
  UsageDailyPoint,
  UsageInsights,
  WorkspaceEntry,
  WorkspaceSummary,
} from "@/shared/contracts";

type Raw = Record<string, unknown>;

function record(value: unknown): Raw {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Raw : {};
}

function text(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value.map((part) => {
      if (typeof part === "string") return part;
      const item = record(part);
      return String(item.text || item.content || "");
    }).filter(Boolean).join("\n");
  }
  const item = record(value);
  return String(item.text || item.content || "");
}

function timestamp(value: unknown): string | undefined {
  if (!value) return undefined;
  if (typeof value === "string" && Number.isNaN(Number(value))) return value;
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return undefined;
  return new Date(numeric < 10_000_000_000 ? numeric * 1000 : numeric).toISOString();
}

function role(value: unknown): ConversationRole {
  const normalized = String(value || "assistant").toLowerCase();
  if (normalized === "user" || normalized === "system" || normalized === "tool") return normalized;
  return "assistant";
}

export function translateMessage(value: unknown, index = 0): ConversationMessage {
  const raw = record(value);
  return {
    id: String(raw.id || raw.message_id || `${raw.timestamp || "message"}-${index}`),
    role: role(raw.role || raw.type),
    text: text(raw.content ?? raw.text ?? raw.message),
    createdAt: timestamp(raw.created_at || raw.timestamp),
  };
}

export function translateSessionSummary(value: unknown): SessionSummary {
  const raw = record(value);
  const id = String(raw.session_id || raw.id || "");
  const backendId = String(raw.ares_backend || raw.backend_id || raw.backend || raw.model_provider || "");
  const source = String(
    raw.source_tag || raw.session_source || raw.source_label || raw.raw_source ||
    (raw.is_cli_session ? "cli" : "")
  ) || "webui";
  return {
    id,
    title: String(raw.title || "New conversation"),
    workspace: String(raw.workspace || ""),
    model: String(raw.model || ""),
    provider: String(raw.model_provider || raw.provider || ""),
    backendId,
    profile: String(raw.profile || "default"),
    source,
    updatedAt: timestamp(raw.last_message_at || raw.updated_at || raw.created_at),
    activeStreamId: String(raw.active_stream_id || "") || undefined,
    messageCount: Number(raw.message_count || 0),
    pinned: Boolean(raw.pinned),
    archived: Boolean(raw.archived),
    isStreaming: Boolean(raw.is_streaming || raw.active_stream_id),
    readOnly: Boolean(raw.read_only || raw.is_read_only),
  };
}

export function translateConversation(value: unknown): ConversationSession {
  const raw = record(value);
  return {
    ...translateSessionSummary(raw),
    messages: Array.isArray(raw.messages) ? raw.messages.map(translateMessage) : [],
    pendingStartedAt: timestamp(raw.pending_started_at),
  };
}

export function translateSessions(value: unknown): SessionSummary[] {
  const raw = record(value);
  return (Array.isArray(raw.sessions) ? raw.sessions : [])
    .map(translateSessionSummary)
    .filter((session) => session.id);
}

export function translateSettings(value: unknown): BackendSettings {
  const raw = record(value);
  return {
    assistantName: String(raw.bot_name || "Ares"),
    authEnabled: Boolean(raw.auth_enabled),
    version: String(raw.webui_version || "") || undefined,
  };
}

export function translateWorkspaces(value: unknown) {
  const raw = record(value);
  const items = Array.isArray(raw.workspaces) ? raw.workspaces : [];
  const workspaces: WorkspaceSummary[] = items.map((item) => {
    const data = record(item);
    const path = typeof item === "string" ? item : String(data.path || data.workspace || "");
    return { path, label: String(data.name || path.split("/").filter(Boolean).at(-1) || path) };
  }).filter((item) => item.path);
  return { workspaces, terminalRemoteBackend: Boolean(raw.terminal_remote_backend) };
}

export function translateWorkspaceEntries(value: unknown): WorkspaceEntry[] {
  const raw = record(value);
  return (Array.isArray(raw.entries) ? raw.entries : []).map((value) => {
    const item = record(value);
    const rawKind = String(item.type || item.kind || "other").toLowerCase();
    const kind: WorkspaceEntry["kind"] = rawKind === "dir" || rawKind === "directory" || item.is_dir === true ? "directory" : rawKind === "file" ? "file" : "other";
    return {
      name: String(item.name || item.path || ""),
      path: String(item.path || item.name || ""),
      kind,
      size: typeof item.size === "number" ? item.size : undefined,
    };
  }).filter((item) => item.name);
}

export function translateAgentHealth(value: unknown): AgentHealth {
  const raw = record(value);
  if (raw.alive === true) return { availability: "available", detail: "Assistant runtime is responding." };
  if (raw.alive === false) return { availability: "unavailable", detail: "The configured assistant runtime is not running." };
  return { availability: "unknown", detail: "No separate assistant runtime is currently reported." };
}

export function translateTools(value: unknown): ToolInventory {
  const raw = record(value);
  const tools = Array.isArray(raw.tools) ? raw.tools : [];
  return {
    total: Number(raw.total || tools.length || 0),
    names: tools.map((value) => String(record(value).name || "")).filter(Boolean),
    unavailableServers: Array.isArray(raw.unavailable_servers) ? raw.unavailable_servers.map(String) : [],
  };
}

function translateBreakdownRow(value: unknown, keyField: "model" | "provider"): UsageBreakdownRow {
  const raw = record(value);
  return {
    key: String(raw[keyField] || "unknown"),
    sessions: Number(raw.sessions || 0),
    inputTokens: Number(raw.input_tokens || 0),
    outputTokens: Number(raw.output_tokens || 0),
    totalTokens: Number(raw.total_tokens || 0),
    cacheReadTokens: Number(raw.cache_read_tokens || 0),
    cacheHitPercent: typeof raw.cache_hit_percent === "number" ? raw.cache_hit_percent : null,
    cost: Number(raw.cost || 0),
    sessionShare: Number(raw.session_share || 0),
    tokenShare: Number(raw.token_share || 0),
    costShare: Number(raw.cost_share || 0),
    durationSeconds: Number(raw.duration_seconds || 0),
    averageDurationSeconds: Number(raw.average_duration_seconds || 0),
  };
}

function translateDailyPoint(value: unknown): UsageDailyPoint {
  const raw = record(value);
  return {
    date: String(raw.date || ""),
    inputTokens: Number(raw.input_tokens || 0),
    outputTokens: Number(raw.output_tokens || 0),
    cacheReadTokens: Number(raw.cache_read_tokens || 0),
    sessions: Number(raw.sessions || 0),
    cost: Number(raw.cost || 0),
    durationSeconds: Number(raw.duration_seconds || 0),
  };
}

export function translateInsights(value: unknown): UsageInsights {
  const raw = record(value);
  return {
    periodDays: Number(raw.period_days || 30),
    totalSessions: Number(raw.total_sessions || 0),
    totalMessages: Number(raw.total_messages || 0),
    totalInputTokens: Number(raw.total_input_tokens || 0),
    totalOutputTokens: Number(raw.total_output_tokens || 0),
    totalTokens: Number(raw.total_tokens || 0),
    totalCacheReadTokens: Number(raw.total_cache_read_tokens || 0),
    totalCacheHitPercent: typeof raw.total_cache_hit_percent === "number" ? raw.total_cache_hit_percent : null,
    totalCost: Number(raw.total_cost || 0),
    totalDurationSeconds: Number(raw.total_duration_seconds || 0),
    averageSessionDurationSeconds: Number(raw.average_session_duration_seconds || 0),
    models: (Array.isArray(raw.models) ? raw.models : []).map((row) => translateBreakdownRow(row, "model")),
    providers: (Array.isArray(raw.providers) ? raw.providers : []).map((row) => translateBreakdownRow(row, "provider")),
    dailyTokens: (Array.isArray(raw.daily_tokens) ? raw.daily_tokens : []).map(translateDailyPoint),
  };
}

export function translateConnections(value: unknown): RuntimeConnection[] {
  const raw = record(value);
  return (Array.isArray(raw.connections) ? raw.connections : []).map((value) => {
    const item = record(value);
    const health = record(item.health);
    const rawState = String(health.state || "offline");
    const state: RuntimeConnection["state"] = rawState === "connected"
      ? "connected"
      : rawState === "needs_attention"
        ? "needs_attention"
        : "offline";
    return {
      id: String(item.id || ""),
      name: String(item.name || item.id || "Connection"),
      kind: String(item.kind || "runtime"),
      selected: Boolean(item.selected),
      state,
      available: Boolean(health.available),
      detail: String(health.message || "Connection status is unavailable."),
      capabilities: Array.isArray(item.capabilities) ? item.capabilities.map(String) : [],
    };
  }).filter((connection) => connection.id);
}

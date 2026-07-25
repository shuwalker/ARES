import { apiFetch } from "@/shared/api-client";
import type { BackendInfo } from "@/shared/contracts";
import {
  translateAgentHealth,
  translateConnections,
  translateConversation,
  translateInsights,
  translateSessions,
  translateSettings,
  translateTools,
  translateWorkerRankings,
  translateWorkspaceEntries,
  translateWorkspaces,
} from "@/shared/translators";

// ── Session search result ─────────────────────────────────────────────
export interface SessionSearchResult {
  session_id: string;
  title: string;
  profile?: string;
  score?: number;
  snippet?: string;
  created_at?: string;
  updated_at?: string;
  message_count?: number;
}

// ── Profile types ────────────────────────────────────────────────────
export interface ProfileInfo {
  name: string;
  display_name?: string;
  is_default?: boolean;
  is_active?: boolean;
  path?: string;
  default_workspace?: string;
}

export interface ProfilesResponse {
  profiles: ProfileInfo[];
  active: string;
  single_profile_mode?: boolean;
}

export interface ProfileCreatePayload {
  name: string;
  clone_from?: string;
  clone_config?: boolean;
  base_url?: string;
  api_key?: string;
  default_model?: string;
  model_provider?: string;
}

// ── Model types ──────────────────────────────────────────────────────
export interface ModelEntry {
  id: string;
  name?: string;
  provider?: string;
  available?: boolean;
  owned?: boolean;
  context_window?: number;
  max_output_tokens?: number;
  reasoning?: boolean;
  vision?: boolean;
}

export interface ModelCatalog {
  models: ModelEntry[];
  default_model?: string;
  default_provider?: string;
}

// ── System health ───────────────────────────────────────────────────
export interface SystemHealth {
  status: string;
  uptime_seconds?: number;
  version?: string;
  cpu_percent?: number;
  memory_percent?: number;
  disk_percent?: number;
  checks?: Record<string, { status: string; detail?: string }>;
}

// ── Schedule types ──────────────────────────────────────────────────
export interface ScheduleEntry {
  job_id: string;
  name?: string;
  schedule: string;
  enabled?: boolean;
  last_run_at?: string;
  next_run_at?: string;
  prompt?: string;
  deliver?: string;
  model?: string;
  provider?: string;
  profile?: string;
  status?: string;
}

export interface ScheduleCreatePayload {
  prompt: string;
  schedule: string;
  name?: string;
  deliver?: string;
  skills?: string[];
  model?: string;
  provider?: string;
  profile?: string;
  toast_notifications?: boolean;
}

export interface ScheduleUpdatePayload {
  job_id: string;
  prompt?: string;
  schedule?: string;
  name?: string;
  deliver?: string;
  skills?: string[];
  model?: string;
  provider?: string;
  profile?: string;
  toast_notifications?: boolean;
}

// ── Webhook types ───────────────────────────────────────────────────
export interface WebhookEntry {
  id: string;
  name: string;
  url: string;
  event?: string;
  enabled?: boolean;
  secret?: string;
}

// ── Pairing types ───────────────────────────────────────────────────
export interface PairingEntry {
  id: string;
  name: string;
  kind: string;
  status: "pending" | "approved" | "revoked";
  created_at: string;
}

// ── MCP server types ────────────────────────────────────────────────
export interface McpServerEntry {
  name: string;
  transport?: "stdio" | "http" | "invalid";
  command?: string;
  url?: string;
  args?: string[];
  env?: Record<string, string>;
  headers?: Record<string, string>;
  enabled?: boolean;
  active?: boolean;
  status?: string;
  description?: string;
  tool_count?: number | null;
  timeout?: number;
  connect_timeout?: number;
}

// ── Env types ───────────────────────────────────────────────────────
export interface EnvResponse {
  variables: Record<string, string>;
  order: string[];
}

// ── Config validation ────────────────────────────────────────────────
export interface ConfigValidationResult {
  valid: boolean;
  errors?: string[];
  warnings?: string[];
}

export const aresApi = {
  // ══════════════════════════════════════════════════════════════════
  // Auth
  // ══════════════════════════════════════════════════════════════════
  async authStatus() {
    const payload = await apiFetch<Record<string, unknown>>("/api/auth/status");
    return {
      authEnabled: Boolean(payload.auth_enabled),
      loggedIn: Boolean(payload.logged_in),
      passwordAuthEnabled: Boolean(payload.password_auth_enabled),
      oidcEnabled: Boolean(payload.oidc_enabled),
      passkeysEnabled: Boolean(payload.passkeys_enabled),
      passwordlessEnabled: Boolean(payload.passwordless_enabled),
      trustedAuthEnabled: Boolean(payload.trusted_auth_enabled),
    };
  },
  async login(password: string) {
    return apiFetch<{ ok: boolean }>("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ password }),
    });
  },
  async passkeyOptions() {
    return apiFetch<{ ok: boolean; publicKey: Record<string, unknown> }>("/api/auth/passkey/options", { method: "POST", body: "{}" });
  },
  async passkeyLogin(payload: Record<string, unknown>) {
    return apiFetch<{ ok: boolean }>("/api/auth/passkey/login", { method: "POST", body: JSON.stringify(payload) });
  },

  // ══════════════════════════════════════════════════════════════════
  // Health / Agent
  // ══════════════════════════════════════════════════════════════════
  async health() {
    return apiFetch<Record<string, unknown>>("/health");
  },
  async agentHealth() {
    return translateAgentHealth(await apiFetch("/api/health/agent"));
  },

  // ══════════════════════════════════════════════════════════════════
  // Settings
  // ══════════════════════════════════════════════════════════════════
  async settings() {
    return translateSettings(await apiFetch("/api/settings"));
  },
  async saveAssistantName(assistantName: string) {
    return translateSettings(await apiFetch("/api/settings", {
      method: "POST",
      body: JSON.stringify({ bot_name: assistantName }),
    }));
  },
  async settingsGet() {
    return apiFetch<Record<string, unknown>>("/api/settings");
  },
  async settingsPost(payload: Record<string, unknown>) {
    return apiFetch<Record<string, unknown>>("/api/settings", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  async productStateGet<T extends object>(module: string) {
    return apiFetch<{ module: string; revision: number; state: T }>(
      `/api/product-state/${encodeURIComponent(module)}`,
    );
  },
  async productStatePut<T extends object>(module: string, state: T, expectedRevision?: number) {
    return apiFetch<{ module: string; revision: number; state: T }>(
      `/api/product-state/${encodeURIComponent(module)}`,
      {
        method: "PUT",
        body: JSON.stringify({ state, expected_revision: expectedRevision }),
      },
    );
  },

  // ══════════════════════════════════════════════════════════════════
  // Sessions
  // ══════════════════════════════════════════════════════════════════
  async sessions() {
    return translateSessions(await apiFetch("/api/sessions?exclude_hidden=1"));
  },
  async session(sessionId: string) {
    const payload = await apiFetch<Record<string, unknown>>(`/api/session?session_id=${encodeURIComponent(sessionId)}&messages=1&msg_limit=200`);
    return translateConversation(payload.session);
  },
  async createSession(input: { workspace?: string; profile?: string; previousSessionId?: string } = {}) {
    const payload = await apiFetch<Record<string, unknown>>("/api/session/new", {
      method: "POST",
      body: JSON.stringify({
        workspace: input.workspace || undefined,
        profile: input.profile || undefined,
        prev_session_id: input.previousSessionId || undefined,
      }),
    });
    return translateConversation(payload.session);
  },
  async startChat(sessionId: string, message: string, session: { model?: string; provider?: string; workspace?: string; profile?: string; backendId?: string }, backendId?: string) {
    return apiFetch<{ stream_id: string; session_id: string; title?: string }>("/api/chat/start", {
      method: "POST",
      body: JSON.stringify({
        session_id: sessionId,
        message,
        model: session.model || undefined,
        model_provider: session.provider || undefined,
        connection_id: backendId || session.backendId || undefined,
        workspace: session.workspace || undefined,
        profile: session.profile || "default",
      }),
    });
  },
  async streamStatus(streamId: string) {
    return apiFetch<{ active: boolean; replay_available: boolean }>(`/api/chat/stream/status?stream_id=${encodeURIComponent(streamId)}`);
  },
  async cancelChat(streamId: string) {
    return apiFetch(`/api/chat/cancel?stream_id=${encodeURIComponent(streamId)}`, { method: "POST" });
  },

  // ── Session mutations ────────────────────────────────────────────
  async searchSessions(query: string, options?: { content?: boolean; depth?: number; allProfiles?: boolean }) {
    const params = new URLSearchParams({ q: query });
    if (options?.content !== undefined) params.set("content", String(options.content));
    if (options?.depth !== undefined) params.set("depth", String(options.depth));
    if (options?.allProfiles) params.set("all_profiles", "true");
    return apiFetch<SessionSearchResult[]>(`/api/sessions/search?${params.toString()}`);
  },

  async deleteSession(sessionId: string) {
    return apiFetch<{ ok: boolean }>("/api/session/delete", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId }),
    });
  },

  async exportSession(sessionId: string, format: "json" | "html" = "json", options?: { theme?: string; palette?: string }) {
    const params = new URLSearchParams({ session_id: sessionId, format });
    if (options?.theme) params.set("theme", options.theme);
    if (options?.palette) params.set("palette", options.palette);
    return apiFetch<string>(`/api/session/export?${params.toString()}`);
  },

  async archiveSession(sessionId: string, archived: boolean) {
    return apiFetch<{ ok: boolean; session: Record<string, unknown> }>("/api/session/archive", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, archived }),
    });
  },

  async pinSession(sessionId: string, pinned: boolean) {
    return apiFetch<{ ok: boolean; session: Record<string, unknown> }>("/api/session/pin", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, pinned }),
    });
  },

  async renameSession(sessionId: string, title: string) {
    return apiFetch<{ session: Record<string, unknown> }>("/api/session/rename", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, title }),
    });
  },

  async duplicateSession(sessionId: string) {
    return apiFetch<{ session: Record<string, unknown> }>("/api/session/duplicate", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId }),
    });
  },
  async createShare(sessionId: string) {
    return apiFetch<{ ok: boolean; share: { token: string; url: string; title: string; message_count: number } }>("/api/share/create", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId }),
    });
  },
  async revokeShare(sessionId: string) {
    return apiFetch<{ ok: boolean }>("/api/share/revoke", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId }),
    });
  },

  async truncateSession(sessionId: string, keepCount: number) {
    return apiFetch<{ ok: boolean; session: Record<string, unknown> }>("/api/session/truncate", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, keep_count: keepCount }),
    });
  },

  async branchSession(sessionId: string, options?: { keepCount?: number; title?: string }) {
    return apiFetch<{ session_id: string; title: string; parent_session_id: string }>("/api/session/branch", {
      method: "POST",
      body: JSON.stringify({
        session_id: sessionId,
        keep_count: options?.keepCount,
        title: options?.title,
      }),
    });
  },

  async sessionStatus(sessionId: string) {
    return apiFetch<Record<string, unknown>>(`/api/session/status?session_id=${encodeURIComponent(sessionId)}`);
  },

  async sessionUsage(sessionId: string) {
    return apiFetch<Record<string, unknown>>(`/api/session/usage?session_id=${encodeURIComponent(sessionId)}`);
  },

  async cleanupSessions() {
    return apiFetch<Record<string, unknown>>("/api/sessions/cleanup", { method: "POST" });
  },

  async updateSession(sessionId: string, updates: { workspace?: string; model?: string; model_provider?: string }) {
    return apiFetch<{ session: Record<string, unknown> }>("/api/session/update", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, ...updates }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Skills
  // ══════════════════════════════════════════════════════════════════
  async skillsList(category?: string) {
    const params = category ? `?category=${encodeURIComponent(category)}` : "";
    return apiFetch<{ skills: Array<{ name: string; description: string; category: string | null; disabled: boolean }>; skill_runtime_available: boolean }>(`/api/skills${params}`);
  },

  async skillsGet(name: string, file?: string) {
    const params = new URLSearchParams({ name });
    if (file) params.set("file", file);
    return apiFetch<{ name: string; content: string; category: string; disabled: boolean }>(`/api/skills/content?${params.toString()}`);
  },

  async skillsCreate(input: { name: string; content: string; category?: string }) {
    return apiFetch<{ ok: boolean }>("/api/skills/save", {
      method: "POST",
      body: JSON.stringify(input),
    });
  },

  async skillsUpdate(name: string, content: string, category?: string) {
    return apiFetch<{ ok: boolean }>("/api/skills/save", {
      method: "POST",
      body: JSON.stringify({ name, content, category }),
    });
  },

  async skillsDelete(name: string) {
    return apiFetch<{ ok: boolean }>("/api/skills/delete", {
      method: "POST",
      body: JSON.stringify({ name }),
    });
  },

  async skillsToggle(name: string, enabled: boolean) {
    return apiFetch<{ ok: boolean }>("/api/skills/toggle", {
      method: "POST",
      body: JSON.stringify({ name, enabled }),
    });
  },

  async skillsUsage() {
    return apiFetch<{ skills: SkillUsageEntry[] }>("/api/skills/usage");
  },

  async skillsContent(name: string) {
    return apiFetch<{ name: string; content: string; category: string; disabled: boolean }>("/api/skills/content", {
      method: "POST",
      body: JSON.stringify({ name }),
    });
  },

  async skillsSave(name: string, content: string, category?: string) {
    return apiFetch<{ ok: boolean }>("/api/skills/save", {
      method: "POST",
      body: JSON.stringify({ name, content, category }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Profiles
  // ══════════════════════════════════════════════════════════════════
  async profilesList() {
    return apiFetch<ProfilesResponse>("/api/profiles");
  },

  async profileActive() {
    return apiFetch<{ name: string; path: string; is_default: boolean; default_workspace: string | null }>("/api/profile/active");
  },

  async profileCreate(payload: ProfileCreatePayload) {
    return apiFetch<{ ok: boolean; profile: Record<string, unknown> }>("/api/profile/create", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  async profileDelete(name: string) {
    return apiFetch<{ ok: boolean }>("/api/profile/delete", {
      method: "POST",
      body: JSON.stringify({ name }),
    });
  },

  async profileSwitch(name: string) {
    return apiFetch<{ ok: boolean; profile?: string }>("/api/profile/switch", {
      method: "POST",
      body: JSON.stringify({ name }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Models
  // ══════════════════════════════════════════════════════════════════
  async models(freshness?: string) {
    const params = freshness ? `?freshness=${encodeURIComponent(freshness)}` : "";
    return apiFetch<ModelCatalog>(`/api/models${params}`);
  },

  async modelsLive(provider: string) {
    return apiFetch<Record<string, unknown>[]>(`/api/models/live?provider=${encodeURIComponent(provider)}`);
  },

  async modelsReload(provider: string) {
    return apiFetch<{ ok: boolean; provider: string }>("/api/models/refresh", {
      method: "POST",
      body: JSON.stringify({ provider }),
    });
  },

  async modelsTestConnection(provider: string, apiKey?: string, baseUrl?: string) {
    return apiFetch<Record<string, unknown>>("/api/providers", {
      method: "POST",
      body: JSON.stringify({
        provider,
        api_key: apiKey || undefined,
        ...(baseUrl ? { base_url: baseUrl } : {}),
      }),
    });
  },

  async setDefaultModel(model: string, provider?: string, advanced?: Record<string, unknown>) {
    return apiFetch<Record<string, unknown>>("/api/default-model", {
      method: "POST",
      body: JSON.stringify({ model, provider: provider || "auto", advanced }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // System
  // ══════════════════════════════════════════════════════════════════
  async systemInfo() {
    return apiFetch<SystemHealth>("/api/system/health");
  },

  async systemHealth() {
    return apiFetch<Record<string, unknown>>("/health");
  },

  async restartGateway() {
    return apiFetch<{ ok: boolean; message: string }>("/api/health/restart", { method: "POST" });
  },

  async shutdown() {
    return apiFetch<{ status: string }>("/api/shutdown", { method: "POST" });
  },

  async adminReload() {
    return apiFetch<{ status: string; reloaded: string }>("/api/admin/reload", { method: "POST" });
  },

  // ══════════════════════════════════════════════════════════════════
  // Schedules (Crons)
  // ══════════════════════════════════════════════════════════════════
  async schedules(allProfiles = false) {
    return apiFetch<{ schedules: ScheduleEntry[] }>(`/api/crons?all_profiles=${allProfiles ? "1" : "0"}`);
  },

  async scheduleStatus(jobId?: string) {
    const params = jobId ? `?job_id=${encodeURIComponent(jobId)}` : "";
    return apiFetch<Record<string, unknown>>(`/api/crons/status${params}`);
  },

  async scheduleCreate(payload: ScheduleCreatePayload) {
    return apiFetch<ScheduleEntry>("/api/crons/create", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  async scheduleUpdate(payload: ScheduleUpdatePayload) {
    return apiFetch<ScheduleEntry>("/api/crons/update", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  async scheduleDelete(jobId: string) {
    return apiFetch<{ ok: boolean }>("/api/crons/delete", {
      method: "POST",
      body: JSON.stringify({ job_id: jobId }),
    });
  },

  async scheduleRun(jobId: string) {
    return apiFetch<{ ok: boolean; run_id?: string }>("/api/crons/run", {
      method: "POST",
      body: JSON.stringify({ job_id: jobId }),
    });
  },

  async schedulePause(jobId: string, reason?: string) {
    return apiFetch<{ ok: boolean }>("/api/crons/pause", {
      method: "POST",
      body: JSON.stringify({ job_id: jobId, reason }),
    });
  },

  async scheduleResume(jobId: string) {
    return apiFetch<{ ok: boolean }>("/api/crons/resume", {
      method: "POST",
      body: JSON.stringify({ job_id: jobId }),
    });
  },

  async scheduleHistory(jobId: string, offset = 0, limit = 50) {
    return apiFetch<Record<string, unknown>>(`/api/crons/history?job_id=${encodeURIComponent(jobId)}&offset=${offset}&limit=${limit}`);
  },

  async scheduleOutput(jobId: string, limit = 5) {
    return apiFetch<Record<string, unknown>>(`/api/crons/output?job_id=${encodeURIComponent(jobId)}&limit=${limit}`);
  },

  async scheduleDeliveryOptions() {
    return apiFetch<Record<string, unknown>>("/api/crons/delivery-options");
  },

  // ══════════════════════════════════════════════════════════════════
  // Webhooks
  // ══════════════════════════════════════════════════════════════════
  async webhooksList() {
    return apiFetch<WebhookEntry[]>("/api/gateway/webhooks");
  },

  async webhookCreate(entry: Omit<WebhookEntry, "id">) {
    return apiFetch<WebhookEntry>("/api/gateway/webhooks", {
      method: "POST",
      body: JSON.stringify(entry),
    });
  },

  async webhookUpdate(webhookId: string, updates: Partial<WebhookEntry>) {
    return apiFetch<WebhookEntry>(`/api/gateway/webhooks/${encodeURIComponent(webhookId)}`, {
      method: "PATCH",
      body: JSON.stringify(updates),
    });
  },

  async webhookDelete(id: string) {
    return apiFetch<WebhookEntry[]>("/api/gateway/webhooks", {
      method: "DELETE",
      body: JSON.stringify({ id }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Pairing
  // ══════════════════════════════════════════════════════════════════
  async pairingList() {
    return apiFetch<PairingEntry[]>("/api/connections/pairing");
  },

  async pairingCreate(entry: { name: string; kind?: string }) {
    return apiFetch<PairingEntry>("/api/connections/pairing/create", {
      method: "POST",
      body: JSON.stringify(entry),
    });
  },

  async pairingApprove(id: string) {
    return apiFetch<PairingEntry[]>("/api/connections/pairing/approve", {
      method: "POST",
      body: JSON.stringify({ id }),
    });
  },

  async pairingRevoke(id: string) {
    return apiFetch<PairingEntry[]>("/api/connections/pairing/revoke", {
      method: "POST",
      body: JSON.stringify({ id }),
    });
  },

  async pairingClear() {
    return apiFetch<PairingEntry[]>("/api/connections/pairing/clear", {
      method: "POST",
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // MCP
  // ══════════════════════════════════════════════════════════════════
  async mcpList() {
    return apiFetch<{ servers: McpServerEntry[]; toggle_supported: boolean; reload_required: boolean }>("/api/mcp/servers");
  },

  async mcpUpdate(name: string, config: Record<string, unknown>) {
    return apiFetch<Record<string, unknown>>(`/api/mcp/servers/${encodeURIComponent(name)}`, {
      method: "PUT",
      body: JSON.stringify(config),
    });
  },

  async mcpToggle(name: string, enabled: boolean) {
    return apiFetch<Record<string, unknown>>(`/api/mcp/servers/${encodeURIComponent(name)}`, {
      method: "PATCH",
      body: JSON.stringify({ name, enabled }),
    });
  },

  async mcpDelete(name: string) {
    return apiFetch<{ ok: boolean }>(`/api/mcp/servers/${encodeURIComponent(name)}`, { method: "DELETE" });
  },

  // ══════════════════════════════════════════════════════════════════
  // Connections / Adapters
  // ══════════════════════════════════════════════════════════════════
  async connectionsList() {
    return translateConnections(await apiFetch("/api/connections"));
  },

  async channelModels(connectionId: string) {
    return apiFetch<Record<string, unknown>>(`/api/connections/${encodeURIComponent(connectionId)}/models`);
  },

  async connectionTest(connectionId: string) {
    return apiFetch<{
      ok: boolean;
      connection_id: string;
      health: { state: string; available: boolean; message: string; details: Record<string, unknown> };
      capabilities: string[];
    }>(`/api/connections/${encodeURIComponent(connectionId)}/test`);
  },

  /** Companion technical intelligence: worker effectiveness leaderboard. */
  async workerRankings() {
    return translateWorkerRankings(await apiFetch("/api/workers/rankings"));
  },

  async recordWorkerEvaluation(payload: {
    workerId: string;
    metrics: Record<string, number>;
    sessionId?: string;
    taskKind?: string;
    notes?: string;
  }) {
    return apiFetch<{ ok: boolean; evaluation: Record<string, unknown> }>("/api/workers/evaluations", {
      method: "POST",
      body: JSON.stringify({
        worker_id: payload.workerId,
        metrics: payload.metrics,
        session_id: payload.sessionId,
        task_kind: payload.taskKind,
        notes: payload.notes,
      }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Environment Variables (scoped)
  // ══════════════════════════════════════════════════════════════════
  async envList() {
    return apiFetch<EnvResponse>("/api/env");
  },

  async envReveal(key: string) {
    return apiFetch<{ key: string; value: string }>(`/api/env/${encodeURIComponent(key)}/reveal`);
  },

  async envSet(key: string, value: string) {
    return apiFetch<EnvResponse>("/api/env", {
      method: "POST",
      body: JSON.stringify({ key, value }),
    });
  },

  async envDelete(key: string) {
    return apiFetch<EnvResponse>("/api/env", {
      method: "DELETE",
      body: JSON.stringify({ key }),
    });
  },

  async envReorder(order: string[]) {
    return apiFetch<EnvResponse>("/api/env/reorder", {
      method: "POST",
      body: JSON.stringify(order),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Secrets (scoped)
  // ══════════════════════════════════════════════════════════════════
  async secrets() {
    return apiFetch<SecretEntry[]>("/api/secrets");
  },

  async secretGetByKey(key: string) {
    return apiFetch<SecretEntry>(`/api/secrets/by-key/${encodeURIComponent(key)}`);
  },

  async saveSecret(key: string, value: string) {
    return apiFetch<SecretEntry>("/api/secrets", {
      method: "POST",
      body: JSON.stringify({ key, value }),
    });
  },

  async updateSecret(secretId: string, updates: Partial<{ name: string; key: string; value: string; description: string; provider: string; status: string }>) {
    return apiFetch<SecretEntry>(`/api/secrets/${encodeURIComponent(secretId)}`, {
      method: "PATCH",
      body: JSON.stringify(updates),
    });
  },

  async deleteSecret(key: string) {
    return apiFetch<SecretEntry[]>("/api/secrets", {
      method: "DELETE",
      body: JSON.stringify({ key }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Config
  // ══════════════════════════════════════════════════════════════════
  async configGet() {
    return apiFetch<Record<string, unknown>>("/api/settings");
  },

  async configSave(payload: Record<string, unknown>) {
    return apiFetch<Record<string, unknown>>("/api/settings", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  async configValidate(payload: Record<string, unknown>) {
    const result = await apiFetch<Record<string, unknown>>("/api/settings", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    const errors = Array.isArray(result.errors) ? result.errors : [];
    const warnings = Array.isArray(result.warnings) ? result.warnings : [];
    return { valid: errors.length === 0, errors, warnings } as ConfigValidationResult;
  },

  // ══════════════════════════════════════════════════════════════════
  // Workspaces & Files
  // ══════════════════════════════════════════════════════════════════
  async workspaces() {
    return translateWorkspaces(await apiFetch("/api/workspaces"));
  },
  async listWorkspace(sessionId: string, path = ".") {
    return translateWorkspaceEntries(await apiFetch(`/api/list?session_id=${encodeURIComponent(sessionId)}&path=${encodeURIComponent(path)}`));
  },
  async readFile(sessionId: string, path: string) {
    const payload = await apiFetch<{ content?: string } | string>(`/api/file?session_id=${encodeURIComponent(sessionId)}&path=${encodeURIComponent(path)}`);
    if (typeof payload === "string") return payload;
    return payload.content || "";
  },
  async saveFile(sessionId: string, path: string, content: string) {
    return apiFetch<{ ok: boolean }>("/api/file/save", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, path, content }),
    });
  },
  async createFile(sessionId: string, path: string, content = "") {
    return apiFetch<{ ok: boolean }>("/api/file/create", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, path, content }),
    });
  },
  async createDirectory(sessionId: string, path: string) {
    return apiFetch<{ ok: boolean }>("/api/file/create-dir", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, path }),
    });
  },
  async deleteFile(sessionId: string, path: string, recursive = false) {
    return apiFetch<{ ok: boolean }>("/api/file/delete", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, path, recursive }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Tools & Connections
  // ══════════════════════════════════════════════════════════════════
  async tools() {
    return translateTools(await apiFetch("/api/mcp/tools"));
  },
  async connections() {
    return translateConnections(await apiFetch("/api/connections"));
  },
  async setDefaultBackend(backend: string) {
    return apiFetch<{ ok: boolean; backend: string }>("/api/ares/backend/set", {
      method: "POST",
      body: JSON.stringify({ backend }),
    });
  },
  async backends() {
    const payload = await apiFetch<{ backends: BackendInfo[] }>("/api/backends");
    return payload.backends ?? [];
  },

  async listAdapters() {
    return apiFetch<Record<string, Record<string, unknown>>>("/api/ares/adapters");
  },

  // ══════════════════════════════════════════════════════════════════
  // Insights
  // ══════════════════════════════════════════════════════════════════
  async insights(days = 30) {
    return translateInsights(await apiFetch(`/api/insights?days=${encodeURIComponent(String(days))}`));
  },

  // ══════════════════════════════════════════════════════════════════
  // Terminal
  // ══════════════════════════════════════════════════════════════════
  async startTerminal(sessionId: string, restart = false) {
    return apiFetch<{ ok: boolean; workspace: string; running: boolean }>("/api/terminal/start", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, rows: 28, cols: 100, restart }),
    });
  },
  async terminalInput(sessionId: string, data: string) {
    return apiFetch("/api/terminal/input", { method: "POST", body: JSON.stringify({ session_id: sessionId, data }) });
  },
  async terminalResize(sessionId: string, rows: number, cols: number) {
    return apiFetch("/api/terminal/resize", { method: "POST", body: JSON.stringify({ session_id: sessionId, rows, cols }) });
  },
  async closeTerminal(sessionId: string) {
    return apiFetch("/api/terminal/close", { method: "POST", body: JSON.stringify({ session_id: sessionId }) });
  },

  // ══════════════════════════════════════════════════════════════════
  // Approval / Inbox
  // ══════════════════════════════════════════════════════════════════
  async approvalPending() {
    const sessions = await this.sessions();
    const snapshots = await Promise.all(sessions.map(async (session) => {
      const result = await apiFetch<{ pending: Record<string, unknown> | null }>(
        `/api/approval/pending?session_id=${encodeURIComponent(session.id)}`,
      );
      if (!result.pending) return null;
      const item = result.pending;
      return {
        id: String(item.approval_id ?? item.id ?? ""),
        session_id: session.id,
        type: String(item.type ?? (item.command ? "execution" : "tool_use")),
        status: "pending" as const,
        subject: String(item.description ?? item.command ?? item.tool ?? "Approval required"),
        detail: String(item.command ?? item.reason ?? item.description ?? "Your Companion is waiting for your decision."),
        requested_by: String(item.requested_by ?? session.backendId ?? "companion"),
        created_at: String(item.created_at ?? item.requested_at ?? session.updatedAt ?? new Date().toISOString()),
        payload: item,
      } satisfies ApprovalItem;
    }));
    return { approvals: snapshots.filter((item): item is NonNullable<typeof item> => item !== null) };
  },
  async approvalRespond(sessionId: string, id: string, action: "approve" | "reject") {
    return apiFetch<{ ok: boolean }>("/api/approval/respond", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, approval_id: id, choice: action === "approve" ? "once" : "deny" }),
    });
  },
  async clarifyPending() {
    const sessions = await this.sessions();
    const snapshots = await Promise.all(sessions.map(async (session) => {
      const result = await apiFetch<{ pending: Record<string, unknown> | null }>(
        `/api/clarify/pending?session_id=${encodeURIComponent(session.id)}`,
      );
      if (!result.pending) return null;
      const item = result.pending;
      return {
        id: String(item.clarify_id ?? item.id ?? ""),
        session_id: session.id,
        question: String(item.question ?? "ARES needs more information."),
        context: String(item.context ?? item.reason ?? ""),
        created_at: String(item.created_at ?? item.requested_at ?? session.updatedAt ?? new Date().toISOString()),
      } satisfies ClarifyItem;
    }));
    return { clarifications: snapshots.filter((item): item is NonNullable<typeof item> => item !== null) };
  },
  async clarifyRespond(sessionId: string, id: string, response: string) {
    return apiFetch<{ ok: boolean }>("/api/clarify/respond", {
      method: "POST",
      body: JSON.stringify({ session_id: sessionId, clarify_id: id, response }),
    });
  },
  async emailUnread() {
    return apiFetch<{ count: number }>("/api/email/unread");
  },
  async emailAll() {
    const result = await apiFetch<{ messages?: Record<string, unknown>[] }>("/api/email/all?limit=50", {
      signal: AbortSignal.timeout(15_000),
    });
    return { emails: (result.messages ?? []).map(translateEmailItem) };
  },

  // ══════════════════════════════════════════════════════════════════
  // Kanban / Issues
  // ══════════════════════════════════════════════════════════════════
  async kanbanBoards() {
    return apiFetch<{ boards: KanbanBoard[] }>("/api/kanban/boards");
  },
  async kanbanBoard(boardId: string) {
    return apiFetch<KanbanBoard>(`/api/kanban/board?board_id=${encodeURIComponent(boardId)}`);
  },
  async kanbanTasks(boardId: string) {
    return apiFetch<{ tasks: KanbanTask[] }>(`/api/kanban/tasks?board_id=${encodeURIComponent(boardId)}`);
  },
  async kanbanTaskAction(taskId: string, action: "move" | "update" | "delete", payload: Record<string, unknown> = {}) {
    return apiFetch<{ ok: boolean }>(`/api/kanban/tasks/${encodeURIComponent(taskId)}/${action}`, {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // Providers
  // ══════════════════════════════════════════════════════════════════
  async providers() {
    return apiFetch<Record<string, unknown>[]>("/api/providers");
  },

  async providerSet(provider: string, apiKey?: string) {
    return apiFetch<{ ok: boolean }>("/api/providers", {
      method: "POST",
      body: JSON.stringify({ provider, api_key: apiKey }),
    });
  },

  async providerDelete(provider: string) {
    return apiFetch<{ ok: boolean }>("/api/providers/delete", {
      method: "POST",
      body: JSON.stringify({ provider }),
    });
  },

  async providerQuota(provider?: string, refresh = false) {
    const params = new URLSearchParams();
    if (provider) params.set("provider", provider);
    if (refresh) params.set("refresh", "true");
    return apiFetch<Record<string, unknown>>(`/api/provider/quota?${params.toString()}`);
  },

  async providerCostHistory(provider?: string, days = 7) {
    const params = new URLSearchParams();
    if (provider) params.set("provider", provider);
    params.set("days", String(days));
    return apiFetch<Record<string, unknown>>(`/api/provider/cost-history?${params.toString()}`);
  },

  // ══════════════════════════════════════════════════════════════════
  // Gateway
  // ══════════════════════════════════════════════════════════════════
  async gatewayStatus() {
    return apiFetch<Record<string, unknown>>("/api/gateway/status");
  },
};

// ── Type declarations for API responses ───────────────────────────────

export interface SecretEntry {
  id: string;
  name: string;
  key: string;
  value?: string;
  value_preview?: string;
  provider: string;
  status: "active" | "disabled" | "archived" | "deleted";
  description?: string;
  created_at?: string;
  updated_at?: string;
}

export interface ApprovalItem {
  id: string;
  session_id: string;
  type: string;
  status: "pending" | "approved" | "rejected" | "revision_requested";
  subject: string;
  detail: string;
  requested_by: string;
  created_at: string;
  payload: Record<string, unknown>;
}

export interface ClarifyItem {
  id: string;
  question: string;
  context: string;
  created_at: string;
  session_id?: string;
}

export interface EmailItem {
  id: string;
  from: string;
  subject: string;
  snippet: string;
  date: string;
  read: boolean;
}

export function translateEmailItem(raw: Record<string, unknown>): EmailItem {
  return {
    id: String(raw.id ?? ""),
    from: String(raw.from ?? raw.sender ?? "Unknown sender"),
    subject: String(raw.subject ?? "(No subject)"),
    snippet: String(raw.snippet ?? raw.body_text ?? ""),
    date: String(raw.date ?? raw.date_received ?? ""),
    read: Boolean(raw.read ?? raw.is_read),
  };
}

export interface KanbanBoard {
  id: string;
  name: string;
  description?: string;
  columns: KanbanColumn[];
}

export interface KanbanColumn {
  id: string;
  name: string;
  order: number;
}

export interface KanbanTask {
  id: string;
  board_id: string;
  column_id: string;
  title: string;
  description: string;
  status: "open" | "in_progress" | "done" | "cancelled";
  priority: "low" | "medium" | "high" | "critical";
  assigned_to?: string;
  created_at: string;
  updated_at: string;
}

export interface CronRun {
  id: string;
  cron_id: string;
  started_at: string;
  finished_at?: string;
  status: "success" | "failed" | "running";
  output?: string;
}

export interface SkillUsageEntry {
  name: string;
  description: string;
  category: string;
  disabled: boolean;
  usage_count?: number;
  last_used?: string;
}

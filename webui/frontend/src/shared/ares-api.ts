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

// ── MCP server types ────────────────────────────────────────────────
export interface McpServerEntry {
  name: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  enabled?: boolean;
  status?: string;
  description?: string;
  tools_count?: number;
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
    };
  },
  async login(password: string) {
    return apiFetch<{ ok: boolean }>("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ password }),
    });
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
  async createSession(input: { workspace?: string; profile?: string; previousSessionId?: string; model_provider?: string } = {}) {
    const payload = await apiFetch<Record<string, unknown>>("/api/session/new", {
      method: "POST",
      body: JSON.stringify({
        workspace: input.workspace || undefined,
        profile: input.profile || undefined,
        prev_session_id: input.previousSessionId || undefined,
        model_provider: input.model_provider || undefined,
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
        model_provider: backendId || session.backendId || session.provider || undefined,
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
    return apiFetch<Record<string, unknown>[]>(`/api/skills${params}`);
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

  // ── Legacy cron aliases (existing) ──────────────────────────────
  async cronsStatus() {
    return apiFetch<{ crons: CronEntry[] }>("/api/crons/status");
  },
  async cronsRecent(limit = 20) {
    return apiFetch<{ runs: CronRun[] }>("/api/crons/recent", { method: "POST", body: JSON.stringify({ limit }) });
  },
  async cronsCreate(entry: { name: string; schedule: string; prompt: string; enabled?: boolean }) {
    return apiFetch<CronEntry>("/api/crons/create", {
      method: "POST",
      body: JSON.stringify(entry),
    });
  },
  async cronsUpdate(id: string, updates: Partial<{ name: string; schedule: string; prompt: string; enabled: boolean }>) {
    return apiFetch<CronEntry>("/api/crons/update", {
      method: "POST",
      body: JSON.stringify({ id, ...updates }),
    });
  },
  async cronsDelete(id: string) {
    return apiFetch<{ ok: boolean }>("/api/crons/delete", {
      method: "POST",
      body: JSON.stringify({ id }),
    });
  },
  async cronsRun(id: string) {
    return apiFetch<{ ok: boolean; run_id: string }>("/api/crons/run", {
      method: "POST",
      body: JSON.stringify({ id }),
    });
  },
  async cronsPause(id: string) {
    return apiFetch<{ ok: boolean }>("/api/crons/pause", {
      method: "POST",
      body: JSON.stringify({ id }),
    });
  },
  async cronsResume(id: string) {
    return apiFetch<{ ok: boolean }>("/api/crons/resume", {
      method: "POST",
      body: JSON.stringify({ id }),
    });
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

  async webhookTest(name: string) {
    return apiFetch<{ ok: boolean; server: Record<string, unknown> }>(`/api/mcp/servers/${encodeURIComponent(name)}/test`);
  },

  async webhookDelete(id: string) {
    return apiFetch<WebhookEntry[]>("/api/gateway/webhooks", {
      method: "DELETE",
      body: JSON.stringify({ id }),
    });
  },

  // ══════════════════════════════════════════════════════════════════
  // MCP
  // ══════════════════════════════════════════════════════════════════
  async mcpList() {
    return apiFetch<McpServerEntry[]>("/api/mcp/servers");
  },

  async mcpStatus() {
    return this.mcpList();
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

  async mcpRestart(name: string) {
    return apiFetch<{ ok: boolean; server: Record<string, unknown> }>(`/api/mcp/servers/${encodeURIComponent(name)}/test`);
  },

  async mcpDelete(name: string) {
    return apiFetch<{ ok: boolean }>(`/api/mcp/servers/${encodeURIComponent(name)}`, { method: "DELETE" });
  },

  // ══════════════════════════════════════════════════════════════════
  // Channels (Connections / Adapters)
  // ══════════════════════════════════════════════════════════════════
  async channelsList() {
    return translateConnections(await apiFetch("/api/connections"));
  },

  async channelModels(connectionId: string) {
    return apiFetch<Record<string, unknown>>(`/api/connections/${encodeURIComponent(connectionId)}/models`);
  },

  async channelTest(connectionId: string) {
    return apiFetch<Record<string, unknown>>(`/api/connections/${encodeURIComponent(connectionId)}/test`);
  },

  async channelConnect(connectionId: string) {
    return apiFetch<Record<string, unknown>>(`/api/connections/${encodeURIComponent(connectionId)}/connect`, {
      method: "POST",
    });
  },

  async channelDisconnect(connectionId: string) {
    return apiFetch<Record<string, unknown>>(`/api/connections/${encodeURIComponent(connectionId)}/disconnect`, {
      method: "POST",
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
  async backends() {
    const payload = await apiFetch<{ backends: BackendInfo[] }>("/api/backends");
    return payload.backends ?? [];
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
  async closeTerminal(sessionId: string) {
    return apiFetch("/api/terminal/close", { method: "POST", body: JSON.stringify({ session_id: sessionId }) });
  },

  // ══════════════════════════════════════════════════════════════════
  // Approval / Inbox
  // ══════════════════════════════════════════════════════════════════
  async approvalPending() {
    return apiFetch<{ approvals: ApprovalItem[] }>("/api/approval/pending");
  },
  async approvalRespond(id: string, action: "approve" | "reject", note?: string) {
    return apiFetch<{ ok: boolean }>("/api/approval/respond", {
      method: "POST",
      body: JSON.stringify({ id, action, note }),
    });
  },
  async clarifyPending() {
    return apiFetch<{ clarifications: ClarifyItem[] }>("/api/clarify/pending");
  },
  async clarifyRespond(id: string, response: string) {
    return apiFetch<{ ok: boolean }>("/api/clarify/respond", {
      method: "POST",
      body: JSON.stringify({ id, response }),
    });
  },
  async emailUnread() {
    return apiFetch<{ count: number }>("/api/email/unread");
  },
  async emailAll() {
    return apiFetch<{ emails: EmailItem[] }>("/api/email/all");
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
  value: string;
  value_preview?: string;
  provider: string;
  status: "active" | "disabled" | "archived" | "deleted";
  description?: string;
  created_at?: string;
  updated_at?: string;
}

export interface ApprovalItem {
  id: string;
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

export interface CronEntry {
  id: string;
  name: string;
  description?: string;
  schedule: string;
  status: "active" | "paused" | "draft" | "archived";
  enabled: boolean;
  last_run_at?: string;
  next_run_at?: string;
  prompt?: string;
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
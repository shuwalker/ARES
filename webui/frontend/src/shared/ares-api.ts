import { apiFetch } from "@/shared/api-client";
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

export const aresApi = {
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
  async health() {
    return apiFetch<Record<string, unknown>>("/health");
  },
  async agentHealth() {
    return translateAgentHealth(await apiFetch("/api/health/agent"));
  },
  async settings() {
    return translateSettings(await apiFetch("/api/settings"));
  },
  async saveAssistantName(assistantName: string) {
    return translateSettings(await apiFetch("/api/settings", {
      method: "POST",
      body: JSON.stringify({ bot_name: assistantName }),
    }));
  },
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
  async startChat(sessionId: string, message: string, session: { model?: string; provider?: string; workspace?: string; profile?: string }) {
    return apiFetch<{ stream_id: string; session_id: string; title?: string }>("/api/chat/start", {
      method: "POST",
      body: JSON.stringify({
        session_id: sessionId,
        message,
        model: session.model || undefined,
        model_provider: session.provider || undefined,
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
  async workspaces() {
    return translateWorkspaces(await apiFetch("/api/workspaces"));
  },
  async listWorkspace(sessionId: string, path = ".") {
    return translateWorkspaceEntries(await apiFetch(`/api/list?session_id=${encodeURIComponent(sessionId)}&path=${encodeURIComponent(path)}`));
  },
  async tools() {
    return translateTools(await apiFetch("/api/mcp/tools"));
  },
  async connections() {
    return translateConnections(await apiFetch("/api/connections"));
  },
  async insights(days = 30) {
    return translateInsights(await apiFetch(`/api/insights?days=${encodeURIComponent(String(days))}`));
  },
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
};

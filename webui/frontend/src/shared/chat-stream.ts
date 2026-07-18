import { webSocketProtocols, webSocketUrl } from "@/shared/api-client";

export type ChatStreamEvent =
  | { type: "text"; text: string }
  | { type: "reasoning"; text: string }
  | { type: "tool"; label: string; completed: boolean }
  | { type: "warning"; message: string }
  | { type: "done"; session?: unknown }
  | { type: "error"; message: string }
  | { type: "cancelled" }
  | { type: "ended" }
  | { type: "unknown"; name: string; data: unknown };

export type TransportState =
  | { state: "connected" }
  | { state: "reconnecting"; attempt: number }
  | { state: "disconnected" };

interface RealtimeEnvelope {
  event?: string;
  data?: unknown;
  event_id?: string | null;
  stream_id?: string | null;
  session_id?: string | null;
  terminal?: boolean;
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

export function translateChatStreamEvent(name: string, value: unknown): ChatStreamEvent {
  if (typeof value === "string") {
    try { value = JSON.parse(value) as unknown; }
    catch { /* Plain-text runtime events remain useful. */ }
  }
  const data = object(value);
  if (name === "token" || name === "chat_delta") return { type: "text", text: String(data.text || value || "") };
  if (name === "interim_assistant") {
    return data.already_streamed ? { type: "unknown", name, data: value } : { type: "text", text: String(data.text || "") };
  }
  if (name === "reasoning" || name === "reasoning_delta") return { type: "reasoning", text: String(data.text || "") };
  if (["tool", "tool_call", "tool_started", "tool.updated", "tool.started", "tool_complete", "tool_result", "tool.done"].includes(name)) {
    return {
      type: "tool",
      label: String(data.name || data.tool_name || data.tool || "Tool"),
      completed: ["tool_complete", "tool_result", "tool.done"].includes(name),
    };
  }
  if (name === "warning") return { type: "warning", message: String(data.message || value || "Warning") };
  if (name === "done") return { type: "done", session: data.session };
  if (name === "error" || name === "apperror") return { type: "error", message: String(data.error || data.message || value || "The response stream failed.") };
  if (name === "cancel") return { type: "cancelled" };
  if (name === "stream_end") return { type: "ended" };
  return { type: "unknown", name, data: value };
}

const MAX_RECONNECTS = 5;

export function subscribeToChatStream(
  streamId: string,
  onEvent: (event: ChatStreamEvent) => void,
  onTransportState: (state: TransportState) => void,
) {
  let socket: WebSocket | null = null;
  let retryTimer: number | undefined;
  let stopped = false;
  let terminal = false;
  let attempt = 0;
  let lastEventId = "";

  const connect = () => {
    if (stopped) return;
    socket = new WebSocket(
      webSocketUrl("/api/chat/stream", {
        stream_id: streamId,
        after_event_id: lastEventId || undefined,
      }),
      webSocketProtocols(),
    );
    socket.onopen = () => {
      attempt = 0;
      onTransportState({ state: "connected" });
    };
    socket.onmessage = (message) => {
      let envelope: RealtimeEnvelope;
      try { envelope = JSON.parse(String(message.data || "{}")) as RealtimeEnvelope; }
      catch { envelope = { event: "warning", data: { message: "ARES received an unreadable stream event." } }; }
      const name = String(envelope.event || "message");
      if (envelope.event_id) lastEventId = envelope.event_id;
      if (name === "heartbeat") return;
      terminal = Boolean(envelope.terminal) || ["stream_end", "error", "cancel"].includes(name);
      onEvent(translateChatStreamEvent(name, envelope.data));
      if (terminal) socket?.close(1000, "terminal event received");
    };
    socket.onerror = () => socket?.close();
    socket.onclose = () => {
      socket = null;
      if (stopped || terminal) return;
      attempt += 1;
      if (attempt > MAX_RECONNECTS) {
        onTransportState({ state: "disconnected" });
        return;
      }
      onTransportState({ state: "reconnecting", attempt });
      retryTimer = window.setTimeout(connect, Math.min(4000, 250 * 2 ** (attempt - 1)));
    };
  };

  connect();
  return () => {
    stopped = true;
    if (retryTimer !== undefined) window.clearTimeout(retryTimer);
    socket?.close(1000, "client detached");
    socket = null;
  };
}

export interface SessionActivityEvent {
  name: string;
  data: Record<string, unknown>;
}

export function subscribeToSessionActivity(
  sessionId: string,
  onEvent: (event: SessionActivityEvent) => void,
  onDisconnected: () => void,
) {
  let socket: WebSocket | null = null;
  let stopped = false;
  let retryTimer: number | undefined;
  let attempt = 0;

  const connect = () => {
    if (stopped) return;
    socket = new WebSocket(
      webSocketUrl(`/api/sessions/${encodeURIComponent(sessionId)}/stream`),
      webSocketProtocols(),
    );
    socket.onopen = () => { attempt = 0; };
    socket.onmessage = (message) => {
      try {
        const envelope = JSON.parse(String(message.data || "{}")) as RealtimeEnvelope;
        const name = String(envelope.event || "message");
        if (name !== "heartbeat") onEvent({ name, data: object(envelope.data) });
      } catch { /* A malformed observation event must not break the conversation. */ }
    };
    socket.onerror = () => socket?.close();
    socket.onclose = () => {
      socket = null;
      if (stopped) return;
      attempt += 1;
      if (attempt > MAX_RECONNECTS) { onDisconnected(); return; }
      retryTimer = window.setTimeout(connect, Math.min(4000, 500 * 2 ** (attempt - 1)));
    };
  };
  connect();
  return () => {
    stopped = true;
    if (retryTimer !== undefined) window.clearTimeout(retryTimer);
    socket?.close(1000, "session changed");
  };
}

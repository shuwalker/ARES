import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import {
  subscribeToChatStream,
  subscribeToSessionActivity,
  type ChatStreamEvent,
  type TransportState,
} from "@/shared/chat-stream";
import type { AresSnapshot, ConversationMessage, ConversationSession } from "@/shared/contracts";
import { translateConversation } from "@/shared/translators";

const EMPTY_SNAPSHOT: AresSnapshot = {
  connection: "loading",
  settings: null,
  sessions: [],
  workspaces: [],
  backends: [],
  terminalRemoteBackend: false,
  agentHealth: { availability: "unknown", detail: "Runtime status has not been checked." },
  tools: { total: 0, names: [], unavailableServers: [] },
  connections: [],
  error: "",
};

interface AresContextValue {
  snapshot: AresSnapshot;
  currentSession: ConversationSession | null;
  selectedSessionId: string;
  streamText: string;
  streamReasoning: string;
  streamTools: string[];
  streamState: "idle" | "starting" | "streaming";
  chatNotice: string;
  refresh: () => Promise<void>;
  selectSession: (id: string) => void;
  createSession: (workspace?: string) => Promise<ConversationSession>;
  sendMessage: (
    message: string,
    options?: {
      backendId?: string;
      model?: string;
      provider?: string;
      workspace?: string;
    },
  ) => Promise<void>;
  cancelResponse: () => Promise<void>;
  saveAssistantName: (name: string) => Promise<void>;
}

const AresContext = createContext<AresContextValue | undefined>(undefined);

export function AresProvider({ children }: { children: ReactNode }) {
  const [snapshot, setSnapshot] = useState(EMPTY_SNAPSHOT);
  const [selectedSessionId, setSelectedSessionId] = useState(() => localStorage.getItem("ares.active-session") || "");
  const [currentSession, setCurrentSession] = useState<ConversationSession | null>(null);
  const [streamText, setStreamText] = useState("");
  const [streamReasoning, setStreamReasoning] = useState("");
  const [streamTools, setStreamTools] = useState<string[]>([]);
  const [streamState, setStreamState] = useState<"idle" | "starting" | "streaming">("idle");
  const [chatNotice, setChatNotice] = useState("");
  const activeStream = useRef("");
  const closeStream = useRef<null | (() => void)>(null);
  const sendInFlight = useRef(false);
  const streamGeneration = useRef(0);

  const refresh = useCallback(async () => {
    // Two-phase boot: never block the conversation list on slow discovery
    // endpoints (/api/backends and /api/connections often take multiple seconds).
    // Phase 1 paints sessions immediately; phase 2 fills secondary chrome.
    const withTimeout = <T,>(promise: Promise<T>, ms: number, label: string): Promise<T> =>
      new Promise<T>((resolve, reject) => {
        const timer = window.setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
        promise.then(
          (value) => { window.clearTimeout(timer); resolve(value); },
          (error) => { window.clearTimeout(timer); reject(error); },
        );
      });

    const [health, settings, sessions, workspaces] = await Promise.allSettled([
      withTimeout(aresApi.health(), 8_000, "health"),
      withTimeout(aresApi.settings(), 8_000, "settings"),
      withTimeout(aresApi.sessions(), 15_000, "sessions"),
      withTimeout(aresApi.workspaces(), 8_000, "workspaces"),
    ]);
    const apiAvailable = health.status === "fulfilled";
    const failures = [settings, sessions, workspaces].filter((item) => item.status === "rejected");
    setSnapshot((previous) => ({
      ...previous,
      connection: !apiAvailable ? "unavailable" : failures.length ? "limited" : "available",
      settings: settings.status === "fulfilled" ? settings.value : previous.settings,
      sessions: sessions.status === "fulfilled" ? sessions.value : previous.sessions,
      workspaces: workspaces.status === "fulfilled" ? workspaces.value.workspaces : previous.workspaces,
      terminalRemoteBackend: workspaces.status === "fulfilled" ? workspaces.value.terminalRemoteBackend : previous.terminalRemoteBackend,
      error: !apiAvailable ? readableError(health.reason, "ARES API is unavailable. The interface remains usable.") : "",
    }));

    const [backends, agentHealth, tools, connections] = await Promise.allSettled([
      withTimeout(aresApi.backends(), 12_000, "backends"),
      withTimeout(aresApi.agentHealth(), 8_000, "agentHealth"),
      withTimeout(aresApi.tools(), 8_000, "tools"),
      withTimeout(aresApi.connections(), 12_000, "connections"),
    ]);
    setSnapshot((previous) => ({
      ...previous,
      backends: backends.status === "fulfilled" ? backends.value : previous.backends,
      agentHealth: agentHealth.status === "fulfilled" ? agentHealth.value : previous.agentHealth,
      tools: tools.status === "fulfilled" ? tools.value : previous.tools,
      connections: connections.status === "fulfilled" ? connections.value : previous.connections,
    }));
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => {
    if (!selectedSessionId) {
      // Prefer a writable WebUI session so boot doesn't open a huge imported CLI
      // transcript (often 100+ messages) and look "stuck loading".
      const preferred =
        snapshot.sessions.find((s) => s.source !== "cli" && !s.readOnly)
        || snapshot.sessions.find((s) => s.source !== "cli")
        || snapshot.sessions[0];
      if (preferred?.id) setSelectedSessionId(preferred.id);
      return;
    }
    // Drop a stale localStorage id that no longer exists in the list once we
    // have sessions, so the chat surface doesn't hang on a 404 forever.
    if (
      snapshot.sessions.length > 0
      && !snapshot.sessions.some((s) => s.id === selectedSessionId)
    ) {
      const fallback =
        snapshot.sessions.find((s) => s.source !== "cli" && !s.readOnly)
        || snapshot.sessions[0];
      if (fallback?.id) setSelectedSessionId(fallback.id);
      return;
    }
  }, [selectedSessionId, snapshot.sessions]);

  useEffect(() => {
    if (!selectedSessionId) return;
    let active = true;
    setChatNotice("");
    aresApi.session(selectedSessionId).then((session) => {
      if (active) setCurrentSession(session);
    }).catch((error) => {
      if (active) {
        setCurrentSession(null);
        setChatNotice(readableError(error, "The conversation could not be loaded."));
      }
    });
    try { localStorage.setItem("ares.active-session", selectedSessionId); } catch { /* private mode */ }
    return () => { active = false; };
    // Intentionally only re-fetch when the selected id changes — not on every
    // sessions list refresh, which used to re-download and re-render the whole
    // transcript and made the chat feel like it never finished loading.
  }, [selectedSessionId]);

  useEffect(() => () => closeStream.current?.(), []);

  const selectSession = useCallback((id: string) => {
    streamGeneration.current += 1;
    sendInFlight.current = false;
    closeStream.current?.();
    closeStream.current = null;
    activeStream.current = "";
    setStreamState("idle");
    setStreamText("");
    setStreamReasoning("");
    setStreamTools([]);
    setChatNotice("");
    setSelectedSessionId(id);
  }, []);

  const createSession = useCallback(async (workspace?: string) => {
    const generation = streamGeneration.current;
    const session = await aresApi.createSession({
      workspace: workspace || snapshot.workspaces[0]?.path,
      previousSessionId: selectedSessionId || undefined,
    });
    if (generation !== streamGeneration.current) return session;
    setSnapshot((previous) => ({ ...previous, sessions: [session, ...previous.sessions.filter((item) => item.id !== session.id)] }));
    setCurrentSession(session);
    setSelectedSessionId(session.id);
    return session;
  }, [selectedSessionId, snapshot.workspaces]);

  const finishStream = useCallback(async (sessionId: string) => {
    sendInFlight.current = false;
    closeStream.current?.();
    closeStream.current = null;
    activeStream.current = "";
    setStreamState("idle");
    try {
      const session = await aresApi.session(sessionId);
      setCurrentSession(session);
      setStreamText("");
      setStreamReasoning("");
      // Companion technical intelligence: soft-record a successful turn for worker ranking.
      // This is not LLM judgment — baseline metrics only (user can refine later).
      const workerId = session.backendId?.trim();
      if (workerId) {
        void aresApi.recordWorkerEvaluation({
          workerId,
          sessionId: session.id,
          taskKind: "chat",
          metrics: {
            task_success: 80,
            safety: 100,
            user_preference: 70,
            tool_efficiency: 70,
            faithfulness: 70,
            latency: 70,
            cost: 70,
          },
        }).catch(() => undefined);
      }
      await refresh();
    } catch (error) {
      setChatNotice(readableError(error, "The response ended, but the conversation could not be refreshed."));
    }
  }, [refresh]);

  const handleStreamEvent = useCallback((event: ChatStreamEvent, sessionId: string) => {
    if (event.type === "text") setStreamText((value) => value + event.text);
    else if (event.type === "reasoning") setStreamReasoning((value) => value + event.text);
    else if (event.type === "tool") setStreamTools((items) => [...items.filter((item) => item !== event.label), event.label]);
    else if (event.type === "warning") setChatNotice(event.message);
    else if (event.type === "error") {
      setChatNotice(event.message);
      void finishStream(sessionId);
    } else if (event.type === "cancelled" || event.type === "ended") {
      void finishStream(sessionId);
    } else if (event.type === "done") {
      if (event.session) setCurrentSession(translateConversation(event.session));
    }
  }, [finishStream]);

  const handleTransportState = useCallback((state: TransportState, streamId: string, sessionId: string) => {
    if (state.state === "connected") {
      setChatNotice((notice) => notice.startsWith("Reconnecting") ? "" : notice);
      return;
    }
    if (state.state === "reconnecting") {
      setChatNotice(`Reconnecting to the response stream (attempt ${state.attempt})…`);
      return;
    }
    void aresApi.streamStatus(streamId).then((status) => {
      if (!status.active) void finishStream(sessionId);
      else setChatNotice("The live response connection is interrupted. Your Companion is preserving the run and will restore it when you reopen this conversation.");
    }).catch(() => {
      setChatNotice("The response connection was interrupted. The Companion preserved the conversation state; reconnect after the worker is available.");
    });
  }, [finishStream]);

  const attachStream = useCallback((streamId: string, sessionId: string) => {
    if (!streamId || (activeStream.current === streamId && closeStream.current)) return;
    closeStream.current?.();
    activeStream.current = streamId;
    sendInFlight.current = true;
    setStreamState("streaming");
    closeStream.current = subscribeToChatStream(
      streamId,
      (event) => handleStreamEvent(event, sessionId),
      (state) => handleTransportState(state, streamId, sessionId),
    );
  }, [handleStreamEvent, handleTransportState]);

  useEffect(() => {
    const streamId = currentSession?.activeStreamId;
    if (!streamId || !currentSession || currentSession.id !== selectedSessionId) return;
    let active = true;
    void aresApi.streamStatus(streamId).then((status) => {
      if (active && (status.active || status.replay_available)) attachStream(streamId, currentSession.id);
    }).catch(() => undefined);
    return () => { active = false; };
  }, [attachStream, currentSession, selectedSessionId]);

  useEffect(() => {
    if (!selectedSessionId) return;
    // Imported CLI / external-agent sessions are read-only: the activity socket
    // rejects them with "read-only imported session". Skip the subscription so
    // we never paint a false "Background activity updates are temporarily
    // unavailable" banner over an otherwise healthy chat page.
    if (currentSession?.id === selectedSessionId && currentSession.readOnly) return;

    return subscribeToSessionActivity(
      selectedSessionId,
      ({ name, data }) => {
        if (name === "error") {
          // Terminal permission/transport errors are handled quietly — chat
          // still works without live background activity.
          return;
        }
        if (name === "server_turn_started") {
          const streamId = String(data.stream_id || "");
          if (streamId) attachStream(streamId, selectedSessionId);
        } else if (name === "bg_task_complete" || name === "process_complete") {
          setChatNotice("Background work completed; your Companion is updating this conversation.");
          void refresh();
        }
      },
      () => setChatNotice((notice) => notice || "Background activity updates are temporarily unavailable."),
    );
  }, [attachStream, currentSession?.id, currentSession?.readOnly, refresh, selectedSessionId]);

  const sendMessage = useCallback(async (
    message: string,
    options?: {
      backendId?: string;
      model?: string;
      provider?: string;
      workspace?: string;
    },
  ) => {
    // Back-compat: older callers passed backendId as the second arg string.
    const opts = typeof options === "string"
      ? { backendId: options as string }
      : (options || {});
    const clean = message.trim();
    if (!clean || streamState !== "idle" || sendInFlight.current) return;
    sendInFlight.current = true;
    const generation = ++streamGeneration.current;
    setChatNotice("");
    setStreamText("");
    setStreamReasoning("");
    setStreamTools([]);
    setStreamState("starting");
    try {
      const effectiveBackend = opts.backendId || undefined;
      const sessionBase = currentSession || await createSession(opts.workspace);
      if (generation !== streamGeneration.current) return;
      if (sessionBase.readOnly) throw new Error("This conversation is read-only. Start a new conversation to send a message.");
      const session = {
        ...sessionBase,
        model: opts.model || sessionBase.model,
        provider: opts.provider || sessionBase.provider,
        workspace: opts.workspace || sessionBase.workspace,
        backendId: effectiveBackend || sessionBase.backendId,
      };
      const optimistic: ConversationMessage = { id: `local-${Date.now()}`, role: "user", text: clean, createdAt: new Date().toISOString() };
      setCurrentSession({ ...session, messages: [...session.messages, optimistic] });
      const started = await aresApi.startChat(session.id, clean, session, effectiveBackend);
      if (generation !== streamGeneration.current) return;
      attachStream(started.stream_id, session.id);
    } catch (error) {
      if (generation === streamGeneration.current) {
        sendInFlight.current = false;
        setStreamState("idle");
        setChatNotice(readableError(error, "No worker is available. Your Companion interface is still operational."));
      }
    }
  }, [attachStream, createSession, currentSession, streamState]);

  const cancelResponse = useCallback(async () => {
    if (!activeStream.current) return;
    await aresApi.cancelChat(activeStream.current);
  }, []);

  const saveAssistantName = useCallback(async (name: string) => {
    const settings = await aresApi.saveAssistantName(name);
    setSnapshot((previous) => ({ ...previous, settings }));
  }, []);

  const value = useMemo(() => ({
    snapshot, currentSession, selectedSessionId, streamText, streamReasoning, streamTools,
    streamState, chatNotice, refresh, selectSession, createSession, sendMessage, cancelResponse, saveAssistantName,
  }), [snapshot, currentSession, selectedSessionId, streamText, streamReasoning, streamTools, streamState, chatNotice, refresh, selectSession, createSession, sendMessage, cancelResponse, saveAssistantName]);

  return <AresContext.Provider value={value}>{children}</AresContext.Provider>;
}

export function useAres() {
  const value = useContext(AresContext);
  if (!value) throw new Error("useAres must be used within AresProvider");
  return value;
}

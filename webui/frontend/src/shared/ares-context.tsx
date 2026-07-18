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
  createSession: (workspace?: string, backendId?: string) => Promise<ConversationSession>;
  sendMessage: (message: string, backendId?: string) => Promise<void>;
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

  const refresh = useCallback(async () => {
    const [health, settings, sessions, workspaces, backends, agentHealth, tools, connections] = await Promise.allSettled([
      aresApi.health(), aresApi.settings(), aresApi.sessions(), aresApi.workspaces(), aresApi.backends(), aresApi.agentHealth(), aresApi.tools(), aresApi.connections(),
    ]);
    const apiAvailable = health.status === "fulfilled";
    const failures = [settings, sessions, workspaces].filter((item) => item.status === "rejected");
    setSnapshot((previous) => ({
      ...previous,
      connection: !apiAvailable ? "unavailable" : failures.length ? "limited" : "available",
      settings: settings.status === "fulfilled" ? settings.value : previous.settings,
      sessions: sessions.status === "fulfilled" ? sessions.value : previous.sessions,
      workspaces: workspaces.status === "fulfilled" ? workspaces.value.workspaces : previous.workspaces,
      backends: backends.status === "fulfilled" ? backends.value : previous.backends,
      terminalRemoteBackend: workspaces.status === "fulfilled" ? workspaces.value.terminalRemoteBackend : previous.terminalRemoteBackend,
      agentHealth: agentHealth.status === "fulfilled" ? agentHealth.value : previous.agentHealth,
      tools: tools.status === "fulfilled" ? tools.value : previous.tools,
      connections: connections.status === "fulfilled" ? connections.value : previous.connections,
      error: !apiAvailable ? readableError(health.reason, "ARES API is unavailable. The interface remains usable.") : "",
    }));
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => {
    if (!selectedSessionId) {
      const first = snapshot.sessions[0]?.id;
      if (first) setSelectedSessionId(first);
      return;
    }
    let active = true;
    aresApi.session(selectedSessionId).then((session) => {
      if (active) setCurrentSession(session);
    }).catch((error) => {
      if (active) setChatNotice(readableError(error, "The conversation could not be loaded."));
    });
    localStorage.setItem("ares.active-session", selectedSessionId);
    return () => { active = false; };
  }, [selectedSessionId, snapshot.sessions]);

  useEffect(() => () => closeStream.current?.(), []);

  const selectSession = useCallback((id: string) => {
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

  const createSession = useCallback(async (workspace?: string, backendId?: string) => {
    const session = await aresApi.createSession({
      workspace: workspace || snapshot.workspaces[0]?.path,
      previousSessionId: selectedSessionId || undefined,
      model_provider: backendId || undefined,
    });
    setSnapshot((previous) => ({ ...previous, sessions: [session, ...previous.sessions.filter((item) => item.id !== session.id)] }));
    setCurrentSession(session);
    setSelectedSessionId(session.id);
    return session;
  }, [selectedSessionId, snapshot.workspaces]);

  const finishStream = useCallback(async (sessionId: string) => {
    closeStream.current?.();
    closeStream.current = null;
    activeStream.current = "";
    setStreamState("idle");
    try {
      const session = await aresApi.session(sessionId);
      setCurrentSession(session);
      setStreamText("");
      setStreamReasoning("");
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
      else setChatNotice("The live response connection is interrupted. ARES is preserving the run and will restore it when you reopen this conversation.");
    }).catch(() => {
      setChatNotice("The response connection was interrupted. ARES preserved the conversation state; reconnect after the backend is available.");
    });
  }, [finishStream]);

  const attachStream = useCallback((streamId: string, sessionId: string) => {
    if (!streamId || (activeStream.current === streamId && closeStream.current)) return;
    closeStream.current?.();
    activeStream.current = streamId;
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
    return subscribeToSessionActivity(
      selectedSessionId,
      ({ name, data }) => {
        if (name === "server_turn_started") {
          const streamId = String(data.stream_id || "");
          if (streamId) attachStream(streamId, selectedSessionId);
        } else if (name === "bg_task_complete" || name === "process_complete") {
          setChatNotice("Background work completed; ARES is updating this conversation.");
          void refresh();
        }
      },
      () => setChatNotice((notice) => notice || "Background activity updates are temporarily unavailable."),
    );
  }, [attachStream, refresh, selectedSessionId]);

  const sendMessage = useCallback(async (message: string, backendId?: string) => {
    const clean = message.trim();
    if (!clean || streamState !== "idle") return;
    setChatNotice("");
    setStreamText("");
    setStreamReasoning("");
    setStreamTools([]);
    setStreamState("starting");
    try {
      const session = currentSession || await createSession();
      if (session.readOnly) throw new Error("This conversation is read-only. Start a new conversation to send a message.");
      const optimistic: ConversationMessage = { id: `local-${Date.now()}`, role: "user", text: clean, createdAt: new Date().toISOString() };
      setCurrentSession({ ...session, messages: [...session.messages, optimistic] });
      const started = await aresApi.startChat(session.id, clean, session, backendId);
      attachStream(started.stream_id, session.id);
    } catch (error) {
      setStreamState("idle");
      setChatNotice(readableError(error, "No assistant runtime is available. Your ARES interface is still operational."));
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

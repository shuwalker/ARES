import {
  ArrowDown,
  Bot,
  Check,
  Copy,
  LoaderCircle,
  Square,
  Wrench,
  AlertTriangle,
  ChevronDown,
  ChevronUp,
  X,
  Paperclip,
  Bookmark,
  Mic,
  MicOff,
  Boxes,
  Folder,
  FileText,
  GitBranch,
  Settings,
  Server,
  User,
  Package,
  Brain,
  Zap,
  WrenchIcon,
} from "lucide-react";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent,
} from "react";

import { Link } from "react-router-dom";

import { APP_ICON_URL } from "@/assets";
import { isBlockingState } from "@/components/ConnectionStatusBadge";
import { Markdown } from "@/components/Markdown";
import { useAres } from "@/shared/ares-context";
import { aresApi } from "@/shared/ares-api";
import { useLocalProfile } from "@/shared/local-profile";
import { useWorkbenchPanel } from "@/shared/workbench-panel";
import { apiFetch, readableError, PROVIDER_UNAVAILABLE_CODES } from "@/shared/api-client";

// Hermes-matching dark blue palette
const H = {
  bg: "var(--chat-bg)",
  surface: "var(--chat-surface)",
  surfaceHover: "#1f2236",
  surfaceActive: "#252840",
  border: "#1e2130",
  border2: "#2a2d42",
  text: "#e2e4f0",
  strong: "#f0f2ff",
  muted: "#6b7194",
  accentGlow: "#08EBF1",
  accentBlue: "#3889FD",
  accent: "#5b7cf6",
  inputBg: "#161822",
  inputBorder: "#252840",
  chipBg: "#1e2130",
  chipBorder: "#2a2d42",
  chipText: "#9094b8",
  sendBtn: "#ef4444",
  sendBtnText: "#ffffff",
};

// ARES Spartan Helmet - uses the actual icon from assets
const SpartanHelmetSVG = () => (
  <img src={APP_ICON_URL} alt="ARES Spartan Helmet" style={{ width: "72px", height: "72px", objectFit: "contain" }} />
);

function IconBtn({ children, title, onClick }: { children: React.ReactNode; title: string; onClick?: () => void }) {
  return (
    <button type="button" title={title} onClick={onClick}
      style={{ display: "inline-flex", alignItems: "center", justifyContent: "center", width: "1.75rem", height: "1.75rem", borderRadius: "0.375rem", border: "none", background: "transparent", color: H.muted, cursor: "pointer", transition: "color 0.15s, background 0.15s" }}
      onMouseEnter={(e) => { e.currentTarget.style.color = H.text; e.currentTarget.style.background = "rgba(255,255,255,0.06)"; }}
      onMouseLeave={(e) => { e.currentTarget.style.color = H.muted; e.currentTarget.style.background = "transparent"; }}>
      {children}
    </button>
  );
}

function ComposerChip({ icon, label, onClick }: { icon: React.ReactNode; label: string; onClick?: () => void }) {
  const [hover, setHover] = useState(false);
  return (
    <button type="button" onClick={onClick} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{ display: "inline-flex", alignItems: "center", gap: "0.3125rem", height: "1.625rem", padding: "0 0.5rem", borderRadius: "0.375rem", border: `1px solid ${hover ? H.border2 : H.chipBorder}`, background: hover ? H.surfaceHover : H.chipBg, color: hover ? H.text : H.chipText, fontSize: "0.75rem", fontWeight: 500, cursor: "pointer", transition: "all 0.15s", whiteSpace: "nowrap", flexShrink: 0, maxWidth: "8.125rem" }}>
      <span style={{ opacity: 0.7, flexShrink: 0 }}>{icon}</span>
      <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{label}</span>
      <ChevronDown size={9} style={{ opacity: 0.5, flexShrink: 0 }} />
    </button>
  );
}

interface DiscoveredBackend {
  adapter_id: string;
  display_name: string;
  detected: boolean;
}

interface DiscoveryResponse {
  adapters: DiscoveredBackend[];
}

const SAVED_PROMPT_TEMPLATES = [
  { label: "Code Review", prompt: "Please review this code for performance, security vulnerabilities, and adherence to clean architecture principles:" },
  { label: "Debug Error", prompt: "Help me diagnose and debug the root cause of this error. Trace the failure path step by step:" },
  { label: "Refactor Code", prompt: "Refactor this code to make it more modular, readable, and maintainable while maintaining exact backward compatibility:" },
  { label: "System Architecture", prompt: "Outline a high-level technical architecture and implementation plan for the following feature requirement:" },
];

/** Available JaegerAI character/personality presets — mirrors backend config.yaml agent.personalities */
const PERSONALITY_OPTIONS: Array<{ id: string; label: string; detail: string }> = [
  { id: "grounded", label: "Grounded", detail: "Practical, direct, no fluff — matches your onboarding character" },
  { id: "helpful", label: "Helpful", detail: "Friendly and thorough, assists accurately and completely" },
  { id: "concise", label: "Concise", detail: "Brief and to the point — minimal words, maximum signal" },
  { id: "technical", label: "Technical", detail: "Detailed, precise technical information and analysis" },
  { id: "creative", label: "Creative", detail: "Think outside the box, innovative solutions" },
  { id: "warm", label: "Warm", detail: "Caring, empathetic, supportive conversational style" },
  { id: "direct", label: "Direct", detail: "No sugar-coating, straight answers, efficient" },
  { id: "curious", label: "Curious", detail: "Asks clarifying questions, explores implications deeply" },
  { id: "teacher", label: "Teacher", detail: "Patient explanations with examples and analogies" },
  { id: "noir", label: "Noir", detail: "Hard-boiled detective style, atmospheric and sharp" },
  { id: "catgirl", label: "Neko-chan", detail: "Playful catgirl companion, nya~!" },
  { id: "pirate", label: "Pirate", detail: "Arrr! Tech-savvy buccaneer of the digital seas" },
  { id: "shakespeare", label: "Shakespeare", detail: "Flowery prose and dramatic flair" },
  { id: "uwu", label: "UwU", detail: "Maximum cuteness, hewwo fwiend!" },
  { id: "philosopher", label: "Philosopher", detail: "Contemplates the deeper meaning behind every query" },
  { id: "hype", label: "Hype", detail: "YOOO LET'S GOOO! Maximum energy, minimum chill" },
  { id: "kawaii", label: "Kawaii", detail: "Sparkles and enthusiasm for everything desu~!" },
  { id: "surfer", label: "Surfer", detail: "Duuude, chillest companion on the web, bro!" },
];

const REASONING_OPTIONS: Array<{ value: string; label: string }> = [
  { value: "none", label: "Off" },
  { value: "minimal", label: "Minimal" },
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
  { value: "xhigh", label: "Extra High" },
  { value: "max", label: "Max" },
  { value: "ultra", label: "Ultra" },
];

export function ConversationPage() {
  const workbenchPanel = useWorkbenchPanel();
  const { profile } = useLocalProfile();
  const {
    snapshot,
    currentSession,
    selectedSessionId,
    createSession,
    sendMessage,
    streamText,
    streamReasoning,
    streamTools,
    streamState,
    chatNotice,
    chatNoticeProvider,
    cancelResponse,
    refresh,
  } = useAres();

  const sessionLoading = Boolean(selectedSessionId && !currentSession && !chatNotice);
  const [draft, setDraft] = useState("");
  const [copied, setCopied] = useState(false);
  const [showScrollBottom, setShowScrollBottom] = useState(false);
  const [discoveredBackends, setDiscoveredBackends] = useState<DiscoveredBackend[]>([]);
  const [discoveryError, setDiscoveryError] = useState("");
  const [selectedBackend, setSelectedBackend] = useState<string>(() => currentSession?.backendId || "");
  const [selectedPersonality, setSelectedPersonality] = useState<string>(() => profile.character || "grounded");
  const [showApproval, setShowApproval] = useState(false);
  const [approvalCollapsed, setApprovalCollapsed] = useState(false);

  // Attachments, saved prompts, dictation, workspace, backend, model
  const [attachedFiles, setAttachedFiles] = useState<File[]>([]);
  const [showSavedPrompts, setShowSavedPrompts] = useState(false);
  const [showBackendMenu, setShowBackendMenu] = useState(false);
  const [showModelMenu, setShowModelMenu] = useState(false);
  const [showWorkspaceMenu, setShowWorkspaceMenu] = useState(false);
  const [showSiModeMenu, setShowSiModeMenu] = useState(false);
  const [showReasoningMenu, setShowReasoningMenu] = useState(false);
  const [showToolsetMenu, setShowToolsetMenu] = useState(false);
  const [selectedReasoning, setSelectedReasoning] = useState<string>("medium");
  const [yoloMode, setYoloMode] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [selectedModel, setSelectedModel] = useState<string>("");
  const [selectedModelProvider, setSelectedModelProvider] = useState<string>("");
  const [workspaceOverride, setWorkspaceOverride] = useState<string>("");
  const [backendCatalog, setBackendCatalog] = useState<
    Array<{
      id: string;
      available?: boolean;
      inventory?: {
        models?: Array<{
          id: string;
          label?: string;
          location?: string;
          in_use?: boolean;
          provider?: string | null;
          notes?: string | null;
        }>;
        providers?: Array<{ id: string; label?: string; status?: string; notes?: string }>;
        active_execution?: { model?: string | null; provider?: string | null };
      };
    }>
  >([]);

  const [wsSearchQuery, setWsSearchQuery] = useState("");
  const [backendSearchQuery, setBackendSearchQuery] = useState("");

  // Composer / transcript prefs from App Settings (agent-agnostic server keys).
  const [sendKey, setSendKey] = useState<"enter" | "ctrl+enter" | "shift+enter">("enter");
  const [hideSuggestions, setHideSuggestions] = useState(false);
  const [autoFollow, setAutoFollow] = useState(true);

  useEffect(() => {
    let cancelled = false;
    void aresApi
      .settingsGet()
      .then((raw) => {
        if (cancelled) return;
        const key = String(raw.send_key || "enter");
        if (key === "ctrl+enter" || key === "shift+enter" || key === "enter") setSendKey(key);
        setHideSuggestions(Boolean(raw.hide_empty_state_suggestions));
        setAutoFollow(raw.auto_scroll_follow !== false);
      })
      .catch(() => {
        /* keep defaults */
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const copiedTimer = useRef<number | undefined>(undefined);
  const transcriptRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const recognitionRef = useRef<any>(null);

  // Close menus when clicking outside
  useEffect(() => {
    const handleDocumentClick = (e: MouseEvent) => {
      // Don't close if click is inside any menu wrapper (they have stopPropagation)
      const target = e.target as HTMLElement;
      if (target.closest?.("[data-menu-wrapper]")) return;
      setShowWorkspaceMenu(false);
      setShowBackendMenu(false);
      setShowModelMenu(false);
      setShowSiModeMenu(false);
      setShowReasoningMenu(false);
      setShowToolsetMenu(false);
    };
    document.addEventListener("click", handleDocumentClick);
    return () => document.removeEventListener("click", handleDocumentClick);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    void apiFetch<DiscoveryResponse>("/api/discover/frameworks", { signal: controller.signal })
      .then((data) => {
        if (controller.signal.aborted) return;
        setDiscoveredBackends(data.adapters || []);
        setDiscoveryError("");
      })
      .catch((error: unknown) => {
        if (!controller.signal.aborted) setDiscoveryError(readableError(error, "Connections could not be discovered."));
      });
    void apiFetch<{ backends?: typeof backendCatalog }>("/api/backends", { signal: controller.signal })
      .then((data) => {
        if (!controller.signal.aborted) setBackendCatalog(data.backends || []);
      })
      .catch(() => undefined);
    return () => controller.abort();
  }, []);

  useEffect(() => () => {
    if (copiedTimer.current !== undefined) window.clearTimeout(copiedTimer.current);
  }, []);

  const isBusy = streamState !== "idle";
  const hasConversation = Boolean(currentSession?.messages.length || streamText || isBusy);
  const isReadOnlyCli = Boolean(currentSession?.readOnly || currentSession?.source === "cli");

  // Whether the chosen provider can actually take a turn. The server refuses
  // one it cannot serve, but letting someone type a message and press send only
  // to be told no is a poor way to learn the provider is down — so the composer
  // says it up front and stays out of the way.
  const activeConnection = snapshot.connections.find((c) => c.id === selectedBackend);
  const noProviderSelected = !selectedBackend && !snapshot.connections.some((c) => c.selected);
  const providerBlocked = Boolean(activeConnection && isBlockingState(activeConnection.state));
  const cannotSend = noProviderSelected || providerBlocked;
  const providerNotice = noProviderSelected
    ? "No AI provider is selected yet."
    : providerBlocked
      ? activeConnection?.detail || `${activeConnection?.name || "This provider"} is unavailable.`
      : "";

  useEffect(() => {
    if (currentSession?.backendId) {
      setSelectedBackend(currentSession.backendId);
    } else {
      const elected = snapshot.connections.find((c) => c.selected)?.id || "";
      if (elected) setSelectedBackend(elected);
    }
    // Session workspace is the agent's working folder unless user overrides.
    if (currentSession?.workspace) setWorkspaceOverride("");
    if (currentSession?.model) {
      setSelectedModel(currentSession.model);
      setSelectedModelProvider(currentSession.provider || "");
    }
    // Restore personality from session, or fall back to onboarding character
    if (currentSession?.personality) {
      setSelectedPersonality(currentSession.personality);
    }
  }, [currentSession?.backendId, currentSession?.workspace, currentSession?.model, currentSession?.provider, currentSession?.personality, snapshot.connections]);

  useEffect(() => {
    const el = transcriptRef.current;
    if (!el) return;
    if (!autoFollow) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
    if (nearBottom || streamText) el.scrollTo({ top: el.scrollHeight, behavior: streamText ? "auto" : "smooth" });
  }, [currentSession?.messages.length, streamText, streamReasoning, streamTools, streamState, autoFollow]);

  const onScroll = useCallback(() => {
    const el = transcriptRef.current;
    if (!el) return;
    setShowScrollBottom(el.scrollHeight - el.scrollTop - el.clientHeight > 120);
  }, []);

  // Dictation handling
  const toggleDictation = useCallback(() => {
    if (isListening) {
      if (recognitionRef.current) recognitionRef.current.stop();
      setIsListening(false);
      return;
    }

    const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SpeechRecognition) {
      alert("Browser speech recognition is not supported in this browser.");
      return;
    }

    try {
      const recognition = new SpeechRecognition();
      recognition.continuous = true;
      recognition.interimResults = true;
      recognition.lang = "en-US";

      recognition.onresult = (event: any) => {
        let transcriptText = "";
        for (let i = event.resultIndex; i < event.results.length; i++) {
          transcriptText += event.results[i][0].transcript;
        }
        setDraft((prev) => prev + (prev ? " " : "") + transcriptText);
      };

      recognition.onerror = () => setIsListening(false);
      recognition.onend = () => setIsListening(false);

      recognition.start();
      recognitionRef.current = recognition;
      setIsListening(true);
    } catch {
      setIsListening(false);
    }
  }, [isListening]);

  const submit = useCallback(async (event: FormEvent) => {
    event.preventDefault();
    const message = draft.trim();
    if (!message && attachedFiles.length === 0) return;
    if (isBusy || isReadOnlyCli || cannotSend) return;

    const files = attachedFiles.length > 0 ? [...attachedFiles] : undefined;

    setDraft("");
    setAttachedFiles([]);
    if (textareaRef.current) textareaRef.current.style.height = "auto";
    const workspace =
      workspaceOverride.trim()
      || currentSession?.workspace
      || snapshot.workspaces?.[0]?.path
      || undefined;
    void sendMessage(message, {
      backendId: selectedBackend || undefined,
      model: selectedModel || undefined,
      provider: selectedModelProvider || undefined,
      workspace,
      files,
      personality: selectedPersonality || undefined,
    });
  }, [
    draft, attachedFiles, isBusy, isReadOnlyCli, cannotSend, sendMessage, selectedBackend,
    selectedModel, selectedModelProvider, workspaceOverride, currentSession, snapshot.workspaces,
  ]);

  const handleComposerKeyDown = useCallback(
    (event: KeyboardEvent<HTMLTextAreaElement>) => {
      if (event.key !== "Enter" || event.nativeEvent.isComposing) return;
      const wantsSend =
        sendKey === "enter"
          ? !event.shiftKey && !event.ctrlKey && !event.metaKey
          : sendKey === "ctrl+enter"
            ? event.ctrlKey || event.metaKey
            : event.shiftKey; // shift+enter
      if (!wantsSend) return;
      event.preventDefault();
      event.currentTarget.form?.requestSubmit();
    },
    [sendKey],
  );

  const copyLastResponse = useCallback(async () => {
    const lastAssistant = [...(currentSession?.messages || [])].reverse().find((m) => m.role !== "user")?.text;
    const text = streamText || lastAssistant;
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      if (copiedTimer.current !== undefined) window.clearTimeout(copiedTimer.current);
      copiedTimer.current = window.setTimeout(() => setCopied(false), 1600);
    } catch (reason) { console.error(reason); }
  }, [currentSession?.messages, streamText]);

  const lastAssistantText = useMemo(() => {
    if (streamText) return streamText;
    return [...(currentSession?.messages || [])].reverse().find((m) => m.role !== "user")?.text;
  }, [currentSession?.messages, streamText]);

  // Agent working folder: session workspace > override > first known workspace.
  const workspacePath =
    workspaceOverride.trim()
    || currentSession?.workspace
    || snapshot.workspaces?.[0]?.path
    || "";
  const activeWorkspaceLabel = (() => {
    if (!workspacePath) return "Working folder";
    if (workspacePath === "~" || workspacePath === "/") return workspacePath;
    const segments = workspacePath.replace(/\/+$/, "").split("/").filter(Boolean);
    return segments[segments.length - 1] || workspacePath;
  })();

  // Live backends: only available connections / detected adapters.
  const backendOptions = useMemo(() => {
    const fromConnections = snapshot.connections
      .filter((c) => c.available !== false && c.state !== "offline")
      .map((c) => ({
        id: c.id,
        label: c.name || c.id,
        detail: c.detail || c.kind,
        available: Boolean(c.available),
      }));
    if (fromConnections.length) return fromConnections;
    return discoveredBackends
      .filter((b) => b.detected)
      .map((b) => ({
        id: b.adapter_id,
        label: b.display_name || b.adapter_id,
        detail: b.adapter_id,
        available: true,
      }));
  }, [snapshot.connections, discoveredBackends]);

  const activeBackendMeta = backendOptions.find((b) => b.id === selectedBackend)
    || backendOptions.find((b) => b.id === snapshot.connections.find((c) => c.selected)?.id);
  const activeBackendLabel = activeBackendMeta?.label
    || (selectedBackend ? selectedBackend.replace(/_/g, " ") : "Select backend");

  // Models auto-detected from that backend's adapter inventory only
  // (configured providers + installed local models).
  const modelsForBackend = useMemo(() => {
    const entry = backendCatalog.find((b) => b.id === selectedBackend);
    const inv = entry?.inventory;
    const listed = (inv?.models || []).filter((m) => {
      if (!m.id || m.id.startsWith("(")) return false;
      // Reject accidental dict-stringified ids from bad catalog data
      if (m.id.includes("{") || m.id.includes("'default'")) return false;
      return true;
    });
    // Active first, then local, then cloud
    const rank = (m: (typeof listed)[number]) =>
      (m.in_use ? 0 : 10) + (m.location === "local" ? 0 : m.location === "cloud" ? 1 : 2);
    return [...listed].sort((a, b) => rank(a) - rank(b) || a.id.localeCompare(b.id));
  }, [backendCatalog, selectedBackend]);

  const providersForBackend = useMemo(() => {
    const entry = backendCatalog.find((b) => b.id === selectedBackend);
    return entry?.inventory?.providers || [];
  }, [backendCatalog, selectedBackend]);

  // When backend or catalog changes, keep model valid for that backend only.
  useEffect(() => {
    if (!selectedBackend) return;
    if (selectedModel && modelsForBackend.some((m) => m.id === selectedModel)) return;
    const preferred = modelsForBackend.find((m) => m.in_use) || modelsForBackend[0];
    if (preferred) {
      setSelectedModel(preferred.id);
      setSelectedModelProvider(preferred.provider || "");
    } else {
      setSelectedModel("");
      setSelectedModelProvider("");
    }
  }, [selectedBackend, modelsForBackend, selectedModel]);

  // Poll provider status every 10 seconds while chatting to detect outages
  useEffect(() => {
    if (streamState !== "streaming" && streamState !== "starting") {
      return; // Only poll while actively chatting
    }

    const pollInterval = setInterval(() => {
      refresh().catch(() => {
        // Silent catch — refresh errors are logged server-side
      });
    }, 10000); // Poll every 10 seconds

    return () => clearInterval(pollInterval);
  }, [streamState, refresh]);

  const activeModelLabel = (() => {
    if (!selectedModel) return modelsForBackend.length ? "Pick model" : "No models";
    const hit = modelsForBackend.find((m) => m.id === selectedModel);
    if (!hit) return selectedModel;
    const loc = hit.location && hit.location !== "unknown" ? ` · ${hit.location}` : "";
    return `${hit.label || hit.id}${loc}`;
  })();

  const filteredBackends = useMemo(() => {
    const q = backendSearchQuery.trim().toLowerCase();
    if (!q) return backendOptions;
    return backendOptions.filter(
      (b) => b.label.toLowerCase().includes(q) || b.id.toLowerCase().includes(q),
    );
  }, [backendOptions, backendSearchQuery]);

  const workspaceChoices = useMemo(() => {
    const paths = new Map<string, string>();
    for (const w of snapshot.workspaces || []) {
      if (w.path) paths.set(w.path, w.label || w.path);
    }
    if (currentSession?.workspace) {
      paths.set(currentSession.workspace, currentSession.workspace);
    }
    return Array.from(paths.entries()).map(([path, label]) => ({ path, label }));
  }, [snapshot.workspaces, currentSession?.workspace]);

  return (
    <div
      className="conversation-page"
      style={{ display: "flex", flexDirection: "column", height: "100%", background: H.bg, color: H.text, position: "relative" }}
    >

      {/* Hidden file input for Attach button — accepts images and other files */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        accept="image/*,.pdf,.txt,.py,.js,.ts,.tsx,.md,.json,.yaml,.csv"
        style={{ display: "none" }}
        onChange={(e) => {
          if (e.target.files) {
            const files = Array.from(e.target.files);
            setAttachedFiles((prev) => [...prev, ...files]);
          }
        }}
      />

      {/* Messages area */}
      <div ref={transcriptRef} onScroll={onScroll} style={{ flex: 1, overflowY: "auto", overflowX: "hidden", position: "relative" }}>
        {sessionLoading ? (
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", minHeight: "100%", gap: "0.75rem", color: H.muted }}>
            <LoaderCircle size={22} style={{ color: H.accentGlow }} className="animate-spin" />
            <p style={{ fontSize: "0.8125rem", margin: "0rem" }}>Loading conversation…</p>
          </div>
        ) : !hasConversation ? (
          /* Empty state */
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", minHeight: "100%", padding: "2.5rem 1.5rem", textAlign: "center", background: `radial-gradient(ellipse at 50% 25%, rgba(56,137,253,0.06) 0%, transparent 60%)` }}>
            <div style={{ marginBottom: "1.25rem" }}><SpartanHelmetSVG /></div>
            <h2 style={{ fontSize: "1.375rem", fontWeight: 700, color: H.strong, margin: "0rem" }}>What are we working on?</h2>
            <p style={{ fontSize: "0.875rem", color: H.muted, margin: "0.5rem 0 1.75rem", lineHeight: 1.6, maxWidth: "23.75rem" }}>
              Start a project, delegate tasks, or ask anything. Your agent remembers.
            </p>
            <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem", width: "100%", maxWidth: "32.5rem" }}>
              {!hideSuggestions && [
                { icon: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>, text: "What files are in this workspace?" },
                { icon: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1"/><line x1="9" y1="12" x2="15" y2="12"/><line x1="9" y1="16" x2="12" y2="16"/></svg>, text: "What's on my schedule today?" },
                { icon: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/></svg>, text: "Help me plan a small project." },
              ].map((s) => (
                <button key={s.text} type="button" onClick={() => { setDraft(s.text); textareaRef.current?.focus(); }}
                  style={{ display: "flex", alignItems: "center", gap: "0.75rem", padding: "0.6875rem 1rem", borderRadius: "0.625rem", border: `1px solid ${H.border2}`, background: H.surface, color: H.text, fontSize: "0.875rem", textAlign: "left", cursor: "pointer", transition: "all 0.15s" }}
                  onMouseEnter={(e) => { e.currentTarget.style.background = H.surfaceHover; e.currentTarget.style.borderColor = H.accent + "55"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.background = H.surface; e.currentTarget.style.borderColor = H.border2; }}>
                  <span style={{ color: H.muted, flexShrink: 0 }}>{s.icon}</span>
                  <span>{s.text}</span>
                </button>
              ))}
            </div>
            {discoveryError && <p style={{ marginTop: "1rem", fontSize: "0.75rem", color: "#fbbf24" }}>{discoveryError}</p>}
          </div>
        ) : (
          /* Messages */
          <div className="conversation-messages" style={{ maxWidth: "min(47.5rem, 100%)", margin: "0 auto", width: "100%", padding: "1.75rem 1rem 7.5rem", display: "flex", flexDirection: "column", gap: "1.375rem" }}>
            {(currentSession?.messages || []).map((message) => {
              const isUser = message.role === "user";
              return (
                <div key={message.id} style={{ display: "flex", width: "100%", justifyContent: isUser ? "flex-end" : "flex-start" }}>
                  {!isUser && (
                    <div style={{ width: "1.875rem", height: "1.875rem", borderRadius: "50%", flexShrink: 0, background: H.surface, border: `1px solid ${H.border2}`, display: "flex", alignItems: "center", justifyContent: "center", marginRight: "0.625rem", marginTop: "0.125rem" }}>
                      <Bot size={14} style={{ color: H.accentGlow }} />
                    </div>
                  )}
                  <div style={{ maxWidth: "85%", display: "flex", flexDirection: "column", alignItems: isUser ? "flex-end" : "flex-start", gap: "0.25rem" }}>
                    <div style={{ padding: "0.5625rem 0.875rem", fontSize: "0.875rem", lineHeight: 1.6, background: isUser ? H.surfaceActive : "transparent", color: isUser ? H.strong : H.text, border: isUser ? `1px solid ${H.border2}` : "none", borderRadius: isUser ? "0.875rem 0.875rem 0.25rem 0.875rem" : 0, whiteSpace: "pre-wrap", wordBreak: "break-word" }}>
                      <Markdown content={message.text} />
                    </div>
                  </div>
                </div>
              );
            })}
            {streamState !== "idle" && (
              <div style={{ display: "flex", width: "100%" }}>
                <div style={{ width: "1.875rem", height: "1.875rem", borderRadius: "50%", flexShrink: 0, background: H.surface, border: `1px solid ${H.border2}`, display: "flex", alignItems: "center", justifyContent: "center", marginRight: "0.625rem", marginTop: "0.125rem" }}>
                  <Bot size={14} style={{ color: H.accentGlow }} />
                </div>
                <div style={{ maxWidth: "85%", fontSize: "0.875rem", lineHeight: 1.6, color: H.text }}>
                  {streamText ? <Markdown content={streamText} streaming /> : streamState === "starting" ? (
                    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
                      <LoaderCircle size={15} style={{ color: H.accentGlow }} />
                      <span style={{ color: H.muted }}>Starting…</span>
                    </div>
                  ) : (
                    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
                      <span style={{ width: "0.4375rem", height: "0.4375rem", borderRadius: "50%", background: H.accentBlue, display: "inline-block" }} />
                      <span style={{ color: H.muted }}>Thinking…</span>
                    </div>
                  )}
                  {streamReasoning && <div style={{ marginTop: "0.625rem", borderLeft: `0.125rem solid ${H.accentBlue}`, paddingLeft: "0.75rem", fontSize: "0.8125rem", fontStyle: "italic", color: H.muted }}>{streamReasoning}</div>}
                  {streamTools.length > 0 && (
                    <div style={{ marginTop: "0.625rem", display: "flex", flexWrap: "wrap", gap: "0.375rem" }}>
                      {streamTools.map((tool) => (
                        <span key={tool} style={{ display: "inline-flex", alignItems: "center", gap: "0.3125rem", padding: "0.1875rem 0.5rem", borderRadius: "0.375rem", fontSize: "0.6875rem", fontWeight: 500, background: H.surface, border: `1px solid ${H.border}`, color: H.text }}>
                          <Wrench size={10} style={{ opacity: 0.7 }} />{tool}
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Floating scroll / copy buttons */}
      <div style={{ position: "absolute", bottom: "6.875rem", right: "1.25rem", display: "flex", flexDirection: "column", alignItems: "flex-end", gap: "0.375rem", pointerEvents: "none", zIndex: 10 }}>
        {showScrollBottom && (
          <button type="button" onClick={() => transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: "smooth" })}
            style={{ pointerEvents: "auto", display: "flex", alignItems: "center", gap: "0.375rem", padding: "0.3125rem 0.75rem", borderRadius: "62.4375rem", border: `1px solid ${H.border2}`, background: H.surface, color: H.text, fontSize: "0.75rem", fontWeight: 500, cursor: "pointer" }}>
            <ArrowDown size={13} /> Bottom
          </button>
        )}
        {lastAssistantText && (
          <button type="button" onClick={() => void copyLastResponse()}
            style={{ pointerEvents: "auto", display: "flex", alignItems: "center", gap: "0.375rem", padding: "0.3125rem 0.75rem", borderRadius: "62.4375rem", border: `1px solid ${H.border2}`, background: H.surface, color: H.text, fontSize: "0.75rem", fontWeight: 500, cursor: "pointer" }}>
            {copied ? <Check size={13} style={{ color: "#4ade80" }} /> : <Copy size={13} />}
            {copied ? "Copied" : "Copy"}
          </button>
        )}
      </div>

      {/* COMPOSER */}
      <div className="conversation-composer" style={{ flexShrink: 0, padding: "0 1rem 0.875rem", background: H.bg, position: "relative", zIndex: 10 }}>

        {/* Approval card */}
        {showApproval && (
          <div style={{ marginBottom: "0.5rem", borderRadius: "0.75rem", border: `1px solid ${H.border2}`, background: H.surface, overflow: "hidden", boxShadow: "0 0.5rem 2rem rgba(0,0,0,0.5)", maxWidth: "46.25rem", margin: "0 auto 0.5rem" }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0.5625rem 0.875rem", borderBottom: `1px solid ${H.border}` }}>
              <span style={{ display: "flex", alignItems: "center", gap: "0.5rem", fontSize: "0.8125rem", fontWeight: 600, color: H.strong }}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
                Approval required
              </span>
              <div style={{ display: "flex", gap: "0.25rem" }}>
                <button onClick={() => setApprovalCollapsed(!approvalCollapsed)} style={{ background: "transparent", border: "none", color: H.muted, cursor: "pointer", padding: "0.25rem" }}>{approvalCollapsed ? <ChevronDown size={14} /> : <ChevronUp size={14} />}</button>
                <button onClick={() => setShowApproval(false)} style={{ background: "transparent", border: "none", color: H.muted, cursor: "pointer", padding: "0.25rem" }}><X size={14} /></button>
              </div>
            </div>
            {!approvalCollapsed && (
              <div style={{ padding: "0.75rem 0.875rem" }}>
                <p style={{ fontSize: "0.8125rem", color: H.muted, marginBottom: "0.625rem" }}>Agent is requesting permission to execute:</p>
                <code style={{ display: "block", background: "#0a0c14", padding: "0.5rem 0.75rem", borderRadius: "0.4375rem", fontFamily: "monospace", fontSize: "0.75rem", color: "#4ade80", border: `1px solid ${H.border}`, marginBottom: "0.75rem", overflowX: "auto" }}>$ rm -rf /tmp/cache/*</code>
                <div style={{ display: "flex", gap: "0.375rem", flexWrap: "wrap" }}>
                  {["Allow once", "Allow session", "Always allow", "Deny", "Skip all ⚡"].map((label) => (
                    <button key={label} type="button" onClick={() => setShowApproval(false)}
                      style={{ padding: "0.3125rem 0.75rem", borderRadius: "0.4375rem", fontSize: "0.75rem", cursor: "pointer", fontWeight: 500, background: label === "Allow once" ? H.accent : label === "Deny" ? "#3b1219" : H.surface, color: label === "Allow once" ? "#fff" : label === "Deny" ? "#fca5a5" : H.text, border: label === "Allow once" ? "none" : label === "Deny" ? "1px solid #7f1d1d" : `1px solid ${H.border2}` }}>
                      {label}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {isReadOnlyCli && (
          <div style={{ marginBottom: "0.5rem", maxWidth: "46.25rem", margin: "0 auto 0.5rem", padding: "0.5625rem 0.875rem", borderRadius: "0.5rem", border: "1px solid rgba(56,137,253,0.35)", background: "rgba(56,137,253,0.08)", color: H.accentBlue, fontSize: "0.75rem" }}>
            CLI / imported session (read-only). Switch to a <strong>WebUI</strong> session in the deck to talk to a backend.
          </div>
        )}

        {!isReadOnlyCli && cannotSend && (
          <div style={{ marginBottom: "0.5rem", maxWidth: "46.25rem", margin: "0 auto 0.5rem", padding: "0.5625rem 0.875rem", borderRadius: "0.5rem", border: "1px solid rgba(251,191,36,0.3)", background: "rgba(251,191,36,0.08)", color: "#fbbf24", fontSize: "0.8125rem", display: "flex", alignItems: "center", gap: "0.5rem" }}>
            <AlertTriangle size={13} style={{ flexShrink: 0 }} />
            <span style={{ flex: 1 }}>{providerNotice}</span>
            <Link
              to="/connections"
              style={{ flexShrink: 0, color: "#fbbf24", fontWeight: 600, textDecoration: "underline" }}
            >
              {noProviderSelected ? "Choose a provider" : "Open Connections"}
            </Link>
          </div>
        )}

        {chatNotice && (
          <div style={{ marginBottom: "0.5rem", maxWidth: "46.25rem", margin: "0 auto 0.5rem", padding: "0.5625rem 0.875rem", borderRadius: "0.5rem", border: "1px solid rgba(251,191,36,0.3)", background: "rgba(251,191,36,0.08)", color: "#fbbf24", fontSize: "0.8125rem", display: "flex", alignItems: "center", gap: "0.5rem" }}>
            <AlertTriangle size={13} style={{ flexShrink: 0 }} />
            <span style={{ flex: 1 }}>{chatNotice}</span>
            {/* A provider problem is fixed on the Connections page, so link there
                rather than leaving the user to find it. */}
            {chatNoticeProvider && PROVIDER_UNAVAILABLE_CODES.has(chatNoticeProvider.code || "") && (
              <Link
                to="/connections"
                style={{ flexShrink: 0, color: "#fbbf24", fontWeight: 600, textDecoration: "underline" }}
              >
                Open Connections
              </Link>
            )}
          </div>
        )}

        {/* Saved Prompts Popover */}
        {showSavedPrompts && (
          <div style={{ maxWidth: "46.25rem", margin: "0 auto 0.5rem", padding: "0.625rem", borderRadius: "0.625rem", border: `1px solid ${H.border2}`, background: H.surface, boxShadow: "0 0.5rem 1.5rem rgba(0,0,0,0.4)" }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "0.375rem", paddingBottom: "0.25rem", borderBottom: `1px solid ${H.border}` }}>
              <span style={{ fontSize: "0.75rem", fontWeight: 600, color: H.text }}>Saved Prompts</span>
              <button type="button" onClick={() => setShowSavedPrompts(false)} style={{ background: "transparent", border: "none", color: H.muted, cursor: "pointer" }}><X size={12} /></button>
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "0.375rem" }}>
              {SAVED_PROMPT_TEMPLATES.map((item) => (
                <button
                  key={item.label}
                  type="button"
                  onClick={() => {
                    setDraft((prev) => prev ? `${prev}\n\n${item.prompt}` : item.prompt);
                    setShowSavedPrompts(false);
                    textareaRef.current?.focus();
                  }}
                  style={{ textAlign: "left", padding: "0.375rem 0.5rem", borderRadius: "0.375rem", border: `1px solid ${H.border2}`, background: H.chipBg, color: H.text, fontSize: "0.6875rem", cursor: "pointer" }}
                >
                  <div style={{ fontWeight: 600, color: H.accentGlow }}>{item.label}</div>
                  <div style={{ color: H.muted, fontSize: "0.625rem", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{item.prompt}</div>
                </button>
              ))}
            </div>
          </div>
        )}

        <form onSubmit={(e) => void submit(e)} style={{ maxWidth: "min(46.25rem, 100%)", margin: "0 auto" }}>
          <div style={{ borderRadius: "0.875rem", border: `1px solid ${H.inputBorder}`, background: H.inputBg, boxShadow: "0 0.125rem 1rem rgba(0,0,0,0.35)", transition: "border-color 0.2s" }}>

            {/* Attached files tray */}
            {attachedFiles.length > 0 && (
              <div style={{ display: "flex", flexWrap: "wrap", gap: "0.375rem", padding: "0.5rem 0.75rem 0" }}>
                {attachedFiles.map((file, idx) => (
                  <span key={idx} style={{ display: "inline-flex", alignItems: "center", gap: "0.375rem", padding: "0.1875rem 0.5rem", borderRadius: "0.375rem", background: H.surface, border: `1px solid ${H.border2}`, fontSize: "0.6875rem", color: H.text }}>
                    <FileText size={11} style={{ color: H.accentGlow }} />
                    <span style={{ maxWidth: "7.5rem", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{file.name}</span>
                    <button type="button" onClick={() => setAttachedFiles((prev) => prev.filter((_, i) => i !== idx))} style={{ background: "transparent", border: "none", color: H.muted, cursor: "pointer", padding: "0rem" }}>
                      <X size={10} />
                    </button>
                  </span>
                ))}
              </div>
            )}

            {/* Listening indicator */}
            {isListening && (
              <div style={{ padding: "0.375rem 0.875rem", fontSize: "0.6875rem", fontWeight: 600, color: "#f43f5e", display: "flex", alignItems: "center", gap: "0.375rem" }}>
                <span style={{ width: "0.375rem", height: "0.375rem", borderRadius: "50%", background: "#f43f5e", display: "inline-block" }} />
                Listening for speech dictation…
              </div>
            )}

            <textarea
              ref={textareaRef}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={handleComposerKeyDown}
              rows={1}
              aria-label="Message"
              placeholder={
                isReadOnlyCli
                  ? "CLI session is read-only — open a project to chat"
                  : noProviderSelected
                    ? "Choose an AI provider to start chatting"
                    : providerBlocked
                      ? `${activeConnection?.name || "This provider"} is unavailable`
                      : "Message Jaeger AI…"
              }
              disabled={isBusy || isReadOnlyCli || cannotSend}
              style={{ width: "100%", padding: "0.8125rem 1rem 0.5rem", background: "transparent", border: "none", outline: "none", color: H.text, fontSize: "0.9062rem", lineHeight: 1.5, resize: "none", fontFamily: "inherit", boxSizing: "border-box", maxHeight: "11.25rem", overflowY: "auto" }}
              onInput={(e) => { const el = e.currentTarget; el.style.height = "auto"; el.style.height = Math.min(el.scrollHeight, 180) + "px"; }}
            />

            {/* Toolbar — scrolls horizontally on narrow viewports (Hermes cf-burger pattern) */}
            <div className="conversation-toolbar" style={{ display: "flex", alignItems: "center", padding: "0.25rem 0.5rem 0.5rem", gap: "0.25rem", overflowX: "auto", whiteSpace: "nowrap", scrollbarWidth: "none", msOverflowStyle: "none", WebkitOverflowScrolling: "touch", maxWidth: "100%" }}>
              <IconBtn title="Attach files" onClick={() => fileInputRef.current?.click()}><Paperclip size={15} /></IconBtn>
              <IconBtn title="Saved prompts" onClick={() => setShowSavedPrompts(!showSavedPrompts)}><Bookmark size={15} /></IconBtn>
              <IconBtn title="Dictate" onClick={toggleDictation}>
                {isListening ? <MicOff size={15} style={{ color: "#f43f5e" }} /> : <Mic size={15} />}
              </IconBtn>

              <div style={{ width: "0.0625rem", height: "1rem", background: H.border2, margin: "0 0.1875rem", flexShrink: 0 }} />

              {/* JaegerAI Character Chip — default is onboarding character, list shows all personalities */}
              <div data-menu-wrapper style={{ position: "relative", flexShrink: 0 }} onClick={(e) => e.stopPropagation()}>
                <button
                  type="button"
                  style={{ display: "inline-flex", alignItems: "center", gap: "0.3125rem", height: "1.625rem", padding: "0 0.5rem", borderRadius: "0.375rem", border: "1px solid rgba(8,235,241,0.2)", background: "rgba(8,235,241,0.05)", color: H.accentGlow, fontSize: "0.75rem", fontWeight: 500, cursor: "pointer" }}
                  onClick={() => setShowSiModeMenu(!showSiModeMenu)}
                >
                  <Boxes size={12} />
                  <span>{selectedPersonality || profile.assistantName || "Jaeger AI"}</span>
                  <ChevronDown size={9} style={{ opacity: 0.5, flexShrink: 0 }} />
                </button>
                {showSiModeMenu && (
                  <div style={{ position: "absolute", left: "0rem", bottom: "2.125rem", zIndex: 40, width: "22rem", maxWidth: "min(22rem, 88vw)", borderRadius: "0.75rem", border: `1px solid ${H.border2}`, background: "#131622", boxShadow: "0 1rem 3rem rgba(0,0,0,0.7)", fontSize: "0.75rem", overflow: "hidden" }}>
                    <div style={{ padding: "0.625rem 0.875rem 0.375rem", fontSize: "0.6875rem", fontWeight: 600, color: H.muted, borderBottom: `1px solid ${H.border}` }}>
                      Jaeger AI Character
                    </div>
                    <div style={{ padding: "0.75rem 0.875rem", background: "rgba(8,235,241,0.1)", borderBottom: `1px solid ${H.border}` }}>
                      <div style={{ fontWeight: 600, color: H.strong, fontSize: "0.8125rem", marginBottom: "0.25rem" }}>{profile.assistantName || "Jaeger AI"}</div>
                      <div style={{ fontSize: "0.6875rem", color: H.muted, lineHeight: 1.5 }}>
                        {profile.character || "grounded"} · {profile.autonomy || "confirm"} — your persistent agent determines context and delegates to workers.
                      </div>
                    </div>
                    {/* Character / Personality list */}
                    <div style={{ padding: "0.5rem 0.625rem", borderBottom: `1px solid ${H.border}` }}>
                      <div style={{ fontSize: "0.625rem", fontWeight: 700, textTransform: "uppercase", letterSpacing: "0.08em", color: H.muted, marginBottom: "0.375rem" }}>Character</div>
                      {PERSONALITY_OPTIONS.map((p) => (
                        <button
                          key={p.id}
                          type="button"
                          onClick={() => {
                            setSelectedPersonality(p.id);
                            setShowSiModeMenu(false);
                          }}
                          style={{
                            display: "flex", alignItems: "center", gap: "0.5rem", width: "100%", padding: "0.5rem 0.625rem", marginBottom: "0.25rem",
                            borderRadius: "0.375rem", border: `1px solid ${selectedPersonality === p.id ? H.accentGlow : H.border}`,
                            background: selectedPersonality === p.id ? "rgba(8,235,241,0.1)" : "transparent",
                            color: H.text, textAlign: "left", cursor: "pointer",
                          }}
                        >
                          <div>
                            <div style={{ fontWeight: 600, fontSize: "0.75rem" }}>{p.label}</div>
                            <div style={{ fontSize: "0.625rem", color: H.muted, lineHeight: 1.4 }}>{p.detail}</div>
                          </div>
                          {selectedPersonality === p.id && <Check size={11} style={{ marginLeft: "auto", color: H.accentGlow }} />}
                        </button>
                      ))}
                    </div>
                    {/* Delegation Agents / Backends */}
                    <div style={{ padding: "0.5rem 0.625rem", borderBottom: `1px solid ${H.border}` }}>
                      <div style={{ fontSize: "0.625rem", fontWeight: 700, textTransform: "uppercase", letterSpacing: "0.08em", color: H.muted, marginBottom: "0.375rem" }}>Delegation Workers</div>
                      {backendOptions.map((b) => (
                        <button
                          key={b.id}
                          type="button"
                          onClick={() => {
                            setSelectedBackend(b.id);
                            setShowSiModeMenu(false);
                          }}
                          style={{
                            display: "flex", alignItems: "center", gap: "0.5rem", width: "100%", padding: "0.5rem 0.625rem", marginBottom: "0.25rem",
                            borderRadius: "0.375rem", border: `1px solid ${selectedBackend === b.id ? H.accentGlow : H.border}`,
                            background: selectedBackend === b.id ? "rgba(8,235,241,0.1)" : "transparent",
                            color: H.text, textAlign: "left", cursor: "pointer",
                          }}
                        >
                          <Server size={11} style={{ opacity: 0.7, color: selectedBackend === b.id ? H.accentGlow : H.muted }} />
                          <div>
                            <div style={{ fontWeight: 600, fontSize: "0.75rem" }}>{b.label}</div>
                            <div style={{ fontSize: "0.625rem", color: H.muted, fontFamily: "monospace" }}>{b.detail || b.id}</div>
                          </div>
                          {selectedBackend === b.id && <Check size={11} style={{ marginLeft: "auto", color: H.accentGlow }} />}
                        </button>
                      ))}
                    </div>
                    <div style={{ padding: "0.5rem 0.625rem", fontSize: "0.625rem", color: H.muted, lineHeight: 1.5 }}>
                      <strong>Jaeger AI</strong> is your persistent agent. It understands your intent, selects the right character, and delegates to workers.
                    </div>
                  </div>
                )}
              </div>

              {/* Working folder — agent cwd / project context */}
              <div data-menu-wrapper style={{ position: "relative", display: "inline-flex", alignItems: "center", borderRadius: "0.375rem", border: `1px solid ${H.chipBorder}`, background: H.chipBg, height: "1.625rem", overflow: "visible", flexShrink: 0 }} onClick={(e) => e.stopPropagation()}>
                <button
                  type="button"
                  title="Browse files in working folder"
                  onClick={workbenchPanel.toggle}
                  style={{ display: "inline-flex", alignItems: "center", justifyContent: "center", padding: "0 0.375rem", height: "100%", border: "none", borderRight: `1px solid ${H.chipBorder}`, background: "transparent", color: H.chipText, cursor: "pointer" }}
                >
                  <Folder size={12} />
                </button>

                <button
                  type="button"
                  title={workspacePath || "Working folder"}
                  onClick={() => {
                    setShowWorkspaceMenu(!showWorkspaceMenu);
                    setShowBackendMenu(false);
                    setShowModelMenu(false);
                  }}
                  style={{ display: "inline-flex", alignItems: "center", gap: "0.3125rem", height: "100%", padding: "0 0.5rem", border: "none", background: "transparent", color: H.chipText, fontSize: "0.75rem", fontWeight: 500, cursor: "pointer", maxWidth: "8.125rem" }}
                >
                  <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{activeWorkspaceLabel}</span>
                  <ChevronDown size={9} style={{ opacity: 0.5, flexShrink: 0 }} />
                </button>

                {showWorkspaceMenu && (
                  <div style={{ position: "absolute", left: "0rem", bottom: "2.125rem", zIndex: 40, width: "22.5rem", maxWidth: "min(21.25rem, 88vw)", borderRadius: "0.75rem", border: `1px solid ${H.border2}`, background: "#131622", boxShadow: "0 1rem 3rem rgba(0,0,0,0.7)", fontSize: "0.75rem", overflow: "hidden" }}>
                    <div style={{ padding: "0.625rem 0.875rem 0.375rem", fontSize: "0.6875rem", fontWeight: 600, color: H.muted, borderBottom: `1px solid ${H.border}` }}>
                      Agent working folder (cwd / context)
                    </div>
                    <div style={{ padding: "0.75rem 0.875rem", background: "rgba(124,58,237,0.12)", borderBottom: `1px solid ${H.border}` }}>
                      <div style={{ fontWeight: 600, color: H.strong, fontSize: "0.8125rem", marginBottom: "0.125rem" }}>{activeWorkspaceLabel}</div>
                      <div style={{ fontSize: "0.6875rem", color: H.muted, fontFamily: "monospace", wordBreak: "break-all" }}>
                        {workspacePath || "No working folder set"}
                      </div>
                    </div>
                    <div style={{ padding: "0.5rem 0.625rem", borderBottom: `1px solid ${H.border}` }}>
                      <input
                        type="text"
                        value={wsSearchQuery}
                        onChange={(e) => setWsSearchQuery(e.target.value)}
                        placeholder="Filter known folders…"
                        style={{ width: "100%", boxSizing: "border-box", background: "#0c0e18", border: `1px solid ${H.border}`, borderRadius: "0.5rem", padding: "0.375rem 0.625rem", color: H.text, fontSize: "0.75rem", outline: "none" }}
                      />
                    </div>
                    <div style={{ maxHeight: "10rem", overflowY: "auto", padding: "0.375rem 0.5rem" }}>
                      {workspaceChoices
                        .filter((w) => {
                          const q = wsSearchQuery.trim().toLowerCase();
                          if (!q) return true;
                          return w.path.toLowerCase().includes(q) || w.label.toLowerCase().includes(q);
                        })
                        .map((w) => (
                          <button
                            key={w.path}
                            type="button"
                            onClick={() => {
                              setWorkspaceOverride(w.path);
                              setShowWorkspaceMenu(false);
                            }}
                            style={{
                              display: "block", width: "100%", textAlign: "left", padding: "0.5rem 0.625rem", marginBottom: "0.25rem",
                              borderRadius: "0.375rem", border: `1px solid ${workspacePath === w.path ? H.accent : H.border}`,
                              background: workspacePath === w.path ? "rgba(124,58,237,0.1)" : "transparent",
                              color: H.text, cursor: "pointer",
                            }}
                          >
                            <div style={{ fontWeight: 600, fontSize: "0.75rem" }}>{w.label.split("/").filter(Boolean).pop() || w.label}</div>
                            <div style={{ fontSize: "0.625rem", color: H.muted, fontFamily: "monospace", wordBreak: "break-all" }}>{w.path}</div>
                          </button>
                        ))}
                    </div>
                    <div style={{ display: "flex", flexDirection: "column", borderTop: `1px solid ${H.border}` }}>
                      <button
                        type="button"
                        onClick={() => {
                          const path = prompt("Working folder for this agent:", workspacePath || "");
                          if (path?.trim()) setWorkspaceOverride(path.trim());
                          setShowWorkspaceMenu(false);
                        }}
                        style={{ display: "flex", alignItems: "flex-start", gap: "0.75rem", padding: "0.625rem 0.875rem", background: "transparent", border: "none", borderBottom: `1px solid ${H.border}`, color: H.text, textAlign: "left", cursor: "pointer" }}
                      >
                        <Folder size={16} style={{ color: H.accentGlow, marginTop: "0.125rem", flexShrink: 0 }} />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: "0.7812rem", color: H.strong }}>Set working folder…</div>
                          <div style={{ fontSize: "0.6875rem", color: H.muted, marginTop: "0.125rem" }}>cwd / project context for the backend</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          void createSession(workspacePath || undefined);
                          setShowWorkspaceMenu(false);
                        }}
                        style={{ display: "flex", alignItems: "flex-start", gap: "0.75rem", padding: "0.625rem 0.875rem", background: "transparent", border: "none", borderBottom: `1px solid ${H.border}`, color: H.text, textAlign: "left", cursor: "pointer" }}
                      >
                        <GitBranch size={16} style={{ color: H.accentGlow, marginTop: "0.125rem", flexShrink: 0 }} />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: "0.7812rem", color: H.strong }}>New project here</div>
                          <div style={{ fontSize: "0.6875rem", color: H.muted, marginTop: "0.125rem" }}>Fresh session in this folder</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          workbenchPanel.toggle();
                          setShowWorkspaceMenu(false);
                        }}
                        style={{ display: "flex", alignItems: "flex-start", gap: "0.75rem", padding: "0.625rem 0.875rem", background: "transparent", border: "none", color: H.text, textAlign: "left", cursor: "pointer" }}
                      >
                        <Settings size={16} style={{ color: H.muted, marginTop: "0.125rem", flexShrink: 0 }} />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: "0.7812rem", color: H.strong }}>Browse files</div>
                          <div style={{ fontSize: "0.6875rem", color: H.muted, marginTop: "0.125rem" }}>Open workspace panel</div>
                        </div>
                      </button>
                    </div>
                  </div>
                )}
              </div>

              {/* Model chip — Auto (Jaeger AI picks) + manual LLM selection */}
              <div data-menu-wrapper style={{ position: "relative", flexShrink: 0 }} onClick={(e) => e.stopPropagation()}>
                <ComposerChip
                  icon={<Package size={12} />}
                  label={selectedModel === "auto" ? "Auto" : activeModelLabel}
                  onClick={() => {
                    if (isReadOnlyCli) return;
                    setShowModelMenu(!showModelMenu);
                    setShowWorkspaceMenu(false);
                    setShowBackendMenu(false);
                  }}
                />
                {showModelMenu && !isReadOnlyCli && (
                  <div style={{ position: "absolute", left: "0rem", bottom: "2.125rem", zIndex: 40, width: "22rem", maxWidth: "min(22rem, 88vw)", borderRadius: "0.75rem", border: `1px solid ${H.border2}`, background: "#131622", boxShadow: "0 1rem 3rem rgba(0,0,0,0.7)", fontSize: "0.75rem", overflow: "hidden" }}>
                    <div style={{ padding: "0.625rem 0.875rem 0.375rem", fontSize: "0.6875rem", fontWeight: 600, color: H.muted, borderBottom: `1px solid ${H.border}` }}>
                      Select Model
                    </div>
                    {/* Auto option — Jaeger AI decides */}
                    <div style={{ padding: "0.5rem 0.625rem", borderBottom: `1px solid ${H.border}` }}>
                      <button
                        type="button"
                        onClick={() => { setSelectedModel("auto"); setSelectedModelProvider(""); setShowModelMenu(false); }}
                        style={{
                          display: "flex", alignItems: "center", gap: "0.5rem", width: "100%", padding: "0.5rem 0.625rem",
                          borderRadius: "0.375rem", border: `1px solid ${selectedModel === "auto" ? H.accentGlow : H.border}`,
                          background: selectedModel === "auto" ? "rgba(8,235,241,0.1)" : "transparent", color: H.text, cursor: "pointer", textAlign: "left",
                        }}
                      >
                        <div>
                          <div style={{ fontWeight: 600, fontSize: "0.75rem", display: "inline-flex", alignItems: "center", gap: "0.375rem" }}>
                            <Boxes size={11} style={{ opacity: 0.7 }} />
                            Auto
                            {selectedModel === "auto" && <span style={{ fontSize: "0.5625rem", fontWeight: 700, padding: "1px 0.3125rem", borderRadius: "0.25rem", background: H.accentGlow, color: "#fff" }}>ACTIVE</span>}
                          </div>
                          <div style={{ fontSize: "0.625rem", color: H.muted }}>Jaeger AI selects the best model for your request</div>
                        </div>
                        {selectedModel === "auto" && <Check size={11} style={{ marginLeft: "auto", color: H.accentGlow }} />}
                      </button>
                    </div>
                    {/* Models grouped by location (local first, then cloud) */}
                    {(["local", "cloud", "unknown"] as const).map((loc) => {
                      const group = modelsForBackend.filter((m) => (m.location || "unknown") === loc);
                      if (!group.length) return null;
                      return (
                        <div key={loc} style={{ padding: "0.25rem 0.625rem 0.375rem" }}>
                          <div style={{ fontSize: "0.625rem", fontWeight: 700, textTransform: "uppercase", letterSpacing: "0.08em", color: H.muted, margin: "0.25rem 0.125rem 0.375rem" }}>
                            {loc === "local" ? "Local models" : loc === "cloud" ? "Cloud models" : "Other"}
                          </div>
                          {group.map((m) => (
                            <button
                              key={`${m.id}-${m.provider || ""}`}
                              type="button"
                              onClick={() => {
                                setSelectedModel(m.id);
                                setSelectedModelProvider(m.provider || "");
                                setShowModelMenu(false);
                              }}
                              style={{
                                display: "block", width: "100%", textAlign: "left", padding: "0.5rem 0.625rem", marginBottom: "0.25rem",
                                borderRadius: "0.375rem", border: `1px solid ${selectedModel === m.id ? H.accent : H.border}`,
                                background: selectedModel === m.id ? "rgba(124,58,237,0.1)" : "transparent", color: H.text, cursor: "pointer",
                              }}
                            >
                              <div style={{ fontWeight: 600, fontSize: "0.75rem", display: "inline-flex", alignItems: "center", gap: "0.375rem" }}>
                                <Package size={11} style={{ opacity: 0.7 }} />
                                {m.label || m.id}
                                {m.in_use ? (
                                  <span style={{ fontSize: "0.5625rem", fontWeight: 700, padding: "1px 0.3125rem", borderRadius: "0.25rem", background: H.accent, color: "#fff" }}>ACTIVE</span>
                                ) : null}
                              </div>
                              <div style={{ fontSize: "0.625rem", color: H.muted, fontFamily: "monospace" }}>
                                {m.provider || "—"}{m.notes ? ` · ${m.notes}` : ""}
                              </div>
                            </button>
                          ))}
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>

              <div style={{ flex: 1 }} />

              {/* Reasoning Effort Chip */}
              <div data-menu-wrapper style={{ position: "relative", flexShrink: 0 }} onClick={(e) => e.stopPropagation()}>
                <ComposerChip
                  icon={<Brain size={12} />}
                  label={REASONING_OPTIONS.find(o => o.value === selectedReasoning)?.label || "Medium"}
                  onClick={() => {
                    if (isReadOnlyCli) return;
                    setShowReasoningMenu(!showReasoningMenu);
                    setShowBackendMenu(false);
                    setShowModelMenu(false);
                    setShowWorkspaceMenu(false);
                    setShowSiModeMenu(false);
                    setShowToolsetMenu(false);
                  }}
                />
                {showReasoningMenu && !isReadOnlyCli && (
                  <div style={{ position: "absolute", right: 0, bottom: "2.125rem", zIndex: 40, width: "14rem", maxWidth: "min(14rem, 88vw)", borderRadius: "0.75rem", border: `1px solid ${H.border2}`, background: "#131622", boxShadow: "0 1rem 3rem rgba(0,0,0,0.7)", fontSize: "0.75rem", overflow: "hidden" }}>
                    <div style={{ padding: "0.625rem 0.875rem 0.375rem", fontSize: "0.6875rem", fontWeight: 600, color: H.muted, borderBottom: `1px solid ${H.border}` }}>
                      Reasoning Effort
                    </div>
                    <div style={{ padding: "0.375rem 0.5rem" }}>
                      {REASONING_OPTIONS.map((opt) => (
                        <button
                          key={opt.value}
                          type="button"
                          onClick={() => { setSelectedReasoning(opt.value); setShowReasoningMenu(false); }}
                          style={{
                            display: "flex", alignItems: "center", justifyContent: "space-between", width: "100%", padding: "0.375rem 0.625rem", marginBottom: "0.125rem",
                            borderRadius: "0.375rem", border: `1px solid ${selectedReasoning === opt.value ? H.accentGlow : H.border}`,
                            background: selectedReasoning === opt.value ? "rgba(8,235,241,0.1)" : "transparent",
                            color: H.text, textAlign: "left", cursor: "pointer", fontSize: "0.75rem",
                          }}
                        >
                          <span style={{ fontWeight: selectedReasoning === opt.value ? 600 : 400 }}>{opt.label}</span>
                          {selectedReasoning === opt.value && <Check size={11} style={{ color: H.accentGlow }} />}
                        </button>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              {/* YOLO / Auto-Approve Toggle */}
              <button
                type="button"
                title={yoloMode ? "YOLO mode: auto-approve all tool calls" : "Manual approval: confirm each tool call"}
                onClick={() => setYoloMode(!yoloMode)}
                style={{
                  display: "inline-flex", alignItems: "center", gap: "0.25rem", height: "1.625rem", padding: "0 0.5rem",
                  borderRadius: "0.375rem", border: `1px solid ${yoloMode ? "#ef4444" : H.chipBorder}`,
                  background: yoloMode ? "rgba(239,68,68,0.12)" : H.chipBg,
                  color: yoloMode ? "#ef4444" : H.chipText, fontSize: "0.75rem", fontWeight: 500, cursor: "pointer",
                  transition: "all 0.15s", flexShrink: 0,
                }}
              >
                <Zap size={12} style={{ opacity: 0.8 }} />
                <span style={{ fontSize: "0.6875rem" }}>YOLO</span>
              </button>

              {/* Toolsets Chip */}
              <div data-menu-wrapper style={{ position: "relative", flexShrink: 0 }} onClick={(e) => e.stopPropagation()}>
                <ComposerChip
                  icon={<WrenchIcon size={12} />}
                  label="Global"
                  onClick={() => {
                    if (isReadOnlyCli) return;
                    setShowToolsetMenu(!showToolsetMenu);
                    setShowBackendMenu(false);
                    setShowModelMenu(false);
                    setShowWorkspaceMenu(false);
                    setShowSiModeMenu(false);
                    setShowReasoningMenu(false);
                  }}
                />
                {showToolsetMenu && !isReadOnlyCli && (
                  <div style={{ position: "absolute", right: 0, bottom: "2.125rem", zIndex: 40, width: "16rem", maxWidth: "min(16rem, 88vw)", borderRadius: "0.75rem", border: `1px solid ${H.border2}`, background: "#131622", boxShadow: "0 1rem 3rem rgba(0,0,0,0.7)", fontSize: "0.75rem", overflow: "hidden" }}>
                    <div style={{ padding: "0.625rem 0.875rem 0.375rem", fontSize: "0.6875rem", fontWeight: 600, color: H.muted, borderBottom: `1px solid ${H.border}` }}>
                      Toolsets
                    </div>
                    <div style={{ padding: "0.75rem 0.875rem", background: "rgba(8,235,241,0.05)", borderBottom: `1px solid ${H.border}` }}>
                      <div style={{ fontWeight: 600, color: H.strong, fontSize: "0.8125rem", marginBottom: "0.125rem" }}>Global</div>
                      <div style={{ fontSize: "0.6875rem", color: H.muted, lineHeight: 1.5 }}>All available tools enabled. Select per-tool control in Settings.</div>
                    </div>
                    <div style={{ padding: "0.5rem 0.625rem", fontSize: "0.625rem", color: H.muted, lineHeight: 1.5 }}>
                      <strong>Global</strong> mode uses all tools the backend provides. Per-tool filtering is available in the Settings page.
                    </div>
                  </div>
                )}
              </div>

              {/* Context window usage ring — shows message count as session progress */}
              <div style={{ display: "inline-flex", alignItems: "center", justifyContent: "center", width: "1.625rem", height: "1.625rem", borderRadius: "50%", background: H.surface, border: `1px solid ${H.border}`, color: H.muted, flexShrink: 0, marginRight: "0.25rem", position: "relative" }} title={`Context: ${currentSession?.messageCount ?? 0} messages`}>
                <svg viewBox="0 0 24 24" width="16" height="16" style={{ transform: "rotate(-90deg)" }}>
                  <circle cx="12" cy="12" r="9.75" fill="none" stroke="currentColor" strokeWidth="2.5" opacity="0.2" />
                </svg>
                <span style={{ position: "absolute", fontSize: "0.45rem", fontWeight: 700, color: H.text }}>{currentSession?.messageCount ?? 0}</span>
              </div>

              {isBusy ? (
                <button type="button" onClick={() => void cancelResponse()} title="Stop response"
                  style={{ width: "2.125rem", height: "2.125rem", borderRadius: "50%", border: `1px solid ${H.border2}`, background: H.surface, color: H.text, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>
                  <Square size={14} fill="currentColor" />
                </button>
              ) : (
                <button type="submit" disabled={!draft.trim() && attachedFiles.length === 0} title="Send message"
                  style={{ width: "2.125rem", height: "2.125rem", borderRadius: "50%", border: "none", background: draft.trim() || attachedFiles.length > 0 ? H.sendBtn : "rgba(255,255,255,0.06)", color: draft.trim() || attachedFiles.length > 0 ? H.sendBtnText : "rgba(255,255,255,0.25)", cursor: draft.trim() || attachedFiles.length > 0 ? "pointer" : "default", display: "flex", alignItems: "center", justifyContent: "center", transition: "background 0.15s, color 0.15s" }}>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/></svg>
                </button>
              )}
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}

import {
  ArrowDown,
  ArrowUp,
  BookOpen,
  ChevronDown,
  ChevronRight,
  Command,
  Eye,
  EyeOff,
  Folder,
  Globe,
  Heart,
  MessageCircle,
  Monitor,
  MoreVertical,
  Plus,
  Search,
  Server,
  Settings,
  SlidersHorizontal,
  Sparkles,
  Tag,
  Terminal,
  Wrench,
  Link2,
  Pencil,
  Share2,
  Pin,
  FolderInput,
  Archive,
  Download,
  Trash2,
  RefreshCw,
  type LucideIcon,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { NavLink, useLocation, useNavigate } from "react-router-dom";

import { navigationSections, type NavigationSection } from "@/app-navigation";
import { cn } from "@/lib/utils";
import { apiFetch } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import { useLocalProfile } from "@/shared/local-profile";

// ─────────────────────────────────────────────────────────────
// Types & Metadata
// ─────────────────────────────────────────────────────────────
type DeckMode = NavigationSection["id"];

interface DiscoveredBackend {
  adapter_id: string;
  display_name: string;
  detected: boolean;
}

interface ProjectItem {
  id: string;
  name: string;
}

interface SessionOverride {
  source?: "webui" | "cli";
  backendId?: string;
  title?: string;
}

/** Rail order: Chat · Companion · Self · Workshop · Library · System */
const modes: Array<{ id: DeckMode; label: string; icon: LucideIcon; to: string }> = [
  { id: "chat", label: "Chat", icon: MessageCircle, to: "/chat" },
  { id: "companion", label: "Companion", icon: Sparkles, to: "/companion" },
  { id: "self", label: "Self", icon: Heart, to: "/self" },
  { id: "workshop", label: "Workshop", icon: Wrench, to: "/workshop" },
  { id: "library", label: "Library", icon: BookOpen, to: "/library" },
  { id: "system", label: "System", icon: Server, to: "/system" },
];

// Maps backend adapter IDs to friendly display info
const BACKEND_META: Record<string, { label: string; color: string }> = {
  hermes_local:   { label: "Hermes",      color: "#08EBF1" },
  jros_local:     { label: "JROS",        color: "#3889FD" },
  claude_local:   { label: "Claude Code", color: "#D97706" },
  codex_local:    { label: "Codex",       color: "#10B981" },
  gemini_local:   { label: "Gemini",      color: "#6366F1" },
  grok_local:     { label: "Grok",        color: "#8B5CF6" },
  opencode_local: { label: "OpenCode",    color: "#EC4899" },
  cursor_local:   { label: "Cursor",      color: "#06B6D4" },
  ollama_local:   { label: "Ollama",      color: "#F59E0B" },
  openai_cloud:   { label: "OpenAI",      color: "#10A37F" },
  xai_cloud:      { label: "xAI Grok",    color: "#8B5CF6" },
  pi_local:       { label: "Pi",          color: "#F472B6" },
};

function backendLabel(id: string): string {
  return BACKEND_META[id]?.label
    ?? id.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function backendColor(id: string): string {
  return BACKEND_META[id]?.color ?? "#6b7194";
}

function sectionForPath(pathname: string): DeckMode {
  if (pathname.startsWith("/chat") || pathname.startsWith("/conversation")) return "chat";
  if (pathname.startsWith("/self/")) return "self";
  // Prefer longest matching route prefix so /system wins over accidental shorts.
  let best: { id: DeckMode; len: number } | null = null;
  for (const section of navigationSections) {
    for (const route of section.routes) {
      if (pathname === route.to || pathname.startsWith(`${route.to}/`)) {
        if (!best || route.to.length > best.len) best = { id: section.id, len: route.to.length };
      }
    }
    if (pathname === section.home || pathname.startsWith(`${section.home}/`)) {
      if (!best || section.home.length > best.len) best = { id: section.id, len: section.home.length };
    }
  }
  return best?.id ?? "companion";
}

/**
 * CLI sessions are frequently persisted with their working directory as the
 * title, which truncates to an unreadable "/Users/m…" in the sidebar. Show the
 * final path segment instead so rows stay distinguishable.
 */
function displayTitle(title: string | undefined): string {
  const clean = (title ?? "").trim();
  if (!clean) return "Untitled";
  if (!clean.startsWith("/") && !clean.startsWith("~/")) return clean;
  const segments = clean.replace(/\/+$/, "").split("/").filter(Boolean);
  return segments.length ? segments[segments.length - 1] : clean;
}

const DATE_GROUP_ORDER = ["Today", "Yesterday", "Last week", "Older"] as const;
type DateGroup = (typeof DATE_GROUP_ORDER)[number];

/** Bucket a session by calendar day so the sidebar reads chronologically. */
function dateGroupFor(iso: string | undefined): DateGroup {
  if (!iso) return "Older";
  const then = new Date(iso);
  if (Number.isNaN(then.getTime())) return "Older";
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const startOfThen = new Date(then);
  startOfThen.setHours(0, 0, 0, 0);
  const days = Math.round((startOfToday.getTime() - startOfThen.getTime()) / 86_400_000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  if (days < 7) return "Last week";
  return "Older";
}

function relativeTime(iso: string | undefined): string {
  if (!iso) return "";
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (diff < 60) return "now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  return `${Math.floor(diff / 86400)}d`;
}

// ─────────────────────────────────────────────────────────────
// Sub-components
// ─────────────────────────────────────────────────────────────

/** Session mutations, owned by ControlDeck so every row shares one implementation. */
interface SessionActions {
  copyLink: (sessionId: string) => void;
  rename: (sessionId: string, currentTitle: string) => void;
  share: (sessionId: string) => void;
  pin: (sessionId: string, pinned: boolean) => void;
  archive: (sessionId: string) => void;
  exportHtml: (sessionId: string) => void;
  regenerateTitle: (sessionId: string) => void;
  remove: (sessionId: string, title: string) => void;
}

/** A single session row with a right-click / ⋮ context menu. */
function SessionRow({
  sessionId,
  title,
  updatedAt,
  projectName,
  projects,
  isActive,
  isStreaming,
  readOnly,
  pinned,
  onClick,
  onAssignProject,
  onOpenEdit,
  actions,
}: {
  sessionId: string;
  title: string;
  updatedAt?: string;
  projectName?: string;
  projects: ProjectItem[];
  isActive: boolean;
  isStreaming?: boolean;
  readOnly?: boolean;
  pinned?: boolean;
  onClick: () => void;
  onAssignProject: (sessionId: string, projectId: string | null) => void;
  onOpenEdit: (sessionId: string) => void;
  actions: SessionActions;
}) {
  const [menuAt, setMenuAt] = useState<{ x: number; y: number } | null>(null);
  const [showProjects, setShowProjects] = useState(false);

  const closeMenu = useCallback(() => {
    setMenuAt(null);
    setShowProjects(false);
  }, []);

  // Dismiss on outside click, Escape, or any scroll (the menu is fixed-position
  // so it would otherwise detach from the row it belongs to).
  useEffect(() => {
    if (!menuAt) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") closeMenu(); };
    document.addEventListener("pointerdown", closeMenu);
    document.addEventListener("keydown", onKey);
    window.addEventListener("scroll", closeMenu, true);
    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      document.removeEventListener("keydown", onKey);
      window.removeEventListener("scroll", closeMenu, true);
    };
  }, [menuAt, closeMenu]);

  const openMenuAt = (x: number, y: number) => {
    // Keep the menu on-screen when the row sits near the viewport edge.
    const width = 200;
    const height = 340;
    setMenuAt({
      x: Math.min(x, window.innerWidth - width - 8),
      y: Math.min(y, window.innerHeight - height - 8),
    });
  };

  const run = (fn: () => void) => {
    closeMenu();
    fn();
  };

  return (
    <div
      className="relative group"
      onContextMenu={(e) => {
        e.preventDefault();
        openMenuAt(e.clientX, e.clientY);
      }}
    >
      <button
        type="button"
        onClick={onClick}
        className={cn(
          "w-full text-left px-3 py-[7px] pr-14 flex items-center gap-2 text-[12px] transition-colors border-l-2",
          isActive
            ? "border-[#5b7cf6] bg-[#1e2035] text-[#f0f2ff] font-medium"
            : "border-transparent text-[#92948b] hover:bg-[#1a1b19] hover:text-[#ecebe4]",
        )}
      >
        {isStreaming && (
          <span className="shrink-0 size-1.5 rounded-full bg-[#08EBF1] animate-pulse" />
        )}
        {pinned && <Pin className="size-2.5 shrink-0 text-[#8ba2ff]" aria-label="Pinned" />}
        <span className="truncate flex-1">{title || "Untitled"}</span>

        {projectName && (
          <span className="shrink-0 text-[10px] px-1.5 py-0.5 rounded bg-[#5b7cf6]/20 text-[#8ba2ff] font-medium max-w-[70px] truncate">
            {projectName}
          </span>
        )}
      </button>

      {/* Kept a sibling of the row button — nesting interactive elements is invalid HTML. */}
      <div className="pointer-events-none absolute inset-y-0 right-2 flex items-center gap-1">
        {updatedAt && (
          <span className="text-[10px] text-[#6f7169]">{relativeTime(updatedAt)}</span>
        )}
        <button
          type="button"
          title="Session menu"
          aria-label="Session menu"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation();
            const r = e.currentTarget.getBoundingClientRect();
            if (menuAt) closeMenu();
            else openMenuAt(r.right, r.bottom + 4);
          }}
          className="pointer-events-auto opacity-0 group-hover:opacity-100 focus-visible:opacity-100 p-0.5 rounded text-[#6f7169] hover:text-[#ecebe4] hover:bg-[#2a2d3d] transition-all"
        >
          <MoreVertical className="size-3" />
        </button>
      </div>

      {menuAt && (
        <div
          role="menu"
          style={{ left: menuAt.x, top: menuAt.y }}
          className="fixed z-50 w-50 rounded-md border border-[#343631] bg-[#1a1c24] p-1 shadow-2xl text-[11px]"
          onPointerDown={(e) => e.stopPropagation()}
        >
          <MenuItem icon={Link2} label="Copy conversation link" onClick={() => run(() => actions.copyLink(sessionId))} />
          <MenuItem
            icon={Pencil}
            label="Rename conversation"
            disabled={readOnly}
            hint={readOnly ? "Read-only" : undefined}
            onClick={() => run(() => actions.rename(sessionId, title))}
          />
          <MenuItem icon={Share2} label="Share" onClick={() => run(() => actions.share(sessionId))} />
          <MenuItem
            icon={Pin}
            label={pinned ? "Unpin conversation" : "Pin conversation"}
            disabled={readOnly}
            hint={readOnly ? "Read-only" : undefined}
            onClick={() => run(() => actions.pin(sessionId, !pinned))}
          />

          <div className="my-1 border-t border-[#2d303e]" />

          <MenuItem
            icon={FolderInput}
            label="Move to project"
            trailing={<ChevronRight className="size-3 opacity-60" />}
            onClick={() => setShowProjects((v) => !v)}
          />
          {showProjects && (
            <div className="mb-1 ml-2 border-l border-[#2d303e] pl-1">
              <button
                type="button"
                onClick={() => run(() => onAssignProject(sessionId, null))}
                className="w-full text-left px-2 py-1 rounded text-[#8f9188] hover:bg-[#252836] hover:text-[#ecebe4]"
              >
                — Unassigned —
              </button>
              {projects.map((p) => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => run(() => onAssignProject(sessionId, p.id))}
                  className={cn(
                    "w-full text-left px-2 py-1 rounded flex items-center gap-1.5 transition-colors",
                    projectName === p.name
                      ? "bg-[#5b7cf6]/20 text-[#5b7cf6] font-medium"
                      : "text-[#8f9188] hover:bg-[#252836] hover:text-[#ecebe4]",
                  )}
                >
                  <Folder className="size-3 shrink-0" />
                  <span className="truncate">{p.name}</span>
                </button>
              ))}
            </div>
          )}

          <MenuItem
            icon={Archive}
            label="Archive conversation"
            disabled={readOnly}
            hint={readOnly ? "Read-only" : undefined}
            onClick={() => run(() => actions.archive(sessionId))}
          />
          <MenuItem icon={Download} label="Export as HTML" onClick={() => run(() => actions.exportHtml(sessionId))} />
          <MenuItem
            icon={RefreshCw}
            label="Regenerate title"
            disabled={readOnly}
            hint={readOnly ? "Read-only" : undefined}
            onClick={() => run(() => actions.regenerateTitle(sessionId))}
          />

          <div className="my-1 border-t border-[#2d303e]" />

          <MenuItem
            icon={Settings}
            label="Properties…"
            onClick={() => run(() => onOpenEdit(sessionId))}
          />
          <MenuItem
            icon={Trash2}
            label="Delete conversation"
            danger
            disabled={readOnly}
            hint={readOnly ? "Imported history" : undefined}
            onClick={() => run(() => actions.remove(sessionId, title))}
          />
        </div>
      )}
    </div>
  );
}

function MenuItem({
  icon: Icon,
  label,
  onClick,
  disabled,
  danger,
  hint,
  trailing,
}: {
  icon: LucideIcon;
  label: string;
  onClick: () => void;
  disabled?: boolean;
  danger?: boolean;
  hint?: string;
  trailing?: React.ReactNode;
}) {
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      title={hint}
      onClick={onClick}
      className={cn(
        "w-full text-left px-2 py-1.5 rounded flex items-center gap-2 transition-colors",
        disabled
          ? "cursor-not-allowed text-[#4b4d47]"
          : danger
            ? "text-[#e06c6c] hover:bg-[#3a2226]"
            : "text-[#c9cbd4] hover:bg-[#252836] hover:text-[#ecebe4]",
      )}
    >
      <Icon className="size-3 shrink-0" />
      <span className="flex-1 truncate">{label}</span>
      {trailing}
    </button>
  );
}

/** A collapsible group header for a CLI backend */
function BackendGroup({
  backendId,
  detected,
  sessionCount,
  children,
}: {
  backendId: string;
  detected: boolean;
  sessionCount: number;
  children?: React.ReactNode;
}) {
  const [open, setOpen] = useState(detected && sessionCount > 0);
  const color = backendColor(backendId);
  const label = backendLabel(backendId);

  return (
    <div>
      <button
        type="button"
        onClick={() => { if (detected) setOpen((v) => !v); }}
        disabled={!detected}
        className={cn(
          "w-full flex items-center gap-2 px-3 py-[6px] text-[11px] font-semibold uppercase tracking-[0.08em] transition-colors",
          detected ? "hover:bg-[#1a1b19] cursor-pointer" : "cursor-default opacity-50",
        )}
      >
        <span
          className="shrink-0 size-1.5 rounded-full"
          style={{ background: detected ? color : "#343631" }}
        />
        <span className={cn("flex-1 truncate", detected ? "text-[#a7a79d]" : "text-[#6f7169]")}>
          {label}
        </span>
        {detected && sessionCount > 0 && (
          <span
            className="shrink-0 rounded px-1.5 py-0.5 text-[10px] font-bold"
            style={{ background: color + "22", color }}
          >
            {sessionCount}
          </span>
        )}
        {!detected && (
          <span className="shrink-0 text-[10px] text-[#4b4d47] font-normal normal-case tracking-normal">
            offline
          </span>
        )}
        {detected && (
          open
            ? <ChevronDown className="shrink-0 size-3 text-[#6f7169]" />
            : <ChevronRight className="shrink-0 size-3 text-[#6f7169]" />
        )}
      </button>
      {open && detected && (
        <div>{children}</div>
      )}
      {open && detected && sessionCount === 0 && (
        <p className="px-4 py-2 text-[11px] text-[#4b4d47] italic">No active sessions</p>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Main ControlDeck
// ─────────────────────────────────────────────────────────────
export function ControlDeck() {
  const location = useLocation();
  const navigate = useNavigate();
  const { profile } = useLocalProfile();
  const { snapshot, currentSession, selectSession, createSession, refresh } = useAres();
  const activeMode = sectionForPath(location.pathname);

  const openChatSession = useCallback(
    (sessionId: string) => {
      selectSession(sessionId);
      if (!location.pathname.startsWith("/chat") && !location.pathname.startsWith("/conversation")) {
        navigate("/chat");
      }
    },
    [location.pathname, navigate, selectSession],
  );

  const openNewChat = useCallback(() => {
    void createSession().then(() => navigate("/chat"));
  }, [createSession, navigate]);
  const activeSection = navigationSections.find(({ id }) => id === activeMode);
  const routes = useMemo(
    () =>
      activeSection?.routes.filter(
        ({ to }) => to !== "/conversation" && !(activeMode === "chat" && to === "/chat"),
      ) ?? [],
    [activeSection, activeMode],
  );

  /** Bucket routes under their optional group heading, keeping declaration order. */
  const groupedRoutes = useMemo(() => {
    const order: string[] = [];
    const byGroup = new Map<string, typeof routes>();
    for (const route of routes) {
      const key = route.group ?? "";
      if (!byGroup.has(key)) {
        byGroup.set(key, []);
        order.push(key);
      }
      byGroup.get(key)!.push(route);
    }
    return order.map((group) => ({ group, items: byGroup.get(group)! }));
  }, [routes]);

  // State
  const [sessionSearch, setSessionSearch] = useState("");
  const [sourceTab, setSourceTab] = useState<"webui" | "cli">("webui");
  const [activeProject, setActiveProject] = useState<string | null>(null);
  const [backends, setBackends] = useState<DiscoveredBackend[]>([]);

  // Modal states
  const [showBackendOrderModal, setShowBackendOrderModal] = useState(false);
  const [editingSessionId, setEditingSessionId] = useState<string | null>(null);

  // Projects state
  const [projects, setProjects] = useState<ProjectItem[]>(() => {
    try {
      const stored = localStorage.getItem("ares_projects_list");
      return stored ? (JSON.parse(stored) as ProjectItem[]) : [];
    } catch {
      return [];
    }
  });

  const [showAddProject, setShowAddProject] = useState(false);
  const [newProjectName, setNewProjectName] = useState("");

  // Map of sessionId -> projectId
  const [sessionProjectMap, setSessionProjectMap] = useState<Record<string, string>>(() => {
    try {
      const stored = localStorage.getItem("ares_session_projects_map");
      return stored ? (JSON.parse(stored) as Record<string, string>) : {};
    } catch {
      return {};
    }
  });

  // Session property overrides (source, backendId, title)
  const [sessionOverrides, setSessionOverrides] = useState<Record<string, SessionOverride>>(() => {
    try {
      const stored = localStorage.getItem("ares_session_overrides_map");
      return stored ? (JSON.parse(stored) as Record<string, SessionOverride>) : {};
    } catch {
      return {};
    }
  });

  // Custom ordering of CLI backends
  const [cliBackendOrder, setCliBackendOrder] = useState<string[]>(() => {
    try {
      const stored = localStorage.getItem("ares_cli_backend_order");
      return stored ? (JSON.parse(stored) as string[]) : [];
    } catch {
      return [];
    }
  });

  // Hidden CLI backends
  const [hiddenBackends, setHiddenBackends] = useState<string[]>(() => {
    try {
      const stored = localStorage.getItem("ares_hidden_backends");
      return stored ? (JSON.parse(stored) as string[]) : [];
    } catch {
      return [];
    }
  });

  // Fetch discovered backends & projects from API
  useEffect(() => {
    const controller = new AbortController();

    void apiFetch<{ adapters: DiscoveredBackend[] }>("/api/discover/frameworks", { signal: controller.signal })
      .then((data) => { if (!controller.signal.aborted) setBackends(data.adapters || []); })
      .catch(() => {});

    void apiFetch<{ projects?: Array<{ id?: string; name?: string; project_id?: string }> }>("/api/projects", { signal: controller.signal })
      .then((data) => {
        if (controller.signal.aborted || !data.projects) return;
        const fetched: ProjectItem[] = data.projects.map((p) => ({
          id: String(p.id || p.project_id || p.name),
          name: String(p.name || "Untitled"),
        }));
        setProjects((prev) => {
          const merged = [...prev];
          for (const item of fetched) {
            if (!merged.some((m) => m.id === item.id || m.name === item.name)) {
              merged.push(item);
            }
          }
          try { localStorage.setItem("ares_projects_list", JSON.stringify(merged)); } catch {}
          return merged;
        });
      })
      .catch(() => {});

    return () => controller.abort();
  }, []);

  // Save session assignments to localStorage
  const handleAssignProject = useCallback((sessionId: string, projectId: string | null) => {
    setSessionProjectMap((prev) => {
      const next = { ...prev };
      if (projectId) {
        next[sessionId] = projectId;
      } else {
        delete next[sessionId];
      }
      try { localStorage.setItem("ares_session_projects_map", JSON.stringify(next)); } catch {}
      return next;
    });
  }, []);

  // Session mutations. These all hit real endpoints and then refresh, unlike the
  // local-only overrides below.
  const [actionNotice, setActionNotice] = useState("");

  const sessionActions = useMemo<SessionActions>(() => {
    const report = (message: string) => {
      setActionNotice(message);
      window.setTimeout(() => setActionNotice(""), 4000);
    };
    const fail = (err: unknown, fallback: string) =>
      report(err instanceof Error ? err.message : fallback);

    return {
      copyLink: (sessionId) => {
        const url = `${window.location.origin}/chat?session=${encodeURIComponent(sessionId)}`;
        void navigator.clipboard.writeText(url)
          .then(() => report("Conversation link copied."))
          .catch(() => report(url));
      },
      rename: (sessionId, currentTitle) => {
        const next = window.prompt("Rename conversation", currentTitle)?.trim();
        if (!next || next === currentTitle) return;
        void aresApi.renameSession(sessionId, next)
          .then(() => refresh())
          .catch((err) => fail(err, "Could not rename conversation"));
      },
      share: (sessionId) => {
        void aresApi.createShare(sessionId)
          .then((res) => {
            const url = res?.share?.url || "";
            if (!url) return report("Share created.");
            return navigator.clipboard.writeText(url)
              .then(() => report("Share link copied."))
              .catch(() => report(url));
          })
          .catch((err) => fail(err, "Could not create share link"));
      },
      pin: (sessionId, pinned) => {
        void aresApi.pinSession(sessionId, pinned)
          .then(() => refresh())
          .catch((err) => fail(err, "Could not pin conversation"));
      },
      archive: (sessionId) => {
        void aresApi.archiveSession(sessionId, true)
          .then(() => refresh())
          .catch((err) => fail(err, "Could not archive conversation"));
      },
      exportHtml: (sessionId) => {
        void aresApi.exportSession(sessionId, "html")
          .then((html) => {
            const blob = new Blob([String(html)], { type: "text/html" });
            const url = URL.createObjectURL(blob);
            const a = document.createElement("a");
            a.href = url;
            a.download = `${sessionId}.html`;
            a.click();
            URL.revokeObjectURL(url);
          })
          .catch((err) => fail(err, "Could not export conversation"));
      },
      regenerateTitle: (sessionId) => {
        void aresApi.regenerateSessionTitle(sessionId)
          .then(() => refresh())
          .catch((err) => fail(err, "Could not regenerate title"));
      },
      remove: (sessionId, title) => {
        // Deletion drops the transcript; the backend has no undo for it.
        if (!window.confirm(`Delete "${title || "Untitled"}"?\n\nThis permanently removes the conversation and cannot be undone.`)) return;
        void aresApi.deleteSession(sessionId)
          .then(() => refresh())
          .catch((err) => fail(err, "Could not delete conversation"));
      },
    };
  }, [refresh]);

  // Update session overrides (title, source, backendId)
  const handleUpdateSessionOverride = useCallback((sessionId: string, updates: Partial<SessionOverride>) => {
    setSessionOverrides((prev) => {
      const next = {
        ...prev,
        [sessionId]: { ...(prev[sessionId] || {}), ...updates },
      };
      try { localStorage.setItem("ares_session_overrides_map", JSON.stringify(next)); } catch {}
      return next;
    });
  }, []);

  // Move backend up/down in order
  const handleMoveBackend = useCallback((backendId: string, direction: "up" | "down") => {
    setCliBackendOrder((prev) => {
      const allIds = Array.from(new Set([...prev, ...backends.map((b) => b.adapter_id), ...Object.keys(BACKEND_META)]));
      const idx = allIds.indexOf(backendId);
      if (idx < 0) return prev;
      const targetIdx = direction === "up" ? idx - 1 : idx + 1;
      if (targetIdx < 0 || targetIdx >= allIds.length) return prev;

      const next = [...allIds];
      const temp = next[idx];
      next[idx] = next[targetIdx];
      next[targetIdx] = temp;

      try { localStorage.setItem("ares_cli_backend_order", JSON.stringify(next)); } catch {}
      return next;
    });
  }, [backends]);

  // Toggle backend visibility
  const handleToggleBackendHide = useCallback((backendId: string) => {
    setHiddenBackends((prev) => {
      const next = prev.includes(backendId)
        ? prev.filter((id) => id !== backendId)
        : [...prev, backendId];
      try { localStorage.setItem("ares_hidden_backends", JSON.stringify(next)); } catch {}
      return next;
    });
  }, []);

  // Create new project
  const handleCreateProject = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();
    const name = newProjectName.trim();
    if (!name) return;

    const newProj: ProjectItem = { id: name.toLowerCase().replace(/\s+/g, "-"), name };

    setProjects((prev) => {
      if (prev.some((p) => p.name.toLowerCase() === name.toLowerCase())) return prev;
      const next = [...prev, newProj];
      try { localStorage.setItem("ares_projects_list", JSON.stringify(next)); } catch {}
      return next;
    });

    setNewProjectName("");
    setShowAddProject(false);
    setActiveProject(newProj.id);

    try {
      await apiFetch("/api/projects/create", {
        method: "POST",
        body: JSON.stringify({ name }),
      });
    } catch {}
  }, [newProjectName]);

  // Enriched sessions with local overrides
  const enrichedSessions = useMemo(() => {
    return snapshot.sessions.map((s) => {
      const override = sessionOverrides[s.id];
      return {
        ...s,
        title: displayTitle(override?.title ?? s.title),
        source: override?.source ?? s.source,
        backendId: override?.backendId ?? s.backendId,
      };
    });
  }, [snapshot.sessions, sessionOverrides]);

  // Total counts for tabs
  const webuiCount = useMemo(() => enrichedSessions.filter((s) => s.source !== "cli").length, [enrichedSessions]);
  const cliCount = useMemo(() => enrichedSessions.filter((s) => s.source === "cli").length, [enrichedSessions]);

  // Filtered session list
  const filteredSessions = useMemo(() => {
    const q = sessionSearch.toLowerCase();
    return enrichedSessions.filter((s) => {
      // 1. Source filter
      const isCli = s.source === "cli";
      if (sourceTab === "webui" && isCli) return false;
      if (sourceTab === "cli" && !isCli) return false;

      // 2. Search query filter
      if (q && !s.title?.toLowerCase().includes(q)) return false;

      // 3. Project filter. Only an explicit assignment counts: falling back to
      // s.workspace made every session look assigned, so "Unassigned" matched
      // nothing and the badge rendered a filesystem path as a project name.
      const assignedProjId = sessionProjectMap[s.id];
      if (activeProject === "unassigned") {
        if (assignedProjId) return false;
      } else if (activeProject !== null) {
        const projObj = projects.find((p) => p.id === activeProject);
        const matchName = projObj?.name;
        if (assignedProjId !== activeProject && assignedProjId !== matchName) return false;
      }

      return true;
    });
  }, [enrichedSessions, sourceTab, sessionSearch, activeProject, sessionProjectMap, projects]);

  // Ordered list of backends
  const sortedBackendIds = useMemo(() => {
    const ids = new Set<string>();
    for (const id of cliBackendOrder) ids.add(id);
    for (const b of backends) ids.add(b.adapter_id);
    for (const s of enrichedSessions) { if (s.source === "cli" && s.backendId) ids.add(s.backendId); }
    for (const id of Object.keys(BACKEND_META)) ids.add(id);
    return Array.from(ids).filter((id) => !hiddenBackends.includes(id));
  }, [cliBackendOrder, backends, enrichedSessions, hiddenBackends]);

  // Group CLI sessions by backend
  const cliByBackend = useMemo(() => {
    if (sourceTab !== "cli") return new Map<string, typeof filteredSessions>();
    const byBackend = new Map<string, typeof filteredSessions>();
    for (const s of filteredSessions) {
      const key = s.backendId || "unknown";
      if (!byBackend.has(key)) byBackend.set(key, []);
      byBackend.get(key)!.push(s);
    }
    return byBackend;
  }, [filteredSessions, sourceTab]);

  const handleNewSession = openNewChat;

  const editingSession = useMemo(
    () => enrichedSessions.find((s) => s.id === editingSessionId),
    [enrichedSessions, editingSessionId],
  );

  return (
    <div className="flex h-full min-h-0 bg-[#111210] text-[#ecebe4] relative">
      {/* ── Icon rail ── */}
      <nav
        className="flex w-14 shrink-0 flex-col items-center border-r border-[#343631] py-3"
        aria-label="Command center modes"
      >
        <NavLink
          to="/companion"
          className="mb-5 grid size-8 place-items-center rounded bg-[#ecebe4] text-[#111210]"
          aria-label="Companion home"
        >
          <Command className="size-4" />
        </NavLink>
        <div className="flex flex-1 flex-col gap-1">
          {modes.map(({ id, label, icon: Icon, to }) => (
            <NavLink
              key={id}
              to={to}
              aria-label={label}
              title={label}
              className={cn(
                "relative grid size-9 place-items-center rounded-sm text-[#777970] transition-colors hover:bg-[#20211f] hover:text-[#ecebe4]",
                activeMode === id &&
                  "bg-[#292b28] text-[#faf9f3] before:absolute before:-left-2.5 before:h-5 before:w-0.5 before:bg-[#d7d6ce]",
              )}
            >
              <Icon className="size-4" />
            </NavLink>
          ))}
        </div>
        <NavLink
          to="/settings"
          aria-label="App settings"
          title="App settings — profile, theme, WebUI & Mac"
          className={({ isActive }) =>
            cn(
              "mt-auto grid size-9 place-items-center rounded-sm text-[#777970] transition-colors hover:bg-[#20211f] hover:text-[#ecebe4]",
              isActive && "bg-[#292b28] text-[#faf9f3]",
            )
          }
        >
          <Settings className="size-4" />
        </NavLink>
      </nav>

      {/* ── Sidebar content ── */}
      <aside className="flex min-w-0 flex-1 flex-col bg-[#151614]">
        {/* Header */}
        <div className="flex h-12 shrink-0 items-center border-b border-[#343631] px-3">
          <p className="min-w-0 truncate font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-[#a7a79d]">
            {activeMode === "chat" ? "Conversations" : activeSection?.label ?? "ARES"}
          </p>
          {activeMode === "chat" && (
            <button
              type="button"
              title="New WebUI conversation"
              onClick={handleNewSession}
              className="ml-auto flex h-6 w-6 items-center justify-center rounded text-[#6f7169] transition-colors hover:bg-[#292b28] hover:text-[#ecebe4]"
            >
              <Plus className="size-3.5" />
            </button>
          )}
          {activeMode !== "chat" && (
            <SlidersHorizontal className="ml-auto size-3.5 text-[#6f7169]" aria-hidden="true" />
          )}
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {activeMode === "chat" ? (
            <div className="flex flex-col h-full">

              {/* 1. Search */}
              <div className="px-2.5 py-2 border-b border-[#1e1f1d]">
                <div className="relative">
                  <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 size-3 text-[#6f7169] pointer-events-none" />
                  <input
                    type="search"
                    placeholder="Filter conversations..."
                    value={sessionSearch}
                    onChange={(e) => setSessionSearch(e.target.value)}
                    className="w-full rounded border border-[#343631] bg-[#1b1c1a] py-1 pl-7 pr-2 text-[12px] text-[#ecebe4] outline-none placeholder:text-[#6f7169] focus:border-[#4b4d47]"
                  />
                </div>
              </div>

              {/* 2. Side-by-side Session Source Tabs (Hermes-style) */}
              <div className="p-2 border-b border-[#1e1f1d]">
                <div className="grid grid-cols-2 gap-1 rounded bg-[#111210] p-1 border border-[#252830]">
                  <button
                    type="button"
                    onClick={() => setSourceTab("webui")}
                    className={cn(
                      "py-1 px-2 rounded text-[11px] font-semibold transition-all text-center flex items-center justify-center gap-1.5",
                      sourceTab === "webui"
                        ? "bg-[#1e2236] text-[#3889fd] border border-[#3889fd]/30 shadow-sm"
                        : "text-[#8f9188] hover:text-[#ecebe4] hover:bg-[#1a1c24]",
                    )}
                  >
                    <Monitor className="size-3 shrink-0" />
                    <span className="truncate">WebUI sessions ({webuiCount})</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => setSourceTab("cli")}
                    className={cn(
                      "py-1 px-2 rounded text-[11px] font-semibold transition-all text-center flex items-center justify-center gap-1.5",
                      sourceTab === "cli"
                        ? "bg-[#1e2236] text-[#08EBF1] border border-[#08EBF1]/30 shadow-sm"
                        : "text-[#8f9188] hover:text-[#ecebe4] hover:bg-[#1a1c24]",
                    )}
                  >
                    <Terminal className="size-3 shrink-0" />
                    <span className="truncate">CLI sessions ({cliCount})</span>
                  </button>
                </div>
              </div>

              {/* 3. Project Filter Chips Bar (All, Unassigned, Projects, +) */}
              <div className="px-2.5 py-2 border-b border-[#1e1f1d] flex items-center gap-1.5 overflow-x-auto scrollbar-none">
                <button
                  type="button"
                  onClick={() => setActiveProject(null)}
                  className={cn(
                    "px-2.5 py-0.5 rounded-full text-[11px] font-medium border transition-colors shrink-0",
                    activeProject === null
                      ? "bg-[#3889fd]/20 border-[#3889fd] text-[#3889fd]"
                      : "border-[#343631] text-[#8f9188] hover:border-[#4b4d47] hover:text-[#ecebe4]",
                  )}
                >
                  All
                </button>
                <button
                  type="button"
                  onClick={() => setActiveProject("unassigned")}
                  className={cn(
                    "px-2.5 py-0.5 rounded-full text-[11px] font-medium border border-dashed transition-colors shrink-0",
                    activeProject === "unassigned"
                      ? "bg-[#f5c542]/20 border-[#f5c542] text-[#f5c542]"
                      : "border-[#343631] text-[#8f9188] hover:border-[#4b4d47] hover:text-[#ecebe4]",
                  )}
                >
                  Unassigned
                </button>
                {projects.map((p) => (
                  <button
                    key={p.id}
                    type="button"
                    onClick={() => setActiveProject(p.id)}
                    className={cn(
                      "px-2.5 py-0.5 rounded-full text-[11px] font-medium border transition-colors shrink-0 flex items-center gap-1.5",
                      activeProject === p.id
                        ? "bg-[#5b7cf6]/20 border-[#5b7cf6] text-[#faf9f3]"
                        : "border-[#343631] text-[#8f9188] hover:border-[#4b4d47] hover:text-[#ecebe4]",
                    )}
                  >
                    <span className="size-1.5 rounded-full bg-[#5b7cf6]" />
                    <span className="truncate max-w-[80px]">{p.name}</span>
                  </button>
                ))}
                <button
                  type="button"
                  onClick={() => setShowAddProject(true)}
                  title="Create new project"
                  className="size-5 rounded-full border border-[#343631] flex items-center justify-center text-[#8f9188] hover:text-[#ecebe4] hover:border-[#5b7cf6] transition-colors shrink-0"
                >
                  <Plus className="size-3" />
                </button>
              </div>

              {/* Inline Create Project Form */}
              {showAddProject && (
                <form onSubmit={(e) => void handleCreateProject(e)} className="m-2 p-2 rounded border border-[#3889fd]/40 bg-[#161824]">
                  <div className="text-[11px] font-semibold text-[#a7a79d] mb-1">Create New Project</div>
                  <div className="flex gap-1.5">
                    <input
                      type="text"
                      autoFocus
                      value={newProjectName}
                      onChange={(e) => setNewProjectName(e.target.value)}
                      placeholder="Project name..."
                      className="flex-1 rounded border border-[#343631] bg-[#111210] px-2 py-1 text-[11px] text-[#ecebe4] outline-none focus:border-[#5b7cf6]"
                    />
                    <button
                      type="submit"
                      disabled={!newProjectName.trim()}
                      className="px-2.5 py-1 rounded bg-[#5b7cf6] text-white text-[11px] font-medium hover:bg-[#4b6ce6] disabled:opacity-50"
                    >
                      Add
                    </button>
                    <button
                      type="button"
                      onClick={() => { setShowAddProject(false); setNewProjectName(""); }}
                      className="px-1.5 py-1 rounded border border-[#343631] text-[#8f9188] text-[11px] hover:text-[#ecebe4]"
                    >
                      Cancel
                    </button>
                  </div>
                </form>
              )}

              {/* 4. Session List Area */}
              <div className="flex-1 overflow-y-auto py-1">
                {sourceTab === "webui" ? (
                  /* WebUI sessions list */
                  <div>
                    {filteredSessions.length === 0 ? (
                      <p className="px-3 py-6 text-center text-[11px] text-[#6f7169]">
                        {activeProject === "unassigned" ? "No unassigned conversations." : "No conversations found."}
                      </p>
                    ) : (
                      DATE_GROUP_ORDER.map((group) => {
                        const groupSessions = filteredSessions.filter((s) => dateGroupFor(s.updatedAt) === group);
                        if (groupSessions.length === 0) return null;
                        return (
                          <div key={group}>
                            <p className="px-3 pb-1 pt-3 text-[10px] font-semibold uppercase tracking-[0.1em] text-[#6f7169]">
                              {group}
                            </p>
                            {groupSessions.map((s) => {
                              // Only an explicit assignment names a project. The
                              // workspace path is not a project — rendering it
                              // leaked the full filesystem path into the badge.
                              const projId = sessionProjectMap[s.id];
                              const projObj = projects.find((p) => p.id === projId || p.name === projId);
                              return (
                                <SessionRow
                                  key={s.id}
                                  sessionId={s.id}
                                  title={s.title}
                                  updatedAt={s.updatedAt}
                                  projectName={projObj?.name || (projId ? String(projId) : undefined)}
                                  projects={projects}
                                  isActive={s.id === currentSession?.id}
                                  isStreaming={s.isStreaming}
                                  readOnly={s.readOnly}
                                  pinned={s.pinned}
                                  onClick={() => openChatSession(s.id)}
                                  onAssignProject={handleAssignProject}
                                  onOpenEdit={(id) => setEditingSessionId(id)}
                                  actions={sessionActions}
                                />
                              );
                            })}
                          </div>
                        );
                      })
                    )}
                  </div>
                ) : (
                  /* CLI sessions list grouped by backend with reordering setting button */
                  <div>
                    <div className="flex items-center justify-between px-3 py-1.5 border-b border-[#1e1f1d]">
                      <span className="text-[10px] font-semibold uppercase tracking-[0.1em] text-[#6f7169]">
                        Agent Backend Order
                      </span>
                      <button
                        type="button"
                        onClick={() => setShowBackendOrderModal(true)}
                        className="flex items-center gap-1 text-[10px] font-medium text-[#3889fd] hover:underline"
                      >
                        <SlidersHorizontal className="size-3" />
                        <span>Reorder / Manage</span>
                      </button>
                    </div>

                    {sortedBackendIds.length === 0 ? (
                      <p className="px-4 py-4 text-center text-[11px] text-[#4b4d47] italic">
                        No CLI backends enabled
                      </p>
                    ) : (
                      sortedBackendIds.map((backendId) => {
                        const detectedObj = backends.find((b) => b.adapter_id === backendId);
                        const isDetected = detectedObj ? detectedObj.detected : true;
                        const sessions = cliByBackend.get(backendId) ?? [];

                        return (
                          <BackendGroup
                            key={backendId}
                            backendId={backendId}
                            detected={isDetected}
                            sessionCount={sessions.length}
                          >
                            {sessions.map((s) => {
                              // Only an explicit assignment names a project. The
                              // workspace path is not a project — rendering it
                              // leaked the full filesystem path into the badge.
                              const projId = sessionProjectMap[s.id];
                              const projObj = projects.find((p) => p.id === projId || p.name === projId);
                              return (
                                <SessionRow
                                  key={s.id}
                                  sessionId={s.id}
                                  title={s.title}
                                  updatedAt={s.updatedAt}
                                  projectName={projObj?.name || (projId ? String(projId) : undefined)}
                                  projects={projects}
                                  isActive={s.id === currentSession?.id}
                                  isStreaming={s.isStreaming}
                                  readOnly={s.readOnly}
                                  pinned={s.pinned}
                                  onClick={() => openChatSession(s.id)}
                                  onAssignProject={handleAssignProject}
                                  onOpenEdit={(id) => setEditingSessionId(id)}
                                  actions={sessionActions}
                                />
                              );
                            })}
                          </BackendGroup>
                        );
                      })
                    )}
                  </div>
                )}
              </div>
            </div>
          ) : (
            <div className="space-y-0.5 p-2">
              {groupedRoutes.map(({ group, items }) => (
                <div key={group || "_ungrouped"}>
                  {group && (
                    <p className="px-2.5 pb-1 pt-3 text-[10px] font-semibold uppercase tracking-[0.1em] text-[#6f7169]">
                      {group}
                    </p>
                  )}
                  {items.map(({ to, label, icon: Icon }) => (
                    <NavLink
                      key={to}
                      to={to}
                      className={({ isActive }) =>
                        cn(
                          "flex items-center gap-2.5 rounded-sm px-2.5 py-2 text-xs text-[#92948b] transition-colors hover:bg-[#20211f] hover:text-[#ecebe4]",
                          isActive && "bg-[#292b28] text-[#faf9f3]",
                        )
                      }
                    >
                      <Icon className="size-3.5 shrink-0" />
                      <span className="truncate">{label}</span>
                    </NavLink>
                  ))}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        <footer className="border-t border-[#343631] px-3 py-2.5">
          <p className="truncate text-[11px] font-medium text-[#d7d6ce]">
            {profile.displayName || "Local profile"}
          </p>
          <p className="truncate font-mono text-[9px] uppercase tracking-wider text-[#6f7169]">
            local · private
          </p>
        </footer>
      </aside>

      {actionNotice && (
        <div
          role="status"
          className="fixed bottom-4 left-1/2 z-50 max-w-md -translate-x-1/2 rounded-md border border-[#343631] bg-[#1a1c24] px-3 py-2 text-[11px] text-[#ecebe4] shadow-2xl"
        >
          {actionNotice}
        </div>
      )}

      {/* ── MODAL 1: CLI Backend Order & Visibility Settings ── */}
      {showBackendOrderModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-[#343631] bg-[#1a1c24] p-4 shadow-2xl text-[#ecebe4]">
            <div className="flex items-center justify-between border-b border-[#2d303e] pb-2 mb-3">
              <h3 className="text-sm font-semibold text-[#f0f2ff] flex items-center gap-2">
                <SlidersHorizontal className="size-4 text-[#08EBF1]" />
                CLI Agent Order & Settings
              </h3>
              <button
                type="button"
                onClick={() => setShowBackendOrderModal(false)}
                className="text-[#8f9188] hover:text-[#ecebe4] text-xs"
              >
                ✕
              </button>
            </div>
            <p className="text-[11px] text-[#8f9188] mb-3">
              Reorder or toggle visibility of CLI agent backends in the sidebar.
            </p>
            <div className="space-y-1.5 max-h-64 overflow-y-auto pr-1">
              {Array.from(new Set([...cliBackendOrder, ...backends.map((b) => b.adapter_id), ...Object.keys(BACKEND_META)])).map((backendId, index, array) => {
                const hidden = hiddenBackends.includes(backendId);
                const color = backendColor(backendId);
                const label = backendLabel(backendId);

                return (
                  <div
                    key={backendId}
                    className="flex items-center justify-between p-2 rounded bg-[#111210] border border-[#272a38] text-[12px]"
                  >
                    <div className="flex items-center gap-2 truncate">
                      <span className="size-2 rounded-full shrink-0" style={{ background: color }} />
                      <span className={cn("truncate font-medium", hidden && "line-through text-[#6f7169]")}>
                        {label}
                      </span>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        type="button"
                        title={hidden ? "Show backend" : "Hide backend"}
                        onClick={() => handleToggleBackendHide(backendId)}
                        className="p-1 rounded text-[#8f9188] hover:text-[#ecebe4] hover:bg-[#202330]"
                      >
                        {hidden ? <EyeOff className="size-3.5 text-[#e11d48]" /> : <Eye className="size-3.5 text-[#4ade80]" />}
                      </button>
                      <button
                        type="button"
                        disabled={index === 0}
                        onClick={() => handleMoveBackend(backendId, "up")}
                        className="p-1 rounded text-[#8f9188] hover:text-[#ecebe4] hover:bg-[#202330] disabled:opacity-30"
                      >
                        <ArrowUp className="size-3.5" />
                      </button>
                      <button
                        type="button"
                        disabled={index === array.length - 1}
                        onClick={() => handleMoveBackend(backendId, "down")}
                        className="p-1 rounded text-[#8f9188] hover:text-[#ecebe4] hover:bg-[#202330] disabled:opacity-30"
                      >
                        <ArrowDown className="size-3.5" />
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
            <button
              type="button"
              onClick={() => setShowBackendOrderModal(false)}
              className="mt-4 w-full py-1.5 rounded bg-[#5b7cf6] text-white text-xs font-semibold hover:bg-[#4b6ce6]"
            >
              Done
            </button>
          </div>
        </div>
      )}

      {/* ── MODAL 2: Edit Session Properties (Title, Source, Backend) ── */}
      {editingSession && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm rounded-xl border border-[#343631] bg-[#1a1c24] p-4 shadow-2xl text-[#ecebe4]">
            <div className="flex items-center justify-between border-b border-[#2d303e] pb-2 mb-3">
              <h3 className="text-sm font-semibold text-[#f0f2ff]">Edit Conversation Details</h3>
              <button
                type="button"
                onClick={() => setEditingSessionId(null)}
                className="text-[#8f9188] hover:text-[#ecebe4] text-xs"
              >
                ✕
              </button>
            </div>

            <div className="space-y-3 text-[12px]">
              <div>
                <label className="block text-[11px] font-semibold text-[#8f9188] mb-1" htmlFor="session-title-input">
                  Title
                </label>
                <div className="flex gap-1.5">
                  <input
                    id="session-title-input"
                    type="text"
                    defaultValue={editingSession.title}
                    disabled={editingSession.readOnly}
                    onKeyDown={(e) => {
                      if (e.key !== "Enter") return;
                      e.preventDefault();
                      (e.currentTarget.nextElementSibling as HTMLButtonElement | null)?.click();
                    }}
                    className="w-full rounded border border-[#343631] bg-[#111210] px-2.5 py-1.5 text-[12px] text-[#ecebe4] outline-none focus:border-[#5b7cf6] disabled:text-[#6f7169]"
                  />
                  <button
                    type="button"
                    disabled={editingSession.readOnly}
                    onClick={(e) => {
                      const input = (e.currentTarget.previousElementSibling as HTMLInputElement | null);
                      const next = input?.value.trim();
                      if (!next || next === editingSession.title) return;
                      void aresApi.renameSession(editingSession.id, next)
                        .then(() => refresh())
                        .catch(() => {});
                    }}
                    className="shrink-0 rounded bg-[#5b7cf6] px-2.5 text-[11px] font-medium text-white disabled:bg-[#2d303e] disabled:text-[#6f7169]"
                  >
                    Save
                  </button>
                </div>
                {editingSession.readOnly && (
                  <p className="mt-1 text-[10px] text-[#6f7169]">
                    Imported history is read-only.
                  </p>
                )}
              </div>

              {/* Provenance — where this conversation came from and what ran it.
                  Deliberately not editable: it is a record of what happened, and
                  the previous editable version only wrote to localStorage, so it
                  silently disagreed with the backend. */}
              <div className="rounded border border-[#2d303e] bg-[#111210] p-2.5">
                <p className="mb-1.5 text-[10px] font-semibold uppercase tracking-wider text-[#6f7169]">
                  Provenance
                </p>
                <dl className="space-y-1 text-[11px]">
                  <div className="flex justify-between gap-2">
                    <dt className="text-[#8f9188]">Source</dt>
                    <dd className="truncate text-[#c9cbd4]">{editingSession.source || "unknown"}</dd>
                  </div>
                  <div className="flex justify-between gap-2">
                    <dt className="text-[#8f9188]">Worker</dt>
                    <dd className="truncate text-[#c9cbd4]">
                      {editingSession.backendId ? backendLabel(editingSession.backendId) : "—"}
                    </dd>
                  </div>
                  <div className="flex justify-between gap-2">
                    <dt className="text-[#8f9188]">Messages</dt>
                    <dd className="text-[#c9cbd4]">{editingSession.messageCount ?? 0}</dd>
                  </div>
                  {editingSession.workspace && (
                    <div className="flex justify-between gap-2">
                      <dt className="shrink-0 text-[#8f9188]">Workspace</dt>
                      <dd className="truncate font-mono text-[10px] text-[#c9cbd4]" title={editingSession.workspace}>
                        {editingSession.workspace}
                      </dd>
                    </div>
                  )}
                </dl>
              </div>
            </div>

            <button
              type="button"
              onClick={() => setEditingSessionId(null)}
              className="mt-4 w-full py-1.5 rounded bg-[#5b7cf6] text-white text-xs font-semibold hover:bg-[#4b6ce6]"
            >
              Save Changes
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

import { ChevronLeft, Folder, Menu, X } from "lucide-react";
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Group, Panel, usePanelRef } from "react-resizable-panels";

import { ControlDeck } from "@/components/command-center/ControlDeck";
import { ResizeHandle } from "@/components/command-center/ResizeHandle";
import { WorkbenchPane } from "@/components/command-center/WorkbenchPane";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import type { ConversationSession } from "@/shared/contracts";
import { useLocalProfile } from "@/shared/local-profile";
import { useIsCompactViewport } from "@/shared/use-media-query";
import { WorkbenchPanelProvider } from "@/shared/workbench-panel";

// Bumped when panel min/default sizes change so a prior layout can't leave the
// brain (chat) pane at 0 width after a rebuild — that looks like a blank app.
const LAYOUT_KEY = "ares.command-center.layout.v2";

function readLayout(): Record<string, number> | undefined {
  try {
    const value = window.localStorage.getItem(LAYOUT_KEY);
    if (!value) return undefined;
    const parsed = JSON.parse(value) as Record<string, number>;
    if (!["deck", "brain", "hands"].every((key) => Number.isFinite(parsed[key]))) return undefined;
    const total = parsed.deck + parsed.brain + parsed.hands;
    // Reject empty / zeroed panes from a bad prior save.
    if (!(total > 0) || parsed.brain < 20 || parsed.deck < 5) return undefined;
    return parsed;
  } catch {
    return undefined;
  }
}

function saveLayout(layout: Record<string, number>) {
  try {
    window.localStorage.setItem(LAYOUT_KEY, JSON.stringify(layout));
  } catch {
    // WKWebView storage can be unavailable in an ephemeral profile.
  }
}

/** Strip a workspace path down to its last segment for display. */
function titleText(title: string | undefined): string {
  const clean = (title ?? "").trim();
  if (!clean) return "Untitled";
  if (!clean.startsWith("/") && !clean.startsWith("~/")) return clean;
  const segments = clean.replace(/\/+$/, "").split("/").filter(Boolean);
  return segments[segments.length - 1] || clean;
}

/**
 * Chat header title — click to rename the session in place.
 *
 * Renaming posts to /api/session/rename, which sets the backend's
 * `manual_title` flag so background LLM auto-titling won't overwrite it.
 */
function SessionTitle({
  session,
  onRenamed,
}: {
  session: ConversationSession | null;
  onRenamed: () => void | Promise<void>;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const inputRef = useRef<HTMLInputElement | null>(null);

  const sessionId = session?.id ?? "";
  const display = titleText(session?.title);

  useEffect(() => {
    if (editing) inputRef.current?.select();
  }, [editing]);

  // Abandon an in-flight edit if the user switches sessions underneath it.
  useEffect(() => {
    setEditing(false);
    setError("");
  }, [sessionId]);

  const beginEdit = () => {
    if (!sessionId || session?.readOnly) return;
    setDraft((session?.title ?? "").trim());
    setError("");
    setEditing(true);
  };

  const commit = async () => {
    const next = draft.trim();
    if (!sessionId || !next || next === (session?.title ?? "").trim()) {
      setEditing(false);
      return;
    }
    setSaving(true);
    try {
      await aresApi.renameSession(sessionId, next);
      setEditing(false);
      await onRenamed();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not rename session");
    } finally {
      setSaving(false);
    }
  };

  if (editing) {
    return (
      <div className="flex min-w-0 flex-1 items-center gap-2">
        <input
          ref={inputRef}
          value={draft}
          autoFocus
          disabled={saving}
          aria-label="Session name"
          onChange={(event) => setDraft(event.target.value)}
          onBlur={() => void commit()}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              void commit();
            } else if (event.key === "Escape") {
              event.preventDefault();
              setEditing(false);
              setError("");
            }
          }}
          className="min-w-0 flex-1 rounded-sm border border-edge-strong bg-shell-raised px-2 py-1 text-xs font-medium text-[#ecebe4] outline-none focus:border-edge-emphasis"
        />
        {error && <span className="shrink-0 text-[10px] text-[#e06c6c]">{error}</span>}
      </div>
    );
  }

  return (
    <div className="flex min-w-0 items-center gap-2">
      <button
        type="button"
        onClick={beginEdit}
        disabled={!sessionId || session?.readOnly}
        title={session?.readOnly ? "This session is read-only" : "Rename session"}
        className="min-w-0 truncate rounded-sm px-1 py-0.5 text-left text-xs font-medium text-[#ecebe4] transition-colors hover:bg-shell-raised disabled:cursor-default disabled:hover:bg-transparent"
      >
        {display}
      </button>
      <span
        title="Messages in this project"
        className="shrink-0 rounded-sm bg-shell-raised px-1.5 py-0.5 font-mono text-[9px] text-[#8f9188]"
      >
        {session?.messageCount ?? session?.messages?.length ?? 0}
      </span>
    </div>
  );
}

function SurfaceLoading() {
  return (
    <div className="grid h-full place-items-center bg-shell text-xs text-[#8f9188]" role="status">
      Loading Companion surface…
    </div>
  );
}

function BrainHeader({
  isConversation,
  currentSession,
  companionName,
  onRenamed,
  compact,
  onOpenDeck,
  onOpenHands,
  handsOpen,
}: {
  isConversation: boolean;
  currentSession: ConversationSession | null;
  companionName: string;
  onRenamed: () => void | Promise<void>;
  compact: boolean;
  onOpenDeck?: () => void;
  onOpenHands?: () => void;
  handsOpen?: boolean;
}) {
  if (!compact && isConversation && !currentSession) {
    return null;
  }

  return (
    <header className="flex h-12 shrink-0 items-center gap-2 border-b border-edge bg-shell/95 px-3 backdrop-blur-xl sm:gap-3 sm:px-4">
      {compact && onOpenDeck && (
        <button
          type="button"
          onClick={onOpenDeck}
          title="Open menu"
          aria-label="Open menu"
          className="grid size-11 shrink-0 place-items-center rounded-md text-[#a7a79d] transition-colors hover:bg-shell-raised hover:text-[#ecebe4]"
        >
          <Menu className="size-5" aria-hidden="true" />
        </button>
      )}
      <div className="min-w-0 flex-1">
        {isConversation ? (
          <SessionTitle session={currentSession} onRenamed={onRenamed} />
        ) : (
          <div className="min-w-0">
            <p className="font-mono text-[9px] uppercase tracking-[0.18em] text-[#6f7169]">Agent</p>
            <p className="truncate text-xs font-medium text-[#ecebe4]">{companionName}</p>
          </div>
        )}
      </div>
      {compact && onOpenHands && (
        <button
          type="button"
          onClick={onOpenHands}
          title={handsOpen ? "Close workspace" : "Open workspace"}
          aria-label={handsOpen ? "Close workspace" : "Open workspace"}
          aria-pressed={handsOpen}
          className="grid size-11 shrink-0 place-items-center rounded-md text-[#a7a79d] transition-colors hover:bg-shell-raised hover:text-[#ecebe4]"
        >
          <Folder className="size-5" aria-hidden="true" />
        </button>
      )}
    </header>
  );
}

/**
 * Desktop: three resizable columns (deck | brain | hands).
 * Compact (≤900px, Hermes-aligned): brain full-width; deck and hands as
 * slide-over drawers so chat is usable on a phone.
 */
export function CommandCenterShell() {
  const location = useLocation();
  const { currentSession, refresh } = useAres();
  const { profile } = useLocalProfile();
  const isCompact = useIsCompactViewport();
  const isConversation =
    location.pathname.startsWith("/conversation") || location.pathname.startsWith("/chat");
  const companionName = profile.assistantName?.trim() || "Jaeger AI";

  const workbenchRef = usePanelRef();
  // Every environment opens with its main surface unobstructed. The workspace
  // remains available on demand, but does not carry an open state between tabs.
  const [workbenchCollapsed, setWorkbenchCollapsed] = useState(true);

  // Compact drawers (Hermes: sidebar + rightpanel slide-ins under 900/640).
  const [deckOpen, setDeckOpen] = useState(false);
  const [handsOpen, setHandsOpen] = useState(false);

  const collapseWorkbench = useCallback(() => {
    if (isCompact) {
      setHandsOpen(false);
      return;
    }
    workbenchRef.current?.collapse();
  }, [isCompact, workbenchRef]);

  const expandWorkbench = useCallback(() => {
    if (isCompact) {
      setDeckOpen(false);
      setHandsOpen(true);
      return;
    }
    workbenchRef.current?.expand();
  }, [isCompact, workbenchRef]);

  const closeDeck = useCallback(() => setDeckOpen(false), []);
  const openDeck = useCallback(() => {
    setHandsOpen(false);
    setDeckOpen(true);
  }, []);
  const toggleHands = useCallback(() => {
    setHandsOpen((open) => {
      if (!open) setDeckOpen(false);
      return !open;
    });
  }, []);

  // Close auxiliary UI when entering a different environment/surface.
  useEffect(() => {
    setDeckOpen(false);
    setHandsOpen(false);
    if (!isCompact) workbenchRef.current?.collapse();
  }, [isCompact, location.pathname, workbenchRef]);

  // Listen for new-session signal to close workbench panel
  useEffect(() => {
    const handleCloseWorkbench = () => {
      collapseWorkbench();
    };
    window.addEventListener("ares:close-workbench", handleCloseWorkbench);
    return () => window.removeEventListener("ares:close-workbench", handleCloseWorkbench);
  }, [collapseWorkbench]);

  // Escape closes the topmost drawer.
  useEffect(() => {
    if (!isCompact || (!deckOpen && !handsOpen)) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      if (handsOpen) setHandsOpen(false);
      else if (deckOpen) setDeckOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [isCompact, deckOpen, handsOpen]);

  // Prevent body scroll bleed when a drawer is open on mobile.
  useEffect(() => {
    if (!isCompact) return;
    const locked = deckOpen || handsOpen;
    if (!locked) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [isCompact, deckOpen, handsOpen]);

  const workbenchCollapsedForProvider = isCompact ? !handsOpen : workbenchCollapsed;

  return (
    <WorkbenchPanelProvider
      collapsed={workbenchCollapsedForProvider}
      collapse={collapseWorkbench}
      expand={expandWorkbench}
    >
      <div
        className="h-dvh w-screen overflow-hidden bg-shell-root text-[#ecebe4]"
        data-compact={isCompact ? "1" : "0"}
      >
        {isCompact ? (
          <div className="relative flex h-full min-h-0 flex-col">
            <main
              className="flex h-full min-h-0 flex-1 flex-col bg-shell"
              data-active-surface={location.pathname}
            >
              <BrainHeader
                isConversation={isConversation}
                currentSession={currentSession}
                companionName={companionName}
                onRenamed={refresh}
                compact
                onOpenDeck={openDeck}
                onOpenHands={toggleHands}
                handsOpen={handsOpen}
              />
              <div className="command-center-surface min-h-0 flex-1 overflow-auto">
                <Suspense fallback={<SurfaceLoading />}>
                  <Outlet />
                </Suspense>
              </div>
            </main>

            {/* Backdrop — Hermes .mobile-overlay */}
            {(deckOpen || handsOpen) && (
              <button
                type="button"
                aria-label="Close panel"
                className="cc-mobile-overlay"
                onClick={() => {
                  setDeckOpen(false);
                  setHandsOpen(false);
                }}
              />
            )}

            {/* Left drawer: ControlDeck (sessions + modes) */}
            <div
              id="ares-mobile-deck"
              className={`cc-mobile-drawer cc-mobile-drawer--deck${deckOpen ? " is-open" : ""}`}
              aria-hidden={!deckOpen}
            >
              <div className="flex h-12 shrink-0 items-center justify-between border-b border-edge bg-shell px-3">
                <p className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-[#a7a79d]">
                  Menu
                </p>
                <button
                  type="button"
                  onClick={closeDeck}
                  title="Close menu"
                  aria-label="Close menu"
                  className="grid size-11 place-items-center rounded-md text-[#a7a79d] transition-colors hover:bg-shell-raised hover:text-[#ecebe4]"
                >
                  <X className="size-4" aria-hidden="true" />
                </button>
              </div>
              <div className="min-h-0 flex-1">
                <ControlDeck onNavigate={closeDeck} onSessionOpened={closeDeck} />
              </div>
            </div>

            {/* Right drawer: Workbench (files) */}
            <div
              id="ares-mobile-hands"
              className={`cc-mobile-drawer cc-mobile-drawer--hands${handsOpen ? " is-open" : ""}`}
              aria-hidden={!handsOpen}
            >
              <WorkbenchPane onCollapse={collapseWorkbench} />
            </div>
          </div>
        ) : (
          <>
            <div className="relative flex h-full w-full overflow-hidden">
              <Group
                id="ares-command-center"
                orientation="horizontal"
                defaultLayout={readLayout()}
                onLayoutChanged={saveLayout}
                className="h-full w-full"
              >
              <Panel id="deck" defaultSize="22%" minSize="220px" maxSize="34%" collapsible collapsedSize="56px">
                <div className="relative h-full w-full overflow-hidden z-10">
                  <ControlDeck />
                </div>
              </Panel>
              <ResizeHandle id="deck-brain-handle" />
              <Panel id="brain" defaultSize="48%" minSize="280px">
                <main
                  className="flex h-full min-h-0 flex-col bg-shell"
                  data-active-surface={location.pathname}
                >
                  <BrainHeader
                    isConversation={isConversation}
                    currentSession={currentSession}
                    companionName={companionName}
                    onRenamed={refresh}
                    compact={false}
                  />
                  <div className="command-center-surface min-h-0 flex-1 overflow-auto">
                    <Suspense fallback={<SurfaceLoading />}>
                      <Outlet />
                    </Suspense>
                  </div>
                </main>
              </Panel>
              <ResizeHandle id="brain-hands-handle" />
              <Panel
                id="hands"
                defaultSize="0px"
                minSize="240px"
                maxSize="55%"
                collapsible
                collapsedSize="0px"
                panelRef={workbenchRef}
                onResize={(size) => setWorkbenchCollapsed(size.inPixels < 1)}
              >
                <WorkbenchPane onCollapse={collapseWorkbench} />
              </Panel>
            </Group>
            </div>

            {workbenchCollapsed && (
              <button
                type="button"
                onClick={expandWorkbench}
                title="Open workspace"
                aria-label="Open workspace"
                className="fixed right-0 top-1/2 z-30 grid h-12 w-6 -translate-y-1/2 place-items-center rounded-l-lg border border-r-0 border-edge bg-shell-raised/95 text-[#a7a79d] shadow-lg backdrop-blur-sm transition-colors hover:border-edge-emphasis hover:text-[#ecebe4]"
              >
                <ChevronLeft className="size-4" aria-hidden="true" />
              </button>
            )}
          </>
        )}
      </div>
    </WorkbenchPanelProvider>
  );
}

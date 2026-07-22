import { ChevronLeft } from "lucide-react";
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
          className="min-w-0 flex-1 rounded-sm border border-[#4a4d45] bg-[#1b1c1a] px-2 py-1 text-xs font-medium text-[#ecebe4] outline-none focus:border-[#71736b]"
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
        className="min-w-0 truncate rounded-sm px-1 py-0.5 text-left text-xs font-medium text-[#ecebe4] transition-colors hover:bg-[#1b1c1a] disabled:cursor-default disabled:hover:bg-transparent"
      >
        {display}
      </button>
      <span
        title="Messages in this conversation"
        className="shrink-0 rounded-sm bg-[#1b1c1a] px-1.5 py-0.5 font-mono text-[9px] text-[#8f9188]"
      >
        {session?.messageCount ?? session?.messages?.length ?? 0}
      </span>
    </div>
  );
}

function SurfaceLoading() {
  return (
    <div className="grid h-full place-items-center bg-[#151614] text-xs text-[#8f9188]" role="status">
      Loading Companion surface…
    </div>
  );
}

export function CommandCenterShell() {
  const location = useLocation();
  const { currentSession, refresh } = useAres();
  const { profile } = useLocalProfile();
  const isConversation =
    location.pathname.startsWith("/conversation") || location.pathname.startsWith("/chat");
  const companionName = profile.assistantName?.trim() || "Companion";

  const workbenchRef = usePanelRef();
  const [workbenchCollapsed, setWorkbenchCollapsed] = useState(false);

  const collapseWorkbench = useCallback(() => {
    workbenchRef.current?.collapse();
  }, [workbenchRef]);

  const expandWorkbench = useCallback(() => {
    workbenchRef.current?.expand();
  }, [workbenchRef]);

  return (
    <WorkbenchPanelProvider collapsed={workbenchCollapsed} collapse={collapseWorkbench} expand={expandWorkbench}>
    <div className="h-dvh w-screen overflow-hidden bg-[#111210] text-[#ecebe4]">
      <Group
        id="ares-command-center"
        orientation="horizontal"
        defaultLayout={readLayout()}
        onLayoutChanged={saveLayout}
        className="h-full"
      >
        <Panel id="deck" defaultSize="22%" minSize="220px" maxSize="34%" collapsible collapsedSize="56px">
          <ControlDeck />
        </Panel>
        <ResizeHandle id="deck-brain-handle" />
        <Panel id="brain" defaultSize="48%" minSize="280px">
          <main className="flex h-full min-h-0 flex-col bg-[#151614]" data-active-surface={location.pathname}>
            <header className="flex h-12 shrink-0 items-center gap-3 border-b border-[#343631] bg-[#151614]/95 px-4 backdrop-blur-xl">
              {isConversation ? (
                <SessionTitle session={currentSession} onRenamed={refresh} />
              ) : (
                <div className="min-w-0">
                  <p className="font-mono text-[9px] uppercase tracking-[0.18em] text-[#6f7169]">Companion</p>
                  <p className="truncate text-xs font-medium text-[#ecebe4]">{companionName}</p>
                </div>
              )}
            </header>
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
          defaultSize="30%"
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

      {workbenchCollapsed && (
        <button
          type="button"
          onClick={expandWorkbench}
          title="Open workspace"
          aria-label="Open workspace"
          className="fixed right-0 top-1/2 z-30 grid h-12 w-6 -translate-y-1/2 place-items-center rounded-l-lg border border-r-0 border-[#343631] bg-[#1b1c1a]/95 text-[#a7a79d] shadow-lg backdrop-blur-sm transition-colors hover:border-[#71736b] hover:text-[#ecebe4]"
        >
          <ChevronLeft className="size-4" aria-hidden="true" />
        </button>
      )}
    </div>
    </WorkbenchPanelProvider>
  );
}

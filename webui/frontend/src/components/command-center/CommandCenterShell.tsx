import { Suspense } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Group, Panel } from "react-resizable-panels";

import { ControlDeck } from "@/components/command-center/ControlDeck";
import { ResizeHandle } from "@/components/command-center/ResizeHandle";
import { WorkbenchPane } from "@/components/command-center/WorkbenchPane";
import { cn } from "@/lib/utils";
import { useAres } from "@/shared/ares-context";
import { useLocalProfile } from "@/shared/local-profile";

const LAYOUT_KEY = "ares.command-center.layout.v1";

function readLayout(): Record<string, number> | undefined {
  try {
    const value = window.localStorage.getItem(LAYOUT_KEY);
    if (!value) return undefined;
    const parsed = JSON.parse(value) as Record<string, number>;
    return ["deck", "brain", "hands"].every((key) => Number.isFinite(parsed[key])) ? parsed : undefined;
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

function SurfaceLoading() {
  return (
    <div className="grid h-full place-items-center bg-[#151614] text-xs text-[#8f9188]" role="status">
      Loading Companion surface…
    </div>
  );
}

export function CommandCenterShell() {
  const location = useLocation();
  const { snapshot } = useAres();
  const { profile } = useLocalProfile();
  const connected = snapshot.connection === "available";
  const companionName = profile.assistantName?.trim() || "Companion";

  return (
    <div className="h-dvh w-screen overflow-hidden bg-[#111210] text-[#ecebe4]">
      <Group
        id="ares-command-center"
        orientation="horizontal"
        defaultLayout={readLayout()}
        onLayoutChanged={saveLayout}
        className="h-full"
      >
        <Panel id="deck" defaultSize="20%" minSize="184px" maxSize="34%" collapsible collapsedSize="56px">
          <ControlDeck />
        </Panel>
        <ResizeHandle id="deck-brain-handle" />
        <Panel id="brain" defaultSize="50%" minSize="360px">
          <main className="flex h-full min-h-0 flex-col bg-[#151614]" data-active-surface={location.pathname}>
            <header className="flex h-12 shrink-0 items-center gap-3 border-b border-[#343631] bg-[#151614]/95 px-4 backdrop-blur-xl">
              <div className="min-w-0">
                <p className="font-mono text-[9px] uppercase tracking-[0.18em] text-[#6f7169]">Companion</p>
                <p className="truncate text-xs font-medium text-[#ecebe4]">{companionName}</p>
              </div>
              <div className="ml-auto flex items-center gap-2 rounded-sm border border-[#343631] bg-[#1b1c1a] px-2 py-1 font-mono text-[9px] uppercase tracking-wider text-[#8f9188]">
                <span className={cn("size-1.5 rounded-full", connected ? "bg-[#10a37f]" : snapshot.connection === "limited" ? "bg-[#e6b15c]" : "bg-[#6f7169]")} />
                {snapshot.connection === "loading" ? "checking" : snapshot.connection}
              </div>
            </header>
            <div className="command-center-surface min-h-0 flex-1 overflow-auto">
              <Suspense fallback={<SurfaceLoading />}>
                <Outlet />
              </Suspense>
            </div>
          </main>
        </Panel>
        <ResizeHandle id="brain-hands-handle" />
        <Panel id="hands" defaultSize="30%" minSize="300px" maxSize="55%" collapsible collapsedSize="0px">
          <WorkbenchPane />
        </Panel>
      </Group>
    </div>
  );
}

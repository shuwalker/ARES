import { Files, SquareTerminal } from "lucide-react";
import { lazy, Suspense, useState } from "react";

import { cn } from "@/lib/utils";

const TerminalPage = lazy(async () => ({
  default: (await import("@/pages/TerminalPage")).TerminalPage,
}));
const WorkspacePage = lazy(async () => ({
  default: (await import("@/pages/WorkspacePage")).WorkspacePage,
}));

type WorkbenchTab = "files" | "terminal";
const STORAGE_KEY = "ares.command-center.workbench-tab";

function initialTab(): WorkbenchTab {
  try {
    return window.localStorage.getItem(STORAGE_KEY) === "terminal" ? "terminal" : "files";
  } catch {
    return "files";
  }
}

export function WorkbenchPane() {
  const [tab, setTab] = useState<WorkbenchTab>(initialTab);

  const choose = (next: WorkbenchTab) => {
    setTab(next);
    try {
      window.localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // Persistence is a convenience; private WKWebView modes may reject storage.
    }
  };

  return (
    <section className="flex h-full min-h-0 flex-col bg-[#111210]" aria-label="Companion workbench">
      <header className="flex h-12 shrink-0 items-center border-b border-[#343631] px-3">
        <span className="mr-auto font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-[#777970]">Tools</span>
        <div className="flex h-full" role="tablist" aria-label="Workbench view">
          {(["files", "terminal"] as const).map((value) => {
            const Icon = value === "files" ? Files : SquareTerminal;
            return (
              <button
                key={value}
                type="button"
                role="tab"
                aria-selected={tab === value}
                onClick={() => choose(value)}
                className={cn(
                  "relative flex items-center gap-1.5 px-3 font-mono text-[10px] uppercase tracking-wider text-[#777970] hover:text-[#ecebe4]",
                  tab === value && "text-[#faf9f3] after:absolute after:inset-x-2 after:bottom-0 after:h-px after:bg-[#d7d6ce]",
                )}
              >
                <Icon className="size-3" />
                {value}
              </button>
            );
          })}
        </div>
      </header>
      <div className="command-center-embedded min-h-0 flex-1 overflow-hidden">
        <Suspense fallback={<div className="grid h-full place-items-center text-xs text-[#777970]">Loading workbench…</div>}>
          {tab === "files" ? <WorkspacePage /> : <TerminalPage />}
        </Suspense>
      </div>
    </section>
  );
}

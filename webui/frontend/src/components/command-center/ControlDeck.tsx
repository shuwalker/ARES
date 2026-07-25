import {
  Brain,
  CircleUserRound,
  Command,
  MessageCircle,
  Settings,
  SlidersHorizontal,
  Sparkles,
  Wrench,
  type LucideIcon,
} from "lucide-react";
import { useMemo } from "react";
import { NavLink, useLocation } from "react-router-dom";

import { navigationSections, type NavigationSection } from "@/app-navigation";
import { cn } from "@/lib/utils";
import { useLocalProfile } from "@/shared/local-profile";

type DeckMode = NavigationSection["id"] | "chat";

const modes: Array<{ id: DeckMode; label: string; icon: LucideIcon; to: string }> = [
  { id: "chat", label: "Chat", icon: MessageCircle, to: "/conversation" },
  { id: "core", label: "Core", icon: Brain, to: "/today" },
  { id: "resources", label: "Life and work", icon: Sparkles, to: "/projects" },
  { id: "system", label: "System", icon: Wrench, to: "/activity" },
];

function sectionForPath(pathname: string): DeckMode {
  if (pathname.startsWith("/conversation")) return "chat";
  return navigationSections.find((section) =>
    section.routes.some(({ to }) => pathname.startsWith(to)),
  )?.id ?? "core";
}

export function ControlDeck() {
  const location = useLocation();
  const { profile } = useLocalProfile();
  const activeMode = sectionForPath(location.pathname);
  const activeSection = navigationSections.find(({ id }) => id === activeMode);
  const routes = useMemo(
    () => activeSection?.routes.filter(({ to }) => to !== "/conversation") ?? [],
    [activeSection],
  );

  return (
    <div className="flex h-full min-h-0 bg-[#111210] text-[#ecebe4]">
      <nav className="flex w-14 shrink-0 flex-col items-center border-r border-[#343631] py-3" aria-label="Command center modes">
        <NavLink
          to="/today"
          className="mb-5 grid size-8 place-items-center rounded bg-[#ecebe4] text-[#111210]"
          aria-label="ARES home"
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
                activeMode === id && "bg-[#292b28] text-[#faf9f3] before:absolute before:-left-2.5 before:h-5 before:w-0.5 before:bg-[#d7d6ce]",
              )}
            >
              <Icon className="size-4" />
            </NavLink>
          ))}
        </div>
        <NavLink
          to="/settings"
          aria-label="Settings"
          title="Settings"
          className="grid size-9 place-items-center rounded-sm text-[#777970] transition-colors hover:bg-[#20211f] hover:text-[#ecebe4]"
        >
          <Settings className="size-4" />
        </NavLink>
        <NavLink
          to="/settings"
          aria-label="Local profile"
          title={profile.displayName || "Local profile"}
          className="mt-1 grid size-9 place-items-center rounded-sm text-[#a7a79d] hover:bg-[#20211f]"
        >
          <CircleUserRound className="size-4" />
        </NavLink>
      </nav>

      <aside className="flex min-w-0 flex-1 flex-col bg-[#151614]">
        <header className="flex h-12 shrink-0 items-center border-b border-[#343631] px-3">
          <div className="min-w-0">
            <p className="truncate font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-[#a7a79d]">
              {activeMode === "chat" ? "Conversations" : activeSection?.label ?? "ARES"}
            </p>
          </div>
          <SlidersHorizontal className="ml-auto size-3.5 text-[#6f7169]" aria-hidden="true" />
        </header>

        <div className="min-h-0 flex-1 overflow-y-auto p-2">
          {activeMode === "chat" ? (
            <div className="space-y-3">
              <div className="rounded-sm border border-[#343631] bg-[#1b1c1a] p-3">
                <div className="flex items-center gap-2 text-xs font-medium">
                  <MessageCircle className="size-3.5 text-[#d7d6ce]" />
                  Current conversation
                </div>
                <p className="mt-1.5 text-[11px] leading-4 text-[#8f9188]">
                  Ask, plan, and act with {profile.assistantName || "your Companion"}. Sessions and journal stay in one place; workers only execute.
                </p>
              </div>
              <NavLink
                to="/search"
                className="block rounded-sm px-2.5 py-2 text-xs text-[#a7a79d] hover:bg-[#20211f] hover:text-[#ecebe4]"
              >
                Search conversation history
              </NavLink>
            </div>
          ) : (
            <div className="space-y-0.5">
              {routes.map(({ to, label, icon: Icon }) => (
                <NavLink
                  key={to}
                  to={to}
                  className={({ isActive }) => cn(
                    "flex items-center gap-2.5 rounded-sm px-2.5 py-2 text-xs text-[#92948b] transition-colors hover:bg-[#20211f] hover:text-[#ecebe4]",
                    isActive && "bg-[#292b28] text-[#faf9f3]",
                  )}
                >
                  <Icon className="size-3.5 shrink-0" />
                  <span className="truncate">{label}</span>
                </NavLink>
              ))}
            </div>
          )}
        </div>

        <footer className="border-t border-[#343631] px-3 py-2.5">
          <p className="truncate text-[11px] font-medium text-[#d7d6ce]">{profile.displayName || "Local profile"}</p>
          <p className="truncate font-mono text-[9px] uppercase tracking-wider text-[#6f7169]">local · private</p>
        </footer>
      </aside>
    </div>
  );
}

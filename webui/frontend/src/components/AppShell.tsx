import {
  Activity,
  Cable,
  ChevronRight,
  CircleUserRound,
  Command,
  FolderKanban,
  Gauge,
  House,
  Menu,
  MessageCircle,
  Moon,
  Settings,
  Sun,
  SquareTerminal,
  X,
  Layers,
  Inbox,
  ListTodo,
  CalendarClock,
  Wrench,
  Key,
  Sliders,
  Radio,
  Smartphone,
  Webhook,
  Server,
} from "lucide-react";
import { useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";

import { Button } from "@/components/ui/button";
import { useTheme } from "@/context/ThemeContext";
import { cn } from "@/lib/utils";
import { useLocalProfile } from "@/shared/local-profile";
import { useAres } from "@/shared/ares-context";

import { type LucideIcon } from "lucide-react";

type NavItem = {
  to: string;
  label: string;
  icon: LucideIcon;
};

const aresNavigation: NavItem[] = [
  { to: "/today", label: "Today", icon: House },
  { to: "/conversation", label: "Chat", icon: MessageCircle },
  { to: "/workspace", label: "Workspace", icon: FolderKanban },
  { to: "/canvas", label: "Canvas", icon: Layers },
  { to: "/terminal", label: "Terminal", icon: SquareTerminal },
];

const paperclipNavigation: NavItem[] = [
  { to: "/inbox", label: "Inbox", icon: Inbox },
  { to: "/issues", label: "Issues", icon: ListTodo },
  { to: "/routines", label: "Routines", icon: CalendarClock },
  { to: "/skills", label: "Skills", icon: Wrench },
  { to: "/secrets", label: "Secrets", icon: Key },
];

const systemNavigation: NavItem[] = [
  { to: "/activity", label: "Activity", icon: Activity },
  { to: "/usage", label: "Usage", icon: Gauge },
  { to: "/connections", label: "Connections", icon: Cable },
  { to: "/channels", label: "Channels", icon: Radio },
  { to: "/cron", label: "Schedules", icon: CalendarClock },
  { to: "/webhooks", label: "Webhooks", icon: Webhook },
  { to: "/pairing", label: "Pairing", icon: Smartphone },
  { to: "/mcp", label: "MCP Servers", icon: Server },
  { to: "/config", label: "Config", icon: Sliders },
];

function SidebarSection({ label, items, onNavigate }: { label: string; items: NavItem[]; onNavigate?: () => void }) {
  return (
    <div className="mb-4">
      <div className="px-3 py-1.5 pointer-coarse:py-1">
        <span className="text-[10px] font-medium uppercase tracking-widest font-mono text-muted-foreground/60">
          {label}
        </span>
      </div>
      <div className="flex flex-col gap-0.5 px-3">
        {items.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            onClick={onNavigate}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                isActive
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:bg-accent/60 hover:text-foreground",
              )
            }
          >
            <Icon className="size-4" aria-hidden="true" />
            {label}
          </NavLink>
        ))}
      </div>
    </div>
  );
}

function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const { profile } = useLocalProfile();
  return (
    <aside className="flex h-full min-h-0 flex-col border-r bg-sidebar text-sidebar-foreground">
      <div className="flex h-16 items-center gap-3 px-5">
        <div className="grid size-9 place-items-center rounded-lg bg-primary text-primary-foreground shadow-sm">
          <Command className="size-5" aria-hidden="true" />
        </div>
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold tracking-wide">ARES</p>
          <p className="truncate text-xs text-muted-foreground">Personal SI interface</p>
        </div>
      </div>
      
      <div className="flex-1 overflow-y-auto py-2">
        <SidebarSection label="ARES Core" items={aresNavigation} onNavigate={onNavigate} />
        <SidebarSection label="Paperclip" items={paperclipNavigation} onNavigate={onNavigate} />
        <SidebarSection label="System" items={systemNavigation} onNavigate={onNavigate} />
      </div>

      <div className="border-t p-3">
        <NavLink
          to="/settings"
          onClick={onNavigate}
          className={({ isActive }) =>
            cn(
              "flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors",
              isActive ? "bg-accent" : "hover:bg-accent/60",
            )
          }
        >
          <CircleUserRound className="size-4" aria-hidden="true" />
          <span className="min-w-0 flex-1 truncate">
            {profile.displayName || "Local Profile"}
          </span>
          <ChevronRight className="size-4 text-muted-foreground" aria-hidden="true" />
        </NavLink>
      </div>
    </aside>
  );
}

export function AppShell() {
  const [mobileOpen, setMobileOpen] = useState(false);
  const { theme, toggleTheme } = useTheme();
  const location = useLocation();
  const { snapshot } = useAres();
  
  const allNav = [...aresNavigation, ...paperclipNavigation, ...systemNavigation];
  const activeLabel =
    allNav.find(({ to }) => location.pathname.startsWith(to))?.label ??
    (location.pathname.startsWith("/settings") ? "Settings" : "ARES");

  return (
    <div className="flex h-dvh flex-col overflow-clip bg-background text-foreground">
      <div className="hidden h-full md:flex">
        <div className="w-60 shrink-0 border-r">
          <Sidebar />
        </div>
        <div className="flex min-h-0 min-w-0 flex-1 flex-col">
          <header className="flex h-16 shrink-0 items-center gap-3 border-b bg-background/90 px-4 backdrop-blur md:px-6">
            <h1 className="text-sm font-semibold">{activeLabel}</h1>
            <div className="ml-auto flex items-center gap-2">
              <span className="hidden items-center gap-2 text-xs text-muted-foreground sm:flex">
                <span className={cn("size-2 rounded-full", snapshot.connection === "available" ? "bg-status-available" : snapshot.connection === "limited" ? "bg-status-limited" : "bg-status-unavailable")} />
                {snapshot.connection === "loading" ? "Checking ARES API" : snapshot.connection === "available" ? "ARES API available" : snapshot.connection === "limited" ? "ARES API limited" : "ARES API unavailable"}
              </span>
              <Button
                variant="ghost"
                size="icon-sm"
                aria-label={`Use ${theme === "dark" ? "light" : "dark"} theme`}
                onClick={toggleTheme}
              >
                {theme === "dark" ? <Sun /> : <Moon />}
              </Button>
              <Button asChild variant="ghost" size="icon-sm">
                <NavLink to="/settings" aria-label="Settings">
                  <Settings />
                </NavLink>
              </Button>
            </div>
          </header>
          <main className="min-h-0 flex-1 overflow-auto">
            <Outlet />
          </main>
        </div>
      </div>
      
      {/* Mobile Layout omitted for brevity, but accessible via standard drawer if needed */}
      <div className="md:hidden flex h-full flex-col">
        <header className="flex h-16 shrink-0 items-center gap-3 border-b bg-background/90 px-4 backdrop-blur">
          <Button variant="ghost" size="icon-sm" onClick={() => setMobileOpen(true)}>
            <Menu />
          </Button>
          <h1 className="text-sm font-semibold">{activeLabel}</h1>
        </header>
        {mobileOpen && (
          <div className="fixed inset-0 z-50">
            <div className="absolute inset-0 bg-black/60" onClick={() => setMobileOpen(false)} />
            <div className="relative h-full w-72 bg-background shadow-2xl">
              <Sidebar onNavigate={() => setMobileOpen(false)} />
              <Button variant="ghost" size="icon-sm" className="absolute right-3 top-3" onClick={() => setMobileOpen(false)}>
                <X />
              </Button>
            </div>
          </div>
        )}
        <main className="min-h-0 flex-1 overflow-auto">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

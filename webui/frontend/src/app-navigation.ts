import { lazy, type ComponentType, type LazyExoticComponent } from "react";
import {
  Activity,
  Briefcase,
  Cable,
  CalendarClock,
  ClipboardList,
  Cpu,
  FolderKanban,
  Gauge,
  House,
  Inbox,
  Kanban,
  Key,
  Layers,
  ListTodo,
  MessageCircle,
  Search,
  Server,
  Sliders,
  Smartphone,
  Sparkles,
  SquareTerminal,
  Target,
  Webhook,
  Wrench,
  type LucideIcon,
} from "lucide-react";

const named = <T,>(loader: () => Promise<T>, key: keyof T) =>
  lazy(async () => ({ default: (await loader())[key] as ComponentType }));

export type AppRoute = {
  path: string;
  to: string;
  label: string;
  icon: LucideIcon;
  component: LazyExoticComponent<ComponentType>;
};

export type NavigationSection = {
  id: "core" | "resources" | "system";
  label: string;
  routes: AppRoute[];
};

export const navigationSections: NavigationSection[] = [
  {
    id: "core",
    label: "Companion",
    routes: [
      { path: "today", to: "/today", label: "Today", icon: House, component: named(() => import("@/pages/TodayPage"), "TodayPage") },
      { path: "conversation", to: "/conversation", label: "Chat", icon: MessageCircle, component: named(() => import("@/pages/ConversationPage"), "ConversationPage") },
      { path: "search", to: "/search", label: "Search", icon: Search, component: named(() => import("@/pages/SearchPage"), "SearchPage") },
      { path: "workspace", to: "/workspace", label: "Workspace", icon: FolderKanban, component: named(() => import("@/pages/WorkspacePage"), "WorkspacePage") },
      { path: "board", to: "/board", label: "Board", icon: Kanban, component: named(() => import("@/pages/BoardChatPage"), "BoardChatPage") },
      { path: "canvas", to: "/canvas", label: "Canvas", icon: Layers, component: named(() => import("@/pages/CanvasPage"), "CanvasPage") },
      { path: "terminal", to: "/terminal", label: "Terminal", icon: SquareTerminal, component: named(() => import("@/pages/TerminalPage"), "TerminalPage") },
      { path: "hatchery", to: "/hatchery", label: "Hatchery", icon: Sparkles, component: lazy(() => import("@/pages/HatcheryPage")) },
    ],
  },
  {
    id: "resources",
    label: "Shared Resources",
    routes: [
      { path: "inbox", to: "/inbox", label: "Inbox", icon: Inbox, component: lazy(() => import("@/pages/InboxPage")) },
      { path: "issues", to: "/issues", label: "Issues", icon: ListTodo, component: lazy(() => import("@/pages/IssuesPage")) },
      { path: "projects", to: "/projects", label: "Projects", icon: Briefcase, component: named(() => import("@/pages/ProjectsPage"), "ProjectsPage") },
      { path: "cases", to: "/cases", label: "Life Admin", icon: ClipboardList, component: named(() => import("@/pages/CasesPage"), "CasesPage") },
      { path: "goals", to: "/goals", label: "Goals", icon: Target, component: named(() => import("@/pages/GoalsPage"), "GoalsPage") },
      { path: "timeline", to: "/timeline", label: "Timeline", icon: CalendarClock, component: named(() => import("@/pages/TimelinePage"), "TimelinePage") },
      { path: "schedules", to: "/schedules", label: "Schedules", icon: CalendarClock, component: lazy(() => import("@/pages/RoutinesPage")) },
      { path: "skills", to: "/skills", label: "Skills", icon: Wrench, component: lazy(() => import("@/pages/SkillsPage")) },
      { path: "secrets", to: "/secrets", label: "Secrets", icon: Key, component: lazy(() => import("@/pages/SecretsPage")) },
    ],
  },
  {
    id: "system",
    label: "System",
    routes: [
      { path: "activity", to: "/activity", label: "Activity", icon: Activity, component: named(() => import("@/pages/ActivityPage"), "ActivityPage") },
      { path: "analytics", to: "/analytics", label: "Analytics", icon: Gauge, component: named(() => import("@/pages/AnalyticsPage"), "AnalyticsPage") },
      { path: "agents", to: "/agents", label: "Workers", icon: Cpu, component: lazy(() => import("@/pages/AgentsPage")) },
      { path: "usage", to: "/usage", label: "Usage", icon: Gauge, component: named(() => import("@/pages/UsageCostPage"), "UsageCostPage") },
      { path: "connections", to: "/connections", label: "Connections", icon: Cable, component: named(() => import("@/pages/ConnectionsPage"), "ConnectionsPage") },
      { path: "webhooks", to: "/webhooks", label: "Webhooks", icon: Webhook, component: lazy(() => import("@/pages/WebhooksPage")) },
      { path: "pairing", to: "/pairing", label: "Pairing", icon: Smartphone, component: lazy(() => import("@/pages/PairingPage")) },
      { path: "mcp", to: "/mcp", label: "MCP Servers", icon: Server, component: lazy(() => import("@/pages/McpPage")) },
      { path: "config", to: "/config", label: "Config", icon: Sliders, component: lazy(() => import("@/pages/ConfigPage")) },
    ],
  },
];

export const workspaceRoutes = navigationSections.flatMap((section) => section.routes);

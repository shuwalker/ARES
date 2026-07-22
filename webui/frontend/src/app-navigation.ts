import { lazy, type ComponentType, type LazyExoticComponent } from "react";
import {
  Activity,
  BookOpen,
  Briefcase,
  Cable,
  CalendarClock,
  ClipboardList,
  Cpu,
  FolderKanban,
  Gauge,
  GraduationCap,
  Heart,
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
  /**
   * Optional heading this route sits under inside its surface. Surfaces like
   * System hold a dozen destinations; a flat list buries them. Routes with no
   * group render first, ungrouped.
   */
  group?: string;
};

/**
 * Six product surfaces from docs/architecture/PRODUCT_SURFACES.md
 *
 * Chat | Companion | Self | Workshop | Library | System
 */
export type NavigationSection = {
  id: "chat" | "companion" | "self" | "workshop" | "library" | "system";
  label: string;
  /** Default deep-link when the rail icon is clicked */
  home: string;
  routes: AppRoute[];
};

export const navigationSections: NavigationSection[] = [
  {
    id: "chat",
    label: "Chat",
    home: "/chat",
    routes: [
      {
        path: "chat",
        to: "/chat",
        label: "Worker console",
        icon: MessageCircle,
        component: named(() => import("@/pages/ConversationPage"), "ConversationPage"),
      },
      // Legacy alias — same console (bookmarks /session links)
      {
        path: "conversation",
        to: "/conversation",
        label: "Conversation (legacy)",
        icon: MessageCircle,
        component: named(() => import("@/pages/ConversationPage"), "ConversationPage"),
      },
    ],
  },
  {
    id: "companion",
    label: "Companion",
    home: "/companion",
    routes: [
      {
        path: "companion",
        to: "/companion",
        label: "SI home",
        icon: Sparkles,
        component: named(() => import("@/pages/surfaces/CompanionPage"), "CompanionPage"),
      },
      {
        path: "today",
        to: "/today",
        label: "Today",
        icon: House,
        component: named(() => import("@/pages/TodayPage"), "TodayPage"),
        group: "Guidance",
      },
      // Approvals are a Companion responsibility (PRODUCT_SURFACES "identity,
      // intent, routing, continuity, approvals"), not Library knowledge. The
      // page itself is "Approvals, decisions, and notifications requiring your
      // attention" — it was only in Library because that surface absorbed
      // leftovers.
      {
        path: "inbox",
        to: "/inbox",
        label: "Approvals",
        icon: Inbox,
        component: lazy(() => import("@/pages/InboxPage")),
        group: "Guidance",
      },
      // "Scheduled and automated tasks that run on your behalf" is delegation,
      // which Companion owns. System keeps the machinery, not the intent.
      // "Schedule" is locked FOUNDATION vocabulary, so the label stays.
      {
        path: "schedules",
        to: "/schedules",
        label: "Schedules",
        icon: CalendarClock,
        component: lazy(() => import("@/pages/RoutinesPage")),
        group: "Delegation",
      },
    ],
  },
  {
    id: "self",
    label: "Self",
    home: "/self",
    routes: [
      {
        path: "self",
        to: "/self",
        label: "Journal & areas",
        icon: Heart,
        component: named(() => import("@/pages/surfaces/SelfPage"), "SelfPage"),
      },
      {
        path: "goals",
        to: "/goals",
        label: "Goals",
        icon: Target,
        component: named(() => import("@/pages/GoalsPage"), "GoalsPage"),
        group: "Life",
      },
      {
        path: "timeline",
        to: "/timeline",
        label: "Timeline",
        icon: CalendarClock,
        component: named(() => import("@/pages/TimelinePage"), "TimelinePage"),
        group: "Life",
      },
      {
        path: "cases",
        to: "/cases",
        label: "Life Admin",
        icon: ClipboardList,
        component: named(() => import("@/pages/CasesPage"), "CasesPage"),
        group: "Life",
      },
    ],
  },
  {
    id: "workshop",
    label: "Workshop",
    home: "/workshop",
    routes: [
      {
        path: "workshop",
        to: "/workshop",
        label: "Workshop home",
        icon: Wrench,
        component: named(() => import("@/pages/surfaces/WorkshopPage"), "WorkshopPage"),
      },
      {
        path: "workspace",
        to: "/workspace",
        label: "Files",
        icon: FolderKanban,
        component: named(() => import("@/pages/WorkspacePage"), "WorkspacePage"),
        group: "Make",
      },
      {
        path: "terminal",
        to: "/terminal",
        label: "Terminal",
        icon: SquareTerminal,
        component: named(() => import("@/pages/TerminalPage"), "TerminalPage"),
        group: "Make",
      },
      {
        path: "canvas",
        to: "/canvas",
        label: "Canvas",
        icon: Layers,
        component: named(() => import("@/pages/CanvasPage"), "CanvasPage"),
        group: "Make",
      },
      {
        path: "projects",
        to: "/projects",
        label: "Projects",
        icon: Briefcase,
        component: named(() => import("@/pages/ProjectsPage"), "ProjectsPage"),
        group: "Track",
      },
      {
        path: "board",
        to: "/board",
        label: "Board",
        icon: Kanban,
        component: named(() => import("@/pages/BoardChatPage"), "BoardChatPage"),
        group: "Track",
      },
      {
        path: "issues",
        to: "/issues",
        label: "Issues",
        icon: ListTodo,
        component: lazy(() => import("@/pages/IssuesPage")),
        group: "Track",
      },
    ],
  },
  {
    id: "library",
    label: "Library",
    home: "/library",
    routes: [
      {
        path: "library",
        to: "/library",
        label: "Alexandria",
        icon: BookOpen,
        component: named(() => import("@/pages/surfaces/LibraryPage"), "LibraryPage"),
      },
      {
        path: "collections",
        to: "/collections",
        label: "Collections",
        icon: FolderKanban,
        component: named(
          () => import("@/pages/surfaces/LibraryCollectionsPage"),
          "LibraryCollectionsPage",
        ),
        group: "Knowledge",
      },
      {
        path: "search",
        to: "/search",
        label: "Search",
        icon: Search,
        component: named(() => import("@/pages/SearchPage"), "SearchPage"),
        group: "Knowledge",
      },
    ],
  },
  {
    id: "system",
    label: "System",
    home: "/system",
    routes: [
      {
        path: "system",
        to: "/system",
        label: "System home",
        icon: Server,
        component: named(() => import("@/pages/surfaces/SystemPage"), "SystemPage"),
      },
      {
        path: "agents",
        to: "/agents",
        label: "Workers",
        icon: Cpu,
        component: lazy(() => import("@/pages/AgentsPage")),
        group: "Workers",
      },
      {
        path: "connections",
        to: "/connections",
        label: "Connections",
        icon: Cable,
        component: named(() => import("@/pages/ConnectionsPage"), "ConnectionsPage"),
        group: "Workers",
      },
      {
        path: "mcp",
        to: "/mcp",
        label: "MCP Servers",
        icon: Server,
        component: lazy(() => import("@/pages/McpPage")),
        group: "Workers",
      },
      // Skills are worker capabilities, not owned knowledge — Library is books
      // and study material, so these moved to the surface that configures what
      // workers can do.
      {
        path: "skills",
        to: "/skills",
        label: "Skills",
        icon: GraduationCap,
        component: lazy(() => import("@/pages/SkillsPage")),
        group: "Workers",
      },
      // Was built but never routed — reachable now instead of dead code.
      {
        path: "skills-studio",
        to: "/skills-studio",
        label: "Skill Studio",
        icon: GraduationCap,
        component: lazy(() => import("@/pages/SkillStudioPage")),
        group: "Workers",
      },
      // "Local model companion workshop" — local model management is
      // infrastructure (PRODUCT_SURFACES System: "local models"), not a user
      // artifact, so it belongs here rather than in Workshop.
      {
        path: "hatchery",
        to: "/hatchery",
        label: "Local Models",
        icon: Sparkles,
        component: lazy(() => import("@/pages/HatcheryPage")),
        group: "Workers",
      },
      {
        path: "activity",
        to: "/activity",
        label: "Activity",
        icon: Activity,
        component: named(() => import("@/pages/ActivityPage"), "ActivityPage"),
        group: "Health",
      },
      {
        path: "analytics",
        to: "/analytics",
        label: "Analytics",
        icon: Gauge,
        component: named(() => import("@/pages/AnalyticsPage"), "AnalyticsPage"),
        group: "Health",
      },
      {
        path: "usage",
        to: "/usage",
        label: "Usage & cost",
        icon: Gauge,
        component: named(() => import("@/pages/UsageCostPage"), "UsageCostPage"),
        group: "Health",
      },
      {
        path: "pairing",
        to: "/pairing",
        label: "Pairing",
        icon: Smartphone,
        component: lazy(() => import("@/pages/PairingPage")),
        group: "Box",
      },
      {
        path: "webhooks",
        to: "/webhooks",
        label: "Webhooks",
        icon: Webhook,
        component: lazy(() => import("@/pages/WebhooksPage")),
        group: "Box",
      },
      {
        path: "secrets",
        to: "/secrets",
        label: "Secrets",
        icon: Key,
        component: lazy(() => import("@/pages/SecretsPage")),
        group: "Box",
      },
      {
        path: "config",
        to: "/config",
        label: "Advanced settings",
        icon: Sliders,
        component: lazy(() => import("@/pages/ConfigPage")),
        group: "Box",
      },
    ],
  },
];

/**
 * Router registrations — unique paths. First declaration wins if duplicated.
 */
export const workspaceRoutes = Array.from(
  new Map(
    navigationSections.flatMap((section) => section.routes).map((route) => [route.path, route]),
  ).values(),
);

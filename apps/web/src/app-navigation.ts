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
  Palette,
  Search,
  Server,
  Shield,
  ShieldAlert,
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
 * Product environments and the supporting Control Center.
 *
 * Agent | Engineering | Studio | Life | Library | Control Center
 *
 * Settings is intentionally NOT a seventh environment — it is a utility
 * opened from the bottom-left gear and uses its own sidebar ownership.
 */
export type NavigationSection = {
  id: "chat" | "companion" | "workshop" | "studio" | "library" | "system";
  label: string;
  /** Default deep-link when the rail icon is clicked */
  home: string;
  routes: AppRoute[];
};

/** Deck mode including the non-environment Settings utility. */
export type DeckSurface = NavigationSection["id"] | "settings";

/**
 * Resolve which left-deck surface owns a pathname.
 * `/settings` is never Life/companion — it is a standalone utility.
 */
export function sectionForPath(pathname: string): DeckSurface {
  // Strip query/hash so accidental full URLs still resolve correctly.
  const path = pathname.split(/[?#]/, 1)[0] || pathname;

  if (path === "/settings" || path.startsWith("/settings/")) {
    return "settings";
  }
  if (path.startsWith("/chat") || path.startsWith("/conversation")) {
    return "chat";
  }
  if (path.startsWith("/self/")) {
    return "companion";
  }
  // Prefer longest matching route prefix so /system wins over accidental shorts.
  let best: { id: NavigationSection["id"]; len: number } | null = null;
  for (const section of navigationSections) {
    for (const route of section.routes) {
      if (path === route.to || path.startsWith(`${route.to}/`)) {
        if (!best || route.to.length > best.len) best = { id: section.id, len: route.to.length };
      }
    }
    if (path === section.home || path.startsWith(`${section.home}/`)) {
      if (!best || section.home.length > best.len) best = { id: section.id, len: section.home.length };
    }
  }
  return best?.id ?? "companion";
}

export const navigationSections: NavigationSection[] = [
  {
    id: "chat",
    label: "Agent",
    home: "/chat",
    routes: [
      {
        path: "chat",
        to: "/chat",
        label: "Sessions",
        icon: MessageCircle,
        component: named(() => import("@/features/advanced-chat/ConversationPage"), "ConversationPage"),
      },
      // Legacy alias — same console (bookmarks /session links)
      {
        path: "conversation",
        to: "/conversation",
        label: "Conversation (legacy)",
        icon: MessageCircle,
        component: named(() => import("@/features/advanced-chat/ConversationPage"), "ConversationPage"),
      },
    ],
  },
  {
    id: "companion",
    label: "Life",
    home: "/companion",
    routes: [
      {
        path: "companion",
        to: "/companion",
        label: "Overview",
        icon: Sparkles,
        component: named(() => import("@/features/companion/CompanionPage"), "CompanionPage"),
      },
      {
        path: "today",
        to: "/today",
        label: "Now",
        icon: House,
        component: named(() => import("@/features/companion/TodayPage"), "TodayPage"),
        group: "Today",
      },
      {
        path: "self",
        to: "/self",
        label: "Journal & Areas",
        icon: Heart,
        component: named(() => import("@/features/self/SelfPage"), "SelfPage"),
        group: "Personal",
      },
      {
        path: "goals",
        to: "/goals",
        label: "Goals",
        icon: Target,
        component: named(() => import("@/features/self/GoalsPage"), "GoalsPage"),
        group: "Personal",
      },
      {
        path: "cases",
        to: "/cases",
        label: "Life Admin",
        icon: ClipboardList,
        component: named(() => import("@/features/self/CasesPage"), "CasesPage"),
        group: "Personal",
      },
      {
        path: "timeline",
        to: "/timeline",
        label: "Timeline",
        icon: CalendarClock,
        component: named(() => import("@/features/self/TimelinePage"), "TimelinePage"),
        group: "History",
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
        component: lazy(() => import("@/features/companion/InboxPage")),
        group: "Attention",
      },
      // "Scheduled and automated tasks that run on your behalf" is delegation,
      // which Companion owns. System keeps the machinery, not the intent.
      // "Schedule" is locked FOUNDATION vocabulary, so the label stays.
      {
        path: "schedules",
        to: "/schedules",
        label: "Automations",
        icon: CalendarClock,
        component: lazy(() => import("@/features/companion/RoutinesPage")),
        group: "Automation",
      },
    ],
  },
  {
    id: "workshop",
    label: "Engineering",
    home: "/workshop",
    routes: [
      {
        path: "workshop",
        to: "/workshop",
        label: "Overview",
        icon: Wrench,
        component: named(() => import("@/features/workshop/WorkshopPage"), "WorkshopPage"),
      },
      {
        path: "workspace",
        to: "/workspace",
        label: "Files",
        icon: FolderKanban,
        component: named(() => import("@/features/workshop/WorkspacePage"), "WorkspacePage"),
        group: "Build",
      },
      {
        path: "terminal",
        to: "/terminal",
        label: "Terminal",
        icon: SquareTerminal,
        component: named(() => import("@/features/workshop/TerminalPage"), "TerminalPage"),
        group: "Build",
      },
      {
        path: "projects",
        to: "/projects",
        label: "Projects",
        icon: Briefcase,
        component: named(() => import("@/features/workshop/ProjectsPage"), "ProjectsPage"),
        group: "Manage",
      },
      {
        path: "board",
        to: "/board",
        label: "Board",
        icon: Kanban,
        component: named(() => import("@/features/workshop/BoardChatPage"), "BoardChatPage"),
        group: "Manage",
      },
      {
        path: "issues",
        to: "/issues",
        label: "Issues",
        icon: ListTodo,
        component: lazy(() => import("@/features/workshop/IssuesPage")),
        group: "Manage",
      },
    ],
  },
  {
    id: "studio",
    label: "Studio",
    home: "/studio",
    routes: [
      {
        path: "studio",
        to: "/studio",
        label: "Create",
        icon: Palette,
        component: named(() => import("@/features/studio/StudioPage"), "StudioPage"),
      },
      {
        path: "canvas",
        to: "/canvas",
        label: "Canvas",
        icon: Layers,
        component: named(() => import("@/features/workshop/CanvasPage"), "CanvasPage"),
        group: "Make",
      },
      {
        path: "studio-assets",
        to: "/studio-assets",
        label: "Assets",
        icon: FolderKanban,
        component: named(() => import("@/features/studio/StudioAssetsPage"), "StudioAssetsPage"),
        group: "Make",
      },
      {
        path: "studio-projects",
        to: "/studio-projects",
        label: "Creative Projects",
        icon: Briefcase,
        component: named(() => import("@/features/studio/StudioProjectsPage"), "StudioProjectsPage"),
        group: "Organize",
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
        component: named(() => import("@/features/library/LibraryPage"), "LibraryPage"),
      },
      {
        path: "collections",
        to: "/collections",
        label: "Collections",
        icon: FolderKanban,
        component: named(
          () => import("@/features/library/LibraryCollectionsPage"),
          "LibraryCollectionsPage",
        ),
        group: "Knowledge",
      },
      {
        path: "search",
        to: "/search",
        label: "Search",
        icon: Search,
        component: named(() => import("@/features/library/SearchPage"), "SearchPage"),
        group: "Knowledge",
      },
    ],
  },
  {
    id: "system",
    label: "Control Center",
    home: "/system",
    routes: [
      {
        path: "system",
        to: "/system",
        label: "Overview",
        icon: Server,
        component: named(() => import("@/features/system/SystemPage"), "SystemPage"),
      },
      {
        path: "agents",
        to: "/agents",
        label: "Workers",
        icon: Cpu,
        component: lazy(() => import("@/features/system/AgentsPage")),
        group: "Intelligence",
      },
      {
        path: "connections",
        to: "/connections",
        label: "Connections",
        icon: Cable,
        component: named(() => import("@/features/system/ConnectionsPage"), "ConnectionsPage"),
        group: "Intelligence",
      },
      {
        path: "mcp",
        to: "/mcp",
        label: "MCP Servers",
        icon: Server,
        component: lazy(() => import("@/features/system/McpPage")),
        group: "Intelligence",
      },
      // Skills are worker capabilities, not owned knowledge — Library is books
      // and study material, so these moved to the surface that configures what
      // workers can do.
      {
        path: "skills",
        to: "/skills",
        label: "Skills",
        icon: GraduationCap,
        component: lazy(() => import("@/features/system/SkillsPage")),
        group: "Intelligence",
      },
      // Was built but never routed — reachable now instead of dead code.
      {
        path: "skills-studio",
        to: "/skills-studio",
        label: "Skill Studio",
        icon: GraduationCap,
        component: lazy(() => import("@/features/system/SkillStudioPage")),
        group: "Intelligence",
      },
      // "Local model companion workshop" — local model management is
      // infrastructure (PRODUCT_SURFACES System: "local models"), not a user
      // artifact, so it belongs here rather than in Workshop.
      {
        path: "hatchery",
        to: "/hatchery",
        label: "Local Models",
        icon: Sparkles,
        component: lazy(() => import("@/features/system/HatcheryPage")),
        group: "Intelligence",
      },
      {
        path: "activity",
        to: "/activity",
        label: "Activity",
        icon: Activity,
        component: named(() => import("@/features/system/ActivityPage"), "ActivityPage"),
        group: "Observe",
      },
      {
        path: "analytics",
        to: "/analytics",
        label: "Analytics",
        icon: Gauge,
        component: named(() => import("@/features/system/AnalyticsPage"), "AnalyticsPage"),
        group: "Observe",
      },
      {
        path: "usage",
        to: "/usage",
        label: "Usage & cost",
        icon: Gauge,
        component: named(() => import("@/features/system/UsageCostPage"), "UsageCostPage"),
        group: "Observe",
      },
      {
        path: "pairing",
        to: "/pairing",
        label: "Pairing",
        icon: Smartphone,
        component: lazy(() => import("@/features/system/PairingPage")),
        group: "Access & automation",
      },
      {
        path: "webhooks",
        to: "/webhooks",
        label: "Webhooks",
        icon: Webhook,
        component: lazy(() => import("@/features/system/WebhooksPage")),
        group: "Access & automation",
      },
      {
        path: "secrets",
        to: "/secrets",
        label: "Secrets",
        icon: Key,
        component: lazy(() => import("@/features/system/SecretsPage")),
        group: "Access & automation",
      },
      {
        path: "memory-privacy",
        to: "/memory-privacy",
        label: "Memory & Privacy",
        icon: Shield,
        component: named(() => import("@/features/system/MemoryPrivacyPage"), "MemoryPrivacyPage"),
        group: "Access & automation",
      },
      {
        path: "permissions-autonomy",
        to: "/permissions-autonomy",
        label: "Permissions & Autonomy",
        icon: ShieldAlert,
        component: named(
          () => import("@/features/system/PermissionsAutonomyPage"),
          "PermissionsAutonomyPage",
        ),
        group: "Access & automation",
      },
      {
        path: "config",
        to: "/config",
        label: "Advanced settings",
        icon: Sliders,
        component: lazy(() => import("@/features/system/ConfigPage")),
        group: "Access & automation",
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

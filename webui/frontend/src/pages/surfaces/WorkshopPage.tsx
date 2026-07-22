import {
  FolderKanban,
  Kanban,
  Layers,
  Sparkles,
  SquareTerminal,
  Briefcase,
  ListTodo,
  FileCode,
} from "lucide-react";

import { SurfaceLinkGrid, SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";

/**
 * Workshop surface — create, build, engineer.
 * Primary question: what are we building?
 */
export function WorkshopPage() {
  return (
    <SurfaceShell
      title="Workshop"
      description="Where real work happens — files, code, terminal, CAD, analysis, and artifacts. Output-oriented."
    >
      <SurfaceNote>
        Workspace-scoped: pick a root folder, then create. The Companion may open projects here from
        intent (“open my CAD project”) once routing is mature. CAD/sim adapters arrive as packs —
        files and terminal are first-class now.
      </SurfaceNote>

      <SurfaceLinkGrid
        links={[
          {
            to: "/workspace",
            label: "Workspace files",
            description: "Browse and work in the rooted project tree.",
            icon: FolderKanban,
          },
          {
            to: "/terminal",
            label: "Terminal",
            description: "Hands on the host — builds, scripts, tools.",
            icon: SquareTerminal,
          },
          {
            to: "/projects",
            label: "Projects",
            description: "Named projects and status.",
            icon: Briefcase,
          },
          {
            to: "/board",
            label: "Board",
            description: "Kanban-style work board for active efforts.",
            icon: Kanban,
          },
          {
            to: "/canvas",
            label: "Canvas",
            description: "Freeform whiteboard for planning and design.",
            icon: Layers,
          },
          {
            to: "/issues",
            label: "Issues",
            description: "Tracked problems and tasks.",
            icon: ListTodo,
          },
          {
            to: "/hatchery",
            label: "Hatchery",
            description: "Experiments and incubating ideas.",
            icon: Sparkles,
          },
          {
            to: "/chat",
            label: "Chat while building",
            description: "Worker console with tools — pair-program mode.",
            icon: FileCode,
          },
        ]}
      />
    </SurfaceShell>
  );
}

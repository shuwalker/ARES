import {
  FolderKanban,
  Kanban,
  Layers,
  SquareTerminal,
  Briefcase,
  ListTodo,
  FileCode,
} from "lucide-react";

import { SurfaceLinkGrid, SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";

/**
 * Engineering surface — design, build, test, and operate technical work.
 * Primary question: what are we building?
 */
export function WorkshopPage() {
  return (
    <SurfaceShell
      title="Engineering"
      description="Design, build, test, and manage technical systems with your Agent."
    >
      <SurfaceNote>
        Choose a workspace and work directly, or delegate through Agent. Code, files,
        projects, and verification are available now; CAD and simulation connect here as
        engineering integrations mature.
      </SurfaceNote>

      <SurfaceLinkGrid
        links={[
          {
            to: "/workspace",
            label: "Files & code",
            description: "Browse and edit the selected engineering workspace.",
            icon: FolderKanban,
          },
          {
            to: "/terminal",
            label: "Terminal",
            description: "Run builds, tests, scripts, and engineering tools.",
            icon: SquareTerminal,
          },
          {
            to: "/projects",
            label: "Projects",
            description: "Organize technical efforts, objectives, and status.",
            icon: Briefcase,
          },
          {
            to: "/board",
            label: "Board",
            description: "Plan and track active engineering work.",
            icon: Kanban,
          },
          {
            to: "/canvas",
            label: "Canvas",
            description: "Explore diagrams, spatial designs, and visual concepts.",
            icon: Layers,
          },
          {
            to: "/issues",
            label: "Issues",
            description: "Track defects, requirements, and technical tasks.",
            icon: ListTodo,
          },
          {
            to: "/chat",
            label: "Open Agent",
            description: "Discuss, delegate, and review engineering work.",
            icon: FileCode,
          },
        ]}
      />
    </SurfaceShell>
  );
}

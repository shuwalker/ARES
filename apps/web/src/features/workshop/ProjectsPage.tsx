import { useCallback, useEffect, useState } from "react";
import {
  ArrowUpDown,
  FolderKanban,
  LoaderCircle,
  Plus,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { apiFetch, readableError } from "@/shared/api-client";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ProjectStatus = "active" | "on_hold" | "completed" | "archived";

interface Project {
  id: string;
  name: string;
  description: string;
  status: ProjectStatus;
  domain: string;
  color?: string;
  icon?: string;
  targetDate?: string;
  taskCount?: number;
  createdAt: string;
  updatedAt: string;
  recentActivity?: string[];
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STATUS_LABELS: Record<ProjectStatus, string> = {
  active: "Active",
  on_hold: "On Hold",
  completed: "Completed",
  archived: "Archived",
};

const STATUS_DOT: Record<ProjectStatus, string> = {
  active: "bg-green-500",
  on_hold: "bg-yellow-500",
  completed: "bg-blue-500",
  archived: "bg-muted-foreground/40",
};

const STATUS_BADGE_VARIANT: Record<
  ProjectStatus,
  "default" | "secondary" | "outline" | "destructive"
> = {
  active: "default",
  on_hold: "secondary",
  completed: "outline",
  archived: "destructive",
};

type SortField = "name" | "updated" | "created" | "targetDate";
type SortDir = "asc" | "desc";

const SORT_OPTIONS: { field: SortField; label: string }[] = [
  { field: "name", label: "Name" },
  { field: "updated", label: "Updated" },
  { field: "created", label: "Created" },
  { field: "targetDate", label: "Target date" },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function timestamp(value: unknown): string {
  if (typeof value === "number") return new Date(value * 1000).toISOString();
  const parsed = new Date(String(value || ""));
  return Number.isNaN(parsed.getTime()) ? new Date().toISOString() : parsed.toISOString();
}

function normalizeProject(value: Record<string, unknown>): Project {
  return {
    id: String(value.project_id ?? value.id ?? ""),
    name: String(value.name ?? "Untitled project"),
    description: String(value.description ?? ""),
    status: (["active", "on_hold", "completed", "archived"].includes(String(value.status))
      ? String(value.status)
      : "active") as ProjectStatus,
    domain: String(value.domain ?? "General"),
    color: value.color ? String(value.color) : undefined,
    targetDate: value.target_date ? String(value.target_date) : undefined,
    createdAt: timestamp(value.created_at),
    updatedAt: timestamp(value.updated_at ?? value.created_at),
  };
}

function relativeTime(value?: string | null): string {
  if (!value) return "—";
  const elapsed = Date.now() - new Date(value).getTime();
  const abs = Math.abs(elapsed);
  const minutes = Math.floor(abs / 60_000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ${elapsed > 0 ? "ago" : "from now"}`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ${elapsed > 0 ? "ago" : "from now"}`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ${elapsed > 0 ? "ago" : "from now"}`;
  return new Date(value).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

function sortProjects(
  projects: Project[],
  sortField: SortField,
  sortDir: SortDir,
): Project[] {
  return [...projects].sort((a, b) => {
    let cmp = 0;
    if (sortField === "name") {
      cmp = a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
    } else {
      const aVal = sortField === "updated" ? a.updatedAt : sortField === "created" ? a.createdAt : a.targetDate ?? "";
      const bVal = sortField === "updated" ? b.updatedAt : sortField === "created" ? b.createdAt : b.targetDate ?? "";
      const aTime = aVal ? new Date(aVal).getTime() : 0;
      const bTime = bVal ? new Date(bVal).getTime() : 0;
      cmp = aTime - bTime;
    }
    return sortDir === "asc" ? cmp : -cmp;
  });
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function ProjectsPage() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [loading, setLoading] = useState(true);
  const [sortField, setSortField] = useState<SortField>("name");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [adding, setAdding] = useState(false);
  const [newName, setNewName] = useState("");
  const [newDomain, setNewDomain] = useState("");
  const [newDesc, setNewDesc] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState("");

  const loadProjects = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const data = await apiFetch<{ projects?: Record<string, unknown>[] }>("/api/projects");
      setProjects((data.projects ?? []).map(normalizeProject));
    } catch (cause) {
      setProjects([]);
      setError(readableError(cause, "Projects could not be loaded."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadProjects();
  }, [loadProjects]);

  const sorted = sortProjects(
    projects.filter((p) => p.status !== "archived"),
    sortField,
    sortDir,
  );

  const counts = {
    active: projects.filter((p) => p.status === "active").length,
    on_hold: projects.filter((p) => p.status === "on_hold").length,
    completed: projects.filter((p) => p.status === "completed").length,
  };

  async function addProject() {
    if (!newName.trim()) return;
    setBusy("create");
    setError("");
    try {
      await apiFetch("/api/projects/create", {
        method: "POST",
        body: JSON.stringify({
          name: newName.trim(),
          description: newDesc.trim(),
          domain: newDomain.trim() || "General",
        }),
      });
      setNewName("");
      setNewDomain("");
      setNewDesc("");
      setAdding(false);
      await loadProjects();
    } catch (cause) {
      setError(readableError(cause, "The project could not be created."));
    } finally {
      setBusy("");
    }
  }

  async function cycleStatus(project: Project) {
    const order: ProjectStatus[] = ["active", "on_hold", "completed", "archived"];
    const next = order[(order.indexOf(project.status) + 1) % order.length];
    setBusy(project.id);
    try {
      await apiFetch("/api/projects/update", {
        method: "POST",
        body: JSON.stringify({ project_id: project.id, status: next }),
      });
      await loadProjects();
    } catch (cause) {
      setError(readableError(cause, "Project status could not be changed."));
    } finally {
      setBusy("");
    }
  }

  async function deleteProject(id: string) {
    setBusy(id);
    try {
      await apiFetch("/api/projects/delete", {
        method: "POST",
        body: JSON.stringify({ project_id: id }),
      });
      await loadProjects();
    } catch (cause) {
      setError(readableError(cause, "The project could not be deleted."));
    } finally {
      setBusy("");
    }
  }

  const sortLabel = SORT_OPTIONS.find((o) => o.field === sortField)?.label ?? "Name";

  return (
    <div className="page-stack">
      <PageHeader
        title="Projects"
        description="Domains and projects your Synthetic Person is working across."
        action={
          <Button size="sm" onClick={() => setAdding(true)}>
            <Plus className="size-4" />
            Add project
          </Button>
        }
      />
      {error && <p className="text-sm text-destructive" role="alert">{error}</p>}

      {/* Summary counts */}
      <div className="flex flex-wrap items-center gap-3 text-sm text-muted-foreground">
        <span className="inline-flex items-center gap-1.5">
          <span className={`size-2 rounded-full ${STATUS_DOT.active}`} />
          {counts.active} Active
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className={`size-2 rounded-full ${STATUS_DOT.on_hold}`} />
          {counts.on_hold} On Hold
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className={`size-2 rounded-full ${STATUS_DOT.completed}`} />
          {counts.completed} Completed
        </span>

        <div className="ml-auto flex items-center gap-2">
          <Popover>
            <PopoverTrigger asChild>
              <Button variant="ghost" size="sm" className="w-fit text-xs">
                <ArrowUpDown className="h-3.5 w-3.5" />
                <span className="ml-1">Sort: {sortLabel}</span>
              </Button>
            </PopoverTrigger>
            <PopoverContent align="end" className="w-44 p-0">
              <div className="p-2 space-y-0.5">
                {SORT_OPTIONS.map((opt) => (
                  <button
                    key={opt.field}
                    type="button"
                    className={`flex w-full items-center justify-between rounded-sm px-2 py-1.5 text-sm ${
                      sortField === opt.field
                        ? "bg-accent/50 text-foreground"
                        : "text-muted-foreground hover:bg-accent/50"
                    }`}
                    onClick={() => {
                      if (sortField === opt.field) {
                        setSortDir((d) => (d === "asc" ? "desc" : "asc"));
                      } else {
                        setSortField(opt.field);
                        setSortDir(opt.field === "name" || opt.field === "targetDate" ? "asc" : "desc");
                      }
                    }}
                  >
                    <span>{opt.label}</span>
                    {sortField === opt.field && (
                      <span className="text-xs text-muted-foreground">
                        {sortDir === "asc" ? "↑" : "↓"}
                      </span>
                    )}
                  </button>
                ))}
              </div>
            </PopoverContent>
          </Popover>
        </div>
      </div>

      {/* Add project form */}
      {adding && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">New Project</CardTitle>
          </CardHeader>
          <CardContent className="border-t pt-4 space-y-3">
            <form
              className="space-y-3"
              onSubmit={(e) => {
                e.preventDefault();
                void addProject();
              }}
            >
              <div className="grid gap-2 sm:grid-cols-2">
                <Input
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder="Project name…"
                  className="flex-1"
                  autoFocus
                />
                <Input
                  value={newDomain}
                  onChange={(e) => setNewDomain(e.target.value)}
                  placeholder="Domain (e.g. Health, Finance)…"
                  className="flex-1"
                />
              </div>
              <Input
                value={newDesc}
                onChange={(e) => setNewDesc(e.target.value)}
                placeholder="Description…"
              />
              <div className="flex items-center gap-2">
                <Button type="submit" size="sm" disabled={!newName.trim() || busy === "create"}>
                  {busy === "create" ? "Adding…" : "Add"}
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    setAdding(false);
                    setNewName("");
                    setNewDomain("");
                    setNewDesc("");
                  }}
                >
                  Cancel
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {loading ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading projects…</p>
        </div>
      ) : sorted.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <FolderKanban className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            No projects yet. Create one to get started.
          </p>
        </div>
      ) : (
        <div className="grid gap-3">
          {sorted.map((project) => (
            <Card key={project.id} className="transition-colors hover:bg-accent/30">
              <CardHeader>
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => void cycleStatus(project)}
                        disabled={busy === project.id}
                        className="transition-colors hover:text-foreground"
                        aria-label={`Status: ${STATUS_LABELS[project.status]}. Click to advance.`}
                      >
                        <span className={`inline-block size-3 rounded-full ${STATUS_DOT[project.status]}`} />
                      </button>
                      <CardTitle className="truncate text-base">
                        {project.name || "Untitled project"}
                      </CardTitle>
                      <Badge variant={STATUS_BADGE_VARIANT[project.status]} className="text-[0.65rem] uppercase tracking-wider">
                        {STATUS_LABELS[project.status]}
                      </Badge>
                      <Badge variant="outline" className="text-[0.6rem] uppercase tracking-wider text-muted-foreground">
                        {project.domain}
                      </Badge>
                    </div>
                    {project.description && (
                      <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">
                        {project.description}
                      </p>
                    )}
                  </div>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    className="shrink-0 text-muted-foreground hover:text-destructive"
                    onClick={() => void deleteProject(project.id)}
                    disabled={busy === project.id}
                    aria-label="Delete project"
                  >
                    ×
                  </Button>
                </div>
              </CardHeader>

              <CardContent className="border-t pt-4">
                <div className="flex flex-wrap items-center gap-x-6 gap-y-2 text-xs text-muted-foreground">
                  {project.taskCount != null && (
                    <span>
                      {project.taskCount} task{project.taskCount === 1 ? "" : "s"}
                    </span>
                  )}
                  {project.targetDate && (
                    <span>Target: {new Date(project.targetDate).toLocaleDateString()}</span>
                  )}
                  <span>Updated {relativeTime(project.updatedAt)}</span>

                  {/* Recent activity preview */}
                  {project.recentActivity && project.recentActivity.length > 0 && (
                    <div className="mt-2 w-full">
                      <p className="text-[0.65rem] uppercase tracking-wider text-muted-foreground/60 mb-1">Recent activity</p>
                      <ul className="space-y-0.5 text-xs text-muted-foreground">
                        {project.recentActivity.slice(0, 3).map((act, i) => (
                          <li key={i} className="truncate">• {act}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}

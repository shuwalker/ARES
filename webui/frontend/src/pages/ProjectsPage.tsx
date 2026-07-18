import { useEffect, useState } from "react";
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
import { apiFetch } from "@/shared/api-client";

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

const STORAGE_KEY = "ares-projects";

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

function uid(): string {
  return Math.random().toString(36).slice(2, 10);
}

function loadFromStorage(): Project[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveToStorage(projects: Project[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(projects));
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

  // Load from API, fall back to localStorage
  useEffect(() => {
    let active = true;
    setLoading(true);
    apiFetch<{ projects?: Project[] }>("/api/projects")
      .then((data) => {
        if (active) {
          const list = data.projects ?? (Array.isArray(data) ? data : []);
          setProjects(list);
          saveToStorage(list);
        }
      })
      .catch(() => {
        if (active) setProjects(loadFromStorage());
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  // Persist to localStorage on changes (for offline / fallback)
  useEffect(() => {
    if (!loading) saveToStorage(projects);
  }, [projects, loading]);

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

  function addProject() {
    if (!newName.trim()) return;
    const now = new Date().toISOString();
    const p: Project = {
      id: uid(),
      name: newName.trim(),
      description: newDesc.trim(),
      domain: newDomain.trim() || "General",
      status: "active",
      createdAt: now,
      updatedAt: now,
    };
    setProjects((prev) => [...prev, p]);
    setNewName("");
    setNewDomain("");
    setNewDesc("");
    setAdding(false);
  }

  function cycleStatus(project: Project) {
    const order: ProjectStatus[] = ["active", "on_hold", "completed", "archived"];
    const next = order[(order.indexOf(project.status) + 1) % order.length];
    setProjects((prev) =>
      prev.map((p) =>
        p.id === project.id ? { ...p, status: next, updatedAt: new Date().toISOString() } : p,
      ),
    );
  }

  function deleteProject(id: string) {
    setProjects((prev) => prev.filter((p) => p.id !== id));
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
                addProject();
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
                <Button type="submit" size="sm" disabled={!newName.trim()}>
                  Add
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
                        onClick={() => cycleStatus(project)}
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
                    onClick={() => deleteProject(project.id)}
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
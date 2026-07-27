import { useCallback, useState, type Dispatch, type SetStateAction } from "react";
import {
  AlertTriangle,
  CircleDot,
  Filter,
  LoaderCircle,
  Plus,
  ShieldCheck,
  ShieldQuestion,
  XCircle,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useProductState } from "@/shared/use-product-state";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type CaseStatus = "draft" | "in_progress" | "in_review" | "approved" | "done" | "cancelled";
type CasePriority = "low" | "medium" | "high" | "critical";

interface LifeCase {
  id: string;
  title: string;
  description: string;
  status: CaseStatus;
  priority: CasePriority;
  caseType: string;
  projectId?: string;
  key?: string;
  createdAt: string;
  updatedAt: string;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STATUS_LABELS: Record<CaseStatus, string> = {
  draft: "Draft",
  in_progress: "In Progress",
  in_review: "In Review",
  approved: "Approved",
  done: "Done",
  cancelled: "Cancelled",
};

const STATUS_ICONS: Record<CaseStatus, typeof CircleDot> = {
  draft: ShieldQuestion,
  in_progress: CircleDot,
  in_review: Filter,
  approved: ShieldCheck,
  done: ShieldCheck,
  cancelled: XCircle,
};

const STATUS_COLORS: Record<CaseStatus, string> = {
  draft: "text-muted-foreground",
  in_progress: "text-yellow-500",
  in_review: "text-blue-500",
  approved: "text-green-500",
  done: "text-green-600",
  cancelled: "text-red-500",
};

const STATUS_BADGE_VARIANT: Record<
  CaseStatus,
  "default" | "secondary" | "outline" | "destructive"
> = {
  draft: "outline",
  in_progress: "secondary",
  in_review: "secondary",
  approved: "default",
  done: "default",
  cancelled: "destructive",
};

const PRIORITY_COLORS: Record<string, string> = {
  critical: "text-red-500 bg-red-500/10 border-red-500/30",
  high: "text-orange-500 bg-orange-500/10 border-orange-500/30",
  medium: "text-yellow-500 bg-yellow-500/10 border-yellow-500/30",
  low: "text-muted-foreground bg-muted border-border/50",
};

const DEFAULT_STATUS_FILTERS: CaseStatus[] = [
  "draft",
  "in_progress",
  "in_review",
  "approved",
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function uid(): string {
  return Math.random().toString(36).slice(2, 10);
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

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function CasesPage() {
  const [caseState, setCaseState, caseStatus] = useProductState<{ cases: LifeCase[] }>("cases", { cases: [] });
  const cases = caseState.cases;
  const setCases: Dispatch<SetStateAction<LifeCase[]>> = useCallback((update) => {
    setCaseState((current) => ({
      cases: typeof update === "function" ? update(current.cases) : update,
    }));
  }, [setCaseState]);
  const [statusFilter, setStatusFilter] = useState<CaseStatus | "all">("all");
  const [search, setSearch] = useState("");
  const [adding, setAdding] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [newType, setNewType] = useState("");
  const [newPriority, setNewPriority] = useState<CasePriority>("medium");

  const filtered = cases
    .filter((c) => statusFilter === "all" || c.status === statusFilter)
    .filter(
      (c) =>
        !search ||
        c.title.toLowerCase().includes(search.toLowerCase()) ||
        c.description.toLowerCase().includes(search.toLowerCase()) ||
        c.caseType?.toLowerCase().includes(search.toLowerCase()),
    )
    .sort((a, b) => {
      // Priority order: critical > high > medium > low, then by updatedAt desc
      const priorityOrder: Record<CasePriority, number> = {
        critical: 0,
        high: 1,
        medium: 2,
        low: 3,
      };
      const pDiff = (priorityOrder[a.priority] ?? 2) - (priorityOrder[b.priority] ?? 2);
      if (pDiff !== 0) return pDiff;
      return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
    });

  const counts = {
    draft: cases.filter((c) => c.status === "draft").length,
    in_progress: cases.filter((c) => c.status === "in_progress").length,
    in_review: cases.filter((c) => c.status === "in_review").length,
    approved: cases.filter((c) => c.status === "approved").length,
    done: cases.filter((c) => c.status === "done").length,
    cancelled: cases.filter((c) => c.status === "cancelled").length,
  };

  function addCase() {
    if (!newTitle.trim()) return;
    const now = new Date().toISOString();
    const c: LifeCase = {
      id: uid(),
      title: newTitle.trim(),
      description: "",
      status: "draft",
      priority: newPriority,
      caseType: newType.trim() || "admin",
      createdAt: now,
      updatedAt: now,
    };
    setCases((prev) => [...prev, c]);
    setNewTitle("");
    setNewType("");
    setNewPriority("medium");
    setAdding(false);
  }

  function cycleStatus(c: LifeCase) {
    const order: CaseStatus[] = ["draft", "in_progress", "in_review", "approved", "done", "cancelled"];
    const next = order[(order.indexOf(c.status) + 1) % order.length];
    setCases((prev) =>
      prev.map((x) =>
        x.id === c.id ? { ...x, status: next, updatedAt: new Date().toISOString() } : x,
      ),
    );
  }

  function deleteCase(id: string) {
    setCases((prev) => prev.filter((c) => c.id !== id));
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Life Admin"
        description="Track life admin cases — paperwork, errands, appointments, and to-dos."
        action={
          <Button size="sm" onClick={() => setAdding(true)}>
            <Plus className="size-4" />
            New case
          </Button>
        }
      />

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <Tabs
          value={statusFilter}
          onValueChange={(v) => setStatusFilter(v as CaseStatus | "all")}
        >
          <TabsList>
            <TabsTrigger value="all">All ({cases.length})</TabsTrigger>
            <TabsTrigger value="draft">
              Draft ({counts.draft})
            </TabsTrigger>
            <TabsTrigger value="in_progress">
              Active ({counts.in_progress})
            </TabsTrigger>
            <TabsTrigger value="in_review">
              Review ({counts.in_review})
            </TabsTrigger>
            <TabsTrigger value="done">
              Done ({counts.done})
            </TabsTrigger>
          </TabsList>
        </Tabs>

        <div className="relative ml-auto">
          <Filter className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search cases..."
            className="w-48 pl-8"
          />
        </div>
      </div>

      {/* Add case form */}
      {adding && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">New Life Admin Case</CardTitle>
          </CardHeader>
          <CardContent className="border-t pt-4 space-y-3">
            <form
              className="space-y-3"
              onSubmit={(e) => {
                e.preventDefault();
                addCase();
              }}
            >
              <div className="grid gap-2 sm:grid-cols-2">
                <Input
                  value={newTitle}
                  onChange={(e) => setNewTitle(e.target.value)}
                  placeholder="Case title…"
                  className="flex-1"
                  autoFocus
                />
                <Input
                  value={newType}
                  onChange={(e) => setNewType(e.target.value)}
                  placeholder="Type (e.g. paperwork, appointment)…"
                  className="flex-1"
                />
              </div>
              <div className="flex items-center gap-2">
                <span className="text-xs text-muted-foreground">Priority:</span>
                {(["low", "medium", "high", "critical"] as CasePriority[]).map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => setNewPriority(p)}
                    className={`rounded-md border px-2 py-1 text-xs capitalize transition-colors ${
                      newPriority === p
                        ? PRIORITY_COLORS[p]
                        : "border-border text-muted-foreground hover:bg-accent/50"
                    }`}
                  >
                    {p}
                  </button>
                ))}
              </div>
              <div className="flex items-center gap-2">
                <Button type="submit" size="sm" disabled={!newTitle.trim()}>
                  Add
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    setAdding(false);
                    setNewTitle("");
                    setNewType("");
                    setNewPriority("medium");
                  }}
                >
                  Cancel
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {caseStatus.error && <p className="text-sm text-destructive" role="alert">{caseStatus.error}</p>}
      {caseStatus.loading ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading cases…</p>
        </div>
      ) : filtered.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <AlertTriangle className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            {statusFilter === "all" ? "No cases yet. Create one to get started." : `No ${STATUS_LABELS[statusFilter as CaseStatus]?.toLowerCase()} cases.`}
          </p>
        </div>
      ) : (
        <div className="grid gap-3">
          {filtered.map((c) => {
            const StatusIcon = STATUS_ICONS[c.status] || CircleDot;
            return (
              <Card key={c.id} className="transition-colors hover:bg-accent/30">
                <CardHeader className="pb-2">
                  <div className="flex items-start justify-between gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => cycleStatus(c)}
                          className="transition-colors hover:text-foreground"
                          aria-label={`Status: ${STATUS_LABELS[c.status]}. Click to advance.`}
                        >
                          <StatusIcon className={`size-4 ${STATUS_COLORS[c.status]}`} />
                        </button>
                        <CardTitle className="truncate text-sm font-medium">
                          {c.title || "Untitled case"}
                        </CardTitle>
                        <Badge variant={STATUS_BADGE_VARIANT[c.status]} className="text-[0.6rem] uppercase tracking-wider">
                          {STATUS_LABELS[c.status]}
                        </Badge>
                        <Badge variant="outline" className={`text-[0.6rem] uppercase tracking-wider ${PRIORITY_COLORS[c.priority] || ""}`}>
                          {c.priority}
                        </Badge>
                        {c.caseType && (
                          <Badge variant="outline" className="text-[0.6rem] uppercase tracking-wider text-muted-foreground">
                            {c.caseType}
                          </Badge>
                        )}
                      </div>
                      {c.description && (
                        <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">
                          {c.description}
                        </p>
                      )}
                    </div>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      className="shrink-0 text-muted-foreground hover:text-destructive"
                      onClick={() => deleteCase(c.id)}
                      aria-label="Delete case"
                    >
                      ×
                    </Button>
                  </div>
                </CardHeader>

                <CardContent className="pt-2">
                  <div className="flex items-center gap-3 text-[0.65rem] text-muted-foreground">
                    {c.key && (
                      <span className="font-mono">{c.key}</span>
                    )}
                    <span className="ml-auto">Updated {relativeTime(c.updatedAt)}</span>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}

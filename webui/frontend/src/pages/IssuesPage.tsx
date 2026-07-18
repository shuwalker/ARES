import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertCircle,
  ArrowDownUp,
  Calendar,
  CircleDot,
  ListTodo,
  Pencil,
  Plus,
  Search,
  Tag,
  Trash2,
  X,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";

// ── Types ───────────────────────────────────────────────────────────────────

type IssueStatus = "open" | "in_progress" | "done" | "cancelled";
type IssuePriority = "low" | "medium" | "high" | "critical";

interface Issue {
  id: string;
  title: string;
  description: string;
  status: IssueStatus;
  priority: IssuePriority;
  labels: string[];
  dueDate: string; // ISO date string or ""
  createdAt: string;
  updatedAt: string;
}

// ── Constants ────────────────────────────────────────────────────────────────

const STORAGE_KEY = "ares.issues";

const STATUS_OPTIONS: { value: IssueStatus; label: string }[] = [
  { value: "open", label: "Open" },
  { value: "in_progress", label: "In Progress" },
  { value: "done", label: "Done" },
  { value: "cancelled", label: "Cancelled" },
];

const PRIORITY_OPTIONS: { value: IssuePriority; label: string }[] = [
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
  { value: "critical", label: "Critical" },
];

const STATUS_LABELS: Record<IssueStatus, string> = {
  open: "Open",
  in_progress: "In Progress",
  done: "Done",
  cancelled: "Cancelled",
};

const PRIORITY_COLORS: Record<IssuePriority, string> = {
  critical: "text-red-500 bg-red-500/10 border-red-500/30",
  high: "text-orange-500 bg-orange-500/10 border-orange-500/30",
  medium: "text-yellow-500 bg-yellow-500/10 border-yellow-500/30",
  low: "text-muted-foreground bg-muted border-border/50",
};

const STATUS_ICON_COLORS: Record<IssueStatus, string> = {
  open: "text-blue-500",
  in_progress: "text-yellow-500",
  done: "text-green-500",
  cancelled: "text-muted-foreground",
};

const PRESET_LABELS = [
  "bug",
  "feature",
  "improvement",
  "docs",
  "infra",
  "security",
  "design",
  "research",
  "blocked",
  "wontfix",
];

// ── Helpers ──────────────────────────────────────────────────────────────────

function uid(): string {
  return `issue-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function loadIssues(): Issue[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    return JSON.parse(raw) as Issue[];
  } catch {
    return [];
  }
}

function saveIssues(issues: Issue[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(issues));
}

function formatDate(iso: string): string {
  if (!iso) return "";
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}

function isOverdue(dueDate: string): boolean {
  if (!dueDate) return false;
  return new Date(dueDate) < new Date(new Date().toISOString().slice(0, 10));
}

// ── Component ───────────────────────────────────────────────────────────────

interface IssueFormData {
  title: string;
  description: string;
  status: IssueStatus;
  priority: IssuePriority;
  labels: string[];
  dueDate: string;
}

const EMPTY_FORM: IssueFormData = {
  title: "",
  description: "",
  status: "open",
  priority: "medium",
  labels: [],
  dueDate: "",
};

export default function IssuesPage() {
  const [issues, setIssues] = useState<Issue[]>(loadIssues);
  const [statusFilter, setStatusFilter] = useState<IssueStatus | "all">("all");
  const [priorityFilter, setPriorityFilter] = useState<IssuePriority | "all">("all");
  const [search, setSearch] = useState("");
  const [sortKey, setSortKey] = useState<"updatedAt" | "priority" | "dueDate">("updatedAt");

  // Dialog state
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingIssue, setEditingIssue] = useState<Issue | null>(null);
  const [form, setForm] = useState<IssueFormData>(EMPTY_FORM);

  // Label input
  const [labelInput, setLabelInput] = useState("");

  // Delete confirmation
  const [deleteTarget, setDeleteTarget] = useState<Issue | null>(null);

  // ── Persist ──────────────────────────────────────────────────────────
  useEffect(() => {
    saveIssues(issues);
  }, [issues]);

  // ── Handlers ──────────────────────────────────────────────────────────
  const openCreate = useCallback(() => {
    setEditingIssue(null);
    setForm(EMPTY_FORM);
    setDialogOpen(true);
  }, []);

  const openEdit = useCallback((issue: Issue) => {
    setEditingIssue(issue);
    setForm({
      title: issue.title,
      description: issue.description,
      status: issue.status,
      priority: issue.priority,
      labels: [...issue.labels],
      dueDate: issue.dueDate,
    });
    setDialogOpen(true);
  }, []);

  const saveForm = useCallback(() => {
    if (!form.title.trim()) return;

    const now = new Date().toISOString();
    if (editingIssue) {
      setIssues((prev) =>
        prev.map((i) =>
          i.id === editingIssue.id
            ? { ...i, ...form, title: form.title.trim(), updatedAt: now }
            : i,
        ),
      );
    } else {
      const newIssue: Issue = {
        id: uid(),
        ...form,
        title: form.title.trim(),
        createdAt: now,
        updatedAt: now,
      };
      setIssues((prev) => [newIssue, ...prev]);
    }
    setDialogOpen(false);
    setEditingIssue(null);
    setForm(EMPTY_FORM);
  }, [editingIssue, form]);

  const deleteIssue = useCallback((id: string) => {
    setIssues((prev) => prev.filter((i) => i.id !== id));
    setDeleteTarget(null);
  }, []);

  const quickStatusChange = useCallback((id: string, status: IssueStatus) => {
    setIssues((prev) =>
      prev.map((i) =>
        i.id === id ? { ...i, status, updatedAt: new Date().toISOString() } : i,
      ),
    );
  }, []);

  // ── Label helpers ─────────────────────────────────────────────────────
  const addLabel = useCallback(
    (label: string) => {
      const tag = label.trim().toLowerCase();
      if (tag && !form.labels.includes(tag)) {
        setForm((f) => ({ ...f, labels: [...f.labels, tag] }));
      }
      setLabelInput("");
    },
    [form.labels],
  );

  const removeLabel = useCallback((tag: string) => {
    setForm((f) => ({ ...f, labels: f.labels.filter((l) => l !== tag) }));
  }, []);

  // ── Filtered / sorted ─────────────────────────────────────────────────
  const allLabels = useMemo(() => {
    const set = new Set<string>();
    issues.forEach((i) => i.labels.forEach((l) => set.add(l)));
    return Array.from(set).sort();
  }, [issues]);

  const [labelFilter, setLabelFilter] = useState<string>("all");

  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    const priorityOrder: Record<IssuePriority, number> = { critical: 0, high: 1, medium: 2, low: 3 };
    return issues
      .filter((i) => statusFilter === "all" || i.status === statusFilter)
      .filter((i) => priorityFilter === "all" || i.priority === priorityFilter)
      .filter((i) => labelFilter === "all" || i.labels.includes(labelFilter))
      .filter(
        (i) =>
          !q ||
          i.title.toLowerCase().includes(q) ||
          i.description.toLowerCase().includes(q) ||
          i.labels.some((l) => l.toLowerCase().includes(q)),
      )
      .sort((a, b) => {
        if (sortKey === "priority") return priorityOrder[a.priority] - priorityOrder[b.priority];
        if (sortKey === "dueDate") {
          if (!a.dueDate && !b.dueDate) return 0;
          if (!a.dueDate) return 1;
          if (!b.dueDate) return -1;
          return a.dueDate.localeCompare(b.dueDate);
        }
        return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
      });
  }, [issues, statusFilter, priorityFilter, labelFilter, search, sortKey]);

  const counts = useMemo(
    () => ({
      all: issues.length,
      open: issues.filter((i) => i.status === "open").length,
      in_progress: issues.filter((i) => i.status === "in_progress").length,
      done: issues.filter((i) => i.status === "done").length,
      cancelled: issues.filter((i) => i.status === "cancelled").length,
    }),
    [issues],
  );

  // ── Render ────────────────────────────────────────────────────────────
  return (
    <div className="page-stack">
      <PageHeader
        title="Issues"
        description="Track tasks and work items."
        action={
          <Button size="sm" onClick={openCreate}>
            <Plus className="size-4" /> New issue
          </Button>
        }
      />

      {/* ── Filters bar ─────────────────────────────────────────────────── */}
      <div className="flex flex-wrap items-center gap-3">
        <Tabs
          value={statusFilter}
          onValueChange={(v) => setStatusFilter(v as IssueStatus | "all")}
        >
          <TabsList>
            <TabsTrigger value="all">All ({counts.all})</TabsTrigger>
            <TabsTrigger value="open">Open ({counts.open})</TabsTrigger>
            <TabsTrigger value="in_progress">Active ({counts.in_progress})</TabsTrigger>
            <TabsTrigger value="done">Done ({counts.done})</TabsTrigger>
          </TabsList>
        </Tabs>

        {/* Priority filter */}
        <Select
          value={priorityFilter}
          onValueChange={(v) => setPriorityFilter(v as IssuePriority | "all")}
        >
          <SelectTrigger size="sm" className="w-[130px]">
            <SelectValue placeholder="Priority" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All priorities</SelectItem>
            {PRIORITY_OPTIONS.map((p) => (
              <SelectItem key={p.value} value={p.value}>
                {p.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        {/* Label filter */}
        {allLabels.length > 0 && (
          <Select
            value={labelFilter}
            onValueChange={(v) => setLabelFilter(v)}
          >
            <SelectTrigger size="sm" className="w-[130px]">
              <SelectValue placeholder="Label" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All labels</SelectItem>
              {allLabels.map((l) => (
                <SelectItem key={l} value={l}>
                  {l}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}

        {/* Sort */}
        <Select
          value={sortKey}
          onValueChange={(v) => setSortKey(v as "updatedAt" | "priority" | "dueDate")}
        >
          <SelectTrigger size="sm" className="w-[140px]">
            <ArrowDownUp className="size-3.5" />
            <SelectValue placeholder="Sort" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="updatedAt">Last updated</SelectItem>
            <SelectItem value="priority">Priority</SelectItem>
            <SelectItem value="dueDate">Due date</SelectItem>
          </SelectContent>
        </Select>

        {/* Search */}
        <div className="relative ml-auto">
          <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search issues…"
            className="w-48 pl-8"
          />
        </div>
      </div>

      {/* ── Empty state ─────────────────────────────────────────────────── */}
      {filtered.length === 0 && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <ListTodo className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            {issues.length === 0 ? "No issues yet. Create one to get started." : "No issues match your filters."}
          </p>
        </div>
      )}

      {/* ── Issue list ──────────────────────────────────────────────────── */}
      <div className="grid gap-3">
        {filtered.map((issue) => (
          <Card key={issue.id} className="group transition-colors hover:bg-accent/50">
            <CardHeader className="pb-2">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <CircleDot className={`size-3.5 shrink-0 ${STATUS_ICON_COLORS[issue.status]}`} />
                    <CardTitle className="text-sm font-medium">{issue.title}</CardTitle>
                  </div>
                  {issue.description && (
                    <CardDescription className="mt-1 line-clamp-2">{issue.description}</CardDescription>
                  )}
                </div>
                <div className="flex items-center gap-1.5">
                  <Badge
                    variant="outline"
                    className={`text-[0.6rem] uppercase tracking-wider ${PRIORITY_COLORS[issue.priority]}`}
                  >
                    {issue.priority}
                  </Badge>
                  {/* Actions */}
                  <Button
                    variant="ghost"
                    size="icon"
                    className="size-7 opacity-0 group-hover:opacity-100 transition-opacity"
                    onClick={() => openEdit(issue)}
                  >
                    <Pencil className="size-3.5" />
                  </Button>
                  <AlertDialog>
                    <AlertDialogTrigger asChild>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="size-7 opacity-0 group-hover:opacity-100 transition-opacity text-destructive hover:text-destructive"
                        onClick={() => setDeleteTarget(issue)}
                      >
                        <Trash2 className="size-3.5" />
                      </Button>
                    </AlertDialogTrigger>
                    <AlertDialogContent>
                      <AlertDialogHeader>
                        <AlertDialogTitle>Delete issue?</AlertDialogTitle>
                        <AlertDialogDescription>
                          This will permanently delete &ldquo;{deleteTarget?.title}&rdquo;. This action cannot be undone.
                        </AlertDialogDescription>
                      </AlertDialogHeader>
                      <AlertDialogFooter>
                        <AlertDialogCancel onClick={() => setDeleteTarget(null)}>Cancel</AlertDialogCancel>
                        <AlertDialogAction
                          className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
                          onClick={() => deleteTarget && deleteIssue(deleteTarget.id)}
                        >
                          Delete
                        </AlertDialogAction>
                      </AlertDialogFooter>
                    </AlertDialogContent>
                  </AlertDialog>
                </div>
              </div>
            </CardHeader>
            <CardContent className="pt-2">
              <div className="flex flex-wrap items-center gap-2 text-[0.65rem] text-muted-foreground">
                {/* Quick status toggle */}
                <Select
                  value={issue.status}
                  onValueChange={(v) => quickStatusChange(issue.id, v as IssueStatus)}
                >
                  <SelectTrigger
                    size="sm"
                    className="h-6 gap-1 border-0 bg-transparent px-1.5 text-[0.6rem] uppercase tracking-wider shadow-none hover:bg-accent"
                  >
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {STATUS_OPTIONS.map((s) => (
                      <SelectItem key={s.value} value={s.value}>
                        {s.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                {/* Labels */}
                {issue.labels.map((label) => (
                  <Badge key={label} variant="secondary" className="text-[0.6rem]">
                    <Tag className="mr-1 size-2.5" />
                    {label}
                  </Badge>
                ))}

                {/* Due date */}
                {issue.dueDate && (
                  <span
                    className={`inline-flex items-center gap-1 ${
                      isOverdue(issue.dueDate) && issue.status !== "done" && issue.status !== "cancelled"
                        ? "text-red-500"
                        : ""
                    }`}
                  >
                    <Calendar className="size-3" />
                    {isOverdue(issue.dueDate) && issue.status !== "done" && issue.status !== "cancelled" && (
                      <AlertCircle className="size-3" />
                    )}
                    {formatDate(issue.dueDate)}
                  </span>
                )}

                <span className="ml-auto">{formatDate(issue.updatedAt)}</span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* ── Create / Edit Dialog ────────────────────────────────────────── */}
      <Dialog open={dialogOpen} onOpenChange={(open) => { if (!open) setDialogOpen(false); }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editingIssue ? "Edit issue" : "New issue"}</DialogTitle>
            <DialogDescription>
              {editingIssue ? "Update the details of this issue." : "Create a new task or issue to track."}
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-4 py-2">
            {/* Title */}
            <div className="grid gap-1.5">
              <Label htmlFor="issue-title">Title</Label>
              <Input
                id="issue-title"
                value={form.title}
                onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
                placeholder="What needs to be done?"
                autoFocus
              />
            </div>

            {/* Description */}
            <div className="grid gap-1.5">
              <Label htmlFor="issue-desc">Description</Label>
              <Textarea
                id="issue-desc"
                value={form.description}
                onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
                placeholder="Details, context, acceptance criteria…"
                rows={3}
              />
            </div>

            {/* Status + Priority row */}
            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-1.5">
                <Label>Status</Label>
                <Select
                  value={form.status}
                  onValueChange={(v) => setForm((f) => ({ ...f, status: v as IssueStatus }))}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {STATUS_OPTIONS.map((s) => (
                      <SelectItem key={s.value} value={s.value}>
                        {s.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-1.5">
                <Label>Priority</Label>
                <Select
                  value={form.priority}
                  onValueChange={(v) => setForm((f) => ({ ...f, priority: v as IssuePriority }))}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {PRIORITY_OPTIONS.map((p) => (
                      <SelectItem key={p.value} value={p.value}>
                        {p.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            {/* Due date */}
            <div className="grid gap-1.5">
              <Label htmlFor="issue-due">Due date</Label>
              <Input
                id="issue-due"
                type="date"
                value={form.dueDate}
                onChange={(e) => setForm((f) => ({ ...f, dueDate: e.target.value }))}
              />
            </div>

            {/* Labels */}
            <div className="grid gap-1.5">
              <Label>Labels</Label>
              <div className="flex flex-wrap gap-1.5">
                {form.labels.map((tag) => (
                  <Badge key={tag} variant="secondary" className="gap-1 pr-1">
                    {tag}
                    <button
                      type="button"
                      className="ml-0.5 rounded-full hover:bg-accent p-0.5"
                      onClick={() => removeLabel(tag)}
                    >
                      <X className="size-3" />
                    </button>
                  </Badge>
                ))}
              </div>
              <div className="flex gap-2">
                <Input
                  value={labelInput}
                  onChange={(e) => setLabelInput(e.target.value)}
                  placeholder="Add a label…"
                  className="flex-1"
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      addLabel(labelInput);
                    }
                  }}
                />
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => addLabel(labelInput)}
                  disabled={!labelInput.trim()}
                >
                  Add
                </Button>
              </div>
              {/* Preset labels */}
              <div className="flex flex-wrap gap-1.5">
                {PRESET_LABELS.filter((l) => !form.labels.includes(l)).map((l) => (
                  <button
                    key={l}
                    type="button"
                    className="rounded-md border border-border/50 px-2 py-0.5 text-[0.6rem] text-muted-foreground hover:bg-accent transition-colors"
                    onClick={() => addLabel(l)}
                  >
                    +{l}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              Cancel
            </Button>
            <Button onClick={saveForm} disabled={!form.title.trim()}>
              {editingIssue ? "Save changes" : "Create issue"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  FileCode2,
  FlaskConical,
  LoaderCircle,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Trash2,
  Wrench,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";
import type { SkillUsageEntry } from "@/shared/ares-api";
import { useNavigate } from "react-router-dom";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SkillListResponse {
  skills: SkillUsageEntry[];
  skill_runtime_available?: boolean;
  message?: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function matchesSearch(skill: SkillUsageEntry, query: string): boolean {
  if (!query) return true;
  const q = query.toLowerCase();
  return (
    skill.name.toLowerCase().includes(q) ||
    skill.description.toLowerCase().includes(q) ||
    skill.category.toLowerCase().includes(q)
  );
}

function categoryIcon(category: string): string {
  const icons: Record<string, string> = {
    coding: "💻",
    research: "🔬",
    productivity: "📊",
    creative: "🎨",
    devops: "🔧",
    "data-science": "📈",
    mlops: "🤖",
    "smart-home": "🏠",
    "social-media": "💬",
    media: "🎵",
    email: "📧",
    github: "🐙",
  };
  return icons[category] || "⚡";
}

// ---------------------------------------------------------------------------
// Skill Detail Drawer
// ---------------------------------------------------------------------------

function SkillDetailDrawer({
  skill,
  open,
  onOpenChange,
  onEdit,
  onDelete,
  onToggle,
  toggling,
}: {
  skill: SkillUsageEntry | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onEdit: (skill: SkillUsageEntry) => void;
  onDelete: (skill: SkillUsageEntry) => void;
  onToggle: (name: string, currentlyDisabled: boolean) => void;
  toggling: string | null;
}) {
  const [content, setContent] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !skill) {
      setContent(null);
      return;
    }
    let active = true;
    setLoading(true);
    setError(null);
    aresApi
      .skillsGet(skill.name)
      .then((data) => {
        if (active) setContent(data.content);
      })
      .catch((err) => {
        if (active) setError(readableError(err, "Failed to load skill content."));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [open, skill]);

  if (!skill) return null;

  const enabled = !skill.disabled;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <span>{categoryIcon(skill.category)}</span>
            {skill.name}
          </SheetTitle>
          <SheetDescription>
            {skill.description || "No description available."}
          </SheetDescription>
        </SheetHeader>

        <div className="grid gap-4 px-4 pb-6">
          {/* Metadata */}
          <div className="grid gap-3">
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">Category</span>
              <Badge variant="outline">{skill.category || "uncategorized"}</Badge>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">Status</span>
              <div className="flex items-center gap-2">
                <Badge
                  variant="outline"
                  className={
                    enabled
                      ? "text-emerald-700 dark:text-emerald-300"
                      : "text-amber-700 dark:text-amber-300"
                  }
                >
                  <span
                    className={`mr-1.5 inline-block size-1.5 rounded-full ${
                      enabled ? "bg-emerald-500" : "bg-amber-500"
                    }`}
                  />
                  {enabled ? "Enabled" : "Disabled"}
                </Badge>
                {toggling === skill.name ? (
                  <LoaderCircle className="size-4 animate-spin text-muted-foreground" />
                ) : (
                  <ToggleSwitch
                    checked={enabled}
                    onCheckedChange={() => onToggle(skill.name, skill.disabled)}
                    aria-label={enabled ? `Disable ${skill.name}` : `Enable ${skill.name}`}
                  />
                )}
              </div>
            </div>
            {skill.usage_count !== undefined && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Usage count</span>
                <span className="text-sm font-medium">{skill.usage_count}</span>
              </div>
            )}
            {skill.last_used && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Last used</span>
                <span className="text-sm text-muted-foreground">
                  {new Date(skill.last_used).toLocaleDateString()}
                </span>
              </div>
            )}
          </div>

          {/* Actions */}
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              className="flex-1"
              onClick={() => onEdit(skill)}
            >
              <Pencil className="size-3.5" />
              Edit YAML
            </Button>
            <Button
              variant="outline"
              size="sm"
              className="text-destructive hover:text-destructive"
              onClick={() => onDelete(skill)}
            >
              <Trash2 className="size-3.5" />
              Delete
            </Button>
          </div>

          {/* Content */}
          <div className="grid gap-2">
            <span className="text-sm font-medium text-foreground">Skill Definition</span>
            {loading ? (
              <div className="flex items-center justify-center py-8">
                <LoaderCircle className="size-5 animate-spin text-muted-foreground/40" />
              </div>
            ) : error ? (
              <div className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                {error}
              </div>
            ) : content ? (
              <pre className="overflow-x-auto rounded-md border bg-muted/50 p-3 text-xs font-mono leading-relaxed text-foreground whitespace-pre-wrap break-words">
                {content}
              </pre>
            ) : (
              <p className="text-sm text-muted-foreground">No content available.</p>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}

// ---------------------------------------------------------------------------
// Delete confirmation dialog
// ---------------------------------------------------------------------------

function DeleteSkillDialog({
  skill,
  open,
  onOpenChange,
  onDeleted,
}: {
  skill: SkillUsageEntry | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onDeleted: () => void;
}) {
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleDelete() {
    if (!skill) return;
    setDeleting(true);
    setError(null);
    try {
      await aresApi.skillsDelete(skill.name);
      onOpenChange(false);
      onDeleted();
    } catch (err) {
      setError(readableError(err, "Failed to delete skill."));
    } finally {
      setDeleting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Delete Skill</DialogTitle>
          <DialogDescription>
            Are you sure you want to delete <strong>{skill?.name}</strong>? This action cannot be undone.
          </DialogDescription>
        </DialogHeader>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button variant="destructive" disabled={deleting} onClick={() => void handleDelete()}>
            {deleting && <LoaderCircle className="mr-2 size-4 animate-spin" />}
            Delete
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export default function SkillsPage() {
  const [skills, setSkills] = useState<SkillUsageEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<string>("all");
  const [togglingName, setTogglingName] = useState<string | null>(null);
  const [selectedSkill, setSelectedSkill] = useState<SkillUsageEntry | null>(null);
  const [detailOpen, setDetailOpen] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<SkillUsageEntry | null>(null);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const navigate = useNavigate();

  // ---- Fetch skills on mount ----

  const loadSkills = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.skillsList();
      // skillsList returns Record<string, unknown>[] — normalize to SkillUsageEntry[]
      const list: SkillUsageEntry[] = (data as unknown as SkillUsageEntry[]).map((s) => ({
        name: String(s.name ?? ""),
        description: String(s.description ?? ""),
        category: String(s.category ?? ""),
        disabled: Boolean(s.disabled),
        usage_count: s.usage_count,
        last_used: s.last_used,
      }));
      setSkills(list);
    } catch (err) {
      setSkills([]);
      setError(readableError(err, "Failed to load skills."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadSkills();
  }, [loadSkills]);

  // ---- Toggle handler ----

  const handleToggle = useCallback(
    async (name: string, currentlyDisabled: boolean) => {
      const enabled = !currentlyDisabled;
      setTogglingName(name);
      // Optimistic update
      setSkills((prev) =>
        prev.map((s) => (s.name === name ? { ...s, disabled: !enabled } : s)),
      );
      try {
        await aresApi.skillsToggle(name, enabled);
      } catch {
        // Revert on failure
        setSkills((prev) =>
          prev.map((s) => (s.name === name ? { ...s, disabled: currentlyDisabled } : s)),
        );
      }
      setTogglingName(null);
    },
    [],
  );

  // ---- Derived state ----

  const categories = useMemo(() => {
    const cats = new Set(skills.map((s) => s.category || "uncategorized"));
    return ["all", ...Array.from(cats).sort()];
  }, [skills]);

  const filtered = useMemo(() => {
    let list = skills.filter((s) => matchesSearch(s, search));
    if (categoryFilter !== "all") {
      list = list.filter((s) => (s.category || "uncategorized") === categoryFilter);
    }
    return list;
  }, [skills, search, categoryFilter]);

  const enabledSkills = useMemo(() => filtered.filter((s) => !s.disabled), [filtered]);
  const disabledSkills = useMemo(() => filtered.filter((s) => s.disabled), [filtered]);
  const enabledCount = skills.filter((s) => !s.disabled).length;

  // ---- Skill click → open detail ----

  function handleSkillClick(skill: SkillUsageEntry) {
    setSelectedSkill(skill);
    setDetailOpen(true);
  }

  function handleEdit(skill: SkillUsageEntry) {
    setDetailOpen(false);
    navigate(`/skills/studio?name=${encodeURIComponent(skill.name)}`);
  }

  function handleDelete(skill: SkillUsageEntry) {
    setDetailOpen(false);
    setDeleteTarget(skill);
    setDeleteOpen(true);
  }

  // ---- Render ----

  return (
    <div className="page-stack">
      <PageHeader
        title="Skills"
        description="Manage installed skills. Enable or disable skills to control what capabilities are available."
        action={
          <Button size="sm" onClick={() => navigate("/skills/studio")}>
            <Plus className="size-4" />
            New Skill
          </Button>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <span className="inline-flex items-center gap-2">
            <AlertCircle className="size-4" />
            {error}
          </span>
          <Button
            variant="outline"
            size="xs"
            className="ml-3"
            onClick={() => void loadSkills()}
          >
            <RefreshCw className="size-3" />
            Retry
          </Button>
        </div>
      )}

      {/* Stats + search row */}
      <div className="flex flex-wrap items-center gap-3">
        <span className="text-sm font-medium text-foreground">
          {enabledCount} of {skills.length} enabled
        </span>
        {skills.length > 0 && (
          <span className="inline-flex items-center gap-1.5 text-xs text-(--status-task-done)">
            <CheckCircle2 className="size-3.5" />
            Saved
          </span>
        )}
        <div className="ml-auto w-full sm:w-auto">
          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search skills…"
              className="h-8 w-full pl-8 sm:w-56"
              aria-label="Search skills"
            />
          </div>
        </div>
      </div>

      {/* Category filter pills */}
      {categories.length > 2 && (
        <div className="flex flex-wrap gap-1.5">
          {categories.map((cat) => (
            <Button
              key={cat}
              variant={categoryFilter === cat ? "default" : "outline"}
              size="xs"
              onClick={() => setCategoryFilter(cat)}
            >
              {cat === "all" ? "All" : cat}
            </Button>
          ))}
        </div>
      )}

      {/* Loading state */}
      {loading ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading skills…</p>
        </div>
      ) : skills.length === 0 ? (
        /* Empty state */
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <FlaskConical className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            No skills found. Skills are discovered from your ARES skills directory.
          </p>
          <Button variant="outline" size="sm" className="mt-4" onClick={() => navigate("/skills/studio")}>
            <Plus className="size-4" />
            Create a Skill
          </Button>
        </div>
      ) : filtered.length === 0 ? (
        <div className="py-8 text-center">
          <p className="text-sm text-muted-foreground">No skills match your search.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {/* Enabled section */}
          {enabledSkills.length > 0 && (
            <SkillSection title="Enabled" count={enabledSkills.length}>
              {enabledSkills.map((skill) => (
                <SkillCard
                  key={skill.name}
                  skill={skill}
                  toggling={togglingName === skill.name}
                  onToggle={() => handleToggle(skill.name, skill.disabled)}
                  onClick={() => handleSkillClick(skill)}
                />
              ))}
            </SkillSection>
          )}

          {/* Disabled section */}
          {disabledSkills.length > 0 && (
            <SkillSection title="Disabled" count={disabledSkills.length}>
              {disabledSkills.map((skill) => (
                <SkillCard
                  key={skill.name}
                  skill={skill}
                  toggling={togglingName === skill.name}
                  onToggle={() => handleToggle(skill.name, skill.disabled)}
                  onClick={() => handleSkillClick(skill)}
                />
              ))}
            </SkillSection>
          )}
        </div>
      )}

      {/* Detail drawer */}
      <SkillDetailDrawer
        skill={selectedSkill}
        open={detailOpen}
        onOpenChange={setDetailOpen}
        onEdit={handleEdit}
        onDelete={handleDelete}
        onToggle={handleToggle}
        toggling={togglingName}
      />

      {/* Delete confirmation */}
      <DeleteSkillDialog
        skill={deleteTarget}
        open={deleteOpen}
        onOpenChange={setDeleteOpen}
        onDeleted={() => void loadSkills()}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function SkillSection({
  title,
  count,
  children,
}: {
  title: string;
  count: number;
  children: React.ReactNode;
}) {
  return (
    <section className="overflow-hidden rounded-lg border border-border">
      <div className="flex items-center gap-2 bg-muted/50 px-3 py-2">
        <span className="text-xs font-medium text-muted-foreground">{title}</span>
        <span className="text-xs text-muted-foreground/70">{count}</span>
      </div>
      <div>{children}</div>
    </section>
  );
}

function SkillCard({
  skill,
  toggling,
  onToggle,
  onClick,
}: {
  skill: SkillUsageEntry;
  toggling: boolean;
  onToggle: () => void;
  onClick: () => void;
}) {
  const enabled = !skill.disabled;

  return (
    <div
      className="flex min-h-11 cursor-pointer items-center gap-3 border-b border-border px-3 py-2.5 last:border-b-0 transition-colors hover:bg-accent/50"
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick();
        }
      }}
    >
      <div className="grid size-8 shrink-0 place-items-center rounded-md bg-muted">
        <Wrench className="size-4 text-muted-foreground" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-medium text-foreground">
            {skill.name}
          </span>
          {skill.category ? (
            <Badge variant="outline" className="hidden shrink-0 sm:inline-flex">
              {skill.category}
            </Badge>
          ) : null}
          {skill.usage_count !== undefined && skill.usage_count > 0 && (
            <Badge variant="secondary" className="hidden shrink-0 sm:inline-flex text-[10px]">
              {skill.usage_count} uses
            </Badge>
          )}
        </div>
        {skill.description ? (
          <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">
            {skill.description}
          </p>
        ) : null}
      </div>
      <div
        className="shrink-0"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => e.stopPropagation()}
      >
        {toggling ? (
          <LoaderCircle className="size-4 animate-spin text-muted-foreground" />
        ) : (
          <ToggleSwitch
            checked={enabled}
            onCheckedChange={onToggle}
            aria-label={enabled ? `Disable ${skill.name}` : `Enable ${skill.name}`}
          />
        )}
      </div>
    </div>
  );
}
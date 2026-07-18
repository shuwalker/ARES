import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  FlaskConical,
  LoaderCircle,
  Search,
  Wrench,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { useAres } from "@/shared/ares-context";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface SkillEntry {
  name: string;
  description: string;
  category: string;
  disabled: boolean;
}

interface SkillsResponse {
  skills: SkillEntry[];
  skill_runtime_available: boolean;
  message?: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function matchesSearch(skill: SkillEntry, query: string): boolean {
  if (!query) return true;
  const q = query.toLowerCase();
  return (
    skill.name.toLowerCase().includes(q) ||
    skill.description.toLowerCase().includes(q) ||
    skill.category.toLowerCase().includes(q)
  );
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function SkillStudioPage() {
  const { snapshot } = useAres();
  const [skills, setSkills] = useState<SkillEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [togglingName, setTogglingName] = useState<string | null>(null);
  const [runtimeAvailable, setRuntimeAvailable] = useState(true);

  // ---- Fetch skills on mount ----

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    fetch("/api/skills")
      .then((r) => {
        if (!r.ok) throw new Error(`Request failed (${r.status})`);
        return r.json() as Promise<SkillsResponse>;
      })
      .then((data) => {
        if (!active) return;
        setSkills(data.skills ?? []);
        setRuntimeAvailable(data.skill_runtime_available !== false);
        if (data.message && !data.skill_runtime_available) {
          setError(data.message);
        }
      })
      .catch((err) => {
        if (!active) return;
        setSkills([]);
        setError(err instanceof Error ? err.message : "Failed to load skills");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  // ---- Toggle handler ----

  const handleToggle = useCallback(async (name: string, currentlyDisabled: boolean) => {
    const enabled = !currentlyDisabled;
    setTogglingName(name);
    // Optimistic update
    setSkills((prev) =>
      prev.map((s) => (s.name === name ? { ...s, disabled: !enabled } : s)),
    );
    try {
      const res = await fetch("/api/skills/toggle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, enabled }),
      });
      if (!res.ok) {
        // Revert on failure
        setSkills((prev) =>
          prev.map((s) => (s.name === name ? { ...s, disabled: currentlyDisabled } : s)),
        );
      }
    } catch {
      // Revert on network error
      setSkills((prev) =>
        prev.map((s) => (s.name === name ? { ...s, disabled: currentlyDisabled } : s)),
      );
    }
    setTogglingName(null);
  }, []);

  // ---- Derived state ----

  const filtered = useMemo(
    () => skills.filter((s) => matchesSearch(s, search)),
    [skills, search],
  );

  const enabledSkills = useMemo(
    () => filtered.filter((s) => !s.disabled),
    [filtered],
  );

  const disabledSkills = useMemo(
    () => filtered.filter((s) => s.disabled),
    [filtered],
  );

  const enabledCount = skills.filter((s) => !s.disabled).length;
  const connected = snapshot.connection !== "unavailable";

  // ---- Render ----

  return (
    <div className="page-stack">
      <PageHeader
        title="Skill Studio"
        description="Manage installed skills and plugins. Enable or disable skills to control what capabilities are available."
      />

      {error && !runtimeAvailable ? (
        <div className="rounded-md border border-status-limited/40 bg-status-limited/10 px-4 py-3 text-sm text-status-limited">
          <span className="inline-flex items-center gap-2">
            <AlertCircle className="size-4" />
            {error}
          </span>
        </div>
      ) : null}

      {/* Stats + search row */}
      <div className="flex flex-wrap items-center gap-3">
        <span className="text-sm font-medium text-foreground">
          {enabledCount} of {skills.length} enabled
        </span>
        {connected && runtimeAvailable && (
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
                />
              ))}
            </SkillSection>
          )}
        </div>
      )}
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
}: {
  skill: SkillEntry;
  toggling: boolean;
  onToggle: () => void;
}) {
  const enabled = !skill.disabled;

  return (
    <div className="flex min-h-11 items-center gap-3 border-b border-border px-3 py-2.5 last:border-b-0 transition-colors hover:bg-accent/50">
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
        </div>
        {skill.description ? (
          <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">
            {skill.description}
          </p>
        ) : null}
      </div>
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
  );
}
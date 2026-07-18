import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ArrowDown,
  ArrowUp,
  CheckSquare,
  Eye,
  EyeOff,
  KeyRound,
  ListOrdered,
  Pencil,
  Plus,
  RefreshCw,
  Save,
  Square,
  Trash2,
  X,
} from "lucide-react";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Checkbox } from "@/components/ui/checkbox";

// ── Types ─────────────────────────────────────────────────────────────

interface EnvVar {
  key: string;
  value: string;
  scope: string;
  revealed: boolean;
}

// ── Helpers ───────────────────────────────────────────────────────────

const SCOPE_COLORS: Record<string, string> = {
  global: "bg-blue-500/15 text-blue-600 dark:text-blue-400 border-blue-500/25",
  profile: "bg-purple-500/15 text-purple-600 dark:text-purple-400 border-purple-500/25",
  session: "bg-amber-500/15 text-amber-600 dark:text-amber-400 border-amber-500/25",
};

const SCOPE_LABELS: Record<string, string> = {
  global: "Global",
  profile: "Profile",
  session: "Session",
};

function scopeBadge(scope: string) {
  const colour = SCOPE_COLORS[scope] ?? "bg-muted text-muted-foreground border-border";
  const label = SCOPE_LABELS[scope] ?? scope;
  return { colour, label };
}

function masked(value: string) {
  if (!value) return "—";
  return "•".repeat(Math.min(value.length, 12));
}

function deriveScope(key: string): string {
  const upper = key.toUpperCase();
  if (upper.startsWith("ARES_") || upper === "PATH" || upper === "HOME" || upper === "LANG") return "global";
  if (upper.includes("_PROFILE_") || upper.startsWith("PROFILE_")) return "profile";
  return "session";
}

// ── Sub-components ────────────────────────────────────────────────────

function ScopeBadge({ scope }: { scope: string }) {
  const { colour, label } = scopeBadge(scope);
  return (
    <Badge variant="outline" className={`font-mono text-[10px] uppercase tracking-wider ${colour}`}>
      {label}
    </Badge>
  );
}

// ── Page ──────────────────────────────────────────────────────────────

export default function EnvPage() {
  // ── State ───────────────────────────────────────────────────────────
  const [vars, setVars] = useState<EnvVar[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Inline edit
  const [editKey, setEditKey] = useState<string | null>(null);
  const [editValue, setEditValue] = useState("");
  const [saving, setSaving] = useState(false);

  // Add dialog
  const [addOpen, setAddOpen] = useState(false);
  const [addKey, setAddKey] = useState("");
  const [addValue, setAddValue] = useState("");
  const [addScope, setAddScope] = useState("session");

  // Delete confirm
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);

  // Bulk edit
  const [bulkMode, setBulkMode] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkValue, setBulkValue] = useState("");
  const [bulkSaving, setBulkSaving] = useState(false);

  // Reorder
  const [reorderMode, setReorderMode] = useState(false);

  // ── Load ─────────────────────────────────────────────────────────────
  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // Try the new scoped env API first; fall back to secrets endpoint
      let items: EnvVar[] = [];
      try {
        const data = await aresApi.envList();
        const order: string[] = Array.isArray(data.order) ? data.order : [];
        const variables: Record<string, string> = data.variables ?? {};
        // Build ordered list, then append any remaining keys not in order
        const seen = new Set<string>();
        for (const key of order) {
          if (key && !seen.has(key)) {
            seen.add(key);
            items.push({ key, value: variables[key] ?? "", scope: deriveScope(key), revealed: false });
          }
        }
        for (const key of Object.keys(variables)) {
          if (!seen.has(key)) {
            items.push({ key, value: variables[key] ?? "", scope: deriveScope(key), revealed: false });
          }
        }
      } catch {
        // Fallback: use secrets endpoint
        const secrets = await aresApi.secrets();
        items = secrets
          .filter((s) => s.key)
          .map((s) => ({ key: s.key, value: s.value ?? s.value_preview ?? "", scope: deriveScope(s.key), revealed: false }));
      }
      setVars(items);
    } catch (e) {
      setError(readableError(e, "Failed to load environment variables."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // ── Scoped vars (grouped) ───────────────────────────────────────────
  const grouped = useMemo(() => {
    const groups: Record<string, EnvVar[]> = {};
    for (const v of vars) {
      const s = v.scope;
      if (!groups[s]) groups[s] = [];
      groups[s].push(v);
    }
    return groups;
  }, [vars]);

  const scopeOrder = ["global", "profile", "session"];

  // ── Handlers ────────────────────────────────────────────────────────
  const handleSave = async (key: string, value: string) => {
    setSaving(true);
    try {
      await aresApi.envSet(key, value);
      setEditKey(null);
      setEditValue("");
      load();
    } catch (e) {
      alert(readableError(e, "Failed to save"));
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      await aresApi.envDelete(deleteTarget);
      setDeleteTarget(null);
      load();
    } catch (e) {
      alert(readableError(e, "Failed to delete"));
    }
  };

  const handleAdd = async () => {
    if (!addKey.trim()) return;
    setSaving(true);
    try {
      await aresApi.envSet(addKey.trim(), addValue);
      setAddKey("");
      setAddValue("");
      setAddOpen(false);
      load();
    } catch (e) {
      alert(readableError(e, "Failed to add"));
    } finally {
      setSaving(false);
    }
  };

  const handleReveal = async (key: string) => {
    // Toggle local reveal state; if revealing, try to fetch actual value from server
    setVars((prev) =>
      prev.map((v) => {
        if (v.key !== key) return v;
        if (v.revealed) {
          // Mask again
          return { ...v, revealed: false };
        }
        return { ...v, revealed: true };
      }),
    );

    // Fetch real value from backend
    try {
      const result = await aresApi.envReveal(key);
      setVars((prev) =>
        prev.map((v) => (v.key === key ? { ...v, value: result.value, revealed: true } : v)),
      );
    } catch {
      // If reveal endpoint fails, just show masked with local toggle
    }
  };

  const handleBulkSet = async () => {
    if (!bulkValue || selected.size === 0) return;
    setBulkSaving(true);
    try {
      await Promise.all(
        Array.from(selected).map((key) => aresApi.envSet(key, bulkValue)),
      );
      setSelected(new Set());
      setBulkValue("");
      setBulkMode(false);
      load();
    } catch (e) {
      alert(readableError(e, "Failed to bulk update"));
    } finally {
      setBulkSaving(false);
    }
  };

  const handleBulkDelete = async () => {
    if (selected.size === 0) return;
    try {
      await Promise.all(
        Array.from(selected).map((key) => aresApi.envDelete(key)),
      );
      setSelected(new Set());
      setBulkMode(false);
      load();
    } catch (e) {
      alert(readableError(e, "Failed to delete selected"));
    }
  };

  const handleMoveUp = async (index: number) => {
    if (index <= 0) return;
    const newVars = [...vars];
    [newVars[index - 1], newVars[index]] = [newVars[index], newVars[index - 1]];
    setVars(newVars);
    try {
      await aresApi.envReorder(newVars.map((v) => v.key));
    } catch (e) {
      alert(readableError(e, "Failed to reorder"));
      load();
    }
  };

  const handleMoveDown = async (index: number) => {
    if (index >= vars.length - 1) return;
    const newVars = [...vars];
    [newVars[index], newVars[index + 1]] = [newVars[index + 1], newVars[index]];
    setVars(newVars);
    try {
      await aresApi.envReorder(newVars.map((v) => v.key));
    } catch (e) {
      alert(readableError(e, "Failed to reorder"));
      load();
    }
  };

  const toggleSelected = (key: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const toggleAll = () => {
    if (selected.size === vars.length) {
      setSelected(new Set());
    } else {
      setSelected(new Set(vars.map((v) => v.key)));
    }
  };

  // ── Render ─────────────────────────────────────────────────────────
  if (loading) {
    return (
      <div className="page-stack">
        <PageHeader title="Environment" description="Manage environment variables and scoped secrets." />
        <div className="flex items-center justify-center py-12 text-muted-foreground">Loading…</div>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Environment"
        description="Manage environment variables and scoped secrets."
        action={
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => void load()} disabled={loading}>
              <RefreshCw className={`mr-1 h-3 w-3 ${loading ? "animate-spin" : ""}`} />
              Refresh
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => setReorderMode((v) => !v)}
              className={reorderMode ? "border-ring text-ring" : ""}
            >
              <ListOrdered className="mr-1 h-3 w-3" />
              {reorderMode ? "Done" : "Reorder"}
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setBulkMode((v) => !v);
                setSelected(new Set());
              }}
              className={bulkMode ? "border-ring text-ring" : ""}
            >
              {bulkMode ? <CheckSquare className="mr-1 h-3 w-3" /> : <Square className="mr-1 h-3 w-3" />}
              {bulkMode ? "Done" : "Bulk Edit"}
            </Button>
            <Button size="sm" onClick={() => setAddOpen(true)}>
              <Plus className="mr-1 h-3 w-3" />
              Add
            </Button>
          </div>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      {/* Bulk edit bar */}
      {bulkMode && (
        <Card>
          <CardContent className="flex items-center gap-3 py-3">
            <Checkbox
              checked={selected.size === vars.length && vars.length > 0}
              onCheckedChange={toggleAll}
            />
            <span className="text-sm text-muted-foreground">
              {selected.size} of {vars.length} selected
            </span>
            <div className="flex-1" />
            <Input
              className="h-8 max-w-64 font-mono text-xs"
              placeholder="New value for selected…"
              value={bulkValue}
              onChange={(e) => setBulkValue(e.target.value)}
              type="password"
            />
            <Button size="sm" onClick={() => void handleBulkSet()} disabled={bulkSaving || !bulkValue || selected.size === 0}>
              <Save className="mr-1 h-3 w-3" />
              {bulkSaving ? "Saving…" : "Set All"}
            </Button>
            <Button
              variant="outline"
              size="sm"
              className="text-destructive hover:text-destructive"
              onClick={() => void handleBulkDelete()}
              disabled={selected.size === 0}
            >
              <Trash2 className="mr-1 h-3 w-3" />
              Delete
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Grouped display */}
      {scopeOrder.map((scope) => {
        const group = grouped[scope];
        if (!group || group.length === 0) return null;
        return (
          <Card key={scope}>
            <CardHeader className="pb-2">
              <div className="flex items-center gap-2">
                <KeyRound className="h-4 w-4 text-muted-foreground" />
                <CardTitle className="text-sm">{SCOPE_LABELS[scope] ?? scope} Variables</CardTitle>
                <Badge variant="secondary" className="font-mono text-[10px]">
                  {group.length}
                </Badge>
              </div>
              <CardDescription className="text-xs">
                {scope === "global"
                  ? "System-wide variables available to all profiles and sessions."
                  : scope === "profile"
                    ? "Variables scoped to the current profile."
                    : "Variables scoped to the current session."}
              </CardDescription>
            </CardHeader>
            <CardContent className="grid gap-1.5">
              {group.map((v, i) => {
                const globalIndex = vars.indexOf(v);
                return (
                  <div
                    key={v.key}
                    className="flex items-center justify-between gap-2 rounded-md border border-border/50 px-3 py-2 transition-colors hover:border-border"
                  >
                    {/* Left: checkbox (bulk) + key + scope badge + value */}
                    <div className="flex min-w-0 flex-1 items-center gap-2">
                      {bulkMode && (
                        <Checkbox
                          checked={selected.has(v.key)}
                          onCheckedChange={() => toggleSelected(v.key)}
                        />
                      )}
                      <span className="shrink-0 font-mono text-xs font-medium">{v.key}</span>
                      <ScopeBadge scope={v.scope} />
                      <code className="min-w-0 truncate rounded bg-muted px-2 py-0.5 font-mono text-xs">
                        {v.revealed ? v.value : masked(v.value)}
                      </code>
                    </div>

                    {/* Right: actions */}
                    <div className="flex shrink-0 items-center gap-1">
                      {reorderMode && (
                        <>
                          <Button
                            variant="ghost"
                            size="icon-xs"
                            disabled={globalIndex === 0}
                            onClick={() => void handleMoveUp(globalIndex)}
                          >
                            <ArrowUp className="h-3 w-3" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon-xs"
                            disabled={globalIndex === vars.length - 1}
                            onClick={() => void handleMoveDown(globalIndex)}
                          >
                            <ArrowDown className="h-3 w-3" />
                          </Button>
                        </>
                      )}
                      {editKey === v.key ? (
                        <>
                          <Input
                            className="h-7 text-xs font-mono"
                            autoFocus
                            value={editValue}
                            onChange={(e) => setEditValue(e.target.value)}
                            placeholder="New value…"
                          />
                          <Button
                            size="xs"
                            onClick={() => void handleSave(v.key, editValue)}
                            disabled={saving || !editValue}
                          >
                            <Save className="mr-1 h-3 w-3" />
                            {saving ? "…" : "Save"}
                          </Button>
                          <Button
                            variant="outline"
                            size="icon-xs"
                            onClick={() => {
                              setEditKey(null);
                              setEditValue("");
                            }}
                          >
                            <X className="h-3 w-3" />
                          </Button>
                        </>
                      ) : (
                        <>
                          <Button
                            variant="ghost"
                            size="icon-xs"
                            onClick={() => void handleReveal(v.key)}
                            aria-label={v.revealed ? "Mask value" : "Reveal value"}
                          >
                            {v.revealed ? <EyeOff className="h-3 w-3" /> : <Eye className="h-3 w-3" />}
                          </Button>
                          <Button
                            variant="outline"
                            size="xs"
                            onClick={() => {
                              setEditKey(v.key);
                              setEditValue("");
                            }}
                          >
                            <Pencil className="mr-1 h-3 w-3" />
                            Edit
                          </Button>
                          {!bulkMode && (
                            <Button
                              variant="outline"
                              size="icon-xs"
                              className="text-destructive hover:text-destructive"
                              onClick={() => setDeleteTarget(v.key)}
                            >
                              <Trash2 className="h-3 w-3" />
                            </Button>
                          )}
                        </>
                      )}
                    </div>
                  </div>
                );
              })}
            </CardContent>
          </Card>
        );
      })}

      {/* Ungrouped / other scopes */}
      {Object.entries(grouped)
        .filter(([scope]) => !scopeOrder.includes(scope))
        .map(([scope, group]) => (
          <Card key={scope}>
            <CardHeader className="pb-2">
              <div className="flex items-center gap-2">
                <KeyRound className="h-4 w-4 text-muted-foreground" />
                <CardTitle className="text-sm">{SCOPE_LABELS[scope] ?? scope} Variables</CardTitle>
                <Badge variant="secondary" className="font-mono text-[10px]">
                  {group.length}
                </Badge>
              </div>
            </CardHeader>
            <CardContent className="grid gap-1.5">
              {group.map((v) => {
                const globalIndex = vars.indexOf(v);
                return (
                  <div
                    key={v.key}
                    className="flex items-center justify-between gap-2 rounded-md border border-border/50 px-3 py-2 transition-colors hover:border-border"
                  >
                    <div className="flex min-w-0 flex-1 items-center gap-2">
                      {bulkMode && (
                        <Checkbox
                          checked={selected.has(v.key)}
                          onCheckedChange={() => toggleSelected(v.key)}
                        />
                      )}
                      <span className="shrink-0 font-mono text-xs font-medium">{v.key}</span>
                      <ScopeBadge scope={v.scope} />
                      <code className="min-w-0 truncate rounded bg-muted px-2 py-0.5 font-mono text-xs">
                        {v.revealed ? v.value : masked(v.value)}
                      </code>
                    </div>
                    <div className="flex shrink-0 items-center gap-1">
                      {reorderMode && (
                        <>
                          <Button
                            variant="ghost"
                            size="icon-xs"
                            disabled={globalIndex === 0}
                            onClick={() => void handleMoveUp(globalIndex)}
                          >
                            <ArrowUp className="h-3 w-3" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon-xs"
                            disabled={globalIndex === vars.length - 1}
                            onClick={() => void handleMoveDown(globalIndex)}
                          >
                            <ArrowDown className="h-3 w-3" />
                          </Button>
                        </>
                      )}
                      {editKey === v.key ? (
                        <>
                          <Input
                            className="h-7 text-xs font-mono"
                            autoFocus
                            value={editValue}
                            onChange={(e) => setEditValue(e.target.value)}
                            placeholder="New value…"
                          />
                          <Button
                            size="xs"
                            onClick={() => void handleSave(v.key, editValue)}
                            disabled={saving || !editValue}
                          >
                            <Save className="mr-1 h-3 w-3" />
                            {saving ? "…" : "Save"}
                          </Button>
                          <Button
                            variant="outline"
                            size="icon-xs"
                            onClick={() => {
                              setEditKey(null);
                              setEditValue("");
                            }}
                          >
                            <X className="h-3 w-3" />
                          </Button>
                        </>
                      ) : (
                        <>
                          <Button
                            variant="ghost"
                            size="icon-xs"
                            onClick={() => void handleReveal(v.key)}
                          >
                            {v.revealed ? <EyeOff className="h-3 w-3" /> : <Eye className="h-3 w-3" />}
                          </Button>
                          <Button
                            variant="outline"
                            size="xs"
                            onClick={() => {
                              setEditKey(v.key);
                              setEditValue("");
                            }}
                          >
                            <Pencil className="mr-1 h-3 w-3" />
                            Edit
                          </Button>
                          {!bulkMode && (
                            <Button
                              variant="outline"
                              size="icon-xs"
                              className="text-destructive hover:text-destructive"
                              onClick={() => setDeleteTarget(v.key)}
                            >
                              <Trash2 className="h-3 w-3" />
                            </Button>
                          )}
                        </>
                      )}
                    </div>
                  </div>
                );
              })}
            </CardContent>
          </Card>
        ))}

      {/* Add dialog */}
      <Dialog open={addOpen} onOpenChange={setAddOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Add Variable</DialogTitle>
            <DialogDescription>
              Add a new environment variable. Choose a scope to control visibility.
            </DialogDescription>
          </DialogHeader>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void handleAdd();
            }}
            className="grid gap-4 py-2"
          >
            <div className="grid gap-2">
              <Label htmlFor="env-key">Key</Label>
              <Input
                id="env-key"
                className="font-mono"
                placeholder="MY_VARIABLE"
                value={addKey}
                onChange={(e) => setAddKey(e.target.value)}
                autoFocus
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="env-value">Value</Label>
              <Input
                id="env-value"
                type="password"
                className="font-mono"
                placeholder="Secret value…"
                value={addValue}
                onChange={(e) => setAddValue(e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label>Scope</Label>
              <div className="flex items-center gap-2">
                {(["session", "profile", "global"] as const).map((s) => (
                  <button
                    key={s}
                    type="button"
                    onClick={() => setAddScope(s)}
                    className={`rounded-md border px-3 py-1.5 text-xs font-medium transition-colors ${
                      addScope === s
                        ? "border-ring bg-ring/10 text-foreground"
                        : "border-border bg-background text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                    }`}
                  >
                    {SCOPE_LABELS[s]}
                  </button>
                ))}
              </div>
              <p className="text-xs text-muted-foreground">
                {addScope === "global"
                  ? "Visible to all profiles and sessions."
                  : addScope === "profile"
                    ? "Scoped to the current profile only."
                    : "Scoped to the current session only."}
              </p>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setAddOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={saving || !addKey.trim()}>
                {saving ? "Adding…" : "Add Variable"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirm dialog */}
      <Dialog open={!!deleteTarget} onOpenChange={(open) => { if (!open) setDeleteTarget(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Clear Variable</DialogTitle>
            <DialogDescription>
              Are you sure you want to remove <strong className="font-mono">{deleteTarget}</strong>? This action cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteTarget(null)}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={() => void handleDelete()}>
              Clear
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
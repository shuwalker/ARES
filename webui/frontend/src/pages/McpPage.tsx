import { useCallback, useEffect, useState } from "react";
import {
  CircleDot,
  LoaderCircle,
  MoreHorizontal,
  Pencil,
  Plus,
  RefreshCw,
  RotateCcw,
  Server,
  Trash2,
  X,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { aresApi } from "@/shared/ares-api";
import type { McpServerEntry } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";

// ── Status helpers ──────────────────────────────────────────────────────

function statusDotClass(status?: string): string {
  switch (status) {
    case "connected":
    case "running":
    case "active":
    case "available":
      return "bg-emerald-500";
    case "error":
    case "failed":
    case "crashed":
      return "bg-destructive";
    case "connecting":
    case "starting":
      return "bg-amber-500 animate-pulse";
    case "disabled":
    case "stopped":
      return "bg-muted-foreground/50";
    default:
      return "bg-muted-foreground";
  }
}

function statusLabel(status?: string): string {
  if (!status) return "Unknown";
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function statusBadgeVariant(status?: string): "outline" | "destructive" | "secondary" {
  switch (status) {
    case "connected":
    case "running":
    case "active":
    case "available":
      return "outline";
    case "error":
    case "failed":
    case "crashed":
      return "destructive";
    default:
      return "secondary";
  }
}

// ── Env editor row ─────────────────────────────────────────────────────

function EnvRow({
  k,
  v,
  onKeyChange,
  onValueChange,
  onRemove,
}: {
  k: string;
  v: string;
  onKeyChange: (val: string) => void;
  onValueChange: (val: string) => void;
  onRemove: () => void;
}) {
  return (
    <div className="flex items-center gap-2">
      <Input
        className="font-mono text-xs flex-1"
        placeholder="KEY"
        value={k}
        onChange={(e) => onKeyChange(e.target.value)}
      />
      <Input
        className="font-mono text-xs flex-1"
        placeholder="value"
        value={v}
        onChange={(e) => onValueChange(e.target.value)}
      />
      <Button type="button" variant="ghost" size="icon-sm" onClick={onRemove} aria-label="Remove env var">
        <X className="size-3.5" />
      </Button>
    </div>
  );
}

// ── Add / Edit server dialog ───────────────────────────────────────────

interface ServerFormState {
  name: string;
  command: string;
  args: string;
  envPairs: [string, string][];
}

function emptyFormState(): ServerFormState {
  return { name: "", command: "", args: "", envPairs: [] };
}

function serverToForm(server: McpServerEntry): ServerFormState {
  return {
    name: server.name ?? "",
    command: server.command ?? "",
    args: Array.isArray(server.args) ? server.args.join(" ") : "",
    envPairs: server.env ? Object.entries(server.env) : [],
  };
}

function formToPayload(form: ServerFormState): Record<string, unknown> {
  const args = form.args.trim() ? form.args.trim().split(/\s+/) : [];
  const env: Record<string, string> = {};
  for (const [k, v] of form.envPairs) {
    if (k.trim()) env[k.trim()] = v;
  }
  return {
    name: form.name.trim(),
    command: form.command.trim(),
    args,
    env,
    enabled: true,
  };
}

function ServerFormDialog({
  open,
  onOpenChange,
  initial,
  onSave,
  title,
  description,
  isEdit,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: ServerFormState | null;
  onSave: (payload: Record<string, unknown>) => Promise<void>;
  title: string;
  description: string;
  isEdit: boolean;
}) {
  const [form, setForm] = useState<ServerFormState>(emptyFormState());
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setForm(initial ?? emptyFormState());
      setError(null);
      setSaving(false);
    }
  }, [open, initial]);

  function addEnvRow() {
    setForm((prev) => ({ ...prev, envPairs: [...prev.envPairs, ["", ""]] }));
  }

  function updateEnvRow(index: number, field: "key" | "value", val: string) {
    setForm((prev) => {
      const pairs = [...prev.envPairs];
      if (field === "key") pairs[index] = [val, pairs[index][1]];
      else pairs[index] = [pairs[index][0], val];
      return { ...prev, envPairs: pairs };
    });
  }

  function removeEnvRow(index: number) {
    setForm((prev) => ({
      ...prev,
      envPairs: prev.envPairs.filter((_, i) => i !== index),
    }));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!form.name.trim() || !form.command.trim()) return;
    setSaving(true);
    setError(null);
    try {
      await onSave(formToPayload(form));
      onOpenChange(false);
    } catch (err) {
      setError(readableError(err, "Failed to save server."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        <form onSubmit={(e) => void handleSubmit(e)} className="grid gap-4 py-2">
          {isEdit && (
            <div className="grid gap-2">
              <Label htmlFor="mcp-name">Name</Label>
              <Input id="mcp-name" value={form.name} disabled className="bg-muted font-mono text-sm" />
            </div>
          )}
          {!isEdit && (
            <div className="grid gap-2">
              <Label htmlFor="mcp-name">Name</Label>
              <Input
                id="mcp-name"
                placeholder="e.g. filesystem"
                value={form.name}
                onChange={(e) => setForm((prev) => ({ ...prev, name: e.target.value }))}
                autoFocus
              />
            </div>
          )}
          <div className="grid gap-2">
            <Label htmlFor="mcp-command">Command</Label>
            <Input
              id="mcp-command"
              placeholder="e.g. npx or python"
              value={form.command}
              onChange={(e) => setForm((prev) => ({ ...prev, command: e.target.value }))}
              className="font-mono text-sm"
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="mcp-args">Arguments</Label>
            <Input
              id="mcp-args"
              placeholder="Space-separated args, e.g. -y @anthropic/mcp-server-filesystem /tmp"
              value={form.args}
              onChange={(e) => setForm((prev) => ({ ...prev, args: e.target.value }))}
              className="font-mono text-sm"
            />
            <p className="text-[11px] text-muted-foreground">Separate arguments with spaces. Values containing spaces should be quoted.</p>
          </div>
          <div className="grid gap-2">
            <div className="flex items-center justify-between">
              <Label>Environment Variables</Label>
              <Button type="button" variant="outline" size="sm" onClick={addEnvRow}>
                <Plus className="mr-1 size-3" /> Add
              </Button>
            </div>
            {form.envPairs.length === 0 && (
              <p className="text-xs text-muted-foreground">No environment variables configured.</p>
            )}
            <div className="grid gap-2">
              {form.envPairs.map(([k, v], i) => (
                <EnvRow
                  key={i}
                  k={k}
                  v={v}
                  onKeyChange={(val) => updateEnvRow(i, "key", val)}
                  onValueChange={(val) => updateEnvRow(i, "value", val)}
                  onRemove={() => removeEnvRow(i)}
                />
              ))}
            </div>
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !form.name.trim() || !form.command.trim()}>
              {saving && <LoaderCircle className="mr-2 size-4 animate-spin" />}
              {isEdit ? "Save Changes" : "Add Server"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ── Delete confirm dialog ──────────────────────────────────────────────

function DeleteConfirmDialog({
  server,
  onOpenChange,
  onDeleted,
}: {
  server: McpServerEntry | null;
  onOpenChange: (open: boolean) => void;
  onDeleted: () => void;
}) {
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleDelete() {
    if (!server) return;
    setDeleting(true);
    setError(null);
    try {
      await aresApi.mcpDelete(server.name);
      onOpenChange(false);
      onDeleted();
    } catch (err) {
      setError(readableError(err, "Failed to delete server."));
      setDeleting(false);
    }
  }

  return (
    <Dialog open={Boolean(server)} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Delete MCP Server</DialogTitle>
          <DialogDescription>
            Remove <strong>{server?.name}</strong> from your configuration. This cannot be undone.
          </DialogDescription>
        </DialogHeader>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={deleting}>
            Cancel
          </Button>
          <Button variant="destructive" onClick={() => void handleDelete()} disabled={deleting}>
            {deleting && <LoaderCircle className="mr-2 size-4 animate-spin" />}
            Delete
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ── Server card ────────────────────────────────────────────────────────

function McpServerCard({
  server,
  onToggle,
  onRestart,
  onEdit,
  onDelete,
  toggling,
  restarting,
}: {
  server: McpServerEntry;
  onToggle: (name: string, enabled: boolean) => void;
  onRestart: (name: string) => void;
  onEdit: (server: McpServerEntry) => void;
  onDelete: (server: McpServerEntry) => void;
  toggling: boolean;
  restarting: boolean;
}) {
  const enabled = server.enabled !== false;
  const statusVariant = statusBadgeVariant(server.status);
  const dotClass = statusDotClass(server.status);

  return (
    <Card className="group transition-shadow hover:shadow-md">
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-3">
          <div className="flex min-w-0 items-center gap-3">
            <div className="grid size-9 shrink-0 place-items-center rounded-md bg-muted">
              <Server className="size-4" />
            </div>
            <div className="min-w-0">
              <CardTitle className="truncate text-base">{server.name}</CardTitle>
              {server.description && (
                <CardDescription className="truncate">{server.description}</CardDescription>
              )}
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <Badge variant={statusVariant} className="text-[10px]">
              <span className={`mr-1.5 inline-block size-1.5 rounded-full ${dotClass}`} />
              {statusLabel(server.status)}
            </Badge>
            {server.tools_count !== undefined && server.tools_count > 0 && (
              <Badge variant="secondary" className="text-[10px]">
                {server.tools_count} tool{server.tools_count !== 1 ? "s" : ""}
              </Badge>
            )}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon-sm" className="opacity-0 group-hover:opacity-100 transition-opacity">
                  <MoreHorizontal className="size-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={() => onEdit(server)}>
                  <Pencil className="mr-2 size-3.5" /> Edit
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => onRestart(server.name)} disabled={restarting}>
                  <RotateCcw className="mr-2 size-3.5" /> Restart
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => onDelete(server)}>
                  <Trash2 className="mr-2 size-3.5" /> Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </CardHeader>
      <CardContent className="grid gap-3 pt-0">
        <div className="grid gap-2 text-sm">
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Command</span>
            <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs truncate max-w-[70%]">
              {server.command || "—"}
            </code>
          </div>
          {server.args && server.args.length > 0 && (
            <div className="flex items-center justify-between gap-4">
              <span className="text-muted-foreground">Args</span>
              <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs truncate max-w-[70%]">
                {server.args.join(" ")}
              </code>
            </div>
          )}
          {server.env && Object.keys(server.env).length > 0 && (
            <div className="flex items-center justify-between gap-4">
              <span className="text-muted-foreground">Env vars</span>
              <span className="text-xs text-muted-foreground">{Object.keys(server.env).length} variable{Object.keys(server.env).length !== 1 ? "s" : ""}</span>
            </div>
          )}
          <div className="flex items-center justify-between gap-4 pt-1">
            <span className="text-muted-foreground">Enabled</span>
            <ToggleSwitch checked={enabled} onCheckedChange={(v) => onToggle(server.name, v)} disabled={toggling} />
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

// ── Main page ───────────────────────────────────────────────────────────

export default function McpPage() {
  const [servers, setServers] = useState<McpServerEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [togglingServer, setTogglingServer] = useState<string | null>(null);
  const [restartingServer, setRestartingServer] = useState<string | null>(null);

  // Add dialog
  const [addOpen, setAddOpen] = useState(false);
  // Edit dialog
  const [editServer, setEditServer] = useState<McpServerEntry | null>(null);
  // Delete dialog
  const [deleteServer, setDeleteServer] = useState<McpServerEntry | null>(null);

  // ── Load servers ────────────────────────────────────────────────
  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.mcpList();
      setServers(Array.isArray(data) ? data : []);
    } catch (err) {
      setError(readableError(err, "Failed to load MCP servers."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // ── Toggle enable/disable ───────────────────────────────────────
  async function handleToggle(name: string, enabled: boolean) {
    setTogglingServer(name);
    try {
      await aresApi.mcpToggle(name, enabled);
      // Optimistically update local state
      setServers((prev) =>
        prev.map((s) => (s.name === name ? { ...s, enabled } : s)),
      );
    } catch (err) {
      setError(readableError(err, `Failed to ${enabled ? "enable" : "disable"} server.`));
    } finally {
      setTogglingServer(null);
    }
  }

  // ── Restart ─────────────────────────────────────────────────────
  async function handleRestart(name: string) {
    setRestartingServer(name);
    try {
      await aresApi.mcpRestart(name);
      // Refresh full list after restart
      await load();
    } catch (err) {
      setError(readableError(err, `Failed to restart ${name}.`));
    } finally {
      setRestartingServer(null);
    }
  }

  // ── Add server ──────────────────────────────────────────────────
  async function handleAddServer(payload: Record<string, unknown>) {
    const name = String(payload.name ?? "");
    await aresApi.mcpUpdate(name, payload);
    await load();
  }

  // ── Edit server ─────────────────────────────────────────────────
  async function handleEditServer(payload: Record<string, unknown>) {
    const name = String(payload.name ?? "");
    await aresApi.mcpUpdate(name, payload);
    setEditServer(null);
    await load();
  }

  // ── Render ──────────────────────────────────────────────────────
  if (loading) {
    return (
      <div className="page-stack">
        <PageHeader title="MCP Servers" description="Manage Model Context Protocol server connections." />
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading MCP servers…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="MCP Servers"
        description="Manage Model Context Protocol server connections."
        action={
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => void load()} disabled={loading}>
              <RefreshCw className="mr-1 size-3.5" />
              Refresh
            </Button>
            <Button size="sm" onClick={() => setAddOpen(true)}>
              <Plus className="mr-1 size-3.5" />
              Add Server
            </Button>
          </div>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      {servers.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <CircleDot className="mb-4 size-10 text-muted-foreground/30" />
          <p className="text-sm text-muted-foreground">No MCP servers configured.</p>
          <p className="mt-1 text-xs text-muted-foreground">Add a server to connect external tools and data sources.</p>
          <Button className="mt-4" size="sm" onClick={() => setAddOpen(true)}>
            <Plus className="mr-1 size-3.5" />
            Add Server
          </Button>
        </div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {servers.map((server) => (
            <McpServerCard
              key={server.name}
              server={server}
              onToggle={handleToggle}
              onRestart={handleRestart}
              onEdit={(s) => setEditServer(s)}
              onDelete={(s) => setDeleteServer(s)}
              toggling={togglingServer === server.name}
              restarting={restartingServer === server.name}
            />
          ))}
        </div>
      )}

      {/* Add server dialog */}
      <ServerFormDialog
        open={addOpen}
        onOpenChange={setAddOpen}
        initial={null}
        onSave={handleAddServer}
        title="Add MCP Server"
        description="Configure a new Model Context Protocol server connection."
        isEdit={false}
      />

      {/* Edit server dialog */}
      {editServer && (
        <ServerFormDialog
          open={Boolean(editServer)}
          onOpenChange={(open) => { if (!open) setEditServer(null); }}
          initial={serverToForm(editServer)}
          onSave={handleEditServer}
          title={`Edit ${editServer.name}`}
          description="Update the configuration for this MCP server."
          isEdit={true}
        />
      )}

      {/* Delete confirm dialog */}
      <DeleteConfirmDialog
        server={deleteServer}
        onOpenChange={(open) => { if (!open) setDeleteServer(null); }}
        onDeleted={() => void load()}
      />
    </div>
  );
}
import { useEffect, useMemo, useState, useCallback } from "react";
import {
  Eye,
  EyeOff,
  KeyRound,
  Loader2,
  MoreHorizontal,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Trash2,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { aresApi } from "@/shared/ares-api";
import type { SecretEntry } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type SecretScope = "all" | "global" | "profile" | "session";

interface CreateSecretPayload {
  key: string;
  value: string;
}

interface UpdateSecretPayload {
  name?: string;
  description?: string;
  value?: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const EMPTY_SECRETS: SecretEntry[] = [];

function maskValue(value: string): string {
  if (!value) return "••••••••";
  if (value.length <= 4) return "••••";
  return value.slice(0, 2) + "••••" + value.slice(-2);
}

function formatRelative(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  const diff = Date.now() - date.getTime();
  if (diff < 0) return date.toLocaleString();
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  return date.toLocaleDateString();
}

function deriveScope(key: string): SecretScope {
  const upper = key.toUpperCase();
  if (upper.startsWith("ARES_") || upper === "PATH" || upper === "HOME" || upper === "LANG")
    return "global";
  if (upper.includes("_PROFILE_") || upper.startsWith("PROFILE_")) return "profile";
  return "session";
}

function providerLabel(provider: string): string {
  const labels: Record<string, string> = {
    local_encrypted: "Local Encrypted",
    aws_secrets_manager: "AWS Secrets Manager",
    gcp_secret_manager: "GCP Secret Manager",
    vault: "HashiCorp Vault",
    openai: "OpenAI",
    anthropic: "Anthropic",
    google: "Google",
    xai: "xAI",
    ollama: "Ollama",
  };
  return labels[provider] ?? provider.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function statusDotClass(status: SecretEntry["status"]): string {
  switch (status) {
    case "active":
      return "bg-emerald-500";
    case "disabled":
      return "bg-amber-500";
    case "archived":
      return "bg-muted-foreground";
    case "deleted":
      return "bg-destructive";
    default:
      return "bg-muted-foreground";
  }
}

function statusLabel(status: SecretEntry["status"]): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function StatusBadge({ status }: { status: SecretEntry["status"] }) {
  return (
    <Badge
      variant="outline"
      className={
        status === "active"
          ? "text-emerald-700 dark:text-emerald-300"
          : status === "disabled"
            ? "text-amber-700 dark:text-amber-300"
            : status === "deleted"
              ? "text-destructive"
              : "text-muted-foreground"
      }
    >
      <span className={`mr-1.5 inline-block size-1.5 rounded-full ${statusDotClass(status)}`} />
      {statusLabel(status)}
    </Badge>
  );
}

function ScopeBadge({ scope }: { scope: SecretScope }) {
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
  const colour = SCOPE_COLORS[scope] ?? "bg-muted text-muted-foreground border-border";
  const label = SCOPE_LABELS[scope] ?? scope;
  return (
    <Badge variant="outline" className={`font-mono text-[10px] uppercase tracking-wider ${colour}`}>
      {label}
    </Badge>
  );
}

function SecretCard({
  secret,
  onEdit,
  onDelete,
}: {
  secret: SecretEntry;
  onEdit: (secret: SecretEntry) => void;
  onDelete: (secret: SecretEntry) => void;
}) {
  const [revealed, setRevealed] = useState(false);
  const [revealedValue, setRevealedValue] = useState<string | null>(null);
  const [revealing, setRevealing] = useState(false);

  async function handleReveal() {
    if (revealed) {
      setRevealed(false);
      setRevealedValue(null);
      return;
    }
    setRevealing(true);
    try {
      const full = await aresApi.secretGetByKey(secret.key);
      setRevealedValue(full.value ?? full.value_preview ?? "");
      setRevealed(true);
    } catch {
      // Fallback: show the preview/masked value
      setRevealed(true);
    } finally {
      setRevealing(false);
    }
  }

  const displayValue = revealed
    ? (revealedValue ?? secret.value_preview ?? secret.value ?? "—")
    : maskValue(secret.value_preview ?? secret.value ?? "");

  const scope = deriveScope(secret.key);

  return (
    <Card className="group transition-shadow hover:shadow-md">
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-3">
          <div className="flex min-w-0 items-center gap-2">
            <div className="grid size-8 shrink-0 place-items-center rounded-md bg-muted">
              <KeyRound className="size-4" />
            </div>
            <div className="min-w-0">
              <CardTitle className="truncate text-base">{secret.name || secret.key}</CardTitle>
              <div className="flex items-center gap-1.5">
                <p className="truncate text-xs text-muted-foreground font-mono">{secret.key}</p>
                <ScopeBadge scope={scope} />
              </div>
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            {secret.status && <StatusBadge status={secret.status} />}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon-sm" className="opacity-0 group-hover:opacity-100 transition-opacity">
                  <MoreHorizontal className="size-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={() => onEdit(secret)}>
                  <Pencil className="mr-2 size-3.5" /> Edit
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => onDelete(secret)}>
                  <Trash2 className="mr-2 size-3.5" /> Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </CardHeader>
      <CardContent className="grid gap-3 pt-0">
        {secret.description && (
          <p className="text-sm text-muted-foreground">{secret.description}</p>
        )}
        <div className="grid gap-2 text-sm">
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Value</span>
            <div className="flex items-center gap-2">
              <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs">{displayValue}</code>
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() => void handleReveal()}
                disabled={revealing}
                aria-label={revealed ? "Mask value" : "Reveal value"}
              >
                {revealing ? (
                  <Loader2 className="size-3.5 animate-spin" />
                ) : revealed ? (
                  <EyeOff className="size-3.5" />
                ) : (
                  <Eye className="size-3.5" />
                )}
              </Button>
            </div>
          </div>
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Provider</span>
            <Badge variant="secondary">{providerLabel(secret.provider)}</Badge>
          </div>
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Last updated</span>
            <span className="text-xs text-muted-foreground">{formatRelative(secret.updated_at)}</span>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function AddSecretDialog({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated: () => void;
}) {
  const [key, setKey] = useState("");
  const [value, setValue] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setKey("");
    setValue("");
    setSaving(false);
    setError(null);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmedKey = key.trim();
    const trimmedValue = value.trim();
    if (!trimmedKey || !trimmedValue) return;
    setSaving(true);
    setError(null);
    try {
      await aresApi.saveSecret(trimmedKey, trimmedValue);
      reset();
      onOpenChange(false);
      onCreated();
    } catch (err) {
      setError(readableError(err, "Failed to create secret."));
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) reset(); onOpenChange(v); }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Add Secret</DialogTitle>
          <DialogDescription>
            Store a new credential or API key. The value will be encrypted at rest.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={(e) => void handleSubmit(e)} className="grid gap-4 py-2">
          <div className="grid gap-2">
            <Label htmlFor="secret-key">Key</Label>
            <Input
              id="secret-key"
              placeholder="e.g. OPENAI_API_KEY"
              value={key}
              onChange={(e) => setKey(e.target.value)}
              autoFocus
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="secret-value">Value</Label>
            <Input
              id="secret-value"
              type="password"
              placeholder="sk-..."
              value={value}
              onChange={(e) => setValue(e.target.value)}
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => { reset(); onOpenChange(false); }}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !key.trim() || !value.trim()}>
              {saving && <Loader2 className="mr-2 size-4 animate-spin" />}
              Add Secret
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function EditSecretDialog({
  secret,
  onOpenChange,
  onSaved,
}: {
  secret: SecretEntry | null;
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [newValue, setNewValue] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (secret) {
      setName(secret.name ?? "");
      setDescription(secret.description ?? "");
      setNewValue("");
      setError(null);
    }
  }, [secret]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!secret) return;
    setSaving(true);
    setError(null);
    try {
      const payload: UpdateSecretPayload = {};
      const trimmedName = name.trim();
      if (trimmedName && trimmedName !== secret.name) payload.name = trimmedName;
      if (description.trim() !== (secret.description ?? "")) payload.description = description.trim() || undefined;
      if (newValue.trim()) payload.value = newValue.trim();
      await aresApi.updateSecret(secret.id, payload);
      onOpenChange(false);
      onSaved();
    } catch (err) {
      setError(readableError(err, "Failed to update secret."));
      setSaving(false);
    }
  }

  return (
    <Dialog open={Boolean(secret)} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Edit Secret</DialogTitle>
          <DialogDescription>
            Update the name, description, or rotate the value for this secret.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={(e) => void handleSubmit(e)} className="grid gap-4 py-2">
          <div className="grid gap-2">
            <Label htmlFor="edit-key">Key</Label>
            <Input id="edit-key" value={secret?.key ?? ""} disabled className="bg-muted" />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="edit-name">Name</Label>
            <Input
              id="edit-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="edit-desc">Description</Label>
            <Input
              id="edit-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="edit-value">New Value (leave blank to keep current)</Label>
            <Input
              id="edit-value"
              type="password"
              placeholder="Enter a new value to rotate the secret"
              value={newValue}
              onChange={(e) => setNewValue(e.target.value)}
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving}>
              {saving && <Loader2 className="mr-2 size-4 animate-spin" />}
              Save Changes
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function DeleteConfirmDialog({
  secret,
  onOpenChange,
  onDeleted,
}: {
  secret: SecretEntry | null;
  onOpenChange: (open: boolean) => void;
  onDeleted: () => void;
}) {
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleDelete() {
    if (!secret) return;
    setDeleting(true);
    setError(null);
    try {
      await aresApi.deleteSecret(secret.key);
      onOpenChange(false);
      onDeleted();
    } catch (err) {
      setError(readableError(err, "Failed to delete secret."));
      setDeleting(false);
    }
  }

  return (
    <Dialog open={Boolean(secret)} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Delete Secret</DialogTitle>
          <DialogDescription>
            Are you sure you want to delete <strong>{secret?.name || secret?.key}</strong>? This action cannot be undone.
          </DialogDescription>
        </DialogHeader>
        {error && <p className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={deleting}>
            Cancel
          </Button>
          <Button variant="destructive" onClick={() => void handleDelete()} disabled={deleting}>
            {deleting && <Loader2 className="mr-2 size-4 animate-spin" />}
            Delete
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function SecretsPage() {
  const [secrets, setSecrets] = useState<SecretEntry[]>(EMPTY_SECRETS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [scopeFilter, setScopeFilter] = useState<SecretScope>("all");
  const [addOpen, setAddOpen] = useState(false);
  const [editingSecret, setEditingSecret] = useState<SecretEntry | null>(null);
  const [deletingSecret, setDeletingSecret] = useState<SecretEntry | null>(null);

  const loadSecrets = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.secrets();
      setSecrets(data ?? []);
    } catch (err) {
      setError(readableError(err, "Failed to load secrets."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadSecrets();
  }, [loadSecrets]);

  const filtered = useMemo(() => {
    let result = secrets;
    // Scope filter
    if (scopeFilter !== "all") {
      result = result.filter((s) => deriveScope(s.key) === scopeFilter);
    }
    // Search filter
    const needle = search.trim().toLowerCase();
    if (needle) {
      result = result.filter(
        (s) =>
          s.name.toLowerCase().includes(needle) ||
          s.key.toLowerCase().includes(needle) ||
          (s.description ?? "").toLowerCase().includes(needle) ||
          providerLabel(s.provider).toLowerCase().includes(needle),
      );
    }
    return result;
  }, [secrets, search, scopeFilter]);

  const scopeCounts = useMemo(() => {
    const counts: Record<SecretScope, number> = { all: secrets.length, global: 0, profile: 0, session: 0 };
    for (const s of secrets) {
      const scope = deriveScope(s.key);
      counts[scope] = (counts[scope] ?? 0) + 1;
    }
    return counts;
  }, [secrets]);

  return (
    <div className="page-stack">
      <PageHeader
        title="Secrets"
        description="Manage API keys and credentials stored for your ARES instance."
        action={
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => void loadSecrets()} disabled={loading}>
              <RefreshCw className={`size-3.5 ${loading ? "animate-spin" : ""}`} />
              Refresh
            </Button>
            <Button size="sm" onClick={() => setAddOpen(true)}>
              <Plus className="size-3.5" />
              Add Secret
            </Button>
          </div>
        }
      />

      <div className="flex items-center gap-3">
        <label className="flex h-9 flex-1 items-center gap-2 rounded-md border bg-background px-3 text-muted-foreground focus-within:border-ring focus-within:text-foreground">
          <Search className="size-4 shrink-0" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search secrets by name, key, or provider…"
            className="min-w-0 flex-1 bg-transparent text-sm text-foreground outline-none placeholder:text-muted-foreground"
          />
        </label>
        <Select value={scopeFilter} onValueChange={(v) => setScopeFilter(v as SecretScope)}>
          <SelectTrigger className="h-9 w-[140px]">
            <SelectValue placeholder="Scope" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All ({scopeCounts.all})</SelectItem>
            <SelectItem value="global">Global ({scopeCounts.global})</SelectItem>
            <SelectItem value="profile">Profile ({scopeCounts.profile})</SelectItem>
            <SelectItem value="session">Session ({scopeCounts.session})</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      {loading && secrets.length === 0 ? (
        <div className="grid place-items-center py-20">
          <Loader2 className="size-8 animate-spin text-muted-foreground" />
        </div>
      ) : filtered.length === 0 ? (
        <Card>
          <CardContent className="grid place-items-center py-16">
            <div className="grid size-12 place-items-center rounded-lg border bg-muted">
              <KeyRound className="size-5 text-muted-foreground" />
            </div>
            <p className="mt-4 text-lg font-semibold">
              {search || scopeFilter !== "all" ? "No matching secrets" : "No secrets yet"}
            </p>
            <p className="mt-1 max-w-sm text-center text-sm text-muted-foreground">
              {search || scopeFilter !== "all"
                ? "Try a different search term or change the scope filter."
                : "Add an API key or credential to get started."}
            </p>
            {!search && scopeFilter === "all" && (
              <Button className="mt-4" size="sm" onClick={() => setAddOpen(true)}>
                <Plus className="size-3.5" /> Add Secret
              </Button>
            )}
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {filtered.map((secret) => (
            <SecretCard
              key={secret.id}
              secret={secret}
              onEdit={setEditingSecret}
              onDelete={setDeletingSecret}
            />
          ))}
        </div>
      )}

      <AddSecretDialog
        open={addOpen}
        onOpenChange={setAddOpen}
        onCreated={() => void loadSecrets()}
      />
      <EditSecretDialog
        secret={editingSecret}
        onOpenChange={(open) => { if (!open) setEditingSecret(null); }}
        onSaved={() => void loadSecrets()}
      />
      <DeleteConfirmDialog
        secret={deletingSecret}
        onOpenChange={(open) => { if (!open) setDeletingSecret(null); }}
        onDeleted={() => void loadSecrets()}
      />
    </div>
  );
}
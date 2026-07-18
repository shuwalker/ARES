import { useCallback, useEffect, useState } from "react";
import {
  LoaderCircle,
  Plus,
  RefreshCw,
  RotateCw,
  Trash2,
  Webhook,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";
import type { WebhookEntry } from "@/shared/ares-api";

// ---------------------------------------------------------------------------
// Create webhook dialog
// ---------------------------------------------------------------------------

function CreateWebhookDialog({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated: () => void;
}) {
  const [name, setName] = useState("");
  const [url, setUrl] = useState("");
  const [event, setEvent] = useState("*");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setName("");
    setUrl("");
    setEvent("*");
    setSaving(false);
    setError(null);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmedName = name.trim();
    const trimmedUrl = url.trim();
    if (!trimmedName || !trimmedUrl) return;
    setSaving(true);
    setError(null);
    try {
      await aresApi.webhookCreate({
        name: trimmedName,
        url: trimmedUrl,
        event: event.trim() || "*",
        enabled: true,
      });
      reset();
      onOpenChange(false);
      onCreated();
    } catch (err) {
      setError(readableError(err, "Failed to create webhook."));
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) reset(); onOpenChange(v); }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>New Webhook</DialogTitle>
          <DialogDescription>
            Register a webhook endpoint to receive event notifications.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={(e) => void handleSubmit(e)} className="grid gap-4 py-2">
          <div className="grid gap-2">
            <Label htmlFor="wh-name">Name</Label>
            <Input
              id="wh-name"
              placeholder="e.g. my-service-hook"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="wh-url">URL</Label>
            <Input
              id="wh-url"
              placeholder="https://example.com/webhook"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="wh-event">Event filter</Label>
            <Select value={event} onValueChange={setEvent}>
              <SelectTrigger id="wh-event">
                <SelectValue placeholder="Select event filter" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="*">All events</SelectItem>
                <SelectItem value="message.created">message.created</SelectItem>
                <SelectItem value="message.completed">message.completed</SelectItem>
                <SelectItem value="session.created">session.created</SelectItem>
                <SelectItem value="session.completed">session.completed</SelectItem>
                <SelectItem value="tool.approval">tool.approval</SelectItem>
              </SelectContent>
            </Select>
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => { reset(); onOpenChange(false); }}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !name.trim() || !url.trim()}>
              {saving && <LoaderCircle className="mr-2 size-4 animate-spin" />}
              Create
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Delete confirm dialog
// ---------------------------------------------------------------------------

function DeleteWebhookDialog({
  open,
  onOpenChange,
  webhook,
  onConfirm,
  loading,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  webhook: WebhookEntry | null;
  onConfirm: () => void;
  loading: boolean;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Delete Webhook</DialogTitle>
          <DialogDescription>
            {webhook
              ? `Permanently remove "${webhook.name}"? This cannot be undone.`
              : "Permanently remove this webhook? This cannot be undone."}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button variant="destructive" disabled={loading} onClick={onConfirm}>
            {loading && <LoaderCircle className="mr-2 size-4 animate-spin" />}
            Delete
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function WebhooksPage() {
  const [webhooks, setWebhooks] = useState<WebhookEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<WebhookEntry | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [togglingId, setTogglingId] = useState<string | null>(null);

  const loadWebhooks = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.webhooksList();
      setWebhooks(Array.isArray(data) ? data : []);
    } catch (err) {
      setError(readableError(err, "Failed to load webhooks."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadWebhooks();
  }, [loadWebhooks]);

  async function handleToggle(wh: WebhookEntry) {
    setTogglingId(wh.id);
    try {
      await aresApi.webhookUpdate(wh.id, { enabled: !wh.enabled });
      setWebhooks((prev) =>
        prev.map((w) =>
          w.id === wh.id ? { ...w, enabled: !w.enabled } : w,
        ),
      );
    } catch {
      // Optimistic revert
      setWebhooks((prev) =>
        prev.map((w) => (w.id === wh.id ? { ...w, enabled: wh.enabled } : w)),
      );
    }
    setTogglingId(null);
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await aresApi.webhookDelete(deleteTarget.id);
      setWebhooks((prev) => prev.filter((w) => w.id !== deleteTarget.id));
      setDeleteTarget(null);
    } catch {
      // Ignore
    }
    setDeleting(false);
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Webhooks"
        description="Manage webhook endpoints that receive event notifications from ARES."
        action={
          <Button size="sm" onClick={() => setCreateOpen(true)}>
            <Plus className="size-4" />
            New webhook
          </Button>
        }
      />

      <CreateWebhookDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        onCreated={() => void loadWebhooks()}
      />

      <DeleteWebhookDialog
        open={!!deleteTarget}
        onOpenChange={(v) => { if (!v) setDeleteTarget(null); }}
        webhook={deleteTarget}
        onConfirm={handleDelete}
        loading={deleting}
      />

      {loading ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading webhooks…</p>
        </div>
      ) : error ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <RotateCw className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-destructive">{error}</p>
          <Button variant="outline" size="sm" className="mt-4" onClick={() => void loadWebhooks()}>
            <RefreshCw className="size-4" />
            Retry
          </Button>
        </div>
      ) : webhooks.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <Webhook className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">No webhooks configured yet.</p>
          <Button variant="outline" size="sm" className="mt-4" onClick={() => setCreateOpen(true)}>
            <Plus className="size-4" />
            Add webhook
          </Button>
        </div>
      ) : (
        <div className="grid gap-3">
          {webhooks.map((wh) => (
            <Card key={wh.id}>
              <CardContent className="flex items-start gap-4 py-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1 flex-wrap">
                    <span className="font-medium text-sm truncate">{wh.name}</span>
                    <Badge variant="outline" className="text-xs">
                      {wh.event || "*"}
                    </Badge>
                    {wh.enabled === false && (
                      <Badge variant="outline" className="text-xs text-amber-600 dark:text-amber-400">
                        disabled
                      </Badge>
                    )}
                  </div>
                  <div className="font-mono text-xs text-muted-foreground truncate mt-1">
                    {wh.url}
                  </div>
                </div>

                <div className="flex items-center gap-3 shrink-0">
                  <ToggleSwitch
                    checked={wh.enabled !== false}
                    onCheckedChange={() => void handleToggle(wh)}
                    disabled={togglingId === wh.id}
                  />
                  <Button
                    variant="ghost"
                    size="icon"
                    className="text-destructive"
                    onClick={() => setDeleteTarget(wh)}
                    title="Delete"
                  >
                    <Trash2 className="size-4" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
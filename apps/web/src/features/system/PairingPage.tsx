import { useCallback, useEffect, useState } from "react";
import {
  Check,
  LoaderCircle,
  RefreshCw,
  RotateCw,
  ShieldCheck,
  Smartphone,
  Trash2,
  Users,
  X,
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
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";
import type { PairingEntry } from "@/shared/ares-api";

// ---------------------------------------------------------------------------
// Create pairing dialog
// ---------------------------------------------------------------------------

function CreatePairingDialog({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated: () => void;
}) {
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setName("");
    setSaving(false);
    setError(null);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmedName = name.trim();
    if (!trimmedName) return;
    setSaving(true);
    setError(null);
    try {
      await aresApi.pairingCreate({ name: trimmedName, kind: "device" });
      reset();
      onOpenChange(false);
      onCreated();
    } catch (err) {
      setError(readableError(err, "Failed to create pairing request."));
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) reset(); onOpenChange(v); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>New Pairing Request</DialogTitle>
          <DialogDescription>
            Generate a pairing request for a new device or client.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={(e) => void handleSubmit(e)} className="grid gap-4 py-2">
          <div className="grid gap-2">
            <Label htmlFor="pair-name">Device name</Label>
            <Input
              id="pair-name"
              placeholder="e.g. my-laptop"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => { reset(); onOpenChange(false); }}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !name.trim()}>
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
// Clear all pending dialog
// ---------------------------------------------------------------------------

function ClearPendingDialog({
  open,
  onOpenChange,
  onConfirm,
  loading,
  count,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onConfirm: () => void;
  loading: boolean;
  count: number;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Clear All Pending Requests</DialogTitle>
          <DialogDescription>
            Remove all {count} pending pairing request{count !== 1 ? "s" : ""}. This cannot be undone.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button variant="destructive" disabled={loading} onClick={onConfirm}>
            {loading && <LoaderCircle className="mr-2 size-4 animate-spin" />}
            Clear all
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Revoke confirm dialog
// ---------------------------------------------------------------------------

function RevokeDialog({
  open,
  onOpenChange,
  entry,
  onConfirm,
  loading,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  entry: PairingEntry | null;
  onConfirm: () => void;
  loading: boolean;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Revoke Access</DialogTitle>
          <DialogDescription>
            {entry
              ? `Revoke access for "${entry.name}"? This cannot be undone.`
              : "Revoke access for this device? This cannot be undone."}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button variant="destructive" disabled={loading} onClick={onConfirm}>
            {loading && <LoaderCircle className="mr-2 size-4 animate-spin" />}
            Revoke
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function PairingPage() {
  const [entries, setEntries] = useState<PairingEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [clearOpen, setClearOpen] = useState(false);
  const [clearing, setClearing] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<PairingEntry | null>(null);
  const [revoking, setRevoking] = useState(false);
  const [approvingId, setApprovingId] = useState<string | null>(null);

  const loadEntries = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.pairingList();
      setEntries(Array.isArray(data) ? data : []);
    } catch (err) {
      setError(readableError(err, "Failed to load pairing data."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadEntries();
  }, [loadEntries]);

  const pending = entries.filter((e) => e.status === "pending");
  const approved = entries.filter((e) => e.status === "approved");

  async function handleApprove(id: string) {
    setApprovingId(id);
    setError(null);
    try {
      await aresApi.pairingApprove(id);
      await loadEntries();
    } catch (reason) {
      setError(readableError(reason, "Failed to approve the pairing request."));
    }
    setApprovingId(null);
  }

  async function handleRevoke() {
    if (!revokeTarget) return;
    setRevoking(true);
    setError(null);
    try {
      await aresApi.pairingRevoke(revokeTarget.id);
      setEntries((prev) => prev.map((e) =>
        e.id === revokeTarget.id ? { ...e, status: "revoked" as const } : e,
      ));
      setRevokeTarget(null);
    } catch (reason) {
      setError(readableError(reason, `Failed to revoke ${revokeTarget.name}.`));
    }
    setRevoking(false);
  }

  async function handleClear() {
    setClearing(true);
    setError(null);
    try {
      await aresApi.pairingClear();
      setEntries((prev) => prev.filter((e) => e.status !== "pending"));
      setClearOpen(false);
    } catch (reason) {
      setError(readableError(reason, "Failed to clear pending pairing requests."));
    }
    setClearing(false);
  }

  function formatRelative(value: string | null | undefined): string {
    if (!value) return "—";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "—";
    const diff = Date.now() - date.getTime();
    const seconds = Math.floor(diff / 1000);
    if (seconds < 60) return "just now";
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 48) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Pairing"
        description="Manage device pairing requests and approved connections."
        action={
          <div className="flex gap-2">
            {pending.length > 0 && (
              <Button variant="outline" size="sm" onClick={() => setClearOpen(true)}>
                <Trash2 className="size-4" />
                Clear pending
              </Button>
            )}
            <Button size="sm" onClick={() => setCreateOpen(true)}>
              <Smartphone className="size-4" />
              New pairing
            </Button>
          </div>
        }
      />

      <CreatePairingDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        onCreated={() => void loadEntries()}
      />

      <ClearPendingDialog
        open={clearOpen}
        onOpenChange={setClearOpen}
        onConfirm={handleClear}
        loading={clearing}
        count={pending.length}
      />

      <RevokeDialog
        open={!!revokeTarget}
        onOpenChange={(v) => { if (!v) setRevokeTarget(null); }}
        entry={revokeTarget}
        onConfirm={handleRevoke}
        loading={revoking}
      />

      {loading ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading pairing data…</p>
        </div>
      ) : error ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <RotateCw className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-destructive">{error}</p>
          <Button variant="outline" size="sm" className="mt-4" onClick={() => void loadEntries()}>
            <RefreshCw className="size-4" />
            Retry
          </Button>
        </div>
      ) : (
        <>
          {/* Pending requests */}
          <div className="flex flex-col gap-3">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Users className="size-4" />
              <span>Pending requests</span>
              <Badge variant="outline">{pending.length}</Badge>
            </div>

            {pending.length === 0 ? (
              <Card>
                <CardContent className="py-8 text-center text-sm text-muted-foreground">
                  No pending pairing requests
                </CardContent>
              </Card>
            ) : (
              pending.map((entry) => (
                <Card key={entry.id}>
                  <CardContent className="flex items-start gap-4 py-4">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-medium text-sm truncate">{entry.name}</span>
                        <Badge variant="outline" className="text-xs">{entry.kind}</Badge>
                      </div>
                      <div className="text-xs text-muted-foreground">
                        <span className="font-mono">{entry.id}</span>
                        {entry.created_at && (
                          <span className="ml-2">{formatRelative(entry.created_at)}</span>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <Button
                        size="sm"
                        onClick={() => void handleApprove(entry.id)}
                        disabled={approvingId === entry.id}
                      >
                        {approvingId === entry.id ? (
                          <LoaderCircle className="size-4 animate-spin" />
                        ) : (
                          <Check className="size-4" />
                        )}
                        Approve
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              ))
            )}
          </div>

          {/* Approved devices */}
          <div className="flex flex-col gap-3">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <ShieldCheck className="size-4" />
              <span>Approved devices</span>
              <Badge variant="outline">{approved.length}</Badge>
            </div>

            {approved.length === 0 ? (
              <Card>
                <CardContent className="py-8 text-center text-sm text-muted-foreground">
                  No approved devices
                </CardContent>
              </Card>
            ) : (
              approved.map((entry) => (
                <Card key={entry.id}>
                  <CardContent className="flex items-start gap-4 py-4">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-medium text-sm truncate">{entry.name}</span>
                        <Badge variant="outline" className="text-xs">{entry.kind}</Badge>
                      </div>
                      <div className="text-xs text-muted-foreground">
                        <span className="font-mono">{entry.id}</span>
                        {entry.created_at && (
                          <span className="ml-2">{formatRelative(entry.created_at)}</span>
                        )}
                      </div>
                    </div>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="text-destructive"
                      onClick={() => setRevokeTarget(entry)}
                      title="Revoke"
                    >
                      <X className="size-4" />
                    </Button>
                  </CardContent>
                </Card>
              ))
            )}
          </div>
        </>
      )}
    </div>
  );
}

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Cpu,
  LoaderCircle,
  RefreshCw,
  Wrench,
  CheckCircle2,
  CircleOff,
  CircleDot,
} from "lucide-react";
import { useNavigate } from "react-router-dom";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";
import type { BackendInfo } from "@/shared/contracts";

// ── Helpers ────────────────────────────────────────────────────────────

function statusDotClass(available: boolean): string {
  return available ? "bg-emerald-500" : "bg-muted-foreground/50";
}

function statusLabel(available: boolean): string {
  return available ? "Available" : "Unavailable";
}

// ── Component ──────────────────────────────────────────────────────────

export default function AgentsPage() {
  const [backends, setBackends] = useState<BackendInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const navigate = useNavigate();

  // ── Load backends ────────────────────────────────────────────────────

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.backends();
      setBackends(data);
    } catch (err) {
      setError(readableError(err, "Failed to load backends."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // ── Refresh ──────────────────────────────────────────────────────────

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await load();
    } finally {
      setRefreshing(false);
    }
  }, [load]);

  // ── Derived stats ───────────────────────────────────────────────────

  const availableCount = useMemo(
    () => backends.filter((b) => b.available).length,
    [backends],
  );

  const totalTools = useMemo(() => {
    let count = 0;
    for (const b of backends) {
      const models = b.models as unknown;
      if (Array.isArray(models)) count += models.length;
    }
    return count;
  }, [backends]);

  // ── Loading skeleton ─────────────────────────────────────────────────

  if (loading) {
    return (
      <div className="page-stack">
        <PageHeader title="Backends" description="View the external execution backends ARES can route to." />
        <div className="flex items-center justify-center py-16 text-muted-foreground">
          <LoaderCircle className="mr-2 size-5 animate-spin" />
          Loading backends…
        </div>
      </div>
    );
  }

  // ── Render ──────────────────────────────────────────────────────────

  return (
    <div className="page-stack">
      <PageHeader
        title="Backends"
        description="View the external execution backends ARES can route to."
        action={
          <Button variant="ghost" size="icon" onClick={() => void handleRefresh()} disabled={refreshing}>
            <RefreshCw className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`} />
          </Button>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <span className="inline-flex items-center gap-2">
            <CircleOff className="size-4" />
            {error}
          </span>
          <Button variant="outline" size="xs" className="ml-3" onClick={() => void load()}>
            <RefreshCw className="size-3" />
            Retry
          </Button>
        </div>
      )}

      {/* Summary cards */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Cpu className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Total Backends</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-semibold">{backends.length}</div>
            <p className="text-xs text-muted-foreground mt-1">
              {availableCount} available · {backends.length - availableCount} offline
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4 text-emerald-500" />
              <CardTitle className="text-sm">Available</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-semibold">{availableCount}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Wrench className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Models Registered</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-semibold">{totalTools}</div>
          </CardContent>
        </Card>
      </div>

      {/* Backend cards */}
      {backends.length === 0 && !error ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <Cpu className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">No backends configured.</p>
        </div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {backends.map((backend) => {
            const models = (backend.models as unknown) as { id: string; label?: string; available?: boolean }[] | undefined;
            const modelCount = Array.isArray(models) ? models.length : 0;
            const deployment = backend.deployment || backend.adapter || "default";

            return (
              <Card
                key={backend.id}
                className="group cursor-pointer transition-shadow hover:shadow-md"
                onClick={() => navigate(`/agents/${encodeURIComponent(backend.id)}`)}
              >
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex min-w-0 items-center gap-3">
                      <div className="grid size-9 shrink-0 place-items-center rounded-md bg-muted">
                        <Cpu className="size-4" />
                      </div>
                      <div className="min-w-0">
                        <CardTitle className="truncate text-base">{backend.name || backend.id}</CardTitle>
                        {backend.description && (
                          <CardDescription className="truncate">{backend.description}</CardDescription>
                        )}
                      </div>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      <Badge variant={backend.available ? "outline" : "secondary"} className="text-[10px]">
                        <span className={`mr-1.5 inline-block size-1.5 rounded-full ${statusDotClass(backend.available)}`} />
                        {statusLabel(backend.available)}
                      </Badge>
                      {modelCount > 0 && (
                        <Badge variant="secondary" className="text-[10px]">
                          {modelCount} model{modelCount !== 1 ? "s" : ""}
                        </Badge>
                      )}
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="grid gap-2 pt-0 text-sm">
                  <div className="flex items-center justify-between gap-4">
                    <span className="text-muted-foreground">ID</span>
                    <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs">{backend.id}</code>
                  </div>
                  <div className="flex items-center justify-between gap-4">
                    <span className="text-muted-foreground">Deployment</span>
                    <span className="text-xs text-foreground">{deployment}</span>
                  </div>
                  {backend.adapter && (
                    <div className="flex items-center justify-between gap-4">
                      <span className="text-muted-foreground">Adapter</span>
                      <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs">{backend.adapter}</code>
                    </div>
                  )}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}

import { useCallback, useState } from "react";
import {
  Cable,
  CheckCircle2,
  CircleOff,
  Cpu,
  LoaderCircle,
  Network,
  PlugZap,
  RefreshCw,
  Server,
  Wrench,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";
import { useAres } from "@/shared/ares-context";
import type { BackendInfo, RuntimeConnection } from "@/shared/contracts";

// ── Helpers ──────────────────────────────────────────────────────────

function statusDot(state: "connected" | "needs_attention" | "offline" | boolean): string {
  if (state === "connected" || state === true) return "bg-emerald-500";
  if (state === "needs_attention") return "bg-amber-500";
  return "bg-muted-foreground/50";
}

function connectionLabel(state: "connected" | "needs_attention" | "offline"): string {
  if (state === "connected") return "Connected";
  if (state === "needs_attention") return "Needs Attention";
  return "Offline";
}

function backendStatusLabel(available: boolean): string {
  return available ? "Available" : "Unavailable";
}

// ── Backend Adapter Card ──────────────────────────────────────────────

function BackendCard({ backend }: { backend: BackendInfo }) {
  const models = (backend.models as unknown) as
    | { id: string; label?: string; available?: boolean }[]
    | undefined;
  const modelCount = Array.isArray(models) ? models.length : 0;
  const deployment = backend.deployment || backend.adapter || "default";

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-3">
          <div className="flex min-w-0 items-center gap-3">
            <div className="grid size-9 shrink-0 place-items-center rounded-md bg-muted">
              <Cpu className="size-4" />
            </div>
            <div className="min-w-0">
              <CardTitle className="truncate text-base">
                {backend.name || backend.id}
              </CardTitle>
              {backend.description && (
                <CardDescription className="truncate">
                  {backend.description}
                </CardDescription>
              )}
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <Badge
              variant={backend.available ? "outline" : "secondary"}
              className="text-[10px]"
            >
              <span
                className={`mr-1.5 inline-block size-1.5 rounded-full ${statusDot(backend.available)}`}
              />
              {backendStatusLabel(backend.available)}
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
          <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs">
            {backend.id}
          </code>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span className="text-muted-foreground">Deployment</span>
          <span className="text-xs text-foreground">{deployment}</span>
        </div>
        {backend.adapter && (
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Adapter</span>
            <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs">
              {backend.adapter}
            </code>
          </div>
        )}
        {backend.kind && (
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Kind</span>
            <span className="text-xs text-foreground">{backend.kind}</span>
          </div>
        )}
        {modelCount > 0 && (
          <div className="mt-1 flex flex-wrap gap-1">
            {models!.slice(0, 4).map((m) => (
              <Badge
                key={m.id}
                variant={m.available !== false ? "outline" : "secondary"}
                className="text-[10px]"
              >
                {m.label || m.id}
              </Badge>
            ))}
            {modelCount > 4 && (
              <Badge variant="secondary" className="text-[10px]">
                +{modelCount - 4} more
              </Badge>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ── Connection Card (runtime / tool) ─────────────────────────────────

function ConnectionCard({ connection }: { connection: RuntimeConnection }) {
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<{
    ok: boolean;
    message: string;
  } | null>(null);
  const [toggling, setToggling] = useState(false);
  const [reconnect, setReconnect] = useState(connection.state === "connected");

  const isConnected = connection.state === "connected";

  const handleTest = useCallback(async () => {
    setTesting(true);
    setTestResult(null);
    try {
      const result = await aresApi.channelTest(connection.id);
      const ok = Boolean(result.ok ?? true);
      const message =
        (result.message as string | undefined) ??
        (result.error as string | undefined) ??
        (ok ? "Connection test succeeded." : "Connection test failed.");
      setTestResult({ ok, message });
    } catch (err) {
      setTestResult({
        ok: false,
        message: readableError(err, "Test failed."),
      });
    } finally {
      setTesting(false);
    }
  }, [connection.id]);

  const handleReconnect = useCallback(
    async (checked: boolean) => {
      setToggling(true);
      setReconnect(checked);
      try {
        if (checked) {
          await aresApi.channelConnect(connection.id);
        } else {
          await aresApi.channelDisconnect(connection.id);
        }
      } catch (err) {
        setReconnect(!checked);
        setTestResult({
          ok: false,
          message: readableError(err, checked ? "Connect failed." : "Disconnect failed."),
        });
      } finally {
        setToggling(false);
      }
    },
    [connection.id],
  );

  const Icon = connection.kind === "tool" ? Wrench : Cable;

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-3">
          <div className="flex min-w-0 items-center gap-3">
            <div className="grid size-9 shrink-0 place-items-center rounded-md bg-muted">
              <Icon className="size-4" />
            </div>
            <div className="min-w-0">
              <CardTitle className="truncate text-base">
                {connection.name}
              </CardTitle>
              {connection.detail && (
                <CardDescription className="truncate">
                  {connection.detail}
                </CardDescription>
              )}
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <Badge
              variant={
                isConnected ? "outline" : connection.state === "needs_attention" ? "outline" : "secondary"
              }
              className={`text-[10px] ${isConnected ? "text-status-available" : connection.state === "needs_attention" ? "text-status-limited" : "text-status-unavailable"}`}
            >
              <span
                className={`mr-1.5 inline-block size-1.5 rounded-full ${statusDot(connection.state)}`}
              />
              {connectionLabel(connection.state)}
            </Badge>
            {connection.selected && (
              <Badge variant="secondary" className="text-[10px]">
                Selected
              </Badge>
            )}
          </div>
        </div>
      </CardHeader>
      <CardContent className="grid gap-3 pt-0 text-sm">
        <div className="flex items-center justify-between gap-4">
          <span className="text-muted-foreground">ID</span>
          <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs">
            {connection.id}
          </code>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span className="text-muted-foreground">Kind</span>
          <span className="text-xs text-foreground capitalize">
            {connection.kind}
          </span>
        </div>
        {connection.capabilities.length > 0 && (
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Capabilities</span>
            <div className="flex flex-wrap gap-1">
              {connection.capabilities.map((cap) => (
                <Badge key={cap} variant="outline" className="text-[10px]">
                  {cap}
                </Badge>
              ))}
            </div>
          </div>
        )}
        {/* Test Connection */}
        <div className="flex items-center justify-between gap-4">
          <span className="text-muted-foreground">Test</span>
          <div className="flex items-center gap-2">
            {testResult && (
              <span
                className={`text-xs ${testResult.ok ? "text-status-available" : "text-status-unavailable"}`}
              >
                {testResult.ok ? <CheckCircle2 className="mr-1 inline size-3" /> : <CircleOff className="mr-1 inline size-3" />}
                {testResult.message}
              </span>
            )}
            <Button
              variant="outline"
              size="xs"
              disabled={testing}
              onClick={() => void handleTest()}
            >
              {testing ? (
                <LoaderCircle className="size-3 animate-spin" />
              ) : (
                <PlugZap className="size-3" />
              )}
              {testing ? "Testing…" : "Test"}
            </Button>
          </div>
        </div>
        {/* Reconnect Toggle */}
        <div className="flex items-center justify-between gap-4">
          <span className="text-muted-foreground">Connected</span>
          <ToggleSwitch
            checked={reconnect}
            onCheckedChange={(checked) => void handleReconnect(checked)}
            disabled={toggling}
          />
        </div>
      </CardContent>
    </Card>
  );
}

// ── Page ─────────────────────────────────────────────────────────────

export function ConnectionsPage() {
  const { snapshot } = useAres();
  const [refreshing, setRefreshing] = useState(false);

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    try {
      // Just re-trigger the snapshot refresh
      await aresApi.health();
    } catch {
      // ignore
    } finally {
      setRefreshing(false);
    }
  }, []);

  const backends = snapshot.backends;
  const connections = snapshot.connections;
  const apiAvailable = snapshot.connection === "available";

  // Fixed capability cards (local profile + API health)
  const fixedCapabilities = [
    {
      id: "profile",
      label: "Local Profile",
      available: true,
      detail: "Identity settings remain available without a model connection.",
      Icon: Network,
    },
    {
      id: "api",
      label: "ARES API",
      available: apiAvailable,
      detail: snapshot.error || "The controller API is responding.",
      Icon: Server,
    },
  ];

  return (
    <div className="page-stack">
      <PageHeader
        title="Connections"
        description="Backend adapters, runtime connections, and capability status."
        action={
          <Button
            variant="ghost"
            size="icon"
            onClick={() => void handleRefresh()}
            disabled={refreshing}
          >
            <RefreshCw className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`} />
          </Button>
        }
      />

      {/* ── Summary stats ─────────────────────────────────────────── */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Cpu className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Backend Adapters</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-semibold">{backends.length}</div>
            <p className="mt-1 text-xs text-muted-foreground">
              {backends.filter((b) => b.available).length} available ·{" "}
              {backends.filter((b) => !b.available).length} offline
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Cable className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Runtime Connections</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-semibold">{connections.length}</div>
            <p className="mt-1 text-xs text-muted-foreground">
              {connections.filter((c) => c.state === "connected").length} connected ·{" "}
              {connections.filter((c) => c.state !== "connected").length} offline
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Server className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">API Health</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-semibold capitalize">{snapshot.connection}</div>
            <p className="mt-1 text-xs text-muted-foreground">
              {apiAvailable ? "All systems nominal" : snapshot.error || "Degraded"}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* ── Fixed capabilities ───────────────────────────────────── */}
      <div className="grid gap-4 lg:grid-cols-2">
        {fixedCapabilities.map((item) => (
          <Card key={item.id}>
            <CardHeader>
              <div className="flex items-start justify-between gap-3">
                <div className="flex min-w-0 items-center gap-3">
                  <div className="grid size-9 shrink-0 place-items-center rounded-md bg-muted">
                    <item.Icon className="size-4" />
                  </div>
                  <div className="min-w-0">
                    <CardTitle className="text-base">{item.label}</CardTitle>
                  </div>
                </div>
                <Badge
                  variant={item.available ? "outline" : "secondary"}
                  className={`text-[10px] ${item.available ? "text-status-available" : "text-status-unavailable"}`}
                >
                  {item.available ? <CheckCircle2 /> : <CircleOff />}
                  {item.available ? "Available" : "Unavailable"}
                </Badge>
              </div>
              <CardDescription className="mt-1">{item.detail}</CardDescription>
            </CardHeader>
          </Card>
        ))}
      </div>

      {/* ── Backend Adapters ──────────────────────────────────────── */}
      {backends.length > 0 && (
        <section>
          <h3 className="mb-3 text-lg font-semibold tracking-tight">
            Backend Adapters
          </h3>
          <div className="grid gap-4 lg:grid-cols-2">
            {backends.map((backend) => (
              <BackendCard key={backend.id} backend={backend} />
            ))}
          </div>
        </section>
      )}

      {/* ── Runtime Connections ────────────────────────────────────── */}
      {connections.length > 0 && (
        <section>
          <h3 className="mb-3 text-lg font-semibold tracking-tight">
            Runtime Connections
          </h3>
          <div className="grid gap-4 lg:grid-cols-2">
            {connections.map((connection) => (
              <ConnectionCard
                key={connection.id}
                connection={connection}
              />
            ))}
          </div>
        </section>
      )}

      {/* ── Empty state ───────────────────────────────────────────── */}
      {backends.length === 0 && connections.length === 0 && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <Cable className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            No connections configured.
          </p>
        </div>
      )}
    </div>
  );
}
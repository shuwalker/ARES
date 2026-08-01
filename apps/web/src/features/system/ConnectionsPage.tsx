import { useCallback, useEffect, useState } from "react";
import {
  Cable,
  CheckCircle2,
  CircleOff,
  Cpu,
  Gauge,
  Network,
  Plus,
  RefreshCw,
  Server,
  Trash2,
  Zap,
  Wrench,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";
import { ConnectionStatusBadge, isBlockingState } from "@/components/ConnectionStatusBadge";
import { useAres } from "@/shared/ares-context";
import type { BackendInfo, RuntimeConnection, WorkerRanking } from "@/shared/contracts";

// ── Helpers ──────────────────────────────────────────────────────────

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
              {backend.state ? (
                <ConnectionStatusBadge state={backend.state} className="mr-0.5" />
              ) : (
                <>
                  <ConnectionStatusBadge
                    state={backend.available ? "connected" : "offline"}
                    showLabel={false}
                    className="mr-1.5"
                  />
                  {backendStatusLabel(backend.available)}
                </>
              )}
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

function ConnectionCard({
  connection,
  selecting,
  testing,
  testResult,
  onSetDefault,
  onTest,
}: {
  connection: RuntimeConnection;
  selecting: boolean;
  testing: boolean;
  testResult?: { ok: boolean; detail: string };
  onSetDefault: (connection: RuntimeConnection) => Promise<void>;
  onTest: (connection: RuntimeConnection) => Promise<void>;
}) {
  const isConnected = connection.state === "connected";

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
              variant={isBlockingState(connection.state) ? "secondary" : "outline"}
              className="text-[10px]"
            >
              <ConnectionStatusBadge state={connection.state} />
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
        {connection.kind === "runtime" && (
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Default runtime</span>
            <Button
              variant={connection.selected ? "secondary" : "outline"}
              size="xs"
              disabled={connection.selected || !connection.available || selecting}
              onClick={() => void onSetDefault(connection)}
            >
              {connection.selected ? "Selected" : selecting ? "Selecting…" : "Use by default"}
            </Button>
          </div>
        )}
        <div className="flex items-center justify-between gap-4 border-t pt-3">
          <span className="text-xs text-muted-foreground">
            Read-only health check
          </span>
          <Button
            variant="outline"
            size="xs"
            disabled={testing}
            onClick={() => void onTest(connection)}
          >
            <Zap className={`mr-1.5 size-3 ${testing ? "animate-pulse" : ""}`} />
            {testing ? "Testing…" : "Test"}
          </Button>
        </div>
        {testResult && (
          <p
            className={`rounded-md border px-3 py-2 text-xs ${
              testResult.ok
                ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
                : "border-destructive/40 bg-destructive/10 text-destructive"
            }`}
            role="status"
          >
            {testResult.detail}
          </p>
        )}
      </CardContent>
    </Card>
  );
}

// ── Page ─────────────────────────────────────────────────────────────

export function ConnectionsPage() {
  const { snapshot, refresh } = useAres();
  const [refreshing, setRefreshing] = useState(false);
  const [selecting, setSelecting] = useState("");
  const [selectionError, setSelectionError] = useState("");
  const [testing, setTesting] = useState("");
  const [testResults, setTestResults] = useState<Record<string, { ok: boolean; detail: string }>>({});
  const [rankings, setRankings] = useState<WorkerRanking[]>([]);
  const [rankingsNote, setRankingsNote] = useState("");
  const [rankingError, setRankingError] = useState("");
  const [providers, setProviders] = useState<Awaited<ReturnType<typeof aresApi.registryProviders>>["providers"]>({});
  const [providerId, setProviderId] = useState("");
  const [providerEndpoint, setProviderEndpoint] = useState("");
  const [providerCredentialEnv, setProviderCredentialEnv] = useState("");
  const [providerError, setProviderError] = useState("");
  const [savingProvider, setSavingProvider] = useState(false);

  const loadProviders = useCallback(async () => {
    try {
      setProviders((await aresApi.registryProviders()).providers);
      setProviderError("");
    } catch (error) {
      setProviderError(readableError(error, "Provider registry could not be loaded."));
    }
  }, []);

  const loadRankings = useCallback(async () => {
    try {
      const data = await aresApi.workerRankings();
      setRankings(data.rankings);
      setRankingsNote(data.note || "");
      setRankingError("");
    } catch (error) {
      setRankingError(readableError(error, "Worker rankings could not be loaded."));
    }
  }, []);

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await refresh();
      await loadRankings();
      await loadProviders();
    } catch (error) {
      setSelectionError(readableError(error, "Connections could not be refreshed."));
    } finally {
      setRefreshing(false);
    }
  }, [refresh, loadRankings, loadProviders]);

  useEffect(() => {
    void loadRankings();
    void loadProviders();
  }, [loadRankings, loadProviders]);

  const handleSaveProvider = useCallback(async () => {
    const id = providerId.trim().toLowerCase();
    if (!id) {
      setProviderError("Provider ID is required.");
      return;
    }
    setSavingProvider(true);
    setProviderError("");
    try {
      await aresApi.saveRegistryProvider(id, {
        enabled: true,
        kind: "runtime",
        endpoint: providerEndpoint.trim(),
        credential_env: providerCredentialEnv.trim(),
        capabilities: ["conversation"],
      });
      setProviderId("");
      setProviderEndpoint("");
      setProviderCredentialEnv("");
      await loadProviders();
      await refresh();
    } catch (error) {
      setProviderError(readableError(error, "Provider connection could not be saved."));
    } finally {
      setSavingProvider(false);
    }
  }, [loadProviders, providerCredentialEnv, providerEndpoint, providerId, refresh]);

  const handleDeleteProvider = useCallback(async (id: string) => {
    try {
      await aresApi.deleteRegistryProvider(id);
      await loadProviders();
      await refresh();
    } catch (error) {
      setProviderError(readableError(error, "Provider connection could not be removed."));
    }
  }, [loadProviders, refresh]);

  const handleTest = useCallback(async (connection: RuntimeConnection) => {
    setTesting(connection.id);
    setTestResults((current) => {
      const next = { ...current };
      delete next[connection.id];
      return next;
    });
    try {
      const result = await aresApi.connectionTest(connection.id);
      setTestResults((current) => ({
        ...current,
        [connection.id]: { ok: result.ok, detail: result.health.message },
      }));
      await refresh();
    } catch (error) {
      setTestResults((current) => ({
        ...current,
        [connection.id]: { ok: false, detail: readableError(error, "Connection test failed.") },
      }));
    } finally {
      setTesting("");
    }
  }, [refresh]);

  const handleSetDefault = useCallback(async (connection: RuntimeConnection) => {
    setSelecting(connection.id);
    setSelectionError("");
    try {
      await aresApi.setDefaultBackend(connection.id);
      await refresh();
    } catch (error) {
      setSelectionError(readableError(error, "The default runtime could not be changed."));
    } finally {
      setSelecting("");
    }
  }, [refresh]);

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
        description="Workers and tools your Companion can use. Status must stay honest — available means verified, not just installed."
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

      {selectionError && (
        <p className="text-sm text-status-unavailable" role="alert">{selectionError}</p>
      )}

      {/* ── Summary stats ─────────────────────────────────────────── */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Cpu className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Worker adapters</CardTitle>
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

      {/* ── Worker effectiveness (Companion technical intelligence) ─ */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">External provider registry</CardTitle>
          <CardDescription>
            Connect independently managed runtimes by full URL. ARES does not own or assign their ports.
            Credentials remain in the named environment or keychain entry.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 md:grid-cols-3">
            <Input
              aria-label="Provider ID"
              placeholder="Provider ID (for example openclaw_local)"
              value={providerId}
              onChange={(event) => setProviderId(event.target.value)}
            />
            <Input
              aria-label="Provider endpoint"
              placeholder="Provider-owned URL"
              value={providerEndpoint}
              onChange={(event) => setProviderEndpoint(event.target.value)}
            />
            <Input
              aria-label="Credential environment name"
              placeholder="Credential env name (optional)"
              value={providerCredentialEnv}
              onChange={(event) => setProviderCredentialEnv(event.target.value)}
            />
          </div>
          <Button onClick={() => void handleSaveProvider()} disabled={savingProvider}>
            <Plus className="size-4" /> Add provider
          </Button>
          {providerError ? <p className="text-sm text-status-unavailable">{providerError}</p> : null}
          <div className="space-y-2">
            {Object.values(providers).map((provider) => (
              <div key={provider.id} className="flex items-center justify-between gap-3 rounded-md border p-3">
                <div className="min-w-0">
                  <p className="font-medium">{provider.id}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {provider.endpoint || "No network endpoint (local/CLI discovery)"}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <Badge variant={provider.enabled ? "outline" : "secondary"}>
                    {provider.enabled ? "Enabled" : "Disabled"}
                  </Badge>
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`Remove ${provider.id}`}
                    onClick={() => void handleDeleteProvider(provider.id)}
                  >
                    <Trash2 className="size-4" />
                  </Button>
                </div>
              </div>
            ))}
            {Object.keys(providers).length === 0 ? (
              <p className="text-sm text-muted-foreground">No external provider is assigned.</p>
            ) : null}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="grid size-9 place-items-center rounded-md bg-muted">
                <Gauge className="size-4" />
              </div>
              <div>
                <CardTitle className="text-base">Worker effectiveness</CardTitle>
                <CardDescription>
                  Companion scores workers on your metrics. Durable memory stays in the Companion journal — not in the workers.
                </CardDescription>
              </div>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-3">
          {rankingError ? (
            <p className="text-sm text-status-unavailable" role="alert">{rankingError}</p>
          ) : rankings.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No evaluations yet. After chat runs, record scores so the Companion can rank Jaeger AI, Ollama, Hermes, and other workers.
            </p>
          ) : (
            <div className="space-y-2">
              {rankings.map((row, index) => (
                <div
                  key={row.workerId}
                  className="flex items-center justify-between gap-3 rounded-md border px-3 py-2 text-sm"
                >
                  <div className="min-w-0">
                    <p className="truncate font-medium">
                      #{index + 1} {row.workerId}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {row.sampleCount} sample{row.sampleCount === 1 ? "" : "s"}
                      {row.lastTaskKind ? ` · last: ${row.lastTaskKind}` : ""}
                    </p>
                  </div>
                  <Badge variant="outline" className="shrink-0 font-mono">
                    {row.effectivenessAvg.toFixed(1)}
                  </Badge>
                </div>
              ))}
            </div>
          )}
          {rankingsNote ? <p className="text-xs text-muted-foreground">{rankingsNote}</p> : null}
        </CardContent>
      </Card>

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
                selecting={selecting === connection.id}
                testing={testing === connection.id}
                testResult={testResults[connection.id]}
                onSetDefault={handleSetDefault}
                onTest={handleTest}
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

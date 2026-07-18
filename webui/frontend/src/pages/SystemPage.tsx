import { useEffect, useState, useCallback } from "react";
import {
  Activity,
  AlertTriangle,
  Brain,
  Check,
  CheckCircle2,
  Clock,
  Cpu,
  Database,
  Globe,
  HardDrive,
  Power,
  RefreshCw,
  Server,
  ShieldCheck,
  Stethoscope,
  X,
} from "lucide-react";
import { apiFetch, readableError } from "@/shared/api-client";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

// ── Types ─────────────────────────────────────────────────────────────

interface StatusResponse {
  version?: string;
  uptime_seconds?: number;
  config_path?: string;
  pid?: number;
  python?: string;
  platform?: string;
  gateway_running?: boolean;
  gateway_state?: string;
  gateway_pid?: number;
  can_update_hermes?: boolean;
  running?: boolean;
  host?: string;
  port?: number;
  url?: string;
  [k: string]: unknown;
}

interface HealthCheckResult {
  status?: string;
  available?: boolean;
  checked_at?: string;
  cpu?: { percent: number } | null;
  memory?: { used_bytes: number; total_bytes: number; percent: number } | null;
  disk?: { used_bytes: number; total_bytes: number; percent: number } | null;
  errors?: { metric: string; code: string }[];
  checks?: Record<string, unknown>;
  [k: string]: unknown;
}

interface AgentHealthResult {
  status?: string;
  agent_running?: boolean;
  uptime_seconds?: number;
  alive?: boolean;
  checked_at?: string;
  details?: {
    gateway_state?: string;
    platform_count?: number;
    platform_states?: Record<string, number>;
    reason?: string;
    [k: string]: unknown;
  };
  [k: string]: unknown;
}

interface ExtensionEntry {
  id: string;
  name?: string;
  description?: string;
  enabled?: boolean;
  user_enabled?: boolean;
  manifest_enabled?: boolean;
  sidecars?: { id: string; name?: string; health_path?: string }[];
  [k: string]: unknown;
}

interface ExtensionStatusResult {
  enabled?: boolean;
  extension_dir_configured?: boolean;
  extension_dir_valid?: boolean;
  script_urls?: string[];
  stylesheet_urls?: string[];
  sidecars?: unknown[];
  counts?: {
    script_urls?: number;
    stylesheet_urls?: number;
    sidecars?: number;
    manifest_extensions?: number;
    user_disabled?: number;
  };
  manifest?: { configured?: boolean; loaded?: boolean; status?: string; entry_count?: number };
  extensions?: ExtensionEntry[];
  warnings?: { code: string; source: string }[];
  [k: string]: unknown;
}

// ── Helpers ────────────────────────────────────────────────────────────

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / (1024 * 1024)).toFixed(1)} MB`;
  return `${(n / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function formatDuration(seconds: number): string {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function statusVariant(ok: boolean | undefined | null) {
  return ok ? "default" : "secondary";
}

function healthBadge(status?: string | null) {
  if (!status) return <Badge variant="secondary">Unknown</Badge>;
  if (status === "ok" || status === "healthy" || status === "running") return <Badge variant="default" className="bg-green-600 text-white">Healthy</Badge>;
  if (status === "partial" || status === "degraded") return <Badge className="bg-yellow-600 text-white">Degraded</Badge>;
  return <Badge variant="destructive">Unhealthy</Badge>;
}

// ── Component ─────────────────────────────────────────────────────────

export default function SystemPage() {
  const [status, setStatus] = useState<StatusResponse | null>(null);
  const [health, setHealth] = useState<HealthCheckResult | null>(null);
  const [agentHealth, setAgentHealth] = useState<AgentHealthResult | null>(null);
  const [extensions, setExtensions] = useState<ExtensionStatusResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [gatewayAction, setGatewayAction] = useState<string | null>(null);

  // Confirmation dialogs
  const [restartConfirm, setRestartConfirm] = useState(false);
  const [shutdownConfirm, setShutdownConfirm] = useState(false);

  const load = useCallback(async () => {
    try {
      const [statusRes, healthRes, agentRes, extRes] = await Promise.allSettled([
        apiFetch<StatusResponse>("/api/dashboard/status"),
        apiFetch<HealthCheckResult>("/api/system/health"),
        apiFetch<AgentHealthResult>("/api/health/agent"),
        apiFetch<ExtensionStatusResult>("/api/extensions/status"),
      ]);
      if (statusRes.status === "fulfilled") setStatus(statusRes.value);
      if (healthRes.status === "fulfilled") setHealth(healthRes.value);
      if (agentRes.status === "fulfilled") setAgentHealth(agentRes.value);
      if (extRes.status === "fulfilled") setExtensions(extRes.value);
    } catch { /* ignore */ }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const runGateway = async (verb: "start" | "stop" | "restart") => {
    setGatewayAction(verb);
    try {
      await apiFetch("/api/health/restart", { method: "POST" });
      setTimeout(load, 3000);
    } catch (e) { alert(readableError(e, `Gateway ${verb} failed`)); }
    finally { setGatewayAction(null); }
  };

  const runShutdown = async () => {
    try {
      await apiFetch("/api/shutdown", { method: "POST" });
    } catch (e) { alert(readableError(e, "Shutdown failed")); }
  };

  const toggleExtension = async (id: string, enabled: boolean) => {
    try {
      const res = await apiFetch<ExtensionStatusResult>("/api/extensions/toggle", {
        method: "POST",
        body: JSON.stringify({ id, enabled }),
      });
      setExtensions(res);
    } catch (e) { alert(readableError(e, "Toggle extension failed")); }
  };

  if (loading) return (
    <div className="page-stack">
      <PageHeader title="System" description="System health and status." />
      <div className="flex items-center justify-center py-12 text-muted-foreground">Loading…</div>
    </div>
  );

  const InfoRow = ({ label, value, icon: Icon }: { label: string; value: string; icon?: typeof Server }) => (
    <div className="flex items-center justify-between py-2 border-b border-border/50 last:border-0">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        {Icon && <Icon className="h-3.5 w-3.5" />}
        {label}
      </div>
      <span className="text-sm font-mono truncate max-w-[60%] text-right">{value || "—"}</span>
    </div>
  );

  // Derived state
  const gatewayRunning = status?.gateway_running ?? agentHealth?.alive;
  const gatewayState = status?.gateway_state ?? agentHealth?.details?.gateway_state;

  return (
    <div className="page-stack">
      <PageHeader
        title="System"
        description="System health, status, and operations."
        action={<Button variant="ghost" size="icon" onClick={load}><RefreshCw className="h-4 w-4" /></Button>}
      />

      {/* ── Health overview cards ────────────────────────────────────── */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <Stethoscope className="h-4 w-4" />
              System Health
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-2">
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">Overall</span>
              {healthBadge(health?.status)}
            </div>
            {health?.cpu && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground flex items-center gap-1"><Cpu className="h-3 w-3" /> CPU</span>
                <span className="text-sm font-mono">{health.cpu.percent.toFixed(1)}%</span>
              </div>
            )}
            {health?.memory && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground flex items-center gap-1"><Server className="h-3 w-3" /> Memory</span>
                <span className="text-sm font-mono">
                  {formatBytes(health.memory.used_bytes)} / {formatBytes(health.memory.total_bytes)} ({health.memory.percent.toFixed(1)}%)
                </span>
              </div>
            )}
            {health?.disk && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground flex items-center gap-1"><HardDrive className="h-3 w-3" /> Disk</span>
                <span className="text-sm font-mono">
                  {formatBytes(health.disk.used_bytes)} / {formatBytes(health.disk.total_bytes)} ({health.disk.percent.toFixed(1)}%)
                </span>
              </div>
            )}
            {health?.errors && health.errors.length > 0 && (
              <div className="mt-1 space-y-1">
                {health.errors.map((err, i) => (
                  <div key={i} className="flex items-center gap-1.5 text-xs text-yellow-500">
                    <AlertTriangle className="h-3 w-3" />
                    {err.metric}: {err.code}
                  </div>
                ))}
              </div>
            )}
            {health?.checked_at && (
              <div className="text-xs text-muted-foreground mt-1">
                Checked {new Date(health.checked_at).toLocaleTimeString()}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <Brain className="h-4 w-4" />
              Agent Health
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-2">
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">Agent</span>
              {agentHealth?.alive ? (
                <Badge className="bg-green-600 text-white">Alive</Badge>
              ) : agentHealth?.status ? (
                <Badge variant="destructive">{agentHealth.status}</Badge>
              ) : (
                <Badge variant="secondary">Unknown</Badge>
              )}
            </div>
            {agentHealth?.details?.gateway_state && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Gateway state</span>
                <span className="text-sm font-mono">{agentHealth.details.gateway_state}</span>
              </div>
            )}
            {agentHealth?.details?.platform_count !== undefined && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Platforms</span>
                <span className="text-sm font-mono">{agentHealth.details.platform_count}</span>
              </div>
            )}
            {agentHealth?.details?.platform_states && Object.keys(agentHealth.details.platform_states).length > 0 && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Platform states</span>
                <div className="flex gap-1 flex-wrap justify-end">
                  {Object.entries(agentHealth.details.platform_states).map(([state, count]) => (
                    <Badge key={state} variant="outline" className="text-xs">{state}: {count as number}</Badge>
                  ))}
                </div>
              </div>
            )}
            {agentHealth?.checked_at && (
              <div className="text-xs text-muted-foreground mt-1">
                Checked {new Date(agentHealth.checked_at).toLocaleTimeString()}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <Power className="h-4 w-4" />
              Gateway
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-2">
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">Status</span>
              <Badge variant={statusVariant(gatewayRunning)}>
                {gatewayRunning ? "Running" : "Stopped"}
              </Badge>
            </div>
            {gatewayState && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">State</span>
                <span className="text-sm font-mono">{gatewayState}</span>
              </div>
            )}
            {status?.gateway_pid && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">PID</span>
                <span className="text-sm font-mono">{status.gateway_pid}</span>
              </div>
            )}
            {status?.url && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">URL</span>
                <a href={status.url} target="_blank" rel="noreferrer" className="text-xs text-primary hover:underline truncate max-w-[60%]">{status.url}</a>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ── System info ──────────────────────────────────────────────── */}
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <Server className="h-4 w-4" />
              Status
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-0">
            <InfoRow label="Version" value={status?.version ?? "—"} icon={Activity} />
            <InfoRow label="Uptime" value={status?.uptime_seconds ? formatDuration(status.uptime_seconds) : "—"} icon={Clock} />
            <InfoRow label="PID" value={status?.pid?.toString() ?? "—"} />
            <InfoRow label="Python" value={status?.python ?? "—"} />
            <InfoRow label="Platform" value={status?.platform ?? "—"} icon={Cpu} />
            <InfoRow label="Config path" value={status?.config_path ?? "—"} />
            <InfoRow label="Gateway" value={gatewayRunning ? "Running" : "Stopped"} icon={Power} />
          </CardContent>
        </Card>

        {/* ── Gateway control ─────────────────────────────────────── */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <Activity className="h-4 w-4" />
              Gateway Control
            </CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <div className="flex items-center gap-2">
              <Badge variant={statusVariant(gatewayRunning)}>{gatewayRunning ? "Running" : "Stopped"}</Badge>
              {gatewayState && <span className="text-xs text-muted-foreground">{gatewayState}</span>}
            </div>
            <div className="flex flex-wrap gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={() => runGateway("start")}
                disabled={!!gatewayAction || !!gatewayRunning}
              >
                {gatewayAction === "start" ? "Starting…" : "Start"}
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setRestartConfirm(true)}
                disabled={!!gatewayAction}
              >
                {gatewayAction === "restart" ? "Restarting…" : "Restart"}
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setShutdownConfirm(true)}
                disabled={!!gatewayAction}
              >
                Stop
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              Restart or stop the gateway process. Operations may briefly interrupt active sessions.
            </p>
          </CardContent>
        </Card>
      </div>

      {/* ── Diagnostics checklist ───────────────────────────────────── */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm flex items-center gap-2">
            <ShieldCheck className="h-4 w-4" />
            Diagnostics
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-2">
            {[
              { label: "System health endpoint", ok: health?.status === "ok" || health?.status === "partial", detail: health?.status === "ok" ? "All systems healthy" : health?.status === "partial" ? "Some metrics unavailable" : health?.status ?? "Not reachable" },
              { label: "Agent process", ok: agentHealth?.alive === true, detail: agentHealth?.alive ? "Agent is alive" : agentHealth?.status ?? "Not reachable" },
              { label: "Gateway running", ok: gatewayRunning === true, detail: gatewayRunning ? "Gateway is running" : gatewayState ?? "Gateway is not running" },
              { label: "CPU metrics", ok: health?.cpu != null, detail: health?.cpu ? `${health.cpu.percent.toFixed(1)}% usage` : "Unavailable" },
              { label: "Memory metrics", ok: health?.memory != null, detail: health?.memory ? `${health.memory.percent.toFixed(1)}% used` : "Unavailable" },
              { label: "Disk metrics", ok: health?.disk != null, detail: health?.disk ? `${health.disk.percent.toFixed(1)}% used` : "Unavailable" },
              { label: "Extensions loaded", ok: extensions?.enabled === true, detail: extensions?.enabled ? `${extensions.extensions?.length ?? 0} extension(s)` : "Not configured" },
            ].map((check, i) => (
              <div key={i} className="flex items-center justify-between py-2 border-b border-border/50 last:border-0">
                <div className="flex items-center gap-2">
                  {check.ok
                    ? <CheckCircle2 className="h-4 w-4 text-green-500" />
                    : <X className="h-4 w-4 text-red-500" />}
                  <span className="text-sm">{check.label}</span>
                </div>
                <span className="text-xs text-muted-foreground">{check.detail}</span>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* ── Extensions ──────────────────────────────────────────────── */}
      {extensions && extensions.extensions && extensions.extensions.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <Globe className="h-4 w-4" />
              Extensions
              <Badge variant="outline" className="ml-1">{extensions.extensions.length}</Badge>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid gap-3">
              {extensions.extensions.map((ext) => {
                const isUserEnabled = ext.user_enabled !== false;
                const isManifestEnabled = ext.manifest_enabled !== false;
                const effectivelyEnabled = isUserEnabled && isManifestEnabled;
                return (
                  <div
                    key={ext.id}
                    className="flex items-center justify-between gap-4 py-2 border-b border-border/50 last:border-0"
                  >
                    <div className="flex flex-col min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium truncate">{ext.name || ext.id}</span>
                        {!isManifestEnabled && (
                          <Badge variant="secondary" className="text-xs">manifest disabled</Badge>
                        )}
                      </div>
                      {ext.description && (
                        <span className="text-xs text-muted-foreground truncate max-w-[400px]">{ext.description}</span>
                      )}
                    </div>
                    <div className="flex items-center gap-3 shrink-0">
                      <Badge variant={effectivelyEnabled ? "default" : "secondary"}>
                        {effectivelyEnabled ? "On" : "Off"}
                      </Badge>
                      <ToggleSwitch
                        checked={isUserEnabled}
                        onCheckedChange={(checked) => toggleExtension(ext.id, checked)}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
            {extensions.warnings && extensions.warnings.length > 0 && (
              <div className="mt-3 space-y-1">
                {extensions.warnings.map((w, i) => (
                  <div key={i} className="flex items-center gap-1.5 text-xs text-yellow-500">
                    <AlertTriangle className="h-3 w-3" />
                    {w.code} ({w.source})
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* ── Restart confirmation ─────────────────────────────────────── */}
      <AlertDialog open={restartConfirm} onOpenChange={setRestartConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Restart gateway?</AlertDialogTitle>
            <AlertDialogDescription>
              This will restart the gateway process. Active sessions may be briefly interrupted.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => { setRestartConfirm(false); runGateway("restart"); }}
            >
              Restart
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* ── Shutdown confirmation ─────────────────────────────────────── */}
      <AlertDialog open={shutdownConfirm} onOpenChange={setShutdownConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Stop gateway?</AlertDialogTitle>
            <AlertDialogDescription>
              This will stop the gateway process. The WebUI will lose connection until the gateway is restarted manually.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-white hover:bg-destructive/90"
              onClick={() => { setShutdownConfirm(false); runGateway("stop"); }}
            >
              Stop
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
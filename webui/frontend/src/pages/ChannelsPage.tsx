import { useCallback, useEffect, useState } from "react";
import {
  Bot,
  CheckCircle2,
  CircleOff,
  LoaderCircle,
  MessageSquare,
  Phone,
  RefreshCw,
  Share2,
  Zap,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import { readableError } from "@/shared/api-client";
import type { RuntimeConnection } from "@/shared/contracts";

// ── Channel icon by kind ────────────────────────────────────────────────

const CHANNEL_ICONS: Record<string, typeof Bot> = {
  telegram: MessageSquare,
  slack: Share2,
  discord: Bot,
  sms: Phone,
  whatsapp: Phone,
  default: Zap,
};

function channelIcon(kind: string) {
  const key = kind.toLowerCase();
  for (const [prefix, Icon] of Object.entries(CHANNEL_ICONS)) {
    if (key.includes(prefix) || prefix === "default") return Icon;
  }
  return Zap;
}

// ── State labels ────────────────────────────────────────────────────────

function stateLabel(state: RuntimeConnection["state"]): string {
  switch (state) {
    case "connected":
      return "Connected";
    case "needs_attention":
      return "Needs Attention";
    case "offline":
      return "Offline";
    default:
      return "Unknown";
  }
}

function stateVariant(
  state: RuntimeConnection["state"],
): "default" | "secondary" | "destructive" | "outline" {
  switch (state) {
    case "connected":
      return "default";
    case "needs_attention":
      return "secondary";
    case "offline":
      return "outline";
    default:
      return "outline";
  }
}

// ── Page component ─────────────────────────────────────────────────────

export function ChannelsPage() {
  const { snapshot, refresh } = useAres();
  const [channels, setChannels] = useState<RuntimeConnection[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [testing, setTesting] = useState<Record<string, boolean>>({});
  const [testResults, setTestResults] = useState<Record<string, { ok: boolean; detail: string }>>({});
  const [toggling, setToggling] = useState<Record<string, boolean>>({});

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.channelsList();
      setChannels(data);
    } catch (e) {
      setError(readableError(e, "Failed to load channels."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // ── Test connection ──────────────────────────────────────────────
  async function handleTest(connectionId: string) {
    setTesting((prev) => ({ ...prev, [connectionId]: true }));
    setTestResults((prev) => {
      const next = { ...prev };
      delete next[connectionId];
      return next;
    });
    try {
      const result = await aresApi.channelTest(connectionId);
      const ok = Boolean(result.ok ?? result.success ?? (result as Record<string, unknown>).status === "ok");
      setTestResults((prev) => ({
        ...prev,
        [connectionId]: {
          ok,
          detail: String((result as Record<string, unknown>).message ?? (result as Record<string, unknown>).detail ?? (ok ? "Connection test passed." : "Connection test failed.")),
        },
      }));
    } catch (e) {
      setTestResults((prev) => ({
        ...prev,
        [connectionId]: { ok: false, detail: readableError(e, "Test failed.") },
      }));
    } finally {
      setTesting((prev) => ({ ...prev, [connectionId]: false }));
    }
  }

  // ── Connect / Disconnect toggle ───────────────────────────────────
  async function handleToggle(connectionId: string, currentlyConnected: boolean) {
    setToggling((prev) => ({ ...prev, [connectionId]: true }));
    try {
      if (currentlyConnected) {
        await aresApi.channelDisconnect(connectionId);
      } else {
        await aresApi.channelConnect(connectionId);
      }
      // Refresh both local state and global snapshot
      await load();
      refresh();
    } catch (e) {
      setError(readableError(e, currentlyConnected ? "Failed to disconnect." : "Failed to connect."));
    } finally {
      setToggling((prev) => ({ ...prev, [connectionId]: false }));
    }
  }

  // ── Render ─────────────────────────────────────────────────────────
  if (loading && channels.length === 0) {
    return (
      <div className="page-stack">
        <PageHeader title="Channels" description="Manage messaging channel integrations — Telegram, Slack, Discord, SMS, and more." />
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading channels…</p>
        </div>
      </div>
    );
  }

  const isRefreshing = loading && channels.length > 0;

  return (
    <div className="page-stack">
      <PageHeader
        title="Channels"
        description="Manage messaging channel integrations — Telegram, Slack, Discord, SMS, and more."
        action={
          <Button variant="outline" size="sm" onClick={() => void load()} disabled={loading}>
            <RefreshCw className={`mr-1.5 size-3.5 ${isRefreshing ? "animate-spin" : ""}`} />
            Refresh
          </Button>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      {channels.length === 0 && !error && (
        <div className="rounded-md border border-border bg-card px-4 py-8 text-center text-sm text-muted-foreground">
          No channels configured. Channels appear here once they are added in your ARES configuration.
        </div>
      )}

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {channels.map((channel) => {
          const Icon = channelIcon(channel.kind || channel.name);
          const connected = channel.state === "connected";
          const isToggling = toggling[channel.id] ?? false;
          const isTesting = testing[channel.id] ?? false;
          const testResult = testResults[channel.id];

          return (
            <Card key={channel.id}>
              <CardHeader>
                <div className="flex items-start justify-between gap-3">
                  <div className="grid size-9 place-items-center rounded-md bg-muted">
                    <Icon className="size-4" />
                  </div>
                  <Badge
                    variant={stateVariant(channel.state)}
                    className={
                      connected
                        ? "text-status-available"
                        : channel.state === "needs_attention"
                          ? "text-status-limited"
                          : "text-status-unavailable"
                    }
                  >
                    {connected ? <CheckCircle2 /> : <CircleOff />}
                    {stateLabel(channel.state)}
                  </Badge>
                </div>
                <CardTitle className="mt-2 text-base">{channel.name}</CardTitle>
                <CardDescription className="text-xs">{channel.detail}</CardDescription>
              </CardHeader>
              <CardContent className="flex flex-col gap-3 pt-0">
                {/* Capabilities */}
                {channel.capabilities.length > 0 && (
                  <div className="flex flex-wrap gap-1">
                    {channel.capabilities.map((cap) => (
                      <Badge key={cap} variant="outline" className="text-[10px] font-mono">
                        {cap}
                      </Badge>
                    ))}
                  </div>
                )}

                {/* Actions */}
                <div className="flex items-center gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    className="flex-1"
                    disabled={isTesting || isToggling}
                    onClick={() => void handleTest(channel.id)}
                  >
                    {isTesting ? (
                      <>
                        <LoaderCircle className="mr-1.5 size-3.5 animate-spin" />
                        Testing…
                      </>
                    ) : (
                      <>
                        <Zap className="mr-1.5 size-3.5" />
                        Test
                      </>
                    )}
                  </Button>

                  <div className="flex items-center gap-2">
                    <ToggleSwitch
                      checked={connected}
                      onCheckedChange={() => void handleToggle(channel.id, connected)}
                      disabled={isToggling || isTesting}
                      aria-label={connected ? "Disconnect" : "Connect"}
                    />
                    {isToggling && (
                      <LoaderCircle className="size-3.5 animate-spin text-muted-foreground" />
                    )}
                  </div>
                </div>

                {/* Test result */}
                {testResult && (
                  <div
                    className={`rounded-md border px-3 py-2 text-xs ${
                      testResult.ok
                        ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
                        : "border-destructive/40 bg-destructive/10 text-destructive"
                    }`}
                  >
                    {testResult.detail}
                  </div>
                )}
              </CardContent>
            </Card>
          );
        })}
      </div>

      {/* Also show runtime connections from snapshot that aren't in the channel list */}
      {snapshot.connections.length > 0 && (
        <>
          <h3 className="mt-8 text-lg font-semibold tracking-tight">Runtime Connections</h3>
          <p className="mb-4 text-sm text-muted-foreground">
            Active backend and tool connections reported by the ARES controller.
          </p>
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            {snapshot.connections
              .filter((conn) => !channels.some((ch) => ch.id === conn.id))
              .map((conn) => {
                const Icon = channelIcon(conn.kind);
                const available = conn.state === "connected";
                return (
                  <Card key={conn.id}>
                    <CardHeader>
                      <div className="flex items-start justify-between gap-3">
                        <div className="grid size-9 place-items-center rounded-md bg-muted">
                          <Icon className="size-4" />
                        </div>
                        <Badge
                          variant="outline"
                          className={
                            available
                              ? "text-status-available"
                              : conn.state === "needs_attention"
                                ? "text-status-limited"
                                : "text-status-unavailable"
                          }
                        >
                          {available ? <CheckCircle2 /> : <CircleOff />}
                          {available ? "available" : conn.state === "needs_attention" ? "limited" : "unavailable"}
                        </Badge>
                      </div>
                      <CardTitle className="mt-2 text-base">
                        {conn.name}
                        {conn.selected ? " · selected" : ""}
                      </CardTitle>
                      <CardDescription className="text-xs">{conn.detail}</CardDescription>
                    </CardHeader>
                  </Card>
                );
              })}
          </div>
        </>
      )}
    </div>
  );
}

export default ChannelsPage;
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ArrowLeft,
  Cpu,
  CheckCircle2,
  CircleOff,
  LoaderCircle,
  RefreshCw,
  Wrench,
} from "lucide-react";
import { useParams, useNavigate } from "react-router-dom";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";
import type { BackendInfo } from "@/shared/contracts";

// ── Adapter detail types ───────────────────────────────────────────────

interface AdapterTool {
  name: string;
  description?: string;
  enabled?: boolean;
}

interface AdapterInfo {
  available: boolean;
  label: string;
  health: { status?: string; latency_ms?: number; [k: string]: unknown };
  identity_projection: {
    name?: string;
    description?: string;
    avatar_state?: string;
    [k: string]: unknown;
  };
  capabilities: {
    chat?: boolean;
    tools?: boolean;
    persona?: boolean;
    [k: string]: unknown;
  };
  chat_session_support: {
    streaming?: boolean;
    context_window?: number;
    multimodal?: boolean;
    [k: string]: unknown;
  };
  tools: AdapterTool[];
  settings_schema: { type?: string; properties?: Record<string, unknown>; [k: string]: unknown };
}

// ── Helpers ────────────────────────────────────────────────────────────

function providerDisplayName(id: string): string {
  if (!id) return "Unknown";
  const map: Record<string, string> = {
    openai: "OpenAI",
    anthropic: "Anthropic",
    google: "Google",
    openrouter: "OpenRouter",
    ollama: "Ollama",
    ollama_cloud: "Ollama Cloud",
    groq: "Groq",
    xai: "xAI",
    mistral: "Mistral",
    deepseek: "DeepSeek",
    copilot: "GitHub Copilot",
    local: "Local",
    custom: "Custom",
  };
  return map[id.toLowerCase()] || id;
}

// ── Component ──────────────────────────────────────────────────────────

export default function AgentDetailPage() {
  const { id: backendId } = useParams<{ id: string }>();
  const navigate = useNavigate();

  const [backends, setBackends] = useState<BackendInfo[]>([]);
  const [adapter, setAdapter] = useState<AdapterInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [togglingTool, setTogglingTool] = useState<string | null>(null);

  const decodedId = decodeURIComponent(backendId ?? "");

  // ── Load ─────────────────────────────────────────────────────────────

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [backendData, adapterData] = await Promise.allSettled([
        aresApi.backends(),
        aresApi.listAdapters(),
      ]);
      if (backendData.status === "fulfilled") setBackends(backendData.value);
      if (adapterData.status === "fulfilled") {
        const adapters = adapterData.value;
        const entry = adapters[decodedId] as unknown;
        if (entry) {
          setAdapter(entry as AdapterInfo);
        }
      }
      const failed = [backendData, adapterData].find((r) => r.status === "rejected");
      if (failed && failed.status === "rejected") {
        setError(readableError(failed.reason, "Failed to load agent data."));
      }
    } catch (err) {
      setError(readableError(err, "Failed to load agent data."));
    } finally {
      setLoading(false);
    }
  }, [decodedId]);

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

  // ── Toggle tool ──────────────────────────────────────────────────────

  const handleToggleTool = useCallback(async (toolName: string, currentlyEnabled: boolean) => {
    setTogglingTool(toolName);
    // Optimistic update
    setAdapter((prev) => {
      if (!prev) return prev;
      return {
        ...prev,
        tools: prev.tools.map((t) =>
          t.name === toolName ? { ...t, enabled: !currentlyEnabled } : t,
        ),
      };
    });
    try {
      // No direct API for tool toggle yet — refresh to get server truth
      await load();
    } catch {
      // Revert on failure
      setAdapter((prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          tools: prev.tools.map((t) =>
            t.name === toolName ? { ...t, enabled: currentlyEnabled } : t,
          ),
        };
      });
    } finally {
      setTogglingTool(null);
    }
  }, [load]);

  // ── Derived ──────────────────────────────────────────────────────────

  const backend = useMemo(
    () => backends.find((b) => b.id === decodedId),
    [backends, decodedId],
  );

  const enabledTools = useMemo(
    () => (adapter?.tools ?? []).filter((t) => t.enabled !== false).length,
    [adapter],
  );

  // ── Loading ───────────────────────────────────────────────────────────

  if (loading) {
    return (
      <div className="page-stack">
        <PageHeader title="Agent Detail" description="Loading…" />
        <div className="flex items-center justify-center py-16 text-muted-foreground">
          <LoaderCircle className="mr-2 size-5 animate-spin" />
          Loading…
        </div>
      </div>
    );
  }

  if (!backend && !adapter) {
    return (
      <div className="page-stack">
        <PageHeader title="Agent Not Found" description={`No backend found for "${decodedId}".`} />
        <Button variant="outline" onClick={() => navigate("/agents")}>
          <ArrowLeft className="mr-2 size-4" />
          Back to Agents
        </Button>
      </div>
    );
  }

  const name = backend?.name || adapter?.label || decodedId;
  const available = backend?.available ?? adapter?.available ?? false;
  const deployment = backend?.deployment || "default";

  return (
    <div className="page-stack">
      <PageHeader
        title={name}
        description={backend?.description || adapter?.identity_projection?.description || `Backend: ${decodedId}`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="icon" onClick={() => void handleRefresh()} disabled={refreshing}>
              <RefreshCw className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`} />
            </Button>
            <Button variant="outline" size="sm" onClick={() => navigate("/agents")}>
              <ArrowLeft className="mr-2 size-4" />
              Back
            </Button>
          </div>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <span className="inline-flex items-center gap-2">
            <CircleOff className="size-4" />
            {error}
          </span>
        </div>
      )}

      {/* Status overview */}
      <Card className="ring-1 ring-primary/40">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2">
            <Cpu className="h-4 w-4 text-primary" />
            <CardTitle className="text-sm">Status</CardTitle>
          </div>
        </CardHeader>
        <CardContent className="grid gap-3 text-sm">
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Availability</span>
            <Badge variant={available ? "outline" : "secondary"} className="text-xs">
              <span className={`mr-1.5 inline-block size-1.5 rounded-full ${available ? "bg-emerald-500" : "bg-muted-foreground/50"}`} />
              {available ? "Available" : "Unavailable"}
            </Badge>
          </div>
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">ID</span>
            <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs">{decodedId}</code>
          </div>
          <div className="flex items-center justify-between gap-4">
            <span className="text-muted-foreground">Deployment</span>
            <span className="text-xs">{deployment}</span>
          </div>
          {backend?.adapter && (
            <div className="flex items-center justify-between gap-4">
              <span className="text-muted-foreground">Adapter</span>
              <code className="rounded bg-muted px-2 py-0.5 font-mono text-xs">{backend.adapter}</code>
            </div>
          )}
          {adapter?.health && (
            <div className="flex items-center justify-between gap-4">
              <span className="text-muted-foreground">Health</span>
              <Badge variant={adapter.health.status === "ok" ? "outline" : "secondary"} className="text-xs">
                {adapter.health.status === "ok" ? (
                  <CheckCircle2 className="mr-1 size-3 text-emerald-500" />
                ) : (
                  <CircleOff className="mr-1 size-3" />
                )}
                {adapter.health.status ?? "unknown"}
                {adapter.health.latency_ms != null && ` · ${adapter.health.latency_ms.toFixed(0)}ms`}
              </Badge>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Identity & Capabilities */}
      {adapter && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Identity & Capabilities</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-3 text-sm">
            {adapter.identity_projection?.name && (
              <div className="flex items-center justify-between gap-4">
                <span className="text-muted-foreground">Name</span>
                <span className="text-xs">{adapter.identity_projection.name}</span>
              </div>
            )}
            {adapter.identity_projection?.description && (
              <div className="flex items-center justify-between gap-4">
                <span className="text-muted-foreground">Description</span>
                <span className="text-xs max-w-[70%] text-right">{adapter.identity_projection.description}</span>
              </div>
            )}
            <div className="flex items-center justify-between gap-4">
              <span className="text-muted-foreground">Chat</span>
              <Badge variant={adapter.capabilities?.chat ? "outline" : "secondary"} className="text-xs">
                {adapter.capabilities?.chat ? "Supported" : "Not supported"}
              </Badge>
            </div>
            <div className="flex items-center justify-between gap-4">
              <span className="text-muted-foreground">Tools</span>
              <Badge variant={adapter.capabilities?.tools ? "outline" : "secondary"} className="text-xs">
                {adapter.capabilities?.tools ? "Supported" : "Not supported"}
              </Badge>
            </div>
            <div className="flex items-center justify-between gap-4">
              <span className="text-muted-foreground">Persona</span>
              <Badge variant={adapter.capabilities?.persona ? "outline" : "secondary"} className="text-xs">
                {adapter.capabilities?.persona ? "Supported" : "Not supported"}
              </Badge>
            </div>
            {adapter.chat_session_support && (
              <>
                <div className="flex items-center justify-between gap-4">
                  <span className="text-muted-foreground">Streaming</span>
                  <Badge variant={adapter.chat_session_support.streaming ? "outline" : "secondary"} className="text-xs">
                    {adapter.chat_session_support.streaming ? "Yes" : "No"}
                  </Badge>
                </div>
                {adapter.chat_session_support.context_window != null && (
                  <div className="flex items-center justify-between gap-4">
                    <span className="text-muted-foreground">Context Window</span>
                    <span className="text-xs font-mono">
                      {adapter.chat_session_support.context_window.toLocaleString()} tokens
                    </span>
                  </div>
                )}
                <div className="flex items-center justify-between gap-4">
                  <span className="text-muted-foreground">Multimodal</span>
                  <Badge variant={adapter.chat_session_support.multimodal ? "outline" : "secondary"} className="text-xs">
                    {adapter.chat_session_support.multimodal ? "Yes" : "No"}
                  </Badge>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      )}

      {/* Parameters / Settings Schema */}
      {adapter?.settings_schema?.properties && Object.keys(adapter.settings_schema.properties).length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Parameters</CardTitle>
            <CardDescription>Configuration schema for this backend.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-2 text-sm">
            {Object.entries(adapter.settings_schema.properties).map(([key, schema]) => {
              const prop = schema as Record<string, unknown>;
              return (
                <div key={key} className="flex items-center justify-between gap-4 rounded-md border px-3 py-2">
                  <div className="min-w-0">
                    <span className="font-mono text-xs font-semibold">{key}</span>
                    {typeof prop.description === "string" && prop.description.length > 0 && (
                      <p className="text-xs text-muted-foreground truncate">{prop.description}</p>
                    )}
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <Badge variant="secondary" className="text-[10px] font-mono">
                      {String(prop.type ?? "any")}
                    </Badge>
                    {prop.default !== undefined && (
                      <code className="rounded bg-muted px-1.5 py-0.5 text-[10px] font-mono">
                        {JSON.stringify(prop.default)}
                      </code>
                    )}
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      {/* Models (if available from backend list) */}
      {backend?.models && Array.isArray(backend.models) && backend.models.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Wrench className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Models</CardTitle>
              <Badge variant="secondary" className="text-xs">
                {backend.models.length}
              </Badge>
            </div>
          </CardHeader>
          <CardContent className="grid gap-2">
            {backend.models.map((model: { id: string; label?: string; available?: boolean; [k: string]: unknown }, idx: number) => (
              <div
                key={model.id || idx}
                className="flex items-center justify-between gap-4 rounded-md border px-3 py-2"
              >
                <div className="min-w-0">
                  <span className="text-sm font-mono font-semibold">{model.label || model.id}</span>
                  <p className="text-xs text-muted-foreground font-mono">{model.id}</p>
                </div>
                <Badge variant={model.available !== false ? "outline" : "secondary"} className="text-[10px]">
                  {model.available !== false ? "Available" : "Unavailable"}
                </Badge>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* Tools */}
      {adapter && adapter.tools && adapter.tools.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Wrench className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Tools</CardTitle>
              <Badge variant="secondary" className="text-xs">
                {enabledTools}/{adapter.tools.length} enabled
              </Badge>
            </div>
            <CardDescription>
              Enable or disable tools for this backend.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-2">
            {adapter.tools.map((tool) => {
              const enabled = tool.enabled !== false;
              const isToggling = togglingTool === tool.name;
              return (
                <div
                  key={tool.name}
                  className="flex items-center justify-between gap-4 rounded-md border px-3 py-2"
                >
                  <div className="min-w-0">
                    <span className="text-sm font-mono font-semibold">{tool.name}</span>
                    {tool.description && (
                      <p className="text-xs text-muted-foreground truncate">{tool.description}</p>
                    )}
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <Badge
                      variant={enabled ? "outline" : "secondary"}
                      className={
                        enabled
                          ? "text-emerald-700 dark:text-emerald-300"
                          : "text-amber-700 dark:text-amber-300"
                      }
                    >
                      <span
                        className={`mr-1.5 inline-block size-1.5 rounded-full ${
                          enabled ? "bg-emerald-500" : "bg-amber-500"
                        }`}
                      />
                      {enabled ? "Enabled" : "Disabled"}
                    </Badge>
                    {isToggling ? (
                      <LoaderCircle className="size-4 animate-spin text-muted-foreground" />
                    ) : (
                      <ToggleSwitch
                        checked={enabled}
                        onCheckedChange={() => void handleToggleTool(tool.name, enabled)}
                        aria-label={enabled ? `Disable ${tool.name}` : `Enable ${tool.name}`}
                      />
                    )}
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
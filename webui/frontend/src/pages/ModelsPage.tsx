import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Brain,
  Check,
  Eye,
  FlaskConical,
  Heart,
  Loader2,
  RefreshCw,
  Star,
  Wrench,
} from "lucide-react";
import { apiFetch, readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

// ── Types ──────────────────────────────────────────────────────────

interface ModelGroupEntry {
  id: string;
  label?: string;
  context_window?: number;
  max_output_tokens?: number;
  capabilities?: {
    reasoning?: { allowed_options?: string[] };
    vision?: boolean;
    tools?: boolean;
    [k: string]: unknown;
  };
  service_tier?: string;
  [k: string]: unknown;
}

interface ModelGroup {
  provider: string;
  provider_id: string;
  models: ModelGroupEntry[];
  extra_models?: ModelGroupEntry[];
  [k: string]: unknown;
}

interface ModelsCatalogResponse {
  active_provider?: string | null;
  default_model?: string;
  default_provider?: string;
  configured_model_badges?: Record<string, unknown>;
  groups: ModelGroup[];
  aliases?: Record<string, unknown>;
}

interface ReasoningResponse {
  show_reasoning: boolean;
  reasoning_effort: string;
  supported_efforts: string[];
  supports_reasoning_effort: boolean;
}

interface InsightsModelEntry {
  model: string;
  provider: string;
  sessions: number;
  input_tokens: number;
  output_tokens: number;
  cache_read_tokens?: number;
  reasoning_tokens?: number;
  api_calls?: number;
  avg_tokens_per_session?: number;
}

interface InsightsResponse {
  models: InsightsModelEntry[];
  daily: {
    date: string;
    input_tokens: number;
    output_tokens: number;
    cache_read_tokens?: number;
    sessions: number;
    cost: number;
  }[];
  skills: { name: string; invocations: number }[];
  period_days: number;
  total_sessions: number;
  total_input_tokens: number;
  total_output_tokens: number;
  total_cost: number;
}

// ── Helpers ────────────────────────────────────────────────────────

const EFFORT_LABELS: Record<string, string> = {
  none: "Off",
  minimal: "Minimal",
  low: "Low",
  medium: "Medium",
  high: "High",
  xhigh: "Extra High",
  max: "Max",
};

function shortModelName(model: string): string {
  const idx = model.indexOf("/");
  return idx > 0 ? model.slice(idx + 1) : model;
}

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

function providerDisplayName(providerId: string): string {
  if (!providerId) return "Unknown";
  const map: Record<string, string> = {
    openai: "OpenAI",
    anthropic: "Anthropic",
    google: "Google",
    openrouter: "OpenRouter",
    ollama: "Ollama",
    ollama_cloud: "Ollama Cloud",
    "ollama-cloud": "Ollama Cloud",
    ollama_local: "Ollama Local",
    "ollama-local": "Ollama Local",
    groq: "Groq",
    xai: "xAI",
    mistral: "Mistral",
    deepseek: "DeepSeek",
    copilot: "GitHub Copilot",
    "github-copilot": "GitHub Copilot",
    local: "Local",
    custom: "Custom",
  };
  return map[providerId.toLowerCase()] || providerId;
}

// ── Component ──────────────────────────────────────────────────────

export default function ModelsPage() {
  // Catalog state
  const [catalog, setCatalog] = useState<ModelsCatalogResponse | null>(null);
  const [insights, setInsights] = useState<InsightsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [period, setPeriod] = useState(30);

  // Reasoning state
  const [reasoning, setReasoning] = useState<ReasoningResponse | null>(null);
  const [reasoningSaving, setReasoningSaving] = useState(false);

  // Refresh state
  const [refreshing, setRefreshing] = useState<string | null>(null);

  // Set-default state
  const [settingDefault, setSettingDefault] = useState<string | null>(null);

  // ── Data loading ───────────────────────────────────────────────

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [insightsRes, catalogRes, reasoningRes] = await Promise.allSettled([
        apiFetch<InsightsResponse>(`/api/insights?days=${period}`),
        apiFetch<ModelsCatalogResponse>("/api/models"),
        apiFetch<ReasoningResponse>("/api/reasoning"),
      ]);
      if (insightsRes.status === "fulfilled") setInsights(insightsRes.value);
      if (catalogRes.status === "fulfilled") setCatalog(catalogRes.value);
      if (reasoningRes.status === "fulfilled") setReasoning(reasoningRes.value);
      const failed = [insightsRes, catalogRes, reasoningRes].find(
        (r) => r.status === "rejected",
      );
      if (failed && failed.status === "rejected")
        setError(readableError(failed.reason, "Failed to load model data"));
    } catch (e) {
      setError(readableError(e, "Failed to load model data"));
    } finally {
      setLoading(false);
    }
  }, [period]);

  useEffect(() => {
    load();
  }, [load]);

  // ── Derived data ──────────────────────────────────────────────

  const defaultModel = catalog?.default_model ?? "";
  const defaultProvider = catalog?.default_provider ?? catalog?.active_provider ?? "";

  const usageMap = useMemo(() => {
    const map = new Map<string, InsightsModelEntry>();
    if (!insights?.models) return map;
    for (const m of insights.models) {
      map.set(`${m.provider}/${m.model}`, m);
    }
    return map;
  }, [insights]);

  const groups = catalog?.groups ?? [];

  // ── Reasoning effort change ───────────────────────────────────

  const handleReasoningEffort = useCallback(
    async (effort: string) => {
      if (!reasoning) return;
      setReasoningSaving(true);
      try {
        const res = await apiFetch<ReasoningResponse>("/api/reasoning", {
          method: "POST",
          body: JSON.stringify({ effort }),
        });
        setReasoning(res);
      } catch {
        // Keep existing state on error
      } finally {
        setReasoningSaving(false);
      }
    },
    [reasoning],
  );

  // ── Set default model ───────────────────────────────────────────

  const handleSetDefault = useCallback(
    async (model: string, provider: string) => {
      setSettingDefault(`${provider}/${model}`);
      try {
        await aresApi.setDefaultModel(model, provider);
        await load();
      } catch {
        // Silently fail — UI will reflect on next load
      } finally {
        setSettingDefault(null);
      }
    },
    [load],
  );

  // ── Refresh provider models ────────────────────────────────────

  const handleRefresh = useCallback(
    async (provider: string) => {
      setRefreshing(provider);
      try {
        await aresApi.modelsReload(provider);
        await load();
      } catch {
        // Silently fail
      } finally {
        setRefreshing(null);
      }
    },
    [load],
  );

  // ── Loading skeleton ───────────────────────────────────────────

  if (loading && !catalog && !insights) {
    return (
      <div className="page-stack">
        <PageHeader title="Models" description="Model catalog, reasoning, and configuration." />
        <div className="flex items-center justify-center py-12 text-muted-foreground">
          Loading…
        </div>
      </div>
    );
  }

  // ── Render ─────────────────────────────────────────────────────

  return (
    <div className="page-stack">
      <PageHeader
        title="Models"
        description="Model catalog, reasoning, and configuration."
        action={
          <div className="flex items-center gap-2">
            {[7, 30, 90].map((d) => (
              <Button
                key={d}
                variant={period === d ? "default" : "outline"}
                size="sm"
                onClick={() => setPeriod(d)}
              >
                {d}d
              </Button>
            ))}
            <Button variant="ghost" size="icon" onClick={load} disabled={loading}>
              <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
            </Button>
          </div>
        }
      />

      {error && <div className="text-sm text-destructive mb-4">{error}</div>}

      {/* ── Reasoning Effort ──────────────────────────────────── */}
      {reasoning && reasoning.supports_reasoning_effort && (
        <Card className="mb-4">
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Brain className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Reasoning Effort</CardTitle>
              {reasoning.show_reasoning && (
                <Badge variant="secondary" className="text-xs">
                  Visible
                </Badge>
              )}
            </div>
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-3">
              <Select
                value={reasoning.reasoning_effort || "medium"}
                onValueChange={handleReasoningEffort}
                disabled={reasoningSaving}
              >
                <SelectTrigger className="w-44">
                  <SelectValue placeholder="Select effort" />
                </SelectTrigger>
                <SelectContent>
                  {(reasoning.supported_efforts?.length
                    ? reasoning.supported_efforts
                    : ["minimal", "low", "medium", "high", "xhigh", "max"]
                  ).map((level) => (
                    <SelectItem key={level} value={level}>
                      {EFFORT_LABELS[level] ?? level}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {reasoningSaving && (
                <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
              )}
            </div>
            <p className="text-xs text-muted-foreground mt-2">
              Controls how many reasoning tokens the model spends. Higher effort = deeper
              thinking, slower responses.
            </p>
          </CardContent>
        </Card>
      )}

      {/* ── Default Model Card ─────────────────────────────────── */}
      {defaultModel && (
        <Card className="ring-1 ring-primary/40 mb-4">
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2">
              <Star className="h-4 w-4 text-primary" />
              <CardTitle className="text-sm">Default Model</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-3">
              <span className="font-mono text-sm font-semibold">
                {shortModelName(defaultModel)}
              </span>
              <Badge variant="secondary">{providerDisplayName(defaultProvider)}</Badge>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Model Groups ──────────────────────────────────────── */}
      <div className="grid gap-4">
        {groups.map((group) => {
          const allModels = [...(group.models ?? []), ...(group.extra_models ?? [])];
          if (allModels.length === 0) return null;

          return (
            <Card key={group.provider_id ?? group.provider}>
              <CardHeader className="pb-2">
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <CardTitle className="text-sm">
                      {group.provider || providerDisplayName(group.provider_id)}
                    </CardTitle>
                    <Badge variant="outline" className="text-xs">
                      {allModels.length} model{allModels.length !== 1 ? "s" : ""}
                    </Badge>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 gap-1 text-xs"
                    disabled={refreshing === group.provider_id}
                    onClick={() => handleRefresh(group.provider_id)}
                  >
                    {refreshing === group.provider_id ? (
                      <Loader2 className="h-3 w-3 animate-spin" />
                    ) : (
                      <RefreshCw className="h-3 w-3" />
                    )}
                    Refresh
                  </Button>
                </div>
              </CardHeader>
              <CardContent className="grid gap-2">
                {allModels.map((model) => {
                  const modelId = model.id;
                  const isDefault =
                    defaultModel === modelId ||
                    (defaultModel &&
                      shortModelName(defaultModel) === shortModelName(modelId));
                  const usage = usageMap.get(`${group.provider_id}/${modelId}`);
                  const totalTokens = usage
                    ? (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0)
                    : 0;
                  const caps = model.capabilities;
                  const hasVision = Boolean(caps?.vision);
                  const hasTools = Boolean(caps?.tools);
                  const hasReasoning = Boolean(caps?.reasoning);
                  const reasoningOptions = (caps?.reasoning as { allowed_options?: string[] } | undefined)?.allowed_options;
                  const settingThis = settingDefault === `${group.provider_id}/${modelId}`;

                  return (
                    <div
                      key={modelId}
                      className={`flex items-start gap-3 rounded-md border px-3 py-2 transition-colors ${
                        isDefault
                          ? "border-primary/40 bg-primary/5"
                          : "border-border hover:border-primary/20"
                      }`}
                    >
                      {/* Model info */}
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-sm font-mono font-semibold truncate">
                            {model.label || shortModelName(modelId)}
                          </span>
                          {isDefault && (
                            <Badge className="bg-primary/15 text-xs">
                              <Star className="h-2.5 w-2.5 mr-0.5" /> default
                            </Badge>
                          )}
                          {hasTools && (
                            <Badge variant="secondary" className="text-xs">
                              <Wrench className="h-2.5 w-2.5 mr-0.5" />
                              Tools
                            </Badge>
                          )}
                          {hasVision && (
                            <Badge variant="secondary" className="text-xs">
                              <Eye className="h-2.5 w-2.5 mr-0.5" />
                              Vision
                            </Badge>
                          )}
                          {hasReasoning && (
                            <Badge variant="secondary" className="text-xs">
                              <Brain className="h-2.5 w-2.5 mr-0.5" />
                              Reasoning
                            </Badge>
                          )}
                          {model.service_tier && model.service_tier !== "auto" && (
                            <Badge variant="outline" className="text-xs">
                              <FlaskConical className="h-2.5 w-2.5 mr-0.5" />
                              {model.service_tier}
                            </Badge>
                          )}
                          {reasoningOptions && reasoningOptions.length > 0 && (
                            <Badge variant="outline" className="text-xs">
                              Effort: {reasoningOptions.join(", ")}
                            </Badge>
                          )}
                        </div>
                        <div className="flex items-center gap-2 mt-0.5 text-xs text-muted-foreground">
                          <span className="font-mono">{modelId}</span>
                          {model.context_window ? (
                            <span>· {formatTokens(model.context_window)} ctx</span>
                          ) : null}
                          {model.max_output_tokens ? (
                            <span>· {formatTokens(model.max_output_tokens)} out</span>
                          ) : null}
                        </div>
                      </div>

                      {/* Usage stats */}
                      {usage && (
                        <div className="text-right shrink-0">
                          <div className="text-xs font-mono font-semibold">
                            {formatTokens(totalTokens)}
                          </div>
                          <div className="text-xs text-muted-foreground">tokens</div>
                        </div>
                      )}

                      {/* Set default action */}
                      {!isDefault && (
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 gap-1 text-xs shrink-0"
                          disabled={settingThis !== null}
                          onClick={() => handleSetDefault(modelId, group.provider_id)}
                        >
                          {settingThis ? (
                            <Loader2 className="h-3 w-3 animate-spin" />
                          ) : (
                            <>
                              <Heart className="h-3 w-3" />
                              Set default
                            </>
                          )}
                        </Button>
                      )}
                      {isDefault && (
                        <div className="flex items-center gap-1 text-xs text-primary shrink-0">
                          <Check className="h-3 w-3" />
                          Active
                        </div>
                      )}
                    </div>
                  );
                })}
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
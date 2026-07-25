import { useEffect, useState } from "react";
import {
  Cpu,
  Download,
  LoaderCircle,
  Plus,
  RefreshCw,
  Sparkles,
  Trash2,
  Eye,
} from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { apiFetch, readableError } from "@/shared/api-client";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface RecommendedModel {
  id: string;
  name: string;
  size_gb: number;
  min_ram_gb: number;
  speed: string;
  quality: string;
  engine?: string;
  multimodal?: boolean;
}

interface HardwareInfo {
  platform: string;
  machine: string;
  ram_gb: number;
  gpu_cores: number;
  gpu_memory_gb: number;
  ssd_speed_gbs: number;
  ollama_running: boolean;
  ollama_models: string[];
  recommended: RecommendedModel;
  recommendations_all: RecommendedModel[];
  downloaded_recommendations: string[];
  pullable_recommendations: string[];
}

interface HatchedSI {
  name: string;
  born_at: string;
  base_model: string;
  system_prompt: string;
  temperature: number;
  top_p: number;
  num_ctx: number;
  thinking: boolean;
  status: string;
}

interface HatcheryStatus {
  ollama_running: boolean;
  available_models: string[];
  hatched: HatchedSI[];
  hardware: HardwareInfo;
}

interface MoldResult {
  name: string;
  base_model: string;
  system_prompt: string;
  temperature: number;
  top_p: number;
  num_ctx: number;
  thinking: boolean;
  needs_pull: boolean;
  modelfile: string;
}

// ---------------------------------------------------------------------------
// Default form state
// ---------------------------------------------------------------------------

const DEFAULTS = {
  name: "",
  base_model: "",
  system_prompt: "",
  temperature: 0.7,
  top_p: 0.9,
  num_ctx: 32768,
  thinking: true,
};

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function HatcheryPage() {
  // --- Data ---
  const [hardware, setHardware] = useState<HardwareInfo | null>(null);
  const [status, setStatus] = useState<HatcheryStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  // --- Form ---
  const [form, setForm] = useState(DEFAULTS);
  const [molding, setMolding] = useState(false);
  const [moldResult, setMoldResult] = useState<MoldResult | null>(null);
  const [hatching, setHatching] = useState(false);
  const [allowModelDownload, setAllowModelDownload] = useState(false);
  const [deleting, setDeleting] = useState<string | null>(null);

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  useEffect(() => {
    void loadAll();
  }, []);

  async function loadAll() {
    setLoading(true);
    setError("");
    try {
      const [hw, st] = await Promise.all([
        apiFetch<HardwareInfo>("/api/hatchery/scan"),
        apiFetch<HatcheryStatus>("/api/hatchery/status"),
      ]);
      setHardware(hw);
      setStatus(st);
    } catch (reason) {
      setError(readableError(reason, "Could not load hatchery status."));
    } finally {
      setLoading(false);
    }
  }

  async function refreshStatus() {
    try {
      const st = await apiFetch<HatcheryStatus>("/api/hatchery/status");
      setStatus(st);
      const hw = await apiFetch<HardwareInfo>("/api/hatchery/scan");
      setHardware(hw);
    } catch (reason) {
      setError(readableError(reason, "Could not refresh status."));
    }
  }

  // ---------------------------------------------------------------------------
  // Mold (preview)
  // ---------------------------------------------------------------------------

  async function handleMold() {
    setMolding(true);
    setError("");
    setMoldResult(null);
    try {
      const result = await apiFetch<MoldResult>("/api/hatchery/mold", {
        method: "POST",
        body: JSON.stringify(form),
      });
      setMoldResult(result);
    } catch (reason) {
      setError(readableError(reason, "Could not preview mold."));
    } finally {
      setMolding(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Hatch (create)
  // ---------------------------------------------------------------------------

  async function handleHatch() {
    setHatching(true);
    setError("");
    try {
      await apiFetch<HatchedSI>("/api/hatchery/hatch", {
        method: "POST",
        body: JSON.stringify({ ...form, pull_if_missing: allowModelDownload }),
      });
      setMoldResult(null);
      setAllowModelDownload(false);
      setForm(DEFAULTS);
      await refreshStatus();
    } catch (reason) {
      setError(readableError(reason, "Could not hatch SI."));
    } finally {
      setHatching(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  async function handleDelete(name: string) {
    setDeleting(name);
    setError("");
    try {
      await apiFetch("/api/hatchery/delete", {
        method: "POST",
        body: JSON.stringify({ name }),
      });
      await refreshStatus();
    } catch (reason) {
      setError(readableError(reason, "Could not delete SI."));
    } finally {
      setDeleting(null);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  const modelOptions = hardware?.recommendations_all ?? [];
  const ollamaModels = status?.available_models ?? hardware?.ollama_models ?? [];

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  if (loading) {
    return (
      <div className="page-stack">
        <PageHeader title="Hatchery" description="Local model companion workshop." />
        <div className="flex items-center justify-center py-12 text-muted-foreground">
          <LoaderCircle className="mr-2 size-5 animate-spin" /> Loading…
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Hatchery"
        description="Inspect hardware, mold a personality, and hatch a local Synthetic Intelligence."
        action={
          <Button size="sm" variant="outline" onClick={() => void loadAll()}>
            <RefreshCw className="mr-1 size-4" /> Refresh
          </Button>
        }
      />

      {error && (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-300">
          {error}
        </div>
      )}

      {/* ── Hardware & Recommendation ── */}
      <div className="grid gap-4 md:grid-cols-2">
        {/* Hardware card */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <Cpu className="size-4" /> Hardware
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            {hardware ? (
              <>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Platform</span>
                  <span>{hardware.platform} · {hardware.machine}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">RAM</span>
                  <span>{hardware.ram_gb} GB</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">GPU</span>
                  <span>{hardware.gpu_cores} cores · {hardware.gpu_memory_gb} GB</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">SSD</span>
                  <span>~{hardware.ssd_speed_gbs} GB/s</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Ollama</span>
                  <Badge variant={hardware.ollama_running ? "default" : "secondary"}>
                    {hardware.ollama_running ? "running" : "offline"}
                  </Badge>
                </div>
              </>
            ) : (
              <div className="text-muted-foreground">No hardware info available.</div>
            )}
          </CardContent>
        </Card>

        {/* Recommended model card */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <Sparkles className="size-4" /> Recommended Model
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 text-sm">
            {hardware?.recommended ? (
              <>
                <div className="font-medium">{hardware.recommended.name}</div>
                <div className="text-xs text-muted-foreground">
                  {hardware.recommended.size_gb} GB · {hardware.recommended.speed} · {hardware.recommended.quality} quality
                  {hardware.recommended.engine ? ` · ${hardware.recommended.engine}` : ""}
                </div>
                {ollamaModels.includes(hardware.recommended.id) ? (
                  <Badge className="mt-1">downloaded</Badge>
                ) : (
                  <Badge variant="outline" className="mt-1">needs pull</Badge>
                )}
              </>
            ) : (
              <div className="text-muted-foreground">No recommendation available.</div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ── Mold Form ── */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-sm">
            <Plus className="size-4" /> Mold a New SI
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            {/* Name */}
            <div className="space-y-1.5">
              <Label htmlFor="si-name">Name</Label>
              <Input
                id="si-name"
                placeholder="my-companion"
                value={form.name}
                onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
              />
              <p className="text-xs text-muted-foreground">Lowercase, letters, numbers, hyphens.</p>
            </div>

            {/* Base model */}
            <div className="space-y-1.5">
              <Label>Base Model</Label>
              <Select
                value={form.base_model}
                onValueChange={(v) => setForm((f) => ({ ...f, base_model: v }))}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Select a model…" />
                </SelectTrigger>
                <SelectContent>
                  {modelOptions.map((m) => (
                    <SelectItem key={m.id} value={m.id}>
                      {m.name} ({m.size_gb} GB)
                    </SelectItem>
                  ))}
                  {ollamaModels
                    .filter((m) => !modelOptions.some((r) => r.id === m))
                    .map((m) => (
                      <SelectItem key={m} value={m}>
                        {m}
                      </SelectItem>
                    ))}
                </SelectContent>
              </Select>
            </div>

            {/* Temperature */}
            <div className="space-y-1.5">
              <Label htmlFor="si-temp">Temperature ({form.temperature})</Label>
              <Input
                id="si-temp"
                type="number"
                min={0}
                max={2}
                step={0.1}
                value={form.temperature}
                onChange={(e) =>
                  setForm((f) => ({ ...f, temperature: parseFloat(e.target.value) || 0 }))
                }
              />
            </div>

            {/* Top P */}
            <div className="space-y-1.5">
              <Label htmlFor="si-topp">Top P ({form.top_p})</Label>
              <Input
                id="si-topp"
                type="number"
                min={0}
                max={1}
                step={0.05}
                value={form.top_p}
                onChange={(e) =>
                  setForm((f) => ({ ...f, top_p: parseFloat(e.target.value) || 0 }))
                }
              />
            </div>

            {/* Context window */}
            <div className="space-y-1.5">
              <Label htmlFor="si-ctx">Context Window (tokens)</Label>
              <Input
                id="si-ctx"
                type="number"
                min={2048}
                max={131072}
                step={1024}
                value={form.num_ctx}
                onChange={(e) =>
                  setForm((f) => ({ ...f, num_ctx: parseInt(e.target.value) || 32768 }))
                }
              />
            </div>

            {/* Thinking toggle */}
            <div className="flex items-center gap-3 pt-5">
              <ToggleSwitch
                checked={form.thinking}
                onCheckedChange={(v) => setForm((f) => ({ ...f, thinking: v }))}
              />
              <Label>Thinking mode</Label>
            </div>
          </div>

          {/* System prompt */}
          <div className="space-y-1.5">
            <Label htmlFor="si-prompt">System Prompt</Label>
            <Textarea
              id="si-prompt"
              placeholder="You are a helpful Synthetic Intelligence…"
              rows={3}
              value={form.system_prompt}
              onChange={(e) => setForm((f) => ({ ...f, system_prompt: e.target.value }))}
            />
          </div>

          {/* Action buttons */}
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              disabled={molding || !form.name || !form.base_model}
              onClick={() => void handleMold()}
            >
              {molding ? (
                <LoaderCircle className="mr-1 size-4 animate-spin" />
              ) : (
                <Eye className="mr-1 size-4" />
              )}
              Preview Mold
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* ── Mold Preview ── */}
      {moldResult && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <Eye className="size-4" /> Mold Preview — {moldResult.name}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid gap-2 text-sm sm:grid-cols-2">
              <div>
                <span className="text-muted-foreground">Base model:</span> {moldResult.base_model}
              </div>
              <div>
                <span className="text-muted-foreground">Temperature:</span> {moldResult.temperature}
              </div>
              <div>
                <span className="text-muted-foreground">Top P:</span> {moldResult.top_p}
              </div>
              <div>
                <span className="text-muted-foreground">Context:</span> {moldResult.num_ctx} tokens
              </div>
              <div>
                <span className="text-muted-foreground">Thinking:</span>{" "}
                {moldResult.thinking ? "enabled" : "disabled"}
              </div>
              <div>
                <span className="text-muted-foreground">Needs pull:</span>{" "}
                <Badge variant={moldResult.needs_pull ? "secondary" : "default"}>
                  {moldResult.needs_pull ? "yes" : "already local"}
                </Badge>
              </div>
            </div>
            {moldResult.system_prompt && (
              <div className="rounded-md border bg-secondary/50 p-3">
                <div className="text-xs font-medium text-muted-foreground mb-1">System Prompt</div>
                <div className="text-sm whitespace-pre-wrap">{moldResult.system_prompt}</div>
              </div>
            )}
            <details className="text-xs text-muted-foreground">
              <summary className="cursor-pointer hover:text-foreground">Modelfile</summary>
              <pre className="mt-1 rounded-md border bg-secondary/30 p-2 text-xs overflow-x-auto">
                {moldResult.modelfile}
              </pre>
            </details>
            {moldResult.needs_pull && (
              <div className="rounded-md border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-200">
                <div className="font-medium">This base model is not on this Mac.</div>
                <div className="mt-1">
                  Hatching will download approximately{
                    modelOptions.find((model) => model.id === moldResult.base_model)?.size_gb
                      ? ` ${modelOptions.find((model) => model.id === moldResult.base_model)?.size_gb} GB`
                      : " several gigabytes"
                  } through Ollama. The download can take a while and uses disk space.
                </div>
                <label className="mt-2 flex cursor-pointer items-center gap-2">
                  <ToggleSwitch
                    checked={allowModelDownload}
                    onCheckedChange={setAllowModelDownload}
                  />
                  I approve downloading this model
                </label>
              </div>
            )}
            {!status?.ollama_running && (
              <div className="text-xs text-destructive">
                Ollama is offline. Start Ollama, then refresh Hatchery before hatching.
              </div>
            )}
            <div className="flex gap-2 pt-1">
              <Button
                size="sm"
                disabled={hatching || !status?.ollama_running || (moldResult.needs_pull && !allowModelDownload)}
                onClick={() => void handleHatch()}
              >
                {hatching ? (
                  <LoaderCircle className="mr-1 size-4 animate-spin" />
                ) : (
                  <Sparkles className="mr-1 size-4" />
                )}
                Hatch {moldResult.name}
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  setMoldResult(null);
                  setAllowModelDownload(false);
                }}
              >
                Cancel
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Hatched SIs ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Hatched Synthetic Intelligences</CardTitle>
        </CardHeader>
        <CardContent className="divide-y">
          {(status?.hatched ?? []).length === 0 ? (
            <div className="py-4 text-center text-sm text-muted-foreground">
              No hatched SIs yet. Mold one above to get started.
            </div>
          ) : (
            (status?.hatched ?? []).map((si) => (
              <div key={si.name} className="flex items-center justify-between py-3">
                <div className="min-w-0">
                  <div className="font-medium text-sm">{si.name}</div>
                  <div className="text-xs text-muted-foreground truncate">
                    {si.base_model} · temp {si.temperature} · top_p {si.top_p} · ctx {si.num_ctx}
                    {si.thinking ? " · thinking" : ""} · born {new Date(si.born_at).toLocaleDateString()}
                  </div>
                  {si.system_prompt && (
                    <div className="text-xs text-muted-foreground mt-0.5 truncate max-w-md">
                      {si.system_prompt}
                    </div>
                  )}
                </div>
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <Button size="sm" variant="outline" disabled={deleting === si.name}>
                      {deleting === si.name ? (
                        <LoaderCircle className="size-4 animate-spin" />
                      ) : (
                        <Trash2 className="size-4 text-destructive" />
                      )}
                    </Button>
                  </AlertDialogTrigger>
                  <AlertDialogContent>
                    <AlertDialogHeader>
                      <AlertDialogTitle>Delete {si.name}?</AlertDialogTitle>
                      <AlertDialogDescription>
                        This will remove the Ollama model and birth certificate for "{si.name}". This action cannot be undone.
                      </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                      <AlertDialogAction onClick={() => void handleDelete(si.name)}>
                        Delete
                      </AlertDialogAction>
                    </AlertDialogFooter>
                  </AlertDialogContent>
                </AlertDialog>
              </div>
            ))
          )}
        </CardContent>
      </Card>

      {/* ── All Recommendations ── */}
      {hardware && hardware.recommendations_all.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <Download className="size-4" /> All Recommendations
            </CardTitle>
          </CardHeader>
          <CardContent className="divide-y">
            {hardware.recommendations_all.map((model) => (
              <div key={model.id} className="flex items-center justify-between py-2">
                <div className="text-sm">
                  <div className="font-medium">{model.name}</div>
                  <div className="text-xs text-muted-foreground">
                    {model.size_gb} GB · {model.speed} · {model.quality}
                    {model.engine ? ` · ${model.engine}` : ""}
                    {model.multimodal ? " · multimodal" : ""}
                  </div>
                </div>
                {ollamaModels.includes(model.id) ? (
                  <Badge variant="outline">downloaded</Badge>
                ) : (
                  <Badge variant="secondary">{model.min_ram_gb} GB min</Badge>
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

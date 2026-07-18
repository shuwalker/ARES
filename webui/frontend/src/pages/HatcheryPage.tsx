import { useEffect, useState } from "react";
import { Cpu, Download, LoaderCircle, Plus, RefreshCw } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { apiFetch, readableError } from "@/shared/api-client";

interface RecommendedModel {
  name: string;
  base_model?: string;
  size?: string;
  quant?: string;
  reason?: string;
  estimated_tok_s?: number;
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

interface MoldResult {
  name: string;
  base_model: string;
  system_prompt: string;
  temperature: number;
}

export default function HatcheryPage() {
  const [hardware, setHardware] = useState<HardwareInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [molding, setMolding] = useState(false);
  const [moldResult, setMoldResult] = useState<MoldResult | null>(null);
  const [pulling, setPulling] = useState<string | null>(null);

  useEffect(() => {
    void loadStatus();
  }, []);

  async function loadStatus() {
    setLoading(true);
    setError("");
    try {
      const data = await apiFetch<HardwareInfo>("/api/hatchery/status");
      setHardware(data);
    } catch (reason) {
      setError(readableError(reason, "Could not load hatchery status."));
    } finally {
      setLoading(false);
    }
  }

  async function moldCompanion() {
    setMolding(true);
    setError("");
    try {
      const result = await apiFetch<MoldResult>("/api/hatchery/mold", { method: "POST" });
      setMoldResult(result);
    } catch (reason) {
      setError(readableError(reason, "Could not mold companion."));
    } finally {
      setMolding(false);
    }
  }

  async function pullModel(name: string) {
    setPulling(name);
    setError("");
    try {
      await apiFetch("/api/hatchery/hatch", {
        method: "POST",
        body: JSON.stringify({ model: name }),
      });
      await loadStatus();
    } catch (reason) {
      setError(readableError(reason, "Could not pull model."));
    } finally {
      setPulling(null);
    }
  }

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
        description="Inspect local hardware and hatch MLX companions tuned for this Mac."
        action={
          <Button size="sm" variant="outline" onClick={() => void loadStatus()}>
            <RefreshCw className="mr-1 size-4" /> Refresh
          </Button>
        }
      />

      {error ? (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-300">{error}</div>
      ) : null}

      {hardware ? (
        <div className="grid gap-4 md:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-sm">
                <Cpu className="size-4" /> Hardware
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-1 text-sm">
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
                <span className="text-muted-foreground">Ollama</span>
                <Badge variant={hardware.ollama_running ? "default" : "secondary"}>
                  {hardware.ollama_running ? "running" : "offline"}
                </Badge>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-sm">
                <Download className="size-4" /> Recommended
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {hardware.recommended ? (
                <div className="flex items-center justify-between">
                  <div className="text-sm">
                    <div className="font-medium">{hardware.recommended.name}</div>
                    <div className="text-xs text-muted-foreground">{hardware.recommended.reason}</div>
                  </div>
                  {hardware.downloaded_recommendations.includes(hardware.recommended.name) ? (
                    <Badge>downloaded</Badge>
                  ) : (
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={pulling === hardware.recommended.name}
                      onClick={() => void pullModel(hardware.recommended!.name)}
                    >
                      {pulling === hardware.recommended.name ? <LoaderCircle className="size-4 animate-spin" /> : <Download className="size-4" />}
                    </Button>
                  )}
                </div>
              ) : (
                <div className="text-sm text-muted-foreground">No recommendation available.</div>
              )}

              <Button
                size="sm"
                className="w-full"
                disabled={molding}
                onClick={() => void moldCompanion()}
              >
                {molding ? <LoaderCircle className="mr-2 size-4 animate-spin" /> : <Plus className="mr-2 size-4" />}
                Mold companion
              </Button>

              {moldResult ? (
                <div className="rounded-md border bg-secondary/50 p-3 text-xs">
                  <div className="font-medium">{moldResult.name}</div>
                  <div className="text-muted-foreground">Base: {moldResult.base_model} · temp: {moldResult.temperature}</div>
                </div>
              ) : null}
            </CardContent>
          </Card>

          <Card className="md:col-span-2">
            <CardHeader>
              <CardTitle className="text-sm">All recommendations</CardTitle>
            </CardHeader>
            <CardContent className="divide-y">
              {hardware.recommendations_all.map((model) => (
                <div key={model.name} className="flex items-center justify-between py-2">
                  <div className="text-sm">
                    <div className="font-medium">{model.name}</div>
                    <div className="text-xs text-muted-foreground">{model.size} · {model.quant} · ~{model.estimated_tok_s} tok/s</div>
                  </div>
                  {hardware.downloaded_recommendations.includes(model.name) ? (
                    <Badge variant="outline">downloaded</Badge>
                  ) : (
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={pulling === model.name}
                      onClick={() => void pullModel(model.name)}
                    >
                      {pulling === model.name ? <LoaderCircle className="size-4 animate-spin" /> : <Download className="size-4" />}
                    </Button>
                  )}
                </div>
              ))}
              {hardware.recommendations_all.length === 0 && (
                <div className="py-4 text-center text-sm text-muted-foreground">No pullable recommendations.</div>
              )}
            </CardContent>
          </Card>
        </div>
      ) : null}
    </div>
  );
}

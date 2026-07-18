import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  Check,
  ChevronsUpDown,
  LoaderCircle,
  RefreshCw,
  RotateCcw,
  Save,
  X,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { aresApi, type ConfigValidationResult } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";

// ── Section definitions for grouping config keys ────────────────────────

interface ConfigSection {
  key: string;
  label: string;
  description: string;
  keys: string[];
}

const SECTIONS: ConfigSection[] = [
  {
    key: "general",
    label: "General",
    description: "Core agent identity and behavior settings.",
    keys: ["bot_name", "display_name", "default_model", "model_provider", "timezone", "language"],
  },
  {
    key: "model",
    label: "Model Defaults",
    description: "Default model, provider, and generation parameters.",
    keys: ["default_model", "model_provider", "max_tokens", "temperature", "top_p", "frequency_penalty", "presence_penalty"],
  },
  {
    key: "network",
    label: "Network & API",
    description: "Connection endpoints, rate limits, and proxy settings.",
    keys: ["base_url", "api_key", "proxy", "timeout", "max_retries", "rate_limit"],
  },
  {
    key: "storage",
    label: "Storage & Memory",
    description: "Context store, memory, and workspace settings.",
    keys: ["context_store_enabled", "memory_enabled", "max_context_tokens", "workspace"],
  },
  {
    key: "privacy",
    label: "Privacy & Safety",
    description: "Content filtering, PII handling, and guardrails.",
    keys: ["content_filter", "pii_redaction", "safety_mode", "max_output_length"],
  },
  {
    key: "advanced",
    label: "Advanced",
    description: "Debug, logging, and experimental options.",
    keys: ["debug", "log_level", "verbose", "experimental_features", "streaming"],
  },
];

// ── Helpers ──────────────────────────────────────────────────────────────

function isNumeric(v: unknown): v is number {
  return typeof v === "number";
}

function isBooleanish(v: unknown): v is boolean | string {
  return typeof v === "boolean" || v === "true" || v === "false";
}

function toBool(v: unknown): boolean {
  if (typeof v === "boolean") return v;
  if (typeof v === "string") return v === "true" || v === "1";
  return Boolean(v);
}

function displayValue(v: unknown): string {
  if (v === null || v === undefined) return "";
  if (typeof v === "object") return JSON.stringify(v, null, 2);
  return String(v);
}

function deepEqual(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

// Determine which top-level keys belong to known sections vs uncategorized
function categorizeKeys(raw: Record<string, unknown>): {
  sectioned: Map<string, Record<string, unknown>>;
  uncategorized: Record<string, unknown>;
} {
  const sectioned = new Map<string, Record<string, unknown>>();
  const assigned = new Set<string>();

  for (const section of SECTIONS) {
    const pairs: Record<string, unknown> = {};
    for (const k of section.keys) {
      if (k in raw) {
        pairs[k] = raw[k];
        assigned.add(k);
      }
    }
    if (Object.keys(pairs).length > 0) {
      sectioned.set(section.key, pairs);
    }
  }

  const uncategorized: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (!assigned.has(k)) {
      uncategorized[k] = v;
    }
  }

  return { sectioned, uncategorized };
}

// ── ConfigSectionCard ────────────────────────────────────────────────────

function ConfigSectionCard({
  section,
  values,
  draft,
  onChange,
  validation,
}: {
  section: ConfigSection;
  values: Record<string, unknown>;
  draft: Record<string, unknown>;
  onChange: (key: string, value: unknown) => void;
  validation: ConfigValidationResult | null;
}) {
  const [open, setOpen] = useState(true);
  const sectionErrors = validation?.errors?.filter((e) =>
    section.keys.some((k) => e.toLowerCase().includes(k.toLowerCase())),
  ) ?? [];
  const sectionWarnings = validation?.warnings?.filter((w) =>
    section.keys.some((k) => w.toLowerCase().includes(k.toLowerCase())),
  ) ?? [];

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <Card>
        <CollapsibleTrigger asChild>
          <CardHeader className="cursor-pointer select-none">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <CardTitle className="text-base">{section.label}</CardTitle>
                {sectionErrors.length > 0 && (
                  <Badge variant="destructive" className="text-[10px]">
                    {sectionErrors.length} error{sectionErrors.length > 1 ? "s" : ""}
                  </Badge>
                )}
                {sectionWarnings.length > 0 && (
                  <Badge variant="outline" className="border-amber-500/50 text-amber-600 dark:text-amber-400 text-[10px]">
                    {sectionWarnings.length} warning{sectionWarnings.length > 1 ? "s" : ""}
                  </Badge>
                )}
              </div>
              <ChevronsUpDown className="size-4 text-muted-foreground" />
            </div>
            <CardDescription>{section.description}</CardDescription>
          </CardHeader>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <CardContent className="grid gap-4 pt-0">
            {Object.entries(values).map(([key, originalValue]) => {
              const currentValue = key in draft ? draft[key] : originalValue;
              const changed = !deepEqual(currentValue, originalValue);
              return (
                <div key={key} className="grid gap-1.5">
                  <div className="flex items-center gap-2">
                    <Label htmlFor={`cfg-${key}`} className="font-mono text-sm">
                      {key}
                    </Label>
                    {changed && (
                      <Badge variant="secondary" className="text-[10px]">modified</Badge>
                    )}
                  </div>
                  <ConfigField
                    id={`cfg-${key}`}
                    value={currentValue}
                    originalValue={originalValue}
                    onChange={(v) => onChange(key, v)}
                  />
                </div>
              );
            })}
          </CardContent>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  );
}

// ── ConfigField (smart editor per value type) ────────────────────────────

function ConfigField({
  id,
  value,
  originalValue,
  onChange,
}: {
  id: string;
  value: unknown;
  originalValue: unknown;
  onChange: (v: unknown) => void;
}) {
  if (isBooleanish(value)) {
    const checked = toBool(value);
    return (
      <button
        id={id}
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full border-2 border-transparent transition-colors ${
          checked ? "bg-emerald-600" : "bg-muted"
        }`}
      >
        <span
          className={`pointer-events-none inline-block size-4 rounded-full bg-white shadow-lg transition-transform ${
            checked ? "translate-x-5" : "translate-x-0"
          }`}
        />
      </button>
    );
  }

  if (isNumeric(value)) {
    return (
      <Input
        id={id}
        type="number"
        value={value as number}
        onChange={(e) => onChange(e.target.value === "" ? "" : Number(e.target.value))}
        className="font-mono text-sm"
      />
    );
  }

  const strVal = displayValue(value);
  const isLong = strVal.length > 80 || strVal.includes("\n") || typeof value === "object";

  if (isLong) {
    return (
      <Textarea
        id={id}
        value={strVal}
        onChange={(e) => {
          try {
            const parsed = JSON.parse(e.target.value);
            onChange(parsed);
          } catch {
            onChange(e.target.value);
          }
        }}
        className="font-mono text-xs min-h-24"
      />
    );
  }

  return (
    <Input
      id={id}
      value={strVal}
      onChange={(e) => onChange(e.target.value)}
      className="font-mono text-sm"
    />
  );
}

// ── Main page ────────────────────────────────────────────────────────────

export default function ConfigPage() {
  const [raw, setRaw] = useState<Record<string, unknown> | null>(null);
  const [draft, setDraft] = useState<Record<string, unknown>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [validation, setValidation] = useState<ConfigValidationResult | null>(null);
  const [viewMode, setViewMode] = useState<"form" | "json" | "yaml">("form");
  const [editorText, setEditorText] = useState("");
  const [editorError, setEditorError] = useState<string | null>(null);

  // ── Load config ──────────────────────────────────────────────────
  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.configGet();
      setRaw(data);
      setDraft({});
      setValidation(null);
    } catch (e) {
      setError(readableError(e, "Failed to load configuration."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // ── Derived state ───────────────────────────────────────────────
  const merged = useMemo(() => {
    if (!raw) return {};
    return { ...raw, ...draft };
  }, [raw, draft]);

  const hasChanges = useMemo(() => {
    if (!raw) return false;
    return Object.keys(draft).length > 0;
  }, [raw, draft]);

  const { sectioned, uncategorized } = useMemo(
    () => categorizeKeys(raw ?? {}),
    [raw],
  );

  // Sync editor text when raw or viewMode changes
  useEffect(() => {
    if (!raw) return;
    if (viewMode === "json") {
      setEditorText(JSON.stringify({ ...raw, ...draft }, null, 2));
      setEditorError(null);
    } else if (viewMode === "yaml") {
      // Simple YAML-like representation (not a full YAML serializer)
      const obj = { ...raw, ...draft };
      const lines = Object.entries(obj).map(([k, v]) => {
        if (typeof v === "object") return `${k}:\n${JSON.stringify(v, null, 2).split("\n").map((l, i) => (i === 0 ? l : "  " + l)).join("\n")}`;
        return `${k}: ${displayValue(v)}`;
      });
      setEditorText(lines.join("\n"));
      setEditorError(null);
    }
  }, [raw, draft, viewMode]);

  // ── Handlers ─────────────────────────────────────────────────────
  function handleChange(key: string, value: unknown) {
    setDraft((prev) => {
      const next = { ...prev };
      if (raw && key in raw && deepEqual(value, raw[key])) {
        delete next[key]; // revert to original
      } else {
        next[key] = value;
      }
      return next;
    });
  }

  async function handleSave() {
    if (!raw) return;
    setSaving(true);
    setError(null);
    try {
      const payload = { ...raw, ...draft };
      await aresApi.configSave(payload);
      setRaw(payload);
      setDraft({});
      setValidation(null);
    } catch (e) {
      setError(readableError(e, "Failed to save configuration."));
    } finally {
      setSaving(false);
    }
  }

  function handleRevert() {
    setDraft({});
    setValidation(null);
    setError(null);
  }

  async function handleValidate() {
    if (!raw) return;
    try {
      const result = await aresApi.configValidate({ ...raw, ...draft });
      setValidation(result);
    } catch (e) {
      setValidation({ valid: false, errors: [readableError(e, "Validation failed.")], warnings: [] });
    }
  }

  async function handleEditorSave() {
    if (viewMode === "json") {
      try {
        const parsed = JSON.parse(editorText);
        setSaving(true);
        setError(null);
        try {
          await aresApi.configSave(parsed);
          setRaw(parsed);
          setDraft({});
          setValidation(null);
        } catch (e) {
          setError(readableError(e, "Failed to save configuration."));
        } finally {
          setSaving(false);
        }
      } catch {
        setEditorError("Invalid JSON syntax.");
      }
    } else {
      // YAML mode: parse simple key: value lines back to object
      try {
        const obj: Record<string, unknown> = {};
        const lines = editorText.split("\n");
        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith("#")) continue;
          const colonIdx = trimmed.indexOf(":");
          if (colonIdx === -1) continue;
          const key = trimmed.slice(0, colonIdx).trim();
          const val = trimmed.slice(colonIdx + 1).trim();
          // Try to parse the value
          if (val === "true") obj[key] = true;
          else if (val === "false") obj[key] = false;
          else if (val === "null") obj[key] = null;
          else if (/^-?\d+(\.\d+)?$/.test(val)) obj[key] = Number(val);
          else obj[key] = val;
        }
        setSaving(true);
        setError(null);
        try {
          await aresApi.configSave(obj);
          setRaw(obj);
          setDraft({});
          setValidation(null);
        } catch (e) {
          setError(readableError(e, "Failed to save configuration."));
        } finally {
          setSaving(false);
        }
      } catch {
        setEditorError("Failed to parse YAML content.");
      }
    }
  }

  // ── Render ───────────────────────────────────────────────────────
  if (loading) {
    return (
      <div className="page-stack">
        <PageHeader title="Configuration" description="View and edit ARES agent configuration." />
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading configuration…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Configuration"
        description="View and edit ARES agent configuration."
        action={
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => void load()} disabled={loading}>
              <RefreshCw className={`mr-1 size-3.5 ${loading ? "animate-spin" : ""}`} />
              Refresh
            </Button>
          </div>
        }
      />

      {error && (
        <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      {/* Validation status bar */}
      {validation && (
        <div
          className={`rounded-md border px-4 py-3 text-sm ${
            validation.valid
              ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"
              : "border-destructive/40 bg-destructive/10 text-destructive"
          }`}
        >
          <div className="flex items-center gap-2 font-medium">
            {validation.valid ? (
              <><Check className="size-4" /> Configuration is valid</>
            ) : (
              <><AlertTriangle className="size-4" /> Validation failed</>
            )}
          </div>
          {validation.errors && validation.errors.length > 0 && (
            <ul className="mt-2 ml-6 list-disc text-destructive">
              {validation.errors.map((e, i) => <li key={i}>{e}</li>)}
            </ul>
          )}
          {validation.warnings && validation.warnings.length > 0 && (
            <ul className="mt-2 ml-6 list-disc text-amber-600 dark:text-amber-400">
              {validation.warnings.map((w, i) => <li key={i}>{w}</li>)}
            </ul>
          )}
        </div>
      )}

      {/* Save / Revert / Validate bar */}
      {hasChanges && (
        <Card>
          <CardContent className="flex items-center gap-3 py-3">
            <span className="text-sm text-muted-foreground">
              {Object.keys(draft).length} unsaved change{Object.keys(draft).length !== 1 ? "s" : ""}
            </span>
            <div className="flex-1" />
            <Button variant="outline" size="sm" onClick={handleRevert}>
              <RotateCcw className="mr-1 size-3.5" />
              Revert
            </Button>
            <Button variant="outline" size="sm" onClick={() => void handleValidate()}>
              <AlertTriangle className="mr-1 size-3.5" />
              Validate
            </Button>
            <Button size="sm" onClick={() => void handleSave()} disabled={saving}>
              {saving ? <LoaderCircle className="mr-1 size-3.5 animate-spin" /> : <Save className="mr-1 size-3.5" />}
              {saving ? "Saving…" : "Save"}
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Main content with tabs */}
      <Tabs value={viewMode} onValueChange={(v) => setViewMode(v as "form" | "json" | "yaml")}>
        <TabsList>
          <TabsTrigger value="form">Form</TabsTrigger>
          <TabsTrigger value="json">JSON</TabsTrigger>
          <TabsTrigger value="yaml">YAML</TabsTrigger>
        </TabsList>

        <TabsContent value="form">
          {raw ? (
            <div className="grid gap-4">
              {SECTIONS.filter((s) => sectioned.has(s.key)).map((section) => (
                <ConfigSectionCard
                  key={section.key}
                  section={section}
                  values={sectioned.get(section.key) ?? {}}
                  draft={draft}
                  onChange={handleChange}
                  validation={validation}
                />
              ))}

              {/* Uncategorized keys */}
              {Object.keys(uncategorized).length > 0 && (
                <ConfigSectionCard
                  section={{
                    key: "other",
                    label: "Other",
                    description: "Additional configuration keys not grouped into a section.",
                    keys: Object.keys(uncategorized),
                  }}
                  values={uncategorized}
                  draft={draft}
                  onChange={handleChange}
                  validation={validation}
                />
              )}
            </div>
          ) : (
            <Card>
              <CardContent className="py-8 text-center text-muted-foreground">
                No configuration loaded.
              </CardContent>
            </Card>
          )}
        </TabsContent>

        <TabsContent value="json">
          <Card>
            <CardHeader className="pb-3">
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="text-base">JSON Editor</CardTitle>
                  <CardDescription>Edit the full configuration as JSON.</CardDescription>
                </div>
                <Button size="sm" onClick={() => void handleEditorSave()} disabled={saving}>
                  {saving ? <LoaderCircle className="mr-1 size-3.5 animate-spin" /> : <Save className="mr-1 size-3.5" />}
                  {saving ? "Saving…" : "Save JSON"}
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              {editorError && (
                <div className="mb-3 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {editorError}
                </div>
              )}
              <Textarea
                value={editorText}
                onChange={(e) => {
                  setEditorText(e.target.value);
                  setEditorError(null);
                }}
                className="font-mono text-xs min-h-[400px]"
                spellCheck={false}
              />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="yaml">
          <Card>
            <CardHeader className="pb-3">
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="text-base">YAML Editor</CardTitle>
                  <CardDescription>Edit the configuration as key: value pairs.</CardDescription>
                </div>
                <Button size="sm" onClick={() => void handleEditorSave()} disabled={saving}>
                  {saving ? <LoaderCircle className="mr-1 size-3.5 animate-spin" /> : <Save className="mr-1 size-3.5" />}
                  {saving ? "Saving…" : "Save YAML"}
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              {editorError && (
                <div className="mb-3 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {editorError}
                </div>
              )}
              <Textarea
                value={editorText}
                onChange={(e) => {
                  setEditorText(e.target.value);
                  setEditorError(null);
                }}
                className="font-mono text-xs min-h-[400px]"
                spellCheck={false}
              />
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}
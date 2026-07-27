import { Check, ChevronsUpDown, LoaderCircle, RefreshCw, RotateCcw, Save } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";

type SettingValue = string | number | boolean | null | unknown[] | Record<string, unknown>;

const READ_ONLY_KEYS = new Set([
  "agent_version", "auth_enabled", "logged_in", "max_tokens_effective", "max_tokens_fallback",
  "passkeys_enabled", "password_auth_enabled", "password_env_var", "passwordless_enabled",
  "persisted_speech_keys", "update_channel_version", "webui_version",
]);

const HIDDEN_KEYS = new Set([
  "password_hash", "connections", "onboarding_completed", "owner_name", "bot_name",
  "local_profile_voice", "local_profile_reachability", "context_store_enabled", "ares_backend",
]);

const GROUPS = [
  { id: "appearance", label: "Appearance & navigation", description: "Theme, density, tabs, and visible controls.", match: /^(theme|skin|font_|sidebar_|tab_|hidden_tabs|hide_|show_|composer_|rtl|language)/ },
  { id: "conversation", label: "Conversation", description: "Composer, transcript, reasoning, and session behavior.", match: /^(send_|chat_|auto_|render_|large_|new_chat|session_|structured_|worklog_|simplified_|workspace_todos)/ },
  { id: "voice", label: "Voice & notifications", description: "Speech, sound, and local notification behavior.", match: /^(tts_|voice_|raw_audio|sound_|notifications_)/ },
  { id: "runtime", label: "Runtime limits", description: "Model defaults, limits, budgets, and runtime safeguards.", match: /^(default_|max_|inflight_|provider_|api_|pinned_)/ },
  { id: "updates", label: "Updates & integrations", description: "Update preferences and optional integrations.", match: /^(check_|update_|ignore_|sync_|dashboard_|whats_)/ },
] as const;

function equal(a: unknown, b: unknown) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function SettingsField({ name, value, onChange }: { name: string; value: SettingValue; onChange: (value: SettingValue) => void }) {
  if (typeof value === "boolean") {
    return <ToggleSwitch id={`setting-${name}`} checked={value} onCheckedChange={onChange} />;
  }
  if (typeof value === "number") {
    return <Input id={`setting-${name}`} type="number" value={value} onChange={(event) => onChange(Number(event.target.value))} className="font-mono" />;
  }
  if (value !== null && typeof value === "object") {
    return (
      <Textarea
        id={`setting-${name}`}
        value={JSON.stringify(value, null, 2)}
        onChange={(event) => {
          try { onChange(JSON.parse(event.target.value) as SettingValue); } catch { /* keep the last valid value */ }
        }}
        className="min-h-28 font-mono text-xs"
      />
    );
  }
  return <Input id={`setting-${name}`} value={value == null ? "" : String(value)} onChange={(event) => onChange(event.target.value)} className="font-mono" />;
}

function SettingsGroup({ label, description, entries, original, changes, onChange }: {
  label: string;
  description: string;
  entries: [string, SettingValue][];
  original: Record<string, SettingValue>;
  changes: Record<string, SettingValue>;
  onChange: (key: string, value: SettingValue) => void;
}) {
  const [open, setOpen] = useState(true);
  const modified = entries.filter(([key]) => key in changes).length;
  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <Card>
        <CollapsibleTrigger asChild>
          <CardHeader className="cursor-pointer select-none">
            <div className="flex items-center justify-between gap-3">
              <div><CardTitle>{label}</CardTitle><CardDescription className="mt-1">{description}</CardDescription></div>
              <div className="flex items-center gap-2">{modified ? <Badge variant="secondary">{modified} changed</Badge> : null}<ChevronsUpDown className="size-4 text-muted-foreground" /></div>
            </div>
          </CardHeader>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <CardContent className="grid gap-5 pt-0 sm:grid-cols-2">
            {entries.map(([key]) => {
              const value = key in changes ? changes[key] : original[key];
              return <div key={key} className="grid content-start gap-2"><div className="flex items-center gap-2"><Label htmlFor={`setting-${key}`} className="font-mono text-xs">{key}</Label>{key in changes ? <Badge variant="outline">modified</Badge> : null}</div><SettingsField name={key} value={value} onChange={(next) => onChange(key, next)} /></div>;
            })}
          </CardContent>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  );
}

export default function ConfigPage() {
  const [settings, setSettings] = useState<Record<string, SettingValue>>({});
  const [changes, setChanges] = useState<Record<string, SettingValue>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    setLoading(true); setError("");
    try { setSettings(await aresApi.configGet() as Record<string, SettingValue>); setChanges({}); }
    catch (reason) { setError(readableError(reason, "Failed to load advanced settings.")); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const editable = useMemo(() => Object.entries(settings).filter(([key]) => !READ_ONLY_KEYS.has(key) && !HIDDEN_KEYS.has(key)) as [string, SettingValue][], [settings]);
  const grouped = useMemo(() => {
    const claimed = new Set<string>();
    const result = GROUPS.map((group) => {
      const entries = editable.filter(([key]) => group.match.test(key));
      entries.forEach(([key]) => claimed.add(key));
      return { ...group, entries };
    }).filter((group) => group.entries.length);
    const other = editable.filter(([key]) => !claimed.has(key));
    return other.length ? [...result, { id: "other", label: "Other", description: "Additional supported WebUI preferences.", match: /.*/, entries: other }] : result;
  }, [editable]);

  function change(key: string, value: SettingValue) {
    setChanges((current) => {
      const next = { ...current };
      if (equal(value, settings[key])) delete next[key]; else next[key] = value;
      return next;
    });
  }

  async function save() {
    if (!Object.keys(changes).length) return;
    setSaving(true); setError(""); setSaved(false);
    try {
      const response = await aresApi.configSave(changes) as Record<string, SettingValue>;
      setSettings(response); setChanges({}); setSaved(true);
      window.setTimeout(() => setSaved(false), 1800);
    } catch (reason) { setError(readableError(reason, "Failed to save advanced settings.")); }
    finally { setSaving(false); }
  }

  return (
    <div className="page-stack">
      <PageHeader title="Advanced Settings" description="WebUI preferences stored in your Local Profile. Identity, connections, and secrets remain in their dedicated surfaces." action={<Button variant="outline" size="sm" onClick={() => void load()} disabled={loading || saving}><RefreshCw /> Refresh</Button>} />
      {error ? <p className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive" role="alert">{error}</p> : null}
      {loading ? <div className="grid justify-items-center gap-3 py-16 text-sm text-muted-foreground"><LoaderCircle className="animate-spin" />Loading settings…</div> : <>
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card px-4 py-3"><p className="text-sm text-muted-foreground">Only changed fields are sent. Server-owned status and authentication fields cannot be edited here.</p><div className="flex gap-2"><Button variant="outline" disabled={!Object.keys(changes).length || saving} onClick={() => setChanges({})}><RotateCcw /> Revert</Button><Button disabled={!Object.keys(changes).length || saving} onClick={() => void save()}>{saving ? <LoaderCircle className="animate-spin" /> : saved ? <Check /> : <Save />}{saved ? "Saved" : "Save changes"}</Button></div></div>
        <div className="grid gap-4">{grouped.map((group) => <SettingsGroup key={group.id} label={group.label} description={group.description} entries={group.entries} original={settings} changes={changes} onChange={change} />)}</div>
        <Card><CardHeader><CardTitle>Runtime diagnostics</CardTitle><CardDescription>Read-only values reported by the running ARES service.</CardDescription></CardHeader><CardContent className="grid gap-2 sm:grid-cols-2">{Object.entries(settings).filter(([key]) => READ_ONLY_KEYS.has(key)).map(([key, value]) => <div key={key} className="flex items-center justify-between gap-4 rounded-md border px-3 py-2"><span className="font-mono text-xs text-muted-foreground">{key}</span><span className="truncate font-mono text-xs">{typeof value === "object" ? JSON.stringify(value) : String(value ?? "—")}</span></div>)}</CardContent></Card>
      </>}
    </div>
  );
}

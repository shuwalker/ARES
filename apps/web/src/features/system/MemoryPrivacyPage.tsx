import { LoaderCircle, Shield } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";

import { SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useLocalProfile } from "@/shared/local-profile";

type SettingValue = string | number | boolean | null | unknown[] | Record<string, unknown>;

function asBool(v: unknown, fallback = false): boolean {
  return typeof v === "boolean" ? v : fallback;
}

function ToggleField({
  id,
  label,
  description,
  checked,
  onChange,
  disabled,
}: {
  id: string;
  label: string;
  description?: string;
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex items-start justify-between gap-4 rounded-lg border border-border/70 bg-card/40 px-3 py-3">
      <div className="grid min-w-0 gap-0.5">
        <Label htmlFor={id} className="text-sm font-medium">
          {label}
        </Label>
        {description ? <p className="text-xs text-muted-foreground">{description}</p> : null}
      </div>
      <ToggleSwitch id={id} checked={checked} onCheckedChange={onChange} disabled={disabled} />
    </div>
  );
}

/**
 * Control Center: memory enablement, external history visibility, and privacy posture.
 * Keys match the previous Settings prefs so stored values survive the move.
 */
export function MemoryPrivacyPage() {
  const { profile, saveProfile } = useLocalProfile();
  const [settings, setSettings] = useState<Record<string, SettingValue>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [status, setStatus] = useState("");
  const [savingKeys, setSavingKeys] = useState<Set<string>>(new Set());
  const saveTimer = useRef<number | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const data = (await aresApi.settingsGet()) as Record<string, SettingValue>;
      setSettings(data);
    } catch (reason) {
      setError(readableError(reason, "Could not load memory & privacy settings."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const flash = useCallback((msg: string) => {
    setStatus(msg);
    window.setTimeout(() => setStatus(""), 1800);
  }, []);

  const patchSettings = useCallback(
    async (patch: Record<string, unknown>) => {
      const keys = Object.keys(patch);
      setSavingKeys((prev) => new Set([...prev, ...keys]));
      setError("");
      try {
        const next = (await aresApi.settingsPost(patch)) as Record<string, SettingValue>;
        setSettings((prev) => ({
          ...prev,
          ...next,
          ...(patch as Record<string, SettingValue>),
        }));
        flash("Saved");
        return next;
      } catch (reason) {
        setError(readableError(reason, "Could not save settings."));
        throw reason;
      } finally {
        setSavingKeys((prev) => {
          const n = new Set(prev);
          keys.forEach((k) => n.delete(k));
          return n;
        });
      }
    },
    [flash],
  );

  const setBool = useCallback(
    (key: string, value: boolean, profileSync?: "context" | "history") => {
      setSettings((prev) => ({ ...prev, [key]: value }));
      if (profileSync === "context") {
        void saveProfile({ ...profile, contextStoreEnabled: value }).catch(() => {});
      }
      if (profileSync === "history") {
        void saveProfile({ ...profile, includeExternalHistory: value }).catch(() => {});
      }
      if (saveTimer.current) window.clearTimeout(saveTimer.current);
      saveTimer.current = window.setTimeout(() => {
        void patchSettings({ [key]: value });
      }, 200);
    },
    [patchSettings, profile, saveProfile],
  );

  const externalHistory = asBool(
    settings.show_cli_sessions,
    profile.includeExternalHistory ?? false,
  );

  return (
    <SurfaceShell
      title="Memory & Privacy"
      description="Control what ARES remembers, which external histories appear, and how private data is handled."
      action={
        status || savingKeys.size ? (
          <Badge variant="secondary" className="font-normal">
            {savingKeys.size ? "Saving…" : status}
          </Badge>
        ) : undefined
      }
    >
      <SurfaceNote>
        These controls used to live under App Settings. They belong here because memory indexing and
        privacy posture are infrastructure — not personalization. Preference keys are unchanged.
      </SurfaceNote>

      {error ? (
        <p
          className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive"
          role="alert"
        >
          {error}
        </p>
      ) : null}

      {loading ? (
        <div className="grid place-items-center gap-3 py-16 text-sm text-muted-foreground">
          <LoaderCircle className="size-5 animate-spin" />
          Loading…
        </div>
      ) : (
        <div className="grid gap-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Shield className="size-4 text-primary" />
                How privacy works
              </CardTitle>
              <CardDescription>
                ARES keeps Companion journal data on this install. Workers keep their own stores;
                ARES never writes another app&apos;s database. External history visibility only
                controls what appears in the session deck — it does not copy or re-host CLI
                transcripts into the Companion journal.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-2 text-xs text-muted-foreground">
              <p>
                <strong className="text-foreground">Local memory</strong> (Context Store) lets the
                Companion recall engineering context from this machine when enabled.
              </p>
              <p>
                <strong className="text-foreground">External AI history</strong> can surface CLI and
                messaging sessions for continuity. Leave it off if you prefer a clean, WebUI-only
                deck.
              </p>
              <p>
                <strong className="text-foreground">Data retention</strong> follows this host&apos;s
                storage: sessions, journal entries, and secrets remain until you delete them or
                clear the underlying store. There is no cloud sync of private history unless you
                configure an external provider yourself.
              </p>
            </CardContent>
          </Card>

          <section className="grid gap-2">
            <h2 className="text-sm font-semibold">Memory</h2>
            <ToggleField
              id="context_store_enabled"
              label="Enable Context Store"
              description="Local memory so Companion can recall engineering context."
              checked={asBool(settings.context_store_enabled, profile.contextStoreEnabled ?? false)}
              onChange={(v) => setBool("context_store_enabled", v, "context")}
            />
          </section>

          <section className="grid gap-2">
            <h2 className="text-sm font-semibold">External history</h2>
            <ToggleField
              id="show_cli_sessions"
              label="Include external AI history"
              description="Show CLI-discovered conversations. Off by default for privacy."
              checked={externalHistory}
              onChange={(v) => setBool("show_cli_sessions", v, "history")}
            />
            <ToggleField
              id="show_claude_code_sessions"
              label="Show Claude Code sessions"
              description="Within external history, include Claude Code imports."
              checked={asBool(settings.show_claude_code_sessions, true)}
              onChange={(v) => setBool("show_claude_code_sessions", v)}
              disabled={!externalHistory}
            />
            <ToggleField
              id="show_cron_sessions"
              label="Show schedule/cron sessions"
              description="Surface scheduled job runs as conversations."
              checked={asBool(settings.show_cron_sessions)}
              onChange={(v) => setBool("show_cron_sessions", v)}
              disabled={!externalHistory}
            />
            <ToggleField
              id="show_webhook_sessions"
              label="Show webhook sessions"
              description="Surface webhook runs in the deck."
              checked={asBool(settings.show_webhook_sessions)}
              onChange={(v) => setBool("show_webhook_sessions", v)}
              disabled={!externalHistory}
            />
            <ToggleField
              id="show_previous_messaging_sessions"
              label="Show previous messaging sessions"
              description="Older Discord/Telegram/etc. reset segments."
              checked={asBool(settings.show_previous_messaging_sessions)}
              onChange={(v) => setBool("show_previous_messaging_sessions", v)}
            />
          </section>

          <section className="grid gap-2">
            <h2 className="text-sm font-semibold">Data retention & redaction</h2>
            <p className="text-xs text-muted-foreground">
              Retention is host-local. Delete sessions from the Agent deck, revoke shares from Chat
              settings, and manage credentials under Secrets. Redaction strips secrets from API
              payloads returned to the browser.
            </p>
            <ToggleField
              id="api_redact_enabled"
              label="Redact secrets in API responses"
              description="Strip keys and secrets from API payloads (recommended on)."
              checked={asBool(settings.api_redact_enabled, true)}
              onChange={(v) => setBool("api_redact_enabled", v)}
            />
            <ToggleField
              id="sync_to_insights"
              label="Sync usage to insights"
              description="Mirror WebUI token usage into insights storage."
              checked={asBool(settings.sync_to_insights)}
              onChange={(v) => setBool("sync_to_insights", v)}
            />
          </section>

          <div className="flex flex-wrap gap-2">
            <Button asChild variant="outline" size="sm">
              <Link to="/permissions-autonomy">Permissions & Autonomy</Link>
            </Button>
            <Button asChild variant="outline" size="sm">
              <Link to="/secrets">Secrets</Link>
            </Button>
            <Button asChild variant="outline" size="sm">
              <Link to="/settings?section=si">App Settings</Link>
            </Button>
          </div>
        </div>
      )}
    </SurfaceShell>
  );
}

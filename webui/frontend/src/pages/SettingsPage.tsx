import { Check, Monitor, Moon, Save, Sun, Laptop, Globe, AppWindow } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";

import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { useTheme } from "@/context/ThemeContext";
import type { LocalProfile } from "@/shared/contracts";
import { useLocalProfile } from "@/shared/local-profile";
import { useAres } from "@/shared/ares-context";
import { readableError } from "@/shared/api-client";
import { cn } from "@/lib/utils";

const WEBUI_DENSITY_KEY = "ares.webui.density";
const MENUBAR_HINT_KEY = "ares.mac.menubar-hints";

type ThemeChoice = "system" | "light" | "dark";
type Density = "comfortable" | "compact";

function readDensity(): Density {
  try {
    const v = localStorage.getItem(WEBUI_DENSITY_KEY);
    return v === "compact" ? "compact" : "comfortable";
  } catch {
    return "comfortable";
  }
}

function readMenubarHints(): boolean {
  try {
    return localStorage.getItem(MENUBAR_HINT_KEY) !== "0";
  } catch {
    return true;
  }
}

/**
 * Single App Settings surface: identity/profile, appearance, WebUI, and Mac app.
 * Replaces the duplicate profile + settings icons on the rail.
 */
export function SettingsPage() {
  const { profile, saveProfile } = useLocalProfile();
  const { snapshot } = useAres();
  const { theme, preference, setPreference } = useTheme();
  const [draft, setDraft] = useState<LocalProfile>(profile);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");
  const [density, setDensity] = useState<Density>(() => readDensity());
  const [menubarHints, setMenubarHints] = useState(() => readMenubarHints());

  const themeChoice: ThemeChoice = preference;

  useEffect(() => {
    setDraft({ ...profile, assistantName: snapshot.settings?.assistantName || profile.assistantName });
  }, [profile, snapshot.settings?.assistantName]);

  useEffect(() => {
    try {
      localStorage.setItem(WEBUI_DENSITY_KEY, density);
      document.documentElement.dataset.density = density;
    } catch {
      /* ignore */
    }
  }, [density]);

  useEffect(() => {
    try {
      localStorage.setItem(MENUBAR_HINT_KEY, menubarHints ? "1" : "0");
    } catch {
      /* ignore */
    }
  }, [menubarHints]);

  function applyThemeChoice(choice: ThemeChoice) {
    setPreference(choice);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    try {
      await saveProfile(draft);
      setSaved(true);
      window.setTimeout(() => setSaved(false), 1800);
    } catch (reason) {
      setError(readableError(reason, "The profile was cached locally, but could not be persisted by ARES."));
    }
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="App settings"
        description="One place for identity, appearance, WebUI preferences, and Mac app behavior. System workers and infrastructure stay under System."
      />

      <form onSubmit={(event) => void submit(event)} className="grid gap-4 xl:grid-cols-2">
        {/* ── Identity / profile ── */}
        <Card>
          <CardHeader>
            <CardTitle>You & Companion</CardTitle>
            <CardDescription>
              Local profile owned by ARES — available even when no worker is connected.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-5">
            <div className="grid gap-2">
              <Label htmlFor="display-name">What should your SI call you?</Label>
              <Input
                id="display-name"
                value={draft.displayName}
                onChange={(event) => setDraft({ ...draft, displayName: event.target.value })}
                placeholder="Your name"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="assistant-name">Companion name</Label>
              <Input
                id="assistant-name"
                value={draft.assistantName}
                onChange={(event) => setDraft({ ...draft, assistantName: event.target.value })}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="voice">Voice</Label>
              <Select value={draft.voice} onValueChange={(voice) => setDraft({ ...draft, voice })}>
                <SelectTrigger id="voice">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="system-default">System default</SelectItem>
                  <SelectItem value="disabled">Disabled</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="reachability">Reachability</Label>
              <Select
                value={draft.reachability}
                onValueChange={(reachability: LocalProfile["reachability"]) =>
                  setDraft({ ...draft, reachability })
                }
              >
                <SelectTrigger id="reachability">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="this-device">This device</SelectItem>
                  <SelectItem value="local-network">Local network</SelectItem>
                  <SelectItem value="private-network">Private network</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="autonomy">Autonomy</Label>
              <Select
                value={draft.autonomy}
                onValueChange={(autonomy: LocalProfile["autonomy"]) =>
                  setDraft({ ...draft, autonomy })
                }
              >
                <SelectTrigger id="autonomy">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="observe">Observe only</SelectItem>
                  <SelectItem value="confirm">Confirm before acting</SelectItem>
                  <SelectItem value="delegated">Delegated</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <Button type="submit" className="justify-self-start">
              {saved ? <Check /> : <Save />}
              {saved ? "Saved" : "Save profile"}
            </Button>
            {error ? <p className="text-sm text-status-limited">{error}</p> : null}
          </CardContent>
        </Card>

        {/* ── Appearance ── */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Monitor className="size-4" />
              Appearance
            </CardTitle>
            <CardDescription>Color scheme for WebUI (and guidance for Mac surfaces).</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4">
            <div className="grid gap-2">
              <Label>Color scheme</Label>
              <div className="grid grid-cols-3 gap-2">
                {(
                  [
                    { id: "system" as const, label: "System", icon: Laptop },
                    { id: "light" as const, label: "Light", icon: Sun },
                    { id: "dark" as const, label: "Dark", icon: Moon },
                  ] as const
                ).map(({ id, label, icon: Icon }) => (
                  <button
                    key={id}
                    type="button"
                    onClick={() => applyThemeChoice(id)}
                    className={cn(
                      "flex flex-col items-center gap-1.5 rounded-lg border px-3 py-3 text-xs font-medium transition-colors",
                      themeChoice === id
                        ? "border-primary bg-primary/10 text-primary"
                        : "border-border text-muted-foreground hover:border-primary/40 hover:text-foreground",
                    )}
                  >
                    <Icon className="size-4" />
                    {label}
                  </button>
                ))}
              </div>
              <p className="text-xs text-muted-foreground">
                Active: {theme === "dark" ? "dark" : "light"}
                {themeChoice === "system" ? " (following OS)" : ""}.
              </p>
            </div>

            <div className="grid gap-2">
              <Label htmlFor="density">WebUI density</Label>
              <Select value={density} onValueChange={(v: Density) => setDensity(v)}>
                <SelectTrigger id="density">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="comfortable">Comfortable</SelectItem>
                  <SelectItem value="compact">Compact</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>

        {/* ── WebUI ── */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Globe className="size-4" />
              WebUI
            </CardTitle>
            <CardDescription>Browser client preferences for this device.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-5">
            <div className="flex items-center justify-between gap-4">
              <div className="grid gap-1">
                <Label htmlFor="context-store" className="text-base font-semibold">
                  Enable Context Store
                </Label>
                <p className="text-sm text-muted-foreground">
                  Local memory so the Companion can recall engineering context.
                </p>
              </div>
              <ToggleSwitch
                id="context-store"
                checked={draft.contextStoreEnabled ?? false}
                onCheckedChange={(checked) => setDraft({ ...draft, contextStoreEnabled: checked })}
              />
            </div>
            <div className="flex items-center justify-between gap-4">
              <div className="grid gap-1">
                <Label htmlFor="external-history" className="text-base font-semibold">
                  Include external AI history
                </Label>
                <p className="text-sm text-muted-foreground">
                  Show CLI-discovered conversations (Claude Code, etc.). Off by default for privacy.
                </p>
              </div>
              <ToggleSwitch
                id="external-history"
                checked={draft.includeExternalHistory ?? false}
                onCheckedChange={(checked) => setDraft({ ...draft, includeExternalHistory: checked })}
              />
            </div>
            <p className="text-xs text-muted-foreground">
              Connection: {snapshot.connection}
              {snapshot.settings?.version ? ` · ${snapshot.settings.version}` : ""}
            </p>
          </CardContent>
        </Card>

        {/* ── Mac app ── */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <AppWindow className="size-4" />
              Mac app & menu bar
            </CardTitle>
            <CardDescription>
              Preferences for the native ARES Mac app. Values stored here sync as local hints until
              the Mac app reads the same keys.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-5">
            <div className="flex items-center justify-between gap-4">
              <div className="grid gap-1">
                <Label htmlFor="menubar-hints" className="text-base font-semibold">
                  Menu bar presence
                </Label>
                <p className="text-sm text-muted-foreground">
                  Prefer showing ARES in the menu bar when the Mac app is installed (tray /
                  status item).
                </p>
              </div>
              <ToggleSwitch
                id="menubar-hints"
                checked={menubarHints}
                onCheckedChange={setMenubarHints}
              />
            </div>
            <div className="rounded-md border border-dashed border-border bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
              Native Mac app can map this page for: launch at login, menu bar icon, dock visibility,
              and following the same color scheme (System / Light / Dark). Wire those controls into
              the Swift app against the same preference keys when you adjust the Mac target.
            </div>
          </CardContent>
        </Card>
      </form>
    </div>
  );
}

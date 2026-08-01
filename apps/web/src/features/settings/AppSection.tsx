import {
  AppWindow,
  BookOpen,
  Cable,
  ExternalLink,
  KeyRound,
  LoaderCircle,
  MessageSquare,
  Monitor,
  Plug,
  RefreshCw,
  Server,
  Shield,
  SlidersHorizontal,
} from "lucide-react";
import { Link } from "react-router-dom";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";

import { Field, ToggleField } from "./fields";
import { asBool, asString } from "./helpers";
import type { SettingsController } from "./useSettingsController";

export function AppSection({
  snapshot,
  settings,
  setBool,
  setStr,
  menubarHints,
  setMenubarHints,
  newPassword,
  setNewPassword,
  currentPassword,
  setCurrentPassword,
  authBusy,
  plugins,
  extensions,
  setExtensions,
  extStatus,
  listsLoading,
  loadSettings,
  setPassword,
  clearPassword,
  flash,
  setError,
}: Pick<
  SettingsController,
  | "snapshot"
  | "settings"
  | "setBool"
  | "setStr"
  | "menubarHints"
  | "setMenubarHints"
  | "newPassword"
  | "setNewPassword"
  | "currentPassword"
  | "setCurrentPassword"
  | "authBusy"
  | "plugins"
  | "extensions"
  | "setExtensions"
  | "extStatus"
  | "listsLoading"
  | "loadSettings"
  | "setPassword"
  | "clearPassword"
  | "flash"
  | "setError"
>) {
  const authEnabled = asBool(settings.auth_enabled);
  const passwordAuth = asBool(settings.password_auth_enabled);
  const envLocked = asBool(settings.password_env_var);
  const backends = snapshot.backends || [];

  return (
    <div className="grid gap-6">
      <div>
        <h3 className="text-lg font-semibold">App</h3>
        <p className="text-sm text-muted-foreground">
          Access, updates, extensions, and device preferences. Infrastructure controls live in Control Center.
        </p>
      </div>

      <div className="flex flex-wrap gap-2">
        <Badge variant="outline">WebUI: {asString(settings.webui_version, "—")}</Badge>
        <Badge variant="outline">Agent: {asString(settings.agent_version, "not detected")}</Badge>
        {settings.update_channel_version != null && (
          <Badge variant="secondary">{String(settings.update_channel_version)}</Badge>
        )}
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Shield className="size-4" />
            Access password
          </CardTitle>
          <CardDescription>
            {envLocked
              ? "ARES_WEBUI_PASSWORD is set in the environment and overrides UI password changes."
              : authEnabled
                ? passwordAuth
                  ? "Password authentication is enabled."
                  : "Auth is enabled (passkey / other)."
                : "This instance is currently accessible without authentication."}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3">
          {!authEnabled && (
            <div className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs text-amber-800 dark:text-amber-200">
              Unauthenticated access — anyone who can reach this host can use ARES.
            </div>
          )}
          {passwordAuth && (
            <div className="grid gap-2">
              <Label htmlFor="current-password">Current password</Label>
              <Input
                id="current-password"
                type="password"
                autoComplete="current-password"
                value={currentPassword}
                onChange={(e) => setCurrentPassword(e.target.value)}
                disabled={envLocked}
              />
            </div>
          )}
          <div className="grid gap-2">
            <Label htmlFor="new-password">New password</Label>
            <Input
              id="new-password"
              type="password"
              autoComplete="new-password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              disabled={envLocked}
              placeholder="Enter new password…"
            />
          </div>
          <div className="flex flex-wrap gap-2">
            <Button
              type="button"
              disabled={envLocked || authBusy || !newPassword.trim()}
              onClick={() => void setPassword()}
            >
              {authBusy ? <LoaderCircle className="animate-spin" /> : <KeyRound />}
              Set password
            </Button>
            {passwordAuth && (
              <Button
                type="button"
                variant="outline"
                disabled={envLocked || authBusy}
                onClick={() => void clearPassword()}
              >
                Disable auth
              </Button>
            )}
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-2">
        <h4 className="text-sm font-semibold">Updates</h4>
        <ToggleField
          id="check_for_updates"
          label="Check for updates"
          description="Banner when newer WebUI releases are available."
          checked={asBool(settings.check_for_updates, true)}
          onChange={(v) => setBool("check_for_updates", v)}
        />
        <Field label="Update channel">
          <Select
            value={asString(settings.update_channel, "stable")}
            onValueChange={(v) => setStr("update_channel", v)}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="stable">Stable</SelectItem>
              <SelectItem value="experimental">Experimental</SelectItem>
            </SelectContent>
          </Select>
        </Field>
        <ToggleField
          id="ignore_agent_updates"
          label="Ignore agent updates"
          description="Keep WebUI checks; hide agent-specific update notices."
          checked={asBool(settings.ignore_agent_updates)}
          onChange={(v) => setBool("ignore_agent_updates", v)}
        />
        <ToggleField
          id="whats_new_summary_enabled"
          label="Summarize What's New with AI"
          checked={asBool(settings.whats_new_summary_enabled)}
          onChange={(v) => setBool("whats_new_summary_enabled", v)}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <AppWindow className="size-4" />
            Mac app & menu bar
          </CardTitle>
          <CardDescription>Device-local hints for the native ARES Mac app.</CardDescription>
        </CardHeader>
        <CardContent>
          <ToggleField
            id="menubar-hints"
            label="Menu bar presence"
            description="Prefer showing ARES in the menu bar when the Mac app is installed."
            checked={menubarHints}
            onChange={setMenubarHints}
          />
        </CardContent>
      </Card>

      <div className="grid gap-4">
        <div>
          <h4 className="text-sm font-semibold">Connections overview</h4>
          <p className="text-sm text-muted-foreground">
            Configure workers, models, and credentials in Control Center — not here.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button asChild>
            <Link to="/connections">
              <Cable />
              Open Connections
              <ExternalLink className="size-3.5 opacity-70" />
            </Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/secrets">
              <KeyRound />
              Secrets / API keys
            </Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/mcp">
              <Plug />
              MCP servers
            </Link>
          </Button>
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">API</CardTitle>
              <CardDescription>
                {snapshot.connection}
                {snapshot.settings?.version ? ` · ${snapshot.settings.version}` : ""}
              </CardDescription>
            </CardHeader>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Backends</CardTitle>
              <CardDescription>
                {backends.length} discovered · {backends.filter((b) => b.available).length} available
              </CardDescription>
            </CardHeader>
          </Card>
        </div>
      </div>

      <div className="grid gap-4">
        <div>
          <h4 className="text-sm font-semibold">Plugins</h4>
          <p className="text-sm text-muted-foreground">
            Installed agent plugins and lifecycle hooks. Read-only inventory.
          </p>
        </div>
        {listsLoading ? (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <LoaderCircle className="size-4 animate-spin" /> Loading plugins…
          </div>
        ) : plugins.length === 0 ? (
          <p className="text-sm text-muted-foreground">No plugins reported by the running ARES service.</p>
        ) : (
          <div className="grid gap-2">
            {plugins.map((p, i) => {
              const name = String(p.name || p.id || `plugin-${i}`);
              const desc = String(p.description || p.summary || "");
              return (
                <div key={name} className="rounded-lg border px-3 py-2">
                  <p className="text-sm font-medium">{name}</p>
                  {desc ? <p className="text-xs text-muted-foreground">{desc}</p> : null}
                </div>
              );
            })}
          </div>
        )}
      </div>

      <div className="grid gap-4">
        <div>
          <h4 className="text-sm font-semibold">Extensions</h4>
          <p className="text-sm text-muted-foreground">
            WebUI extensions run in the browser origin. Only load trusted packages.
          </p>
        </div>
        {extStatus && (
          <p className="text-xs text-muted-foreground font-mono">
            Status: {JSON.stringify(extStatus).slice(0, 180)}
            {JSON.stringify(extStatus).length > 180 ? "…" : ""}
          </p>
        )}
        {listsLoading ? (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <LoaderCircle className="size-4 animate-spin" /> Loading extensions…
          </div>
        ) : extensions.length === 0 ? (
          <p className="text-sm text-muted-foreground">No extensions in the registry.</p>
        ) : (
          <div className="grid gap-2">
            {extensions.map((ext, i) => {
              const id = String(ext.id || ext.name || `ext-${i}`);
              const enabled = asBool(ext.enabled ?? ext.user_enabled, true);
              return (
                <div key={id} className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{String(ext.name || id)}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {String(ext.description || id)}
                    </p>
                  </div>
                  <ToggleSwitch
                    checked={enabled}
                    onCheckedChange={(v) => {
                      void aresApi
                        .toggleExtension(id, v)
                        .then(() => {
                          setExtensions((prev) =>
                            prev.map((e) =>
                              String(e.id || e.name) === id
                                ? { ...e, enabled: v, user_enabled: v }
                                : e,
                            ),
                          );
                          flash(v ? "Extension enabled" : "Extension disabled");
                        })
                        .catch((reason) =>
                          setError(readableError(reason, "Could not toggle extension.")),
                        );
                    }}
                  />
                </div>
              );
            })}
          </div>
        )}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Control Center & advanced</CardTitle>
          <CardDescription>
            Infrastructure, memory, permissions, and raw preference keys.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          <Button asChild variant="outline">
            <Link to="/config">
              <SlidersHorizontal />
              Advanced settings
            </Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/system">
              <Monitor />
              Control Center
            </Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/memory-privacy">Memory & Privacy</Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/permissions-autonomy">Permissions & Autonomy</Link>
          </Button>
          <Button type="button" variant="outline" onClick={() => void loadSettings()}>
            <RefreshCw />
            Reload settings
          </Button>
        </CardContent>
      </Card>

      <div className="grid gap-2 sm:grid-cols-2">
        <Button asChild variant="outline" className="h-auto justify-start py-3">
          <Link to="/companion">
            <BookOpen />
            <span className="text-left">
              <span className="block font-medium">Life</span>
              <span className="block text-xs text-muted-foreground">SI home & identity</span>
            </span>
          </Link>
        </Button>
        <Button asChild variant="outline" className="h-auto justify-start py-3">
          <Link to="/chat">
            <MessageSquare />
            <span className="text-left">
              <span className="block font-medium">Agent</span>
              <span className="block text-xs text-muted-foreground">Worker console</span>
            </span>
          </Link>
        </Button>
        <Button asChild variant="outline" className="h-auto justify-start py-3">
          <Link to="/connections">
            <Cable />
            <span className="text-left">
              <span className="block font-medium">Connections</span>
              <span className="block text-xs text-muted-foreground">LLMs, workers, defaults</span>
            </span>
          </Link>
        </Button>
        <Button asChild variant="outline" className="h-auto justify-start py-3">
          <Link to="/system">
            <Server />
            <span className="text-left">
              <span className="block font-medium">Control Center</span>
              <span className="block text-xs text-muted-foreground">Health & infrastructure</span>
            </span>
          </Link>
        </Button>
      </div>
    </div>
  );
}

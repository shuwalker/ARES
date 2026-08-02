import { AppWindow, Keyboard } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { NativeSystemSettingsPatch, NativeSystemStatus } from "@/shared/system-settings-contract";

import { ToggleField } from "./fields";

function appliedLabel(desired: boolean, effective: boolean | null) {
  if (effective === null) return "Unavailable";
  return desired === effective ? "Applied" : "Applying…";
}

export function DesktopIntegrationCard({
  system,
  busy,
  update,
}: {
  system: NativeSystemStatus;
  busy: string;
  update: (key: string, patch: NativeSystemSettingsPatch) => Promise<void>;
}) {
  const connected = system.nativeApp.connected;
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle className="flex items-center gap-2">
              <AppWindow className="size-4" /> Desktop integration
            </CardTitle>
            <CardDescription>
              Controls applied by the native ARES Mac app—not browser-only preferences.
            </CardDescription>
          </div>
          <Badge variant={connected ? "secondary" : "outline"}>
            {connected ? "Mac app connected" : "Mac app unavailable"}
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="grid gap-3">
        {!connected ? (
          <p className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-800 dark:text-amber-200">
            Launch the ARES Mac app to change native controls. Nothing on this page will claim a change was applied while it is disconnected.
          </p>
        ) : null}
        <ToggleField
          id="system-menu-bar"
          label="Show ARES in the menu bar"
          description={appliedLabel(system.desired.menuBarEnabled, system.effective.menuBarEnabled)}
          checked={system.desired.menuBarEnabled}
          disabled={!connected || !system.capabilities.menuBar || busy === "menu_bar_enabled"}
          onChange={(value) => void update("menu_bar_enabled", { menuBarEnabled: value })}
        />
        <ToggleField
          id="system-launch-login"
          label="Launch ARES at login"
          description={
            system.capabilities.launchAtLogin
              ? appliedLabel(system.desired.launchAtLogin, system.effective.launchAtLogin)
              : "Available only from the packaged ARES Mac app."
          }
          checked={system.desired.launchAtLogin}
          disabled={!connected || !system.capabilities.launchAtLogin || busy === "launch_at_login"}
          onChange={(value) => void update("launch_at_login", { launchAtLogin: value })}
        />
        <ToggleField
          id="system-quick-launch"
          label="Global quick launch"
          description={`⌘ ⇧ Space · ${appliedLabel(system.desired.quickLaunchEnabled, system.effective.quickLaunchEnabled)}`}
          checked={system.desired.quickLaunchEnabled}
          disabled={!connected || !system.capabilities.quickLaunch || busy === "quick_launch_enabled"}
          onChange={(value) => void update("quick_launch_enabled", { quickLaunchEnabled: value })}
        />
        <div className="flex items-center gap-2 rounded-lg border border-border/70 px-3 py-2 text-xs text-muted-foreground">
          <Keyboard className="size-4" />
          Current shortcut: <span className="font-medium text-foreground">Command + Shift + Space</span>
        </div>
        <ToggleField
          id="system-background"
          label="Keep ARES available in the background"
          description={appliedLabel(system.desired.backgroundOperation, system.effective.backgroundOperation)}
          checked={system.desired.backgroundOperation}
          disabled={!connected || !system.capabilities.backgroundOperation || busy === "background_operation"}
          onChange={(value) => void update("background_operation", { backgroundOperation: value })}
        />
      </CardContent>
    </Card>
  );
}

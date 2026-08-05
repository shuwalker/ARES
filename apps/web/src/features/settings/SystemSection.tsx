import type { SettingsController } from "./useSettingsController";
import { AccessCard } from "./AccessCard";
import { DesktopIntegrationCard } from "./DesktopIntegrationCard";
import { ExtensionsCard } from "./ExtensionsCard";
import { asBool, asString } from "./helpers";
import { LocalRuntimeCard } from "./LocalRuntimeCard";
import { MaintenanceCard } from "./MaintenanceCard";
import { UpdatesCard } from "./UpdatesCard";
import { useSystemSettings } from "./useSystemSettings";

export function SystemSection({
  settings,
  setBool,
  setStr,
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
  | "settings"
  | "setBool"
  | "setStr"
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
  const native = useSystemSettings();
  const authEnabled = asBool(settings.auth_enabled);
  const passwordAuth = asBool(settings.password_auth_enabled);
  const envLocked = asBool(settings.password_env_var);

  return (
    <div className="grid gap-6">
      <div>
        <h3 className="text-lg font-semibold">System</h3>
        <p className="text-sm text-muted-foreground">
          Configure the ARES application, this Mac, and the local controller it owns.
        </p>
      </div>

      {native.error ? <p className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive" role="alert">{native.error}</p> : null}
      {native.loading || !native.system ? <p className="text-sm text-muted-foreground">Loading native ARES status…</p> : (
        <>
          <DesktopIntegrationCard system={native.system} busy={native.busy} update={native.update} />
          <LocalRuntimeCard system={native.system} busy={native.busy} restartServer={native.restartServer} />
        </>
      )}

      <AccessCard
        authEnabled={authEnabled}
        passwordAuth={passwordAuth}
        envLocked={envLocked}
        currentPassword={currentPassword}
        setCurrentPassword={setCurrentPassword}
        newPassword={newPassword}
        setNewPassword={setNewPassword}
        authBusy={authBusy}
        setPassword={setPassword}
        clearPassword={clearPassword}
      />
      <UpdatesCard
        checkForUpdates={asBool(settings.check_for_updates, true)}
        updateChannel={asString(settings.update_channel, "stable")}
        ignoreAgentUpdates={asBool(settings.ignore_agent_updates)}
        whatsNewSummary={asBool(settings.whats_new_summary_enabled)}
        setBool={setBool}
        setStr={setStr}
      />
      <ExtensionsCard
        plugins={plugins}
        extensions={extensions}
        setExtensions={setExtensions}
        extStatus={extStatus}
        listsLoading={listsLoading}
        flash={flash}
        setError={setError}
      />
      <MaintenanceCard
        webVersion={asString(settings.webui_version, "—")}
        agentVersion={asString(settings.agent_version, "not detected")}
        updateVersion={asString(settings.update_channel_version)}
        reload={loadSettings}
      />
    </div>
  );
}

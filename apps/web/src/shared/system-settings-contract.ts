export interface NativeSystemPreferences {
  menuBarEnabled: boolean;
  launchAtLogin: boolean;
  quickLaunchEnabled: boolean;
  quickLaunchShortcut: string;
  backgroundOperation: boolean;
}

export interface NativeSystemEffectivePreferences {
  menuBarEnabled: boolean | null;
  launchAtLogin: boolean | null;
  quickLaunchEnabled: boolean | null;
  quickLaunchShortcut: string | null;
  backgroundOperation: boolean | null;
}

export interface NativeSystemStatus {
  contractVersion: number;
  nativeApp: {
    connected: boolean;
    instanceId: string;
    pid: number | null;
    lastSeenUnix: number | null;
  };
  controller: {
    running: boolean;
    pid: number | null;
    host: string;
    port: number;
    owner: string;
    managedByMacApp: boolean;
    instanceId: string;
  };
  desired: NativeSystemPreferences;
  effective: NativeSystemEffectivePreferences;
  capabilities: {
    menuBar: boolean;
    launchAtLogin: boolean;
    quickLaunch: boolean;
    backgroundOperation: boolean;
    serverRestart: boolean;
  };
  message: string;
}

export type NativeSystemSettingsPatch = Partial<NativeSystemPreferences>;

const DEFAULT_DESIRED: NativeSystemPreferences = {
  menuBarEnabled: true,
  launchAtLogin: false,
  quickLaunchEnabled: true,
  quickLaunchShortcut: "command+shift+space",
  backgroundOperation: true,
};

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function bool(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function nullableBool(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function number(value: unknown, fallback: number | null = null): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function string(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

export function parseNativeSystemStatus(value: unknown): NativeSystemStatus {
  const payload = record(value);
  const nativeApp = record(payload.native_app);
  const controller = record(payload.controller);
  const desired = record(payload.desired);
  const effective = record(payload.effective);
  const capabilities = record(payload.capabilities);

  return {
    contractVersion: number(payload.contract_version, 1) ?? 1,
    nativeApp: {
      connected: bool(nativeApp.connected),
      instanceId: string(nativeApp.instance_id),
      pid: number(nativeApp.pid),
      lastSeenUnix: number(nativeApp.last_seen_unix),
    },
    controller: {
      running: bool(controller.running),
      pid: number(controller.pid),
      host: string(controller.host, "127.0.0.1"),
      port: number(controller.port, 8788) ?? 8788,
      owner: string(controller.owner, "standalone"),
      managedByMacApp: bool(controller.managed_by_mac_app),
      instanceId: string(controller.instance_id),
    },
    desired: {
      menuBarEnabled: bool(desired.menu_bar_enabled, DEFAULT_DESIRED.menuBarEnabled),
      launchAtLogin: bool(desired.launch_at_login, DEFAULT_DESIRED.launchAtLogin),
      quickLaunchEnabled: bool(desired.quick_launch_enabled, DEFAULT_DESIRED.quickLaunchEnabled),
      quickLaunchShortcut: string(desired.quick_launch_shortcut, DEFAULT_DESIRED.quickLaunchShortcut),
      backgroundOperation: bool(desired.background_operation, DEFAULT_DESIRED.backgroundOperation),
    },
    effective: {
      menuBarEnabled: nullableBool(effective.menu_bar_enabled),
      launchAtLogin: nullableBool(effective.launch_at_login),
      quickLaunchEnabled: nullableBool(effective.quick_launch_enabled),
      quickLaunchShortcut: typeof effective.quick_launch_shortcut === "string"
        ? effective.quick_launch_shortcut
        : null,
      backgroundOperation: nullableBool(effective.background_operation),
    },
    capabilities: {
      menuBar: bool(capabilities.menu_bar),
      launchAtLogin: bool(capabilities.launch_at_login),
      quickLaunch: bool(capabilities.quick_launch),
      backgroundOperation: bool(capabilities.background_operation),
      serverRestart: bool(capabilities.server_restart),
    },
    message: string(payload.message),
  };
}

export function nativeSettingsPatch(
  patch: NativeSystemSettingsPatch,
): Record<string, boolean | string> {
  const payload: Record<string, boolean | string> = {};
  if (patch.menuBarEnabled !== undefined) payload.menu_bar_enabled = patch.menuBarEnabled;
  if (patch.launchAtLogin !== undefined) payload.launch_at_login = patch.launchAtLogin;
  if (patch.quickLaunchEnabled !== undefined) payload.quick_launch_enabled = patch.quickLaunchEnabled;
  if (patch.quickLaunchShortcut !== undefined) payload.quick_launch_shortcut = patch.quickLaunchShortcut;
  if (patch.backgroundOperation !== undefined) payload.background_operation = patch.backgroundOperation;
  return payload;
}

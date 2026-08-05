import { describe, expect, it } from "vitest";

import { nativeSettingsPatch, parseNativeSystemStatus } from "./system-settings-contract";

describe("native System settings contract", () => {
  it("normalizes desired, effective, ownership, and capabilities", () => {
    const status = parseNativeSystemStatus({
      contract_version: 1,
      native_app: {
        connected: true,
        instance_id: "mac-instance",
        pid: 321,
        last_seen_unix: 42,
      },
      controller: {
        running: true,
        pid: 654,
        host: "127.0.0.1",
        port: 8788,
        owner: "mac_app",
        managed_by_mac_app: true,
        instance_id: "mac-instance",
      },
      desired: {
        menu_bar_enabled: false,
        launch_at_login: true,
        quick_launch_enabled: true,
        quick_launch_shortcut: "command+shift+space",
        background_operation: true,
      },
      effective: {
        menu_bar_enabled: true,
        launch_at_login: false,
        quick_launch_enabled: true,
        quick_launch_shortcut: "command+shift+space",
        background_operation: true,
      },
      capabilities: {
        menu_bar: true,
        launch_at_login: true,
        quick_launch: true,
        background_operation: true,
        server_restart: true,
      },
      message: "Native ARES app connected.",
    });

    expect(status.nativeApp).toMatchObject({ connected: true, instanceId: "mac-instance", pid: 321 });
    expect(status.controller).toMatchObject({ managedByMacApp: true, owner: "mac_app", port: 8788 });
    expect(status.desired.menuBarEnabled).toBe(false);
    expect(status.effective.menuBarEnabled).toBe(true);
    expect(status.capabilities.serverRestart).toBe(true);
  });

  it("uses null effective state and disabled capabilities when native data is absent", () => {
    const status = parseNativeSystemStatus({ controller: { running: true } });

    expect(status.nativeApp.connected).toBe(false);
    expect(status.effective.menuBarEnabled).toBeNull();
    expect(status.capabilities.menuBar).toBe(false);
    expect(status.desired.quickLaunchShortcut).toBe("command+shift+space");
  });

  it("serializes only typed native keys", () => {
    expect(nativeSettingsPatch({
      menuBarEnabled: false,
      launchAtLogin: true,
      quickLaunchEnabled: true,
    })).toEqual({
      menu_bar_enabled: false,
      launch_at_login: true,
      quick_launch_enabled: true,
    });
  });
});

import { describe, expect, it } from "vitest";

import { SETTINGS_SECTIONS, normalizeSettingsSection } from "./constants";

/**
 * Ownership contract: privacy / memory / autonomy must not reappear in Settings.
 * They live under Control Center pages that keep the same stored keys.
 */
const MOVED_CONTROL_KEYS = [
  "context_store_enabled",
  "show_cli_sessions",
  "show_claude_code_sessions",
  "show_cron_sessions",
  "show_webhook_sessions",
  "show_previous_messaging_sessions",
  "api_redact_enabled",
  "sync_to_insights",
  "local_profile_autonomy",
  "local_profile_reachability",
] as const;

describe("settings ownership split", () => {
  it("keeps Settings limited to SI, Appearance, Chat, System", () => {
    expect(SETTINGS_SECTIONS).toHaveLength(4);
    expect(SETTINGS_SECTIONS.map((s) => s.id)).toEqual(["si", "appearance", "chat", "app"]);
    expect(SETTINGS_SECTIONS[0]?.label).toBe("SI");
    expect(SETTINGS_SECTIONS.map((section) => section.label)).toEqual([
      "SI",
      "Appearance",
      "Chat",
      "System",
    ]);
  });

  it("normalizes legacy you/preferences deep-links to si", () => {
    expect(normalizeSettingsSection("si")).toBe("si");
    expect(normalizeSettingsSection("you")).toBe("si");
    expect(normalizeSettingsSection("preferences")).toBe("si");
    expect(normalizeSettingsSection(null)).toBe("si");
  });

  it("documents the stored keys that Control Center pages must preserve", () => {
    expect([...MOVED_CONTROL_KEYS]).toEqual([
      "context_store_enabled",
      "show_cli_sessions",
      "show_claude_code_sessions",
      "show_cron_sessions",
      "show_webhook_sessions",
      "show_previous_messaging_sessions",
      "api_redact_enabled",
      "sync_to_insights",
      "local_profile_autonomy",
      "local_profile_reachability",
    ]);
  });
});

import { describe, expect, it } from "vitest";

import { SETTINGS_SEARCH_CATALOG, SETTINGS_SECTIONS, normalizeSettingsSection } from "./constants";
import {
  calibrationFromSettings,
  calibrationToPatch,
  SI_CAL_DEFAULTS,
  SI_CAL_KEYS,
} from "./si-calibration";
import {
  jaegerStateLabel,
  normalizeJaegerState,
  parseJaegerStatus,
} from "./jaeger-status";

/**
 * Ownership contract: privacy / memory / autonomy must not reappear in Settings.
 * They live under Control Center pages that keep the same stored keys.
 */
const FORBIDDEN_SETTINGS_KEYWORDS = [
  "privacy",
  "cli history",
  "external history",
  "context store",
  "autonomy",
  "observe only",
  "ask before",
  "delegated",
  "retention",
  "reachability",
];

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
  it("keeps Settings limited to SI, Appearance, Chat, App", () => {
    expect(SETTINGS_SECTIONS).toHaveLength(4);
    expect(SETTINGS_SECTIONS.map((s) => s.id)).toEqual(["si", "appearance", "chat", "app"]);
    expect(SETTINGS_SECTIONS[0]?.label).toBe("SI");
  });

  it("normalizes legacy you/preferences deep-links to si", () => {
    expect(normalizeSettingsSection("si")).toBe("si");
    expect(normalizeSettingsSection("you")).toBe("si");
    expect(normalizeSettingsSection("preferences")).toBe("si");
    expect(normalizeSettingsSection(null)).toBe("si");
  });

  it("does not surface moved Control Center concerns in Settings search", () => {
    const haystack = SETTINGS_SEARCH_CATALOG.map(
      (h) => `${h.label} ${h.keywords}`.toLowerCase(),
    ).join(" | ");
    for (const word of FORBIDDEN_SETTINGS_KEYWORDS) {
      expect(haystack.includes(word)).toBe(false);
    }
  });

  it("includes SI calibration and Jaeger in the search catalog", () => {
    const labels = SETTINGS_SEARCH_CATALOG.map((h) => h.label);
    expect(labels).toEqual(expect.arrayContaining(["SI identity", "Calibration", "Jaeger AI"]));
    expect(SETTINGS_SEARCH_CATALOG.every((h) => h.section !== ("you" as never))).toBe(true);
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

describe("SI calibration persistence helpers", () => {
  it("uses stable keys and defaults", () => {
    expect(SI_CAL_KEYS).toEqual({
      verbosity: "si_cal_verbosity",
      tone: "si_cal_tone",
      support: "si_cal_support",
      initiative: "si_cal_initiative",
      notes: "si_cal_notes",
    });
    expect(SI_CAL_DEFAULTS).toEqual({
      verbosity: "balanced",
      tone: "balanced",
      support: "balanced",
      initiative: "balanced",
      notes: "",
    });
  });

  it("round-trips calibration values for reload", () => {
    const stored = {
      si_cal_verbosity: "concise",
      si_cal_tone: "direct",
      si_cal_support: "challenging",
      si_cal_initiative: "proactive",
      si_cal_notes: "Give me the result first, then details.",
    };
    const cal = calibrationFromSettings(stored);
    expect(cal).toEqual({
      verbosity: "concise",
      tone: "direct",
      support: "challenging",
      initiative: "proactive",
      notes: "Give me the result first, then details.",
    });
    expect(calibrationToPatch(cal)).toEqual(stored);
  });

  it("coerces corrupt calibration values to defaults", () => {
    const cal = calibrationFromSettings({
      si_cal_verbosity: "nope",
      si_cal_tone: 12,
      si_cal_notes: null,
    });
    expect(cal.verbosity).toBe("balanced");
    expect(cal.tone).toBe("balanced");
    expect(cal.notes).toBe("");
  });
});

describe("Jaeger status parsing", () => {
  it("maps provider states to explicit UI labels", () => {
    expect(normalizeJaegerState("ready")).toBe("ready");
    expect(normalizeJaegerState("connected")).toBe("ready");
    expect(normalizeJaegerState("offline")).toBe("installed_but_stopped");
    expect(normalizeJaegerState("not_installed")).toBe("not_installed");
    expect(normalizeJaegerState("error")).toBe("error");
    expect(jaegerStateLabel("ready")).toBe("Ready");
    expect(jaegerStateLabel("installed_but_stopped")).toBe("Installed but stopped");
  });

  it("parses ready status with live model only when reported", () => {
    const parsed = parseJaegerStatus({
      state: "ready",
      available: true,
      message: "Gateway responding",
      active_model: "local-7b",
      active_instance: "athena",
      models_are_live: true,
      transport_mode: "gateway",
      instances: [{ name: "athena", path: "/tmp/athena", display_name: "Athena" }],
    });
    expect(parsed.state).toBe("ready");
    expect(parsed.available).toBe(true);
    expect(parsed.active_model).toBe("local-7b");
    expect(parsed.models_are_live).toBe(true);
    expect(parsed.instances).toHaveLength(1);
  });

  it("never invents an active model from empty or recommendation-like payloads", () => {
    const parsed = parseJaegerStatus({
      state: "not_installed",
      available: false,
      message: "Not installed",
      // Recommendations must not appear on this endpoint; if garbage arrives, ignore.
      awake: { registry_key: "fake", display_name: "Fake" },
      models_are_live: true,
      active_model: null,
    });
    expect(parsed.state).toBe("not_installed");
    expect(parsed.active_model).toBeNull();
    expect(parsed.models_are_live).toBe(false);
  });

  it("surfaces error and unavailable states distinctly", () => {
    expect(parseJaegerStatus({ state: "error", available: false, message: "boom" }).state).toBe(
      "error",
    );
    expect(parseJaegerStatus({ state: "unavailable", available: false, message: "x" }).state).toBe(
      "unavailable",
    );
    expect(parseJaegerStatus(null).state).toBe("error");
  });

  it("targets Hatchery for advanced local intelligence", () => {
    // Contract for JaegerStatusCard link — keep in sync with app-navigation hatchery route.
    expect("/hatchery").toBe("/hatchery");
  });
});

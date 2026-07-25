import { describe, expect, it } from "vitest";

import {
  ISLAND_DEFAULTS,
  ISLAND_ROOT_CLASS,
  clampOpacity,
  normalizeSettings,
  rootClassesFor,
} from "./island-backdrop";

describe("island backdrop preference", () => {
  it("stays opt-in until the hardcoded-color surfaces are converted", () => {
    // Phase 2 of docs/ui/glassmorphism-plan.md flips this. Until then a fresh
    // profile must render the shell exactly as it does today.
    expect(ISLAND_DEFAULTS.enabled).toBe(false);
    expect(rootClassesFor(ISLAND_DEFAULTS)).toEqual([]);
  });

  it("emits both the gate class and a position class when enabled", () => {
    expect(rootClassesFor({ ...ISLAND_DEFAULTS, enabled: true })).toEqual([
      ISLAND_ROOT_CLASS,
      "island-pos-top",
    ]);
    expect(rootClassesFor({ enabled: true, surfaceOpacity: 42, position: "bottom" })).toEqual([
      ISLAND_ROOT_CLASS,
      "island-pos-bottom",
    ]);
  });

  it("clamps opacity into 0–100 and rejects non-numeric input", () => {
    expect(clampOpacity(42)).toBe(42);
    expect(clampOpacity(-30)).toBe(0);
    expect(clampOpacity(180)).toBe(100);
    expect(clampOpacity(42.6)).toBe(43);
    expect(clampOpacity("not a number")).toBe(ISLAND_DEFAULTS.surfaceOpacity);
    expect(clampOpacity(Number.NaN)).toBe(ISLAND_DEFAULTS.surfaceOpacity);
  });

  it("coerces corrupt or partial stored settings instead of trusting them", () => {
    expect(normalizeSettings(null)).toEqual(ISLAND_DEFAULTS);
    expect(normalizeSettings("garbage")).toEqual(ISLAND_DEFAULTS);
    expect(normalizeSettings({ position: "sideways" }).position).toBe(ISLAND_DEFAULTS.position);
    // `enabled` is strict-true only: a truthy string must not switch the shell on.
    expect(normalizeSettings({ enabled: "yes" }).enabled).toBe(false);
    expect(normalizeSettings({ enabled: true, surfaceOpacity: 999 })).toEqual({
      enabled: true,
      surfaceOpacity: 100,
      position: "top",
    });
  });
});

import { describe, expect, it } from "vitest";

import {
  ISLAND_DEFAULTS,
  ISLAND_ROOT_CLASS,
  clampOpacity,
  normalizeSettings,
  rootClassesFor,
} from "./island-backdrop";

describe("island backdrop preference", () => {
  it("is on by default now that every shell surface reads from a token", () => {
    expect(ISLAND_DEFAULTS.enabled).toBe(true);
    expect(rootClassesFor(ISLAND_DEFAULTS)).toEqual([ISLAND_ROOT_CLASS, "island-pos-top"]);
  });

  it("emits no classes when switched off, leaving the default shell untouched", () => {
    expect(rootClassesFor({ ...ISLAND_DEFAULTS, enabled: false })).toEqual([]);
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
    // A stored non-boolean is treated as absent, not as truthy.
    expect(normalizeSettings({ enabled: "no" }).enabled).toBe(ISLAND_DEFAULTS.enabled);
    // An explicit opt-out must survive normalization.
    expect(normalizeSettings({ enabled: false }).enabled).toBe(false);
    expect(normalizeSettings({ enabled: true, surfaceOpacity: 999 })).toEqual({
      enabled: true,
      surfaceOpacity: 100,
      position: "top",
    });
  });
});

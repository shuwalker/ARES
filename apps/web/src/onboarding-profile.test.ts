import { describe, expect, it } from "vitest";

import {
  AUTONOMY_OPTIONS,
  CHARACTER_OPTIONS,
  LIFE_AREA_OPTIONS,
  ONBOARDING_STEPS,
  canFinishIntelligenceStep,
  intelligenceChoiceLabel,
  stepAfterIdentity,
  stepBeforeIntelligence,
} from "./onboarding-profile";

describe("Local Profile onboarding contract", () => {
  it("keeps Quickstart and Advanced on one canonical flow", () => {
    expect(ONBOARDING_STEPS).toEqual([
      "Welcome",
      "You",
      "Jaeger Character",
      "Jaeger Model",
      "Companion",
      "Access",
      "Intelligence",
      "Review",
    ]);
    // After identity ("You"), both modes enter Jaeger character (index 2).
    expect(stepAfterIdentity("quick")).toBe(2);
    expect(stepAfterIdentity("advanced")).toBe(2);
    // Access is index 5; step before Intelligence is Access.
    expect(stepBeforeIntelligence("quick")).toBe(5);
    expect(stepBeforeIntelligence("advanced")).toBe(5);
  });

  it("keeps profile choices bounded and unique", () => {
    expect(new Set(CHARACTER_OPTIONS).size).toBe(CHARACTER_OPTIONS.length);
    expect(new Set(LIFE_AREA_OPTIONS.map(({ id }) => id)).size).toBe(LIFE_AREA_OPTIONS.length);
    expect(AUTONOMY_OPTIONS.map(({ id }) => id)).toEqual(["observe", "confirm", "delegated"]);
  });

  it("requires an explicit intelligence choice before finish", () => {
    expect(canFinishIntelligenceStep(null)).toBe(false);
    expect(canFinishIntelligenceStep({ kind: "organizer_only" })).toBe(true);
    expect(canFinishIntelligenceStep({ kind: "runtime", runtimeId: "" })).toBe(false);
    expect(canFinishIntelligenceStep({ kind: "runtime", runtimeId: "ollama_local" })).toBe(true);
    expect(intelligenceChoiceLabel({ kind: "organizer_only" })).toMatch(/Organizer only/);
  });
});

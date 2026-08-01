import { describe, expect, it } from "vitest";

import { EMPTY_STUDIO_STATE, STUDIO_KIND_LABELS, studioId } from "@/features/studio/studio-state";

describe("Studio state contract", () => {
  it("starts empty and exposes every supported creative medium", () => {
    expect(EMPTY_STUDIO_STATE).toEqual({ projects: [], assets: [] });
    expect(Object.keys(STUDIO_KIND_LABELS)).toEqual([
      "image",
      "video",
      "audio",
      "writing",
      "presentation",
      "3d",
    ]);
  });

  it("creates namespaced record identifiers", () => {
    expect(studioId("asset")).toMatch(/^asset-/);
    expect(studioId("studio")).toMatch(/^studio-/);
  });
});

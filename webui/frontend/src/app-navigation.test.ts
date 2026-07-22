import { describe, expect, it } from "vitest";

import { navigationSections, workspaceRoutes } from "@/app-navigation";

describe("app navigation registry", () => {
  it("is the single unique source for routed sidebar tabs", () => {
    expect(navigationSections.map((section) => section.id)).toEqual([
      "chat",
      "companion",
      "self",
      "workshop",
      "library",
      "system",
    ]);
    expect(navigationSections.map((section) => section.home)).toEqual([
      "/chat",
      "/companion",
      "/self",
      "/workshop",
      "/library",
      "/system",
    ]);
    // Deliberately not a fixed count: routes are added often, and a magic
    // number only ever fails as staleness. Uniqueness below is the real
    // invariant — duplicate paths would silently shadow a page.
    expect(workspaceRoutes.length).toBeGreaterThan(0);
    expect(new Set(workspaceRoutes.map((route) => route.path)).size).toBe(workspaceRoutes.length);
    expect(new Set(workspaceRoutes.map((route) => route.to)).size).toBe(workspaceRoutes.length);
    for (const route of workspaceRoutes) {
      expect(route.to).toBe(`/${route.path}`);
      expect(route.label.length).toBeGreaterThan(0);
      expect(route.component).toBeTypeOf("object");
    }
  });
});

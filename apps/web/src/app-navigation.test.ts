import { describe, expect, it } from "vitest";

import {
  navigationSections,
  sectionForPath,
  workspaceRoutes,
} from "@/app-navigation";
import {
  normalizeSettingsSection,
  SETTINGS_SECTIONS,
} from "@/features/settings/constants";

describe("app navigation registry", () => {
  it("is the single unique source for routed sidebar tabs", () => {
    // Product surfaces: six environments (Settings is not a seventh)
    expect(navigationSections.map((section) => section.id)).toEqual([
      "chat",
      "companion",
      "workshop",
      "studio",
      "library",
      "system",
    ]);
    expect(workspaceRoutes.length).toBe(39);
    expect(navigationSections.find((section) => section.id === "chat")?.label).toBe("Agent");
    expect(navigationSections.find((section) => section.id === "workshop")?.label).toBe("Engineering");
    expect(navigationSections.find((section) => section.id === "studio")?.label).toBe("Studio");
    expect(navigationSections.find((section) => section.id === "companion")?.label).toBe("Life");
    expect(workspaceRoutes.find((route) => route.path === "chat")?.label).toBe("Sessions");
    expect(new Set(workspaceRoutes.map((route) => route.path)).size).toBe(workspaceRoutes.length);
    expect(new Set(workspaceRoutes.map((route) => route.to)).size).toBe(workspaceRoutes.length);
    for (const route of workspaceRoutes) {
      expect(route.to).toBe(`/${route.path}`);
      expect(route.label.length).toBeGreaterThan(0);
      expect(route.component).toBeTypeOf("object");
    }
  });

  it("keeps every existing Control Center destination and adds Memory/Privacy + Permissions", () => {
    const system = navigationSections.find((section) => section.id === "system");
    expect(system?.label).toBe("Control Center");
    const labels = system?.routes.map((r) => r.label) ?? [];
    expect(labels).toEqual(
      expect.arrayContaining([
        "Overview",
        "Workers",
        "Connections",
        "MCP Servers",
        "Skills",
        "Skill Studio",
        "Local Models",
        "Activity",
        "Analytics",
        "Usage & cost",
        "Pairing",
        "Webhooks",
        "Secrets",
        "Advanced settings",
        "Memory & Privacy",
        "Permissions & Autonomy",
      ]),
    );
    expect(workspaceRoutes.find((r) => r.path === "memory-privacy")?.to).toBe("/memory-privacy");
    expect(workspaceRoutes.find((r) => r.path === "permissions-autonomy")?.to).toBe(
      "/permissions-autonomy",
    );
    expect(workspaceRoutes.find((r) => r.path === "hatchery")?.to).toBe("/hatchery");
    // Settings is not registered as a main environment route
    expect(workspaceRoutes.find((r) => r.path === "settings")).toBeUndefined();
    expect(navigationSections.some((s) => s.id === ("settings" as never))).toBe(false);
  });
});

describe("sectionForPath ownership", () => {
  it("treats /settings as a standalone utility, not Life", () => {
    expect(sectionForPath("/settings")).toBe("settings");
    expect(sectionForPath("/settings?section=appearance")).toBe("settings");
    expect(sectionForPath("/settings?section=si")).toBe("settings");
    expect(sectionForPath("/settings/")).toBe("settings");
  });

  it("maps the six environments correctly", () => {
    expect(sectionForPath("/chat")).toBe("chat");
    expect(sectionForPath("/conversation")).toBe("chat");
    expect(sectionForPath("/workshop")).toBe("workshop");
    expect(sectionForPath("/studio")).toBe("studio");
    expect(sectionForPath("/companion")).toBe("companion");
    expect(sectionForPath("/today")).toBe("companion");
    expect(sectionForPath("/self/work")).toBe("companion");
    expect(sectionForPath("/library")).toBe("library");
    expect(sectionForPath("/system")).toBe("system");
    expect(sectionForPath("/memory-privacy")).toBe("system");
    expect(sectionForPath("/permissions-autonomy")).toBe("system");
    expect(sectionForPath("/agents")).toBe("system");
    expect(sectionForPath("/config")).toBe("system");
    expect(sectionForPath("/hatchery")).toBe("system");
  });
});

describe("settings section model", () => {
  it("exposes only the four utility sections with SI first", () => {
    expect(SETTINGS_SECTIONS.map((s) => s.id)).toEqual(["si", "appearance", "chat", "app"]);
    expect(SETTINGS_SECTIONS.map((s) => s.label)).toEqual(["SI", "Appearance", "Chat", "App"]);
  });

  it("normalizes legacy deep-links without losing preferences", () => {
    expect(normalizeSettingsSection("si")).toBe("si");
    expect(normalizeSettingsSection("you")).toBe("si");
    expect(normalizeSettingsSection("preferences")).toBe("si");
    expect(normalizeSettingsSection("appearance")).toBe("appearance");
    expect(normalizeSettingsSection("chat")).toBe("chat");
    expect(normalizeSettingsSection("app")).toBe("app");
    expect(normalizeSettingsSection("conversation")).toBe("chat");
    expect(normalizeSettingsSection("system")).toBe("app");
    expect(normalizeSettingsSection("plugins")).toBe("app");
    expect(normalizeSettingsSection(null)).toBe("si");
    expect(normalizeSettingsSection("unknown")).toBe("si");
  });
});

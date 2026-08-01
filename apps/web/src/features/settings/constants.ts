import {
  AppWindow,
  MessageSquare,
  Palette,
  Sparkles,
} from "lucide-react";

import type { SearchHit, SettingsSectionMeta } from "./types";

export const SETTINGS_SECTIONS: SettingsSectionMeta[] = [
  {
    id: "si",
    label: "SI",
    description: "Synthetic Intelligence identity, calibration, and Jaeger AI.",
    icon: Sparkles,
  },
  {
    id: "appearance",
    label: "Appearance",
    description: "Theme, font size, and visual chrome.",
    icon: Palette,
  },
  {
    id: "chat",
    label: "Chat",
    description: "Composer defaults, transcript tools, and voice.",
    icon: MessageSquare,
  },
  {
    id: "app",
    label: "App",
    description: "Access, updates, extensions, and device prefs.",
    icon: AppWindow,
  },
];

export const SETTINGS_SEARCH_CATALOG: SearchHit[] = [
  {
    section: "si",
    label: "SI identity",
    keywords: "si synthetic intelligence name identity profile companion character voice personality jaeger",
  },
  {
    section: "si",
    label: "Calibration",
    keywords: "calibration concise explanatory direct conversational supportive challenging proactive notes policy guidance",
  },
  {
    section: "si",
    label: "Jaeger AI",
    keywords: "jaeger ai local brain runtime gateway bridge hatchery model instance status",
  },
  { section: "appearance", label: "Theme", keywords: "theme light dark system color scheme" },
  { section: "appearance", label: "Skin", keywords: "skin accent graphite slate poseidon" },
  { section: "appearance", label: "Font size", keywords: "font size accessibility large small" },
  {
    section: "appearance",
    label: "Island backdrop",
    keywords: "island backdrop wallpaper glass glassmorphism blur transparency background",
  },
  { section: "appearance", label: "Activity display", keywords: "worklog transparent stream tools thinking activity" },
  { section: "appearance", label: "Auto-follow", keywords: "scroll follow streaming" },
  { section: "appearance", label: "User markdown", keywords: "markdown user messages" },
  { section: "chat", label: "Export transcript", keywords: "export download markdown json html share clear import" },
  { section: "chat", label: "Send key", keywords: "enter send keyboard composer" },
  { section: "chat", label: "TTS", keywords: "speech tts voice read aloud" },
  { section: "chat", label: "Notifications", keywords: "sound notification browser" },
  { section: "app", label: "Password", keywords: "auth password access security" },
  { section: "app", label: "Updates", keywords: "version update channel" },
  { section: "app", label: "Plugins", keywords: "plugin hooks" },
  { section: "app", label: "Extensions", keywords: "extension gallery install" },
  { section: "app", label: "Mac menu bar", keywords: "menubar mac app device" },
  { section: "app", label: "Advanced settings", keywords: "config raw keys advanced control center" },
];

/** Valid ?section= query values for the Settings hub. */
export function isSettingsSectionId(value: string | null | undefined): value is SettingsSectionMeta["id"] {
  return value === "si" || value === "appearance" || value === "chat" || value === "app";
}

/** Map legacy section ids from older deep-links. */
export function normalizeSettingsSection(raw: string | null | undefined): SettingsSectionMeta["id"] {
  if (isSettingsSectionId(raw)) return raw;
  switch (raw) {
    case "you":
    case "preferences":
      return "si";
    case "conversation":
      return "chat";
    case "connections":
    case "plugins":
    case "extensions":
    case "system":
    case "help":
      return "app";
    case "appearance":
      return "appearance";
    default:
      return "si";
  }
}

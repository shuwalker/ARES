import type { Density, FontSize, ThemeChoice } from "./types";

export const WEBUI_DENSITY_KEY = "ares.webui.density";

export const SKINS = [
  "default",
  "ares",
  "mono",
  "graphite",
  "slate",
  "poseidon",
  "sisyphus",
  "charizard",
  "sienna",
  "catppuccin",
  "nous",
  "geist-contrast",
  "zeus",
  "verdigris",
  "neon-soft",
  "neon-paint",
] as const;

export function asBool(v: unknown, fallback = false): boolean {
  return typeof v === "boolean" ? v : fallback;
}

export function asString(v: unknown, fallback = ""): string {
  return typeof v === "string" ? v : fallback;
}

export function asNumber(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

export function readDensity(): Density {
  try {
    return localStorage.getItem(WEBUI_DENSITY_KEY) === "compact" ? "compact" : "comfortable";
  } catch {
    return "comfortable";
  }
}

export function applyAppearanceToDocument(opts: {
  theme: ThemeChoice;
  skin: string;
  fontSize: FontSize;
  density: Density;
  rtl: boolean;
}) {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  root.dataset.skin = opts.skin || "default";
  root.dataset.fontSize = opts.fontSize || "default";
  root.dataset.density = opts.density;
  root.dir = opts.rtl ? "rtl" : "ltr";
}

export function downloadBlob(filename: string, content: string, mime: string) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

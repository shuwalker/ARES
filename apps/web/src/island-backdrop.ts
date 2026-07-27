/**
 * Island backdrop preference — the glassmorphism shell over the island wallpaper.
 *
 * The visual work lives entirely in `styles/island-backdrop.css`, gated on
 * `html.island-backdrop`. This module owns only the browser-local preference and
 * the class it toggles, mirroring how ThemeContext drives `html.dark`.
 *
 * Storage key and settings shape are carried over from the legacy engine in
 * TBR/20260726-existing-attic/attic/island-backdrop-legacy/background_manager.js, including its
 * `enabled: true` default — every shell surface now reads from a token, so the
 * effect is complete rather than patchy. See docs/ui/glassmorphism-plan.md.
 */

export const ISLAND_STORAGE_KEY = "ares-island-backdrop";
export const ISLAND_ROOT_CLASS = "island-backdrop";

export const ISLAND_POSITIONS = ["top", "center", "bottom"] as const;
export type IslandPosition = (typeof ISLAND_POSITIONS)[number];

export interface IslandBackdropSettings {
  enabled: boolean;
  /** Surface fill percentage, 0–100. Lower means more wallpaper shows through. */
  surfaceOpacity: number;
  position: IslandPosition;
}

export const ISLAND_DEFAULTS: IslandBackdropSettings = {
  enabled: true,
  surfaceOpacity: 42,
  position: "top",
};

export function clampOpacity(value: unknown): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return ISLAND_DEFAULTS.surfaceOpacity;
  return Math.min(100, Math.max(0, Math.round(numeric)));
}

/** Coerces anything — including a corrupt or partial record — into valid settings. */
export function normalizeSettings(raw: unknown): IslandBackdropSettings {
  if (!raw || typeof raw !== "object") return { ...ISLAND_DEFAULTS };
  const record = raw as Record<string, unknown>;
  const position = record.position;
  return {
    // Type-strict rather than truthy: a stored non-boolean is treated as absent
    // and falls back to the default, so junk in storage can neither force the
    // backdrop on nor silently switch it off.
    enabled: typeof record.enabled === "boolean" ? record.enabled : ISLAND_DEFAULTS.enabled,
    surfaceOpacity: clampOpacity(record.surfaceOpacity),
    position: ISLAND_POSITIONS.includes(position as IslandPosition)
      ? (position as IslandPosition)
      : ISLAND_DEFAULTS.position,
  };
}

export function readSettings(): IslandBackdropSettings {
  if (typeof window === "undefined") return { ...ISLAND_DEFAULTS };
  try {
    const stored = window.localStorage.getItem(ISLAND_STORAGE_KEY);
    if (!stored) return { ...ISLAND_DEFAULTS };
    return normalizeSettings(JSON.parse(stored));
  } catch {
    // Unparseable or unavailable storage falls back to defaults rather than
    // throwing during first paint.
    return { ...ISLAND_DEFAULTS };
  }
}

export function writeSettings(settings: IslandBackdropSettings): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(ISLAND_STORAGE_KEY, JSON.stringify(settings));
  } catch {
    // Ignore local storage write failures in restricted environments.
  }
}

/** Class list the root element should carry for the given settings. */
export function rootClassesFor(settings: IslandBackdropSettings): string[] {
  if (!settings.enabled) return [];
  return [ISLAND_ROOT_CLASS, `island-pos-${settings.position}`];
}

export function applySettings(settings: IslandBackdropSettings): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  const next = rootClassesFor(settings);

  root.classList.toggle(ISLAND_ROOT_CLASS, settings.enabled);
  for (const position of ISLAND_POSITIONS) {
    root.classList.toggle(`island-pos-${position}`, next.includes(`island-pos-${position}`));
  }

  if (settings.enabled) {
    root.style.setProperty("--island-surface-opacity", `${settings.surfaceOpacity}%`);
  } else {
    root.style.removeProperty("--island-surface-opacity");
  }
}

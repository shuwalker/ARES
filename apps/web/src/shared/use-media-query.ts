import { useEffect, useState } from "react";

function getMatches(query: string): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }
  return window.matchMedia(query).matches;
}

/**
 * Subscribe to a CSS media query. Initial value is read synchronously on the
 * client so phone layouts do not flash the desktop three-pane shell first.
 *
 * Hermes WebUI uses 640px (phone) and 900px (compact / hide right panel).
 * ARES command-center collapses to single-column + drawers at 900px.
 */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => getMatches(query));

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return;
    }
    const media = window.matchMedia(query);
    const update = () => setMatches(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, [query]);

  return matches;
}

/** ≤900px — Hermes compact: hide docked workbench, use drawers. */
export function useIsCompactViewport(): boolean {
  return useMediaQuery("(max-width: 900px)");
}

/** ≤640px — Hermes phone: full slide-in sidebar, 44px touch targets. */
export function useIsPhoneViewport(): boolean {
  return useMediaQuery("(max-width: 640px)");
}

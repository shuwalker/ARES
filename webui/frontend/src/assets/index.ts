/**
 * Brand assets — the single source of truth for asset URLs in the frontend.
 *
 * Import from here rather than writing string paths. These are resolved by Vite
 * at build time, so a missing or renamed file fails the build instead of
 * shipping a broken image, and each file is content-hashed for cache busting.
 *
 * ## Why some assets are NOT in this folder
 *
 * `public/assets/ares-app-icon.png` deliberately stays in `public/`. The backend
 * hands out its URL as a literal string in `webui/api/characters.py`
 * (`"card_url": "/assets/ares-app-icon.png"`), so the filename is a server-side
 * contract and must not be content-hashed. Moving it would break character cards
 * with no build-time error. Reference it as `APP_ICON_URL` below.
 *
 * Hashed output still lands under `/assets/` (Vite's default `assetsDir`), which
 * keeps it inside the unauthenticated prefix allowlisted in `webui/api/auth.py`.
 */

import aresIslandWide from "./ares-island-wide.png";
import aresSplash from "./ares-splash.jpg";

/** Island wallpaper behind the glassmorphism shell. See docs/ui/glassmorphism-plan.md. */
export const ISLAND_WIDE_URL = aresIslandWide;

/** Full-bleed splash art. Currently unreferenced; exported so the build still emits it. */
export const SPLASH_URL = aresSplash;

/**
 * Spartan helmet app icon. A plain string, not an import: the path is pinned by
 * `characters.py` and must stay unhashed at this exact URL.
 */
export const APP_ICON_URL = "/assets/ares-app-icon.png";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

type Theme = "light" | "dark";
type ThemePreference = Theme | "system";

interface ThemeContextValue {
  theme: Theme;
  /** Effective preference: system follows OS, light/dark are explicit. */
  preference: ThemePreference;
  setTheme: (theme: Theme) => void;
  setPreference: (preference: ThemePreference) => void;
  toggleTheme: () => void;
}

const THEME_STORAGE_KEY = "ares.theme";
const DARK_THEME_COLOR = "#111318";
const LIGHT_THEME_COLOR = "#ffffff";
const ThemeContext = createContext<ThemeContextValue | undefined>(undefined);

function resolveThemeFromDocument(): Theme {
  if (typeof document === "undefined") return "dark";
  return document.documentElement.classList.contains("dark") ? "dark" : "light";
}

function hasStoredTheme(): boolean {
  if (typeof window === "undefined") return false;
  try {
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY);
    return stored === "light" || stored === "dark";
  } catch {
    return false;
  }
}

function applyTheme(theme: Theme) {
  if (typeof document === "undefined") return;
  const isDark = theme === "dark";
  const root = document.documentElement;
  root.classList.toggle("dark", isDark);
  root.style.colorScheme = isDark ? "dark" : "light";
  const themeColorMeta = document.querySelector('meta[name="theme-color"]');
  if (themeColorMeta instanceof HTMLMetaElement) {
    themeColorMeta.setAttribute("content", isDark ? DARK_THEME_COLOR : LIGHT_THEME_COLOR);
  }
}

function osTheme(): Theme {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") return "dark";
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(() => resolveThemeFromDocument());
  // Track whether the user has explicitly chosen a theme. If false, the
  // theme is being derived from the OS `prefers-color-scheme` and should
  // follow OS-level changes mid-session without being persisted.
  const [hasExplicitChoice, setHasExplicitChoice] = useState<boolean>(() => hasStoredTheme());

  const setTheme = useCallback((nextTheme: Theme) => {
    setHasExplicitChoice(true);
    setThemeState(nextTheme);
  }, []);

  const setPreference = useCallback((preference: ThemePreference) => {
    if (preference === "system") {
      setHasExplicitChoice(false);
      try {
        localStorage.removeItem(THEME_STORAGE_KEY);
      } catch {
        // Ignore local storage write failures in restricted environments.
      }
      setThemeState(osTheme());
      return;
    }
    setHasExplicitChoice(true);
    setThemeState(preference);
  }, []);

  const toggleTheme = useCallback(() => {
    setHasExplicitChoice(true);
    setThemeState((current) => (current === "dark" ? "light" : "dark"));
  }, []);

  useEffect(() => {
    applyTheme(theme);
    if (!hasExplicitChoice) return;
    try {
      localStorage.setItem(THEME_STORAGE_KEY, theme);
    } catch {
      // Ignore local storage write failures in restricted environments.
    }
  }, [theme, hasExplicitChoice]);

  // When the user has not made an explicit choice, follow OS-level
  // `prefers-color-scheme` changes so the UI flips alongside the OS theme.
  useEffect(() => {
    if (hasExplicitChoice) return;
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return;
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const handleChange = (event: MediaQueryListEvent) => {
      setThemeState(event.matches ? "dark" : "light");
    };
    media.addEventListener("change", handleChange);
    return () => media.removeEventListener("change", handleChange);
  }, [hasExplicitChoice]);

  const preference: ThemePreference = hasExplicitChoice ? theme : "system";

  const value = useMemo(
    () => ({
      theme,
      preference,
      setTheme,
      setPreference,
      toggleTheme,
    }),
    [theme, preference, setTheme, setPreference, toggleTheme],
  );

  return (
    <ThemeContext.Provider value={value}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error("useTheme must be used within ThemeProvider");
  }
  return context;
}

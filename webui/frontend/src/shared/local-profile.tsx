import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useEffect,
  useState,
  type ReactNode,
} from "react";

import type { LocalProfile } from "@/shared/contracts";
import { apiFetch } from "@/shared/api-client";

const LEGACY_STORAGE_KEY = "ares.local-profile.v1";
const storageKey = (profileScope: string) => `${LEGACY_STORAGE_KEY}:${encodeURIComponent(profileScope)}`;

export const DEFAULT_LOCAL_PROFILE: LocalProfile = {
  displayName: "",
  assistantName: "Ares",
  voice: "system-default",
  reachability: "this-device",
  setupMode: "quick",
  character: "grounded",
  autonomy: "confirm",
  lifeAreas: [],
  includeExternalHistory: false,
};

function loadProfile(profileName: string, includeLegacy = false): LocalProfile {
  if (typeof window === "undefined") return DEFAULT_LOCAL_PROFILE;
  try {
    const stored = window.localStorage.getItem(storageKey(profileName))
      ?? (includeLegacy ? window.localStorage.getItem(LEGACY_STORAGE_KEY) : null);
    if (!stored) return DEFAULT_LOCAL_PROFILE;
    return { ...DEFAULT_LOCAL_PROFILE, ...JSON.parse(stored) } as LocalProfile;
  } catch {
    return DEFAULT_LOCAL_PROFILE;
  }
}

interface LocalProfileContextValue {
  profile: LocalProfile;
  loading: boolean;
  saveProfile: (next: LocalProfile) => Promise<void>;
}

const LocalProfileContext = createContext<LocalProfileContextValue | undefined>(undefined);

export function LocalProfileProvider({ children }: { children: ReactNode }) {
  const [profile, setProfile] = useState<LocalProfile>(DEFAULT_LOCAL_PROFILE);
  const [profileName, setProfileName] = useState("default");
  const [loading, setLoading] = useState(true);

  const cacheProfile = useCallback((next: LocalProfile, scope = profileName) => {
    setProfile(next);
    try {
      window.localStorage.setItem(storageKey(scope), JSON.stringify(next));
    } catch {
      // The profile remains usable for this session if storage is unavailable.
    }
  }, [profileName]);

  const saveProfile = useCallback(async (next: LocalProfile) => {
    cacheProfile(next);
    await apiFetch("/api/settings", {
      method: "POST",
      body: JSON.stringify({
        owner_name: next.displayName.trim(),
        bot_name: next.assistantName.trim() || "Ares",
        local_profile_voice: next.voice,
        local_profile_reachability: next.reachability,
        local_profile_setup_mode: next.setupMode,
        local_profile_character: next.character,
        local_profile_autonomy: next.autonomy,
        local_profile_life_areas: next.lifeAreas,
        context_store_enabled: next.contextStoreEnabled ?? false,
        show_cli_sessions: next.includeExternalHistory ?? false,
      }),
    });
  }, [cacheProfile]);

  useEffect(() => {
    let active = true;
    Promise.all([
      apiFetch<Record<string, unknown>>("/api/settings"),
      apiFetch<{ name?: string; path?: string }>("/api/profile/active").catch(() => ({ name: "default", path: "" })),
    ])
      .then(async ([settings, activeProfile]) => {
        if (!active) return;
        const activeName = String(activeProfile.name || "default");
        const activePath = String(activeProfile.path || activeName);
        const scope = `${activeName}:${activePath}`;
        setProfileName(scope);
        const cached = loadProfile(
          scope,
          activeName === "default" && settings.onboarding_completed === true,
        );
        const ownerName = String(settings.owner_name || "").trim();
        const serverProfile: LocalProfile = {
          displayName: ownerName || cached.displayName,
          assistantName: String(settings.bot_name || cached.assistantName || "Ares"),
          voice: settings.local_profile_voice === "disabled" || settings.local_profile_voice === "system-default"
            ? settings.local_profile_voice
            : cached.voice,
          reachability: (["this-device", "local-network", "private-network"].includes(String(settings.local_profile_reachability))
            ? String(settings.local_profile_reachability)
            : cached.reachability) as LocalProfile["reachability"],
          setupMode: (settings.local_profile_setup_mode === "advanced" ? "advanced" : "quick"),
          character: (["grounded", "warm", "direct", "curious"].includes(String(settings.local_profile_character))
            ? String(settings.local_profile_character)
            : cached.character) as LocalProfile["character"],
          autonomy: (["observe", "confirm", "delegated"].includes(String(settings.local_profile_autonomy))
            ? String(settings.local_profile_autonomy)
            : cached.autonomy) as LocalProfile["autonomy"],
          lifeAreas: (Array.isArray(settings.local_profile_life_areas)
            ? settings.local_profile_life_areas
            : cached.lifeAreas).filter((area): area is LocalProfile["lifeAreas"][number] =>
              ["finance", "health", "work", "home", "projects"].includes(String(area))),
          contextStoreEnabled: typeof settings.context_store_enabled === "boolean"
            ? settings.context_store_enabled
            : cached.contextStoreEnabled,
          includeExternalHistory: typeof settings.show_cli_sessions === "boolean"
            ? settings.show_cli_sessions
            : cached.includeExternalHistory,
        };
        cacheProfile(serverProfile, scope);
        // One-time upgrade path for installs that completed onboarding before
        // owner_name became server-authoritative. Never import browser identity
        // into a fresh or non-default profile.
        if (!ownerName && cached.displayName.trim() && settings.onboarding_completed === true && activeName === "default") {
          await apiFetch("/api/settings", {
            method: "POST",
            body: JSON.stringify({
              owner_name: cached.displayName.trim(),
              bot_name: serverProfile.assistantName.trim() || "Ares",
              local_profile_voice: serverProfile.voice,
              local_profile_reachability: serverProfile.reachability,
              local_profile_setup_mode: serverProfile.setupMode,
              local_profile_character: serverProfile.character,
              local_profile_autonomy: serverProfile.autonomy,
              local_profile_life_areas: serverProfile.lifeAreas,
              context_store_enabled: serverProfile.contextStoreEnabled ?? false,
              show_cli_sessions: serverProfile.includeExternalHistory ?? false,
            }),
          });
        }
      })
      .catch(() => {
        // The cached profile remains the honest offline fallback.
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => { active = false; };
  }, [cacheProfile]);

  const value = useMemo(() => ({ profile, loading, saveProfile }), [profile, loading, saveProfile]);
  return <LocalProfileContext.Provider value={value}>{children}</LocalProfileContext.Provider>;
}

export function useLocalProfile() {
  const value = useContext(LocalProfileContext);
  if (!value) throw new Error("useLocalProfile must be used within LocalProfileProvider");
  return value;
}

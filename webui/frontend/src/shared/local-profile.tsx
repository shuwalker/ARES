import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";

import type { LocalProfile } from "@/shared/contracts";

const STORAGE_KEY = "ares.local-profile.v1";

export const DEFAULT_LOCAL_PROFILE: LocalProfile = {
  displayName: "",
  assistantName: "Ares",
  voice: "system-default",
  reachability: "this-device",
};

function loadProfile(): LocalProfile {
  if (typeof window === "undefined") return DEFAULT_LOCAL_PROFILE;
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (!stored) return DEFAULT_LOCAL_PROFILE;
    return { ...DEFAULT_LOCAL_PROFILE, ...JSON.parse(stored) } as LocalProfile;
  } catch {
    return DEFAULT_LOCAL_PROFILE;
  }
}

interface LocalProfileContextValue {
  profile: LocalProfile;
  saveProfile: (next: LocalProfile) => void;
}

const LocalProfileContext = createContext<LocalProfileContextValue | undefined>(undefined);

export function LocalProfileProvider({ children }: { children: ReactNode }) {
  const [profile, setProfile] = useState<LocalProfile>(loadProfile);
  const saveProfile = useCallback((next: LocalProfile) => {
    setProfile(next);
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
    } catch {
      // The profile remains usable for this session if storage is unavailable.
    }
  }, []);
  const value = useMemo(() => ({ profile, saveProfile }), [profile, saveProfile]);
  return <LocalProfileContext.Provider value={value}>{children}</LocalProfileContext.Provider>;
}

export function useLocalProfile() {
  const value = useContext(LocalProfileContext);
  if (!value) throw new Error("useLocalProfile must be used within LocalProfileProvider");
  return value;
}

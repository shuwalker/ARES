import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";

export type SettingsSectionId = "si" | "appearance" | "chat" | "app";

export type ThemeChoice = "system" | "light" | "dark";
export type FontSize = "small" | "default" | "large" | "xlarge";
export type Density = "comfortable" | "compact";
export type SettingValue = string | number | boolean | null | unknown[] | Record<string, unknown>;

/** SI calibration dimensions — persisted as discrete enums. */
export type SiCalVerbosity = "concise" | "balanced" | "explanatory";
export type SiCalTone = "direct" | "balanced" | "conversational";
export type SiCalSupport = "supportive" | "balanced" | "challenging";
export type SiCalInitiative = "reactive" | "balanced" | "proactive";

export interface SiCalibration {
  verbosity: SiCalVerbosity;
  tone: SiCalTone;
  support: SiCalSupport;
  initiative: SiCalInitiative;
  notes: string;
}

export interface SettingsSectionMeta {
  id: SettingsSectionId;
  label: string;
  description: string;
  icon: LucideIcon;
}

export interface SearchHit {
  section: SettingsSectionId;
  label: string;
  keywords: string;
}

export interface FieldProps {
  id?: string;
  label: string;
  description?: string;
  children: ReactNode;
  searchId?: string;
}

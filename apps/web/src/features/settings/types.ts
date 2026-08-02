import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";

export type SettingsSectionId = "si" | "appearance" | "chat" | "app";

export type ThemeChoice = "system" | "light" | "dark";
export type FontSize = "small" | "default" | "large" | "xlarge";
export type Density = "comfortable" | "compact";
export type SettingValue = string | number | boolean | null | unknown[] | Record<string, unknown>;

export interface SettingsSectionMeta {
  id: SettingsSectionId;
  label: string;
  description: string;
  icon: LucideIcon;
}

export interface FieldProps {
  id?: string;
  label: string;
  description?: string;
  children: ReactNode;
  searchId?: string;
}

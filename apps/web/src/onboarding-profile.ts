import type { LocalProfile } from "@/shared/contracts";

export const ONBOARDING_STEPS = [
  "Welcome",
  "You",
  "Jaeger Character",
  "Jaeger Model",
  "Companion",
  "Access",
  "Intelligence",
  "Review",
] as const;

export const CHARACTER_OPTIONS: LocalProfile["character"][] = [
  "grounded",
  "warm",
  "direct",
  "curious",
];

export const LIFE_AREA_OPTIONS: Array<{
  id: LocalProfile["lifeAreas"][number];
  label: string;
}> = [
  { id: "finance", label: "Finance" },
  { id: "health", label: "Health" },
  { id: "work", label: "Work" },
  { id: "home", label: "Home" },
  { id: "projects", label: "Projects" },
];

export const AUTONOMY_OPTIONS: Array<{
  id: LocalProfile["autonomy"];
  label: string;
  detail: string;
}> = [
  { id: "observe", label: "Tell me things", detail: "Surface changes and suggestions. Do not act." },
  { id: "confirm", label: "Ask before acting", detail: "Prepare work, then request confirmation for consequential actions." },
  { id: "delegated", label: "Handle delegated work", detail: "Act within explicit scopes. System permission gates still apply." },
];

export function stepAfterIdentity(mode: LocalProfile["setupMode"]): 2 {
  return 2; // Always go to the Jaeger AI character step after identity
}

export function stepBeforeIntelligence(mode: LocalProfile["setupMode"]): 5 {
  return 5; // Access step is now at index 5
}

/** First-run intelligence selection — nothing is pre-selected. */
export type IntelligenceChoice =
  | { kind: "runtime"; runtimeId: string }
  | { kind: "organizer_only" }
  | null;

/**
 * Finish setup only after an explicit intelligence choice.
 * A silent default backend is not allowed.
 */
export function canFinishIntelligenceStep(choice: IntelligenceChoice): boolean {
  if (choice === null) return false;
  if (choice.kind === "organizer_only") return true;
  return choice.kind === "runtime" && choice.runtimeId.trim().length > 0;
}

export function intelligenceChoiceLabel(
  choice: IntelligenceChoice,
  runtimeName?: string,
): string {
  if (choice === null) return "Not chosen yet";
  if (choice.kind === "organizer_only") return "Organizer only (no AI runtime yet)";
  return runtimeName?.trim() || choice.runtimeId;
}

/** Jaeger AI character for onboarding */
export interface JaegerCharacter {
  id: string;
  name: string;
  description: string;
  role: string;
  voice_tone: string;
  voice_id: string;
}

/** Jaeger AI model recommendation */
export interface JaegerModel {
  registry_key: string;
  display_name: string;
  size_gb: number;
  score_pct: number;
  tokens_per_task: number;
  notes: string;
}

/** Jaeger AI onboarding state */
export interface JaegerOnboardingState {
  characterId: string | null;
  awakeModel: string | null;
  asleepModel: string | null;
  voiceId: string | null;
}

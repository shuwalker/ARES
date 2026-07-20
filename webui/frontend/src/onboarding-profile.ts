import type { LocalProfile } from "@/shared/contracts";

export const ONBOARDING_STEPS = [
  "Welcome",
  "You",
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

export function stepAfterIdentity(mode: LocalProfile["setupMode"]): 2 | 4 {
  return mode === "quick" ? 4 : 2;
}

export function stepBeforeIntelligence(mode: LocalProfile["setupMode"]): 1 | 3 {
  return mode === "quick" ? 1 : 3;
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

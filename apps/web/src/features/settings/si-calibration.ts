import type {
  SiCalInitiative,
  SiCalSupport,
  SiCalTone,
  SiCalVerbosity,
  SiCalibration,
} from "./types";
import { asString } from "./helpers";

export const SI_CAL_DEFAULTS: SiCalibration = {
  verbosity: "balanced",
  tone: "balanced",
  support: "balanced",
  initiative: "balanced",
  notes: "",
};

export const SI_CAL_KEYS = {
  verbosity: "si_cal_verbosity",
  tone: "si_cal_tone",
  support: "si_cal_support",
  initiative: "si_cal_initiative",
  notes: "si_cal_notes",
} as const;

const VERBOSITY: SiCalVerbosity[] = ["concise", "balanced", "explanatory"];
const TONE: SiCalTone[] = ["direct", "balanced", "conversational"];
const SUPPORT: SiCalSupport[] = ["supportive", "balanced", "challenging"];
const INITIATIVE: SiCalInitiative[] = ["reactive", "balanced", "proactive"];

function pick<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  const s = asString(value, fallback);
  return (allowed as readonly string[]).includes(s) ? (s as T) : fallback;
}

/** Parse stored settings into a typed calibration object. */
export function calibrationFromSettings(settings: Record<string, unknown>): SiCalibration {
  return {
    verbosity: pick(settings[SI_CAL_KEYS.verbosity], VERBOSITY, SI_CAL_DEFAULTS.verbosity),
    tone: pick(settings[SI_CAL_KEYS.tone], TONE, SI_CAL_DEFAULTS.tone),
    support: pick(settings[SI_CAL_KEYS.support], SUPPORT, SI_CAL_DEFAULTS.support),
    initiative: pick(settings[SI_CAL_KEYS.initiative], INITIATIVE, SI_CAL_DEFAULTS.initiative),
    notes: asString(settings[SI_CAL_KEYS.notes], "").slice(0, 2000),
  };
}

/** Payload for settingsPost — only SI calibration keys. */
export function calibrationToPatch(cal: SiCalibration): Record<string, string> {
  return {
    [SI_CAL_KEYS.verbosity]: cal.verbosity,
    [SI_CAL_KEYS.tone]: cal.tone,
    [SI_CAL_KEYS.support]: cal.support,
    [SI_CAL_KEYS.initiative]: cal.initiative,
    [SI_CAL_KEYS.notes]: cal.notes.slice(0, 2000),
  };
}

export const CALIBRATION_DIMENSIONS: Array<{
  key: keyof Omit<SiCalibration, "notes">;
  label: string;
  description: string;
  left: string;
  right: string;
  options: Array<{ id: string; label: string }>;
}> = [
  {
    key: "verbosity",
    label: "Detail level",
    description: "How much explanation accompanies answers.",
    left: "Concise",
    right: "Explanatory",
    options: [
      { id: "concise", label: "Concise" },
      { id: "balanced", label: "Balanced" },
      { id: "explanatory", label: "Explanatory" },
    ],
  },
  {
    key: "tone",
    label: "Tone",
    description: "How formal or conversational replies feel.",
    left: "Direct",
    right: "Conversational",
    options: [
      { id: "direct", label: "Direct" },
      { id: "balanced", label: "Balanced" },
      { id: "conversational", label: "Conversational" },
    ],
  },
  {
    key: "support",
    label: "Challenge style",
    description: "Whether the SI primarily supports or stress-tests ideas.",
    left: "Supportive",
    right: "Challenging",
    options: [
      { id: "supportive", label: "Supportive" },
      { id: "balanced", label: "Balanced" },
      { id: "challenging", label: "Challenging" },
    ],
  },
  {
    key: "initiative",
    label: "Initiative",
    description: "How often the SI offers suggestions unprompted.",
    left: "Reactive",
    right: "Proactive",
    options: [
      { id: "reactive", label: "Reactive" },
      { id: "balanced", label: "Balanced" },
      { id: "proactive", label: "Proactive" },
    ],
  },
];

/** Example policy guidance chips — append to notes; not separate stored keys. */
export const CALIBRATION_EXAMPLES = [
  "Be direct when I am working.",
  "Explain unfamiliar concepts before using jargon.",
  "Challenge assumptions when the evidence is weak.",
  "Give me the result first, then details.",
  "Do not contact other people without confirmation.",
] as const;

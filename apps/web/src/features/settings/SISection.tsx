import { Check } from "lucide-react";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import type { LocalProfile } from "@/shared/contracts";

import { Field } from "./fields";
import { JaegerStatusCard } from "./JaegerStatusCard";
import {
  CALIBRATION_DIMENSIONS,
  CALIBRATION_EXAMPLES,
  calibrationFromSettings,
  calibrationToPatch,
} from "./si-calibration";
import type { SiCalibration } from "./types";
import type { SettingsController } from "./useSettingsController";

/**
 * Settings → SI
 *
 * Identity + calibration + Jaeger peer status. Memory, privacy, autonomy, and
 * reachability remain in Control Center.
 */
export function SISection({
  draft,
  setDraft,
  profileSaved,
  submitProfile,
  settings,
  patchSettings,
  setSettings,
  flash,
  setError,
}: Pick<
  SettingsController,
  | "draft"
  | "setDraft"
  | "profileSaved"
  | "submitProfile"
  | "settings"
  | "patchSettings"
  | "setSettings"
  | "flash"
  | "setError"
>) {
  const [calibration, setCalibration] = useState<SiCalibration>(() =>
    calibrationFromSettings(settings),
  );
  const [calSaving, setCalSaving] = useState(false);
  const [calSaved, setCalSaved] = useState(false);

  // Reload calibration when persisted SI calibration keys change.
  const calFingerprint = [
    settings.si_cal_verbosity,
    settings.si_cal_tone,
    settings.si_cal_support,
    settings.si_cal_initiative,
    settings.si_cal_notes,
  ].join("|");
  useEffect(() => {
    setCalibration(calibrationFromSettings(settings as Record<string, unknown>));
    // eslint-disable-next-line react-hooks/exhaustive-deps -- keyed by calFingerprint
  }, [calFingerprint]);

  const saveCalibration = useCallback(
    async (event?: FormEvent) => {
      event?.preventDefault();
      setCalSaving(true);
      setError("");
      try {
        const patch = calibrationToPatch(calibration);
        await patchSettings(patch, { quiet: true });
        setSettings((prev) => ({ ...prev, ...patch }));
        setCalSaved(true);
        flash("Calibration saved");
        window.setTimeout(() => setCalSaved(false), 1800);
      } catch {
        // patchSettings already sets error
      } finally {
        setCalSaving(false);
      }
    },
    [calibration, flash, patchSettings, setError, setSettings],
  );

  const appendExample = useCallback((line: string) => {
    setCalibration((prev) => {
      const notes = prev.notes.trim();
      if (notes.includes(line)) return prev;
      const next = notes ? `${notes}\n${line}` : line;
      return { ...prev, notes: next.slice(0, 2000) };
    });
  }, []);

  const equation = useMemo(
    () => [
      "model reasoning",
      "identity",
      "memory",
      "rules",
      "tools",
      "verification",
      "feedback",
    ],
    [],
  );

  return (
    <div className="grid gap-6">
      <div>
        <h3 className="text-lg font-semibold">SI</h3>
        <p className="text-sm text-muted-foreground">
          Your persistent Synthetic Intelligence — identity, how it should work with you, and the
          local Jaeger AI runtime. Memory, privacy, and autonomy live in Control Center.
        </p>
      </div>

      {/* 1. What is Synthetic Intelligence? */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">What is Synthetic Intelligence?</CardTitle>
          <CardDescription>
            An LLM predicts useful responses, but it does not independently provide stable identity,
            durable memory, reliable rules, verified actions, or continuity. ARES combines model
            reasoning with deterministic software, memory, policies, tools, and feedback to create a
            persistent Synthetic Intelligence.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4">
          <div
            className="rounded-lg border border-border/70 bg-card/50 px-4 py-3"
            aria-label="Synthetic Intelligence composition"
          >
            <p className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
              Synthetic Intelligence
            </p>
            <ul className="mt-2 flex flex-wrap items-center gap-x-1.5 gap-y-1 text-sm text-foreground">
              {equation.map((part, i) => (
                <li key={part} className="inline-flex items-center gap-1.5">
                  {i === 0 ? (
                    <span className="text-muted-foreground">=</span>
                  ) : (
                    <span className="text-muted-foreground" aria-hidden="true">
                      +
                    </span>
                  )}
                  <span className="rounded-md border border-border/80 bg-background/60 px-2 py-0.5 text-xs font-medium">
                    {part}
                  </span>
                </li>
              ))}
            </ul>
          </div>

          <ul className="grid gap-2 text-xs leading-relaxed text-muted-foreground sm:grid-cols-2">
            <li>
              <strong className="text-foreground">The SI</strong> is the persistent identity you
              talk to — not a one-off model session.
            </li>
            <li>
              <strong className="text-foreground">Jaeger AI</strong> is the default local
              intelligence runtime (a peer product).
            </li>
            <li>
              <strong className="text-foreground">Models</strong> are replaceable reasoning engines.
              Swapping a model does not rename your SI.
            </li>
            <li>
              <strong className="text-foreground">Specialist workers</strong> (Codex, Claude, Hermes,
              Ollama, …) may execute tasks while ARES keeps continuity and provenance.
            </li>
          </ul>
        </CardContent>
      </Card>

      {/* 2. Relationship and identity */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Relationship and identity</CardTitle>
          <CardDescription>
            These names belong to your SI relationship. Changing workers or models underneath
            should not change who you are talking to.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form
            onSubmit={(e: FormEvent) => void submitProfile(e)}
            className="grid gap-4 sm:grid-cols-2"
          >
            <div className="grid gap-2">
              <Label htmlFor="display-name">What should your SI call you?</Label>
              <Input
                id="display-name"
                value={draft.displayName}
                onChange={(e) => setDraft({ ...draft, displayName: e.target.value })}
                autoComplete="nickname"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="assistant-name">SI name</Label>
              <Input
                id="assistant-name"
                value={draft.assistantName}
                onChange={(e) => setDraft({ ...draft, assistantName: e.target.value })}
                placeholder="Jaeger AI"
                autoComplete="off"
              />
              <p className="text-[11px] text-muted-foreground">
                The name shown in chat. This is not a worker or model ID.
              </p>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="si-voice">Voice</Label>
              <Select value={draft.voice} onValueChange={(voice) => setDraft({ ...draft, voice })}>
                <SelectTrigger id="si-voice" aria-label="SI voice">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="system-default">System default</SelectItem>
                  <SelectItem value="disabled">Disabled</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="si-character">Character</Label>
              <Select
                value={draft.character}
                onValueChange={(character: LocalProfile["character"]) =>
                  setDraft({ ...draft, character })
                }
              >
                <SelectTrigger id="si-character" aria-label="SI character">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="grounded">Grounded</SelectItem>
                  <SelectItem value="warm">Warm</SelectItem>
                  <SelectItem value="direct">Direct</SelectItem>
                  <SelectItem value="curious">Curious</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="sm:col-span-2">
              <Button type="submit">
                {profileSaved ? <Check /> : null}
                {profileSaved ? "Saved" : "Save profile"}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      {/* 3. Calibration */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Calibration</CardTitle>
          <CardDescription>
            Teach your SI how to communicate and collaborate. This is policy guidance for context
            assembly — not hard permissions (those stay in Control Center).
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={(e) => void saveCalibration(e)} className="grid gap-5">
            {CALIBRATION_DIMENSIONS.map((dim) => (
              <Field
                key={dim.key}
                label={dim.label}
                description={`${dim.description} (${dim.left} ↔ ${dim.right})`}
              >
                <div className="flex flex-wrap gap-2" role="group" aria-label={dim.label}>
                  {dim.options.map((opt) => {
                    const selected = calibration[dim.key] === opt.id;
                    return (
                      <button
                        key={opt.id}
                        type="button"
                        onClick={() =>
                          setCalibration((prev) => ({
                            ...prev,
                            [dim.key]: opt.id,
                          }))
                        }
                        className={cn(
                          "rounded-md border px-3 py-2 text-xs font-medium transition-colors",
                          selected
                            ? "border-primary bg-primary/10 text-primary"
                            : "border-border text-muted-foreground hover:border-primary/40 hover:text-foreground",
                        )}
                        aria-pressed={selected}
                      >
                        {opt.label}
                      </button>
                    );
                  })}
                </div>
              </Field>
            ))}

            <Field
              id="si-cal-notes"
              label="Personal guidance"
              description="Short rules in your own words. Saved with calibration (max 2000 characters)."
            >
              <Textarea
                id="si-cal-notes"
                value={calibration.notes}
                onChange={(e) =>
                  setCalibration((prev) => ({
                    ...prev,
                    notes: e.target.value.slice(0, 2000),
                  }))
                }
                rows={4}
                placeholder="Example: Give me the result first, then details."
                className="min-h-[6rem] resize-y"
              />
              <div className="mt-2 flex flex-wrap gap-1.5">
                {CALIBRATION_EXAMPLES.map((example) => (
                  <button
                    key={example}
                    type="button"
                    onClick={() => appendExample(example)}
                    className="rounded-full border border-border/80 px-2.5 py-1 text-[11px] text-muted-foreground transition-colors hover:border-primary/40 hover:text-foreground"
                  >
                    + {example}
                  </button>
                ))}
              </div>
            </Field>

            <div>
              <Button type="submit" disabled={calSaving}>
                {calSaved ? <Check /> : null}
                {calSaved ? "Saved" : calSaving ? "Saving…" : "Save calibration"}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      {/* 4. Jaeger AI — live peer status only */}
      <JaegerStatusCard />
    </div>
  );
}

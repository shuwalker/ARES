import {
  ArrowLeft,
  ArrowRight,
  Briefcase,
  Check,
  Cpu,
  Eye,
  Hand,
  HeartPulse,
  Home,
  Laptop,
  LoaderCircle,
  Network,
  ShieldCheck,
  Sparkles,
  Target,
  UserRound,
  WalletCards,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { cn } from "@/lib/utils";
import {
  AUTONOMY_OPTIONS,
  CHARACTER_OPTIONS,
  LIFE_AREA_OPTIONS,
  ONBOARDING_STEPS,
  canFinishIntelligenceStep,
  intelligenceChoiceLabel,
  stepAfterIdentity,
  stepBeforeIntelligence,
  type IntelligenceChoice,
} from "@/onboarding-profile";
import { apiFetch, readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import type { LocalProfile } from "@/shared/contracts";
import { useLocalProfile } from "@/shared/local-profile";

interface ReadinessResponse {
  profile_ready: boolean;
  connection_ready: boolean;
  execution_available: boolean;
}

const lifeAreaIcons = { finance: WalletCards, health: HeartPulse, work: Briefcase, home: Home, projects: Target } as const;
const autonomyIcons = { observe: Eye, confirm: Hand, delegated: Sparkles } as const;

export function ActivationScreen() {
  const navigate = useNavigate();
  const { profile, loading: profileLoading, saveProfile } = useLocalProfile();
  const { snapshot, refresh } = useAres();
  const [draft, setDraft] = useState<LocalProfile>(profile);
  const [step, setStep] = useState(0);
  const [checking, setChecking] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [selecting, setSelecting] = useState("");
  /** Nothing pre-selected — user must pick a runtime or organizer-only. */
  const [intelligenceChoice, setIntelligenceChoice] = useState<IntelligenceChoice>(null);

  const runtimes = useMemo(
    () => snapshot.connections.filter((connection) => connection.kind === "runtime"),
    [snapshot.connections],
  );

  useEffect(() => {
    if (!profileLoading) setDraft(profile);
  }, [profile, profileLoading]);

  useEffect(() => {
    if (profileLoading) return;
    const controller = new AbortController();
    apiFetch<ReadinessResponse>("/api/readiness", { signal: controller.signal })
      .then((readiness) => {
        if (readiness.profile_ready && profile.displayName.trim()) {
          navigate("/today", { replace: true });
        } else {
          setChecking(false);
        }
      })
      .catch((reason) => {
        if (!controller.signal.aborted) {
          setError(readableError(reason, "ARES could not check first-run readiness."));
          setChecking(false);
        }
      });
    return () => controller.abort();
  }, [navigate, profile.displayName, profileLoading]);

  async function saveIdentity() {
    if (!draft.displayName.trim() || !draft.assistantName.trim()) return;
    setSaving(true);
    setError("");
    try {
      const next = { ...draft, displayName: draft.displayName.trim(), assistantName: draft.assistantName.trim() };
      setDraft(next);
      await saveProfile(next);
      setStep(stepAfterIdentity(next.setupMode));
    } catch (reason) {
      setError(readableError(reason, "Your identity was cached locally, but ARES could not persist the Local Profile."));
    } finally {
      setSaving(false);
    }
  }

  async function savePreferences() {
    setSaving(true);
    setError("");
    try {
      await saveProfile(draft);
      setStep(4);
    } catch (reason) {
      setError(readableError(reason, "ARES could not persist your Local Profile."));
    } finally {
      setSaving(false);
    }
  }

  async function selectRuntime(id: string) {
    setSelecting(id);
    setError("");
    try {
      await aresApi.setDefaultBackend(id);
      setIntelligenceChoice({ kind: "runtime", runtimeId: id });
      await refresh();
    } catch (reason) {
      setError(readableError(reason, "ARES could not select that runtime."));
    } finally {
      setSelecting("");
    }
  }

  function chooseOrganizerOnly() {
    setError("");
    setIntelligenceChoice({ kind: "organizer_only" });
  }

  async function finishSetup() {
    if (!canFinishIntelligenceStep(intelligenceChoice)) {
      setError("Choose a worker: pick a detected runtime, or explicitly continue as organizer only. Nothing is selected by default.");
      return;
    }
    setSaving(true);
    setError("");
    try {
      await apiFetch("/api/onboarding/complete", { method: "POST", body: "{}" });
      await refresh();
      setStep(5);
    } catch (reason) {
      setError(readableError(reason, "ARES could not finish setup."));
    } finally {
      setSaving(false);
    }
  }

  if (checking || profileLoading) {
    return (
      <main className="activation-surface grid min-h-dvh place-items-center p-6">
        <div className="grid justify-items-center gap-4 text-center">
          <div className="grid size-14 place-items-center rounded-2xl border border-primary/25 bg-primary/10 text-primary shadow-xl shadow-primary/10">
            <Sparkles className="size-6" />
          </div>
          <div>
            <p className="text-lg font-semibold tracking-tight">Starting your Companion</p>
            <p className="mt-1 text-sm text-muted-foreground">Checking your local system and worker connections…</p>
          </div>
          <LoaderCircle className="size-5 animate-spin text-primary" />
        </div>
      </main>
    );
  }

  return (
    <main className="activation-surface min-h-dvh overflow-auto p-5 sm:p-8">
      <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-5xl flex-col">
        <header className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="grid size-10 place-items-center rounded-xl bg-primary text-primary-foreground shadow-lg shadow-primary/20">
              <Sparkles className="size-5" />
            </div>
            <div>
              <p className="font-semibold tracking-wide">ARES</p>
              <p className="text-xs text-muted-foreground">App for your Companion</p>
            </div>
          </div>
          <Badge variant="outline" className="gap-1.5 text-status-available">
            <ShieldCheck className="size-3.5" /> Local-first
          </Badge>
        </header>

        <div className="mx-auto grid w-full max-w-3xl flex-1 content-center gap-8 py-12">
          <div className="grid gap-5 text-center">
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-primary">First-run setup</p>
            <div>
              <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">
                {[
                  "A personal Companion, built around you.",
                  "Name yourself and your Companion.",
                  `Shape ${draft.assistantName || "your Companion"}.`,
                  "Choose the boundaries.",
                  "Choose which workers run.",
                  "Your Companion is ready.",
                ][step]}
              </h1>
              <p className="mx-auto mt-3 max-w-xl text-sm leading-6 text-muted-foreground sm:text-base">
                {[
                  "ARES is just the app. Your Companion is everything that is not a worker — identity, memory, context, and control. Create a Local Profile first, then pick workers.",
                  "Choose the names used throughout your private workspace. They remain available when every worker is offline.",
                  "Set attention and behavior—not blanket permission. Every macOS and product safety gate remains enforceable.",
                  "Decide reachability (this machine, LAN, or trusted tailnet), context indexing, and optional import of external AI history into your Companion journal.",
                  "Nothing is pre-selected. Pick a detected worker (Ollama, jros, Hermes, cloud, …) or explicitly continue as organizer only.",
                  intelligenceChoice?.kind === "runtime"
                    ? "Your Local Profile and selected worker are ready. Conversations land in the Companion journal with provenance."
                    : "Your Local Profile is ready. Execution stays offline until you connect a worker — the Companion organizer and journal remain available.",
                ][step]}
              </p>
            </div>
            <div className="mx-auto flex items-center gap-2" aria-label={`Setup step ${step + 1} of ${ONBOARDING_STEPS.length}`}>
              {ONBOARDING_STEPS.map((label, index) => (
                <div key={label} className="flex items-center gap-2">
                  <span className={cn("grid size-7 place-items-center rounded-full border text-xs font-semibold", index < step && "border-primary bg-primary text-primary-foreground", index === step && "border-primary text-primary", index > step && "text-muted-foreground")}>
                    {index < step ? <Check className="size-3.5" /> : index + 1}
                  </span>
                  <span className={cn("hidden text-xs sm:inline", index === step ? "text-foreground" : "text-muted-foreground")}>{label}</span>
                  {index < ONBOARDING_STEPS.length - 1 ? <span className="h-px w-6 bg-border sm:w-10" /> : null}
                </div>
              ))}
            </div>
          </div>

          {step === 0 ? (
            <div className="grid gap-4 sm:grid-cols-2">
              {([
                { id: "quick", title: "Quickstart", detail: "Name yourself and your SI, then make an explicit intelligence choice. No backend is assumed.", badge: "About a minute" },
                { id: "advanced", title: "Shape the experience", detail: "Attention, character, autonomy, privacy, reachability, then an explicit runtime pick (or organizer only).", badge: "Full control" },
              ] as const).map((mode) => (
                <button
                  key={mode.id}
                  type="button"
                  onClick={() => { setDraft({ ...draft, setupMode: mode.id }); setStep(1); }}
                  className={cn("group rounded-2xl border bg-card/85 p-6 text-left shadow-xl shadow-black/5 transition hover:-translate-y-0.5 hover:border-primary/60", draft.setupMode === mode.id && "border-primary/60")}
                >
                  <div className="flex items-center justify-between gap-3"><Badge variant="outline">{mode.badge}</Badge><ArrowRight className="size-4 text-muted-foreground transition group-hover:translate-x-1 group-hover:text-primary" /></div>
                  <p className="mt-8 text-xl font-semibold">{mode.title}</p>
                  <p className="mt-2 text-sm leading-6 text-muted-foreground">{mode.detail}</p>
                </button>
              ))}
              <p className="text-center text-xs text-muted-foreground sm:col-span-2">Both paths save the same Local Profile. Quickstart can be expanded later in Settings.</p>
            </div>
          ) : step === 1 ? (
            <Card className="border-border/80 bg-card/85 shadow-2xl shadow-black/10 backdrop-blur-xl">
              <CardContent className="grid gap-6 p-6 sm:p-8">
                <div className="flex items-center gap-3">
                  <div className="grid size-10 place-items-center rounded-xl bg-primary/10 text-primary"><UserRound className="size-5" /></div>
                  <div><p className="font-semibold">Identity</p><p className="text-sm text-muted-foreground">You can change this later in Settings.</p></div>
                </div>
                <div className="grid gap-5 sm:grid-cols-2">
                  <div className="grid gap-2"><Label htmlFor="setup-owner">What should ARES call you?</Label><Input id="setup-owner" autoFocus value={draft.displayName} onChange={(event) => setDraft({ ...draft, displayName: event.target.value })} placeholder="Your name" /></div>
                  <div className="grid gap-2"><Label htmlFor="setup-assistant">What should your SI be called?</Label><Input id="setup-assistant" value={draft.assistantName} onChange={(event) => setDraft({ ...draft, assistantName: event.target.value })} placeholder="Ares" /></div>
                </div>
                <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-between">
                  <Button variant="ghost" onClick={() => setStep(0)}><ArrowLeft />Back</Button>
                  <Button size="lg" disabled={saving || !draft.displayName.trim() || !draft.assistantName.trim()} onClick={() => void saveIdentity()}>
                    {saving ? <LoaderCircle className="animate-spin" /> : null} Continue <ArrowRight />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ) : step === 2 ? (
            <Card className="border-border/80 bg-card/85 shadow-2xl shadow-black/10">
              <CardContent className="grid gap-7 p-6 sm:p-8">
                <div className="grid gap-3">
                  <Label>Companion character</Label>
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                    {CHARACTER_OPTIONS.map((character) => (
                      <button key={character} type="button" onClick={() => setDraft({ ...draft, character })} className={cn("rounded-lg border px-3 py-3 text-sm capitalize transition hover:border-primary/60", draft.character === character && "border-primary bg-primary/10 text-primary")}>{character}</button>
                    ))}
                  </div>
                </div>
                <div className="grid gap-3">
                  <div><Label>Life areas to watch</Label><p className="mt-1 text-xs text-muted-foreground">Attention only. Selecting an area grants no account or system access.</p></div>
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
                    {LIFE_AREA_OPTIONS.map(({ id, label }) => {
                      const Icon = lifeAreaIcons[id];
                      const selected = draft.lifeAreas.includes(id);
                      return <button key={id} type="button" onClick={() => setDraft({ ...draft, lifeAreas: selected ? draft.lifeAreas.filter((area) => area !== id) : [...draft.lifeAreas, id] })} className={cn("grid justify-items-center gap-2 rounded-lg border p-3 text-xs transition hover:border-primary/60", selected && "border-primary bg-primary/10 text-primary")}><Icon className="size-4" />{label}</button>;
                    })}
                  </div>
                </div>
                <div className="grid gap-3">
                  <Label>Default working relationship</Label>
                  <div className="grid gap-2 sm:grid-cols-3">
                    {AUTONOMY_OPTIONS.map(({ id, label, detail }) => { const Icon = autonomyIcons[id]; return <button key={id} type="button" onClick={() => setDraft({ ...draft, autonomy: id })} className={cn("rounded-lg border p-4 text-left transition hover:border-primary/60", draft.autonomy === id && "border-primary bg-primary/10")}><Icon className="size-4 text-primary" /><p className="mt-3 text-sm font-medium">{label}</p><p className="mt-1 text-xs leading-5 text-muted-foreground">{detail}</p></button>; })}
                  </div>
                </div>
                <div className="flex justify-between"><Button variant="ghost" onClick={() => setStep(1)}><ArrowLeft />Back</Button><Button size="lg" onClick={() => setStep(3)}>Continue <ArrowRight /></Button></div>
              </CardContent>
            </Card>
          ) : step === 3 ? (
            <Card className="border-border/80 bg-card/85 shadow-2xl shadow-black/10">
              <CardContent className="grid gap-5 p-6 sm:p-8">
                <div className="grid gap-3"><Label>Reachability</Label><div className="grid gap-2 sm:grid-cols-3">
                  {([
                    { id: "this-device", label: "This machine", detail: "Loopback only", icon: Laptop },
                    { id: "local-network", label: "This network", detail: "Trusted LAN", icon: Network },
                    { id: "private-network", label: "Your tailnet", detail: "Private overlay", icon: ShieldCheck },
                  ] as const).map(({ id, label, detail, icon: Icon }) => <button key={id} type="button" onClick={() => setDraft({ ...draft, reachability: id })} className={cn("rounded-lg border p-4 text-left transition hover:border-primary/60", draft.reachability === id && "border-primary bg-primary/10")}><Icon className="size-4 text-primary" /><p className="mt-3 text-sm font-medium">{label}</p><p className="mt-1 text-xs text-muted-foreground">{detail}</p></button>)}
                </div></div>
                <div className="flex items-center justify-between gap-4 rounded-lg border bg-muted/20 p-4"><div><Label htmlFor="setup-context">Build local searchable context</Label><p className="mt-1 text-xs text-muted-foreground">Off by default. Enable local indexing for workspace search and recall.</p></div><ToggleSwitch id="setup-context" checked={draft.contextStoreEnabled ?? false} onCheckedChange={(checked) => setDraft({ ...draft, contextStoreEnabled: checked })} /></div>
                <div className="flex items-center justify-between gap-4 rounded-lg border bg-muted/20 p-4"><div><Label htmlFor="setup-history">Include existing AI CLI history</Label><p className="mt-1 text-xs text-muted-foreground">Opt in to Claude, Codex, Gemini, and other CLI conversations. Off keeps this profile isolated.</p></div><ToggleSwitch id="setup-history" checked={draft.includeExternalHistory ?? false} onCheckedChange={(checked) => setDraft({ ...draft, includeExternalHistory: checked })} /></div>
                <div className="flex justify-between"><Button variant="ghost" onClick={() => setStep(2)}><ArrowLeft />Back</Button><Button size="lg" disabled={saving} onClick={() => void savePreferences()}>{saving ? <LoaderCircle className="animate-spin" /> : null}Save Local Profile <ArrowRight /></Button></div>
              </CardContent>
            </Card>
          ) : step === 4 ? (
            <div className="grid gap-4">
              <p className="text-center text-xs text-muted-foreground">
                Required step: nothing is selected by default. Your Companion controls routing — you choose the workers.
              </p>
              <div className="grid gap-3 sm:grid-cols-2">
                {runtimes.map((runtime) => {
                  const chosen =
                    intelligenceChoice?.kind === "runtime" && intelligenceChoice.runtimeId === runtime.id;
                  return (
                    <button
                      key={runtime.id}
                      type="button"
                      onClick={() => void selectRuntime(runtime.id)}
                      disabled={!runtime.available || !!selecting}
                      className={cn(
                        "rounded-xl border bg-card/85 p-5 text-left transition hover:border-primary/60 hover:bg-card disabled:cursor-not-allowed disabled:opacity-55",
                        chosen && "border-primary ring-1 ring-primary/30",
                      )}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="grid size-9 place-items-center rounded-lg bg-muted">
                          <Cpu className="size-4" />
                        </div>
                        <Badge
                          variant="outline"
                          className={runtime.available ? "text-status-available" : "text-status-unavailable"}
                        >
                          {chosen
                            ? "Selected"
                            : runtime.state === "connected"
                              ? "Ready"
                              : runtime.state === "needs_attention"
                                ? "Needs setup"
                                : "Offline"}
                        </Badge>
                      </div>
                      <p className="mt-4 font-semibold">{runtime.name}</p>
                      <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{runtime.detail}</p>
                    </button>
                  );
                })}
                {runtimes.length === 0 ? (
                  <Card className="sm:col-span-2">
                    <CardContent className="p-6 text-center text-sm text-muted-foreground">
                      No execution runtime is currently detected. You can still choose organizer only, or open
                      Connections / Hatchery to add Ollama, jros, or another backend.
                    </CardContent>
                  </Card>
                ) : null}
                <button
                  type="button"
                  onClick={chooseOrganizerOnly}
                  className={cn(
                    "rounded-xl border border-dashed bg-card/60 p-5 text-left transition hover:border-primary/60 sm:col-span-2",
                    intelligenceChoice?.kind === "organizer_only" && "border-primary ring-1 ring-primary/30",
                  )}
                >
                  <div className="flex items-start justify-between gap-3">
                    <p className="font-semibold">Organizer only for now</p>
                    <Badge variant="outline">
                      {intelligenceChoice?.kind === "organizer_only" ? "Selected" : "Explicit skip"}
                    </Badge>
                  </div>
                  <p className="mt-2 text-sm text-muted-foreground">
                    Use your Companion for profile, workspace, journal, and tools without an AI execution worker.
                    You can connect Ollama, jros, Hermes, or cloud later — nothing is silently assumed.
                  </p>
                </button>
              </div>
              <Card className="border-dashed">
                <CardContent className="grid gap-4 p-5 sm:grid-cols-[1fr_auto]">
                  <div>
                    <p className="font-medium">Need a runtime first?</p>
                    <p className="mt-1 text-sm text-muted-foreground">
                      Configure Connections or build a private local path in Hatchery. ARES verifies a runtime
                      before treating it as selected.
                    </p>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <Button variant="outline" onClick={() => navigate("/connections")}>
                      <Cpu />
                      Configure connections
                    </Button>
                    <Button variant="outline" onClick={() => navigate("/hatchery")}>
                      <Sparkles />
                      Build a local SI
                    </Button>
                  </div>
                </CardContent>
              </Card>
              <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-between">
                <Button variant="ghost" onClick={() => setStep(stepBeforeIntelligence(draft.setupMode))}>
                  <ArrowLeft />
                  Back
                </Button>
                <Button
                  size="lg"
                  disabled={saving || !canFinishIntelligenceStep(intelligenceChoice)}
                  onClick={() => void finishSetup()}
                >
                  {saving ? <LoaderCircle className="animate-spin" /> : null}
                  Review setup <ArrowRight />
                </Button>
              </div>
            </div>
          ) : (
            <Card className="border-primary/25 bg-card/85 shadow-2xl shadow-primary/10">
              <CardContent className="grid gap-6 p-6 sm:p-8">
                <div className="flex items-center gap-4">
                  <div className="grid size-12 place-items-center rounded-full bg-status-available/15 text-status-available">
                    <Check className="size-6" />
                  </div>
                  <div>
                    <p className="text-xl font-semibold">Welcome, {draft.displayName}.</p>
                    <p className="mt-1 text-sm text-muted-foreground">
                      Review what is saved locally and your explicit intelligence choice.
                    </p>
                  </div>
                </div>
                <div className="grid gap-3 sm:grid-cols-2">
                  <div className="rounded-xl border p-4">
                    <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                      Saved locally
                    </p>
                    <p className="mt-3 font-medium">
                      {draft.assistantName} · {draft.character}
                    </p>
                    <p className="mt-1 text-sm text-muted-foreground">
                      {draft.autonomy === "observe"
                        ? "Observe only"
                        : draft.autonomy === "confirm"
                          ? "Ask before acting"
                          : "Explicit delegation"}{" "}
                      · {draft.reachability.replaceAll("-", " ")}
                    </p>
                    <p className="mt-2 text-xs text-muted-foreground">
                      {draft.lifeAreas.length
                        ? `Watching: ${draft.lifeAreas.join(", ")}`
                        : "No life areas selected yet"}
                    </p>
                  </div>
                  <div className="rounded-xl border p-4">
                    <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                      Intelligence choice
                    </p>
                    <p className="mt-3 font-medium">
                      {intelligenceChoiceLabel(
                        intelligenceChoice,
                        runtimes.find((runtime) => runtime.id === (intelligenceChoice?.kind === "runtime" ? intelligenceChoice.runtimeId : ""))
                          ?.name,
                      )}
                    </p>
                    <p className="mt-1 text-sm text-muted-foreground">
                      {intelligenceChoice?.kind === "runtime"
                        ? "Verified selection. Chat uses this worker; your Companion keeps the unified journal."
                        : "Companion organizer and journal available. Connect a worker when you want execution."}
                    </p>
                  </div>
                </div>
                <div className="flex flex-wrap justify-end gap-3">
                  {intelligenceChoice?.kind !== "runtime" ? (
                    <Button variant="outline" onClick={() => navigate("/hatchery")}>
                      <Sparkles />
                      Build local SI
                    </Button>
                  ) : (
                    <Button variant="outline" onClick={() => navigate("/conversation")}>
                      Open Chat
                    </Button>
                  )}
                  <Button onClick={() => navigate("/today", { replace: true })}>
                    Enter workspace <ArrowRight />
                  </Button>
                </div>
              </CardContent>
            </Card>
          )}

          {error ? <p className="rounded-lg border border-status-limited/30 bg-status-limited/10 px-4 py-3 text-sm text-status-limited" role="alert">{error}</p> : null}
        </div>
      </div>
    </main>
  );
}

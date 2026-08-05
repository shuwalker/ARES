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

  async function chooseOrganizerOnly() {
    setError("");
    setSelecting("unassigned");
    try {
      await aresApi.setDefaultBackend("unassigned");
      setIntelligenceChoice({ kind: "organizer_only" });
      await refresh();
    } catch (reason) {
      setError(readableError(reason, "ARES could not clear the runtime selection."));
    } finally {
      setSelecting("");
    }
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
                  "Jaeger AI Synthetic Intelligence Setup",
                  "Name yourself and your Jaeger AI SI.",
                  `Shape ${draft.assistantName || "Jaeger AI"}.`,
                  "Choose safety & system boundaries.",
                  "Choose local LLM & worker backends.",
                  "Your Jaeger AI Companion is active.",
                ][step]}
              </h1>
              <p className="mx-auto mt-3 max-w-xl text-sm leading-6 text-muted-foreground sm:text-base">
                {[
                  "ARES provides the multi-agent control plane. Your Companion sits above worker backends such as Jaeger AI, Hermes, Claude, and Ollama to maintain relationship continuity, intent routing, and local privacy.",
                  "Set the operator and SI Companion names used throughout your private workspace. They remain active even when subagent workers are offline.",
                  "Configure Jaeger AI persona attention, character tone, and life focus areas.",
                  "Decide reachability (this Mac, LAN, or trusted network) and context indexing policies.",
                  "Select your local LLM engine (Ollama/MLX) or backend runtime to process turns and command subagents.",
                  intelligenceChoice?.kind === "runtime"
                    ? "Your Jaeger AI Local Profile and worker runtime are active. All subagent turns will log transparently with full provenance."
                    : "Your Jaeger AI Local Profile is active. The Companion organizer remains ready to connect workers.",
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
                { id: "quick", title: "Jaeger AI Quickstart", detail: "Set your name and Jaeger AI SI defaults, then select a local or cloud LLM runtime.", badge: "Fast track" },
                { id: "advanced", title: "Custom Character & Architecture", detail: "Configure Jaeger AI persona tone, life areas, autonomy boundaries, and multi-agent routing.", badge: "Full control" },
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
              <p className="text-center text-xs text-muted-foreground sm:col-span-2">Both paths save your Local Profile. You can re-run this character wizard anytime from Companion home.</p>
            </div>
          ) : step === 1 ? (
            <Card className="border-border/80 bg-card/85 shadow-2xl shadow-black/10 backdrop-blur-xl">
              <CardContent className="grid gap-6 p-6 sm:p-8">
                <div className="flex items-center gap-3">
                  <div className="grid size-10 place-items-center rounded-xl bg-primary/10 text-primary"><UserRound className="size-5" /></div>
                  <div><p className="font-semibold">Identity & Companion Name</p><p className="text-sm text-muted-foreground">Define your operator handle and SI name.</p></div>
                </div>
                <div className="grid gap-5 sm:grid-cols-2">
                  <div className="grid gap-2"><Label htmlFor="setup-owner">What should ARES call you?</Label><Input id="setup-owner" autoFocus value={draft.displayName} onChange={(event) => setDraft({ ...draft, displayName: event.target.value })} placeholder="Your name" /></div>
                  <div className="grid gap-2"><Label htmlFor="setup-assistant">What should your SI be called?</Label><Input id="setup-assistant" value={draft.assistantName} onChange={(event) => setDraft({ ...draft, assistantName: event.target.value })} placeholder="Jaeger AI" /></div>
                </div>

                <div className="grid gap-3">
                  <Label htmlFor="setup-avatar">Jaeger AI Profile Avatar (Image URL or Base64)</Label>
                  <Input
                    id="setup-avatar"
                    value={draft.assistantAvatar || ""}
                    onChange={(event) => setDraft({ ...draft, assistantAvatar: event.target.value })}
                    placeholder="https://.../jaeger-avatar.png or data:image/png;base64,..."
                  />
                  <div className="flex items-center gap-3 pt-1">
                    <span className="text-xs text-muted-foreground">Presets:</span>
                    {[
                      { label: "Default Core", val: "" },
                      { label: "Cyber Holographic", val: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=150&auto=format&fit=crop&q=80" },
                      { label: "Quantum Gold", val: "https://images.unsplash.com/photo-1634017839464-5c339ebe3cb4?w=150&auto=format&fit=crop&q=80" },
                      { label: "Deepspace Void", val: "https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=150&auto=format&fit=crop&q=80" },
                    ].map((preset) => (
                      <button
                        key={preset.label}
                        type="button"
                        onClick={() => setDraft({ ...draft, assistantAvatar: preset.val })}
                        className={cn(
                          "rounded-md border px-2.5 py-1 text-xs transition hover:border-primary/60",
                          (draft.assistantAvatar || "") === preset.val && "border-primary bg-primary/10 text-primary font-medium"
                        )}
                      >
                        {preset.label}
                      </button>
                    ))}
                  </div>
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
                      Connections / Hatchery to add Jaeger AI, Ollama, or another backend.
                    </CardContent>
                  </Card>
                ) : null}
                <button
                  type="button"
                  onClick={() => void chooseOrganizerOnly()}
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
                    You can connect Jaeger AI, Ollama, Hermes, or cloud later — nothing is silently assumed.
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

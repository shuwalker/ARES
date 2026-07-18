import { useCallback, useEffect, useState } from "react";
import {
  Check,
  ChevronLeft,
  ChevronRight,
  Cpu,
  Copy,
  Search,
  Server,
  Sparkles,
  User,
} from "lucide-react";
import { apiFetch, readableError } from "@/shared/api-client";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";

const PROFILE_NAME_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/;

type StepId = "identity" | "model" | "skills" | "mcp" | "review";

const STEPS: { id: StepId; label: string; icon: React.ReactNode }[] = [
  { id: "identity", label: "Identity", icon: <User className="h-3.5 w-3.5" /> },
  { id: "model", label: "Model", icon: <Cpu className="h-3.5 w-3.5" /> },
  { id: "skills", label: "Skills", icon: <Sparkles className="h-3.5 w-3.5" /> },
  { id: "mcp", label: "MCPs", icon: <Server className="h-3.5 w-3.5" /> },
  { id: "review", label: "Review", icon: <Check className="h-3.5 w-3.5" /> },
];

interface SkillInfo {
  name: string;
  description: string;
  enabled: boolean;
  category?: string;
}
interface McpServerInfo {
  name: string;
  transport: string;
  enabled: boolean;
}
interface ModelChoice {
  provider: string;
  model: string;
  label: string;
}
interface ProfileOption {
  name: string;
  is_default: boolean;
}

export default function ProfileBuilderPage() {
  const [step, setStep] = useState<StepId>("identity");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [cloneFrom, setCloneFrom] = useState<string>("");
  const [modelChoice, setModelChoice] = useState("");
  const [modelChoices, setModelChoices] = useState<ModelChoice[]>([]);
  const [availableSkills, setAvailableSkills] = useState<SkillInfo[]>([]);
  const [selectedSkills, setSelectedSkills] = useState<string[]>([]);
  const [availableMcps, setAvailableMcps] = useState<McpServerInfo[]>([]);
  const [selectedMcps, setSelectedMcps] = useState<string[]>([]);
  const [existingProfiles, setExistingProfiles] = useState<ProfileOption[]>([]);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState("");
  const [created, setCreated] = useState(false);
  const [skillSearch, setSkillSearch] = useState("");
  const [mcpSearch, setMcpSearch] = useState("");

  const stepIdx = STEPS.findIndex((s) => s.id === step);

  // ── Data loading ────────────────────────────────────────────────────
  useEffect(() => {
    apiFetch<{
      providers: { slug: string; name: string; models: string[] }[];
    }>("/api/models/options")
      .then((res) => {
        const flat: ModelChoice[] = [];
        for (const prov of res.providers ?? []) {
          for (const m of prov.models ?? []) {
            flat.push({
              provider: prov.slug,
              model: m,
              label: `${prov.name} · ${m}`,
            });
          }
        }
        setModelChoices(flat);
      })
      .catch(() => {});

    apiFetch<{ skills: SkillInfo[] }>("/api/skills")
      .then((res) => setAvailableSkills(res.skills ?? []))
      .catch(() => {});

    apiFetch<{ servers: McpServerInfo[] }>("/api/mcp/servers")
      .then((res) => setAvailableMcps(res.servers ?? []))
      .catch(() => {});

    apiFetch<{ profiles: ProfileOption[] }>("/api/profiles")
      .then((res) =>
        setExistingProfiles(
          (res.profiles ?? []).map((p) => ({
            name: p.name,
            is_default: p.is_default,
          })),
        ),
      )
      .catch(() => {});
  }, []);

  // ── Helpers ─────────────────────────────────────────────────────────
  const toggleSkill = (skillName: string) => {
    setSelectedSkills((prev) =>
      prev.includes(skillName)
        ? prev.filter((s) => s !== skillName)
        : [...prev, skillName],
    );
  };

  const toggleMcp = (mcpName: string) => {
    setSelectedMcps((prev) =>
      prev.includes(mcpName)
        ? prev.filter((m) => m !== mcpName)
        : [...prev, mcpName],
    );
  };

  const canProceed = (): boolean => {
    if (step === "identity") return !!name.trim() && PROFILE_NAME_RE.test(name.trim());
    return true;
  };

  const nextStep = () => {
    const idx = stepIdx + 1;
    if (idx < STEPS.length) setStep(STEPS[idx].id);
  };

  const prevStep = () => {
    const idx = stepIdx - 1;
    if (idx >= 0) setStep(STEPS[idx].id);
  };

  // ── Create handler ──────────────────────────────────────────────────
  const handleCreate = async () => {
    if (!name.trim() || !PROFILE_NAME_RE.test(name.trim())) {
      setError(
        "Profile name must be lowercase letters, numbers, hyphens, underscores (1–64 chars).",
      );
      return;
    }
    setCreating(true);
    setError("");
    try {
      const picked = modelChoice
        ? modelChoices.find(
            (c) => `${c.provider}\0${c.model}` === modelChoice,
          )
        : undefined;
      await apiFetch("/api/profiles", {
        method: "POST",
        body: JSON.stringify({
          name: name.trim(),
          description: description.trim() || undefined,
          clone_from: cloneFrom || undefined,
          provider: picked?.provider,
          model: picked?.model,
          skills: selectedSkills.length > 0 ? selectedSkills : undefined,
          mcps: selectedMcps.length > 0 ? selectedMcps : undefined,
        }),
      });
      setCreated(true);
    } catch (e) {
      setError(readableError(e, "Failed to create profile"));
    } finally {
      setCreating(false);
    }
  };

  // ── Filtered lists ──────────────────────────────────────────────────
  const filteredSkills = availableSkills.filter((s) => {
    if (!skillSearch.trim()) return true;
    const q = skillSearch.toLowerCase();
    return (
      s.name.toLowerCase().includes(q) ||
      s.description.toLowerCase().includes(q) ||
      (s.category ?? "").toLowerCase().includes(q)
    );
  });

  const filteredMcps = availableMcps.filter((m) => {
    if (!mcpSearch.trim()) return true;
    const q = mcpSearch.toLowerCase();
    return (
      m.name.toLowerCase().includes(q) ||
      m.transport.toLowerCase().includes(q)
    );
  });

  // Group model choices by provider for better UX
  const modelGroups = modelChoices.reduce<
    Record<string, ModelChoice[]>
  >((acc, c) => {
    const key = c.provider;
    if (!acc[key]) acc[key] = [];
    acc[key].push(c);
    return acc;
  }, {});

  // ── Success state ──────────────────────────────────────────────────
  if (created) {
    return (
      <div className="page-stack">
        <PageHeader
          title="Profile Created"
          description="Your new profile is ready to use."
        />
        <Card>
          <CardContent className="flex flex-col items-center justify-center gap-4 py-12">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-primary/15">
              <Check className="h-8 w-8 text-primary" />
            </div>
            <h3 className="text-lg font-semibold">
              Profile{" "}
              <span className="font-mono">{name.trim()}</span> created
            </h3>
            <p className="text-sm text-muted-foreground max-w-md text-center">
              You can now switch to this profile from the Profiles page, or
              configure it further.
            </p>
            <div className="flex gap-2 mt-2">
              <Button
                variant="outline"
                onClick={() => {
                  setCreated(false);
                  setStep("identity");
                  setName("");
                  setDescription("");
                  setCloneFrom("");
                  setModelChoice("");
                  setSelectedSkills([]);
                  setSelectedMcps([]);
                  setError("");
                }}
              >
                Create Another
              </Button>
              <Button onClick={() => (window.location.href = "/profiles")}>
                Go to Profiles
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  // ── Step indicator ──────────────────────────────────────────────────
  const StepIndicator = () => (
    <div className="flex items-center gap-1 mb-6 overflow-x-auto">
      {STEPS.map((s, i) => (
        <button
          key={s.id}
          className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md whitespace-nowrap transition-colors ${
            i === stepIdx
              ? "bg-primary text-primary-foreground"
              : i < stepIdx
                ? "bg-primary/10 text-primary cursor-pointer hover:bg-primary/20"
                : "bg-muted text-muted-foreground"
          }`}
          onClick={() => {
            if (i < stepIdx) setStep(s.id);
          }}
        >
          {i < stepIdx ? (
            <Check className="h-3 w-3" />
          ) : (
            s.icon
          )}
          {s.label}
        </button>
      ))}
    </div>
  );

  return (
    <div className="page-stack">
      <PageHeader
        title="Profile Builder"
        description="Create a new agent profile step by step."
      />

      <StepIndicator />

      {error && (
        <div className="rounded-md border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive mb-4">
          {error}
        </div>
      )}

      {/* ── Step: Identity ────────────────────────────────────────── */}
      {step === "identity" && (
        <Card>
          <CardContent className="grid gap-5 p-6">
            <div className="grid gap-2">
              <Label htmlFor="pb-name">
                Profile name <span className="text-destructive">*</span>
              </Label>
              <Input
                id="pb-name"
                autoFocus
                placeholder="e.g. coding-assistant, research-mode"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                Lowercase letters, numbers, hyphens, underscores. 1–64 chars.
              </p>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="pb-desc">Description</Label>
              <Textarea
                id="pb-desc"
                placeholder="What is this profile good at?"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={2}
              />
            </div>
            <div className="grid gap-2">
              <Label>Clone from existing profile</Label>
              <Select
                value={cloneFrom}
                onValueChange={(v) =>
                  setCloneFrom(v === "__none__" ? "" : v)
                }
              >
                <SelectTrigger>
                  <SelectValue placeholder="Start from scratch" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">
                    Start from scratch
                  </SelectItem>
                  {existingProfiles.map((p) => (
                    <SelectItem key={p.name} value={p.name}>
                      {p.name}
                      {p.is_default ? " (default)" : ""}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                Cloning copies skills, MCP servers, and settings from another
                profile.
              </p>
            </div>
            <div className="flex justify-end">
              <Button
                onClick={() => setStep("model")}
                disabled={!canProceed()}
              >
                Next
                <ChevronRight className="h-4 w-4 ml-1" />
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Step: Model ────────────────────────────────────────────── */}
      {step === "model" && (
        <Card>
          <CardContent className="grid gap-5 p-6">
            <div>
              <Label className="text-base">Provider & Model</Label>
              <p className="text-sm text-muted-foreground mt-1">
                Choose which LLM provider and model this profile should use. If
                omitted, it inherits from the cloned profile or the system
                default.
              </p>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="pb-model">
                Model <span className="text-muted-foreground font-normal">(optional)</span>
              </Label>
              <Select value={modelChoice} onValueChange={setModelChoice}>
                <SelectTrigger id="pb-model">
                  <SelectValue placeholder="Inherit from clone / default" />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(modelGroups).map(([provider, models]) => (
                    <div key={provider}>
                      <div className="px-2 py-1.5 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                        {provider}
                      </div>
                      {models.map((c) => (
                        <SelectItem
                          key={`${c.provider}\0${c.model}`}
                          value={`${c.provider}\0${c.model}`}
                        >
                          {c.model}
                        </SelectItem>
                      ))}
                    </div>
                  ))}
                  {modelChoices.length === 0 && (
                    <div className="px-2 py-4 text-sm text-muted-foreground text-center">
                      No models available. Configure providers in Connections.
                    </div>
                  )}
                </SelectContent>
              </Select>
            </div>
            {modelChoice && (
              <div className="rounded-md border border-border bg-muted/30 p-3">
                <div className="text-xs text-muted-foreground">
                  Selected model
                </div>
                <div className="font-mono text-sm mt-0.5">
                  {modelChoices.find(
                    (c) => `${c.provider}\0${c.model}` === modelChoice,
                  )?.label ?? modelChoice}
                </div>
              </div>
            )}
            <div className="flex justify-between">
              <Button variant="outline" onClick={prevStep}>
                <ChevronLeft className="h-4 w-4 mr-1" />
                Back
              </Button>
              <Button onClick={() => setStep("skills")}>
                Next
                <ChevronRight className="h-4 w-4 ml-1" />
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Step: Skills ──────────────────────────────────────────── */}
      {step === "skills" && (
        <Card>
          <CardContent className="grid gap-5 p-6">
            <div>
              <Label className="text-base">Select Skills</Label>
              <p className="text-sm text-muted-foreground mt-1">
                Choose which skills to enable for this profile. Skills can be
                toggled later from the Skills page.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search skills…"
                  value={skillSearch}
                  onChange={(e) => setSkillSearch(e.target.value)}
                  className="pl-9 h-9"
                />
              </div>
              {selectedSkills.length > 0 && (
                <Badge variant="secondary">
                  {selectedSkills.length} selected
                </Badge>
              )}
            </div>
            {availableSkills.length === 0 ? (
              <p className="text-sm text-muted-foreground py-4 text-center">
                No skills available.
              </p>
            ) : (
              <div className="max-h-72 overflow-y-auto border border-border rounded-md">
                {filteredSkills.length === 0 ? (
                  <p className="text-sm text-muted-foreground py-4 text-center">
                    No skills match "{skillSearch}".
                  </p>
                ) : (
                  filteredSkills.map((s) => (
                    <label
                      key={s.name}
                      className={`flex items-center gap-3 px-3 py-2 text-sm cursor-pointer border-b border-border last:border-b-0 transition-colors ${
                        selectedSkills.includes(s.name)
                          ? "bg-primary/5"
                          : "hover:bg-muted/40"
                      }`}
                    >
                      <input
                        type="checkbox"
                        className="accent-primary"
                        checked={selectedSkills.includes(s.name)}
                        onChange={() => toggleSkill(s.name)}
                      />
                      <div className="flex-1 min-w-0">
                        <span className="font-mono font-medium">
                          {s.name}
                        </span>
                        {s.category && (
                          <Badge
                            variant="outline"
                            className="ml-2 text-xs"
                          >
                            {s.category}
                          </Badge>
                        )}
                        <p className="text-xs text-muted-foreground truncate">
                          {s.description}
                        </p>
                      </div>
                    </label>
                  ))
                )}
              </div>
            )}
            <div className="flex justify-between">
              <Button variant="outline" onClick={prevStep}>
                <ChevronLeft className="h-4 w-4 mr-1" />
                Back
              </Button>
              <Button onClick={() => setStep("mcp")}>
                Next
                <ChevronRight className="h-4 w-4 ml-1" />
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Step: MCPs ────────────────────────────────────────────── */}
      {step === "mcp" && (
        <Card>
          <CardContent className="grid gap-5 p-6">
            <div>
              <Label className="text-base">MCP Servers</Label>
              <p className="text-sm text-muted-foreground mt-1">
                Select which MCP servers to enable for this profile. These
                provide additional tools and capabilities.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search MCP servers…"
                  value={mcpSearch}
                  onChange={(e) => setMcpSearch(e.target.value)}
                  className="pl-9 h-9"
                />
              </div>
              {selectedMcps.length > 0 && (
                <Badge variant="secondary">
                  {selectedMcps.length} selected
                </Badge>
              )}
            </div>
            {availableMcps.length === 0 ? (
              <p className="text-sm text-muted-foreground py-4 text-center">
                No MCP servers configured.
              </p>
            ) : (
              <div className="max-h-72 overflow-y-auto border border-border rounded-md">
                {filteredMcps.length === 0 ? (
                  <p className="text-sm text-muted-foreground py-4 text-center">
                    No MCP servers match "{mcpSearch}".
                  </p>
                ) : (
                  filteredMcps.map((m) => (
                    <label
                      key={m.name}
                      className={`flex items-center gap-3 px-3 py-2 text-sm cursor-pointer border-b border-border last:border-b-0 transition-colors ${
                        selectedMcps.includes(m.name)
                          ? "bg-primary/5"
                          : "hover:bg-muted/40"
                      }`}
                    >
                      <input
                        type="checkbox"
                        className="accent-primary"
                        checked={selectedMcps.includes(m.name)}
                        onChange={() => toggleMcp(m.name)}
                      />
                      <div className="flex-1 min-w-0">
                        <span className="font-mono font-medium">{m.name}</span>
                        <Badge variant="outline" className="ml-2 text-xs">
                          {m.transport}
                        </Badge>
                      </div>
                    </label>
                  ))
                )}
              </div>
            )}
            <div className="flex justify-between">
              <Button variant="outline" onClick={prevStep}>
                <ChevronLeft className="h-4 w-4 mr-1" />
                Back
              </Button>
              <Button onClick={() => setStep("review")}>
                Next
                <ChevronRight className="h-4 w-4 ml-1" />
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Step: Review ───────────────────────────────────────────── */}
      {step === "review" && (
        <Card>
          <CardContent className="grid gap-5 p-6">
            <h3 className="text-lg font-semibold">Review Profile</h3>
            <p className="text-sm text-muted-foreground">
              Verify the configuration before creating the profile.
            </p>

            <div className="grid gap-3 text-sm">
              {/* Name */}
              <div className="flex items-start gap-3 py-2 border-b border-border">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
                  <User className="h-4 w-4 text-muted-foreground" />
                </div>
                <div className="flex-1">
                  <div className="text-muted-foreground text-xs">Name</div>
                  <div className="font-mono font-medium">
                    {name.trim() || "(unnamed)"}
                  </div>
                </div>
              </div>

              {/* Description */}
              {description.trim() && (
                <div className="flex items-start gap-3 py-2 border-b border-border">
                  <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted text-muted-foreground text-xs">
                    <Copy className="h-4 w-4" />
                  </div>
                  <div className="flex-1">
                    <div className="text-muted-foreground text-xs">
                      Description
                    </div>
                    <div>{description.trim()}</div>
                  </div>
                </div>
              )}

              {/* Clone source */}
              {cloneFrom && (
                <div className="flex items-start gap-3 py-2 border-b border-border">
                  <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted text-muted-foreground text-xs">
                    <Copy className="h-4 w-4" />
                  </div>
                  <div className="flex-1">
                    <div className="text-muted-foreground text-xs">
                      Cloned from
                    </div>
                    <div className="font-mono">{cloneFrom}</div>
                  </div>
                </div>
              )}

              {/* Model */}
              <div className="flex items-start gap-3 py-2 border-b border-border">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
                  <Cpu className="h-4 w-4 text-muted-foreground" />
                </div>
                <div className="flex-1">
                  <div className="text-muted-foreground text-xs">Model</div>
                  <div>
                    {modelChoice
                      ? modelChoices.find(
                          (c) =>
                            `${c.provider}\0${c.model}` === modelChoice,
                        )?.label ?? "inherit"
                      : "inherit"}
                  </div>
                </div>
              </div>

              {/* Skills */}
              <div className="flex items-start gap-3 py-2 border-b border-border">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
                  <Sparkles className="h-4 w-4 text-muted-foreground" />
                </div>
                <div className="flex-1">
                  <div className="text-muted-foreground text-xs">Skills</div>
                  {selectedSkills.length > 0 ? (
                    <div className="flex flex-wrap gap-1 mt-1">
                      {selectedSkills.map((s) => (
                        <Badge key={s} variant="secondary" className="text-xs">
                          {s}
                        </Badge>
                      ))}
                    </div>
                  ) : (
                    <div className="text-muted-foreground">none</div>
                  )}
                </div>
              </div>

              {/* MCPs */}
              <div className="flex items-start gap-3 py-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
                  <Server className="h-4 w-4 text-muted-foreground" />
                </div>
                <div className="flex-1">
                  <div className="text-muted-foreground text-xs">
                    MCP Servers
                  </div>
                  {selectedMcps.length > 0 ? (
                    <div className="flex flex-wrap gap-1 mt-1">
                      {selectedMcps.map((m) => (
                        <Badge key={m} variant="secondary" className="text-xs">
                          {m}
                        </Badge>
                      ))}
                    </div>
                  ) : (
                    <div className="text-muted-foreground">none</div>
                  )}
                </div>
              </div>
            </div>

            <div className="flex justify-between pt-2">
              <Button variant="outline" onClick={prevStep}>
                <ChevronLeft className="h-4 w-4 mr-1" />
                Back
              </Button>
              <Button
                onClick={handleCreate}
                disabled={creating || !name.trim()}
              >
                {creating ? "Creating…" : "Create Profile"}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
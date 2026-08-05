import {
  Box,
  Clapperboard,
  FileText,
  Image,
  Mic2,
  MonitorPlay,
  Palette,
  Send,
} from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";

import { SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { useProductState } from "@/shared/use-product-state";
import {
  EMPTY_STUDIO_STATE,
  STUDIO_KIND_LABELS,
  studioId,
  type StudioKind,
  type StudioProject,
} from "@/features/studio/studio-state";

const CREATION_TYPES = [
  { kind: "image", icon: Image, description: "Illustrations, concepts, photography, and design." },
  { kind: "video", icon: Clapperboard, description: "Research, scripts, storyboards, scenes, and edits." },
  { kind: "audio", icon: Mic2, description: "Voice, music, sound effects, and audio production." },
  { kind: "writing", icon: FileText, description: "Stories, scripts, articles, and documents." },
  { kind: "presentation", icon: MonitorPlay, description: "Narrative decks, explainers, and visual reports." },
  { kind: "3d", icon: Box, description: "Characters, environments, models, and animation concepts." },
] as const;

export function StudioPage() {
  const navigate = useNavigate();
  const [state, setState, stateStatus] = useProductState("studio", EMPTY_STUDIO_STATE);
  const [kind, setKind] = useState<StudioKind>("video");
  const [prompt, setPrompt] = useState("");

  const begin = () => {
    const request = prompt.trim();
    if (!request) return;
    const now = new Date().toISOString();
    const project: StudioProject = {
      id: studioId("studio"),
      title: request.length > 64 ? `${request.slice(0, 61)}…` : request,
      kind,
      prompt: request,
      status: "concept",
      createdAt: now,
      updatedAt: now,
    };
    setState((current) => ({ ...current, projects: [project, ...current.projects] }));
    const handoff = [
      `Start a ${STUDIO_KIND_LABELS[kind].toLowerCase()} production session for this creative brief:`,
      request,
      "First develop a clear plan, identify required sources and assets, and do not claim unavailable generation tools are connected.",
    ].join("\n\n");
    navigate(`/chat?prompt=${encodeURIComponent(handoff)}&source=studio`);
  };

  return (
    <SurfaceShell
      title="Studio"
      description="Develop images, video, audio, writing, presentations, and creative 3D with your Agent."
    >
      <SurfaceNote>
        Studio coordinates creative work and preserves its brief, assets, and history.
        Generation depends on the workers and providers connected in Control Center.
      </SurfaceNote>

      {stateStatus.error && (
        <p className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
          {stateStatus.error}
        </p>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Palette className="size-4 text-primary" />
            What do you want to create?
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {CREATION_TYPES.map(({ kind: option, icon: Icon, description }) => (
              <button
                key={option}
                type="button"
                onClick={() => setKind(option)}
                className={`rounded-lg border p-3 text-left transition-colors ${
                  kind === option ? "border-primary bg-primary/10" : "border-border bg-card hover:bg-accent/40"
                }`}
              >
                <div className="flex items-center gap-2">
                  <Icon className="size-4 text-primary" />
                  <span className="text-sm font-semibold">{STUDIO_KIND_LABELS[option]}</span>
                </div>
                <p className="mt-1.5 text-xs leading-relaxed text-muted-foreground">{description}</p>
              </button>
            ))}
          </div>
          <Textarea
            value={prompt}
            onChange={(event) => setPrompt(event.target.value)}
            placeholder="Describe the story, image, film, sound, document, presentation, or world you want to create…"
            className="min-h-28"
          />
          <div className="flex items-center justify-between gap-3">
            <p className="text-xs text-muted-foreground">
              A project is saved before the brief is handed to Agent.
            </p>
            <Button onClick={begin} disabled={!prompt.trim()}>
              <Send className="size-4" />
              Begin in Agent
            </Button>
          </div>
        </CardContent>
      </Card>

      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold">Recent creative projects</h2>
          <Button variant="ghost" size="sm" onClick={() => navigate("/studio-projects")}>View all</Button>
        </div>
        {stateStatus.loading ? (
          <p className="text-sm text-muted-foreground">Loading Studio…</p>
        ) : state.projects.length === 0 ? (
          <Card><CardContent className="py-8 text-center text-sm text-muted-foreground">No creative projects yet.</CardContent></Card>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {state.projects.slice(0, 4).map((project) => (
              <Card key={project.id}>
                <CardContent className="space-y-2 py-4">
                  <div className="flex items-start justify-between gap-2">
                    <p className="text-sm font-medium">{project.title}</p>
                    <Badge variant="outline">{STUDIO_KIND_LABELS[project.kind]}</Badge>
                  </div>
                  <p className="line-clamp-2 text-xs text-muted-foreground">{project.prompt}</p>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </section>
    </SurfaceShell>
  );
}

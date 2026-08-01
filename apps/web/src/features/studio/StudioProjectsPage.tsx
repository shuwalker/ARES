import { Clapperboard, Trash2 } from "lucide-react";
import { useNavigate } from "react-router-dom";

import { SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { useProductState } from "@/shared/use-product-state";
import { EMPTY_STUDIO_STATE, STUDIO_KIND_LABELS } from "@/features/studio/studio-state";

export function StudioProjectsPage() {
  const navigate = useNavigate();
  const [state, setState, status] = useProductState("studio", EMPTY_STUDIO_STATE);

  return (
    <SurfaceShell
      title="Creative Projects"
      description="Saved briefs and production work across every Studio medium."
      action={<Button onClick={() => navigate("/studio")}>New project</Button>}
    >
      {status.error && <p className="text-sm text-destructive">{status.error}</p>}
      {status.loading ? <p className="text-sm text-muted-foreground">Loading projects…</p> : state.projects.length === 0 ? (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">No creative projects yet.</CardContent></Card>
      ) : (
        <div className="space-y-2">
          {state.projects.map((project) => (
            <Card key={project.id}><CardContent className="flex items-start gap-3 py-4">
              <Clapperboard className="mt-0.5 size-4 shrink-0 text-primary" />
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-medium">{project.title}</p>
                  <Badge variant="outline">{STUDIO_KIND_LABELS[project.kind]}</Badge>
                  <Badge variant="secondary">{project.status.replace("_", " ")}</Badge>
                </div>
                <p className="mt-1 line-clamp-3 text-sm text-muted-foreground">{project.prompt}</p>
              </div>
              <Button variant="ghost" size="icon" aria-label={`Delete ${project.title}`} onClick={() => setState((current) => ({ ...current, projects: current.projects.filter((item) => item.id !== project.id) }))}>
                <Trash2 className="size-4 text-destructive" />
              </Button>
            </CardContent></Card>
          ))}
        </div>
      )}
    </SurfaceShell>
  );
}

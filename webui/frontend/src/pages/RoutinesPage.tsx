import { useEffect, useState } from "react";
import {
  Clock,
  LoaderCircle,
  Play,
  Plus,
  Repeat,
  ToggleLeft,
  ToggleRight,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useAres } from "@/shared/ares-context";

type RoutineStatus = "active" | "paused" | "draft" | "archived";

interface Routine {
  id: string;
  title: string;
  description?: string;
  schedule: string;
  status: RoutineStatus;
  lastRunAt?: string;
  nextRunAt?: string;
  enabled: boolean;
}

function relativeTime(value?: string) {
  if (!value) return "—";
  const elapsed = Date.now() - new Date(value).getTime();
  const abs = Math.abs(elapsed);
  const minutes = Math.floor(abs / 60_000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ${elapsed > 0 ? "ago" : "from now"}`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ${elapsed > 0 ? "ago" : "from now"}`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ${elapsed > 0 ? "ago" : "from now"}`;
  return new Date(value).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

function statusBadgeVariant(
  status: RoutineStatus,
): "default" | "secondary" | "outline" | "destructive" {
  if (status === "active") return "default";
  if (status === "paused") return "secondary";
  if (status === "draft") return "outline";
  return "destructive";
}

export default function RoutinesPage() {
  const { snapshot } = useAres();
  const [routines, setRoutines] = useState<Routine[]>([]);
  const [loading, setLoading] = useState(true);
  const [togglingId, setTogglingId] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    fetch("/api/routines")
      .then((r) => r.json())
      .then((data) => {
        if (active) setRoutines(data.routines ?? data ?? []);
      })
      .catch(() => {
        if (active) setRoutines([]);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  async function handleToggle(id: string, currentlyEnabled: boolean) {
    setTogglingId(id);
    try {
      const res = await fetch(`/api/routines/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ enabled: !currentlyEnabled }),
      });
      if (res.ok) {
        const updated = await res.json();
        setRoutines((prev) =>
          prev.map((r) => (r.id === id ? { ...r, ...updated, enabled: updated.enabled ?? !currentlyEnabled } : r)),
        );
      } else {
        // Optimistic toggle on failure — still update locally
        setRoutines((prev) =>
          prev.map((r) => (r.id === id ? { ...r, enabled: !currentlyEnabled } : r)),
        );
      }
    } catch {
      setRoutines((prev) =>
        prev.map((r) => (r.id === id ? { ...r, enabled: !currentlyEnabled } : r)),
      );
    }
    setTogglingId(null);
  }

  const connected = snapshot.connection !== "unavailable";

  return (
    <div className="page-stack">
      <PageHeader
        title="Routines"
        description="Scheduled and automated tasks that run on your behalf."
        action={
          <Button size="sm" disabled={!connected}>
            <Plus className="size-4" />
            New routine
          </Button>
        }
      />

      {loading ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading routines…</p>
        </div>
      ) : routines.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <Repeat className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            No routines yet. Create one to automate recurring tasks.
          </p>
        </div>
      ) : (
        <div className="grid gap-3">
          {routines.map((routine) => (
            <Card key={routine.id}>
              <CardHeader>
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <Repeat className="size-4 shrink-0 text-muted-foreground" />
                      <CardTitle className="truncate text-base">
                        {routine.title || "Untitled routine"}
                      </CardTitle>
                      <Badge variant={statusBadgeVariant(routine.status)}>
                        {routine.status}
                      </Badge>
                    </div>
                    {routine.description && (
                      <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">
                        {routine.description}
                      </p>
                    )}
                  </div>

                  <div className="flex shrink-0 items-center gap-2">
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label={routine.enabled ? "Disable routine" : "Enable routine"}
                      disabled={togglingId === routine.id}
                      onClick={() => handleToggle(routine.id, routine.enabled)}
                    >
                      {togglingId === routine.id ? (
                        <LoaderCircle className="size-4 animate-spin" />
                      ) : routine.enabled ? (
                        <ToggleRight className="size-5 text-green-500" />
                      ) : (
                        <ToggleLeft className="size-5 text-muted-foreground" />
                      )}
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="Run routine now"
                      disabled={!routine.enabled}
                      onClick={() =>
                        fetch(`/api/routines/${routine.id}/run`, {
                          method: "POST",
                        }).catch(() => undefined)
                      }
                    >
                      <Play className="size-4" />
                    </Button>
                  </div>
                </div>
              </CardHeader>

              <CardContent className="border-t pt-4">
                <div className="flex flex-wrap items-center gap-x-6 gap-y-2 text-xs text-muted-foreground">
                  <span className="inline-flex items-center gap-1.5">
                    <Clock className="size-3.5" />
                    {routine.schedule}
                  </span>
                  {routine.lastRunAt && (
                    <span>
                      Last run: {relativeTime(routine.lastRunAt)}
                    </span>
                  )}
                  {routine.nextRunAt && routine.enabled && (
                    <span>
                      Next run: {relativeTime(routine.nextRunAt)}
                    </span>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
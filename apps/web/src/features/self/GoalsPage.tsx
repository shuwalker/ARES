import { useCallback, useState, type Dispatch, type SetStateAction } from "react";
import {
  Circle,
  CircleCheck,
  CircleDot,
  LoaderCircle,
  Plus,
  Target,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useProductState } from "@/shared/use-product-state";

type GoalStatus = "not_started" | "in_progress" | "done";

interface Goal {
  id: string;
  title: string;
  description: string;
  status: GoalStatus;
  targetDate: string;
  progress: number; // 0–100
  createdAt: string;
  updatedAt: string;
}

const STATUS_LABELS: Record<GoalStatus, string> = {
  not_started: "Not Started",
  in_progress: "In Progress",
  done: "Done",
};

function statusIcon(status: GoalStatus) {
  if (status === "done") return <CircleCheck className="size-4 text-green-500" />;
  if (status === "in_progress") return <CircleDot className="size-4 text-yellow-500" />;
  return <Circle className="size-4 text-muted-foreground" />;
}

function statusBadgeVariant(
  status: GoalStatus,
): "default" | "secondary" | "outline" {
  if (status === "done") return "default";
  if (status === "in_progress") return "secondary";
  return "outline";
}

function uid(): string {
  return Math.random().toString(36).slice(2, 10);
}

export function GoalsPage() {
  const [goalState, setGoalState, goalStatus] = useProductState<{ goals: Goal[] }>("goals", { goals: [] });
  const goals = goalState.goals;
  const setGoals: Dispatch<SetStateAction<Goal[]>> = useCallback((update) => {
    setGoalState((current) => ({ goals: typeof update === "function" ? update(current.goals) : update }));
  }, [setGoalState]);
  const [filter, setFilter] = useState<GoalStatus | "all">("all");
  const [adding, setAdding] = useState(false);
  const [newTitle, setNewTitle] = useState("");

  const filtered = goals
    .filter((g) => filter === "all" || g.status === filter)
    .sort((a, b) => {
      // done last, then by updatedAt desc
      if (a.status === "done" && b.status !== "done") return 1;
      if (b.status === "done" && a.status !== "done") return -1;
      return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
    });

  const counts = {
    not_started: goals.filter((g) => g.status === "not_started").length,
    in_progress: goals.filter((g) => g.status === "in_progress").length,
    done: goals.filter((g) => g.status === "done").length,
  };

  function cycleStatus(goal: Goal) {
    const order: GoalStatus[] = ["not_started", "in_progress", "done"];
    const next = order[(order.indexOf(goal.status) + 1) % order.length];
    setGoals((prev) =>
      prev.map((g) =>
        g.id === goal.id
          ? { ...g, status: next, updatedAt: new Date().toISOString() }
          : g,
      ),
    );
  }

  function addGoal() {
    if (!newTitle.trim()) return;
    const now = new Date().toISOString();
    setGoals((prev) => [
      ...prev,
      {
        id: uid(),
        title: newTitle.trim(),
        description: "",
        status: "not_started",
        targetDate: "",
        progress: 0,
        createdAt: now,
        updatedAt: now,
      },
    ]);
    setNewTitle("");
    setAdding(false);
  }

  function updateGoal(id: string, patch: Partial<Goal>) {
    setGoals((prev) =>
      prev.map((g) =>
        g.id === id
          ? { ...g, ...patch, updatedAt: new Date().toISOString() }
          : g,
      ),
    );
  }

  function deleteGoal(id: string) {
    setGoals((prev) => prev.filter((g) => g.id !== id));
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Goals"
        description="Track objectives and milestones for your Synthetic Person."
        action={
          <Button size="sm" onClick={() => setAdding(true)}>
            <Plus className="size-4" />
            New goal
          </Button>
        }
      />
      {goalStatus.error && <p className="text-sm text-destructive" role="alert">{goalStatus.error}</p>}
      {goalStatus.loading && <p className="text-sm text-muted-foreground" role="status">Loading goals…</p>}

      <Tabs
        value={filter}
        onValueChange={(v) => setFilter(v as GoalStatus | "all")}
      >
        <TabsList>
          <TabsTrigger value="all">All ({goals.length})</TabsTrigger>
          <TabsTrigger value="not_started">
            Not Started ({counts.not_started})
          </TabsTrigger>
          <TabsTrigger value="in_progress">
            In Progress ({counts.in_progress})
          </TabsTrigger>
          <TabsTrigger value="done">Done ({counts.done})</TabsTrigger>
        </TabsList>
      </Tabs>

      {adding && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">New Goal</CardTitle>
          </CardHeader>
          <CardContent className="border-t pt-4">
            <form
              className="flex items-center gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                addGoal();
              }}
            >
              <Input
                value={newTitle}
                onChange={(e) => setNewTitle(e.target.value)}
                placeholder="Goal title…"
                className="flex-1"
                autoFocus
              />
              <Button type="submit" size="sm" disabled={!newTitle.trim()}>
                Add
              </Button>
              <Button
                type="button"
                size="sm"
                variant="ghost"
                onClick={() => {
                  setAdding(false);
                  setNewTitle("");
                }}
              >
                Cancel
              </Button>
            </form>
          </CardContent>
        </Card>
      )}

      {filtered.length === 0 && !adding && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <Target className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            {filter === "all" ? "No goals yet. Create one to get started." : `No ${STATUS_LABELS[filter as GoalStatus]?.toLowerCase()} goals.`}
          </p>
        </div>
      )}

      <div className="grid gap-3">
        {filtered.map((goal) => (
          <Card key={goal.id}>
            <CardHeader>
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => cycleStatus(goal)}
                      className="transition-colors hover:text-foreground"
                      aria-label={`Status: ${STATUS_LABELS[goal.status]}. Click to advance.`}
                    >
                      {statusIcon(goal.status)}
                    </button>
                    <CardTitle
                      className={`truncate text-base ${goal.status === "done" ? "line-through text-muted-foreground" : ""}`}
                    >
                      {goal.title || "Untitled goal"}
                    </CardTitle>
                    <Badge variant={statusBadgeVariant(goal.status)}>
                      {STATUS_LABELS[goal.status]}
                    </Badge>
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  className="shrink-0 text-muted-foreground hover:text-destructive"
                  onClick={() => deleteGoal(goal.id)}
                  aria-label="Delete goal"
                >
                  &times;
                </Button>
              </div>
            </CardHeader>

            <CardContent className="border-t pt-4 space-y-3">
              {/* Progress bar */}
              <div className="space-y-1">
                <div className="flex items-center justify-between text-xs text-muted-foreground">
                  <span>Progress</span>
                  <span>{goal.progress}%</span>
                </div>
                <div className="h-2 w-full overflow-hidden rounded-full bg-secondary">
                  <div
                    className="h-full rounded-full bg-primary transition-all"
                    style={{ width: `${goal.progress}%` }}
                  />
                </div>
              </div>

              {/* Editable fields */}
              <div className="grid gap-2 sm:grid-cols-2">
                <div className="space-y-1">
                  <label className="text-[0.65rem] uppercase tracking-wider text-muted-foreground">
                    Target date
                  </label>
                  <Input
                    type="date"
                    value={goal.targetDate}
                    onChange={(e) =>
                      updateGoal(goal.id, { targetDate: e.target.value })
                    }
                    className="h-8 text-xs"
                  />
                </div>
                <div className="space-y-1">
                  <label className="text-[0.65rem] uppercase tracking-wider text-muted-foreground">
                    Progress %
                  </label>
                  <Input
                    type="number"
                    min={0}
                    max={100}
                    value={goal.progress}
                    onChange={(e) =>
                      updateGoal(goal.id, {
                        progress: Math.min(100, Math.max(0, Number(e.target.value))),
                      })
                    }
                    className="h-8 text-xs"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <label className="text-[0.65rem] uppercase tracking-wider text-muted-foreground">
                  Description
                </label>
                <Input
                  value={goal.description}
                  onChange={(e) =>
                    updateGoal(goal.id, { description: e.target.value })
                  }
                  placeholder="Add details…"
                  className="h-8 text-xs"
                />
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

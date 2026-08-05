import { useCallback, useEffect, useState } from "react";
import {
  CalendarClock,
  CheckCircle2,
  Circle,
  Clock,
  ExternalLink,
  MessageCircle,
  Network,
  PlayCircle,
  Pin,
  Plus,
  RefreshCw,
  Search,
  Sparkles,
  Timer,
  Zap,
} from "lucide-react";
import { Link } from "react-router-dom";

import { EmptyState } from "@/components/EmptyState";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { useAres } from "@/shared/ares-context";
import { useLocalProfile } from "@/shared/local-profile";
import { aresApi } from "@/shared/ares-api";
import type { ScheduleEntry } from "@/shared/ares-api";
import { apiFetch, readableError } from "@/shared/api-client";
import { useProductState } from "@/shared/use-product-state";

interface PinnedGoal {
  id: string;
  text: string;
  done: boolean;
  createdAt: string;
}

interface OrganizerTask {
  id: string;
  title: string;
  status: string;
  priority: string;
  estimated_minutes?: number | null;
}

interface OrganizerToday {
  now: OrganizerTask[];
  next: OrganizerTask[];
  later: OrganizerTask[];
  blocked: OrganizerTask[];
  unscheduled: OrganizerTask[];
}

interface OrganizerPlan {
  plan: Array<{
    task_id: string;
    task_title: string;
    start_time: string;
    duration_minutes: number;
  }>;
  summary: string;
  generated_at: string;
}

const EMPTY_ORGANIZER_TODAY: OrganizerToday = {
  now: [],
  next: [],
  later: [],
  blocked: [],
  unscheduled: [],
};

// ── Compact quick-stat card ──────────────────────────────────────────────
function QuickStatCard({
  icon: Icon,
  value,
  label,
  description,
  to,
}: {
  icon: React.ComponentType<{ className?: string }>;
  value: string | number;
  label: string;
  description?: string;
  to?: string;
}) {
  const inner = (
    <>
      <CardHeader className="flex-row items-center gap-3 pb-2">
        <Icon className="size-5 shrink-0 text-primary" />
        <CardTitle className="text-sm">{label}</CardTitle>
      </CardHeader>
      <CardContent className="pt-0">
        <p className="text-3xl font-semibold tabular-nums">{value}</p>
        {description && (
          <p className="mt-1 text-xs text-muted-foreground">{description}</p>
        )}
      </CardContent>
    </>
  );

  if (to) {
    return (
      <Link to={to} className="block no-underline">
        <Card interactive className="transition-shadow hover:shadow-md">
          {inner}
        </Card>
      </Link>
    );
  }
  return <Card>{inner}</Card>;
}

// ── Schedule row ─────────────────────────────────────────────────────────
function ScheduleRow({ entry }: { entry: ScheduleEntry }) {
  const enabled = entry.enabled !== false;
  const nextRun = entry.next_run_at
    ? formatRelativeTime(new Date(entry.next_run_at))
    : "Not scheduled";

  return (
    <div className="flex items-center gap-3 py-2 text-sm">
      <CalendarClock className="size-4 shrink-0 text-muted-foreground" />
      <div className="min-w-0 flex-1">
        <span className="truncate font-medium">
          {entry.name || entry.job_id}
        </span>
        {entry.schedule && (
          <span className="ml-2 text-xs text-muted-foreground">
            {entry.schedule}
          </span>
        )}
      </div>
      <Badge variant={enabled ? "default" : "outline"} className="shrink-0">
        {enabled ? "Enabled" : "Paused"}
      </Badge>
      <span className="shrink-0 text-xs text-muted-foreground">{nextRun}</span>
    </div>
  );
}

// ── Pinned-goal row ──────────────────────────────────────────────────────
function GoalRow({
  goal,
  onToggle,
  onRemove,
}: {
  goal: PinnedGoal;
  onToggle: (id: string) => void;
  onRemove: (id: string) => void;
}) {
  return (
    <div className="flex items-center gap-2 py-1.5 text-sm group">
      <button
        onClick={() => onToggle(goal.id)}
        className="shrink-0"
        aria-label={goal.done ? "Mark incomplete" : "Mark complete"}
      >
        {goal.done ? (
          <CheckCircle2 className="size-4 text-status-available" />
        ) : (
          <div className="size-4 rounded-full border-2 border-muted-foreground/40" />
        )}
      </button>
      <span
        className={`flex-1 truncate ${
          goal.done ? "text-muted-foreground line-through" : ""
        }`}
      >
        {goal.text}
      </span>
      <button
        onClick={() => onRemove(goal.id)}
        className="shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
        aria-label="Remove goal"
      >
        <Pin className="size-3.5 text-muted-foreground hover:text-destructive" />
      </button>
    </div>
  );
}

// ── Relative time ────────────────────────────────────────────────────────
function formatRelativeTime(date: Date): string {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (seconds < 0) {
    // Future — show "in X"
    const abs = Math.abs(seconds);
    if (abs < 60) return "now";
    const mins = Math.floor(abs / 60);
    if (mins < 60) return `in ${mins}m`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `in ${hrs}h`;
    return date.toLocaleDateString();
  }
  if (seconds < 60) return "just now";
  const mins = Math.floor(seconds / 60);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

// ── Main TodayPage ───────────────────────────────────────────────────────
export function TodayPage() {
  const { profile } = useLocalProfile();
  const { snapshot, refresh } = useAres();
  const [schedules, setSchedules] = useState<ScheduleEntry[]>([]);
  const [schedulesLoading, setSchedulesLoading] = useState(false);
  const [schedulesError, setSchedulesError] = useState<string | null>(null);
  const [dailyGoalState, setDailyGoalState, dailyGoalStatus] = useProductState<{ goals: PinnedGoal[] }>("daily-goals", { goals: [] });
  const goals = dailyGoalState.goals;
  const setGoals = useCallback((update: React.SetStateAction<PinnedGoal[]>) => {
    setDailyGoalState((current) => ({ goals: typeof update === "function" ? update(current.goals) : update }));
  }, [setDailyGoalState]);
  const [newGoalText, setNewGoalText] = useState("");
  const [organizerToday, setOrganizerToday] = useState<OrganizerToday>(EMPTY_ORGANIZER_TODAY);
  const [organizerPlan, setOrganizerPlan] = useState<OrganizerPlan | null>(null);
  const [organizerLoading, setOrganizerLoading] = useState(true);
  const [organizerError, setOrganizerError] = useState("");
  const [captureText, setCaptureText] = useState("");
  const [organizerBusy, setOrganizerBusy] = useState("");

  const greeting = profile.displayName
    ? `Good to see you, ${profile.displayName}.`
    : "Your day at a glance.";

  const active = snapshot.sessions.filter((session) => session.activeStreamId);
  const recent = snapshot.sessions.slice(0, 5);
  const pinned = snapshot.sessions.filter((session) => session.pinned);

  const loadOrganizer = useCallback(async () => {
    setOrganizerLoading(true);
    try {
      const [today, plan] = await Promise.all([
        apiFetch<OrganizerToday>("/api/organizer/today"),
        apiFetch<OrganizerPlan>("/api/organizer/plan"),
      ]);
      setOrganizerToday(today);
      setOrganizerPlan(plan);
      setOrganizerError("");
    } catch (error) {
      setOrganizerError(readableError(error, "Organizer is unavailable."));
    } finally {
      setOrganizerLoading(false);
    }
  }, []);

  useEffect(() => { void loadOrganizer(); }, [loadOrganizer]);

  const captureTask = useCallback(async () => {
    const title = captureText.trim();
    if (!title) return;
    setOrganizerBusy("capture");
    try {
      await apiFetch("/api/organizer/tasks", {
        method: "POST",
        body: JSON.stringify({ title, status: "todo", priority: "medium" }),
      });
      setCaptureText("");
      await loadOrganizer();
    } catch (error) {
      setOrganizerError(readableError(error, "Task could not be captured."));
    } finally {
      setOrganizerBusy("");
    }
  }, [captureText, loadOrganizer]);

  const completeTask = useCallback(async (taskId: string) => {
    setOrganizerBusy(taskId);
    try {
      await apiFetch(`/api/organizer/tasks/${encodeURIComponent(taskId)}`, {
        method: "PATCH",
        body: JSON.stringify({ status: "done" }),
      });
      await loadOrganizer();
    } catch (error) {
      setOrganizerError(readableError(error, "Task could not be completed."));
    } finally {
      setOrganizerBusy("");
    }
  }, [loadOrganizer]);

  // ── Load schedules ───────────────────────────────────────────────────
  useEffect(() => {
    let active = true;
    setSchedulesLoading(true);
    aresApi
      .schedules(true)
      .then((data) => {
        if (!active) return;
        setSchedules(data.schedules ?? []);
        setSchedulesError(null);
      })
      .catch((err) => {
        if (!active) return;
        setSchedulesError(readableError(err));
        setSchedules([]);
      })
      .finally(() => {
        if (active) setSchedulesLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  // ── Goals persistence ─────────────────────────────────────────────────
  const toggleGoal = useCallback((id: string) => {
    setGoals((prev) =>
      prev.map((g) =>
        g.id === id ? { ...g, done: !g.done } : g,
      ),
    );
  }, [setGoals]);

  const removeGoal = useCallback((id: string) => {
    setGoals((prev) => prev.filter((g) => g.id !== id));
  }, [setGoals]);

  const addGoal = useCallback(() => {
    const text = newGoalText.trim();
    if (!text) return;
    setGoals((prev) => [
        ...prev,
        {
          id: `goal-${Date.now()}`,
          text,
          done: false,
          createdAt: new Date().toISOString(),
        },
      ]);
    setNewGoalText("");
  }, [newGoalText, setGoals]);

  const upcomingSchedules = schedules
    .filter((s) => s.enabled !== false)
    .slice(0, 5);

  // ── Compute quick stats ──────────────────────────────────────────────
  const totalSessions = snapshot.sessions.length;
  const activeExecutions = active.length;
  const totalTools = snapshot.tools.total;
  const connectionCount = snapshot.connections.filter(
    (c) => c.state === "connected",
  ).length;

  return (
    <div className="page-stack">
      <PageHeader
        title="Now"
        description={`${greeting} Capture obligations, see the plan, and decide what comes next.`}
        action={
          <div className="flex items-center gap-2">
            <Button asChild variant="outline">
              <Link to="/chat">Open conversation</Link>
            </Button>
            <Button variant="ghost" size="icon-sm" onClick={() => refresh()}>
              <RefreshCw className="size-4" />
            </Button>
          </div>
        }
      />
      {dailyGoalStatus.error && <p className="text-sm text-destructive" role="alert">{dailyGoalStatus.error}</p>}
      {organizerError && <p className="text-sm text-destructive" role="alert">{organizerError}</p>}

      {snapshot.error && (
        <p className="rounded-md border border-status-limited/40 bg-status-limited/10 px-4 py-3 text-sm text-status-limited">
          {snapshot.error}
        </p>
      )}

      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle className="flex items-center gap-2">
            <Plus className="size-4 text-primary" />
            Quick capture
          </CardTitle>
          <Button variant="ghost" size="sm" onClick={() => void loadOrganizer()} disabled={organizerLoading}>
            <RefreshCw className={organizerLoading ? "size-4 animate-spin" : "size-4"} />
            Replan
          </Button>
        </CardHeader>
        <CardContent className="space-y-4">
          <form className="flex gap-2" onSubmit={(event) => { event.preventDefault(); void captureTask(); }}>
            <input
              value={captureText}
              onChange={(event) => setCaptureText(event.target.value)}
              placeholder="What do you need to remember or do?"
              className="min-w-0 flex-1 rounded-md border bg-transparent px-3 py-2 text-sm outline-none focus:border-ring"
            />
            <Button type="submit" disabled={!captureText.trim() || organizerBusy === "capture"}>Capture</Button>
          </form>

          {organizerLoading && !organizerPlan ? (
            <Skeleton className="h-20 w-full" />
          ) : (
            <div className="grid gap-4 lg:grid-cols-[1.2fr_1fr]">
              <div>
                <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Today’s plan</p>
                {organizerPlan?.plan.length ? (
                  <div className="divide-y">
                    {organizerPlan.plan.map((entry) => (
                      <div key={`${entry.task_id}-${entry.start_time}`} className="flex items-center gap-3 py-2 text-sm">
                        <span className="w-12 shrink-0 font-mono text-xs text-muted-foreground">{entry.start_time}</span>
                        <span className="min-w-0 flex-1 truncate">{entry.task_title}</span>
                        <span className="text-xs text-muted-foreground">{entry.duration_minutes}m</span>
                        <Button variant="ghost" size="icon-sm" aria-label={`Complete ${entry.task_title}`} disabled={organizerBusy === entry.task_id} onClick={() => void completeTask(entry.task_id)}>
                          <Circle className="size-4" />
                        </Button>
                      </div>
                    ))}
                  </div>
                ) : <p className="text-sm text-muted-foreground">No tasks planned yet.</p>}
                {organizerPlan && <p className="mt-2 text-xs text-muted-foreground">{organizerPlan.summary}</p>}
              </div>
              <div>
                <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Unscheduled</p>
                {organizerToday.unscheduled.length ? (
                  <div className="space-y-1">
                    {organizerToday.unscheduled.slice(0, 6).map((task) => (
                      <div key={task.id} className="flex items-center gap-2 rounded-md border px-2.5 py-2 text-sm">
                        <span className="min-w-0 flex-1 truncate">{task.title}</span>
                        <Badge variant="outline">{task.priority}</Badge>
                        <Button variant="ghost" size="icon-sm" aria-label={`Complete ${task.title}`} disabled={organizerBusy === task.id} onClick={() => void completeTask(task.id)}>
                          <CheckCircle2 className="size-4" />
                        </Button>
                      </div>
                    ))}
                  </div>
                ) : <p className="text-sm text-muted-foreground">Nothing waiting to be scheduled.</p>}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── Quick stats cards ───────────────────────────────────────── */}
      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4" aria-label="Quick stats">
        <QuickStatCard
          icon={CheckCircle2}
          value={organizerPlan?.plan.length ?? 0}
          label="Tasks planned"
          description={organizerPlan?.summary || "Organizer loading"}
        />
        <QuickStatCard
          icon={PlayCircle}
          value={activeExecutions}
          label="Active executions"
          description={activeExecutions > 0 ? "Running now" : "None running"}
          to="/activity"
        />
        <QuickStatCard
          icon={Zap}
          value={totalTools}
          label="Tools available"
          description={`${snapshot.tools.names.length} registered`}
          to="/connections"
        />
        <QuickStatCard
          icon={Network}
          value={connectionCount}
          label="Connections"
          description={`${snapshot.connections.length} total`}
          to="/connections"
        />
      </section>

      {/* ── Main dashboard grid ─────────────────────────────────────── */}
      <section className="grid gap-4 xl:grid-cols-2">
        {/* ── Recent conversations ─────────────────────────────────── */}
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2">
              <MessageCircle className="size-4" />
              Recent conversations
            </CardTitle>
            <Button asChild variant="ghost" size="sm">
              <Link to="/chat">
                View all
              </Link>
            </Button>
          </CardHeader>
          <CardContent>
            {recent.length ? (
              <div className="divide-y">
                {recent.map((session) => (
                  <Link
                    key={session.id}
                    to="/chat"
                    className="flex items-center gap-3 py-3 text-sm hover:text-primary"
                  >
                    <MessageCircle className="size-4 shrink-0" />
                    <span className="min-w-0 flex-1 truncate">
                      {session.title}
                    </span>
                    <span className="truncate text-xs text-muted-foreground">
                      {session.model || "Local session"}
                    </span>
                    {session.activeStreamId && (
                      <Badge variant="default" className="shrink-0 text-(length:--text-nano)">
                        Live
                      </Badge>
                    )}
                  </Link>
                ))}
              </div>
            ) : (
              <EmptyState
                icon={MessageCircle}
                title="No conversations yet"
                description="Start a conversation to create the first local session."
              />
            )}
          </CardContent>
        </Card>

        {/* ── Upcoming schedules ────────────────────────────────────── */}
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2">
              <CalendarClock className="size-4" />
              Upcoming schedules
            </CardTitle>
            <Button asChild variant="ghost" size="sm">
              <Link to="/schedules">Manage</Link>
            </Button>
          </CardHeader>
          <CardContent>
            {schedulesLoading ? (
              <div className="space-y-3">
                {Array.from({ length: 3 }).map((_, i) => (
                  <div key={i} className="flex items-center gap-3">
                    <Skeleton className="size-4 rounded-full" />
                    <Skeleton className="h-4 w-2/3" />
                    <Skeleton className="ml-auto h-3 w-16" />
                  </div>
                ))}
              </div>
            ) : schedulesError ? (
              <p className="text-sm text-muted-foreground">
                Schedules unavailable{snapshot.connection !== "available" ? " — ARES API offline" : ""}
              </p>
            ) : upcomingSchedules.length > 0 ? (
              <div className="divide-y">
                {upcomingSchedules.map((entry) => (
                  <ScheduleRow key={entry.job_id} entry={entry} />
                ))}
              </div>
            ) : (
              <EmptyState
                icon={CalendarClock}
                title="No scheduled tasks"
                description="Create a schedule to run tasks automatically."
              />
            )}
          </CardContent>
        </Card>
      </section>

      {/* ── Pinned sessions + Goals row ─────────────────────────────── */}
      <section className="grid gap-4 xl:grid-cols-2">
        {/* ── Pinned sessions ─────────────────────────────────────── */}
        <Card>
          <CardHeader className="flex-row items-center gap-2">
            <Pin className="size-4 text-primary" />
            <CardTitle>Pinned sessions</CardTitle>
          </CardHeader>
          <CardContent>
            {pinned.length > 0 ? (
              <div className="divide-y">
                {pinned.slice(0, 5).map((session) => (
                  <Link
                    key={session.id}
                    to="/chat"
                    className="flex items-center gap-3 py-2 text-sm hover:text-primary"
                  >
                    <Pin className="size-3.5 shrink-0 text-primary" />
                    <span className="min-w-0 flex-1 truncate">{session.title}</span>
                    <span className="truncate text-xs text-muted-foreground">
                      {session.model || "Local session"}
                    </span>
                  </Link>
                ))}
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">
                Pin important sessions for quick access.
              </p>
            )}
          </CardContent>
        </Card>

        {/* ── Pinned goals ────────────────────────────────────────── */}
        <Card>
          <CardHeader className="flex-row items-center gap-2">
            <Sparkles className="size-4 text-primary" />
            <CardTitle>Daily goals</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-1">
              {goals.map((goal) => (
                <GoalRow
                  key={goal.id}
                  goal={goal}
                  onToggle={toggleGoal}
                  onRemove={removeGoal}
                />
              ))}
              {goals.length === 0 && (
                <p className="text-sm text-muted-foreground py-2">
                  Add goals to track your daily focus.
                </p>
              )}
            </div>
            <form
              className="mt-3 flex gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                addGoal();
              }}
            >
              <input
                value={newGoalText}
                onChange={(e) => setNewGoalText(e.target.value)}
                placeholder="Add a goal…"
                className="flex-1 rounded-md border bg-transparent px-3 py-1.5 text-sm outline-none focus:border-ring"
              />
              <Button type="submit" size="sm" disabled={!newGoalText.trim()}>
                Add
              </Button>
            </form>
          </CardContent>
        </Card>
      </section>

      {/* ── System activity (kept from original) ────────────────────── */}
      {active.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <PlayCircle className="size-4 text-primary" />
              Active executions
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {active.map((session) => (
                <p key={session.id} className="flex items-center gap-2 text-sm">
                  <PlayCircle className="size-4 text-primary" />
                  {session.title}
                </p>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Quick actions ───────────────────────────────────────────── */}
      <section className="grid gap-3 sm:grid-cols-3">
        <Button asChild variant="outline" className="justify-start gap-2 h-auto py-3">
          <Link to="/search">
            <Search className="size-4" />
            Search sessions
          </Link>
        </Button>
        <Button asChild variant="outline" className="justify-start gap-2 h-auto py-3">
          <Link to="/chat">
            <MessageCircle className="size-4" />
            New conversation
          </Link>
        </Button>
        <Button asChild variant="outline" className="justify-start gap-2 h-auto py-3">
          <Link to="/schedules">
            <Timer className="size-4" />
            Manage schedules
          </Link>
        </Button>
      </section>
    </div>
  );
}

import { useCallback, useEffect, useState } from "react";
import {
  CalendarClock,
  CheckCircle2,
  Clock,
  ExternalLink,
  MessageCircle,
  Network,
  PlayCircle,
  Pin,
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
import { readableError } from "@/shared/api-client";

// ── Pinned goals localStorage ───────────────────────────────────────────
const PINNED_GOALS_KEY = "ares.today.pinned-goals";

interface PinnedGoal {
  id: string;
  text: string;
  done: boolean;
  createdAt: string;
}

function loadGoals(): PinnedGoal[] {
  try {
    const raw = localStorage.getItem(PINNED_GOALS_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveGoals(goals: PinnedGoal[]) {
  try {
    localStorage.setItem(PINNED_GOALS_KEY, JSON.stringify(goals));
  } catch {
    // Best-effort.
  }
}

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
  const [goals, setGoals] = useState<PinnedGoal[]>(loadGoals);
  const [newGoalText, setNewGoalText] = useState("");

  const greeting = profile.displayName
    ? `Good to see you, ${profile.displayName}.`
    : "Your day at a glance.";

  const active = snapshot.sessions.filter((session) => session.activeStreamId);
  const recent = snapshot.sessions.slice(0, 5);
  const pinned = snapshot.sessions.filter((session) => session.pinned);

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
    setGoals((prev) => {
      const next = prev.map((g) =>
        g.id === id ? { ...g, done: !g.done } : g,
      );
      saveGoals(next);
      return next;
    });
  }, []);

  const removeGoal = useCallback((id: string) => {
    setGoals((prev) => {
      const next = prev.filter((g) => g.id !== id);
      saveGoals(next);
      return next;
    });
  }, []);

  const addGoal = useCallback(() => {
    const text = newGoalText.trim();
    if (!text) return;
    setGoals((prev) => {
      const next = [
        ...prev,
        {
          id: `goal-${Date.now()}`,
          text,
          done: false,
          createdAt: new Date().toISOString(),
        },
      ];
      saveGoals(next);
      return next;
    });
    setNewGoalText("");
  }, [newGoalText]);

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
        title="Today"
        description={`${greeting} This view reports current ARES state without requiring an assistant runtime.`}
        action={
          <div className="flex items-center gap-2">
            <Button asChild variant="outline">
              <Link to="/conversation">Open conversation</Link>
            </Button>
            <Button variant="ghost" size="icon-sm" onClick={() => refresh()}>
              <RefreshCw className="size-4" />
            </Button>
          </div>
        }
      />

      {snapshot.error && (
        <p className="rounded-md border border-status-limited/40 bg-status-limited/10 px-4 py-3 text-sm text-status-limited">
          {snapshot.error}
        </p>
      )}

      {/* ── Quick stats cards ───────────────────────────────────────── */}
      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4" aria-label="Quick stats">
        <QuickStatCard
          icon={CheckCircle2}
          value="0"
          label="Tasks completed"
          description="No task tracking yet"
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
              <Link to="/conversation">
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
                    to="/conversation"
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
              <Link to="/cron">Manage</Link>
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
                    to="/conversation"
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
          <Link to="/conversation">
            <MessageCircle className="size-4" />
            New conversation
          </Link>
        </Button>
        <Button asChild variant="outline" className="justify-start gap-2 h-auto py-3">
          <Link to="/cron">
            <Timer className="size-4" />
            Manage schedules
          </Link>
        </Button>
      </section>
    </div>
  );
}

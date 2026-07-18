import { useCallback, useEffect, useState } from "react";
import {
  Clock,
  LoaderCircle,
  Play,
  Plus,
  RefreshCw,
  RotateCw,
  ToggleLeft,
  ToggleRight,
  Trash2,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";
import type { ScheduleEntry, CronRun } from "@/shared/ares-api";

// ---------------------------------------------------------------------------
// Cron preset definitions
// ---------------------------------------------------------------------------

interface CronPreset {
  label: string;
  expression: string;
  description: string;
}

const CRON_PRESETS: CronPreset[] = [
  { label: "Every minute", expression: "* * * * *", description: "Runs every minute" },
  { label: "Every 5 minutes", expression: "*/5 * * * *", description: "Runs every 5 minutes" },
  { label: "Every 15 minutes", expression: "*/15 * * * *", description: "Runs every 15 minutes" },
  { label: "Every 30 minutes", expression: "*/30 * * * *", description: "Runs every 30 minutes" },
  { label: "Every hour", expression: "0 * * * *", description: "Runs at the top of every hour" },
  { label: "Every 6 hours", expression: "0 */6 * * *", description: "Runs every 6 hours" },
  { label: "Every day at midnight", expression: "0 0 * * *", description: "Runs once daily at 00:00" },
  { label: "Every day at 9 AM", expression: "0 9 * * *", description: "Runs once daily at 09:00" },
  { label: "Every Monday at 9 AM", expression: "0 9 * * 1", description: "Runs weekly on Monday at 09:00" },
  { label: "First of the month", expression: "0 0 1 * *", description: "Runs monthly on the 1st at 00:00" },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatRelative(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  const diff = Date.now() - date.getTime();
  if (diff < 0) {
    const abs = Math.abs(diff);
    if (abs < 60_000) return "in a few seconds";
    const m = Math.floor(abs / 60_000);
    if (m < 60) return `in ${m}m`;
    const h = Math.floor(m / 60);
    if (h < 24) return `in ${h}h`;
    const d = Math.floor(h / 24);
    return `in ${d}d`;
  }
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  return date.toLocaleDateString();
}

function statusBadgeClass(status: string | undefined): string {
  if (status === "active" || status === "running") return "text-emerald-700 dark:text-emerald-300";
  if (status === "paused") return "text-amber-700 dark:text-amber-300";
  if (status === "failed" || status === "error") return "text-destructive";
  return "text-muted-foreground";
}

function statusDotClass(status: string | undefined): string {
  if (status === "active" || status === "running") return "bg-emerald-500";
  if (status === "paused") return "bg-amber-500";
  if (status === "failed" || status === "error") return "bg-destructive";
  return "bg-muted-foreground";
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function ScheduleStatusBadge({ status }: { status: string | undefined }) {
  const label = status ?? "unknown";
  return (
    <Badge variant="outline" className={statusBadgeClass(status)}>
      <span className={`mr-1.5 inline-block size-1.5 rounded-full ${statusDotClass(status)}`} />
      {label}
    </Badge>
  );
}

// ---------------------------------------------------------------------------
// Cron expression builder
// ---------------------------------------------------------------------------

function CronExpressionBuilder({
  value,
  onChange,
}: {
  value: string;
  onChange: (expr: string) => void;
}) {
  const [selectedPreset, setSelectedPreset] = useState<string>("");

  function handlePresetChange(presetLabel: string) {
    setSelectedPreset(presetLabel);
    if (!presetLabel) return;
    const preset = CRON_PRESETS.find((p) => p.label === presetLabel);
    if (preset) onChange(preset.expression);
  }

  return (
    <div className="grid gap-3">
      <div className="grid gap-2">
        <Label htmlFor="cron-expr">Cron expression</Label>
        <Input
          id="cron-expr"
          placeholder="* * * * *"
          value={value}
          onChange={(e) => {
            onChange(e.target.value);
            setSelectedPreset("");
          }}
          className="font-mono"
        />
      </div>
      <div className="grid gap-2">
        <Label>Common presets</Label>
        <Select value={selectedPreset} onValueChange={handlePresetChange}>
          <SelectTrigger className="w-full">
            <SelectValue placeholder="Choose a schedule…" />
          </SelectTrigger>
          <SelectContent>
            {CRON_PRESETS.map((p) => (
              <SelectItem key={p.label} value={p.label}>
                <span className="font-medium">{p.label}</span>
                <span className="ml-2 text-xs text-muted-foreground">{p.description}</span>
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      {value && (
        <div className="flex flex-wrap gap-1.5">
          {value.split(/\s+/).map((field, idx) => {
            const labels = ["Minute", "Hour", "Day of month", "Month", "Day of week"];
            return (
              <div
                key={idx}
                className="rounded-md border bg-muted/50 px-2 py-1 text-center"
              >
                <div className="text-[10px] uppercase tracking-wider text-muted-foreground">
                  {labels[idx] ?? `Field ${idx + 1}`}
                </div>
                <div className="font-mono text-sm">{field}</div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Create schedule dialog
// ---------------------------------------------------------------------------

function CreateScheduleDialog({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated: () => void;
}) {
  const [name, setName] = useState("");
  const [schedule, setSchedule] = useState("0 * * * *");
  const [prompt, setPrompt] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setName("");
    setSchedule("0 * * * *");
    setPrompt("");
    setSaving(false);
    setError(null);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmedName = name.trim();
    const trimmedPrompt = prompt.trim();
    const trimmedSchedule = schedule.trim();
    if (!trimmedSchedule || !trimmedPrompt) return;
    setSaving(true);
    setError(null);
    try {
      await aresApi.scheduleCreate({
        name: trimmedName || undefined,
        schedule: trimmedSchedule,
        prompt: trimmedPrompt,
      });
      reset();
      onOpenChange(false);
      onCreated();
    } catch (err) {
      setError(readableError(err, "Failed to create schedule."));
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) reset(); onOpenChange(v); }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>New Schedule</DialogTitle>
          <DialogDescription>
            Create a scheduled job that runs automatically on a cron expression.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={(e) => void handleSubmit(e)} className="grid gap-4 py-2">
          <div className="grid gap-2">
            <Label htmlFor="sched-name">Name (optional)</Label>
            <Input
              id="sched-name"
              placeholder="e.g. Daily digest"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
            />
          </div>
          <CronExpressionBuilder value={schedule} onChange={setSchedule} />
          <div className="grid gap-2">
            <Label htmlFor="sched-prompt">Prompt</Label>
            <Textarea
              id="sched-prompt"
              placeholder="What should this schedule do each time it runs?"
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => { reset(); onOpenChange(false); }}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !schedule.trim() || !prompt.trim()}>
              {saving && <LoaderCircle className="mr-2 size-4 animate-spin" />}
              Create
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Execution history dialog
// ---------------------------------------------------------------------------

function HistoryDialog({
  job,
  open,
  onOpenChange,
}: {
  job: ScheduleEntry | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [runs, setRuns] = useState<CronRun[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !job) return;
    let active = true;
    setLoading(true);
    setError(null);
    aresApi
      .scheduleHistory(job.job_id, 0, 50)
      .then((data) => {
        if (!active) return;
        // The API may return { runs: [...] } or a flat array
        const list = Array.isArray(data)
          ? data
          : (data as Record<string, unknown>).runs
            ? (data as { runs: CronRun[] }).runs
            : [];
        setRuns(list);
      })
      .catch((err) => {
        if (active) setError(readableError(err, "Failed to load history."));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => { active = false; };
  }, [open, job]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-2xl max-h-[70vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>Execution History</DialogTitle>
          <DialogDescription>
            {job ? `Past runs for "${job.name || job.job_id}"` : ""}
          </DialogDescription>
        </DialogHeader>
        <div className="flex-1 overflow-y-auto py-2">
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <LoaderCircle className="size-6 animate-spin text-muted-foreground" />
            </div>
          ) : error ? (
            <p className="text-sm text-destructive text-center py-4">{error}</p>
          ) : runs.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-8">
              No execution history yet.
            </p>
          ) : (
            <div className="grid gap-2">
              {runs.map((run) => (
                <div
                  key={run.id}
                  className="flex items-center justify-between rounded-md border px-3 py-2 text-sm"
                >
                  <div className="flex items-center gap-2 min-w-0">
                    <span
                      className={`inline-block size-2 rounded-full ${
                        run.status === "success"
                          ? "bg-emerald-500"
                          : run.status === "running"
                            ? "bg-blue-500 animate-pulse"
                            : "bg-destructive"
                      }`}
                    />
                    <span className="truncate font-mono text-xs">{run.id.slice(0, 8)}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs text-muted-foreground">
                    <span>{formatRelative(run.started_at)}</span>
                    <Badge
                      variant="outline"
                      className={
                        run.status === "success"
                          ? "text-emerald-700 dark:text-emerald-300"
                          : run.status === "running"
                            ? "text-blue-700 dark:text-blue-300"
                            : "text-destructive"
                      }
                    >
                      {run.status}
                    </Badge>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
        <DialogFooter showCloseButton />
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function CronPage() {
  const [schedules, setSchedules] = useState<ScheduleEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [historyJob, setHistoryJob] = useState<ScheduleEntry | null>(null);
  const [runningId, setRunningId] = useState<string | null>(null);
  const [togglingId, setTogglingId] = useState<string | null>(null);

  const loadSchedules = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await aresApi.schedules();
      setSchedules(data.schedules ?? []);
    } catch (err) {
      setError(readableError(err, "Failed to load schedules."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadSchedules();
  }, [loadSchedules]);

  async function handleRunNow(jobId: string) {
    setRunningId(jobId);
    try {
      await aresApi.scheduleRun(jobId);
    } catch {
      // Still refresh even if run request fails
    }
    setRunningId(null);
    // Refresh after a brief delay to give the backend time to update status
    setTimeout(() => void loadSchedules(), 1000);
  }

  async function handleToggle(job: ScheduleEntry) {
    setTogglingId(job.job_id);
    try {
      if (job.enabled) {
        await aresApi.schedulePause(job.job_id);
      } else {
        await aresApi.scheduleResume(job.job_id);
      }
      setSchedules((prev) =>
        prev.map((s) =>
          s.job_id === job.job_id ? { ...s, enabled: !s.enabled, status: job.enabled ? "paused" : "active" } : s,
        ),
      );
    } catch {
      // Optimistic revert
      setSchedules((prev) =>
        prev.map((s) => (s.job_id === job.job_id ? { ...s, enabled: job.enabled, status: job.status } : s)),
      );
    }
    setTogglingId(null);
  }

  async function handleDelete(jobId: string) {
    try {
      await aresApi.scheduleDelete(jobId);
      setSchedules((prev) => prev.filter((s) => s.job_id !== jobId));
    } catch {
      // Ignore
    }
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Schedules"
        description="Automated jobs that run on a cron schedule. Create, monitor, and trigger scheduled tasks."
        action={
          <Button size="sm" onClick={() => setCreateOpen(true)}>
            <Plus className="size-4" />
            New schedule
          </Button>
        }
      />

      {loading ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
          <p className="text-sm text-muted-foreground">Loading schedules…</p>
        </div>
      ) : error ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <RotateCw className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-destructive">{error}</p>
          <Button variant="outline" size="sm" className="mt-4" onClick={() => void loadSchedules()}>
            <RefreshCw className="size-4" />
            Retry
          </Button>
        </div>
      ) : schedules.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <Clock className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            No schedules yet. Create one to automate recurring tasks.
          </p>
        </div>
      ) : (
        <div className="grid gap-3">
          {schedules.map((job) => (
            <Card key={job.job_id}>
              <CardHeader>
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <Clock className="size-4 shrink-0 text-muted-foreground" />
                      <CardTitle className="truncate text-base">
                        {job.name || job.job_id.slice(0, 8)}
                      </CardTitle>
                      <ScheduleStatusBadge status={job.status} />
                    </div>
                    <CardDescription className="mt-1">
                      <code className="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">
                        {job.schedule}
                      </code>
                    </CardDescription>
                  </div>

                  <div className="flex shrink-0 items-center gap-1">
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label={job.enabled ? "Pause schedule" : "Resume schedule"}
                      disabled={togglingId === job.job_id}
                      onClick={() => void handleToggle(job)}
                    >
                      {togglingId === job.job_id ? (
                        <LoaderCircle className="size-4 animate-spin" />
                      ) : job.enabled ? (
                        <ToggleRight className="size-5 text-green-500" />
                      ) : (
                        <ToggleLeft className="size-5 text-muted-foreground" />
                      )}
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="Run now"
                      disabled={runningId === job.job_id}
                      onClick={() => void handleRunNow(job.job_id)}
                    >
                      {runningId === job.job_id ? (
                        <LoaderCircle className="size-4 animate-spin" />
                      ) : (
                        <Play className="size-4" />
                      )}
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="View history"
                      onClick={() => setHistoryJob(job)}
                    >
                      <RotateCw className="size-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="Delete schedule"
                      className="text-destructive hover:text-destructive"
                      onClick={() => void handleDelete(job.job_id)}
                    >
                      <Trash2 className="size-4" />
                    </Button>
                  </div>
                </div>
              </CardHeader>

              <CardContent className="border-t pt-4">
                <div className="flex flex-wrap items-center gap-x-6 gap-y-2 text-xs text-muted-foreground">
                  {job.last_run_at && (
                    <span className="inline-flex items-center gap-1.5">
                      Last run: {formatRelative(job.last_run_at)}
                    </span>
                  )}
                  {job.next_run_at && job.enabled && (
                    <span className="inline-flex items-center gap-1.5">
                      Next run: {formatRelative(job.next_run_at)}
                    </span>
                  )}
                  {job.profile && (
                    <Badge variant="secondary" className="text-xs">
                      {job.profile}
                    </Badge>
                  )}
                </div>
                {job.prompt && (
                  <p className="mt-2 line-clamp-2 text-sm text-muted-foreground">{job.prompt}</p>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <CreateScheduleDialog open={createOpen} onOpenChange={setCreateOpen} onCreated={() => void loadSchedules()} />
      <HistoryDialog job={historyJob} open={historyJob !== null} onOpenChange={(v) => { if (!v) setHistoryJob(null); }} />
    </div>
  );
}
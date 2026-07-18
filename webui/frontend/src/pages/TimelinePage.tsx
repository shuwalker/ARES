import { useEffect, useState } from "react";
import {
  Calendar,
  Flag,
  LoaderCircle,
  Plus,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

type EventType = "milestone" | "event" | "note";

interface TimelineEvent {
  id: string;
  title: string;
  description: string;
  type: EventType;
  date: string; // ISO date string
  createdAt: string;
}

const STORAGE_KEY = "ares-timeline";

const TYPE_CONFIG: Record<EventType, { label: string; color: string }> = {
  milestone: { label: "Milestone", color: "text-yellow-500 bg-yellow-500/10 border-yellow-500/30" },
  event: { label: "Event", color: "text-blue-500 bg-blue-500/10 border-blue-500/30" },
  note: { label: "Note", color: "text-muted-foreground bg-muted border-border/50" },
};

function loadEvents(): TimelineEvent[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveEvents(events: TimelineEvent[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(events));
}

function uid(): string {
  return Math.random().toString(36).slice(2, 10);
}

function relativeDate(dateStr: string): string {
  const d = new Date(dateStr);
  const now = new Date();
  const diffMs = d.getTime() - now.getTime();
  const absDiffMs = Math.abs(diffMs);
  const days = Math.floor(absDiffMs / 86_400_000);

  if (days === 0) return "Today";
  if (days === 1) return diffMs > 0 ? "Tomorrow" : "Yesterday";
  if (days < 7) return diffMs > 0 ? `In ${days} days` : `${days} days ago`;
  if (days < 30) {
    const weeks = Math.floor(days / 7);
    return diffMs > 0 ? `In ${weeks} week${weeks > 1 ? "s" : ""}` : `${weeks} week${weeks > 1 ? "s" : ""} ago`;
  }
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric", year: d.getFullYear() !== now.getFullYear() ? "numeric" : undefined });
}

export function TimelinePage() {
  const [events, setEvents] = useState<TimelineEvent[]>(loadEvents);
  const [adding, setAdding] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [newType, setNewType] = useState<EventType>("event");
  const [newDate, setNewDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [newDescription, setNewDescription] = useState("");

  useEffect(() => {
    saveEvents(events);
  }, [events]);

  // Sort chronologically, newest first
  const sorted = [...events].sort(
    (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime(),
  );

  function addEvent() {
    if (!newTitle.trim()) return;
    const now = new Date().toISOString();
    setEvents((prev) => [
      ...prev,
      {
        id: uid(),
        title: newTitle.trim(),
        description: newDescription.trim(),
        type: newType,
        date: newDate ? new Date(newDate).toISOString() : now,
        createdAt: now,
      },
    ]);
    setNewTitle("");
    setNewDescription("");
    setNewType("event");
    setNewDate(new Date().toISOString().slice(0, 10));
    setAdding(false);
  }

  function deleteEvent(id: string) {
    setEvents((prev) => prev.filter((e) => e.id !== id));
  }

  function updateEvent(id: string, patch: Partial<TimelineEvent>) {
    setEvents((prev) =>
      prev.map((e) => (e.id === id ? { ...e, ...patch } : e)),
    );
  }

  // Group by date (just the day portion)
  const groups: { label: string; date: string; events: TimelineEvent[] }[] = [];
  let lastDate = "";
  for (const ev of sorted) {
    const dayKey = ev.date.slice(0, 10);
    if (dayKey !== lastDate) {
      groups.push({ label: relativeDate(ev.date), date: ev.date, events: [] });
      lastDate = dayKey;
    }
    groups[groups.length - 1].events.push(ev);
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Timeline"
        description="Chronological log of events and milestones for your Synthetic Person."
        action={
          <Button size="sm" onClick={() => setAdding(true)}>
            <Plus className="size-4" />
            New event
          </Button>
        }
      />

      {adding && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">New Event</CardTitle>
          </CardHeader>
          <CardContent className="border-t pt-4">
            <form
              className="space-y-3"
              onSubmit={(e) => {
                e.preventDefault();
                addEvent();
              }}
            >
              <div className="grid gap-2 sm:grid-cols-[1fr_auto_auto]">
                <Input
                  value={newTitle}
                  onChange={(e) => setNewTitle(e.target.value)}
                  placeholder="Event title…"
                  className="h-8"
                  autoFocus
                />
                <Input
                  type="date"
                  value={newDate}
                  onChange={(e) => setNewDate(e.target.value)}
                  className="h-8 w-36 text-xs"
                />
                <select
                  value={newType}
                  onChange={(e) => setNewType(e.target.value as EventType)}
                  className="h-8 rounded-md border border-input bg-background px-2 text-xs"
                >
                  <option value="event">Event</option>
                  <option value="milestone">Milestone</option>
                  <option value="note">Note</option>
                </select>
              </div>
              <Input
                value={newDescription}
                onChange={(e) => setNewDescription(e.target.value)}
                placeholder="Description (optional)…"
                className="h-8 text-xs"
              />
              <div className="flex gap-2">
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
                    setNewDescription("");
                  }}
                >
                  Cancel
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {sorted.length === 0 && !adding && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <Calendar className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            No events yet. Add milestones and events to build your timeline.
          </p>
        </div>
      )}

      <div className="space-y-6">
        {groups.map((group) => (
          <div key={group.date}>
            <div className="mb-3 flex items-center gap-2">
              <Calendar className="size-4 text-muted-foreground" />
              <h3 className="text-sm font-semibold">{group.label}</h3>
              <span className="text-xs text-muted-foreground">
                {new Date(group.date).toLocaleDateString(undefined, {
                  month: "short",
                  day: "numeric",
                  year: "numeric",
                })}
              </span>
            </div>

            <div className="ml-3 border-l-2 border-border pl-4 space-y-3">
              {group.events.map((ev) => (
                <Card key={ev.id} className="relative">
                  {/* Timeline dot */}
                  <div className="absolute -left-[1.35rem] top-4 size-2.5 rounded-full bg-primary" />

                  <CardHeader className="pb-2">
                    <div className="flex items-start justify-between gap-4">
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          {ev.type === "milestone" && (
                            <Flag className="size-4 text-yellow-500" />
                          )}
                          <CardTitle
                            className={`truncate text-base ${ev.type === "milestone" ? "font-semibold" : "font-medium"}`}
                          >
                            {ev.title || "Untitled event"}
                          </CardTitle>
                          <Badge
                            variant="outline"
                            className={`text-[0.6rem] uppercase tracking-wider ${TYPE_CONFIG[ev.type].color}`}
                          >
                            {TYPE_CONFIG[ev.type].label}
                          </Badge>
                        </div>
                      </div>
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="shrink-0 text-muted-foreground hover:text-destructive"
                        onClick={() => deleteEvent(ev.id)}
                        aria-label="Delete event"
                      >
                        &times;
                      </Button>
                    </div>
                  </CardHeader>

                  {(ev.description || ev.type !== "note") && (
                    <CardContent className="border-t pt-3 space-y-2">
                      {ev.description && (
                        <p className="text-sm text-muted-foreground">
                          {ev.description}
                        </p>
                      )}
                      <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                        <Input
                          type="date"
                          value={ev.date.slice(0, 10)}
                          onChange={(e) =>
                            updateEvent(ev.id, {
                              date: new Date(e.target.value).toISOString(),
                            })
                          }
                          className="h-6 w-28 text-[0.65rem]"
                        />
                      </div>
                    </CardContent>
                  )}
                </Card>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
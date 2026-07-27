import { useMemo, useState } from "react";
import { NavLink, useParams } from "react-router-dom";
import {
  BookHeart,
  Brain,
  Dumbbell,
  Lock,
  Moon,
  NotebookPen,
  Plus,
  Trash2,
} from "lucide-react";

import { SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { useProductState } from "@/shared/use-product-state";

type SelfArea = "journal" | "mind" | "body" | "dreams" | "life" | "private";

const AREAS: Array<{
  id: SelfArea;
  label: string;
  description: string;
  icon: typeof NotebookPen;
  privacy: "standard" | "elevated" | "vault";
}> = [
  { id: "journal", label: "Journal", description: "Daily entries, decisions, events.", icon: NotebookPen, privacy: "elevated" },
  { id: "mind", label: "Mind", description: "Mood, thoughts, meditation, development.", icon: Brain, privacy: "elevated" },
  { id: "body", label: "Body", description: "Health, fitness, sleep, symptoms.", icon: Dumbbell, privacy: "vault" },
  { id: "dreams", label: "Dreams", description: "Dream journal and waking links.", icon: Moon, privacy: "elevated" },
  { id: "life", label: "Life", description: "Goals, relationships, values, timeline.", icon: BookHeart, privacy: "elevated" },
  { id: "private", label: "Private Records", description: "Clinical, legal, insurance — highest lock.", icon: Lock, privacy: "vault" },
];

interface SelfEntry {
  id: string;
  area: SelfArea;
  title: string;
  body: string;
  createdAt: string;
  updatedAt: string;
}

function uid() {
  return Math.random().toString(36).slice(2, 10);
}

/**
 * Self surface — private inner record (knowledge about me).
 * Stricter privacy than Library/Workshop; workers do not get this by default.
 */
export function SelfPage() {
  const params = useParams();
  const areaParam = (params.area as SelfArea | undefined) || "journal";
  const area = AREAS.some((a) => a.id === areaParam) ? areaParam : "journal";
  const meta = AREAS.find((a) => a.id === area)!;

  const [state, setState, { loading, error }] = useProductState<{ entries: SelfEntry[] }>("self-entries", {
    entries: [],
  });
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");

  const entries = useMemo(
    () =>
      state.entries
        .filter((e) => e.area === area)
        .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)),
    [state.entries, area],
  );

  const addEntry = () => {
    const cleanTitle = title.trim() || "Untitled";
    const cleanBody = body.trim();
    if (!cleanBody) return;
    const now = new Date().toISOString();
    setState((cur) => ({
      entries: [
        { id: uid(), area, title: cleanTitle, body: cleanBody, createdAt: now, updatedAt: now },
        ...cur.entries,
      ],
    }));
    setTitle("");
    setBody("");
  };

  const removeEntry = (id: string) => {
    setState((cur) => ({ entries: cur.entries.filter((e) => e.id !== id) }));
  };

  return (
    <SurfaceShell
      title="Self"
      description="Your private inner record — knowledge about you. Engineering workers do not receive this by default."
    >
      <SurfaceNote>
        Privacy wall: {meta.privacy === "vault" ? "vault tier" : "elevated"} for {meta.label}. Grant
        Companion or any worker access only explicitly — never auto-attach medical or private records
        to a Workshop task.
      </SurfaceNote>

      <div className="flex flex-wrap gap-1.5">
        {AREAS.map(({ id, label, icon: Icon }) => (
          <NavLink
            key={id}
            to={id === "journal" ? "/self" : `/self/${id}`}
            className={({ isActive }) =>
              cn(
                "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium transition-colors",
                isActive || area === id
                  ? "border-primary bg-primary/15 text-primary"
                  : "border-border text-muted-foreground hover:border-primary/40 hover:text-foreground",
              )
            }
          >
            <Icon className="size-3.5" />
            {label}
          </NavLink>
        ))}
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <meta.icon className="size-4 text-primary" />
            {meta.label}
          </CardTitle>
          <p className="text-xs text-muted-foreground">{meta.description}</p>
        </CardHeader>
        <CardContent className="space-y-3">
          <Input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Title (optional)"
            className="text-sm"
          />
          <Textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder={`Write in ${meta.label.toLowerCase()}…`}
            rows={4}
            className="text-sm"
          />
          <div className="flex items-center gap-2">
            <Button type="button" size="sm" onClick={addEntry} disabled={!body.trim()}>
              <Plus className="mr-1 size-3.5" />
              Save entry
            </Button>
            {loading && (
              <span className="text-xs text-muted-foreground">Syncing…</span>
            )}
            {error && (
              <span className="text-xs text-destructive">{error}</span>
            )}
          </div>
        </CardContent>
      </Card>

      <div className="space-y-2">
        {entries.length === 0 ? (
          <p className="text-sm text-muted-foreground">No entries in {meta.label} yet.</p>
        ) : (
          entries.map((entry) => (
            <Card key={entry.id}>
              <CardContent className="flex items-start gap-3 p-4">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-sm font-medium">{entry.title}</p>
                    <button
                      type="button"
                      title="Delete entry"
                      onClick={() => removeEntry(entry.id)}
                      className="text-muted-foreground hover:text-destructive"
                    >
                      <Trash2 className="size-3.5" />
                    </button>
                  </div>
                  <p className="mt-1 whitespace-pre-wrap text-sm text-muted-foreground">{entry.body}</p>
                  <p className="mt-2 font-mono text-[10px] uppercase tracking-wider text-muted-foreground/70">
                    {new Date(entry.updatedAt).toLocaleString()}
                  </p>
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>

      <div className="grid gap-2 sm:grid-cols-2">
        <NavLink to="/goals" className="rounded-md border border-border px-3 py-2 text-xs hover:border-primary/40">
          Goals → Life continuity
        </NavLink>
        <NavLink to="/timeline" className="rounded-md border border-border px-3 py-2 text-xs hover:border-primary/40">
          Timeline → personal history
        </NavLink>
        <NavLink to="/cases" className="rounded-md border border-border px-3 py-2 text-xs hover:border-primary/40">
          Life Admin → cases
        </NavLink>
      </div>
    </SurfaceShell>
  );
}

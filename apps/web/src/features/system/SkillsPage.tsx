import { useCallback, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { AlertCircle, LoaderCircle, Pencil, Plus, RefreshCw, Trash2, Wrench } from "lucide-react";

import { EmptyState } from "@/components/EmptyState";
import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { aresApi } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";

type SkillSummary = {
  name: string;
  description: string;
  category: string | null;
  disabled: boolean;
};

export default function SkillsPage() {
  const [skills, setSkills] = useState<SkillSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState("");
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const result = await aresApi.skillsList();
      setSkills(result.skills);
      if (!result.skill_runtime_available) setError("The skill runtime is unavailable in this installation.");
    } catch (reason) {
      setError(readableError(reason, "Skills could not be loaded."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function toggle(skill: SkillSummary, enabled: boolean) {
    setWorking(skill.name); setError("");
    try {
      await aresApi.skillsToggle(skill.name, enabled);
      setSkills((current) => current.map((item) => item.name === skill.name ? { ...item, disabled: !enabled } : item));
    } catch (reason) {
      setError(readableError(reason, `Could not ${enabled ? "enable" : "disable"} ${skill.name}.`));
    } finally { setWorking(""); }
  }

  async function remove(skill: SkillSummary) {
    if (!window.confirm(`Delete the local skill “${skill.name}”? This cannot be undone.`)) return;
    setWorking(skill.name); setError("");
    try {
      await aresApi.skillsDelete(skill.name);
      setSkills((current) => current.filter((item) => item.name !== skill.name));
    } catch (reason) {
      setError(readableError(reason, `Could not delete ${skill.name}. Built-in or plugin skills may be read-only.`));
    } finally { setWorking(""); }
  }

  const categories = useMemo(() => new Set(skills.map((skill) => skill.category).filter(Boolean)).size, [skills]);

  return (
    <div className="page-stack">
      <PageHeader title="Skills" description={`${skills.length} available across ${categories} categories. Enable, inspect, or create reusable capabilities.`} action={<div className="flex gap-2"><Button size="sm" variant="outline" onClick={() => void load()} disabled={loading}><RefreshCw className={loading ? "animate-spin" : ""} />Refresh</Button><Button size="sm" asChild><Link to="/skills/studio"><Plus />New skill</Link></Button></div>} />
      {error ? <div className="flex items-center gap-2 rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive"><AlertCircle className="size-4" />{error}</div> : null}
      {loading ? <div className="grid place-items-center py-16 text-sm text-muted-foreground"><LoaderCircle className="mb-2 animate-spin" />Loading skills…</div> : skills.length === 0 ? <div className="space-y-3"><EmptyState icon={Wrench} title="No skills available" description="Create a skill to give ARES a reusable, explicit workflow." /><div className="flex justify-center"><Button asChild><Link to="/skills/studio"><Plus />Create skill</Link></Button></div></div> : <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">{skills.map((skill) => <Card key={skill.name}><CardContent className="space-y-3 pt-5"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><div className="truncate font-medium">{skill.name}</div><Badge variant="outline" className="mt-1">{skill.category || "uncategorized"}</Badge></div><ToggleSwitch checked={!skill.disabled} disabled={working === skill.name} onCheckedChange={(enabled) => void toggle(skill, enabled)} /></div><p className="min-h-10 text-sm text-muted-foreground">{skill.description || "No description provided."}</p><div className="flex justify-end gap-2"><Button size="sm" variant="outline" asChild><Link to={`/skills/studio?name=${encodeURIComponent(skill.name)}`}><Pencil />Edit</Link></Button><Button size="sm" variant="outline" disabled={working === skill.name} onClick={() => void remove(skill)} aria-label={`Delete ${skill.name}`}><Trash2 className="text-destructive" /></Button></div></CardContent></Card>)}</div>}
    </div>
  );
}

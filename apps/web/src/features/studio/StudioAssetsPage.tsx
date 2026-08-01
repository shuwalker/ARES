import { FolderOpen, Plus, Trash2 } from "lucide-react";
import { useState } from "react";

import { SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { useProductState } from "@/shared/use-product-state";
import {
  EMPTY_STUDIO_STATE,
  STUDIO_KIND_LABELS,
  studioId,
  type StudioKind,
} from "@/features/studio/studio-state";

export function StudioAssetsPage() {
  const [state, setState, status] = useProductState("studio", EMPTY_STUDIO_STATE);
  const [name, setName] = useState("");
  const [location, setLocation] = useState("");
  const [kind, setKind] = useState<StudioKind>("image");

  const add = () => {
    if (!name.trim() || !location.trim()) return;
    setState((current) => ({
      ...current,
      assets: [{
        id: studioId("asset"),
        name: name.trim(),
        location: location.trim(),
        kind,
        createdAt: new Date().toISOString(),
      }, ...current.assets],
    }));
    setName("");
    setLocation("");
  };

  return (
    <SurfaceShell title="Studio Assets" description="References and creative outputs used across Studio projects.">
      <SurfaceNote>
        Register local paths or URLs without copying or deleting the original file. Generated-asset ingestion will use this same catalog.
      </SurfaceNote>
      {status.error && <p className="text-sm text-destructive">{status.error}</p>}
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2 text-base"><Plus className="size-4 text-primary" />Add asset</CardTitle></CardHeader>
        <CardContent className="grid gap-2 sm:grid-cols-[1fr_1fr_auto_auto]">
          <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Asset name" />
          <Input value={location} onChange={(e) => setLocation(e.target.value)} placeholder="File path or URL" />
          <select value={kind} onChange={(e) => setKind(e.target.value as StudioKind)} className="rounded-md border border-input bg-background px-3 text-sm">
            {Object.entries(STUDIO_KIND_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
          <Button onClick={add} disabled={!name.trim() || !location.trim()}>Add</Button>
        </CardContent>
      </Card>
      <div className="space-y-2">
        {status.loading ? <p className="text-sm text-muted-foreground">Loading assets…</p> : state.assets.length === 0 ? (
          <Card><CardContent className="py-8 text-center text-sm text-muted-foreground">No Studio assets registered.</CardContent></Card>
        ) : state.assets.map((asset) => (
          <Card key={asset.id}><CardContent className="flex items-center gap-3 py-3">
            <FolderOpen className="size-4 shrink-0 text-primary" />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{asset.name}</p>
              <p className="truncate text-xs text-muted-foreground">{asset.location}</p>
            </div>
            <Badge variant="outline">{STUDIO_KIND_LABELS[asset.kind]}</Badge>
            <Button variant="ghost" size="icon" aria-label={`Remove ${asset.name}`} onClick={() => setState((current) => ({ ...current, assets: current.assets.filter((item) => item.id !== asset.id) }))}>
              <Trash2 className="size-4 text-destructive" />
            </Button>
          </CardContent></Card>
        ))}
      </div>
    </SurfaceShell>
  );
}

import { File, FileCode2, Folder, KanbanSquare, LoaderCircle, PackageOpen } from "lucide-react";
import { useEffect, useState } from "react";

import { EmptyState } from "@/components/EmptyState";
import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import type { WorkspaceEntry } from "@/shared/contracts";

export function WorkspacePage() {
  const { snapshot, selectedSessionId, selectSession } = useAres();
  const [entries, setEntries] = useState<WorkspaceEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const workspaceSessions = snapshot.sessions.filter((session) => session.workspace);

  useEffect(() => {
    if (!selectedSessionId || !workspaceSessions.some((session) => session.id === selectedSessionId)) return;
    setLoading(true);
    setError("");
    aresApi.listWorkspace(selectedSessionId).then(setEntries).catch((reason) => setError(readableError(reason, "Workspace files could not be loaded."))).finally(() => setLoading(false));
  }, [selectedSessionId, workspaceSessions.length]);

  return (
    <div className="page-stack">
      <PageHeader title="Workspace" description="Inspect files, tasks, and artifacts through stable ARES interfaces shared by every supported runtime." />
      {workspaceSessions.length ? <label className="flex max-w-xl items-center gap-3 text-sm"><span>Session workspace</span><select className="min-w-0 flex-1 rounded-md border bg-background px-3 py-2" value={workspaceSessions.some((item) => item.id === selectedSessionId) ? selectedSessionId : ""} onChange={(event) => selectSession(event.target.value)}><option value="" disabled>Select a session</option>{workspaceSessions.map((session) => <option key={session.id} value={session.id}>{session.title} — {session.workspace}</option>)}</select></label> : null}
      <Tabs defaultValue="files">
        <TabsList><TabsTrigger value="files">Files</TabsTrigger><TabsTrigger value="tasks">Tasks</TabsTrigger><TabsTrigger value="artifacts">Artifacts</TabsTrigger></TabsList>
        <TabsContent value="files"><Card><CardContent>
          {loading ? <p className="flex items-center gap-2 text-sm text-muted-foreground"><LoaderCircle className="size-4 animate-spin" />Loading workspace…</p> : error ? <p className="text-sm text-status-limited">{error}</p> : entries.length ? <div className="divide-y">{entries.map((entry) => <div key={entry.path} className="flex items-center gap-3 py-2 text-sm">{entry.kind === "directory" ? <Folder className="size-4 text-primary" /> : <File className="size-4 text-muted-foreground" />}<span>{entry.name}</span>{entry.size !== undefined ? <span className="ml-auto text-xs text-muted-foreground">{entry.size.toLocaleString()} bytes</span> : null}</div>)}</div> : <EmptyState icon={FileCode2} title="No workspace selected" description="Choose a conversation with a workspace to inspect its files." />}
        </CardContent></Card></TabsContent>
        <TabsContent value="tasks"><Card><CardContent><EmptyState icon={KanbanSquare} title="No tasks" description="ARES uses Task as the single name for a normalized unit of planned work." /></CardContent></Card></TabsContent>
        <TabsContent value="artifacts"><Card><CardContent><EmptyState icon={PackageOpen} title="No artifacts" description="Generated documents, code, and media will appear here through the artifact contract." /></CardContent></Card></TabsContent>
      </Tabs>
    </div>
  );
}

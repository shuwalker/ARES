import { Activity, Box, Cpu, Wrench } from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useAres } from "@/shared/ares-context";

export function ActivityPage() {
  const { snapshot } = useAres();
  const active = snapshot.sessions.filter((session) => session.activeStreamId);
  return <div className="page-stack"><PageHeader title="Activity" description="A visual inspection surface grounded in reported execution, model, and tool state." /><div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_20rem]"><section className="activity-stage" aria-label="Execution environment"><div className="activity-node"><Cpu className="size-7" /><span>SI interface</span><Badge variant="outline">{active.length ? "working" : "idle"}</Badge></div><p className="absolute bottom-4 left-4 text-xs text-muted-foreground">{active.length ? `${active.length} active execution${active.length === 1 ? "" : "s"}` : "No active execution telemetry"}</p></section><div className="grid gap-4"><Card><CardHeader className="flex-row items-center gap-2"><Activity className="size-4" /><CardTitle>Executions</CardTitle></CardHeader><CardContent className="text-sm text-muted-foreground">{active.length ? active.map((item) => <p key={item.id}>{item.title}</p>) : "No active executions."}</CardContent></Card><Card><CardHeader className="flex-row items-center gap-2"><Wrench className="size-4" /><CardTitle>Tools</CardTitle></CardHeader><CardContent className="text-sm text-muted-foreground">{snapshot.tools.total ? `${snapshot.tools.total} tools available` : "No active tools reported."}</CardContent></Card><Card><CardHeader className="flex-row items-center gap-2"><Box className="size-4" /><CardTitle>Runtime</CardTitle></CardHeader><CardContent className="text-sm text-muted-foreground">{snapshot.agentHealth.detail}</CardContent></Card></div></div></div>;
}

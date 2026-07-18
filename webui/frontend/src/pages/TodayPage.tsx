import { CalendarClock, CheckCircle2, MessageCircle, Network, PlayCircle } from "lucide-react";
import { Link } from "react-router-dom";

import { EmptyState } from "@/components/EmptyState";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useAres } from "@/shared/ares-context";
import { useLocalProfile } from "@/shared/local-profile";

export function TodayPage() {
  const { profile } = useLocalProfile();
  const { snapshot } = useAres();
  const greeting = profile.displayName ? `Good to see you, ${profile.displayName}.` : "Your day at a glance.";
  const active = snapshot.sessions.filter((session) => session.activeStreamId);
  const recent = snapshot.sessions.slice(0, 5);
  return (
    <div className="page-stack">
      <PageHeader title="Today" description={`${greeting} This view reports current ARES state without requiring an assistant runtime.`} action={<Button asChild variant="outline"><Link to="/conversation">Open conversation</Link></Button>} />
      {snapshot.error ? <p className="rounded-md border border-status-limited/40 bg-status-limited/10 px-4 py-3 text-sm text-status-limited">{snapshot.error}</p> : null}
      <section className="grid gap-4 lg:grid-cols-3" aria-label="Today summary">
        <Card><CardHeader className="flex-row items-center gap-3"><CheckCircle2 className="size-5 text-status-available" /><CardTitle>Tasks completed</CardTitle></CardHeader><CardContent className="text-3xl font-semibold">0</CardContent></Card>
        <Card><CardHeader className="flex-row items-center gap-3"><CalendarClock className="size-5 text-status-limited" /><CardTitle>Tasks due soon</CardTitle></CardHeader><CardContent className="text-3xl font-semibold">0</CardContent></Card>
        <Card><CardHeader className="flex-row items-center gap-3"><PlayCircle className="size-5 text-primary" /><CardTitle>Active executions</CardTitle></CardHeader><CardContent className="text-3xl font-semibold">{active.length}</CardContent></Card>
      </section>
      <section className="grid gap-4 xl:grid-cols-2">
        <Card><CardHeader><CardTitle>Recent conversations</CardTitle></CardHeader><CardContent>{recent.length ? <div className="divide-y">{recent.map((session) => <Link key={session.id} to="/conversation" className="flex items-center gap-3 py-3 text-sm hover:text-primary"><MessageCircle className="size-4" /><span className="min-w-0 flex-1 truncate">{session.title}</span><span className="truncate text-xs text-muted-foreground">{session.model || "Local session"}</span></Link>)}</div> : <EmptyState icon={MessageCircle} title="No conversations yet" description="Start a conversation to create the first local session." />}</CardContent></Card>
        <Card><CardHeader><CardTitle>System activity</CardTitle></CardHeader><CardContent>{active.length ? <div className="space-y-2">{active.map((session) => <p key={session.id} className="flex items-center gap-2 text-sm"><PlayCircle className="size-4 text-primary" />{session.title}</p>)}</div> : <EmptyState icon={Network} title="No active executions" description={snapshot.agentHealth.detail} />}</CardContent></Card>
      </section>
    </div>
  );
}

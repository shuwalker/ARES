import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity,
  Bot,
  ChevronDown,
  ChevronRight,
  Cpu,
  FileText,
  Filter,
  Globe,
  MessageSquare,
  User,
  Wrench,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import type { SessionSummary, UsageInsights } from "@/shared/contracts";

// ── Types ──────────────────────────────────────────────────────────

type ActivityCategory = "all" | "sessions" | "files" | "system";

interface ActivityEntry {
  id: string;
  category: "sessions" | "files" | "system";
  actor: "user" | "assistant" | "system";
  actorLabel: string;
  action: string;
  entityName: string;
  entityDetail?: string;
  timestamp: string;
  details: Record<string, unknown>;
}

// ── Helpers ─────────────────────────────────────────────────────────

function relativeTime(value?: string | null): string {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (seconds < 0) return "now";
  if (seconds < 60) return "just now";
  const mins = Math.floor(seconds / 60);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 30) return `${days}d ago`;
  return date.toLocaleDateString();
}

function actorIcon(actor: "user" | "assistant" | "system") {
  switch (actor) {
    case "user":
      return <User className="size-3.5" />;
    case "assistant":
      return <Bot className="size-3.5" />;
    case "system":
      return <Cpu className="size-3.5" />;
  }
}

function actorBadgeVariant(actor: "user" | "assistant" | "system") {
  switch (actor) {
    case "user":
      return "default" as const;
    case "assistant":
      return "secondary" as const;
    case "system":
      return "outline" as const;
  }
}

function categoryIcon(category: ActivityCategory) {
  switch (category) {
    case "sessions":
      return <MessageSquare className="size-4" />;
    case "files":
      return <FileText className="size-4" />;
    case "system":
      return <Wrench className="size-4" />;
    default:
      return <Activity className="size-4" />;
  }
}

// ── Build activity entries from data sources ────────────────────────

function buildSessionEntries(sessions: SessionSummary[]): ActivityEntry[] {
  return sessions.map((s) => ({
    id: `session:${s.id}`,
    category: "sessions" as const,
    actor: (s.source === "api" ? "system" : "user") as ActivityEntry["actor"],
    actorLabel: s.source === "api" ? "System" : "You",
    action: s.isStreaming ? "is streaming in" : "conversed in",
    entityName: s.title || "Untitled session",
    entityDetail: `${s.model} · ${s.provider}`,
    timestamp: s.updatedAt || s.id,
    details: {
      model: s.model,
      provider: s.provider,
      workspace: s.workspace,
      profile: s.profile,
      messageCount: s.messageCount,
      pinned: s.pinned,
      activeStreamId: s.activeStreamId,
    },
  }));
}

function buildSystemEntries(
  insights: UsageInsights | null,
  snapshot: { agentHealth: { detail: string }; tools: { total: number; names: string[] } },
): ActivityEntry[] {
  const entries: ActivityEntry[] = [];

  if (insights) {
    entries.push({
      id: "insights:usage",
      category: "system",
      actor: "system",
      actorLabel: "System",
      action: "tracked usage across",
      entityName: `${insights.totalSessions} sessions`,
      entityDetail: `${insights.totalMessages.toLocaleString()} messages · ${insights.totalTokens.toLocaleString()} tokens · $${insights.totalCost.toFixed(2)}`,
      timestamp: new Date().toISOString(),
      details: {
        totalSessions: insights.totalSessions,
        totalMessages: insights.totalMessages,
        totalTokens: insights.totalTokens,
        totalCost: insights.totalCost,
        periodDays: insights.periodDays,
      },
    });

    for (const model of insights.models.slice(0, 5)) {
      entries.push({
        id: `insights:model:${model.key}`,
        category: "system",
        actor: "assistant",
        actorLabel: model.key,
        action: "processed",
        entityName: `${model.totalTokens.toLocaleString()} tokens`,
        entityDetail: `${model.sessions} sessions · $${model.cost.toFixed(2)}`,
        timestamp: new Date().toISOString(),
        details: { model: model.key, sessions: model.sessions, tokens: model.totalTokens, cost: model.cost },
      });
    }
  }

  entries.push({
    id: "system:health",
    category: "system",
    actor: "system",
    actorLabel: "System",
    action: "reported health:",
    entityName: snapshot.agentHealth.detail || "OK",
    timestamp: new Date().toISOString(),
    details: { tools: snapshot.tools.total },
  });

  return entries;
}

function buildFileEntries(sessions: SessionSummary[]): ActivityEntry[] {
  const entries: ActivityEntry[] = [];
  const seen = new Set<string>();

  for (const s of sessions) {
    const ws = s.workspace;
    if (ws && !seen.has(ws)) {
      seen.add(ws);
      entries.push({
        id: `file:ws:${s.id}`,
        category: "files",
        actor: "user",
        actorLabel: "You",
        action: "worked in",
        entityName: ws.split("/").pop() || ws,
        entityDetail: ws,
        timestamp: s.updatedAt || s.id,
        details: { workspace: ws, profile: s.profile },
      });
    }
  }

  return entries;
}

// ── Activity Row ────────────────────────────────────────────────────

function ActivityRow({ entry }: { entry: ActivityEntry }) {
  const [open, setOpen] = useState(false);
  const hasDetails = Object.keys(entry.details).length > 0;

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <div className="flex items-start gap-3 rounded-lg border border-transparent px-3 py-2.5 transition-colors hover:bg-accent/40">
        <div className="mt-0.5 shrink-0">{categoryIcon(entry.category)}</div>

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <Badge variant={actorBadgeVariant(entry.actor)} className="gap-1 text-[10px]">
              {actorIcon(entry.actor)}
              {entry.actorLabel}
            </Badge>
            <span className="min-w-0 flex-1 truncate text-sm">
              <span className="text-muted-foreground">{entry.action}</span>{" "}
              <span className="font-medium">{entry.entityName}</span>
              {entry.entityDetail && (
                <span className="text-muted-foreground"> — {entry.entityDetail}</span>
              )}
            </span>
            <span className="shrink-0 text-xs text-muted-foreground">
              {relativeTime(entry.timestamp)}
            </span>
          </div>

          {hasDetails && (
            <CollapsibleTrigger asChild>
              <Button variant="ghost" size="sm" className="mt-1 h-6 gap-1 px-1 text-xs text-muted-foreground">
                {open ? <ChevronDown className="size-3" /> : <ChevronRight className="size-3" />}
                Details
              </Button>
            </CollapsibleTrigger>
          )}

          <CollapsibleContent>
            <div className="mt-2 grid gap-1.5 rounded-md border bg-muted/30 p-3 text-xs">
              {Object.entries(entry.details).map(([key, value]) => (
                <div key={key} className="flex gap-2">
                  <span className="w-28 shrink-0 font-medium text-muted-foreground">{key}</span>
                  <span className="truncate font-mono">
                    {typeof value === "boolean" ? (value ? "Yes" : "No") : String(value ?? "")}
                  </span>
                </div>
              ))}
            </div>
          </CollapsibleContent>
        </div>
      </div>
    </Collapsible>
  );
}

// ── Stats Cards ─────────────────────────────────────────────────────

function StatCard({ icon, title, value, subtitle }: { icon: React.ReactNode; title: string; value: string | number; subtitle?: string }) {
  return (
    <Card>
      <CardHeader className="flex-row items-center gap-2 pb-2">
        {icon}
        <CardTitle className="text-sm">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="text-2xl font-semibold">{value}</p>
        {subtitle && <p className="text-xs text-muted-foreground">{subtitle}</p>}
      </CardContent>
    </Card>
  );
}

// ── Main Page ───────────────────────────────────────────────────────

export function ActivityPage() {
  const { snapshot } = useAres();
  const [insights, setInsights] = useState<UsageInsights | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [filter, setFilter] = useState<ActivityCategory>("all");

  useEffect(() => {
    let active = true;
    setLoading(true);
    aresApi
      .insights(30)
      .then((data) => {
        if (active) setInsights(data);
      })
      .catch((e) => {
        if (active) setError(e instanceof Error ? e.message : "Failed to load activity data");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const entries = useMemo(() => {
    const sessionEntries = buildSessionEntries(snapshot.sessions);
    const fileEntries = buildFileEntries(snapshot.sessions);
    const systemEntries = buildSystemEntries(insights, snapshot);
    return [...sessionEntries, ...fileEntries, ...systemEntries].sort(
      (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime(),
    );
  }, [snapshot.sessions, insights, snapshot.agentHealth, snapshot.tools]);

  const filtered = useMemo(
    () => (filter === "all" ? entries : entries.filter((e) => e.category === filter)),
    [entries, filter],
  );

  const categoryCounts = useMemo(() => {
    const counts: Record<ActivityCategory, number> = { all: entries.length, sessions: 0, files: 0, system: 0 };
    for (const e of entries) counts[e.category]++;
    return counts;
  }, [entries]);

  const active = snapshot.sessions.filter((s) => s.activeStreamId);

  if (loading) {
    return (
      <div className="page-stack">
        <PageHeader title="Activity" description="A visual inspection surface grounded in reported execution, model, and tool state." />
        <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_20rem]">
          <section className="activity-stage">
            <div className="activity-node">
              <Cpu className="size-7" />
              <span>Loading…</span>
            </div>
          </section>
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <PageHeader
        title="Activity"
        description="A visual inspection surface grounded in reported execution, model, and tool state."
      />

      {/* Stats row */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          icon={<Activity className="size-4" />}
          title="Total Sessions"
          value={insights?.totalSessions ?? snapshot.sessions.length}
          subtitle={insights ? `Last ${insights.periodDays} days` : undefined}
        />
        <StatCard
          icon={<MessageSquare className="size-4" />}
          title="Messages"
          value={insights?.totalMessages?.toLocaleString() ?? "—"}
          subtitle={insights ? `${insights.totalTokens.toLocaleString()} tokens` : undefined}
        />
        <StatCard
          icon={<Bot className="size-4" />}
          title="Active Now"
          value={active.length}
          subtitle={active.length === 1 ? active[0].title : undefined}
        />
        <StatCard
          icon={<Wrench className="size-4" />}
          title="Tools"
          value={snapshot.tools.total}
          subtitle={snapshot.tools.names.slice(0, 3).join(", ") || undefined}
        />
      </div>

      {/* Filtered feed */}
      <Tabs value={filter} onValueChange={(v) => setFilter(v as ActivityCategory)}>
        <TabsList variant="line">
          <TabsTrigger value="all" className="gap-1.5">
            <Filter className="size-3" />
            All <span className="text-muted-foreground">({categoryCounts.all})</span>
          </TabsTrigger>
          <TabsTrigger value="sessions" className="gap-1.5">
            <MessageSquare className="size-3" />
            Sessions <span className="text-muted-foreground">({categoryCounts.sessions})</span>
          </TabsTrigger>
          <TabsTrigger value="files" className="gap-1.5">
            <FileText className="size-3" />
            Files <span className="text-muted-foreground">({categoryCounts.files})</span>
          </TabsTrigger>
          <TabsTrigger value="system" className="gap-1.5">
            <Globe className="size-3" />
            System <span className="text-muted-foreground">({categoryCounts.system})</span>
          </TabsTrigger>
        </TabsList>

        <TabsContent value={filter}>
          {error && <p className="text-sm text-destructive">{error}</p>}

          {filtered.length === 0 && (
            <div className="flex flex-col items-center gap-2 py-12 text-muted-foreground">
              <Activity className="size-8" />
              <p className="text-sm">No activity to display.</p>
            </div>
          )}

          {filtered.length > 0 && (
            <Card className="overflow-hidden">
              <ScrollArea className="max-h-[60vh]">
                <div className="divide-y divide-border">
                  {filtered.map((entry) => (
                    <ActivityRow key={entry.id} entry={entry} />
                  ))}
                </div>
              </ScrollArea>
            </Card>
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
}
import { useEffect, useState } from "react";
import { CircleDot, ListTodo, Plus, Search } from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useAres } from "@/shared/ares-context";

type IssueStatus = "open" | "in_progress" | "done" | "cancelled";

interface Issue {
  id: string;
  title: string;
  description: string;
  status: IssueStatus;
  priority: "low" | "medium" | "high" | "critical";
  assignedTo?: string;
  createdAt: string;
  updatedAt: string;
}

const STATUS_LABELS: Record<IssueStatus, string> = {
  open: "Open",
  in_progress: "In Progress",
  done: "Done",
  cancelled: "Cancelled",
};

const PRIORITY_COLORS: Record<string, string> = {
  critical: "text-red-500 bg-red-500/10 border-red-500/30",
  high: "text-orange-500 bg-orange-500/10 border-orange-500/30",
  medium: "text-yellow-500 bg-yellow-500/10 border-yellow-500/30",
  low: "text-muted-foreground bg-muted border-border/50",
};

export default function IssuesPage() {
  const { snapshot } = useAres();
  const [issues, setIssues] = useState<Issue[]>([]);
  const [statusFilter, setStatusFilter] = useState<IssueStatus | "all">("all");
  const [search, setSearch] = useState("");

  useEffect(() => {
    fetch("/api/issues")
      .then((r) => r.json())
      .then((data) => setIssues(data.issues || []))
      .catch(() => setIssues([]));
  }, []);

  const filtered = issues
    .filter((i) => statusFilter === "all" || i.status === statusFilter)
    .filter((i) => !search || i.title.toLowerCase().includes(search.toLowerCase()) || i.description.toLowerCase().includes(search.toLowerCase()))
    .sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime());

  const counts = {
    open: issues.filter((i) => i.status === "open").length,
    in_progress: issues.filter((i) => i.status === "in_progress").length,
    done: issues.filter((i) => i.status === "done").length,
  };

  return (
    <div className="page-stack">
      <PageHeader title="Issues" description="Track tasks and work items." action={<Button size="sm"><Plus /> New issue</Button>} />

      <div className="flex items-center gap-4">
        <Tabs value={statusFilter} onValueChange={(v) => setStatusFilter(v as IssueStatus | "all")}>
          <TabsList>
            <TabsTrigger value="all">All ({issues.length})</TabsTrigger>
            <TabsTrigger value="open">Open ({counts.open})</TabsTrigger>
            <TabsTrigger value="in_progress">Active ({counts.in_progress})</TabsTrigger>
            <TabsTrigger value="done">Done ({counts.done})</TabsTrigger>
          </TabsList>
        </Tabs>
        <div className="relative ml-auto">
          <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search issues..."
            className="w-48 pl-8"
          />
        </div>
      </div>

      {filtered.length === 0 && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <ListTodo className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">No issues found.</p>
        </div>
      )}

      <div className="grid gap-3">
        {filtered.map((issue) => (
          <Card key={issue.id} className="cursor-pointer transition-colors hover:bg-accent/50">
            <CardHeader className="pb-2">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <CircleDot className={`size-3.5 ${
                      issue.status === "open" ? "text-blue-500" :
                      issue.status === "in_progress" ? "text-yellow-500" :
                      issue.status === "done" ? "text-green-500" : "text-muted-foreground"
                    }`} />
                    <CardTitle className="text-sm font-medium">{issue.title}</CardTitle>
                  </div>
                  {issue.description && (
                    <CardDescription className="mt-1 line-clamp-2">{issue.description}</CardDescription>
                  )}
                </div>
                <Badge variant="outline" className={`text-[0.6rem] uppercase tracking-wider ${PRIORITY_COLORS[issue.priority] || ""}`}>
                  {issue.priority}
                </Badge>
              </div>
            </CardHeader>
            <CardContent className="pt-2">
              <div className="flex items-center gap-3 text-[0.65rem] text-muted-foreground">
                <Badge variant="outline" className="text-[0.6rem] uppercase tracking-wider">
                  {STATUS_LABELS[issue.status]}
                </Badge>
                {issue.assignedTo && <span>Assigned to {issue.assignedTo}</span>}
                <span className="ml-auto">{new Date(issue.updatedAt).toLocaleDateString()}</span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

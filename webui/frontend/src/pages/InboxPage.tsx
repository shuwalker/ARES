import { useEffect, useState } from "react";
import { CheckCircle2, Clock, Inbox, ShieldCheck, XCircle } from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useAres } from "@/shared/ares-context";

type ApprovalStatus = "pending" | "approved" | "rejected" | "revision_requested";

interface Approval {
  id: string;
  type: string;
  status: ApprovalStatus;
  subject: string;
  detail: string;
  requestedBy: string;
  createdAt: string;
  payload: Record<string, unknown>;
}

function statusIcon(status: ApprovalStatus) {
  if (status === "approved") return <CheckCircle2 className="size-4 text-green-500" />;
  if (status === "rejected") return <XCircle className="size-4 text-red-500" />;
  if (status === "revision_requested") return <Clock className="size-4 text-amber-500" />;
  return <Clock className="size-4 text-yellow-500" />;
}

export default function InboxPage() {
  const { snapshot } = useAres();
  const [approvals, setApprovals] = useState<Approval[]>([]);
  const [statusFilter, setStatusFilter] = useState<"pending" | "all">("pending");
  const [actionPending, setActionPending] = useState<string | null>(null);

  useEffect(() => {
    // Load approvals from ARES backend
    fetch("/api/approvals")
      .then((r) => r.json())
      .then((data) => setApprovals(data.approvals || []))
      .catch(() => setApprovals([]));
  }, []);

  const filtered = approvals
    .filter((a) => statusFilter === "all" || a.status === "pending" || a.status === "revision_requested")
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  const pendingCount = approvals.filter(
    (a) => a.status === "pending" || a.status === "revision_requested",
  ).length;

  async function handleApprove(id: string) {
    setActionPending(id);
    try {
      await fetch(`/api/approvals/${id}/approve`, { method: "POST" });
      setApprovals((prev) => prev.map((a) => a.id === id ? { ...a, status: "approved" as const } : a));
    } catch { /* ignore */ }
    setActionPending(null);
  }

  async function handleReject(id: string) {
    setActionPending(id);
    try {
      await fetch(`/api/approvals/${id}/reject`, { method: "POST" });
      setApprovals((prev) => prev.map((a) => a.id === id ? { ...a, status: "rejected" as const } : a));
    } catch { /* ignore */ }
    setActionPending(null);
  }

  return (
    <div className="page-stack">
      <PageHeader title="Inbox" description="Approvals and requests requiring your attention." />

      <Tabs value={statusFilter} onValueChange={(v) => setStatusFilter(v as "pending" | "all")}>
        <TabsList>
          <TabsTrigger value="pending">
            Pending
            {pendingCount > 0 && (
              <Badge variant="secondary" className="ml-2 bg-yellow-500/20 text-yellow-600 dark:text-yellow-400">
                {pendingCount}
              </Badge>
            )}
          </TabsTrigger>
          <TabsTrigger value="all">All</TabsTrigger>
        </TabsList>
      </Tabs>

      {filtered.length === 0 && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
            <Inbox className="size-6 text-muted-foreground/50" />
          </div>
          <p className="text-sm text-muted-foreground">
            {statusFilter === "pending" ? "No pending approvals." : "No approvals yet."}
          </p>
        </div>
      )}

      <div className="grid gap-3">
        {filtered.map((approval) => (
          <Card key={approval.id}>
            <CardHeader>
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <Badge variant="outline" className="text-xs uppercase tracking-wider text-muted-foreground">
                      {approval.type}
                    </Badge>
                    {approval.requestedBy && (
                      <span className="text-xs text-muted-foreground">
                        Requested by {approval.requestedBy}
                      </span>
                    )}
                  </div>
                  <CardTitle className="mt-2 text-base">{approval.subject}</CardTitle>
                  <CardDescription className="mt-1">{approval.detail}</CardDescription>
                </div>
                <div className="inline-flex shrink-0 items-center gap-1.5 rounded-full border bg-background px-2.5 py-1 text-xs text-muted-foreground">
                  {statusIcon(approval.status)}
                  <span className="capitalize">{approval.status.replace(/_/g, " ")}</span>
                </div>
              </div>
            </CardHeader>
            {(approval.status === "pending" || approval.status === "revision_requested") && (
              <CardContent className="border-t pt-4">
                <div className="flex items-center gap-2">
                  <Button
                    size="sm"
                    className="bg-green-700 text-white hover:bg-green-600"
                    onClick={() => handleApprove(approval.id)}
                    disabled={actionPending === approval.id}
                  >
                    {actionPending === approval.id ? "Approving..." : "Approve"}
                  </Button>
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => handleReject(approval.id)}
                    disabled={actionPending === approval.id}
                  >
                    {actionPending === approval.id ? "Rejecting..." : "Reject"}
                  </Button>
                </div>
              </CardContent>
            )}
          </Card>
        ))}
      </div>
    </div>
  );
}

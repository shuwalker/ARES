import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Bell,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  Clock,
  Inbox,
  LoaderCircle,
  Mail,
  MailOpen,
  MessageCircle,
  RefreshCw,
  Search,
  ShieldCheck,
  XCircle,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { aresApi } from "@/shared/ares-api";
import type { ApprovalItem, ClarifyItem, EmailItem } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";

// ── Helpers ───────────────────────────────────────────────────────────

type ApprovalStatus = ApprovalItem["status"];

function formatRelative(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  const diff = Date.now() - date.getTime();
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function statusIcon(status: ApprovalStatus) {
  if (status === "approved") return <CheckCircle2 className="size-4 text-green-500" />;
  if (status === "rejected") return <XCircle className="size-4 text-red-500" />;
  if (status === "revision_requested") return <Clock className="size-4 text-amber-500" />;
  return <Clock className="size-4 text-yellow-500" />;
}

function typeBadgeColor(type: string): string {
  switch (type) {
    case "tool_use": return "bg-blue-500/20 text-blue-400 border-blue-500/30";
    case "execution": return "bg-purple-500/20 text-purple-400 border-purple-500/30";
    case "network": return "bg-orange-500/20 text-orange-400 border-orange-500/30";
    case "clarification": return "bg-cyan-500/20 text-cyan-400 border-cyan-500/30";
    default: return "bg-muted text-muted-foreground";
  }
}

// ── Inbox tab type ────────────────────────────────────────────────────

type InboxTab = "approvals" | "clarifications" | "notifications";

// ── Main component ────────────────────────────────────────────────────

export default function InboxPage() {
  // ── Approvals state ──
  const [approvals, setApprovals] = useState<ApprovalItem[]>([]);
  const [approvalsLoading, setApprovalsLoading] = useState(true);
  const [approvalsError, setApprovalsError] = useState<string | null>(null);
  const [actionPending, setActionPending] = useState<string | null>(null);

  // ── Clarifications state ──
  const [clarifications, setClarifications] = useState<ClarifyItem[]>([]);
  const [clarifyLoading, setClarifyLoading] = useState(true);
  const [clarifyError, setClarifyError] = useState<string | null>(null);

  // ── Notifications (email) state ──
  const [notifications, setNotifications] = useState<EmailItem[]>([]);
  const [notifLoading, setNotifLoading] = useState(true);
  const [notifError, setNotifError] = useState<string | null>(null);
  const [notificationsLoaded, setNotificationsLoaded] = useState(false);

  // ── UI state ──
  const [activeTab, setActiveTab] = useState<InboxTab>("approvals");
  const [searchQuery, setSearchQuery] = useState("");
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [clarifyInput, setClarifyInput] = useState<Record<string, string>>({});
  const [clarifySubmitting, setClarifySubmitting] = useState<string | null>(null);

  // ── Data loading ──

  const loadApprovals = useCallback(async () => {
    setApprovalsLoading(true);
    setApprovalsError(null);
    try {
      const data = await aresApi.approvalPending();
      const items = data.approvals ?? [];
      setApprovals(items);
    } catch (error) {
      setApprovals([]);
      setApprovalsError(readableError(error, "Approvals could not be loaded."));
    } finally {
      setApprovalsLoading(false);
    }
  }, []);

  const loadClarifications = useCallback(async () => {
    setClarifyLoading(true);
    setClarifyError(null);
    try {
      const data = await aresApi.clarifyPending();
      setClarifications(data.clarifications ?? []);
    } catch (error) {
      setClarifications([]);
      setClarifyError(readableError(error, "Clarifications could not be loaded."));
    } finally {
      setClarifyLoading(false);
    }
  }, []);

  const loadNotifications = useCallback(async () => {
    setNotifLoading(true);
    setNotifError(null);
    try {
      const data = await aresApi.emailAll();
      setNotifications(data.emails ?? []);
    } catch (error) {
      setNotifications([]);
      setNotifError(readableError(error, "Notifications are unavailable. Connect a supported email source to use this tab."));
    } finally {
      setNotifLoading(false);
      setNotificationsLoaded(true);
    }
  }, []);

  useEffect(() => {
    void loadApprovals();
    void loadClarifications();
  }, [loadApprovals, loadClarifications]);

  useEffect(() => {
    if (activeTab === "notifications" && !notificationsLoaded) {
      void loadNotifications();
    }
  }, [activeTab, loadNotifications, notificationsLoaded]);

  // ── Approval actions ──

  async function handleApprovalAction(
    id: string,
    action: "approve" | "reject",
    note?: string,
  ) {
    setActionPending(id);
    try {
      const approval = approvals.find((item) => item.id === id);
      if (!approval) throw new Error("Approval is no longer available.");
      await aresApi.approvalRespond(approval.session_id, id, action);
      setApprovals((prev) => prev.filter((item) => item.id !== id));
    } catch (error) {
      setApprovalsError(readableError(error, "The approval response could not be submitted."));
    } finally {
      setActionPending(null);
    }
  }

  async function handleClarifyRespond(id: string) {
    const response = clarifyInput[id]?.trim();
    if (!response) return;
    setClarifySubmitting(id);
    try {
      const item = clarifications.find((candidate) => candidate.id === id);
      if (!item?.session_id) throw new Error("Clarification session is unavailable.");
      await aresApi.clarifyRespond(item.session_id, id, response);
      setClarifications((prev) => prev.filter((candidate) => candidate.id !== id));
      setClarifyInput((prev) => { const next = { ...prev }; delete next[id]; return next; });
    } catch (error) {
      setApprovalsError(readableError(error, "The clarification response could not be submitted."));
    } finally {
      setClarifySubmitting(null);
    }
  }

  // ── Derived data ──

  const pendingCount = approvals.length;

  const unreadNotifCount = notifications.filter((n) => !n.read).length;

  const filteredApprovals = useMemo(() => {
    let items = approvals;
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      items = items.filter(
        (a) =>
          a.subject.toLowerCase().includes(q) ||
          a.detail.toLowerCase().includes(q) ||
          a.type.toLowerCase().includes(q) ||
          a.requested_by.toLowerCase().includes(q),
      );
    }
    return [...items].sort(
      (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
    );
  }, [approvals, searchQuery]);

  const filteredClarifications = useMemo(() => {
    if (!searchQuery.trim()) return clarifications;
    const q = searchQuery.toLowerCase();
    return clarifications.filter(
      (c) =>
        c.question.toLowerCase().includes(q) ||
        c.context.toLowerCase().includes(q),
    );
  }, [clarifications, searchQuery]);

  const filteredNotifications = useMemo(() => {
    if (!searchQuery.trim()) return notifications;
    const q = searchQuery.toLowerCase();
    return notifications.filter(
      (n) =>
        n.subject.toLowerCase().includes(q) ||
        n.from.toLowerCase().includes(q) ||
        n.snippet.toLowerCase().includes(q),
    );
  }, [notifications, searchQuery]);

  // ── Render ──

  return (
    <div className="page-stack">
      <PageHeader
        title="Inbox"
        description="Approvals, decisions, and notifications requiring your attention."
        action={
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              void loadApprovals();
              void loadClarifications();
              void loadNotifications();
            }}
          >
            <RefreshCw className="size-4" />
            Refresh
          </Button>
        }
      />

      {/* ── Tab bar + search/filter ── */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as InboxTab)}>
          <TabsList>
            <TabsTrigger value="approvals" className="gap-1.5">
              <ShieldCheck className="size-3.5" />
              Approvals
              {pendingCount > 0 && (
                <Badge variant="secondary" className="ml-1 bg-yellow-500/20 text-yellow-600 dark:text-yellow-400">
                  {pendingCount}
                </Badge>
              )}
            </TabsTrigger>
            <TabsTrigger value="clarifications" className="gap-1.5">
              <MessageCircle className="size-3.5" />
              Clarifications
              {clarifications.length > 0 && (
                <Badge variant="secondary" className="ml-1 bg-cyan-500/20 text-cyan-600 dark:text-cyan-400">
                  {clarifications.length}
                </Badge>
              )}
            </TabsTrigger>
            <TabsTrigger value="notifications" className="gap-1.5">
              <Bell className="size-3.5" />
              Notifications
              {unreadNotifCount > 0 && (
                <Badge variant="secondary" className="ml-1 bg-blue-500/20 text-blue-600 dark:text-blue-400">
                  {unreadNotifCount}
                </Badge>
              )}
            </TabsTrigger>
          </TabsList>
        </Tabs>

        <div className="flex items-center gap-2">
          <div className="relative">
            <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
            <Input
              placeholder="Search inbox…"
              className="w-[200px] pl-9"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
        </div>
      </div>

      {/* ── Approvals tab ── */}
      {activeTab === "approvals" && (
        approvalsLoading ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
            <p className="text-sm text-muted-foreground">Loading approvals…</p>
          </div>
        ) : approvalsError ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
              <XCircle className="size-6 text-destructive" />
            </div>
            <p className="text-sm text-destructive">{approvalsError}</p>
            <Button variant="outline" size="sm" className="mt-4" onClick={() => void loadApprovals()}>
              <RefreshCw className="size-4" />
              Retry
            </Button>
          </div>
        ) : filteredApprovals.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
              <Inbox className="size-6 text-muted-foreground/50" />
            </div>
            <p className="text-sm text-muted-foreground">
              {searchQuery
                ? "No approvals match your filters."
                : "No pending approvals. You're all caught up!"}
            </p>
          </div>
        ) : (
          <div className="grid gap-3">
            {filteredApprovals.map((approval) => {
              const isExpanded = expandedId === approval.id;
              return (
                <Card key={approval.id}>
                  <CardHeader
                    className="cursor-pointer select-none"
                    onClick={() => setExpandedId(isExpanded ? null : approval.id)}
                  >
                    <div className="flex items-start justify-between gap-4">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <Badge
                            variant="outline"
                            className={`text-xs uppercase tracking-wider ${typeBadgeColor(approval.type)}`}
                          >
                            {approval.type.replace(/_/g, " ")}
                          </Badge>
                          {approval.requested_by && (
                            <span className="text-xs text-muted-foreground">
                              from {approval.requested_by}
                            </span>
                          )}
                          <span className="text-xs text-muted-foreground">
                            {formatRelative(approval.created_at)}
                          </span>
                        </div>
                        <CardTitle className="mt-2 text-base">{approval.subject}</CardTitle>
                      </div>
                      <div className="flex shrink-0 items-center gap-2">
                        <div className="inline-flex items-center gap-1.5 rounded-full border bg-background px-2.5 py-1 text-xs text-muted-foreground">
                          {statusIcon(approval.status)}
                          <span className="capitalize">{approval.status.replace(/_/g, " ")}</span>
                        </div>
                        {isExpanded ? (
                          <ChevronUp className="size-4 text-muted-foreground" />
                        ) : (
                          <ChevronDown className="size-4 text-muted-foreground" />
                        )}
                      </div>
                    </div>
                  </CardHeader>

                  {isExpanded && (
                    <CardContent className="border-t pt-4">
                      <CardDescription className="mb-4 whitespace-pre-wrap text-sm">
                        {approval.detail}
                      </CardDescription>

                      {Object.keys(approval.payload).length > 0 && (
                        <div className="mb-4 rounded-md bg-muted/50 p-3">
                          <p className="mb-1 text-xs font-medium text-muted-foreground">Payload</p>
                          <pre className="overflow-x-auto text-xs text-foreground">
                            {JSON.stringify(approval.payload, null, 2)}
                          </pre>
                        </div>
                      )}

                      <div className="flex items-center gap-2">
                          <Button
                            size="sm"
                            className="bg-green-700 text-white hover:bg-green-600"
                            onClick={(e) => {
                              e.stopPropagation();
                              void handleApprovalAction(approval.id, "approve");
                            }}
                            disabled={actionPending === approval.id}
                          >
                            {actionPending === approval.id ? (
                              <LoaderCircle className="mr-1.5 size-4 animate-spin" />
                            ) : (
                              <CheckCircle2 className="mr-1.5 size-4" />
                            )}
                            Approve
                          </Button>
                          <Button
                            variant="destructive"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              void handleApprovalAction(approval.id, "reject");
                            }}
                            disabled={actionPending === approval.id}
                          >
                            {actionPending === approval.id ? (
                              <LoaderCircle className="mr-1.5 size-4 animate-spin" />
                            ) : (
                              <XCircle className="mr-1.5 size-4" />
                            )}
                            Reject
                          </Button>
                        </div>
                    </CardContent>
                  )}
                </Card>
              );
            })}
          </div>
        )
      )}

      {/* ── Clarifications tab ── */}
      {activeTab === "clarifications" && (
        clarifyLoading ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
            <p className="text-sm text-muted-foreground">Loading clarifications…</p>
          </div>
        ) : clarifyError ? (
          <div className="grid justify-items-center gap-3 py-16 text-center"><XCircle className="size-7 text-destructive" /><p className="text-sm text-destructive">{clarifyError}</p><Button variant="outline" size="sm" onClick={() => void loadClarifications()}><RefreshCw />Retry</Button></div>
        ) : filteredClarifications.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
              <MessageCircle className="size-6 text-muted-foreground/50" />
            </div>
            <p className="text-sm text-muted-foreground">
              {searchQuery ? "No clarifications match your search." : "No pending clarifications."}
            </p>
          </div>
        ) : (
          <div className="grid gap-3">
            {filteredClarifications.map((item) => (
              <Card key={item.id}>
                <CardHeader>
                  <div className="flex items-start justify-between gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <Badge variant="outline" className="text-xs uppercase tracking-wider bg-cyan-500/20 text-cyan-400 border-cyan-500/30">
                          Clarification
                        </Badge>
                        <span className="text-xs text-muted-foreground">
                          {formatRelative(item.created_at)}
                        </span>
                      </div>
                      <CardTitle className="mt-2 text-base">{item.question}</CardTitle>
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="border-t pt-4">
                  {item.context && (
                    <p className="mb-3 text-sm text-muted-foreground">{item.context}</p>
                  )}
                  <div className="flex items-center gap-2">
                    <Input
                      placeholder="Type your response…"
                      className="flex-1"
                      value={clarifyInput[item.id] ?? ""}
                      onChange={(e) =>
                        setClarifyInput((prev) => ({ ...prev, [item.id]: e.target.value }))
                      }
                      onKeyDown={(e) => {
                        if (e.key === "Enter" && clarifyInput[item.id]?.trim()) {
                          e.preventDefault();
                          void handleClarifyRespond(item.id);
                        }
                      }}
                    />
                    <Button
                      size="sm"
                      disabled={!clarifyInput[item.id]?.trim() || clarifySubmitting === item.id}
                      onClick={() => void handleClarifyRespond(item.id)}
                    >
                      {clarifySubmitting === item.id ? (
                        <LoaderCircle className="mr-1.5 size-4 animate-spin" />
                      ) : (
                        <MessageCircle className="mr-1.5 size-4" />
                      )}
                      Reply
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )
      )}

      {/* ── Notifications tab ── */}
      {activeTab === "notifications" && (
        notifLoading ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <LoaderCircle className="mb-4 size-8 animate-spin text-muted-foreground/40" />
            <p className="text-sm text-muted-foreground">Loading notifications…</p>
          </div>
        ) : notifError ? (
          <div className="grid justify-items-center gap-3 py-16 text-center"><MailOpen className="size-7 text-muted-foreground" /><p className="max-w-lg text-sm text-muted-foreground">{notifError}</p><Button variant="outline" size="sm" onClick={() => void loadNotifications()}><RefreshCw />Retry</Button></div>
        ) : filteredNotifications.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="mb-4 grid size-12 place-items-center rounded-lg bg-muted">
              <Bell className="size-6 text-muted-foreground/50" />
            </div>
            <p className="text-sm text-muted-foreground">
              {searchQuery ? "No notifications match your search." : "No notifications yet."}
            </p>
          </div>
        ) : (
          <div className="grid gap-3">
            {filteredNotifications.map((notif) => (
              <Card key={notif.id} className={notif.read ? "opacity-60" : ""}>
                <CardContent className="flex items-start gap-3 py-4">
                  <div className="mt-0.5 shrink-0">
                    {notif.read ? (
                      <MailOpen className="size-5 text-muted-foreground" />
                    ) : (
                      <Mail className="size-5 text-blue-400" />
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium">{notif.subject}</span>
                      {!notif.read && (
                        <Badge variant="secondary" className="bg-blue-500/20 text-blue-400">
                          New
                        </Badge>
                      )}
                    </div>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      From {notif.from} · {formatRelative(notif.date)}
                    </p>
                    <p className="mt-1 text-sm text-muted-foreground line-clamp-2">{notif.snippet}</p>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )
      )}
    </div>
  );
}

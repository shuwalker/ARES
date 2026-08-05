import {
  ArrowRight,
  CalendarClock,
  ClipboardList,
  Heart,
  Inbox,
  Library,
  MessageCircle,
  Target,
  UserCheck,
} from "lucide-react";
import { Link } from "react-router-dom";

import { SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useAres } from "@/shared/ares-context";
import { useLocalProfile } from "@/shared/local-profile";

/**
 * Life environment — daily guidance, personal context, and administration.
 */
export function CompanionPage() {
  const { profile } = useLocalProfile();
  const { snapshot } = useAres();
  const companionName = profile.assistantName?.trim() || "Jaeger AI";
  const displayName = profile.displayName?.trim() || "operator";
  const connected = snapshot.connection === "available";
  // Only connections that are actually selected or verified-available count.
  // Never fall back to the backend catalog size — that reports adapter
  // *types*, not live workers, and reads as fabricated status on a fresh box.
  const workerCount = snapshot.connections.filter((c) => c.selected || c.available).length;

  const quickActionMatrix = [
    {
      to: "/today",
      label: "Now",
      subtitle: "Today’s commitments, plan, and active work",
      icon: CalendarClock,
      badge: "Today",
      color: "border-primary/40 bg-primary/10 text-primary",
    },
    {
      to: "/self",
      label: "Journal & Areas",
      subtitle: "Personal context and ongoing areas of life",
      icon: Heart,
      badge: "Personal",
      color: "border-blue-500/30 bg-blue-500/10 text-blue-400",
    },
    {
      to: "/goals",
      label: "Goals",
      subtitle: "Long-term outcomes and direction",
      icon: Target,
      badge: "Focus",
      color: "border-amber-500/30 bg-amber-500/10 text-amber-400",
    },
    {
      to: "/cases",
      label: "Life Admin",
      subtitle: "Important personal cases, deadlines, and paperwork",
      icon: ClipboardList,
      badge: "Admin",
      color: "border-emerald-500/30 bg-emerald-500/10 text-emerald-400",
    },
    {
      to: "/schedules",
      label: "Automations",
      subtitle: "Recurring reminders and background assistance",
      icon: CalendarClock,
      badge: "Automate",
      color: "border-purple-500/30 bg-purple-500/10 text-purple-400",
    },
    {
      to: "/inbox",
      label: "Approvals",
      subtitle: "Pending worker decisions and notifications",
      icon: Inbox,
      badge: "Decisions",
      color: "border-rose-500/30 bg-rose-500/10 text-rose-400",
    },
    {
      to: "/chat",
      label: "Open Agent",
      subtitle: "Talk through anything in your life",
      icon: MessageCircle,
      badge: "Agent",
      color: "border-cyan-500/30 bg-cyan-500/10 text-cyan-400",
    },
    {
      to: "/library",
      label: "Library",
      subtitle: "Find documents, research, and retained knowledge",
      icon: Library,
      badge: "Memory",
      color: "border-zinc-500/30 bg-zinc-500/10 text-zinc-300",
    },
  ];

  return (
    <SurfaceShell
      title="Life"
      description={`${companionName} helps ${displayName} manage today, personal context, goals, and important obligations.`}
      action={
        <Button asChild variant="default">
          <Link to="/today">
            Open Now
            <ArrowRight className="ml-1.5 size-4" />
          </Link>
        </Button>
      }
    >
      {/* ── Top Quick-Access Action Matrix ────────────────────────────────── */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Life at a glance
          </h2>
          <span className="text-[11px] text-muted-foreground">
            Personal guidance and context
          </span>
        </div>

        <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2 lg:grid-cols-4">
          {quickActionMatrix.map((item) => {
            const Icon = item.icon;
            return (
              <Link
                key={item.to}
                to={item.to}
                className="group relative flex flex-col justify-between rounded-xl border border-border/80 bg-card/70 p-3.5 transition-all hover:border-primary/50 hover:bg-card hover:shadow-lg"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className={`rounded-lg border p-2 ${item.color}`}>
                    <Icon className="size-4" />
                  </div>
                  <span className="rounded-md border border-border/60 bg-background/50 px-2 py-0.5 text-[10px] font-mono font-medium text-foreground/70">
                    {item.badge}
                  </span>
                </div>
                <div className="mt-3">
                  <div className="font-medium text-sm text-foreground transition-colors group-hover:text-primary">
                    {item.label}
                  </div>
                  <div className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">
                    {item.subtitle}
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      </div>

      {/* ── Jaeger AI SI Status & Relationship Card ──────────────────────── */}
      <Card className="border-border/80 bg-card/60">
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center justify-between text-base text-foreground font-semibold">
            <div className="flex items-center gap-3">
              {profile.assistantAvatar ? (
                <img
                  src={profile.assistantAvatar}
                  alt={companionName}
                  className="size-10 rounded-full border border-primary/50 object-cover shadow-md shadow-primary/20"
                />
              ) : (
                <div className="grid size-10 place-items-center rounded-full border border-primary/40 bg-primary/10 text-primary shadow-md shadow-primary/20 font-bold text-sm">
                  {companionName.slice(0, 2).toUpperCase()}
                </div>
              )}
              <div>
                <span>{companionName} Status</span>
                <p className="text-xs font-normal text-muted-foreground">Persistent SI Identity</p>
              </div>
            </div>
            <Button asChild size="sm" variant="outline" className="h-7 text-xs">
              <Link to="/activation">
                <UserCheck className="mr-1.5 size-3.5" />
                Character & Avatar Wizard
              </Link>
            </Button>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3 text-sm text-foreground/90 leading-relaxed">
          <p>
            Hello, <span className="font-semibold text-foreground">{displayName}</span>. You are connected to{" "}
            <span className="font-semibold text-foreground">{companionName}</span> — your persistent Synthetic Intelligence.
            Workers execute tasks under your supervision; {companionName} maintains relationship continuity and intent routing.
          </p>
          <div className="flex flex-wrap gap-2 text-xs">
            <span className="rounded-full border border-border bg-background/60 px-2.5 py-1 text-foreground/80 font-medium">
              Link: {connected ? "online" : snapshot.connection}
            </span>
            <span className="rounded-full border border-border bg-background/60 px-2.5 py-1 text-foreground/80 font-medium">
              Workers active: {workerCount || "—"}
            </span>
            <span className="rounded-full border border-border bg-background/60 px-2.5 py-1 text-foreground/80 font-medium">
              Autonomy mode: {profile.autonomy}
            </span>
            <span className="rounded-full border border-border bg-background/60 px-2.5 py-1 text-foreground/80 font-medium">
              Persona: {profile.character || "grounded"}
            </span>
          </div>
        </CardContent>
      </Card>

      <SurfaceNote>
        Projects (`/chat`) group your discussions with the agent by subject. The Companion surface (`/companion`) provides high-level intent routing, memory retrieval, and approval management.
      </SurfaceNote>
    </SurfaceShell>
  );
}

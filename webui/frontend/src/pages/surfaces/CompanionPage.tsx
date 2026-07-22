import { ArrowRight, Heart, Library, MessageCircle, Shield, Sparkles, Wrench } from "lucide-react";
import { Link } from "react-router-dom";

import { SurfaceLinkGrid, SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useAres } from "@/shared/ares-context";
import { useLocalProfile } from "@/shared/local-profile";

/**
 * Companion surface — the SI front door.
 * Not a model picker: identity, continuity, intent, and routing above workers.
 */
export function CompanionPage() {
  const { profile } = useLocalProfile();
  const { snapshot } = useAres();
  const companionName = profile.assistantName?.trim() || "Companion";
  const displayName = profile.displayName?.trim() || "friend";
  const connected = snapshot.connection === "available";
  const workerCount = snapshot.connections.filter((c) => c.selected || c.available).length
    || snapshot.backends.length;

  return (
    <SurfaceShell
      title={companionName}
      description="Your Synthetic Intelligence — one continuous identity above workers. Speak intent; it routes the work."
      action={
        <Button asChild>
          <Link to="/chat">
            Open Chat console
            <ArrowRight className="ml-1.5 size-4" />
          </Link>
        </Button>
      }
    >
      <Card className="border-primary/20 bg-primary/5">
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <Sparkles className="size-4 text-primary" />
            Relationship
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3 text-sm text-muted-foreground">
          <p>
            Hello, <span className="font-medium text-foreground">{displayName}</span>. You talk to{" "}
            <span className="font-medium text-foreground">{companionName}</span> — not to a rotating
            list of brands. Workers execute; the Companion stays.
          </p>
          <div className="flex flex-wrap gap-2 text-xs">
            <span className="rounded-full border border-border px-2.5 py-1">
              Link: {connected ? "online" : snapshot.connection}
            </span>
            <span className="rounded-full border border-border px-2.5 py-1">
              Workers known: {workerCount || "—"}
            </span>
            <span className="rounded-full border border-border px-2.5 py-1">
              Autonomy: {profile.autonomy}
            </span>
          </div>
        </CardContent>
      </Card>

      <SurfaceNote>
        Chat is the transparent backend console. Companion is the SI experience — intent, memory
        retrieval with privacy tiers, delegation, and approvals. Long-term, this surface becomes the
        default home; Chat moves to advanced mode.
      </SurfaceNote>

      <SurfaceLinkGrid
        links={[
          {
            to: "/chat",
            label: "Chat (worker console)",
            description: "Talk directly to Hermes, JROS, Claude, local models — tools visible.",
            icon: MessageCircle,
          },
          {
            to: "/today",
            label: "Today",
            description: "What needs you, what is in flight, what already moved.",
            icon: Sparkles,
          },
          {
            to: "/self",
            label: "Self",
            description: "Private journal, mind, body, life — knowledge about you.",
            icon: Heart,
          },
          {
            to: "/workshop",
            label: "Workshop",
            description: "Files, code, terminal, CAD — what you are building.",
            icon: Wrench,
          },
          {
            to: "/library",
            label: "Library",
            description: "Your Alexandria — books, notes, study, preserved knowledge.",
            icon: Library,
          },
          {
            to: "/system",
            label: "System",
            description: "Local infrastructure, workers, permissions, memory indexing.",
            icon: Shield,
          },
        ]}
      />
    </SurfaceShell>
  );
}

import {
  Activity,
  Cable,
  Cpu,
  Gauge,
  Key,
  Server,
  Shield,
  Sliders,
  Smartphone,
  Webhook,
  CalendarClock,
  HardDrive,
} from "lucide-react";

import { SurfaceLinkGrid, SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useAres } from "@/shared/ares-context";

/**
 * System surface — local self-hosted infrastructure (UI name for Foundation).
 * Memory infrastructure lives here; knowledge content lives in Library.
 */
export function SystemPage() {
  const { snapshot } = useAres();

  return (
    <SurfaceShell
      title="System"
      description="Your box: workers, models, devices, network, storage, permissions, memory infrastructure, and health."
    >
      <SurfaceNote>
        This is not where you read books or write journals. Configure how the digital world works —
        self-hoster ground under the Companion.
      </SurfaceNote>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <HardDrive className="size-4 text-primary" />
            Box status
          </CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2 text-xs">
          <span className="rounded-full border border-border px-2.5 py-1">
            API: {snapshot.connection}
          </span>
          <span className="rounded-full border border-border px-2.5 py-1">
            Sessions: {snapshot.sessions.length}
          </span>
          <span className="rounded-full border border-border px-2.5 py-1">
            Backends: {snapshot.backends.length}
          </span>
          <span className="rounded-full border border-border px-2.5 py-1">
            Agent: {snapshot.agentHealth.availability}
          </span>
        </CardContent>
      </Card>

      <SurfaceLinkGrid
        links={[
          {
            to: "/connections",
            label: "Connections",
            description: "Providers and channels the Companion can use.",
            icon: Cable,
          },
          {
            to: "/agents",
            label: "Workers",
            description: "Agent frameworks and worker health.",
            icon: Cpu,
          },
          {
            to: "/mcp",
            label: "MCP servers",
            description: "Tool servers and capabilities.",
            icon: Server,
          },
          {
            to: "/config",
            label: "Config",
            description: "Runtime and product configuration.",
            icon: Sliders,
          },
          {
            to: "/activity",
            label: "Activity",
            description: "What ran — honest execution visibility.",
            icon: Activity,
          },
          {
            to: "/analytics",
            label: "Analytics",
            description: "Usage patterns and trends.",
            icon: Gauge,
          },
          {
            to: "/usage",
            label: "Usage & cost",
            description: "Tokens, cost, provider spend.",
            icon: Gauge,
          },
          {
            to: "/pairing",
            label: "Pairing",
            description: "Devices and remote reachability.",
            icon: Smartphone,
          },
          {
            to: "/webhooks",
            label: "Webhooks",
            description: "Inbound automation hooks.",
            icon: Webhook,
          },
          {
            to: "/secrets",
            label: "Secrets",
            description: "Credentials vault for the box.",
            icon: Key,
          },
          {
            to: "/schedules",
            label: "Schedules",
            description: "Cron and recurring work on your metal.",
            icon: CalendarClock,
          },
          {
            to: "/settings",
            label: "Settings & profile",
            description: "Local profile, Companion name, privacy posture.",
            icon: Shield,
          },
        ]}
      />
    </SurfaceShell>
  );
}

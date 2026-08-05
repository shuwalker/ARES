import {
  Activity,
  Cable,
  Cpu,
  Gauge,
  GraduationCap,
  Key,
  Server,
  Shield,
  Sliders,
  Smartphone,
  Webhook,
  CalendarClock,
  HardDrive,
  Sparkles,
} from "lucide-react";
import type { ReactNode } from "react";

import { SurfaceLinkGrid, SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useAres } from "@/shared/ares-context";

function ControlGroup({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: ReactNode;
}) {
  return (
    <section className="space-y-3">
      <div>
        <h2 className="text-sm font-semibold text-foreground">{title}</h2>
        <p className="mt-1 text-xs text-foreground/70">{description}</p>
      </div>
      {children}
    </section>
  );
}

export function SystemPage() {
  const { snapshot } = useAres();

  return (
    <SurfaceShell
      title="Control Center"
      description="Configure the intelligence, access, safety, and health behind your ARES experience."
    >
      <SurfaceNote>
        Your everyday work stays in Agent, Engineering, Studio, Life, and Library.
        Control Center is where you decide what ARES can use and what it may do.
      </SurfaceNote>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <HardDrive className="size-4 text-primary" />
            System status
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

      <ControlGroup
        title="Intelligence"
        description="Choose the workers, models, tools, and reusable capabilities ARES may call."
      >
        <SurfaceLinkGrid links={[
          { to: "/agents", label: "Workers", description: "Agent runtimes, capabilities, and availability.", icon: Cpu },
          { to: "/connections", label: "Connections", description: "AI providers, services, and communication channels.", icon: Cable },
          { to: "/mcp", label: "MCP servers", description: "External tool servers available to workers.", icon: Server },
          { to: "/skills", label: "Skills", description: "Reusable workflows ARES can assign to workers.", icon: GraduationCap },
          { to: "/hatchery", label: "Local models", description: "Discover and manage intelligence running on this machine.", icon: Sparkles },
          { to: "/skills-studio", label: "Skill Studio", description: "Create and refine reusable worker capabilities.", icon: GraduationCap },
        ]} />
      </ControlGroup>

      <ControlGroup
        title="Access and safety"
        description="Control memory, privacy, devices, credentials, integrations, and autonomous actions."
      >
        <SurfaceLinkGrid links={[
          { to: "/memory-privacy", label: "Memory & Privacy", description: "Context store, external history, retention, and redaction.", icon: Shield },
          { to: "/permissions-autonomy", label: "Permissions & Autonomy", description: "Observe-only, ask-before-acting, delegated, and device reach.", icon: Shield },
          { to: "/pairing", label: "Devices", description: "Pair devices and manage remote reachability.", icon: Smartphone },
          { to: "/secrets", label: "Secrets", description: "Credentials used by approved connections and workers.", icon: Key },
          { to: "/webhooks", label: "Webhooks", description: "Allow trusted external systems to trigger ARES.", icon: Webhook },
          { to: "/schedules", label: "Automations", description: "Recurring and scheduled work performed on your behalf.", icon: CalendarClock },
          { to: "/config", label: "Advanced settings", description: "Technical runtime and product configuration.", icon: Sliders },
        ]} />
      </ControlGroup>

      <ControlGroup
        title="Observe"
        description="See what ran, whether it worked, and what resources it consumed."
      >
        <SurfaceLinkGrid links={[
          { to: "/activity", label: "Activity", description: "Executions, tool use, and current worker state.", icon: Activity },
          { to: "/analytics", label: "Analytics", description: "Reliability and usage patterns over time.", icon: Gauge },
          { to: "/usage", label: "Usage & cost", description: "Tokens, model usage, and provider spending.", icon: Gauge },
        ]} />
      </ControlGroup>
    </SurfaceShell>
  );
}

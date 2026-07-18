import { Cable, CheckCircle2, CircleOff, Network, Server, Wrench } from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useAres } from "@/shared/ares-context";
import type { CapabilityStatus } from "@/shared/contracts";

export function ConnectionsPage() {
  const { snapshot } = useAres();
  const fixedCapabilities: CapabilityStatus[] = [
    { id: "profile", label: "Local Profile", availability: "available", detail: "Identity settings remain available without a model connection." },
    { id: "api", label: "ARES API", availability: snapshot.connection === "available" ? "available" : snapshot.connection === "limited" ? "limited" : "unavailable", detail: snapshot.error || "The controller API is responding." },
  ];
  const capabilities: CapabilityStatus[] = [
    ...fixedCapabilities,
    ...snapshot.connections.map((connection) => ({
      id: `connection:${connection.id}`,
      label: `${connection.name}${connection.selected ? " · selected" : ""}`,
      availability: connection.state === "connected" ? "available" as const : connection.state === "needs_attention" ? "limited" as const : "unavailable" as const,
      detail: connection.detail,
    })),
  ];
  return (
    <div className="page-stack">
      <PageHeader title="Connections" description="Capability status is reported independently for the controller, assistant runtime, and tools." />
      <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-4">
        {capabilities.map((item) => {
          const available = item.availability === "available";
          const connection = item.id.startsWith("connection:") ? snapshot.connections.find((value) => `connection:${value.id}` === item.id) : undefined;
          const Icon = item.id === "profile" ? Network : item.id === "api" ? Server : connection?.kind === "tool" ? Wrench : Cable;
          return <Card key={item.id}><CardHeader><div className="flex items-start justify-between gap-3"><div className="grid size-9 place-items-center rounded-md bg-muted"><Icon className="size-4" /></div><Badge variant="outline" className={available ? "text-status-available" : item.availability === "limited" ? "text-status-limited" : "text-status-unavailable"}>{available ? <CheckCircle2 /> : <CircleOff />}{item.availability}</Badge></div><CardTitle className="mt-2">{item.label}</CardTitle><CardDescription>{item.detail}</CardDescription></CardHeader></Card>;
        })}
      </div>
    </div>
  );
}

import { LoaderCircle, RefreshCw, Server } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { NativeSystemStatus } from "@/shared/system-settings-contract";

export function LocalRuntimeCard({
  system,
  busy,
  restartServer,
}: {
  system: NativeSystemStatus;
  busy: string;
  restartServer: () => Promise<void>;
}) {
  const owned = system.controller.managedByMacApp && system.nativeApp.connected;
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Server className="size-4" /> Local ARES controller
            </CardTitle>
            <CardDescription>
              http://{system.controller.host}:{system.controller.port} · PID {system.controller.pid ?? "—"}
            </CardDescription>
          </div>
          <Badge variant={owned ? "secondary" : "destructive"}>
            {owned ? "Managed by Mac app" : "Unmanaged process"}
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="grid gap-3">
        <p className="text-sm text-muted-foreground">
          {owned
            ? "The native ARES app created this controller and owns its lifecycle."
            : "This controller was not proven to be owned by the connected ARES Mac app. Native lifecycle actions are disabled."}
        </p>
        <div className="flex flex-wrap gap-2">
          <Button
            type="button"
            variant="outline"
            disabled={!owned || !system.capabilities.serverRestart || busy === "restart_server"}
            onClick={() => void restartServer()}
          >
            {busy === "restart_server" ? <LoaderCircle className="animate-spin" /> : <RefreshCw />}
            Restart controller
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          Start and stop remain native-app actions because the Web UI cannot start the server that serves this page.
        </p>
      </CardContent>
    </Card>
  );
}

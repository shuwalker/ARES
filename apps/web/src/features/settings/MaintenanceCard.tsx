import { RefreshCw, SlidersHorizontal } from "lucide-react";
import { Link } from "react-router-dom";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export function MaintenanceCard({
  webVersion,
  agentVersion,
  updateVersion,
  reload,
}: {
  webVersion: string;
  agentVersion: string;
  updateVersion: string;
  reload: () => Promise<void>;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Maintenance</CardTitle>
        <CardDescription>Versions, diagnostics, and advanced application preferences.</CardDescription>
      </CardHeader>
      <CardContent className="grid gap-4">
        <div className="flex flex-wrap gap-2">
          <Badge variant="outline">Web: {webVersion}</Badge>
          <Badge variant="outline">Controller: {agentVersion}</Badge>
          {updateVersion ? <Badge variant="secondary">{updateVersion}</Badge> : null}
        </div>
        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="outline" onClick={() => void reload()}><RefreshCw /> Reload settings</Button>
          <Button asChild variant="outline"><Link to="/config"><SlidersHorizontal /> Advanced settings</Link></Button>
        </div>
      </CardContent>
    </Card>
  );
}

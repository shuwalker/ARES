import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

import { Field, ToggleField } from "./fields";

export function UpdatesCard({
  checkForUpdates,
  updateChannel,
  ignoreAgentUpdates,
  whatsNewSummary,
  setBool,
  setStr,
}: {
  checkForUpdates: boolean;
  updateChannel: string;
  ignoreAgentUpdates: boolean;
  whatsNewSummary: boolean;
  setBool: (key: string, value: boolean) => void;
  setStr: (key: string, value: string | number) => void;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Updates</CardTitle>
        <CardDescription>Application and controller update preferences.</CardDescription>
      </CardHeader>
      <CardContent className="grid gap-3">
        <ToggleField id="check_for_updates" label="Check for updates" checked={checkForUpdates} onChange={(value) => setBool("check_for_updates", value)} />
        <Field label="Update channel">
          <Select value={updateChannel} onValueChange={(value) => setStr("update_channel", value)}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="stable">Stable</SelectItem>
              <SelectItem value="experimental">Experimental</SelectItem>
            </SelectContent>
          </Select>
        </Field>
        <ToggleField id="ignore_agent_updates" label="Ignore worker update notices" checked={ignoreAgentUpdates} onChange={(value) => setBool("ignore_agent_updates", value)} />
        <ToggleField id="whats_new_summary_enabled" label="Summarize What’s New with AI" checked={whatsNewSummary} onChange={(value) => setBool("whats_new_summary_enabled", value)} />
      </CardContent>
    </Card>
  );
}

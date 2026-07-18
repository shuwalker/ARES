import { Check, Save } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { ToggleSwitch } from "@/components/ui/toggle-switch";

import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { LocalProfile } from "@/shared/contracts";
import { useLocalProfile } from "@/shared/local-profile";
import { useAres } from "@/shared/ares-context";
import { readableError } from "@/shared/api-client";

export function SettingsPage() {
  const { profile, saveProfile } = useLocalProfile();
  const { snapshot, saveAssistantName } = useAres();
  const [draft, setDraft] = useState<LocalProfile>(profile);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => setDraft({ ...profile, assistantName: snapshot.settings?.assistantName || profile.assistantName }), [profile, snapshot.settings?.assistantName]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    saveProfile(draft);
    try {
      if (snapshot.connection !== "unavailable") await saveAssistantName(draft.assistantName);
      setSaved(true);
      window.setTimeout(() => setSaved(false), 1800);
    } catch (reason) {
      setError(readableError(reason, "The profile was retained locally, but the backend setting could not be saved."));
    }
  }

  return (
    <div className="page-stack">
      <PageHeader title="Local Profile" description="Identity and reachability belong to ARES. Connected frameworks may read these settings but do not own them." />
      <form onSubmit={(event) => void submit(event)} className="grid gap-4 xl:grid-cols-[minmax(0,42rem)_1fr]">
        <Card>
          <CardHeader>
            <CardTitle>Identity</CardTitle>
            <CardDescription>These values remain available when no assistant runtime is connected.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-5">
            <div className="grid gap-2">
              <Label htmlFor="display-name">What should your SI call you?</Label>
              <Input id="display-name" value={draft.displayName} onChange={(event) => setDraft({ ...draft, displayName: event.target.value })} placeholder="Your name" />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="assistant-name">Assistant name</Label>
              <Input id="assistant-name" value={draft.assistantName} onChange={(event) => setDraft({ ...draft, assistantName: event.target.value })} />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="voice">Voice</Label>
              <Select value={draft.voice} onValueChange={(voice) => setDraft({ ...draft, voice })}>
                <SelectTrigger id="voice"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="system-default">System default</SelectItem>
                  <SelectItem value="disabled">Disabled</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="reachability">Reachability</Label>
              <Select value={draft.reachability} onValueChange={(reachability: LocalProfile["reachability"]) => setDraft({ ...draft, reachability })}>
                <SelectTrigger id="reachability"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="this-device">This device</SelectItem>
                  <SelectItem value="local-network">Local network</SelectItem>
                  <SelectItem value="private-network">Private network</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <Button type="submit" className="justify-self-start">
              {saved ? <Check /> : <Save />}{saved ? "Saved" : "Save Local Profile"}
            </Button>
            {error ? <p className="text-sm text-status-limited">{error}</p> : null}
          </CardContent>
        </Card>
        <Card className="h-fit">
          <CardHeader>
            <CardTitle>Runtime independence</CardTitle>
            <CardDescription>Connecting Ares Agent, Claude, Gemini, or another framework is optional. Each integration maps its capabilities into ARES contracts. The assistant name is also synchronized with the controller when it is available.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-5">
            <div className="flex items-center justify-between gap-4">
              <div className="grid gap-1">
                <Label htmlFor="context-store" className="text-base font-semibold">Enable Context Store</Label>
                <p className="text-sm text-muted-foreground">Activate the local sqlite-vec memory so Jaeger AI can remember your engineering context.</p>
              </div>
              <ToggleSwitch 
                id="context-store" 
                checked={draft.contextStoreEnabled ?? false} 
                onCheckedChange={(checked) => setDraft({ ...draft, contextStoreEnabled: checked })}
              />
            </div>
          </CardContent>
        </Card>
      </form>
    </div>
  );
}

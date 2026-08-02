import { Bot, Check, LoaderCircle, RefreshCw } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

import { useCompanionSettings } from "./useCompanionSettings";

/** Settings → SI: one ARES relationship backed by one live JaegerAI Companion. */
export function SISection() {
  const companion = useCompanionSettings();
  const selectedCharacter = companion.status?.characters.find(
    (row) => row.id === companion.characterId,
  );

  if (companion.loading) {
    return (
      <div className="grid place-items-center gap-3 py-20 text-sm text-muted-foreground">
        <LoaderCircle className="size-5 animate-spin" />
        Connecting to your Companion…
      </div>
    );
  }

  if (!companion.status) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Companion unavailable</CardTitle>
          <CardDescription>{companion.error || "ARES could not reach JaegerAI."}</CardDescription>
        </CardHeader>
        <CardContent>
          <Button variant="outline" onClick={() => void companion.load()}>
            <RefreshCw /> Try again
          </Button>
        </CardContent>
      </Card>
    );
  }

  const { status } = companion;
  return (
    <div className="grid gap-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-lg font-semibold">SI</h3>
          <p className="text-sm text-muted-foreground">
            One identity in ARES, powered locally by your JaegerAI Companion.
          </p>
        </div>
        <Badge variant={status.relationship.aligned ? "secondary" : "outline"}>
          {status.relationship.aligned ? "Identity synchronized" : "Identity needs sync"}
        </Badge>
      </div>

      {companion.error ? (
        <p className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {companion.error}
        </p>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Bot className="size-4" /> Your Companion
          </CardTitle>
          <CardDescription>
            These controls update ARES and the selected JaegerAI agent together.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-5">
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label htmlFor="owner-name">What should your SI call you?</Label>
              <Input
                id="owner-name"
                value={companion.ownerName}
                onChange={(event) => companion.setOwnerName(event.target.value)}
                autoComplete="nickname"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="companion-name">Companion name</Label>
              <Input
                id="companion-name"
                value={companion.name}
                onChange={(event) => companion.setName(event.target.value)}
                autoComplete="off"
                maxLength={64}
              />
              <p className="text-xs text-muted-foreground">
                This changes the agent’s real JaegerAI identity, not its technical ID.
              </p>
            </div>
          </div>

          <div className="grid gap-2">
            <Label htmlFor="companion-character">Character</Label>
            <Select value={companion.characterId} onValueChange={companion.setCharacterId}>
              <SelectTrigger id="companion-character">
                <SelectValue placeholder="Choose a character" />
              </SelectTrigger>
              <SelectContent>
                {status.characters.map((character) => (
                  <SelectItem key={character.id} value={character.id}>
                    {character.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              {selectedCharacter?.role || status.character.role ||
                "Character controls personality, communication style, and voice."}
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <Button
              onClick={() => void companion.save()}
              disabled={companion.saving || !companion.name.trim() || !companion.characterId}
            >
              {companion.saving ? <LoaderCircle className="animate-spin" /> : companion.saved ? <Check /> : null}
              {companion.saving ? "Saving…" : companion.saved ? "Saved" : "Save Companion"}
            </Button>
            <span className="text-xs text-muted-foreground">
              Voice: {status.character.voice_id || status.character.voice_tone || "Character default"}
            </span>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Local intelligence</CardTitle>
          <CardDescription>
            JaegerAI is the primary local runtime. Specialist workers remain separate tools.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm sm:grid-cols-3">
          <div>
            <div className="text-xs uppercase tracking-wide text-muted-foreground">Agent</div>
            <div className="font-medium">{status.agent.id || status.agent.name}</div>
          </div>
          <div>
            <div className="text-xs uppercase tracking-wide text-muted-foreground">Transport</div>
            <div className="font-medium capitalize">{status.dependency.transport}</div>
          </div>
          <div>
            <div className="text-xs uppercase tracking-wide text-muted-foreground">Model</div>
            <div className="font-medium">{status.agent.model || "Starting when needed"}</div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

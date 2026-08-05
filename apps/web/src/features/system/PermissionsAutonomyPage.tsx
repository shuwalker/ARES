import { Check, LoaderCircle, ShieldAlert, Smartphone } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { AUTONOMY_OPTIONS } from "@/onboarding-profile";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import type { LocalProfile } from "@/shared/contracts";
import { useLocalProfile } from "@/shared/local-profile";

/**
 * Control Center: observe-only / ask-before-acting / delegated autonomy,
 * device & network reachability, and approval behavior.
 *
 * Persists the same keys as before (`local_profile_autonomy`,
 * `local_profile_reachability`) so existing preferences survive.
 */
export function PermissionsAutonomyPage() {
  const { profile, saveProfile } = useLocalProfile();
  const [draft, setDraft] = useState<Pick<LocalProfile, "autonomy" | "reachability">>({
    autonomy: profile.autonomy,
    reachability: profile.reachability,
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");
  const [status, setStatus] = useState("");

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    void aresApi
      .settingsGet()
      .then((settings) => {
        if (cancelled) return;
        const autonomy = String(settings.local_profile_autonomy || profile.autonomy);
        const reachability = String(settings.local_profile_reachability || profile.reachability);
        setDraft({
          autonomy: (["observe", "confirm", "delegated"].includes(autonomy)
            ? autonomy
            : profile.autonomy) as LocalProfile["autonomy"],
          reachability: (["this-device", "local-network", "private-network"].includes(reachability)
            ? reachability
            : profile.reachability) as LocalProfile["reachability"],
        });
      })
      .catch((reason) => {
        if (!cancelled) setError(readableError(reason, "Could not load permission settings."));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [profile.autonomy, profile.reachability]);

  const save = useCallback(async () => {
    setSaving(true);
    setError("");
    try {
      await saveProfile({
        ...profile,
        autonomy: draft.autonomy,
        reachability: draft.reachability,
      });
      await aresApi.settingsPost({
        local_profile_autonomy: draft.autonomy,
        local_profile_reachability: draft.reachability,
      });
      setSaved(true);
      setStatus("Saved");
      window.setTimeout(() => {
        setSaved(false);
        setStatus("");
      }, 1800);
    } catch (reason) {
      setError(readableError(reason, "Could not save permissions."));
    } finally {
      setSaving(false);
    }
  }, [draft, profile, saveProfile]);

  const selectedAutonomy = AUTONOMY_OPTIONS.find((o) => o.id === draft.autonomy);

  return (
    <SurfaceShell
      title="Permissions & Autonomy"
      description="Decide how freely the Companion may act, which networks it may use, and when approvals are required."
      action={
        status ? (
          <Badge variant="secondary" className="font-normal">
            {status}
          </Badge>
        ) : undefined
      }
    >
      <SurfaceNote>
        Autonomy and device reachability moved here from App Settings. Approval queues still live
        under Life → Approvals; this page sets the default posture that feeds those gates.
      </SurfaceNote>

      {error ? (
        <p
          className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive"
          role="alert"
        >
          {error}
        </p>
      ) : null}

      {loading ? (
        <div className="grid place-items-center gap-3 py-16 text-sm text-muted-foreground">
          <LoaderCircle className="size-5 animate-spin" />
          Loading…
        </div>
      ) : (
        <div className="grid gap-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <ShieldAlert className="size-4 text-primary" />
                Autonomy mode
              </CardTitle>
              <CardDescription>
                Choose the default action posture. System permission gates and worker tool policies
                still apply in every mode.
              </CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4">
              <div className="grid gap-2">
                <Label>Default autonomy</Label>
                <Select
                  value={draft.autonomy}
                  onValueChange={(autonomy: LocalProfile["autonomy"]) =>
                    setDraft((d) => ({ ...d, autonomy }))
                  }
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="observe">Observe only</SelectItem>
                    <SelectItem value="confirm">Ask before acting</SelectItem>
                    <SelectItem value="delegated">Delegated autonomy</SelectItem>
                  </SelectContent>
                </Select>
                {selectedAutonomy ? (
                  <p className="text-xs text-muted-foreground">{selectedAutonomy.detail}</p>
                ) : null}
              </div>

              <div className="grid gap-2 rounded-lg border border-border/70 bg-card/40 p-3 text-xs text-muted-foreground">
                <p>
                  <strong className="text-foreground">Observe only</strong> — surface changes and
                  suggestions; do not act.
                </p>
                <p>
                  <strong className="text-foreground">Ask before acting</strong> — prepare work,
                  then request confirmation for consequential actions.
                </p>
                <p>
                  <strong className="text-foreground">Delegated</strong> — act within explicit
                  scopes; approval gates and pairing still apply.
                </p>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Smartphone className="size-4 text-primary" />
                Device & network access
              </CardTitle>
              <CardDescription>
                How far this Companion instance may be reached. Pair devices under Pairing for remote
                clients.
              </CardDescription>
            </CardHeader>
            <CardContent className="grid gap-3">
              <div className="grid gap-2">
                <Label>Reachability</Label>
                <Select
                  value={draft.reachability}
                  onValueChange={(reachability: LocalProfile["reachability"]) =>
                    setDraft((d) => ({ ...d, reachability }))
                  }
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="this-device">This device only</SelectItem>
                    <SelectItem value="local-network">Local network</SelectItem>
                    <SelectItem value="private-network">Private network (e.g. Tailscale)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <Button asChild variant="outline" size="sm" className="w-fit">
                <Link to="/pairing">Manage paired devices</Link>
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Approval behavior</CardTitle>
              <CardDescription>
                When autonomy is “Ask before acting” or a tool requires a gate, pending decisions
                appear in Life → Approvals. Delegated mode reduces prompts but does not bypass
                hard permission checks.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-2">
              <Button asChild variant="outline" size="sm">
                <Link to="/inbox">Open Approvals</Link>
              </Button>
              <Button asChild variant="outline" size="sm">
                <Link to="/secrets">Secrets</Link>
              </Button>
              <Button asChild variant="outline" size="sm">
                <Link to="/memory-privacy">Memory & Privacy</Link>
              </Button>
            </CardContent>
          </Card>

          <div>
            <Button type="button" disabled={saving} onClick={() => void save()}>
              {saving ? <LoaderCircle className="animate-spin" /> : saved ? <Check /> : null}
              {saved ? "Saved" : "Save permissions"}
            </Button>
          </div>
        </div>
      )}
    </SurfaceShell>
  );
}

import { FormEvent, useEffect, useState, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";

export function AuthGate({ children }: { children: ReactNode }) {
  const [state, setState] = useState<"loading" | "allowed" | "login">("loading");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let active = true;
    void aresApi.authStatus().then((status) => {
      if (active) setState(!status.authEnabled || status.loggedIn ? "allowed" : "login");
    }).catch((reason) => {
      if (active) {
        setError(readableError(reason, "ARES authentication status is unavailable."));
        setState("login");
      }
    });
    return () => { active = false; };
  }, []);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError("");
    try {
      await aresApi.login(password);
      window.location.reload();
    } catch (reason) {
      setError(readableError(reason, "ARES could not sign you in."));
      setSubmitting(false);
    }
  }

  if (state === "allowed") return children;
  if (state === "loading") return <main className="grid min-h-dvh place-items-center bg-background text-sm text-muted-foreground">Starting ARES…</main>;

  return (
    <main className="grid min-h-dvh place-items-center bg-background px-4 text-foreground">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Open ARES</CardTitle>
          <CardDescription>Enter the password for this ARES controller.</CardDescription>
        </CardHeader>
        <CardContent>
          <form className="space-y-4" onSubmit={(event) => void submit(event)}>
            <div className="space-y-2">
              <Label htmlFor="ares-password">Password</Label>
              <Input id="ares-password" type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} autoFocus />
            </div>
            {error ? <p className="text-sm text-status-unavailable" role="alert">{error}</p> : null}
            <Button className="w-full" type="submit" disabled={submitting || !password}>{submitting ? "Signing in…" : "Sign in"}</Button>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}

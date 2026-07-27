import { Fingerprint, KeyRound, LogIn, LoaderCircle } from "lucide-react";
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
  const [methods, setMethods] = useState({ password: false, oidc: false, passkey: false });

  useEffect(() => {
    let active = true;
    void aresApi.authStatus().then((status) => {
      if (active) {
        setMethods({ password: status.passwordAuthEnabled, oidc: status.oidcEnabled, passkey: status.passkeysEnabled });
        setState(!status.authEnabled || status.loggedIn ? "allowed" : "login");
      }
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

  function decodeBase64Url(value: string): ArrayBuffer {
    const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
    const binary = window.atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "="));
    return Uint8Array.from(binary, (character) => character.charCodeAt(0)).buffer;
  }

  function encodeBase64Url(value: ArrayBuffer | null): string | null {
    if (!value) return null;
    const bytes = new Uint8Array(value);
    let binary = "";
    bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
    return window.btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  async function usePasskey() {
    if (!window.PublicKeyCredential || !navigator.credentials) {
      setError("Passkeys are not supported by this WebView or browser.");
      return;
    }
    setSubmitting(true); setError("");
    try {
      const options = await aresApi.passkeyOptions();
      const source = options.publicKey;
      const publicKey: PublicKeyCredentialRequestOptions = {
        ...(source as unknown as PublicKeyCredentialRequestOptions),
        challenge: decodeBase64Url(String(source.challenge || "")),
        allowCredentials: Array.isArray(source.allowCredentials)
          ? (source.allowCredentials as Array<Record<string, unknown>>).map((item) => ({ ...item, id: decodeBase64Url(String(item.id || "")) } as PublicKeyCredentialDescriptor))
          : undefined,
      };
      const credential = await navigator.credentials.get({ publicKey }) as PublicKeyCredential | null;
      if (!credential) throw new Error("Passkey sign-in was cancelled.");
      const response = credential.response as AuthenticatorAssertionResponse;
      await aresApi.passkeyLogin({
        id: credential.id,
        rawId: encodeBase64Url(credential.rawId),
        type: credential.type,
        response: {
          authenticatorData: encodeBase64Url(response.authenticatorData),
          clientDataJSON: encodeBase64Url(response.clientDataJSON),
          signature: encodeBase64Url(response.signature),
          userHandle: encodeBase64Url(response.userHandle),
        },
      });
      window.location.reload();
    } catch (reason) {
      setError(readableError(reason, "ARES could not sign in with the passkey."));
      setSubmitting(false);
    }
  }

  if (state === "allowed") return children;
  if (state === "loading") return <main className="grid min-h-dvh place-items-center bg-background text-sm text-muted-foreground">Starting ARES app…</main>;

  return (
    <main className="grid min-h-dvh place-items-center bg-background px-4 text-foreground">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Open ARES</CardTitle>
          <CardDescription>Authenticate with one of the methods configured for this ARES controller.</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
          {methods.password ? <form className="space-y-4" onSubmit={(event) => void submit(event)}>
            <div className="space-y-2">
              <Label htmlFor="ares-password">Password</Label>
              <Input id="ares-password" type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} autoFocus />
            </div>
            {error ? <p className="text-sm text-status-unavailable" role="alert">{error}</p> : null}
            <Button className="w-full" type="submit" disabled={submitting || !password}>{submitting ? <LoaderCircle className="animate-spin" /> : <KeyRound />}{submitting ? "Signing in…" : "Sign in with password"}</Button>
          </form> : null}
          {methods.passkey ? <Button className="w-full" variant="outline" disabled={submitting} onClick={() => void usePasskey()}><Fingerprint />Sign in with passkey</Button> : null}
          {methods.oidc ? <Button className="w-full" variant="outline" disabled={submitting} onClick={() => window.location.assign("/api/auth/oidc/start?next=%2F")}><LogIn />Sign in with identity provider</Button> : null}
          {!methods.password && !methods.passkey && !methods.oidc ? <p className="text-sm text-status-unavailable" role="alert">Authentication is enabled, but no interactive sign-in method is available in this client. Check the controller’s trusted-header or authentication configuration.</p> : null}
          {error && !methods.password ? <p className="text-sm text-status-unavailable" role="alert">{error}</p> : null}
          </div>
        </CardContent>
      </Card>
    </main>
  );
}

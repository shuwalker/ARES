import { KeyRound, LoaderCircle, Shield } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function AccessCard({
  authEnabled,
  passwordAuth,
  envLocked,
  currentPassword,
  setCurrentPassword,
  newPassword,
  setNewPassword,
  authBusy,
  setPassword,
  clearPassword,
}: {
  authEnabled: boolean;
  passwordAuth: boolean;
  envLocked: boolean;
  currentPassword: string;
  setCurrentPassword: (value: string) => void;
  newPassword: string;
  setNewPassword: (value: string) => void;
  authBusy: boolean;
  setPassword: () => Promise<void>;
  clearPassword: () => Promise<void>;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2"><Shield className="size-4" /> Access password</CardTitle>
        <CardDescription>
          {envLocked
            ? "ARES_WEBUI_PASSWORD is set in the environment and overrides UI changes."
            : authEnabled ? "Authentication is enabled." : "This instance is accessible without authentication."}
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-3">
        {!authEnabled ? (
          <p className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs text-amber-800 dark:text-amber-200">
            Anyone who can reach this host can use ARES.
          </p>
        ) : null}
        {passwordAuth ? (
          <div className="grid gap-2">
            <Label htmlFor="current-password">Current password</Label>
            <Input id="current-password" type="password" autoComplete="current-password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} disabled={envLocked} />
          </div>
        ) : null}
        <div className="grid gap-2">
          <Label htmlFor="new-password">New password</Label>
          <Input id="new-password" type="password" autoComplete="new-password" value={newPassword} onChange={(event) => setNewPassword(event.target.value)} disabled={envLocked} placeholder="Enter new password…" />
        </div>
        <div className="flex flex-wrap gap-2">
          <Button type="button" disabled={envLocked || authBusy || !newPassword.trim()} onClick={() => void setPassword()}>
            {authBusy ? <LoaderCircle className="animate-spin" /> : <KeyRound />} Set password
          </Button>
          {passwordAuth ? <Button type="button" variant="outline" disabled={envLocked || authBusy} onClick={() => void clearPassword()}>Disable auth</Button> : null}
        </div>
      </CardContent>
    </Card>
  );
}

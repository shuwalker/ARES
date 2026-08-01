import { ExternalLink, LoaderCircle, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";

import {
  jaegerStateLabel,
  jaegerStateTone,
  normalizeJaegerState,
  parseJaegerStatus,
  type JaegerStatusPayload,
  type JaegerUiState,
} from "./jaeger-status";

/**
 * Live Jaeger AI peer status. Never mocks runtime state; only shows fields
 * returned by GET /api/jaeger-onboarding/status. Refresh re-probes the peer.
 */
export function JaegerStatusCard() {
  const [status, setStatus] = useState<JaegerStatusPayload | null>(null);
  const [uiState, setUiState] = useState<JaegerUiState>("checking");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (refresh = false) => {
    setBusy(true);
    setError("");
    if (!refresh) setUiState("checking");
    try {
      const raw = await aresApi.jaegerStatus(refresh);
      const parsed = parseJaegerStatus(raw);
      setStatus(parsed);
      setUiState(normalizeJaegerState(parsed.state));
    } catch (reason) {
      const msg = readableError(reason, "Could not reach Jaeger status.");
      setError(msg);
      setUiState("error");
      setStatus({
        state: "error",
        available: false,
        message: msg,
      });
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void load(false);
  }, [load]);

  const checkedLabel =
    status?.checked_at != null
      ? new Date(status.checked_at * 1000).toLocaleTimeString()
      : null;

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="grid gap-1">
            <CardTitle className="text-base">Jaeger AI</CardTitle>
            <CardDescription>
              Jaeger AI is the default local brain for fast, private, always-available interaction.
              ARES can delegate specialized work to connected workers while preserving one continuous
              SI identity.
            </CardDescription>
          </div>
          <Badge variant={jaegerStateTone(uiState)} className="shrink-0 font-normal">
            {uiState === "checking" || busy ? (
              <span className="inline-flex items-center gap-1">
                <LoaderCircle className="size-3 animate-spin" aria-hidden="true" />
                {jaegerStateLabel(uiState === "checking" ? "checking" : uiState)}
              </span>
            ) : (
              jaegerStateLabel(uiState)
            )}
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="grid gap-4">
        {error ? (
          <p className="text-xs text-destructive" role="alert">
            {error}
          </p>
        ) : null}

        <p className="text-sm text-foreground/90">{status?.message || "Probing Jaeger peer…"}</p>

        <dl className="grid gap-2 text-xs sm:grid-cols-2">
          <div className="rounded-md border border-border/70 bg-card/40 px-3 py-2">
            <dt className="text-muted-foreground">Transport</dt>
            <dd className="mt-0.5 font-medium text-foreground">
              {status?.transport_mode === "gateway"
                ? "HTTP gateway"
                : status?.transport_mode === "bridge"
                  ? "Local bridge"
                  : "—"}
            </dd>
          </div>
          <div className="rounded-md border border-border/70 bg-card/40 px-3 py-2">
            <dt className="text-muted-foreground">Companion instance ready</dt>
            <dd className="mt-0.5 font-medium text-foreground">
              {status ? (status.companion_ready ? "Yes" : "No") : "—"}
            </dd>
          </div>
          <div className="rounded-md border border-border/70 bg-card/40 px-3 py-2">
            <dt className="text-muted-foreground">Active model</dt>
            <dd className="mt-0.5 font-medium text-foreground">
              {status?.models_are_live && status.active_model
                ? status.active_model
                : "Not reported by live health check"}
            </dd>
          </div>
          <div className="rounded-md border border-border/70 bg-card/40 px-3 py-2">
            <dt className="text-muted-foreground">Active instance</dt>
            <dd className="mt-0.5 font-medium text-foreground">
              {status?.active_instance || "Not reported by live health check"}
            </dd>
          </div>
          {status?.gateway_url ? (
            <div className="rounded-md border border-border/70 bg-card/40 px-3 py-2 sm:col-span-2">
              <dt className="text-muted-foreground">Gateway</dt>
              <dd className="mt-0.5 break-all font-mono text-[11px] text-foreground">
                {status.gateway_url}
              </dd>
            </div>
          ) : null}
          {status?.root ? (
            <div className="rounded-md border border-border/70 bg-card/40 px-3 py-2 sm:col-span-2">
              <dt className="text-muted-foreground">Install root</dt>
              <dd className="mt-0.5 break-all font-mono text-[11px] text-foreground">{status.root}</dd>
            </div>
          ) : null}
        </dl>

        {status?.instances && status.instances.length > 0 ? (
          <div className="grid gap-2">
            <p className="text-xs font-medium text-foreground">Configured instances</p>
            <ul className="grid gap-1.5">
              {status.instances.slice(0, 6).map((inst) => (
                <li
                  key={inst.path || inst.name}
                  className="rounded-md border border-border/60 px-3 py-2 text-xs"
                >
                  <span className="font-medium text-foreground">
                    {inst.display_name || inst.name}
                  </span>
                  {inst.model ? (
                    <span className="ml-2 text-muted-foreground">model: {inst.model}</span>
                  ) : null}
                </li>
              ))}
            </ul>
          </div>
        ) : (
          <p className="text-xs text-muted-foreground">
            No local instances discovered. Complete onboarding or create a Companion with Jaeger
            tools if you want a named agent on disk.
          </p>
        )}

        {checkedLabel ? (
          <p className="text-[11px] text-muted-foreground">Last health check: {checkedLabel}</p>
        ) : null}

        <div className="flex flex-wrap gap-2">
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={busy}
            onClick={() => void load(true)}
            aria-label="Refresh Jaeger status"
          >
            {busy ? <LoaderCircle className="animate-spin" /> : <RefreshCw />}
            Test / refresh
          </Button>
          <Button asChild variant="outline" size="sm">
            <Link to="/hatchery">
              Advanced local intelligence
              <ExternalLink className="size-3.5 opacity-70" />
            </Link>
          </Button>
        </div>

        <p className="text-[11px] leading-relaxed text-muted-foreground">
          Start, restart, model install, and hardware tuning are not controlled from Settings. Use
          Hatchery and Control Center for advanced local intelligence. Active model is shown only
          when the live health probe reports it — recommendations are never shown as active.
        </p>
      </CardContent>
    </Card>
  );
}

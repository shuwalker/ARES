/**
 * Jaeger AI peer-runtime status helpers.
 *
 * Status comes from GET /api/jaeger-onboarding/status, which probes the shared
 * provider contract — never from saved preferences or model recommendations.
 */

export type JaegerUiState =
  | "checking"
  | "ready"
  | "needs_attention"
  | "installed_but_stopped"
  | "misconfigured"
  | "not_installed"
  | "unavailable"
  | "error";

export interface JaegerInstanceInfo {
  name: string;
  path: string;
  display_name?: string;
  model?: string | null;
  character?: string | null;
}

export interface JaegerStatusPayload {
  state: JaegerUiState | string;
  provider_state?: string;
  available: boolean;
  message: string;
  details?: Record<string, unknown>;
  checked_at?: number;
  jaeger_cli?: string | null;
  jaeger_ai_available?: boolean;
  jaeger_ai_path?: string | null;
  companion_ready?: boolean;
  transport_mode?: string | null;
  gateway_url?: string | null;
  root?: string | null;
  active_model?: string | null;
  active_instance?: string | null;
  instances?: JaegerInstanceInfo[];
  has_instances?: boolean;
  models_are_live?: boolean;
}

export function normalizeJaegerState(raw: unknown): JaegerUiState {
  const s = String(raw || "").toLowerCase();
  switch (s) {
    case "ready":
    case "connected":
      return "ready";
    case "needs_attention":
      return "needs_attention";
    case "installed_but_stopped":
    case "offline":
      return "installed_but_stopped";
    case "misconfigured":
    case "not_configured":
      return "misconfigured";
    case "not_installed":
      return "not_installed";
    case "error":
      return "error";
    case "checking":
      return "checking";
    default:
      return "unavailable";
  }
}

export function jaegerStateLabel(state: JaegerUiState): string {
  switch (state) {
    case "checking":
      return "Checking";
    case "ready":
      return "Ready";
    case "needs_attention":
      return "Needs attention";
    case "installed_but_stopped":
      return "Installed but stopped";
    case "misconfigured":
      return "Misconfigured";
    case "not_installed":
      return "Not installed";
    case "error":
      return "Error";
    default:
      return "Unavailable";
  }
}

/** Badge tone for the design system (muted, not neon). */
export function jaegerStateTone(
  state: JaegerUiState,
): "default" | "secondary" | "outline" | "destructive" {
  switch (state) {
    case "ready":
      return "default";
    case "needs_attention":
    case "installed_but_stopped":
    case "misconfigured":
      return "secondary";
    case "error":
    case "not_installed":
      return "destructive";
    default:
      return "outline";
  }
}

/**
 * Parse a status API response. Never invents model/instance from recommendations.
 */
export function parseJaegerStatus(raw: unknown): JaegerStatusPayload {
  if (!raw || typeof raw !== "object") {
    return {
      state: "error",
      available: false,
      message: "Invalid Jaeger status response.",
    };
  }
  const data = raw as Record<string, unknown>;
  const instances = Array.isArray(data.instances)
    ? (data.instances as JaegerInstanceInfo[]).filter(
        (i) => i && typeof i === "object" && typeof i.name === "string",
      )
    : [];

  const activeModel =
    typeof data.active_model === "string" && data.active_model.trim()
      ? data.active_model.trim()
      : null;
  const activeInstance =
    typeof data.active_instance === "string" && data.active_instance.trim()
      ? data.active_instance.trim()
      : null;

  return {
    state: normalizeJaegerState(data.state),
    provider_state: typeof data.provider_state === "string" ? data.provider_state : undefined,
    available: Boolean(data.available),
    message: typeof data.message === "string" ? data.message : "No status message.",
    details:
      data.details && typeof data.details === "object"
        ? (data.details as Record<string, unknown>)
        : {},
    checked_at: typeof data.checked_at === "number" ? data.checked_at : undefined,
    jaeger_cli: typeof data.jaeger_cli === "string" ? data.jaeger_cli : null,
    jaeger_ai_available: Boolean(data.jaeger_ai_available),
    jaeger_ai_path: typeof data.jaeger_ai_path === "string" ? data.jaeger_ai_path : null,
    companion_ready: Boolean(data.companion_ready),
    transport_mode: typeof data.transport_mode === "string" ? data.transport_mode : null,
    gateway_url: typeof data.gateway_url === "string" ? data.gateway_url : null,
    root: typeof data.root === "string" ? data.root : null,
    active_model: activeModel,
    active_instance: activeInstance,
    instances,
    has_instances: instances.length > 0,
    models_are_live: Boolean(data.models_are_live) && activeModel != null,
  };
}

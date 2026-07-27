declare global {
  interface Window {
    __ARES_CONFIG__?: { csrfToken?: string };
  }
}

export class ApiError extends Error {
  status: number;
  code?: string;
  details: unknown;

  constructor(message: string, status: number, details?: unknown, code?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.details = details;
    this.code = code;
  }
}

function requestHeaders(init: RequestInit): Headers {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  const method = (init.method || "GET").toUpperCase();
  if (!["GET", "HEAD", "OPTIONS"].includes(method)) {
    const token = window.__ARES_CONFIG__?.csrfToken;
    if (token) {
      headers.set("X-Ares-CSRF-Token", token);
      headers.set("X-CSRF-Token", token);
    }
  }
  return headers;
}

export async function apiFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(path, {
    ...init,
    credentials: "same-origin",
    headers: requestHeaders(init),
  });
  const contentType = response.headers.get("content-type") || "";
  const payload: unknown = contentType.includes("application/json")
    ? await response.json().catch(() => ({}))
    : await response.text().catch(() => "");
  if (!response.ok) {
    const body = payload && typeof payload === "object" ? payload as Record<string, unknown> : {};
    // Only fall back to the raw payload when it is a string. Stringifying an
    // object here rendered a literal "[object Object]" to users whenever an
    // error body carried structured fields but no top-level message.
    const rawFallback = typeof payload === "string" && payload.trim() ? payload : "";
    const message = String(
      body.error || body.message || rawFallback || `Request failed (${response.status})`,
    );
    throw new ApiError(message, response.status, payload, typeof body.code === "string" ? body.code : undefined);
  }
  return payload as T;
}

export function apiUrl(path: string, query?: Record<string, string | number | boolean | undefined>) {
  const url = new URL(path, window.location.origin);
  Object.entries(query || {}).forEach(([key, value]) => {
    if (value !== undefined) url.searchParams.set(key, String(value));
  });
  return url.toString();
}

export function webSocketUrl(path: string, query?: Record<string, string | number | boolean | undefined>) {
  const url = new URL(apiUrl(path, query));
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  return url.toString();
}

export function webSocketProtocols() {
  const token = window.__ARES_CONFIG__?.csrfToken;
  return token ? ["ares-v1", `ares.csrf.${token}`] : ["ares-v1"];
}

export function readableError(error: unknown, fallback = "ARES could not complete the request.") {
  if (error instanceof Error && error.message) return error.message;
  return fallback;
}

/**
 * The provider context behind a failed request, when the server sent one.
 *
 * Adapter errors carry `code`, and often `connection_id` and `state`, which the
 * UI needs in order to say which provider failed and link to where it is fixed.
 * `readableError` deliberately keeps returning only the message; this is the
 * separate accessor for callers that can act on the structure.
 */
export interface ProviderErrorContext {
  code?: string;
  connectionId?: string;
  state?: string;
}

export function providerErrorContext(error: unknown): ProviderErrorContext | null {
  if (!(error instanceof ApiError)) return null;
  const details =
    error.details && typeof error.details === "object"
      ? (error.details as Record<string, unknown>)
      : {};
  const connectionId = typeof details.connection_id === "string" ? details.connection_id : undefined;
  const state = typeof details.state === "string" ? details.state : undefined;
  if (!error.code && !connectionId && !state) return null;
  return { code: error.code, connectionId, state };
}

/** Error codes that mean "no usable provider", as opposed to a transient failure. */
export const PROVIDER_UNAVAILABLE_CODES = new Set([
  "no_runtime_selected",
  "runtime_unavailable",
  "runtime_health_unavailable",
  "unknown_runtime_connection",
]);

export interface UploadResult {
  filename: string;
  path: string;
  size: number;
  mime: string;
  is_image: boolean;
}

export async function uploadFile(sessionId: string, file: File): Promise<UploadResult> {
  const formData = new FormData();
  formData.append("session_id", sessionId);
  formData.append("file", file);
  const response = await fetch("/api/upload", {
    method: "POST",
    credentials: "same-origin",
    body: formData,
  });
  const payload: unknown = await response.json().catch(() => ({}));
  if (!response.ok) {
    const body = payload && typeof payload === "object" ? payload as Record<string, unknown> : {};
    const message = String(body.error || body.message || `Upload failed (${response.status})`);
    throw new ApiError(message, response.status, payload);
  }
  return payload as UploadResult;
}

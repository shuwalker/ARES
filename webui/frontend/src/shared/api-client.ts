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
    const message = String(body.error || body.message || payload || `Request failed (${response.status})`);
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

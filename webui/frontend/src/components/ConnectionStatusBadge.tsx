import { cn } from "@/lib/utils";
import type { RuntimeConnectionState } from "@/shared/contracts";

/**
 * One rendering of provider readiness, shared across every surface that shows it.
 *
 * The point of the five states is that a user can tell what to *do*: a provider
 * that was never set up needs configuration, one whose CLI is missing needs an
 * install, and one that is installed but unreachable needs starting. ARES
 * previously reported all three as "offline", which answered none of those.
 *
 * Uses the `--status-*` design tokens rather than raw palette colours so the
 * meaning stays consistent if the palette changes.
 */

interface StatusPresentation {
  label: string;
  dot: string;
  text: string;
  /** True when the provider cannot currently accept a turn. */
  blocking: boolean;
}

const PRESENTATION: Record<RuntimeConnectionState, StatusPresentation> = {
  connected: {
    label: "Connected",
    dot: "bg-status-available",
    text: "text-status-available",
    blocking: false,
  },
  available: {
    label: "Available",
    dot: "bg-status-available",
    text: "text-status-available",
    blocking: false,
  },
  needs_attention: {
    label: "Needs attention",
    dot: "bg-status-limited",
    text: "text-status-limited",
    blocking: false,
  },
  offline: {
    label: "Offline",
    dot: "bg-status-unavailable",
    text: "text-status-unavailable",
    blocking: true,
  },
  // Never-configured and never-installed read as outlines rather than filled
  // dots: nothing is wrong, something is simply absent.
  not_configured: {
    label: "Not configured",
    dot: "border border-status-limited bg-transparent",
    text: "text-status-limited",
    blocking: true,
  },
  not_installed: {
    label: "Not installed",
    dot: "border border-muted-foreground bg-transparent",
    text: "text-muted-foreground",
    blocking: true,
  },
};

const FALLBACK: StatusPresentation = PRESENTATION.offline;

export function statusPresentation(state: RuntimeConnectionState | undefined): StatusPresentation {
  return (state && PRESENTATION[state]) || FALLBACK;
}

/** Whether a provider in this state can accept a chat turn. */
export function isBlockingState(state: RuntimeConnectionState | undefined): boolean {
  return statusPresentation(state).blocking;
}

export function ConnectionStatusBadge({
  state,
  className,
  showLabel = true,
}: {
  state: RuntimeConnectionState | undefined;
  className?: string;
  showLabel?: boolean;
}) {
  const presentation = statusPresentation(state);
  return (
    <span className={cn("inline-flex items-center gap-1.5", className)}>
      <span
        aria-hidden="true"
        className={cn("inline-block size-2 shrink-0 rounded-full", presentation.dot)}
      />
      {showLabel ? (
        <span className={cn("text-[11px] font-medium", presentation.text)}>{presentation.label}</span>
      ) : null}
    </span>
  );
}

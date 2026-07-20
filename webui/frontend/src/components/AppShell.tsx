import { CommandCenterShell } from "@/components/command-center/CommandCenterShell";

/**
 * Compatibility export for the route boundary. The actual shell is split into
 * focused command-center modules so navigation, panes, and workbench behavior
 * can evolve independently.
 */
export function AppShell() {
  return <CommandCenterShell />;
}

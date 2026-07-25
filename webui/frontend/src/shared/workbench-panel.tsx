import { createContext, useContext, useMemo, type ReactNode } from "react";

/**
 * Control surface for the Command Center's right-hand workspace panel.
 *
 * The panel is owned by CommandCenterShell, but the conversation composer also
 * needs to toggle it. Passing the imperative handle through context keeps those
 * callers off synthetic DOM events, which never worked: the panel library's
 * Separator has no click-to-collapse behavior.
 */
export interface WorkbenchPanelControls {
  collapsed: boolean;
  collapse: () => void;
  expand: () => void;
  toggle: () => void;
}

const NOOP_CONTROLS: WorkbenchPanelControls = {
  collapsed: false,
  collapse: () => {},
  expand: () => {},
  toggle: () => {},
};

const WorkbenchPanelContext = createContext<WorkbenchPanelControls>(NOOP_CONTROLS);

export function WorkbenchPanelProvider({
  collapsed,
  collapse,
  expand,
  children,
}: {
  collapsed: boolean;
  collapse: () => void;
  expand: () => void;
  children: ReactNode;
}) {
  const value = useMemo<WorkbenchPanelControls>(
    () => ({
      collapsed,
      collapse,
      expand,
      toggle: () => (collapsed ? expand() : collapse()),
    }),
    [collapsed, collapse, expand],
  );

  return <WorkbenchPanelContext.Provider value={value}>{children}</WorkbenchPanelContext.Provider>;
}

/**
 * Returns no-op controls when rendered outside the Command Center shell, so
 * surfaces reused elsewhere (tests, standalone routes) degrade quietly.
 */
export function useWorkbenchPanel(): WorkbenchPanelControls {
  return useContext(WorkbenchPanelContext);
}

import { Navigate, Route, Routes } from "react-router-dom";

import { workspaceRoutes } from "@/app-navigation";
import { AppShell } from "@/components/AppShell";
import { AuthGate } from "@/components/AuthGate";
import { ActivationScreen } from "@/pages/ActivationScreen";
import AgentDetailPage from "@/pages/AgentDetailPage";
import { SettingsPage } from "@/pages/SettingsPage";
import { SharePage } from "@/pages/SharePage";

/**
 * Canonical ARES WebUI entry (ARES = app name only).
 *
 * Product shell: CommandCenterShell via AppShell.
 * Route table: app-navigation.ts (sidebar source of truth).
 * First-run: Use native onboarding (`ares setup` command).
 * User talks to Companion; workers execute.
 *
 * Do not re-mount HermesWorkspace here — discarded prototype.
 */
export default function App() {
  return (
    <Routes>
      <Route path="share/:token" element={<SharePage />} />
      {/* ActivationScreen disabled — use native onboarding (ares setup) instead */}
      <Route
        element={
          <AuthGate>
            <AppShell />
          </AuthGate>
        }
      >
        <Route index element={<Navigate to="/activation" replace />} />
        {workspaceRoutes.map(({ path, component: Component }) => (
          <Route key={path} path={path} element={<Component />} />
        ))}
        <Route path="settings" element={<SettingsPage />} />
        <Route path="agents/:id" element={<AgentDetailPage />} />
        {/* Legacy path aliases */}
        <Route path="channels" element={<Navigate to="/connections" replace />} />
        <Route path="cron" element={<Navigate to="/schedules" replace />} />
        <Route path="routines" element={<Navigate to="/schedules" replace />} />
        <Route path="skills-studio" element={<Navigate to="/skills" replace />} />
        <Route path="*" element={<Navigate to="/today" replace />} />
      </Route>
    </Routes>
  );
}

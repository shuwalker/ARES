import { lazy, Suspense } from "react";
import { Navigate, Route, Routes } from "react-router-dom";

import { workspaceRoutes } from "@/app-navigation";
import { AppShell } from "@/components/AppShell";
import { AuthGate } from "@/components/AuthGate";
import AgentDetailPage from "@/pages/AgentDetailPage";
import { SettingsPage } from "@/pages/SettingsPage";
import { SharePage } from "@/pages/SharePage";

const SelfPage = lazy(async () => {
  const mod = await import("@/pages/surfaces/SelfPage");
  return { default: mod.SelfPage };
});

/**
 * Canonical ARES WebUI entry (ARES = app name only).
 *
 * Product shell: CommandCenterShell via AppShell.
 * Surfaces: Chat | Companion | Self | Workshop | Library | System
 *   → docs/architecture/PRODUCT_SURFACES.md
 */
export default function App() {
  return (
    <Routes>
      <Route path="share/:token" element={<SharePage />} />
      <Route
        element={
          <AuthGate>
            <AppShell />
          </AuthGate>
        }
      >
        <Route index element={<Navigate to="/companion" replace />} />
        {workspaceRoutes.map(({ path, component: Component }) => (
          <Route key={path} path={path} element={<Component />} />
        ))}
        <Route
          path="self/:area"
          element={
            <Suspense fallback={<div className="p-6 text-sm text-muted-foreground">Loading Self…</div>}>
              <SelfPage />
            </Suspense>
          }
        />
        <Route path="settings" element={<SettingsPage />} />
        <Route path="agents/:id" element={<AgentDetailPage />} />
        {/* Legacy path aliases */}
        <Route path="channels" element={<Navigate to="/connections" replace />} />
        <Route path="cron" element={<Navigate to="/schedules" replace />} />
        <Route path="routines" element={<Navigate to="/schedules" replace />} />
        {/* /skills-studio is now a real route (Skill Studio was built but never
            registered), so it is no longer aliased to the skills list. */}
        <Route path="*" element={<Navigate to="/companion" replace />} />
      </Route>
    </Routes>
  );
}

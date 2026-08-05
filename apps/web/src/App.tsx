import { lazy, Suspense } from "react";
import { Navigate, Route, Routes } from "react-router-dom";

import { workspaceRoutes } from "@/app-navigation";
import { AppShell } from "@/components/AppShell";
import { AuthGate } from "@/components/AuthGate";
import AgentDetailPage from "@/features/system/AgentDetailPage";
import { SettingsPage } from "@/features/system/SettingsPage";
import { SharePage } from "@/features/advanced-chat/SharePage";

const SelfPage = lazy(async () => {
  const mod = await import("@/features/self/SelfPage");
  return { default: mod.SelfPage };
});

const ActivationScreen = lazy(async () => {
  const mod = await import("@/features/companion/ActivationScreen");
  return { default: mod.ActivationScreen };
});

/**
 * Canonical ARES WebUI entry (ARES = app name only).
 *
 * Product shell: CommandCenterShell via AppShell.
 * Environments: Agent | Engineering | Studio | Life | Library | Control Center
 *   → docs/architecture/PRODUCT_SURFACES.md
 */
export default function App() {
  return (
    <Routes>
      <Route path="share/:token" element={<SharePage />} />
      {/* Full-window SI character/activation wizard — linked from the
          Companion surface; lives outside the AppShell chrome on purpose. */}
      <Route
        path="activation"
        element={
          <AuthGate>
            <Suspense fallback={<div className="p-6 text-sm text-muted-foreground">Loading wizard…</div>}>
              <ActivationScreen />
            </Suspense>
          </AuthGate>
        }
      />
      <Route
        element={
          <AuthGate>
            <AppShell />
          </AuthGate>
        }
      >
        <Route index element={<Navigate to="/chat" replace />} />
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

import { Navigate, Route, Routes } from "react-router-dom";

import { AppShell } from "@/components/AppShell";
import { AuthGate } from "@/components/AuthGate";
import { ActivityPage } from "@/pages/ActivityPage";
import { ConnectionsPage } from "@/pages/ConnectionsPage";
import { ConversationPage } from "@/pages/ConversationPage";
import { SettingsPage } from "@/pages/SettingsPage";
import { SharePage } from "@/pages/SharePage";
import { TerminalPage } from "@/pages/TerminalPage";
import { TodayPage } from "@/pages/TodayPage";
import { UsageCostPage } from "@/pages/UsageCostPage";
import { WorkspacePage } from "@/pages/WorkspacePage";
import { CanvasPage } from "@/pages/CanvasPage";
import InboxPage from "@/pages/InboxPage";
import IssuesPage from "@/pages/IssuesPage";
import RoutinesPage from "@/pages/RoutinesPage";
import SkillStudioPage from "@/pages/SkillStudioPage";
import SecretsPage from "@/pages/SecretsPage";
import HatcheryPage from "@/pages/HatcheryPage";
import CronPage from "@/pages/CronPage";

export default function App() {
  return (
    <Routes>
      <Route path="share/:token" element={<SharePage />} />
      <Route element={<AuthGate><AppShell /></AuthGate>}>
        <Route index element={<Navigate to="/today" replace />} />
        <Route path="today" element={<TodayPage />} />
        <Route path="conversation" element={<ConversationPage />} />
        <Route path="workspace" element={<WorkspacePage />} />
        <Route path="terminal" element={<TerminalPage />} />
        <Route path="activity" element={<ActivityPage />} />
        <Route path="canvas" element={<CanvasPage />} />
        <Route path="usage" element={<UsageCostPage />} />
        <Route path="connections" element={<ConnectionsPage />} />
        <Route path="settings" element={<SettingsPage />} />
        <Route path="inbox" element={<InboxPage />} />
        <Route path="issues" element={<IssuesPage />} />
        <Route path="routines" element={<RoutinesPage />} />
        <Route path="skills" element={<SkillStudioPage />} />
        <Route path="secrets" element={<SecretsPage />} />
        <Route path="hatchery" element={<HatcheryPage />} />
        <Route path="cron" element={<CronPage />} />
        <Route path="*" element={<Navigate to="/today" replace />} />
      </Route>
    </Routes>
  );
}

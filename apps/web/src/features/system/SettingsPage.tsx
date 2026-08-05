import { LoaderCircle } from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";

import { AppearanceSection } from "@/features/settings/AppearanceSection";
import { ChatSection } from "@/features/settings/ChatSection";
import { SISection } from "@/features/settings/SISection";
import { SystemSection } from "@/features/settings/SystemSection";
import { useSettingsController } from "@/features/settings/useSettingsController";

/**
 * Route-level Settings container.
 *
 * Settings is a standalone utility opened from the bottom-left gear — not a
 * seventh main environment. Sections are focused components under
 * `features/settings/`. Memory, privacy, and autonomy live in Control Center.
 */
export function SettingsPage() {
  const ctrl = useSettingsController();

  const body = (() => {
    switch (ctrl.section) {
      case "si":
        return <SISection />;
      case "appearance":
        return (
          <AppearanceSection
            theme={ctrl.theme}
            themeChoice={ctrl.themeChoice}
            fontSize={ctrl.fontSize}
            skin={ctrl.skin}
            density={ctrl.density}
            setDensity={ctrl.setDensity}
            island={ctrl.island}
            updateIsland={ctrl.updateIsland}
            settings={ctrl.settings}
            setBool={ctrl.setBool}
            setStr={ctrl.setStr}
            applyThemeChoice={ctrl.applyThemeChoice}
            applySkin={ctrl.applySkin}
            applyFontSize={ctrl.applyFontSize}
          />
        );
      case "chat":
        return (
          <ChatSection
            activeSession={ctrl.activeSession}
            sessionId={ctrl.sessionId}
            actionBusy={ctrl.actionBusy}
            importRef={ctrl.importRef}
            settings={ctrl.settings}
            setSettings={ctrl.setSettings}
            setBool={ctrl.setBool}
            setStr={ctrl.setStr}
            patchSettings={ctrl.patchSettings}
            exportActive={ctrl.exportActive}
            shareActive={ctrl.shareActive}
            stopShareActive={ctrl.stopShareActive}
            clearActive={ctrl.clearActive}
            onImportFile={ctrl.onImportFile}
          />
        );
      case "app":
        return (
          <SystemSection
            settings={ctrl.settings}
            setBool={ctrl.setBool}
            setStr={ctrl.setStr}
            newPassword={ctrl.newPassword}
            setNewPassword={ctrl.setNewPassword}
            currentPassword={ctrl.currentPassword}
            setCurrentPassword={ctrl.setCurrentPassword}
            authBusy={ctrl.authBusy}
            plugins={ctrl.plugins}
            extensions={ctrl.extensions}
            setExtensions={ctrl.setExtensions}
            extStatus={ctrl.extStatus}
            listsLoading={ctrl.listsLoading}
            loadSettings={ctrl.loadSettings}
            setPassword={ctrl.setPassword}
            clearPassword={ctrl.clearPassword}
            flash={ctrl.flash}
            setError={ctrl.setError}
          />
        );
      default:
        return null;
    }
  })();

  return (
    <div className="page-stack settings-hub">
      <PageHeader
        title="Settings"
        description="SI identity and preferences. Memory, privacy, and autonomy live in Control Center."
        action={
          ctrl.status || ctrl.savingKeys.size ? (
            <Badge variant="secondary" className="font-normal">
              {ctrl.savingKeys.size ? "Saving…" : ctrl.status}
            </Badge>
          ) : undefined
        }
      />

      {ctrl.error ? (
        <p
          className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive"
          role="alert"
        >
          {ctrl.error}
        </p>
      ) : null}

      <main className="settings-main min-w-0">
        {ctrl.loading ? (
          <div className="grid place-items-center gap-3 py-20 text-sm text-muted-foreground">
            <LoaderCircle className="size-5 animate-spin" />
            Loading settings…
          </div>
        ) : (
          body
        )}
      </main>
    </div>
  );
}

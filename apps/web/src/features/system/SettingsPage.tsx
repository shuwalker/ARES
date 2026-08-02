import { LoaderCircle, Search } from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

import { AppearanceSection } from "@/features/settings/AppearanceSection";
import { ChatSection } from "@/features/settings/ChatSection";
import { SETTINGS_SECTIONS } from "@/features/settings/constants";
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
        return (
          <SISection
            draft={ctrl.draft}
            setDraft={ctrl.setDraft}
            profileSaved={ctrl.profileSaved}
            submitProfile={ctrl.submitProfile}
            settings={ctrl.settings}
            patchSettings={ctrl.patchSettings}
            setSettings={ctrl.setSettings}
            flash={ctrl.flash}
            setError={ctrl.setError}
          />
        );
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

      <div className="settings-layout">
        <aside className="settings-side">
          <div className="relative mb-3">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={ctrl.search}
              onChange={(e) => {
                ctrl.setSearch(e.target.value);
                ctrl.setSearchOpen(true);
              }}
              onFocus={() => ctrl.setSearchOpen(true)}
              onBlur={() => window.setTimeout(() => ctrl.setSearchOpen(false), 150)}
              placeholder="Search settings…"
              className="pl-8"
              aria-label="Search settings"
            />
            {ctrl.searchOpen && ctrl.searchHits.length > 0 && (
              <div className="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-md border bg-popover p-1 shadow-lg">
                {ctrl.searchHits.map((hit) => (
                  <button
                    key={`${hit.section}-${hit.label}`}
                    type="button"
                    className="flex w-full flex-col items-start rounded-sm px-2 py-1.5 text-left text-xs hover:bg-accent"
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => ctrl.goSection(hit.section)}
                  >
                    <span className="font-medium text-foreground">{hit.label}</span>
                    <span className="text-[10px] uppercase tracking-wide text-muted-foreground">
                      {SETTINGS_SECTIONS.find((s) => s.id === hit.section)?.label}
                    </span>
                  </button>
                ))}
              </div>
            )}
          </div>

          <nav className="settings-side-nav" aria-label="Settings sections">
            {SETTINGS_SECTIONS.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => ctrl.goSection(id)}
                className={cn("settings-side-item", ctrl.section === id && "is-active")}
              >
                <Icon className="size-4 shrink-0" />
                <span>{label}</span>
              </button>
            ))}
          </nav>
        </aside>

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
    </div>
  );
}

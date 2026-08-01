import { Laptop, Moon, Sun } from "lucide-react";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { IslandPosition } from "@/island-backdrop";
import { cn } from "@/lib/utils";

import { ChoiceGrid, Field, ToggleField } from "./fields";
import { applyAppearanceToDocument, asBool, asNumber, asString, SKINS } from "./helpers";
import type { Density, FontSize, ThemeChoice } from "./types";
import type { SettingsController } from "./useSettingsController";

export function AppearanceSection({
  theme,
  themeChoice,
  fontSize,
  skin,
  density,
  setDensity,
  island,
  updateIsland,
  settings,
  setBool,
  setStr,
  applyThemeChoice,
  applySkin,
  applyFontSize,
}: Pick<
  SettingsController,
  | "theme"
  | "themeChoice"
  | "fontSize"
  | "skin"
  | "density"
  | "setDensity"
  | "island"
  | "updateIsland"
  | "settings"
  | "setBool"
  | "setStr"
  | "applyThemeChoice"
  | "applySkin"
  | "applyFontSize"
>) {
  return (
    <div className="grid gap-6">
      <div>
        <h3 className="text-lg font-semibold">Appearance</h3>
        <p className="text-sm text-muted-foreground">Theme, accent skins, and chat visual behavior.</p>
      </div>

      <Field label="Theme" description={`Active: ${theme}${themeChoice === "system" ? " (following OS)" : ""}.`}>
        <ChoiceGrid
          value={themeChoice}
          onChange={(id) => void applyThemeChoice(id as ThemeChoice)}
          options={[
            { id: "system", label: "System", icon: <Laptop className="size-4" /> },
            { id: "light", label: "Light", icon: <Sun className="size-4" /> },
            { id: "dark", label: "Dark", icon: <Moon className="size-4" /> },
          ]}
        />
      </Field>

      <Field label="Skin" description="Accent palette. Agent-agnostic — applies to the whole WebUI.">
        <div className="flex flex-wrap gap-2">
          {SKINS.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => void applySkin(s)}
              className={cn(
                "rounded-md border px-2.5 py-1.5 text-[11px] font-medium capitalize transition-colors",
                skin === s
                  ? "border-primary bg-primary/10 text-primary"
                  : "border-border text-muted-foreground hover:border-primary/40 hover:text-foreground",
              )}
            >
              {s}
            </button>
          ))}
        </div>
      </Field>

      <Field label="Font size">
        <ChoiceGrid
          value={fontSize}
          onChange={(id) => void applyFontSize(id as FontSize)}
          options={[
            { id: "small", label: "Small", preview: <span className="text-[10px] font-semibold">Aa</span> },
            { id: "default", label: "Default", preview: <span className="text-[13px] font-semibold">Aa</span> },
            { id: "large", label: "Large", preview: <span className="text-[17px] font-semibold">Aa</span> },
            { id: "xlarge", label: "Extra large", preview: <span className="text-[20px] font-semibold">Aa</span> },
          ]}
        />
      </Field>

      <Field label="WebUI density" description="Local device density for lists and spacing.">
        <Select value={density} onValueChange={(v: Density) => setDensity(v)}>
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="comfortable">Comfortable</SelectItem>
            <SelectItem value="compact">Compact</SelectItem>
          </SelectContent>
        </Select>
      </Field>

      <Field
        label="Island backdrop"
        description="Renders the shell as translucent glass over the ARES island wallpaper. Browser-local — it does not sync to other devices."
      >
        <div className="grid gap-3">
          <ToggleField
            id="island-backdrop-enabled"
            label="Enable island backdrop"
            checked={island.enabled}
            onChange={(enabled) => updateIsland({ enabled })}
          />
          <div className={cn("grid gap-3", !island.enabled && "pointer-events-none opacity-50")}>
            <div className="grid gap-1.5">
              <Label htmlFor="island-surface-opacity" className="text-xs text-muted-foreground">
                Surface opacity — {island.surfaceOpacity}%
              </Label>
              <input
                id="island-surface-opacity"
                type="range"
                min={0}
                max={100}
                step={1}
                value={island.surfaceOpacity}
                disabled={!island.enabled}
                onChange={(event) => updateIsland({ surfaceOpacity: Number(event.target.value) })}
                className="w-full accent-primary"
              />
            </div>
            <Select
              value={island.position}
              onValueChange={(position: IslandPosition) => updateIsland({ position })}
            >
              <SelectTrigger aria-label="Wallpaper anchor">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="top">Anchor top</SelectItem>
                <SelectItem value="center">Anchor center</SelectItem>
                <SelectItem value="bottom">Anchor bottom</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
      </Field>

      <Field label="Activity display" description="How tool and thinking activity appears while workers run.">
        <div className="flex flex-wrap gap-2">
          {(
            [
              { id: "compact_worklog", label: "Compact worklog" },
              { id: "transparent_stream", label: "Transparent stream" },
              { id: "hide_all_activity", label: "Final answer only" },
            ] as const
          ).map((opt) => (
            <button
              key={opt.id}
              type="button"
              onClick={() => setStr("chat_activity_display_mode", opt.id)}
              className={cn(
                "rounded-md border px-3 py-2 text-xs font-medium transition-colors",
                asString(settings.chat_activity_display_mode, "compact_worklog") === opt.id
                  ? "border-primary bg-primary/10 text-primary"
                  : "border-border text-muted-foreground hover:border-primary/40",
              )}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </Field>

      <div className="grid gap-2">
        <ToggleField
          id="auto_scroll_follow"
          label="Auto-follow new content"
          description="Scroll to the bottom as tokens stream in."
          checked={asBool(settings.auto_scroll_follow, true)}
          onChange={(v) => setBool("auto_scroll_follow", v)}
        />
        <ToggleField
          id="session_endless_scroll"
          label="Load older messages while scrolling up"
          description="Endless scroll for long transcripts."
          checked={asBool(settings.session_endless_scroll)}
          onChange={(v) => setBool("session_endless_scroll", v)}
        />
        <ToggleField
          id="session_jump_buttons"
          label="Show session jump buttons"
          description="Floating Start / End controls on long histories."
          checked={asBool(settings.session_jump_buttons)}
          onChange={(v) => setBool("session_jump_buttons", v)}
        />
        <ToggleField
          id="render_user_markdown"
          label="Render markdown in user messages"
          description="Bold, links, and lists in your own messages."
          checked={asBool(settings.render_user_markdown)}
          onChange={(v) => setBool("render_user_markdown", v)}
        />
        <ToggleField
          id="large_text_paste_as_attachment"
          label="Attach large pasted text as file"
          description="Long pastes become a .md attachment instead of flooding the composer."
          checked={asBool(settings.large_text_paste_as_attachment, true)}
          onChange={(v) => setBool("large_text_paste_as_attachment", v)}
        />
        <ToggleField
          id="worklog_details_expanded_default"
          label="Open worklog details automatically"
          description="Expand tool/thinking cards by default."
          checked={asBool(settings.worklog_details_expanded_default)}
          onChange={(v) => setBool("worklog_details_expanded_default", v)}
        />
        <ToggleField
          id="workspace_todos_tab"
          label="Show Todos tab in workspace panel"
          description="Adds a Todos tab in the right-hand workbench."
          checked={asBool(settings.workspace_todos_tab)}
          onChange={(v) => setBool("workspace_todos_tab", v)}
        />
        <ToggleField
          id="project_quick_create_buttons"
          label="Per-project new-conversation buttons"
          description="Show + on project chips in the deck."
          checked={asBool(settings.project_quick_create_buttons)}
          onChange={(v) => setBool("project_quick_create_buttons", v)}
        />
        <ToggleField
          id="show_titlebar_profile"
          label="Show profile switcher in titlebar"
          description="Optional profile control in the app chrome."
          checked={asBool(settings.show_titlebar_profile)}
          onChange={(v) => setBool("show_titlebar_profile", v)}
        />
        <ToggleField
          id="rtl"
          label="Right-to-left chat layout"
          description="RTL for messages and composer only."
          checked={asBool(settings.rtl)}
          onChange={(v) => {
            setBool("rtl", v);
            applyAppearanceToDocument({
              theme: themeChoice,
              skin,
              fontSize,
              density,
              rtl: v,
            });
          }}
        />
        <ToggleField
          id="fade_text_effect"
          label="Fade text effect"
          description="Light fade-in on newly streamed words."
          checked={asBool(settings.fade_text_effect)}
          onChange={(v) => setBool("fade_text_effect", v)}
        />
      </div>

      <Field label="JSON / YAML code blocks" description="How structured code fences open by default.">
        <Select
          value={asString(settings.structured_code_default_view, "auto")}
          onValueChange={(v) => setStr("structured_code_default_view", v)}
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="auto">Auto: tree for long blocks</SelectItem>
            <SelectItem value="on">Tree by default</SelectItem>
            <SelectItem value="off">Raw by default</SelectItem>
          </SelectContent>
        </Select>
      </Field>

      <Field label="Auto tree threshold (lines)">
        <Input
          type="number"
          min={1}
          max={1000}
          value={asNumber(settings.structured_code_auto_tree_lines, 10)}
          onChange={(e) => setStr("structured_code_auto_tree_lines", Number(e.target.value) || 10)}
        />
      </Field>
    </div>
  );
}

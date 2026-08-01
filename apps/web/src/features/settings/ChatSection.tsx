import {
  Download,
  FileJson,
  FileText,
  Link2,
  LoaderCircle,
  Share2,
  Trash2,
  Upload,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

import { Field, ToggleField } from "./fields";
import { asBool, asNumber, asString } from "./helpers";
import type { SettingsController } from "./useSettingsController";

export function ChatSection({
  activeSession,
  sessionId,
  actionBusy,
  importRef,
  settings,
  setSettings,
  setBool,
  setStr,
  patchSettings,
  exportActive,
  shareActive,
  stopShareActive,
  clearActive,
  onImportFile,
}: Pick<
  SettingsController,
  | "activeSession"
  | "sessionId"
  | "actionBusy"
  | "importRef"
  | "settings"
  | "setSettings"
  | "setBool"
  | "setStr"
  | "patchSettings"
  | "exportActive"
  | "shareActive"
  | "stopShareActive"
  | "clearActive"
  | "onImportFile"
>) {
  const title = activeSession?.title?.trim() || (sessionId ? sessionId : "No active conversation");

  return (
    <div className="grid gap-6">
      <div>
        <h3 className="text-lg font-semibold">Chat</h3>
        <p className="text-sm text-muted-foreground">
          Active conversation tools, composer defaults, and voice notifications.
        </p>
      </div>

      <div className="grid gap-4">
        <div>
          <h4 className="text-sm font-semibold">Active conversation</h4>
          <p className="text-sm text-muted-foreground">
            {sessionId ? (
              <>
                Active: <span className="text-foreground">{title}</span>
                {activeSession?.messageCount != null ? ` · ${activeSession.messageCount} messages` : ""}
              </>
            ) : (
              "No active conversation selected — open Agent and pick a session."
            )}
          </p>
        </div>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
          {(
            [
              { id: "md", label: "Transcript", icon: FileText, fn: () => void exportActive("md") },
              { id: "json", label: "JSON", icon: FileJson, fn: () => void exportActive("json") },
              { id: "html", label: "HTML", icon: Download, fn: () => void exportActive("html") },
              { id: "share", label: "Share", icon: Share2, fn: () => void shareActive() },
              { id: "stop-share", label: "Stop sharing", icon: Link2, fn: () => void stopShareActive() },
              {
                id: "import",
                label: "Import",
                icon: Upload,
                fn: () => importRef.current?.click(),
              },
              { id: "clear", label: "Clear", icon: Trash2, fn: () => void clearActive(), danger: true },
            ] as const
          ).map((btn) => (
            <Button
              key={btn.id}
              type="button"
              variant={"danger" in btn && btn.danger ? "destructive" : "outline"}
              className="justify-start"
              disabled={!sessionId && btn.id !== "import"}
              onClick={btn.fn}
            >
              {actionBusy === btn.id ? <LoaderCircle className="animate-spin" /> : <btn.icon />}
              {btn.label}
            </Button>
          ))}
        </div>
        <input
          ref={importRef}
          type="file"
          accept=".json,application/json"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) void onImportFile(f);
            e.target.value = "";
          }}
        />
      </div>

      <div className="grid gap-2">
        <h4 className="text-sm font-semibold">Composer & sessions</h4>
        <Field label="Send key" description="How Enter behaves in the composer.">
          <Select value={asString(settings.send_key, "enter")} onValueChange={(v) => setStr("send_key", v)}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="enter">Enter to send</SelectItem>
              <SelectItem value="ctrl+enter">Ctrl/Cmd+Enter to send</SelectItem>
              <SelectItem value="shift+enter">Shift+Enter to send</SelectItem>
            </SelectContent>
          </Select>
        </Field>
        <Field
          label="Default message mode"
          description="What happens when you send while a worker is still running."
        >
          <Select
            value={asString(settings.default_message_mode, "steer")}
            onValueChange={(v) => setStr("default_message_mode", v)}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="steer">Steer</SelectItem>
              <SelectItem value="queue">Queue</SelectItem>
              <SelectItem value="interrupt">Interrupt</SelectItem>
            </SelectContent>
          </Select>
        </Field>
        <Field label="Sidebar density">
          <Select
            value={asString(settings.sidebar_density, "compact")}
            onValueChange={(v) => setStr("sidebar_density", v)}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="compact">Compact</SelectItem>
              <SelectItem value="detailed">Detailed</SelectItem>
            </SelectContent>
          </Select>
        </Field>
        <Field label="Auto-title refresh">
          <Select
            value={asString(settings.auto_title_refresh_every, "0")}
            onValueChange={(v) => setStr("auto_title_refresh_every", v)}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="0">Off</SelectItem>
              <SelectItem value="5">Every 5 exchanges</SelectItem>
              <SelectItem value="10">Every 10 exchanges</SelectItem>
              <SelectItem value="20">Every 20 exchanges</SelectItem>
            </SelectContent>
          </Select>
        </Field>
        <Field label="Pinned sessions limit">
          <Input
            type="number"
            min={1}
            max={99}
            value={asNumber(settings.pinned_sessions_limit, 3)}
            onChange={(e) => setStr("pinned_sessions_limit", Number(e.target.value) || 3)}
          />
        </Field>
        <Field label="Max output tokens" description="Optional override. Leave empty for model default.">
          <Input
            type="number"
            min={1}
            placeholder="No override"
            value={settings.max_tokens == null ? "" : String(settings.max_tokens)}
            onChange={(e) => {
              const raw = e.target.value.trim();
              if (!raw) {
                setSettings((p) => ({ ...p, max_tokens: null }));
                void patchSettings({ max_tokens: null });
              } else {
                setStr("max_tokens", Number(raw));
              }
            }}
          />
        </Field>
        <ToggleField
          id="hide_empty_state_suggestions"
          label="Hide new-chat suggestions"
          description="Hide the three suggestion buttons on empty chat."
          checked={asBool(settings.hide_empty_state_suggestions)}
          onChange={(v) => setBool("hide_empty_state_suggestions", v)}
        />
        <ToggleField
          id="virtualize_transcript"
          label="Virtualize long transcripts"
          description="Experimental: virtualize chats over ~80 messages."
          checked={asBool(settings.virtualize_transcript)}
          onChange={(v) => setBool("virtualize_transcript", v)}
        />
        <ToggleField
          id="new_chat_on_workspace_switch"
          label="New chat when switching workspace"
          description="Start a fresh conversation instead of rebinding the current one."
          checked={asBool(settings.new_chat_on_workspace_switch)}
          onChange={(v) => setBool("new_chat_on_workspace_switch", v)}
        />
        <ToggleField
          id="show_token_usage"
          label="Show token usage"
          description="Input/output token badge under assistant messages."
          checked={asBool(settings.show_token_usage)}
          onChange={(v) => setBool("show_token_usage", v)}
        />
        <ToggleField
          id="show_quota_chip"
          label="Show provider quota chip"
          description="Ambient quota in the composer footer (wide layouts)."
          checked={asBool(settings.show_quota_chip)}
          onChange={(v) => setBool("show_quota_chip", v)}
        />
        <ToggleField
          id="show_tps"
          label="Show tokens/sec"
          description="Throughput chip on assistant headers."
          checked={asBool(settings.show_tps)}
          onChange={(v) => setBool("show_tps", v)}
        />
        <ToggleField
          id="show_conversation_outline"
          label="Conversation outline"
          description="Desktop jump-to-question panel."
          checked={asBool(settings.show_conversation_outline)}
          onChange={(v) => setBool("show_conversation_outline", v)}
        />
        <ToggleField
          id="show_busy_placeholder_hint"
          label="Busy placeholder hint"
          description="Hint text while the worker is still running."
          checked={asBool(settings.show_busy_placeholder_hint)}
          onChange={(v) => setBool("show_busy_placeholder_hint", v)}
        />
        <ToggleField
          id="terminal_auto_expand_on_output"
          label="Auto-expand terminal on output"
          checked={asBool(settings.terminal_auto_expand_on_output)}
          onChange={(v) => setBool("terminal_auto_expand_on_output", v)}
        />
      </div>

      <div className="grid gap-2">
        <h4 className="text-sm font-semibold">Voice & notifications</h4>
        <ToggleField
          id="sound_enabled"
          label="Completion sound"
          checked={asBool(settings.sound_enabled)}
          onChange={(v) => setBool("sound_enabled", v)}
        />
        <ToggleField
          id="notifications_enabled"
          label="Browser notifications"
          description="Notify when the tab is in the background."
          checked={asBool(settings.notifications_enabled)}
          onChange={(v) => setBool("notifications_enabled", v)}
        />
        <ToggleField
          id="tts_enabled"
          label="Text-to-speech"
          checked={asBool(settings.tts_enabled)}
          onChange={(v) => setBool("tts_enabled", v)}
        />
        <ToggleField
          id="tts_auto_read"
          label="Auto-read assistant replies"
          checked={asBool(settings.tts_auto_read)}
          onChange={(v) => setBool("tts_auto_read", v)}
          disabled={!asBool(settings.tts_enabled)}
        />
        <Field label="TTS engine">
          <Select
            value={asString(settings.tts_engine, "browser")}
            onValueChange={(v) => setStr("tts_engine", v)}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="browser">Browser speech synthesis</SelectItem>
              <SelectItem value="edge">Edge TTS (server)</SelectItem>
              <SelectItem value="elevenlabs">ElevenLabs (server)</SelectItem>
              <SelectItem value="openai">OpenAI TTS (server)</SelectItem>
            </SelectContent>
          </Select>
        </Field>
        <Field label="TTS rate">
          <Input
            type="number"
            min={0.5}
            max={2}
            step={0.1}
            value={asNumber(settings.tts_rate, 1)}
            onChange={(e) => setStr("tts_rate", Number(e.target.value) || 1)}
          />
        </Field>
        <ToggleField
          id="voice_mode_button"
          label="Voice mode button"
          checked={asBool(settings.voice_mode_button)}
          onChange={(v) => setBool("voice_mode_button", v)}
        />
        <ToggleField
          id="raw_audio_mode"
          label="Raw audio mode"
          checked={asBool(settings.raw_audio_mode)}
          onChange={(v) => setBool("raw_audio_mode", v)}
        />
      </div>
    </div>
  );
}

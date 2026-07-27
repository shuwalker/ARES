import {
  AppWindow,
  BookOpen,
  Cable,
  Check,
  Download,
  FileJson,
  FileText,
  HelpCircle,
  KeyRound,
  Link2,
  LoaderCircle,
  MessageSquare,
  Monitor,
  Moon,
  Palette,
  Plug,
  Puzzle,
  RefreshCw,
  Search,
  Server,
  Settings2,
  Share2,
  SlidersHorizontal,
  Sun,
  Trash2,
  Upload,
  Laptop,
  ExternalLink,
  Shield,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import { Link, useSearchParams } from "react-router-dom";

import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ToggleSwitch } from "@/components/ui/toggle-switch";
import { useTheme } from "@/context/ThemeContext";
import {
  applySettings as applyIslandSettings,
  readSettings as readIslandSettings,
  writeSettings as writeIslandSettings,
  type IslandBackdropSettings,
  type IslandPosition,
} from "@/island-backdrop";
import { cn } from "@/lib/utils";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import type { LocalProfile } from "@/shared/contracts";
import { useLocalProfile } from "@/shared/local-profile";

// ── Types ────────────────────────────────────────────────────────────

type SettingsSection =
  | "conversation"
  | "appearance"
  | "preferences"
  | "connections"
  | "plugins"
  | "extensions"
  | "system"
  | "help";

type ThemeChoice = "system" | "light" | "dark";
type FontSize = "small" | "default" | "large" | "xlarge";
type Density = "comfortable" | "compact";
type SettingValue = string | number | boolean | null | unknown[] | Record<string, unknown>;

interface SearchHit {
  section: SettingsSection;
  label: string;
  keywords: string;
}

const SECTIONS: Array<{
  id: SettingsSection;
  label: string;
  description: string;
  icon: typeof Settings2;
}> = [
  { id: "conversation", label: "Conversation", description: "Export, share, and clear the active chat.", icon: MessageSquare },
  { id: "appearance", label: "Appearance", description: "Theme, font size, and chat chrome.", icon: Palette },
  { id: "preferences", label: "Preferences", description: "Identity, chat defaults, voice, privacy.", icon: Settings2 },
  { id: "connections", label: "Connections", description: "Workers, models, and LLM runtimes.", icon: Cable },
  { id: "plugins", label: "Plugins", description: "Installed agent plugins (read-only).", icon: Puzzle },
  { id: "extensions", label: "Extensions", description: "WebUI extensions registry.", icon: Plug },
  { id: "system", label: "System", description: "Version, access, and advanced keys.", icon: Server },
  { id: "help", label: "Help", description: "Docs and product orientation.", icon: HelpCircle },
];

const SKINS = [
  "default", "ares", "mono", "graphite", "slate", "poseidon", "sisyphus",
  "charizard", "sienna", "catppuccin", "nous", "geist-contrast", "zeus",
  "verdigris", "neon-soft", "neon-paint",
] as const;

const WEBUI_DENSITY_KEY = "ares.webui.density";
const MENUBAR_HINT_KEY = "ares.mac.menubar-hints";

function asBool(v: unknown, fallback = false): boolean {
  return typeof v === "boolean" ? v : fallback;
}

function asString(v: unknown, fallback = ""): string {
  return typeof v === "string" ? v : fallback;
}

function asNumber(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

function readDensity(): Density {
  try {
    return localStorage.getItem(WEBUI_DENSITY_KEY) === "compact" ? "compact" : "comfortable";
  } catch {
    return "comfortable";
  }
}

function readMenubarHints(): boolean {
  try {
    return localStorage.getItem(MENUBAR_HINT_KEY) !== "0";
  } catch {
    return true;
  }
}

function applyAppearanceToDocument(opts: {
  theme: ThemeChoice;
  skin: string;
  fontSize: FontSize;
  density: Density;
  rtl: boolean;
}) {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  root.dataset.skin = opts.skin || "default";
  root.dataset.fontSize = opts.fontSize || "default";
  root.dataset.density = opts.density;
  root.dir = opts.rtl ? "rtl" : "ltr";
}

function downloadBlob(filename: string, content: string, mime: string) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function Field({
  id,
  label,
  description,
  children,
  searchId,
}: {
  id?: string;
  label: string;
  description?: string;
  children: ReactNode;
  searchId?: string;
}) {
  return (
    <div className="settings-field grid gap-2" data-settings-search={searchId || label}>
      <div className="grid gap-0.5">
        <Label htmlFor={id} className="text-sm font-medium">
          {label}
        </Label>
        {description ? <p className="text-xs text-muted-foreground">{description}</p> : null}
      </div>
      {children}
    </div>
  );
}

function ToggleField({
  id,
  label,
  description,
  checked,
  onChange,
  disabled,
}: {
  id: string;
  label: string;
  description?: string;
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <div
      className="flex items-start justify-between gap-4 rounded-lg border border-border/70 bg-card/40 px-3 py-3"
      data-settings-search={`${label} ${description || ""}`}
    >
      <div className="grid min-w-0 gap-0.5">
        <Label htmlFor={id} className="text-sm font-medium">
          {label}
        </Label>
        {description ? <p className="text-xs text-muted-foreground">{description}</p> : null}
      </div>
      <ToggleSwitch id={id} checked={checked} onCheckedChange={onChange} disabled={disabled} />
    </div>
  );
}

function ChoiceGrid<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: Array<{ id: T; label: string; icon?: ReactNode; preview?: ReactNode }>;
  onChange: (id: T) => void;
}) {
  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4">
      {options.map((opt) => (
        <button
          key={opt.id}
          type="button"
          onClick={() => onChange(opt.id)}
          className={cn(
            "flex flex-col items-center gap-1.5 rounded-lg border px-3 py-3 text-xs font-medium transition-colors",
            value === opt.id
              ? "border-primary bg-primary/10 text-primary"
              : "border-border text-muted-foreground hover:border-primary/40 hover:text-foreground",
          )}
        >
          {opt.preview || opt.icon}
          {opt.label}
        </button>
      ))}
    </div>
  );
}

// ── Page ─────────────────────────────────────────────────────────────

export function SettingsPage() {
  const { profile, saveProfile } = useLocalProfile();
  const { snapshot, currentSession, refresh, selectedSessionId } = useAres();
  const { theme, preference, setPreference } = useTheme();
  const [searchParams, setSearchParams] = useSearchParams();

  const sectionParam = searchParams.get("section") as SettingsSection | null;
  const [section, setSection] = useState<SettingsSection>(() =>
    sectionParam && SECTIONS.some((s) => s.id === sectionParam) ? sectionParam : "appearance",
  );
  const [search, setSearch] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);

  const [settings, setSettings] = useState<Record<string, SettingValue>>({});
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");
  const [savingKeys, setSavingKeys] = useState<Set<string>>(new Set());

  // Local profile draft (identity)
  const [draft, setDraft] = useState<LocalProfile>(profile);
  const [profileSaved, setProfileSaved] = useState(false);

  // Device-local prefs
  const [density, setDensity] = useState<Density>(() => readDensity());
  const [menubarHints, setMenubarHints] = useState(() => readMenubarHints());
  const [island, setIsland] = useState<IslandBackdropSettings>(() => readIslandSettings());

  // The backdrop is pure presentation held in localStorage, so it applies
  // immediately rather than round-tripping through the settings API.
  const updateIsland = useCallback((patch: Partial<IslandBackdropSettings>) => {
    setIsland((current) => {
      const next = { ...current, ...patch };
      applyIslandSettings(next);
      writeIslandSettings(next);
      return next;
    });
  }, []);

  // Auth
  const [newPassword, setNewPassword] = useState("");
  const [currentPassword, setCurrentPassword] = useState("");
  const [authBusy, setAuthBusy] = useState(false);

  // Plugins / extensions
  const [plugins, setPlugins] = useState<Array<Record<string, unknown>>>([]);
  const [extensions, setExtensions] = useState<Array<Record<string, unknown>>>([]);
  const [extStatus, setExtStatus] = useState<Record<string, unknown> | null>(null);
  const [listsLoading, setListsLoading] = useState(false);

  // Conversation actions
  const [actionBusy, setActionBusy] = useState("");
  const importRef = useRef<HTMLInputElement | null>(null);
  const saveTimer = useRef<number | null>(null);

  const activeSession = currentSession;
  const sessionId = activeSession?.id || selectedSessionId || "";

  const themeChoice: ThemeChoice =
    asString(settings.theme, preference) === "system" ||
    asString(settings.theme, preference) === "light" ||
    asString(settings.theme, preference) === "dark"
      ? (asString(settings.theme, preference) as ThemeChoice)
      : preference;

  const fontSize = (["small", "default", "large", "xlarge"].includes(asString(settings.font_size))
    ? asString(settings.font_size)
    : "default") as FontSize;

  const skin = SKINS.includes(asString(settings.skin) as (typeof SKINS)[number])
    ? asString(settings.skin)
    : "default";

  // ── Load ───────────────────────────────────────────────────────────

  const loadSettings = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const data = (await aresApi.settingsGet()) as Record<string, SettingValue>;
      setSettings(data);
      const nextTheme = asString(data.theme, "dark") as ThemeChoice;
      if (nextTheme === "system" || nextTheme === "light" || nextTheme === "dark") {
        setPreference(nextTheme);
      }
      applyAppearanceToDocument({
        theme: nextTheme === "system" ? "system" : nextTheme,
        skin: asString(data.skin, "default"),
        fontSize: (asString(data.font_size, "default") as FontSize) || "default",
        density: readDensity(),
        rtl: asBool(data.rtl),
      });
    } catch (reason) {
      setError(readableError(reason, "Could not load settings."));
    } finally {
      setLoading(false);
    }
  }, [setPreference]);

  useEffect(() => {
    void loadSettings();
  }, [loadSettings]);

  useEffect(() => {
    setDraft({
      ...profile,
      assistantName: asString(settings.bot_name, profile.assistantName) || profile.assistantName,
      displayName: asString(settings.owner_name, profile.displayName) || profile.displayName,
      contextStoreEnabled: asBool(settings.context_store_enabled, profile.contextStoreEnabled ?? false),
      includeExternalHistory: asBool(settings.show_cli_sessions, profile.includeExternalHistory ?? false),
    });
  }, [profile, settings.bot_name, settings.owner_name, settings.context_store_enabled, settings.show_cli_sessions]);

  useEffect(() => {
    if (sectionParam && SECTIONS.some((s) => s.id === sectionParam) && sectionParam !== section) {
      setSection(sectionParam);
    }
  }, [sectionParam, section]);

  useEffect(() => {
    try {
      localStorage.setItem(WEBUI_DENSITY_KEY, density);
      document.documentElement.dataset.density = density;
    } catch {
      /* ignore */
    }
  }, [density]);

  useEffect(() => {
    try {
      localStorage.setItem(MENUBAR_HINT_KEY, menubarHints ? "1" : "0");
    } catch {
      /* ignore */
    }
  }, [menubarHints]);

  useEffect(() => {
    if (section !== "plugins" && section !== "extensions") return;
    let cancelled = false;
    setListsLoading(true);
    void (async () => {
      try {
        if (section === "plugins") {
          const res = await aresApi.listPlugins();
          if (!cancelled) setPlugins(Array.isArray(res.plugins) ? res.plugins : []);
        } else {
          const [reg, st] = await Promise.all([
            aresApi.listExtensions().catch(() => ({})),
            aresApi.extensionStatus().catch(() => ({})),
          ]);
          if (cancelled) return;
          setExtStatus(st);
          const list =
            (Array.isArray((reg as { extensions?: unknown[] }).extensions) &&
              (reg as { extensions: Array<Record<string, unknown>> }).extensions) ||
            (Array.isArray((reg as { items?: unknown[] }).items) &&
              (reg as { items: Array<Record<string, unknown>> }).items) ||
            (Array.isArray(reg) ? (reg as Array<Record<string, unknown>>) : []);
          setExtensions(list);
        }
      } catch {
        if (!cancelled) {
          if (section === "plugins") setPlugins([]);
          else setExtensions([]);
        }
      } finally {
        if (!cancelled) setListsLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [section]);

  const goSection = useCallback(
    (id: SettingsSection) => {
      setSection(id);
      setSearchParams({ section: id }, { replace: true });
      setSearchOpen(false);
      setSearch("");
    },
    [setSearchParams],
  );

  // ── Persist helpers ────────────────────────────────────────────────

  const flash = useCallback((msg: string) => {
    setStatus(msg);
    window.setTimeout(() => setStatus(""), 1800);
  }, []);

  const patchSettings = useCallback(
    async (patch: Record<string, unknown>, opts?: { quiet?: boolean }) => {
      const keys = Object.keys(patch);
      setSavingKeys((prev) => new Set([...prev, ...keys]));
      setError("");
      try {
        const next = (await aresApi.settingsPost(patch)) as Record<string, SettingValue>;
        setSettings((prev) => ({
          ...prev,
          ...next,
          ...(patch as Record<string, SettingValue>),
        }));
        if (!opts?.quiet) flash("Saved");
        return next;
      } catch (reason) {
        setError(readableError(reason, "Could not save settings."));
        throw reason;
      } finally {
        setSavingKeys((prev) => {
          const n = new Set(prev);
          keys.forEach((k) => n.delete(k));
          return n;
        });
      }
    },
    [flash],
  );

  const setBool = useCallback(
    (key: string, value: boolean) => {
      setSettings((prev) => ({ ...prev, [key]: value }));
      if (saveTimer.current) window.clearTimeout(saveTimer.current);
      saveTimer.current = window.setTimeout(() => {
        void patchSettings({ [key]: value });
      }, 200);
    },
    [patchSettings],
  );

  const setStr = useCallback(
    (key: string, value: string | number) => {
      setSettings((prev) => ({ ...prev, [key]: value }));
      if (saveTimer.current) window.clearTimeout(saveTimer.current);
      saveTimer.current = window.setTimeout(() => {
        void patchSettings({ [key]: value });
      }, 280);
    },
    [patchSettings],
  );

  async function applyThemeChoice(choice: ThemeChoice) {
    setPreference(choice);
    setSettings((prev) => ({ ...prev, theme: choice }));
    applyAppearanceToDocument({
      theme: choice,
      skin,
      fontSize,
      density,
      rtl: asBool(settings.rtl),
    });
    await patchSettings({ theme: choice });
  }

  async function applySkin(next: string) {
    setSettings((prev) => ({ ...prev, skin: next }));
    applyAppearanceToDocument({
      theme: themeChoice,
      skin: next,
      fontSize,
      density,
      rtl: asBool(settings.rtl),
    });
    await patchSettings({ skin: next });
  }

  async function applyFontSize(next: FontSize) {
    setSettings((prev) => ({ ...prev, font_size: next }));
    applyAppearanceToDocument({
      theme: themeChoice,
      skin,
      fontSize: next,
      density,
      rtl: asBool(settings.rtl),
    });
    await patchSettings({ font_size: next });
  }

  async function submitProfile(event: FormEvent) {
    event.preventDefault();
    setError("");
    try {
      await saveProfile(draft);
      await patchSettings(
        {
          owner_name: draft.displayName.trim(),
          bot_name: draft.assistantName.trim() || "Companion",
          local_profile_voice: draft.voice,
          local_profile_reachability: draft.reachability,
          local_profile_setup_mode: draft.setupMode,
          local_profile_character: draft.character,
          local_profile_autonomy: draft.autonomy,
          local_profile_life_areas: draft.lifeAreas,
          context_store_enabled: draft.contextStoreEnabled ?? false,
          show_cli_sessions: draft.includeExternalHistory ?? false,
        },
        { quiet: true },
      );
      setProfileSaved(true);
      flash("Profile saved");
      window.setTimeout(() => setProfileSaved(false), 1800);
    } catch (reason) {
      setError(readableError(reason, "Profile could not be saved."));
    }
  }

  // ── Conversation actions ───────────────────────────────────────────

  async function exportActive(format: "json" | "html" | "md") {
    if (!sessionId) return;
    setActionBusy(format);
    try {
      if (format === "md") {
        const lines = (activeSession?.messages || []).map((m) => {
          const role = m.role === "user" ? "You" : m.role === "assistant" ? "Assistant" : m.role;
          return `### ${role}\n\n${m.text || ""}\n`;
        });
        downloadBlob(
          `${sessionId}.md`,
          `# ${activeSession?.title || "Conversation"}\n\n${lines.join("\n")}`,
          "text/markdown",
        );
      } else {
        const body = await aresApi.exportSession(sessionId, format);
        const text = typeof body === "string" ? body : JSON.stringify(body, null, 2);
        downloadBlob(
          `${sessionId}.${format}`,
          text,
          format === "html" ? "text/html" : "application/json",
        );
      }
      flash(`Exported ${format.toUpperCase()}`);
    } catch (reason) {
      setError(readableError(reason, "Export failed."));
    } finally {
      setActionBusy("");
    }
  }

  async function shareActive() {
    if (!sessionId) return;
    setActionBusy("share");
    try {
      const res = await aresApi.createShare(sessionId);
      const url = res?.share?.url || "";
      if (url) {
        try {
          await navigator.clipboard.writeText(url);
          flash("Share link copied");
        } catch {
          flash(url);
        }
      } else {
        flash("Share created");
      }
    } catch (reason) {
      setError(readableError(reason, "Could not create share link."));
    } finally {
      setActionBusy("");
    }
  }

  async function stopShareActive() {
    if (!sessionId) return;
    setActionBusy("stop-share");
    try {
      await aresApi.revokeShare(sessionId);
      flash("Sharing stopped");
    } catch (reason) {
      setError(readableError(reason, "Could not revoke share."));
    } finally {
      setActionBusy("");
    }
  }

  async function clearActive() {
    if (!sessionId) return;
    if (!window.confirm("Clear all messages in this conversation? This cannot be undone.")) return;
    setActionBusy("clear");
    try {
      await aresApi.clearSession(sessionId);
      await refresh();
      flash("Conversation cleared");
    } catch (reason) {
      setError(readableError(reason, "Could not clear conversation."));
    } finally {
      setActionBusy("");
    }
  }

  async function onImportFile(file: File) {
    setActionBusy("import");
    try {
      const text = await file.text();
      const data = JSON.parse(text) as Record<string, unknown>;
      await aresApi.importSession(data);
      await refresh();
      flash("Session imported");
    } catch (reason) {
      setError(readableError(reason, "Import failed — expected a session JSON export."));
    } finally {
      setActionBusy("");
    }
  }

  // ── Auth ───────────────────────────────────────────────────────────

  async function setPassword() {
    if (!newPassword.trim()) return;
    setAuthBusy(true);
    setError("");
    try {
      await patchSettings({
        _set_password: newPassword,
        ...(currentPassword ? { _current_password: currentPassword } : {}),
      });
      setNewPassword("");
      setCurrentPassword("");
      flash("Password updated");
      await loadSettings();
    } catch (reason) {
      setError(readableError(reason, "Could not update password."));
    } finally {
      setAuthBusy(false);
    }
  }

  async function clearPassword() {
    if (!window.confirm("Disable password authentication?")) return;
    setAuthBusy(true);
    try {
      await patchSettings({
        _clear_password: true,
        ...(currentPassword ? { _current_password: currentPassword } : {}),
      });
      setCurrentPassword("");
      flash("Auth disabled");
      await loadSettings();
    } catch (reason) {
      setError(readableError(reason, "Could not disable auth."));
    } finally {
      setAuthBusy(false);
    }
  }

  // ── Search catalog ─────────────────────────────────────────────────

  const searchHits = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return [] as SearchHit[];
    const catalog: SearchHit[] = [
      { section: "conversation", label: "Export transcript", keywords: "export download markdown json html share clear import" },
      { section: "appearance", label: "Theme", keywords: "theme light dark system color scheme" },
      { section: "appearance", label: "Skin", keywords: "skin accent graphite slate poseidon" },
      { section: "appearance", label: "Font size", keywords: "font size accessibility large small" },
      {
        section: "appearance",
        label: "Island backdrop",
        keywords: "island backdrop wallpaper glass glassmorphism blur transparency background",
      },
      { section: "appearance", label: "Activity display", keywords: "worklog transparent stream tools thinking activity" },
      { section: "appearance", label: "Auto-follow", keywords: "scroll follow streaming" },
      { section: "appearance", label: "User markdown", keywords: "markdown user messages" },
      { section: "preferences", label: "You & Companion", keywords: "name identity profile autonomy reachability voice" },
      { section: "preferences", label: "Send key", keywords: "enter send keyboard composer" },
      { section: "preferences", label: "CLI history", keywords: "cli sessions external history privacy" },
      { section: "preferences", label: "TTS", keywords: "speech tts voice read aloud" },
      { section: "preferences", label: "Notifications", keywords: "sound notification browser" },
      { section: "connections", label: "Workers & models", keywords: "backend llm model connection worker hermes ollama openai" },
      { section: "plugins", label: "Plugins", keywords: "plugin hooks" },
      { section: "extensions", label: "Extensions", keywords: "extension gallery install" },
      { section: "system", label: "Password", keywords: "auth password access security" },
      { section: "system", label: "Updates", keywords: "version update channel" },
      { section: "system", label: "Advanced settings", keywords: "config raw keys advanced" },
      { section: "help", label: "Help", keywords: "docs product surfaces" },
    ];
    return catalog.filter((h) => h.label.toLowerCase().includes(q) || h.keywords.includes(q)).slice(0, 12);
  }, [search]);

  // ── Render sections ────────────────────────────────────────────────

  function renderConversation() {
    const title = activeSession?.title?.trim() || (sessionId ? sessionId : "No active conversation");
    return (
      <div className="grid gap-4">
        <div>
          <h3 className="text-lg font-semibold">Conversation</h3>
          <p className="text-sm text-muted-foreground">
            {sessionId ? (
              <>
                Active: <span className="text-foreground">{title}</span>
                {activeSession?.messageCount != null ? ` · ${activeSession.messageCount} messages` : ""}
              </>
            ) : (
              "No active conversation selected — open Chat and pick a session."
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
    );
  }

  function renderAppearance() {
    return (
      <div className="grid gap-6">
        <div>
          <h3 className="text-lg font-semibold">Appearance</h3>
          <p className="text-sm text-muted-foreground">Theme, accent skins, and chat visual behavior.</p>
        </div>

        <Field label="Theme" description={`Active: ${theme}${themeChoice === "system" ? " (following OS)" : ""}.`}>
          <ChoiceGrid
            value={themeChoice}
            onChange={(id) => void applyThemeChoice(id)}
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
            onChange={(id) => void applyFontSize(id)}
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

        <Field
          label="Activity display"
          description="How tool and thinking activity appears while workers run."
        >
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

        <Field
          label="JSON / YAML code blocks"
          description="How structured code fences open by default."
        >
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

  function renderPreferences() {
    return (
      <div className="grid gap-6">
        <div>
          <h3 className="text-lg font-semibold">Preferences</h3>
          <p className="text-sm text-muted-foreground">
            Identity, chat defaults, privacy, and voice — agent-agnostic.
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>You & Companion</CardTitle>
            <CardDescription>Local profile owned by ARES even when no worker is connected.</CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={(e) => void submitProfile(e)} className="grid gap-4 sm:grid-cols-2">
              <div className="grid gap-2">
                <Label htmlFor="display-name">What should your SI call you?</Label>
                <Input
                  id="display-name"
                  value={draft.displayName}
                  onChange={(e) => setDraft({ ...draft, displayName: e.target.value })}
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="assistant-name">Companion name</Label>
                <Input
                  id="assistant-name"
                  value={draft.assistantName}
                  onChange={(e) => setDraft({ ...draft, assistantName: e.target.value })}
                />
              </div>
              <div className="grid gap-2">
                <Label>Voice</Label>
                <Select value={draft.voice} onValueChange={(voice) => setDraft({ ...draft, voice })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="system-default">System default</SelectItem>
                    <SelectItem value="disabled">Disabled</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label>Reachability</Label>
                <Select
                  value={draft.reachability}
                  onValueChange={(reachability: LocalProfile["reachability"]) =>
                    setDraft({ ...draft, reachability })
                  }
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="this-device">This device</SelectItem>
                    <SelectItem value="local-network">Local network</SelectItem>
                    <SelectItem value="private-network">Private network</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label>Autonomy</Label>
                <Select
                  value={draft.autonomy}
                  onValueChange={(autonomy: LocalProfile["autonomy"]) => setDraft({ ...draft, autonomy })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="observe">Observe only</SelectItem>
                    <SelectItem value="confirm">Confirm before acting</SelectItem>
                    <SelectItem value="delegated">Delegated</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label>Character</Label>
                <Select
                  value={draft.character}
                  onValueChange={(character: LocalProfile["character"]) => setDraft({ ...draft, character })}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="grounded">Grounded</SelectItem>
                    <SelectItem value="warm">Warm</SelectItem>
                    <SelectItem value="direct">Direct</SelectItem>
                    <SelectItem value="curious">Curious</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="sm:col-span-2">
                <Button type="submit">
                  {profileSaved ? <Check /> : null}
                  {profileSaved ? "Saved" : "Save profile"}
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>

        <div className="grid gap-2">
          <h4 className="text-sm font-semibold">Chat & composer</h4>
          <Field label="Send key" description="How Enter behaves in the composer.">
            <Select
              value={asString(settings.send_key, "enter")}
              onValueChange={(v) => setStr("send_key", v)}
            >
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
          <h4 className="text-sm font-semibold">Privacy & history</h4>
          <ToggleField
            id="context_store_enabled"
            label="Enable Context Store"
            description="Local memory so Companion can recall engineering context."
            checked={asBool(settings.context_store_enabled, draft.contextStoreEnabled ?? false)}
            onChange={(v) => {
              setBool("context_store_enabled", v);
              setDraft((d) => ({ ...d, contextStoreEnabled: v }));
            }}
          />
          <ToggleField
            id="show_cli_sessions"
            label="Include external AI history"
            description="Show CLI-discovered conversations. Off by default for privacy."
            checked={asBool(settings.show_cli_sessions, draft.includeExternalHistory ?? false)}
            onChange={(v) => {
              setBool("show_cli_sessions", v);
              setDraft((d) => ({ ...d, includeExternalHistory: v }));
            }}
          />
          <ToggleField
            id="show_claude_code_sessions"
            label="Show Claude Code sessions"
            description="Within external history, include Claude Code imports."
            checked={asBool(settings.show_claude_code_sessions, true)}
            onChange={(v) => setBool("show_claude_code_sessions", v)}
            disabled={!asBool(settings.show_cli_sessions)}
          />
          <ToggleField
            id="show_cron_sessions"
            label="Show schedule/cron sessions"
            description="Surface scheduled job runs as conversations."
            checked={asBool(settings.show_cron_sessions)}
            onChange={(v) => setBool("show_cron_sessions", v)}
            disabled={!asBool(settings.show_cli_sessions)}
          />
          <ToggleField
            id="show_webhook_sessions"
            label="Show webhook sessions"
            description="Surface webhook runs in the deck."
            checked={asBool(settings.show_webhook_sessions)}
            onChange={(v) => setBool("show_webhook_sessions", v)}
            disabled={!asBool(settings.show_cli_sessions)}
          />
          <ToggleField
            id="show_previous_messaging_sessions"
            label="Show previous messaging sessions"
            description="Older Discord/Telegram/etc. reset segments."
            checked={asBool(settings.show_previous_messaging_sessions)}
            onChange={(v) => setBool("show_previous_messaging_sessions", v)}
          />
          <ToggleField
            id="api_redact_enabled"
            label="Redact secrets in API responses"
            description="Strip keys and secrets from API payloads (recommended on)."
            checked={asBool(settings.api_redact_enabled, true)}
            onChange={(v) => setBool("api_redact_enabled", v)}
          />
          <ToggleField
            id="sync_to_insights"
            label="Sync usage to insights"
            description="Mirror WebUI token usage into insights storage."
            checked={asBool(settings.sync_to_insights)}
            onChange={(v) => setBool("sync_to_insights", v)}
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

        <div className="grid gap-2">
          <h4 className="text-sm font-semibold">Updates</h4>
          <ToggleField
            id="check_for_updates"
            label="Check for updates"
            description="Banner when newer WebUI releases are available."
            checked={asBool(settings.check_for_updates, true)}
            onChange={(v) => setBool("check_for_updates", v)}
          />
          <Field label="Update channel">
            <Select
              value={asString(settings.update_channel, "stable")}
              onValueChange={(v) => setStr("update_channel", v)}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="stable">Stable</SelectItem>
                <SelectItem value="experimental">Experimental</SelectItem>
              </SelectContent>
            </Select>
          </Field>
          <ToggleField
            id="ignore_agent_updates"
            label="Ignore agent updates"
            description="Keep WebUI checks; hide agent-specific update notices."
            checked={asBool(settings.ignore_agent_updates)}
            onChange={(v) => setBool("ignore_agent_updates", v)}
          />
          <ToggleField
            id="whats_new_summary_enabled"
            label="Summarize What's New with AI"
            checked={asBool(settings.whats_new_summary_enabled)}
            onChange={(v) => setBool("whats_new_summary_enabled", v)}
          />
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <AppWindow className="size-4" />
              Mac app & menu bar
            </CardTitle>
            <CardDescription>Device-local hints for the native ARES Mac app.</CardDescription>
          </CardHeader>
          <CardContent>
            <ToggleField
              id="menubar-hints"
              label="Menu bar presence"
              description="Prefer showing ARES in the menu bar when the Mac app is installed."
              checked={menubarHints}
              onChange={setMenubarHints}
            />
          </CardContent>
        </Card>
      </div>
    );
  }

  function renderConnections() {
    const backends = snapshot.backends || [];
    const connections = snapshot.connections || [];
    return (
      <div className="grid gap-4">
        <div>
          <h3 className="text-lg font-semibold">Connections</h3>
          <p className="text-sm text-muted-foreground">
            Workers and LLM runtimes are agent-agnostic. Configure adapters, models, and defaults on the
            Connections surface — not Hermes-only.
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          <Button asChild>
            <Link to="/connections">
              <Cable />
              Open Connections
              <ExternalLink className="size-3.5 opacity-70" />
            </Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/secrets">
              <KeyRound />
              Secrets / API keys
            </Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/mcp">
              <Plug />
              MCP servers
            </Link>
          </Button>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">API</CardTitle>
              <CardDescription>
                {snapshot.connection}
                {snapshot.settings?.version ? ` · ${snapshot.settings.version}` : ""}
              </CardDescription>
            </CardHeader>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Backends</CardTitle>
              <CardDescription>
                {backends.length} discovered · {backends.filter((b) => b.available).length} available
              </CardDescription>
            </CardHeader>
          </Card>
        </div>

        <div className="grid gap-2">
          <h4 className="text-sm font-semibold">Discovered workers</h4>
          {backends.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No backends discovered yet. Open Connections to scan and select a default runtime.
            </p>
          ) : (
            <div className="grid gap-2">
              {backends.slice(0, 12).map((b) => (
                <div
                  key={b.id}
                  className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2 text-sm"
                >
                  <div className="min-w-0">
                    <p className="truncate font-medium">{b.name || b.id}</p>
                    <p className="truncate font-mono text-[11px] text-muted-foreground">{b.id}</p>
                  </div>
                  <Badge variant={b.available ? "outline" : "secondary"}>
                    {b.available ? "Available" : "Unavailable"}
                  </Badge>
                </div>
              ))}
            </div>
          )}
        </div>

        {connections.length > 0 && (
          <div className="grid gap-2">
            <h4 className="text-sm font-semibold">Runtime connections</h4>
            <div className="grid gap-2">
              {connections.slice(0, 8).map((c) => (
                <div
                  key={c.id}
                  className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2 text-sm"
                >
                  <div className="min-w-0">
                    <p className="truncate font-medium">{c.name}</p>
                    <p className="truncate text-[11px] text-muted-foreground">{c.detail || c.kind}</p>
                  </div>
                  <Badge variant="secondary">{c.state}</Badge>
                </div>
              ))}
            </div>
          </div>
        )}

        <p className="text-xs text-muted-foreground">
          Per-conversation model selection stays in the Chat composer. Defaults and credentials live under
          Connections / Secrets so any adapter (Hermes, Ollama, OpenAI-compatible, CLI workers, …) can be
          wired the same way.
        </p>
      </div>
    );
  }

  function renderPlugins() {
    return (
      <div className="grid gap-4">
        <div>
          <h3 className="text-lg font-semibold">Plugins</h3>
          <p className="text-sm text-muted-foreground">
            Installed agent plugins and lifecycle hooks. Read-only inventory — enablement is owned by each
            adapter/runtime.
          </p>
        </div>
        {listsLoading ? (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <LoaderCircle className="size-4 animate-spin" /> Loading plugins…
          </div>
        ) : plugins.length === 0 ? (
          <p className="text-sm text-muted-foreground">No plugins reported by the running ARES service.</p>
        ) : (
          <div className="grid gap-2">
            {plugins.map((p, i) => {
              const name = String(p.name || p.id || `plugin-${i}`);
              const desc = String(p.description || p.summary || "");
              return (
                <div key={name} className="rounded-lg border px-3 py-2">
                  <p className="text-sm font-medium">{name}</p>
                  {desc ? <p className="text-xs text-muted-foreground">{desc}</p> : null}
                </div>
              );
            })}
          </div>
        )}
      </div>
    );
  }

  function renderExtensions() {
    return (
      <div className="grid gap-4">
        <div>
          <h3 className="text-lg font-semibold">Extensions</h3>
          <p className="text-sm text-muted-foreground">
            WebUI extensions run in the browser origin and can reach the same APIs as this session. Only
            load trusted packages.
          </p>
        </div>
        {extStatus && (
          <p className="text-xs text-muted-foreground font-mono">
            Status: {JSON.stringify(extStatus).slice(0, 180)}
            {JSON.stringify(extStatus).length > 180 ? "…" : ""}
          </p>
        )}
        {listsLoading ? (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <LoaderCircle className="size-4 animate-spin" /> Loading extensions…
          </div>
        ) : extensions.length === 0 ? (
          <p className="text-sm text-muted-foreground">No extensions in the registry.</p>
        ) : (
          <div className="grid gap-2">
            {extensions.map((ext, i) => {
              const id = String(ext.id || ext.name || `ext-${i}`);
              const enabled = asBool(ext.enabled ?? ext.user_enabled, true);
              return (
                <div key={id} className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{String(ext.name || id)}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {String(ext.description || id)}
                    </p>
                  </div>
                  <ToggleSwitch
                    checked={enabled}
                    onCheckedChange={(v) => {
                      void aresApi
                        .toggleExtension(id, v)
                        .then(() => {
                          setExtensions((prev) =>
                            prev.map((e) =>
                              String(e.id || e.name) === id
                                ? { ...e, enabled: v, user_enabled: v }
                                : e,
                            ),
                          );
                          flash(v ? "Extension enabled" : "Extension disabled");
                        })
                        .catch((reason) =>
                          setError(readableError(reason, "Could not toggle extension.")),
                        );
                    }}
                  />
                </div>
              );
            })}
          </div>
        )}
      </div>
    );
  }

  function renderSystem() {
    const authEnabled = asBool(settings.auth_enabled);
    const passwordAuth = asBool(settings.password_auth_enabled);
    const envLocked = asBool(settings.password_env_var);
    return (
      <div className="grid gap-6">
        <div>
          <h3 className="text-lg font-semibold">System</h3>
          <p className="text-sm text-muted-foreground">Instance version, access controls, and advanced keys.</p>
        </div>

        <div className="flex flex-wrap gap-2">
          <Badge variant="outline">WebUI: {asString(settings.webui_version, "—")}</Badge>
          <Badge variant="outline">Agent: {asString(settings.agent_version, "not detected")}</Badge>
          {settings.update_channel_version != null && (
            <Badge variant="secondary">{String(settings.update_channel_version)}</Badge>
          )}
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Shield className="size-4" />
              Access password
            </CardTitle>
            <CardDescription>
              {envLocked
                ? "ARES_WEBUI_PASSWORD is set in the environment and overrides UI password changes."
                : authEnabled
                  ? passwordAuth
                    ? "Password authentication is enabled."
                    : "Auth is enabled (passkey / other)."
                  : "This instance is currently accessible without authentication."}
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-3">
            {!authEnabled && (
              <div className="rounded-md border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-xs text-amber-800 dark:text-amber-200">
                Unauthenticated access — anyone who can reach this host can use ARES.
              </div>
            )}
            {passwordAuth && (
              <div className="grid gap-2">
                <Label htmlFor="current-password">Current password</Label>
                <Input
                  id="current-password"
                  type="password"
                  autoComplete="current-password"
                  value={currentPassword}
                  onChange={(e) => setCurrentPassword(e.target.value)}
                  disabled={envLocked}
                />
              </div>
            )}
            <div className="grid gap-2">
              <Label htmlFor="new-password">New password</Label>
              <Input
                id="new-password"
                type="password"
                autoComplete="new-password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                disabled={envLocked}
                placeholder="Enter new password…"
              />
            </div>
            <div className="flex flex-wrap gap-2">
              <Button type="button" disabled={envLocked || authBusy || !newPassword.trim()} onClick={() => void setPassword()}>
                {authBusy ? <LoaderCircle className="animate-spin" /> : <KeyRound />}
                Set password
              </Button>
              {passwordAuth && (
                <Button type="button" variant="outline" disabled={envLocked || authBusy} onClick={() => void clearPassword()}>
                  Disable auth
                </Button>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Advanced settings</CardTitle>
            <CardDescription>
              Raw key editor for every persisted preference. Prefer the curated sections above when possible.
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            <Button asChild variant="outline">
              <Link to="/config">
                <SlidersHorizontal />
                Open advanced settings
              </Link>
            </Button>
            <Button asChild variant="outline">
              <Link to="/system">
                <Monitor />
                System surface
              </Link>
            </Button>
            <Button type="button" variant="outline" onClick={() => void loadSettings()}>
              <RefreshCw />
              Reload settings
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  function renderHelp() {
    return (
      <div className="grid gap-4">
        <div>
          <h3 className="text-lg font-semibold">Help</h3>
          <p className="text-sm text-muted-foreground">
            ARES is agent-agnostic: Chat is a pure worker console; Companion owns SI identity and context.
          </p>
        </div>
        <div className="grid gap-2 sm:grid-cols-2">
          <Button asChild variant="outline" className="justify-start h-auto py-3">
            <Link to="/companion">
              <BookOpen />
              <span className="text-left">
                <span className="block font-medium">Companion</span>
                <span className="block text-xs text-muted-foreground">SI home & identity</span>
              </span>
            </Link>
          </Button>
          <Button asChild variant="outline" className="justify-start h-auto py-3">
            <Link to="/chat">
              <MessageSquare />
              <span className="text-left">
                <span className="block font-medium">Chat</span>
                <span className="block text-xs text-muted-foreground">Worker console</span>
              </span>
            </Link>
          </Button>
          <Button asChild variant="outline" className="justify-start h-auto py-3">
            <Link to="/connections">
              <Cable />
              <span className="text-left">
                <span className="block font-medium">Connections</span>
                <span className="block text-xs text-muted-foreground">LLMs, workers, defaults</span>
              </span>
            </Link>
          </Button>
          <Button asChild variant="outline" className="justify-start h-auto py-3">
            <Link to="/system">
              <Server />
              <span className="text-left">
                <span className="block font-medium">System</span>
                <span className="block text-xs text-muted-foreground">Health & infrastructure</span>
              </span>
            </Link>
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          Official Hermes “dashboard mode” is intentionally not offered — ARES is multi-runtime and does
          not assume a single agent product.
        </p>
      </div>
    );
  }

  const body = (() => {
    switch (section) {
      case "conversation":
        return renderConversation();
      case "appearance":
        return renderAppearance();
      case "preferences":
        return renderPreferences();
      case "connections":
        return renderConnections();
      case "plugins":
        return renderPlugins();
      case "extensions":
        return renderExtensions();
      case "system":
        return renderSystem();
      case "help":
        return renderHelp();
      default:
        return null;
    }
  })();

  return (
    <div className="page-stack settings-hub">
      <PageHeader
        title="App settings"
        description="Hermes-style control plane adapted for ARES: agent-agnostic connections, curated chat prefs, and Local Profile identity."
        action={
          status || savingKeys.size ? (
            <Badge variant="secondary" className="font-normal">
              {savingKeys.size ? "Saving…" : status}
            </Badge>
          ) : undefined
        }
      />

      {error ? (
        <p className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive" role="alert">
          {error}
        </p>
      ) : null}

      <div className="settings-layout">
        {/* Side menu */}
        <aside className="settings-side">
          <div className="relative mb-3">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setSearchOpen(true);
              }}
              onFocus={() => setSearchOpen(true)}
              onBlur={() => window.setTimeout(() => setSearchOpen(false), 150)}
              placeholder="Search settings…"
              className="pl-8"
              aria-label="Search settings"
            />
            {searchOpen && searchHits.length > 0 && (
              <div className="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-md border bg-popover p-1 shadow-lg">
                {searchHits.map((hit) => (
                  <button
                    key={`${hit.section}-${hit.label}`}
                    type="button"
                    className="flex w-full flex-col items-start rounded-sm px-2 py-1.5 text-left text-xs hover:bg-accent"
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => goSection(hit.section)}
                  >
                    <span className="font-medium text-foreground">{hit.label}</span>
                    <span className="text-[10px] uppercase tracking-wide text-muted-foreground">
                      {SECTIONS.find((s) => s.id === hit.section)?.label}
                    </span>
                  </button>
                ))}
              </div>
            )}
          </div>

          <nav className="settings-side-nav" aria-label="Settings sections">
            {SECTIONS.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => goSection(id)}
                className={cn(
                  "settings-side-item",
                  section === id && "is-active",
                )}
              >
                <Icon className="size-4 shrink-0" />
                <span>{label}</span>
              </button>
            ))}
          </nav>
        </aside>

        {/* Main pane */}
        <main className="settings-main min-w-0">
          {loading ? (
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

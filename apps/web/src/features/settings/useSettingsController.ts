import { useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";

import { useTheme } from "@/context/ThemeContext";
import {
  applySettings as applyIslandSettings,
  readSettings as readIslandSettings,
  writeSettings as writeIslandSettings,
  type IslandBackdropSettings,
} from "@/island-backdrop";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";

import { normalizeSettingsSection } from "./constants";
import {
  applyAppearanceToDocument,
  asBool,
  asString,
  downloadBlob,
  readDensity,
  SKINS,
  WEBUI_DENSITY_KEY,
} from "./helpers";
import type { Density, FontSize, SettingValue, SettingsSectionId, ThemeChoice } from "./types";

export function useSettingsController() {
  const { snapshot, currentSession, refresh, selectedSessionId } = useAres();
  const { theme, preference, setPreference } = useTheme();
  const [searchParams, setSearchParams] = useSearchParams();

  const sectionParam = searchParams.get("section");
  const [section, setSection] = useState<SettingsSectionId>(() => normalizeSettingsSection(sectionParam));
  const [settings, setSettings] = useState<Record<string, SettingValue>>({});
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");
  const [savingKeys, setSavingKeys] = useState<Set<string>>(new Set());

  const [density, setDensity] = useState<Density>(() => readDensity());
  const [island, setIsland] = useState<IslandBackdropSettings>(() => readIslandSettings());

  const updateIsland = useCallback((patch: Partial<IslandBackdropSettings>) => {
    setIsland((current) => {
      const next = { ...current, ...patch };
      applyIslandSettings(next);
      writeIslandSettings(next);
      return next;
    });
  }, []);

  const [newPassword, setNewPassword] = useState("");
  const [currentPassword, setCurrentPassword] = useState("");
  const [authBusy, setAuthBusy] = useState(false);

  const [plugins, setPlugins] = useState<Array<Record<string, unknown>>>([]);
  const [extensions, setExtensions] = useState<Array<Record<string, unknown>>>([]);
  const [extStatus, setExtStatus] = useState<Record<string, unknown> | null>(null);
  const [listsLoading, setListsLoading] = useState(false);

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
    const next = normalizeSettingsSection(sectionParam);
    if (next !== section) setSection(next);
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
    if (section !== "app") return;
    let cancelled = false;
    setListsLoading(true);
    void (async () => {
      try {
        const [pluginRes, reg, st] = await Promise.all([
          aresApi.listPlugins().catch(() => ({ plugins: [] as Array<Record<string, unknown>> })),
          aresApi.listExtensions().catch(() => ({})),
          aresApi.extensionStatus().catch(() => ({})),
        ]);
        if (cancelled) return;
        setPlugins(Array.isArray(pluginRes.plugins) ? pluginRes.plugins : []);
        setExtStatus(st);
        const list =
          (Array.isArray((reg as { extensions?: unknown[] }).extensions) &&
            (reg as { extensions: Array<Record<string, unknown>> }).extensions) ||
          (Array.isArray((reg as { items?: unknown[] }).items) &&
            (reg as { items: Array<Record<string, unknown>> }).items) ||
          (Array.isArray(reg) ? (reg as Array<Record<string, unknown>>) : []);
        setExtensions(list);
      } catch {
        if (!cancelled) {
          setPlugins([]);
          setExtensions([]);
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
    (id: SettingsSectionId) => {
      setSection(id);
      setSearchParams({ section: id }, { replace: true });
    },
    [setSearchParams],
  );

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

  return {
    snapshot,
    activeSession,
    sessionId,
    section,
    goSection,
    settings,
    setSettings,
    loading,
    status,
    error,
    setError,
    savingKeys,
    density,
    setDensity,
    island,
    updateIsland,
    newPassword,
    setNewPassword,
    currentPassword,
    setCurrentPassword,
    authBusy,
    plugins,
    extensions,
    setExtensions,
    extStatus,
    listsLoading,
    actionBusy,
    importRef,
    theme,
    themeChoice,
    fontSize,
    skin,
    loadSettings,
    patchSettings,
    setBool,
    setStr,
    applyThemeChoice,
    applySkin,
    applyFontSize,
    exportActive,
    shareActive,
    stopShareActive,
    clearActive,
    onImportFile,
    setPassword,
    clearPassword,
    flash,
  };
}

export type SettingsController = ReturnType<typeof useSettingsController>;

import { useCallback, useEffect, useRef, useState } from "react";

import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import type { NativeSystemSettingsPatch, NativeSystemStatus } from "@/shared/system-settings-contract";

export function useSystemSettings() {
  const [system, setSystem] = useState<NativeSystemStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const mounted = useRef(true);

  const refresh = useCallback(async (quiet = false) => {
    if (!quiet) setLoading(true);
    try {
      const next = await aresApi.nativeSystemGet();
      if (mounted.current) {
        setSystem(next);
        setError("");
      }
    } catch (reason) {
      if (mounted.current && !quiet) {
        setError(readableError(reason, "Could not load native ARES status."));
      }
    } finally {
      if (mounted.current && !quiet) setLoading(false);
    }
  }, []);

  useEffect(() => {
    mounted.current = true;
    void refresh();
    const timer = window.setInterval(() => void refresh(true), 2_000);
    return () => {
      mounted.current = false;
      window.clearInterval(timer);
    };
  }, [refresh]);

  const update = useCallback(async (key: string, patch: NativeSystemSettingsPatch) => {
    setBusy(key);
    setError("");
    try {
      const next = await aresApi.nativeSystemPatch(patch);
      if (mounted.current) setSystem(next);
    } catch (reason) {
      if (mounted.current) setError(readableError(reason, "Native setting was not changed."));
    } finally {
      if (mounted.current) setBusy("");
    }
  }, []);

  const restartServer = useCallback(async () => {
    setBusy("restart_server");
    setError("");
    try {
      await aresApi.nativeSystemAction("restart_server");
      window.setTimeout(() => void refresh(true), 2_000);
    } catch (reason) {
      if (mounted.current) setError(readableError(reason, "ARES could not request a controller restart."));
    } finally {
      if (mounted.current) setBusy("");
    }
  }, [refresh]);

  return { system, loading, busy, error, refresh, update, restartServer };
}

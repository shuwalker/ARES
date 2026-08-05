import { useCallback, useEffect, useState } from "react";

import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import type { CompanionStatus } from "@/shared/companion-contract";

export function useCompanionSettings() {
  const [status, setStatus] = useState<CompanionStatus | null>(null);
  const [ownerName, setOwnerName] = useState("");
  const [name, setName] = useState("");
  const [characterId, setCharacterId] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(false);

  const apply = useCallback((next: CompanionStatus) => {
    setStatus(next);
    setOwnerName(next.relationship.owner_name);
    setName(next.agent.name);
    setCharacterId(next.character.id);
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      apply(await aresApi.companionGet());
    } catch (reason) {
      setError(readableError(reason, "Could not connect to your JaegerAI Companion."));
    } finally {
      setLoading(false);
    }
  }, [apply]);

  useEffect(() => {
    void load();
  }, [load]);

  const save = useCallback(async () => {
    setSaving(true);
    setError("");
    try {
      const next = await aresApi.companionPatch({
        name: name.trim(),
        owner_name: ownerName.trim(),
        character_id: characterId,
      });
      apply(next);
      setSaved(true);
      window.setTimeout(() => setSaved(false), 1800);
    } catch (reason) {
      setError(readableError(reason, "Companion settings could not be saved."));
    } finally {
      setSaving(false);
    }
  }, [apply, characterId, name, ownerName]);

  return {
    status,
    ownerName,
    setOwnerName,
    name,
    setName,
    characterId,
    setCharacterId,
    loading,
    saving,
    error,
    saved,
    load,
    save,
  };
}

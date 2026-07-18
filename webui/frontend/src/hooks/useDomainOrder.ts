import { useCallback, useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { Domain } from "@paperclipai/shared";
import { sidebarPreferencesApi } from "../api/sidebarPreferences";
import { queryKeys } from "../lib/queryKeys";

function areEqual(a: string[], b: string[]) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i += 1) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function sortDomainsByOrder(domains: Domain[], orderedIds: string[]): Domain[] {
  if (domains.length === 0) return [];
  if (orderedIds.length === 0) return domains;

  const byId = new Map(domains.map((domain) => [domain.id, domain]));
  const sorted: Domain[] = [];

  for (const id of orderedIds) {
    const domain = byId.get(id);
    if (!domain) continue;
    sorted.push(domain);
    byId.delete(id);
  }
  for (const domain of byId.values()) {
    sorted.push(domain);
  }
  return sorted;
}

function buildOrderIds(domains: Domain[], orderedIds: string[]) {
  return sortDomainsByOrder(domains, orderedIds).map((domain) => domain.id);
}

type UseDomainOrderParams = {
  domains: Domain[];
  userId: string | null | undefined;
};

export function useDomainOrder({ domains, userId }: UseDomainOrderParams) {
  const queryClient = useQueryClient();
  const queryKey = useMemo(
    () => queryKeys.sidebarPreferences.domainOrder(userId ?? "__anon__"),
    [userId],
  );

  const { data } = useQuery({
    queryKey,
    queryFn: () => sidebarPreferencesApi.getDomainOrder(),
    enabled: Boolean(userId),
  });

  const [orderedIds, setOrderedIds] = useState<string[]>(() => buildOrderIds(domains, []));

  useEffect(() => {
    const nextIds = buildOrderIds(domains, data?.orderedIds ?? []);
    setOrderedIds((current) => (areEqual(current, nextIds) ? current : nextIds));
  }, [domains, data?.orderedIds]);

  const mutation = useMutation({
    mutationFn: (nextIds: string[]) => sidebarPreferencesApi.updateDomainOrder({ orderedIds: nextIds }),
    onSuccess: (preference) => {
      queryClient.setQueryData(queryKey, preference);
    },
  });

  const orderedDomains = useMemo(
    () => sortDomainsByOrder(domains, orderedIds),
    [domains, orderedIds],
  );

  const persistOrder = useCallback(
    (ids: string[]) => {
      const idSet = new Set(domains.map((domain) => domain.id));
      const filtered = ids.filter((id) => idSet.has(id));
      for (const domain of domains) {
        if (!filtered.includes(domain.id)) filtered.push(domain.id);
      }

      setOrderedIds((current) => (areEqual(current, filtered) ? current : filtered));
      if (!userId) return;

      queryClient.setQueryData(queryKey, (current: { orderedIds?: string[]; updatedAt?: Date | null } | undefined) => ({
        orderedIds: filtered,
        updatedAt: current?.updatedAt ?? null,
      }));
      mutation.mutate(filtered);
    },
    [domains, mutation, queryClient, queryKey, userId],
  );

  return {
    orderedDomains,
    orderedIds,
    persistOrder,
  };
}

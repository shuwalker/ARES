const STORAGE_PREFIX = "paperclip:recent-searches:";
const MAX_RECENT_SEARCHES = 5;

function storageKey(domainId: string) {
  return `${STORAGE_PREFIX}${domainId}`;
}

function isStorageAvailable() {
  return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
}

export function loadRecentSearches(domainId: string): string[] {
  if (!isStorageAvailable() || !domainId) return [];
  try {
    const raw = window.localStorage.getItem(storageKey(domainId));
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    const cleaned: string[] = [];
    for (const value of parsed) {
      if (typeof value !== "string") continue;
      const trimmed = value.trim();
      if (!trimmed) continue;
      cleaned.push(trimmed);
      if (cleaned.length >= MAX_RECENT_SEARCHES) break;
    }
    return cleaned;
  } catch {
    return [];
  }
}

export function pushRecentSearch(domainId: string, query: string): string[] {
  if (!isStorageAvailable() || !domainId) return [];
  const trimmed = query.trim();
  if (!trimmed) return loadRecentSearches(domainId);
  const existing = loadRecentSearches(domainId);
  const filtered = existing.filter((entry) => entry.toLowerCase() !== trimmed.toLowerCase());
  const next = [trimmed, ...filtered].slice(0, MAX_RECENT_SEARCHES);
  try {
    window.localStorage.setItem(storageKey(domainId), JSON.stringify(next));
  } catch {
    // ignore
  }
  return next;
}

export function clearRecentSearches(domainId: string): void {
  if (!isStorageAvailable() || !domainId) return;
  try {
    window.localStorage.removeItem(storageKey(domainId));
  } catch {
    // ignore
  }
}

export const RECENT_SEARCHES_LIMIT = MAX_RECENT_SEARCHES;

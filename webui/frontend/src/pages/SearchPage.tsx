import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import {
  Search,
  X,
  Clock,
  MessageCircle,
  FileText,
  Sparkles,
  LoaderCircle,
  ArrowRight,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { EmptyState } from "@/components/EmptyState";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { useAres } from "@/shared/ares-context";
import { aresApi } from "@/shared/ares-api";
import type { SessionSearchResult } from "@/shared/ares-api";
import { readableError } from "@/shared/api-client";

// ── localStorage helpers for search history ──────────────────────────────
const HISTORY_KEY = "ares.search.recent";
const MAX_HISTORY = 12;

function loadRecentSearches(): string[] {
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function pushRecentSearch(query: string): string[] {
  const trimmed = query.trim();
  if (!trimmed) return loadRecentSearches();
  const prev = loadRecentSearches().filter((q) => q !== trimmed);
  const next = [trimmed, ...prev].slice(0, MAX_HISTORY);
  try {
    localStorage.setItem(HISTORY_KEY, JSON.stringify(next));
  } catch {
    // Storage full or unavailable — best-effort.
  }
  return next;
}

function clearRecentSearches(): string[] {
  try {
    localStorage.removeItem(HISTORY_KEY);
  } catch {
    // No-op.
  }
  return [];
}

// ── Scope / filter chip definitions ──────────────────────────────────────
type SearchScope = "all" | "sessions" | "messages" | "workspaces";

const SCOPE_CONFIG: Record<SearchScope, { label: string; icon: typeof Search }> = {
  all: { label: "All", icon: Search },
  sessions: { label: "Sessions", icon: MessageCircle },
  messages: { label: "Messages", icon: FileText },
  workspaces: { label: "Workspaces", icon: Sparkles },
};

const SCOPE_KEYS: SearchScope[] = ["all", "sessions", "messages", "workspaces"];

// ── Snippet highlighter ─────────────────────────────────────────────────
function HighlightedSnippet({ text, query }: { text: string; query: string }) {
  if (!query.trim()) return <>{text}</>;
  const regex = new RegExp(`(${query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi");
  const parts = text.split(regex);
  return (
    <>
      {parts.map((part, i) =>
        regex.test(part) ? (
          <mark key={i} className="rounded-sm bg-primary/20 text-foreground px-0.5">
            {part}
          </mark>
        ) : (
          part
        ),
      )}
    </>
  );
}

// ── Result row ──────────────────────────────────────────────────────────
function SearchResultRow({
  result,
  query,
}: {
  result: SessionSearchResult;
  query: string;
}) {
  const title = result.title || "Untitled session";
  const snippet = result.snippet || "";
  const timeAgo = result.updated_at ? timeSince(new Date(result.updated_at)) : "";

  return (
    <Link
      to="/conversation"
      className="flex items-start gap-3 rounded-md border bg-card px-4 py-3 transition-colors hover:border-foreground/20 hover:shadow-sm"
    >
      <MessageCircle className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-medium">{title}</span>
          {result.message_count != null && (
            <Badge variant="outline" className="shrink-0 text-(length:--text-nano)">
              {result.message_count} msgs
            </Badge>
          )}
        </div>
        {snippet && (
          <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">
            <HighlightedSnippet text={snippet} query={query} />
          </p>
        )}
      </div>
      {timeAgo && (
        <span className="shrink-0 text-xs text-muted-foreground">{timeAgo}</span>
      )}
    </Link>
  );
}

// ── Relative time ───────────────────────────────────────────────────────
function timeSince(date: Date): string {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  return date.toLocaleDateString();
}

// ── Main SearchPage ─────────────────────────────────────────────────────
export function SearchPage() {
  const { snapshot, selectSession } = useAres();
  const [query, setQuery] = useState("");
  const [scope, setScope] = useState<SearchScope>("all");
  const [results, setResults] = useState<SessionSearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [recentSearches, setRecentSearches] = useState<string[]>(loadRecentSearches);
  const inputRef = useRef<HTMLInputElement>(null);

  const trimmedQuery = query.trim();

  // Debounced search
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (!trimmedQuery) {
      setResults([]);
      setSearching(false);
      setError(null);
      return;
    }
    setSearching(true);
    setError(null);
    if (searchTimer.current) clearTimeout(searchTimer.current);
    searchTimer.current = setTimeout(async () => {
      try {
        const data = await aresApi.searchSessions(trimmedQuery, {
          content: scope === "messages" || scope === "all",
          depth: scope === "messages" ? 2 : 1,
        });
        let filtered = data;
        if (scope === "sessions") {
          filtered = data;
        } else if (scope === "workspaces") {
          filtered = data.filter((r) =>
            snapshot.workspaces.some(
              (w) => r.title?.toLowerCase().includes(w.label?.toLowerCase() ?? ""),
            ),
          );
        }
        setResults(filtered);
      } catch (err) {
        setError(readableError(err, "Search failed. The backend may not be available yet."));
        setResults([]);
      } finally {
        setSearching(false);
      }
    }, 300);
    return () => {
      if (searchTimer.current) clearTimeout(searchTimer.current);
    };
  }, [trimmedQuery, scope, snapshot.workspaces]);

  // Persist successful searches
  useEffect(() => {
    if (trimmedQuery && results.length > 0 && !searching) {
      setRecentSearches(pushRecentSearch(trimmedQuery));
    }
  }, [trimmedQuery, results.length, searching]);

  const handleClear = useCallback(() => {
    setQuery("");
    setResults([]);
    setError(null);
    inputRef.current?.focus();
  }, []);

  const handleRecentClick = useCallback((q: string) => {
    setQuery(q);
    inputRef.current?.focus();
  }, []);

  const handleClearHistory = useCallback(() => {
    setRecentSearches(clearRecentSearches());
  }, []);

  const handleResultClick = useCallback(
    (sessionId: string) => {
      selectSession(sessionId);
    },
    [selectSession],
  );

  // Global "/" shortcut
  useEffect(() => {
    function handler(event: KeyboardEvent) {
      if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return;
      const target = event.target as HTMLElement | null;
      const tag = target?.tagName?.toLowerCase();
      if (target?.isContentEditable || tag === "input" || tag === "textarea") return;
      event.preventDefault();
      inputRef.current?.focus();
    }
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  const showResults = trimmedQuery.length > 0;
  const showEmpty = showResults && !searching && !error && results.length === 0;

  return (
    <div className="page-stack">
      <PageHeader
        title="Search"
        description="Find sessions, messages, and workspace content across ARES."
      />

      {/* Search input */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          ref={inputRef}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search sessions, messages, workspaces…"
          className="pl-9 pr-10"
          aria-label="Search query"
        />
        {query && (
          <Button
            variant="ghost"
            size="icon-sm"
            className="absolute right-1.5 top-1/2 -translate-y-1/2"
            onClick={handleClear}
            aria-label="Clear search"
          >
            <X className="size-4" />
          </Button>
        )}
      </div>

      {/* Scope filter chips */}
      <div className="flex flex-wrap gap-2">
        {SCOPE_KEYS.map((key) => {
          const cfg = SCOPE_CONFIG[key];
          const Icon = cfg.icon;
          const active = scope === key;
          return (
            <Button
              key={key}
              variant={active ? "default" : "outline"}
              size="sm"
              className="gap-1.5"
              onClick={() => setScope(key)}
            >
              <Icon className="size-3.5" />
              {cfg.label}
            </Button>
          );
        })}
      </div>

      {/* Error banner */}
      {error && (
        <p className="rounded-md border border-status-limited/40 bg-status-limited/10 px-4 py-3 text-sm text-status-limited">
          {error}
        </p>
      )}

      {/* Loading skeletons */}
      {searching && (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <div key={i} className="flex items-start gap-3 rounded-md border bg-card px-4 py-3">
              <Skeleton className="size-4 shrink-0 rounded-full" />
              <div className="flex-1 space-y-2">
                <Skeleton className="h-4 w-3/5" />
                <Skeleton className="h-3 w-4/5" />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Search results */}
      {showResults && !searching && results.length > 0 && (
        <section aria-label="Search results" className="space-y-2">
          <p className="text-xs text-muted-foreground">
            {results.length} result{results.length !== 1 ? "s" : ""} for &ldquo;{trimmedQuery}&rdquo;
          </p>
          <div className="space-y-2">
            {results.map((result) => (
              <div
                key={result.session_id}
                role="button"
                tabIndex={0}
                onClick={() => handleResultClick(result.session_id)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") handleResultClick(result.session_id);
                }}
                className="contents"
              >
                <SearchResultRow result={result} query={trimmedQuery} />
              </div>
            ))}
          </div>
        </section>
      )}

      {/* No results */}
      {showEmpty && (
        <EmptyState
          icon={Search}
          title="No results found"
          description={`No sessions matched "${trimmedQuery}". Try a different query or scope.`}
        />
      )}

      {/* Recent searches (only when no active query) */}
      {!showResults && recentSearches.length > 0 && (
        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2 text-sm">
              <Clock className="size-4" />
              Recent searches
            </CardTitle>
            <Button variant="ghost" size="sm" onClick={handleClearHistory}>
              Clear
            </Button>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            {recentSearches.map((q) => (
              <Badge
                key={q}
                variant="outline"
                className="cursor-pointer transition-colors hover:bg-accent"
                onClick={() => handleRecentClick(q)}
              >
                {q}
              </Badge>
            ))}
          </CardContent>
        </Card>
      )}

      {/* Session list fallback (no query, no history) */}
      {!showResults && recentSearches.length === 0 && snapshot.sessions.length > 0 && (
        <section aria-label="All sessions" className="space-y-2">
          <div className="flex items-center justify-between">
            <p className="text-sm font-medium text-muted-foreground">All sessions</p>
            <Button asChild variant="ghost" size="sm">
              <Link to="/conversation">
                View all <ArrowRight className="ml-1 size-3.5" />
              </Link>
            </Button>
          </div>
          <div className="divide-y rounded-md border">
            {snapshot.sessions.slice(0, 8).map((session) => (
              <button
                key={session.id}
                className="flex w-full items-center gap-3 px-4 py-3 text-left text-sm transition-colors hover:bg-accent/60"
                onClick={() => handleResultClick(session.id)}
              >
                <MessageCircle className="size-4 shrink-0 text-muted-foreground" />
                <span className="min-w-0 flex-1 truncate">{session.title || "Untitled session"}</span>
                {session.model && (
                  <span className="truncate text-xs text-muted-foreground">{session.model}</span>
                )}
              </button>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
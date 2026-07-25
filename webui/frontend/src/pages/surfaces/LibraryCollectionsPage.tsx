import {
  BookOpen,
  ChevronRight,
  FileText,
  Folder,
  HardDrive,
  Loader2,
  Network,
  Plus,
  RefreshCw,
  Trash2,
  TriangleAlert,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";

import { Markdown } from "@/components/Markdown";
import { SurfaceNote, SurfaceShell } from "@/components/surfaces/SurfaceShell";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { aresApi } from "@/shared/ares-api";
import type { LibraryCollection, LibraryEntry, LibraryItem } from "@/shared/contracts";

const KIND_META: Record<LibraryCollection["kind"], { label: string; icon: typeof Folder }> = {
  obsidian: { label: "Obsidian vault", icon: BookOpen },
  network: { label: "Network drive", icon: Network },
  folder: { label: "Local folder", icon: HardDrive },
};

function readableSize(bytes: number | null): string {
  if (bytes == null) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/**
 * Library → Collections.
 *
 * Connect folder-backed knowledge sources (Obsidian vault, local notes folder,
 * mounted network share) and read them. Collections are read-only by design:
 * Library is what you study and preserve, Workshop is where you write.
 */
export function LibraryCollectionsPage() {
  const [collections, setCollections] = useState<LibraryCollection[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [newPath, setNewPath] = useState("");
  const [newLabel, setNewLabel] = useState("");
  const [connecting, setConnecting] = useState(false);

  const [openId, setOpenId] = useState("");
  const [browsePath, setBrowsePath] = useState(".");
  const [entries, setEntries] = useState<LibraryEntry[]>([]);
  const [browsing, setBrowsing] = useState(false);
  const [item, setItem] = useState<LibraryItem | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await aresApi.listLibraryCollections();
      setCollections(res.collections ?? []);
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load collections");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const connect = async () => {
    const path = newPath.trim();
    if (!path) return;
    setConnecting(true);
    setError("");
    try {
      await aresApi.addLibraryCollection(path, newLabel.trim());
      setNewPath("");
      setNewLabel("");
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not connect that folder");
    } finally {
      setConnecting(false);
    }
  };

  const disconnect = async (collection: LibraryCollection) => {
    if (!window.confirm(
      `Disconnect "${collection.label}"?\n\nThis only removes it from Library. Nothing on disk is deleted.`,
    )) return;
    try {
      await aresApi.removeLibraryCollection(collection.id);
      if (openId === collection.id) {
        setOpenId("");
        setEntries([]);
        setItem(null);
      }
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not disconnect");
    }
  };

  const browse = useCallback(async (collectionId: string, path: string) => {
    setBrowsing(true);
    setItem(null);
    try {
      const res = await aresApi.browseLibrary(collectionId, path);
      setEntries(res.entries ?? []);
      setBrowsePath(res.path || ".");
      setOpenId(collectionId);
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not open that folder");
    } finally {
      setBrowsing(false);
    }
  }, []);

  const openItem = async (collectionId: string, path: string) => {
    try {
      setItem(await aresApi.readLibraryItem(collectionId, path));
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not open that file");
    }
  };

  const parentPath = (path: string): string => {
    if (!path || path === ".") return ".";
    const parts = path.split("/").filter(Boolean);
    parts.pop();
    return parts.length ? parts.join("/") : ".";
  };

  return (
    <SurfaceShell
      title="Collections"
      description="Connect an Obsidian vault, a local notes folder, or a mounted network drive, then read and study it here."
    >
      <SurfaceNote>
        Collections are read-only: Library is what you study and preserve, Workshop is where you
        write. Indexing and search configuration live in System (memory infrastructure), not here.
      </SurfaceNote>

      {error && (
        <div className="flex items-start gap-2 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
          <TriangleAlert className="mt-0.5 size-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base">
            <Plus className="size-4 text-primary" />
            Connect a source
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <div className="flex flex-col gap-2 sm:flex-row">
            <Input
              value={newPath}
              onChange={(e) => setNewPath(e.target.value)}
              placeholder="/path/to/vault, /Volumes/share/books, ~/Notes"
              className="flex-1 font-mono text-xs"
              onKeyDown={(e) => { if (e.key === "Enter") void connect(); }}
            />
            <Input
              value={newLabel}
              onChange={(e) => setNewLabel(e.target.value)}
              placeholder="Label (optional)"
              className="sm:w-48"
              onKeyDown={(e) => { if (e.key === "Enter") void connect(); }}
            />
            <Button onClick={() => void connect()} disabled={connecting || !newPath.trim()}>
              {connecting ? <Loader2 className="size-4 animate-spin" /> : "Connect"}
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            An Obsidian vault is detected automatically by its <code>.obsidian</code> folder.
            Network shares must already be mounted by the operating system.
          </p>
        </CardContent>
      </Card>

      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-medium">Connected sources</h2>
          <Button variant="ghost" size="sm" onClick={() => void load()} disabled={loading}>
            <RefreshCw className={loading ? "size-3.5 animate-spin" : "size-3.5"} />
          </Button>
        </div>

        {loading && collections.length === 0 ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : collections.length === 0 ? (
          <Card>
            <CardContent className="py-8 text-center text-sm text-muted-foreground">
              No sources connected yet. Point Library at a vault or folder above.
            </CardContent>
          </Card>
        ) : (
          collections.map((collection) => {
            const meta = KIND_META[collection.kind] ?? KIND_META.folder;
            const Icon = meta.icon;
            const isOpen = openId === collection.id;
            return (
              <Card key={collection.id}>
                <CardContent className="space-y-3 py-3">
                  <div className="flex items-start gap-3">
                    <Icon className="mt-0.5 size-4 shrink-0 text-primary" />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm font-medium">{collection.label}</span>
                        <Badge variant="secondary" className="text-[10px]">{meta.label}</Badge>
                        {!collection.available && (
                          <Badge variant="destructive" className="text-[10px]">Unavailable</Badge>
                        )}
                      </div>
                      <p className="truncate font-mono text-xs text-muted-foreground" title={collection.path}>
                        {collection.path}
                      </p>
                      {collection.stats && collection.available && (
                        <p className="mt-1 text-xs text-muted-foreground">
                          {collection.stats.notes} notes · {collection.stats.documents} documents
                          {collection.stats.truncated && " · large corpus (partial count)"}
                        </p>
                      )}
                    </div>
                    <div className="flex shrink-0 gap-1">
                      <Button
                        variant="secondary"
                        size="sm"
                        disabled={!collection.available}
                        onClick={() => (isOpen ? setOpenId("") : void browse(collection.id, "."))}
                      >
                        {isOpen ? "Close" : "Browse"}
                      </Button>
                      <Button variant="ghost" size="sm" onClick={() => void disconnect(collection)}>
                        <Trash2 className="size-3.5" />
                      </Button>
                    </div>
                  </div>

                  {isOpen && (
                    <div className="rounded-md border">
                      <div className="flex items-center gap-2 border-b px-3 py-1.5 text-xs text-muted-foreground">
                        <button
                          type="button"
                          className="hover:text-foreground"
                          onClick={() => void browse(collection.id, ".")}
                        >
                          {collection.label}
                        </button>
                        {browsePath !== "." && (
                          <>
                            <ChevronRight className="size-3" />
                            <span className="truncate font-mono">{browsePath}</span>
                          </>
                        )}
                        {browsing && <Loader2 className="ml-auto size-3 animate-spin" />}
                      </div>

                      <div className="max-h-72 overflow-auto">
                        {browsePath !== "." && (
                          <button
                            type="button"
                            onClick={() => void browse(collection.id, parentPath(browsePath))}
                            className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-xs text-muted-foreground hover:bg-muted"
                          >
                            <Folder className="size-3.5" /> ..
                          </button>
                        )}
                        {entries.length === 0 && !browsing ? (
                          <p className="px-3 py-4 text-center text-xs text-muted-foreground">Empty folder.</p>
                        ) : (
                          entries.map((entry) => (
                            <button
                              key={entry.path}
                              type="button"
                              disabled={entry.kind === "file" && !entry.readable}
                              onClick={() =>
                                entry.kind === "directory"
                                  ? void browse(collection.id, entry.path)
                                  : void openItem(collection.id, entry.path)
                              }
                              className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-xs hover:bg-muted disabled:cursor-not-allowed disabled:opacity-50"
                            >
                              {entry.kind === "directory" ? (
                                <Folder className="size-3.5 shrink-0 text-primary" />
                              ) : (
                                <FileText className="size-3.5 shrink-0 text-muted-foreground" />
                              )}
                              <span className="flex-1 truncate">{entry.name}</span>
                              {entry.document && (
                                <Badge variant="outline" className="text-[9px]">doc</Badge>
                              )}
                              <span className="shrink-0 text-muted-foreground">
                                {readableSize(entry.size)}
                              </span>
                            </button>
                          ))
                        )}
                      </div>

                      {item && (
                        <div className="border-t">
                          <div className="flex items-center gap-2 border-b bg-muted/40 px-3 py-1.5 text-xs">
                            <FileText className="size-3.5" />
                            <span className="flex-1 truncate font-mono">{item.path}</span>
                            <Button variant="ghost" size="sm" onClick={() => setItem(null)}>Close</Button>
                          </div>
                          <div className="max-h-96 overflow-auto px-3 py-2 text-sm">
                            {item.readable ? (
                              <Markdown content={item.content} />
                            ) : (
                              <p className="text-muted-foreground">
                                {item.name} can be listed but not opened here yet
                                ({readableSize(item.size)}). PDF and EPUB reading lands with the
                                document pipeline.
                              </p>
                            )}
                          </div>
                        </div>
                      )}
                    </div>
                  )}
                </CardContent>
              </Card>
            );
          })
        )}
      </div>
    </SurfaceShell>
  );
}

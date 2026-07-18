import {
  ChevronDown,
  ChevronRight,
  File,
  FileCode2,
  Folder,
  LoaderCircle,
  Plus,
  Save,
  Trash2,
} from "lucide-react";
import Editor, { type BeforeMount } from "@monaco-editor/react";
import { useCallback, useEffect, useMemo, useState } from "react";

import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import type { WorkspaceEntry } from "@/shared/contracts";

// ── Graphite dark palette ──
const G = {
  bg: "#151614",
  surface: "#1B1C1A",
  border: "#343631",
  text: "#ECEBE4",
  muted: "#A7A79D",
  accent: "#D7D6CE",
  accentBg: "rgba(255,255,255,0.08)",
  codeBg: "#111210",
};

interface TreeNode extends WorkspaceEntry {
  expanded: boolean;
  loading: boolean;
}

function dirname(path: string): string {
  const parts = path.replace(/\/$/, "").split("/");
  parts.pop();
  return parts.join("/") || ".";
}

function isTextFile(name: string): boolean {
  const ext = name.split(".").pop()?.toLowerCase() || "";
  const binary = new Set([
    "png", "jpg", "jpeg", "gif", "webp", "mp4", "mov", "mp3", "wav", "ogg", "pdf",
    "zip", "tar", "gz", "dmg", "exe", "dll", "so", "dylib", "bin", "ico", "ttf",
    "woff", "woff2", "otf", "eot", "sqlite", "db",
  ]);
  return !binary.has(ext);
}

const defineAresTheme: BeforeMount = (monaco) => {
  monaco.editor.defineTheme("ares-dark", {
    base: "vs-dark",
    inherit: true,
    rules: [],
    colors: {
      "editor.background": G.codeBg,
      "editor.lineHighlightBackground": "#1B1C1A",
      "editorLineNumber.foreground": "#6B6D65",
      "editorCursor.foreground": "#D7D6CE",
      "editor.selectionBackground": "rgba(255,255,255,0.12)",
      "editor.inactiveSelectionBackground": "rgba(255,255,255,0.06)",
    },
  });
};

export function WorkspacePage() {
  const { snapshot, selectedSessionId, selectSession } = useAres();
  const [tree, setTree] = useState<Record<string, TreeNode[]>>({});
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [loadingPaths, setLoadingPaths] = useState<Set<string>>(new Set());
  const [selectedPath, setSelectedPath] = useState<string>("");
  const [editorContent, setEditorContent] = useState<string>("");
  const [dirty, setDirty] = useState(false);
  const [loadingFile, setLoadingFile] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [createName, setCreateName] = useState("");
  const [createType, setCreateType] = useState<"file" | "directory" | null>(null);

  const workspaceSessions = useMemo(
    () => snapshot.sessions.filter((session) => session.workspace),
    [snapshot.sessions]
  );
  const activeSession = useMemo(
    () => workspaceSessions.find((session) => session.id === selectedSessionId) || workspaceSessions[0],
    [workspaceSessions, selectedSessionId]
  );

  const loadDirectory = useCallback(async (sessionId: string, path: string) => {
    setLoadingPaths((previous) => new Set(previous).add(path));
    try {
      const entries = await aresApi.listWorkspace(sessionId, path);
      const nodes = entries.map((entry) => ({
        ...entry,
        expanded: false,
        loading: false,
      }));
      setTree((previous) => ({ ...previous, [path]: nodes }));
    } catch (reason) {
      setError(readableError(reason, "Could not list workspace directory."));
    } finally {
      setLoadingPaths((previous) => {
        const next = new Set(previous);
        next.delete(path);
        return next;
      });
    }
  }, []);

  useEffect(() => {
    if (!activeSession) return;
    loadDirectory(activeSession.id, ".");
  }, [activeSession?.id, loadDirectory]);

  const toggleDirectory = useCallback(
    async (path: string) => {
      if (!activeSession) return;
      const next = new Set(expanded);
      if (next.has(path)) {
        next.delete(path);
      } else {
        next.add(path);
        if (!tree[path]) {
          await loadDirectory(activeSession.id, path);
        }
      }
      setExpanded(next);
    },
    [activeSession, expanded, tree, loadDirectory]
  );

  const openFile = useCallback(
    async (path: string) => {
      if (!activeSession || !isTextFile(path)) return;
      setSelectedPath(path);
      setLoadingFile(true);
      setError("");
      try {
        const content = await aresApi.readFile(activeSession.id, path);
        setEditorContent(content);
        setDirty(false);
      } catch (reason) {
        setError(readableError(reason, "Could not read file."));
      } finally {
        setLoadingFile(false);
      }
    },
    [activeSession]
  );

  const saveFile = useCallback(async () => {
    if (!activeSession || !selectedPath) return;
    setSaving(true);
    setError("");
    try {
      await aresApi.saveFile(activeSession.id, selectedPath, editorContent);
      setDirty(false);
    } catch (reason) {
      setError(readableError(reason, "Could not save file."));
    } finally {
      setSaving(false);
    }
  }, [activeSession, selectedPath, editorContent]);

  const createItem = useCallback(async () => {
    if (!activeSession || !createName || !createType) return;
    const parent = selectedPath && tree[selectedPath]?.some((node) => node.kind === "directory") ? selectedPath : ".";
    const target = parent === "." ? createName : `${parent}/${createName}`;
    setError("");
    try {
      if (createType === "directory") {
        await aresApi.createDirectory(activeSession.id, target);
      } else {
        await aresApi.createFile(activeSession.id, target, "");
      }
      setCreateName("");
      setCreateType(null);
      await loadDirectory(activeSession.id, parent);
      const parentExpanded = new Set(expanded);
      parentExpanded.add(parent);
      setExpanded(parentExpanded);
    } catch (reason) {
      setError(readableError(reason, "Could not create item."));
    }
  }, [activeSession, createName, createType, selectedPath, tree, expanded, loadDirectory]);

  const deleteItem = useCallback(
    async (path: string, kind: string) => {
      if (!activeSession) return;
      if (!confirm(`Delete ${path}?`)) return;
      setError("");
      try {
        await aresApi.deleteFile(activeSession.id, path, kind === "directory");
        const parent = dirname(path);
        await loadDirectory(activeSession.id, parent === path ? "." : parent);
        if (selectedPath === path) {
          setSelectedPath("");
          setEditorContent("");
          setDirty(false);
        }
      } catch (reason) {
        setError(readableError(reason, "Could not delete item."));
      }
    },
    [activeSession, selectedPath, loadDirectory]
  );

  const renderTree = useCallback(
    (path: string, depth = 0) => {
      const nodes = tree[path] || [];
      return (
        <div key={path} style={{ paddingLeft: depth * 12 }}>
          {nodes.map((node) => {
            const active = selectedPath === node.path;
            const isDir = node.kind === "directory";
            const isOpen = expanded.has(node.path);
            return (
              <div key={node.path}>
                <div
                  className="group flex items-center gap-1 rounded px-1.5 py-1 text-[13px]"
                  style={{
                    backgroundColor: active ? G.accentBg : "transparent",
                    color: active ? G.accent : G.text,
                    cursor: "pointer",
                  }}
                  onClick={() => (isDir ? toggleDirectory(node.path) : openFile(node.path))}
                >
                  {isDir ? (
                    isOpen ? <ChevronDown size={14} style={{ color: G.muted }} /> : <ChevronRight size={14} style={{ color: G.muted }} />
                  ) : (
                    <span className="w-[14px]" />
                  )}
                  {isDir ? <Folder size={14} style={{ color: G.accent }} /> : <File size={14} style={{ color: G.muted }} />}
                  <span className="ml-1 flex-1 truncate">{node.name}</span>
                  <button
                    type="button"
                    onClick={(event) => {
                      event.stopPropagation();
                      deleteItem(node.path, node.kind);
                    }}
                    className="opacity-0 group-hover:opacity-100"
                    style={{ color: G.muted }}
                    title="Delete"
                  >
                    <Trash2 size={12} />
                  </button>
                </div>
                {isDir && isOpen && (tree[node.path] || loadingPaths.has(node.path)) ? (
                  loadingPaths.has(node.path) ? (
                    <div style={{ paddingLeft: 16, color: G.muted }} className="flex items-center gap-2 py-1 text-xs">
                      <LoaderCircle size={12} className="animate-spin" /> Loading…
                    </div>
                  ) : (
                    renderTree(node.path, depth + 1)
                  )
                ) : null}
              </div>
            );
          })}
        </div>
      );
    },
    [tree, expanded, selectedPath, loadingPaths, toggleDirectory, openFile, deleteItem]
  );

  if (!workspaceSessions.length) {
    return (
      <div className="page-stack">
        <PageHeader
          title="Workspace"
          description="Inspect files, tasks, and artifacts through stable ARES interfaces shared by every supported runtime."
        />
        <div
          className="flex flex-1 flex-col items-center justify-center gap-3 rounded-xl border p-8 text-center"
          style={{ borderColor: G.border, backgroundColor: G.surface }}
        >
          <FileCode2 size={40} style={{ color: G.muted }} />
          <p style={{ color: G.muted }}>No workspace sessions yet. Start a conversation with a workspace to browse and edit files.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack h-full">
      <PageHeader
        title="Workspace"
        description="File tree and editor for the selected session workspace."
        action={
          selectedPath ? (
            <Button
              size="sm"
              onClick={() => void saveFile()}
              disabled={!dirty || saving}
              className="gap-1"
              style={{ backgroundColor: dirty ? G.accent : G.accentBg, color: dirty ? G.bg : G.text }}
            >
              {saving ? <LoaderCircle size={14} className="animate-spin" /> : <Save size={14} />}
              {saving ? "Saving" : "Save"}
            </Button>
          ) : null
        }
      />

      {error ? (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-300">{error}</div>
      ) : null}

      <div className="flex items-center gap-3">
        <span className="text-sm" style={{ color: G.muted }}>Session workspace</span>
        <select
          className="min-w-0 flex-1 rounded-md border bg-background px-3 py-2 text-sm"
          value={activeSession?.id || ""}
          onChange={(event) => selectSession(event.target.value)}
        >
          {workspaceSessions.map((session) => (
            <option key={session.id} value={session.id}>
              {session.title} — {session.workspace}
            </option>
          ))}
        </select>
        <Button
          size="sm"
          variant="outline"
          className="gap-1"
          onClick={() => setCreateType("file")}
        >
          <Plus size={14} /> File
        </Button>
        <Button
          size="sm"
          variant="outline"
          className="gap-1"
          onClick={() => setCreateType("directory")}
        >
          <Plus size={14} /> Folder
        </Button>
      </div>

      {createType ? (
        <div className="flex items-center gap-2">
          <input
            value={createName}
            onChange={(event) => setCreateName(event.target.value)}
            placeholder={createType === "directory" ? "New folder name" : "New file name"}
            className="flex-1 rounded-md border bg-background px-3 py-1.5 text-sm"
          />
          <Button size="sm" onClick={() => void createItem()} disabled={!createName}>Create</Button>
          <Button size="sm" variant="outline" onClick={() => { setCreateType(null); setCreateName(""); }}>Cancel</Button>
        </div>
      ) : null}

      <div className="flex min-h-0 flex-1 gap-3">
        <div
          className="flex w-64 min-w-0 flex-col gap-2 overflow-y-auto rounded-xl border p-2"
          style={{ borderColor: G.border, backgroundColor: G.surface }}
        >
          {tree["."] ? renderTree(".") : (
            <div className="flex items-center gap-2 py-2 text-xs" style={{ color: G.muted }}>
              <LoaderCircle size={12} className="animate-spin" /> Loading workspace…
            </div>
          )}
        </div>

        <div
          className="flex min-w-0 flex-1 flex-col overflow-hidden rounded-xl border"
          style={{ borderColor: G.border, backgroundColor: G.codeBg }}
        >
          {selectedPath ? (
            <>
              <div
                className="flex items-center justify-between border-b px-3 py-2 text-xs"
                style={{ borderColor: G.border, color: G.muted }}
              >
                <span className="truncate">{selectedPath}</span>
                {dirty ? <span style={{ color: G.accent }}>● unsaved</span> : null}
              </div>
              <div className="min-h-0 flex-1">
                {loadingFile ? (
                  <div className="flex h-full items-center justify-center gap-2 text-sm" style={{ color: G.muted }}>
                    <LoaderCircle size={16} className="animate-spin" /> Loading…
                  </div>
                ) : (
                  <Editor
                    height="100%"
                    path={selectedPath}
                    defaultLanguage={languageFromPath(selectedPath)}
                    value={editorContent}
                    theme="ares-dark"
                    beforeMount={defineAresTheme}
                    onChange={(value) => {
                      setEditorContent(value || "");
                      setDirty(true);
                    }}
                    options={{
                      minimap: { enabled: false },
                      fontSize: 13,
                      lineNumbers: "on",
                      roundedSelection: false,
                      scrollBeyondLastLine: false,
                      automaticLayout: true,
                      padding: { top: 12 },
                    }}
                  />
                )}
              </div>
            </>
          ) : (
            <div className="flex h-full flex-col items-center justify-center gap-3 p-6 text-center">
              <FileCode2 size={40} style={{ color: G.muted }} />
              <p style={{ color: G.muted }}>Select a file from the workspace tree to edit it.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function languageFromPath(path: string): string {
  const ext = path.split(".").pop()?.toLowerCase() || "";
  const map: Record<string, string> = {
    ts: "typescript", tsx: "typescript", js: "javascript", jsx: "javascript",
    py: "python", rs: "rust", go: "go", json: "json", yaml: "yaml", yml: "yaml",
    md: "markdown", html: "html", css: "css", scss: "scss", sql: "sql",
    sh: "shell", bash: "shell", zsh: "shell", c: "c", cpp: "cpp",
    h: "c", hpp: "cpp", java: "java", kt: "kotlin", swift: "swift",
  };
  return map[ext] || "plaintext";
}

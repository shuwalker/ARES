import {
  Plus,
  Folder,
  RefreshCw,
  Download,
  MoreVertical,
  X,
  FileCode,
  Box,
  ChevronRight,
  ChevronDown,
  FileText,
  Save,
  LoaderCircle,
  ArrowLeft,
} from "lucide-react";
import { lazy, Suspense, useState, useEffect, useCallback } from "react";
import { useAres } from "@/shared/ares-context";
import { aresApi } from "@/shared/ares-api";

const Editor = lazy(async () => ({
  default: (await import("@monaco-editor/react")).Editor,
}));

type WorkbenchTab = "files" | "artifacts";
const STORAGE_KEY = "ares.command-center.workbench-tab";

// Theme constants matching Hermes dark UI
const H = {
  bg: "#11131c",
  surface: "#181b26",
  surfaceHover: "#202434",
  border: "rgba(255, 255, 255, 0.08)",
  border2: "rgba(255, 255, 255, 0.12)",
  text: "#ececf1",
  muted: "#8e8ea0",
  strong: "#ffffff",
  accent: "#7c3aed",
  accentGlow: "#9333ea",
  chipBg: "#1a1d29",
  chipBorder: "rgba(255, 255, 255, 0.1)",
};

interface FileNode {
  name: string;
  path: string;
  kind: "file" | "directory" | "other";
  size?: number;
}

export function WorkbenchPane({ onCollapse }: { onCollapse?: () => void }) {
  const { currentSession, snapshot } = useAres();
  const [tab, setTab] = useState<WorkbenchTab>(() => {
    try {
      // "terminal" may still be persisted from when this pane had a Terminal
      // tab; it falls through to "files" rather than restoring a dead tab.
      const saved = window.localStorage.getItem(STORAGE_KEY);
      return saved === "artifacts" ? saved : "files";
    } catch {
      return "files";
    }
  });

  const [tree, setTree] = useState<Record<string, FileNode[]>>({});
  const [expanded, setExpanded] = useState<Set<string>>(new Set(["."]));
  const [selectedFilePath, setSelectedFilePath] = useState<string>("");
  const [fileContent, setFileContent] = useState<string>("");
  const [isDirty, setIsDirty] = useState(false);
  const [isLoadingFile, setIsLoadingFile] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string>("");
  const [showNewInput, setShowNewInput] = useState<"file" | "folder" | null>(null);
  const [newItemName, setNewItemName] = useState("");

  const activeSessionId = currentSession?.id || snapshot.sessions[0]?.id || "";

  const chooseTab = (next: WorkbenchTab) => {
    setTab(next);
    try {
      window.localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // storage persistent error fallback
    }
  };

  const loadDirectory = useCallback(async (dirPath: string) => {
    if (!activeSessionId) return;
    try {
      const items = await aresApi.listWorkspace(activeSessionId, dirPath);
      setTree((prev) => ({ ...prev, [dirPath]: items }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load directory");
    }
  }, [activeSessionId]);

  useEffect(() => {
    if (activeSessionId) {
      void loadDirectory(".");
    }
  }, [activeSessionId, loadDirectory]);

  const toggleDirectory = async (dirPath: string) => {
    const next = new Set(expanded);
    if (next.has(dirPath)) {
      next.delete(dirPath);
    } else {
      next.add(dirPath);
      if (!tree[dirPath]) {
        await loadDirectory(dirPath);
      }
    }
    setExpanded(next);
  };

  const openFile = async (filePath: string) => {
    if (!activeSessionId) return;
    setSelectedFilePath(filePath);
    setIsLoadingFile(true);
    setIsDirty(false);
    try {
      const content = await aresApi.readFile(activeSessionId, filePath);
      setFileContent(content);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not open file");
      setFileContent("");
    } finally {
      setIsLoadingFile(false);
    }
  };

  const saveFile = async () => {
    if (!activeSessionId || !selectedFilePath) return;
    setIsSaving(true);
    try {
      await aresApi.saveFile(activeSessionId, selectedFilePath, fileContent);
      setIsDirty(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save file");
    } finally {
      setIsSaving(false);
    }
  };

  const createItem = async () => {
    if (!activeSessionId || !newItemName.trim() || !showNewInput) return;
    try {
      if (showNewInput === "file") {
        await aresApi.createFile(activeSessionId, newItemName.trim(), "");
      } else {
        await aresApi.createDirectory(activeSessionId, newItemName.trim());
      }
      setShowNewInput(null);
      setNewItemName("");
      void loadDirectory(".");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create item");
    }
  };

  const renderTreeNodes = (dirPath: string, depth = 0) => {
    const nodes = tree[dirPath] || [];
    return (
      <div key={dirPath} style={{ paddingLeft: depth > 0 ? 12 : 0 }}>
        {nodes.map((node) => {
          const isDir = node.kind === "directory";
          const isOpen = expanded.has(node.path);
          const isSelected = selectedFilePath === node.path;

          return (
            <div key={node.path}>
              <button
                type="button"
                onClick={() => (isDir ? void toggleDirectory(node.path) : void openFile(node.path))}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  width: "100%",
                  padding: "4px 8px",
                  borderRadius: 6,
                  border: "none",
                  background: isSelected ? "rgba(124,58,237,0.18)" : "transparent",
                  color: isSelected ? H.strong : H.text,
                  fontSize: 12,
                  cursor: "pointer",
                  textAlign: "left",
                }}
              >
                {isDir ? (
                  isOpen ? <ChevronDown size={13} style={{ color: H.muted }} /> : <ChevronRight size={13} style={{ color: H.muted }} />
                ) : (
                  <span style={{ width: 13 }} />
                )}
                {isDir ? <Folder size={13} style={{ color: H.accentGlow }} /> : <FileText size={13} style={{ color: H.muted }} />}
                <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{node.name}</span>
              </button>
              {isDir && isOpen && renderTreeNodes(node.path, depth + 1)}
            </div>
          );
        })}
      </div>
    );
  };

  return (
    <section style={{ height: "100%", display: "flex", flexDirection: "column", background: H.bg, color: H.text, borderLeft: `1px solid ${H.border}` }}>
      {/* Hermes Top Header */}
      <header style={{ height: 44, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 12px", borderBottom: `1px solid ${H.border}`, flexShrink: 0 }}>
        <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.1em", textTransform: "uppercase", color: H.muted }}>
          WORKSPACE
        </span>

        <div style={{ display: "flex", alignItems: "center", gap: 3 }}>
          <button type="button" title="New file / folder" onClick={() => setShowNewInput(showNewInput ? null : "file")} style={{ background: "transparent", border: "none", color: H.muted, padding: 5, borderRadius: 4, cursor: "pointer" }}>
            <Plus size={14} />
          </button>
          <button
            type="button"
            title={currentSession?.workspace ? `Workspace: ${currentSession.workspace}` : "No workspace for this session"}
            onClick={() => setShowNewInput(showNewInput ? null : "folder")}
            style={{ background: "transparent", border: "none", color: H.muted, padding: 5, borderRadius: 4, cursor: "pointer" }}
          >
            <Folder size={14} />
          </button>
          <button type="button" title="Refresh files" onClick={() => void loadDirectory(".")} style={{ background: "transparent", border: "none", color: H.muted, padding: 5, borderRadius: 4, cursor: "pointer" }}>
            <RefreshCw size={14} />
          </button>
          <button type="button" title="Export workspace" onClick={() => alert("Workspace exported.")} style={{ background: "transparent", border: "none", color: H.muted, padding: 5, borderRadius: 4, cursor: "pointer" }}>
            <Download size={14} />
          </button>
          <button type="button" title="More options" onClick={() => {}} style={{ background: "transparent", border: "none", color: H.muted, padding: 5, borderRadius: 4, cursor: "pointer" }}>
            <MoreVertical size={14} />
          </button>
          <div style={{ width: 1, height: 14, background: H.border2, margin: "0 2px" }} />
          <button type="button" title="Close panel" aria-label="Close workspace" onClick={onCollapse} style={{ background: "transparent", border: "none", color: H.muted, padding: 5, borderRadius: 4, cursor: "pointer" }}>
            <X size={14} />
          </button>
        </div>
      </header>

      {/* Sub-Navigation Pill Tabs */}
      <div style={{ padding: "8px 12px", borderBottom: `1px solid ${H.border}`, display: "flex", alignItems: "center", gap: 6, flexShrink: 0 }}>
        <button
          type="button"
          onClick={() => chooseTab("files")}
          style={{
            padding: "4px 14px",
            borderRadius: 20,
            border: `1px solid ${tab === "files" ? H.border2 : "transparent"}`,
            background: tab === "files" ? H.surface : "transparent",
            color: tab === "files" ? H.strong : H.muted,
            fontSize: 12,
            fontWeight: 500,
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            gap: 6,
          }}
        >
          <FileCode size={13} />
          Files
        </button>

        <button
          type="button"
          onClick={() => chooseTab("artifacts")}
          style={{
            padding: "4px 14px",
            borderRadius: 20,
            border: `1px solid ${tab === "artifacts" ? H.border2 : "transparent"}`,
            background: tab === "artifacts" ? H.surface : "transparent",
            color: tab === "artifacts" ? H.strong : H.muted,
            fontSize: 12,
            fontWeight: 500,
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            gap: 6,
          }}
        >
          <Box size={13} />
          Artifacts 0
        </button>

      </div>

      {/* Main Content Area */}
      <div style={{ flex: 1, minHeight: 0, overflow: "hidden", display: "flex", flexDirection: "column" }}>
        {tab === "files" && (
          <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
            {/* Inline New File / Folder input */}
            {showNewInput && (
              <div style={{ padding: "8px 12px", borderBottom: `1px solid ${H.border}`, display: "flex", gap: 6, alignItems: "center" }}>
                <input
                  type="text"
                  value={newItemName}
                  onChange={(e) => setNewItemName(e.target.value)}
                  placeholder={showNewInput === "file" ? "New file name..." : "New folder name..."}
                  style={{ flex: 1, background: "#0c0e18", border: `1px solid ${H.border}`, borderRadius: 6, padding: "4px 8px", color: H.text, fontSize: 11, outline: "none" }}
                  onKeyDown={(e) => { if (e.key === "Enter") void createItem(); }}
                />
                <button type="button" onClick={() => void createItem()} style={{ padding: "4px 8px", borderRadius: 6, border: "none", background: H.accent, color: "#fff", fontSize: 11, cursor: "pointer" }}>
                  Create
                </button>
                <button type="button" onClick={() => setShowNewInput(null)} style={{ padding: "4px 8px", borderRadius: 6, border: `1px solid ${H.border}`, background: "transparent", color: H.muted, fontSize: 11, cursor: "pointer" }}>
                  Cancel
                </button>
              </div>
            )}

            {/* If a file is selected for viewing/editing */}
            {selectedFilePath ? (
              <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
                <div style={{ height: 36, padding: "0 12px", borderBottom: `1px solid ${H.border}`, display: "flex", alignItems: "center", justifyContent: "space-between", background: H.surface }}>
                  <button type="button" onClick={() => setSelectedFilePath("")} style={{ display: "flex", alignItems: "center", gap: 4, background: "transparent", border: "none", color: H.muted, fontSize: 12, cursor: "pointer" }}>
                    <ArrowLeft size={13} /> Back
                  </button>
                  <span style={{ fontSize: 11, fontFamily: "monospace", color: H.text, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 180 }}>
                    {selectedFilePath}
                  </span>
                  <button type="button" onClick={() => void saveFile()} disabled={!isDirty || isSaving} style={{ display: "flex", alignItems: "center", gap: 4, padding: "3px 8px", borderRadius: 5, border: "none", background: isDirty ? H.accent : H.chipBg, color: isDirty ? "#fff" : H.muted, fontSize: 11, cursor: isDirty ? "pointer" : "default" }}>
                    {isSaving ? <LoaderCircle size={11} className="animate-spin" /> : <Save size={11} />}
                    {isSaving ? "Saving" : "Save"}
                  </button>
                </div>
                <div style={{ flex: 1, minHeight: 0 }}>
                  {isLoadingFile ? (
                    <div style={{ height: "100%", display: "flex", alignItems: "center", justifyContent: "center", gap: 6, color: H.muted, fontSize: 12 }}>
                      <LoaderCircle size={14} className="animate-spin" /> Loading file…
                    </div>
                  ) : (
                    <Suspense fallback={<div style={{ padding: 12, color: H.muted, fontSize: 12 }}>Loading editor…</div>}>
                      <Editor
                        height="100%"
                        path={selectedFilePath}
                        value={fileContent}
                        theme="vs-dark"
                        onChange={(val) => {
                          setFileContent(val || "");
                          setIsDirty(true);
                        }}
                        options={{
                          minimap: { enabled: false },
                          fontSize: 12,
                          lineNumbers: "on",
                          scrollBeyondLastLine: false,
                          automaticLayout: true,
                          padding: { top: 8 },
                        }}
                      />
                    </Suspense>
                  )}
                </div>
              </div>
            ) : (
              /* File Tree List */
              <div style={{ flex: 1, overflowY: "auto", padding: 8 }}>
                {tree["."] ? renderTreeNodes(".") : (
                  <div style={{ padding: 16, display: "flex", alignItems: "center", gap: 6, color: H.muted, fontSize: 12 }}>
                    <LoaderCircle size={14} className="animate-spin" /> Loading workspace…
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {tab === "artifacts" && (
          <div style={{ padding: 16, textAlign: "center", color: H.muted, fontSize: 12 }}>
            <Box size={32} style={{ margin: "0 auto 8px", opacity: 0.5 }} />
            No artifacts generated in this session.
          </div>
        )}

      </div>
    </section>
  );
}

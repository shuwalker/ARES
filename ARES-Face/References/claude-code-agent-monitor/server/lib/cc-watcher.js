/**
 * @file cc-watcher.js
 * @description Best-effort file watcher for the Claude Code config surfaces
 * surfaced by the Config Explorer page. Watches ~/.claude/ recursively (if
 * the platform supports it) plus ~/.claude.json and emits a debounced
 * `cc_config_changed` over the dashboard websocket so the UI can refetch
 * without polling.
 *
 * Aggressively filters fs.watch events: ~/.claude/ contains lots of churn
 * (`projects/*.jsonl` transcripts, `file-history/`, our own
 * `cc-config-backups/`) that has nothing to do with the Config Explorer.
 * Only paths matching real config surfaces fire a broadcast. Without this
 * filter the watcher fires multiple times per second while a claude session
 * is active and the page becomes a perpetual loading spinner.
 *
 * Failures here are non-fatal — `fs.watch` is platform-quirky, and the
 * Config Explorer still has a manual Refresh button.
 *
 * @author Son Nguyen <hoangson091104@gmail.com>
 */

const fs = require("fs");
const path = require("path");
const os = require("os");
const { getClaudeHome } = require("./claude-home");

const DEBOUNCE_MS = 500;

// Subpaths inside ~/.claude/ that ARE config surfaces and should trigger a
// refetch. Anything else (transcripts, file history, our own backups) is
// ignored. Match is by prefix on the relative path.
const RELEVANT_PREFIXES = [
  "settings.json",
  "settings.local.json",
  "keybindings.json",
  "statusline.py",
  "statusline-command.sh",
  "known_marketplaces.json",
  "agents",
  "commands",
  "skills",
  "output-styles",
  "hooks",
  "plugins",
  "CLAUDE.md",
];

// Subpaths to explicitly ignore even if they match RELEVANT_PREFIXES by
// accident. Important: our own backup dir lives at ~/.claude/cc-config-backups/
// and writing backups would re-trigger the watcher in a loop without this.
const IGNORED_PREFIXES = [
  "cc-config-backups",
  "projects",
  "file-history",
  "todos",
  "shell-snapshots",
  "ide",
  "logs",
  "statsig",
];

let started = false;
let timer = null;
let pendingPaths = new Set();
const watchers = [];

function isRelevantUnderHome(home, fullPath) {
  const rel = path.relative(home, fullPath);
  if (!rel || rel.startsWith("..")) return false;
  // First segment of the relative path
  const head = rel.split(path.sep)[0];
  if (IGNORED_PREFIXES.includes(head)) return false;
  if (!RELEVANT_PREFIXES.includes(head)) return false;
  return true;
}

function scheduleEmit(broadcast, p) {
  if (p) pendingPaths.add(p);
  if (timer) return;
  timer = setTimeout(() => {
    timer = null;
    const paths = Array.from(pendingPaths);
    pendingPaths = new Set();
    if (paths.length === 0) return;
    try {
      broadcast("cc_config_changed", { source: "fs", paths });
    } catch {
      /* ignore */
    }
  }, DEBOUNCE_MS);
}

function safeWatchHome({ home, broadcast }) {
  try {
    if (!fs.existsSync(home)) return;
    const w = fs.watch(home, { recursive: true }, (_event, filename) => {
      if (!filename) return;
      const full = path.join(home, filename);
      if (!isRelevantUnderHome(home, full)) return;
      scheduleEmit(broadcast, full);
    });
    w.on("error", () => {});
    watchers.push(w);
  } catch {
    /* platform limitation — best effort only */
  }
}

function safeWatchFile({ target, broadcast }) {
  try {
    if (!fs.existsSync(target)) return;
    const w = fs.watch(target, () => scheduleEmit(broadcast, target));
    w.on("error", () => {});
    watchers.push(w);
  } catch {
    /* ignore */
  }
}

/**
 * Start watching the Claude Code config surfaces. Idempotent: subsequent
 * calls are no-ops.
 */
function startCcWatcher({ broadcast }) {
  if (started) return;
  started = true;
  const home = getClaudeHome();
  safeWatchHome({ home, broadcast });
  // ~/.claude.json sits beside ~/.claude/, not inside it.
  safeWatchFile({ target: path.join(os.homedir(), ".claude.json"), broadcast });
}

function stopCcWatcher() {
  if (timer) {
    clearTimeout(timer);
    timer = null;
  }
  for (const w of watchers) {
    try {
      w.close();
    } catch {
      /* ignore */
    }
  }
  watchers.length = 0;
  pendingPaths = new Set();
  started = false;
}

module.exports = { startCcWatcher, stopCcWatcher, isRelevantUnderHome };

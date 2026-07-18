import { Cable, LoaderCircle, Play, Square, TerminalSquare } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebLinksAddon } from "@xterm/addon-web-links";
import "@xterm/xterm/css/xterm.css";

import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import { subscribeToTerminalStream } from "@/shared/terminal-stream";

export function TerminalPage() {
  const { snapshot, selectedSessionId, selectSession } = useAres();
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState("");
  const closeStreamRef = useRef<null | (() => void)>(null);
  const termRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const workspaceSessions = snapshot.sessions.filter(
    (session) => session.workspace && !session.readOnly,
  );

  // ── Create xterm instance once ──────────────────────────────────────
  useEffect(() => {
    const container = termRef.current;
    if (!container) return;

    const xterm = new Terminal({
      theme: {
        background: "#111210",
        foreground: "#ECEBE4",
        cursor: "#D7D6CE",
        cursorAccent: "#151614",
        selectionBackground: "rgba(244, 243, 236, 0.15)",
        selectionForeground: "#FAF9F3",
        black: "#151614",
        red: "#FF6B6B",
        green: "#10A37F",
        yellow: "#E6B15C",
        blue: "#6B8ADB",
        magenta: "#C792EA",
        cyan: "#56D4DD",
        white: "#ECEBE4",
        brightBlack: "#A7A79D",
        brightRed: "#FF8A8A",
        brightGreen: "#3ECF8E",
        brightYellow: "#F0C96A",
        brightBlue: "#8AAAF0",
        brightMagenta: "#D4A6F5",
        brightCyan: "#7AEAE6",
        brightWhite: "#FAF9F3",
      },
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
      fontSize: 13,
      lineHeight: 1.4,
      cursorBlink: true,
      scrollback: 5000,
    });

    const fitAddon = new FitAddon();
    const webLinksAddon = new WebLinksAddon();
    xterm.loadAddon(fitAddon);
    xterm.loadAddon(webLinksAddon);
    xterm.open(container);
    fitAddon.fit();

    xterm.write("\x1b[90mConnect a session workspace to start the terminal.\x1b[0m\r\n");

    xtermRef.current = xterm;
    fitAddonRef.current = fitAddon;

    return () => {
      xterm.dispose();
      xtermRef.current = null;
      fitAddonRef.current = null;
    };
  }, []);

  // ── Re-fit on window resize ─────────────────────────────────────────
  useEffect(() => {
    const handleResize = () => fitAddonRef.current?.fit();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  // ── Re-fit when connected state changes (layout shift) ──────────────
  useEffect(() => {
    requestAnimationFrame(() => fitAddonRef.current?.fit());
  }, [connected]);

  // ── Wire up xterm input → backend when connected ───────────────────
  useEffect(() => {
    const xterm = xtermRef.current;
    if (!connected || !xterm) return;
    const disposable = xterm.onData((data) => {
      void aresApi
        .terminalInput(selectedSessionId, data)
        .catch((reason) => setError(readableError(reason)));
    });
    return () => disposable.dispose();
  }, [connected, selectedSessionId]);

  // ── Cleanup stream on unmount ───────────────────────────────────────
  useEffect(() => () => closeStreamRef.current?.(), []);

  async function connect() {
    if (!selectedSessionId || !xtermRef.current) return;
    setConnecting(true);
    setError("");
    xtermRef.current.clear();
    xtermRef.current.focus();
    try {
      await aresApi.startTerminal(selectedSessionId);
      closeStreamRef.current?.();
      closeStreamRef.current = subscribeToTerminalStream(selectedSessionId, {
        open: () => {
          setConnected(true);
          requestAnimationFrame(() => fitAddonRef.current?.fit());
        },
        output: (text) => xtermRef.current?.write(text),
        closed: () => {
          setConnected(false);
          closeStreamRef.current = null;
          xtermRef.current?.write("\r\n\x1b[90m[Terminal closed]\x1b[0m\r\n");
        },
        error: (message) => {
          setError(message);
          setConnected(false);
          xtermRef.current?.write(`\r\n\x1b[31m${message}\x1b[0m\r\n`);
        },
      });
    } catch (reason) {
      const msg = readableError(reason, "Terminal transport is unavailable.");
      setError(msg);
      xtermRef.current?.write(`\r\n\x1b[31m${msg}\x1b[0m\r\n`);
    } finally {
      setConnecting(false);
    }
  }

  async function disconnect() {
    if (selectedSessionId)
      await aresApi.closeTerminal(selectedSessionId).catch(() => undefined);
    closeStreamRef.current?.();
    closeStreamRef.current = null;
    setConnected(false);
  }

  const disabled = snapshot.terminalRemoteBackend || !selectedSessionId;

  return (
    <div className="page-stack h-full">
      <PageHeader
        title="Terminal"
        description="A terminal for the selected local session workspace, supplied by the ARES controller rather than an assistant framework."
        action={
          connected ? (
            <Button variant="outline" onClick={() => void disconnect()}>
              <Square />
              Close
            </Button>
          ) : (
            <Button
              variant="outline"
              disabled={disabled || connecting}
              onClick={() => void connect()}
            >
              {connecting ? <LoaderCircle className="animate-spin" /> : <Play />}
              Connect
            </Button>
          )
        }
      />
      {workspaceSessions.length ? (
        <select
          className="max-w-xl rounded-md border bg-background px-3 py-2 text-sm"
          value={
            workspaceSessions.some((item) => item.id === selectedSessionId)
              ? selectedSessionId
              : ""
          }
          onChange={(event) => selectSession(event.target.value)}
          disabled={connected}
        >
          <option value="" disabled>
            Select a session workspace
          </option>
          {workspaceSessions.map((session) => (
            <option key={session.id} value={session.id}>
              {session.title} — {session.workspace}
            </option>
          ))}
        </select>
      ) : null}
      <section
        className="terminal-surface flex min-h-96 flex-1 flex-col"
        aria-label="Terminal"
      >
        <div className="flex items-center gap-2 border-b border-white/10 px-4 py-3 text-xs text-slate-400">
          <TerminalSquare className="size-4" />
          local shell · {connected ? "connected" : "disconnected"}
        </div>
        <div ref={termRef} className="min-h-0 flex-1 px-1 py-1" />
        {error ? (
          <p className="border-t border-white/10 px-4 py-2 text-xs text-amber-300">
            {error}
          </p>
        ) : null}
      </section>
      {!workspaceSessions.length ? (
        <p className="flex items-center gap-2 text-xs text-muted-foreground">
          <Cable className="size-3" />
          Create a conversation with a local workspace before opening a terminal.
        </p>
      ) : null}
    </div>
  );
}
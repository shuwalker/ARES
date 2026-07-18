import { Cable, LoaderCircle, Play, Send, Square, TerminalSquare } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent } from "react";

import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import { useAres } from "@/shared/ares-context";
import { subscribeToTerminalStream } from "@/shared/terminal-stream";

export function TerminalPage() {
  const { snapshot, selectedSessionId, selectSession } = useAres();
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [output, setOutput] = useState("");
  const [input, setInput] = useState("");
  const [error, setError] = useState("");
  const closeStreamRef = useRef<null | (() => void)>(null);
  const workspaceSessions = snapshot.sessions.filter((session) => session.workspace && !session.readOnly);

  useEffect(() => () => closeStreamRef.current?.(), []);

  async function connect() {
    if (!selectedSessionId) return;
    setConnecting(true); setError("");
    try {
      await aresApi.startTerminal(selectedSessionId);
      closeStreamRef.current?.();
      closeStreamRef.current = subscribeToTerminalStream(selectedSessionId, {
        open: () => setConnected(true),
        output: (text) => setOutput((value) => value + text),
        closed: () => { setConnected(false); closeStreamRef.current = null; },
        error: (message) => { setError(message); setConnected(false); },
      });
    } catch (reason) { setError(readableError(reason, "Terminal transport is unavailable.")); }
    finally { setConnecting(false); }
  }

  async function disconnect() {
    if (selectedSessionId) await aresApi.closeTerminal(selectedSessionId).catch(() => undefined);
    closeStreamRef.current?.(); closeStreamRef.current = null; setConnected(false);
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    if (!input || !connected) return;
    const data = `${input}\n`;
    setInput("");
    void aresApi.terminalInput(selectedSessionId, data).catch((reason) => setError(readableError(reason)));
  }

  const disabled = snapshot.terminalRemoteBackend || !selectedSessionId;
  return (
    <div className="page-stack h-full">
      <PageHeader title="Terminal" description="A terminal for the selected local session workspace, supplied by the ARES controller rather than an assistant framework." action={connected ? <Button variant="outline" onClick={() => void disconnect()}><Square />Close</Button> : <Button variant="outline" disabled={disabled || connecting} onClick={() => void connect()}>{connecting ? <LoaderCircle className="animate-spin" /> : <Play />}Connect</Button>} />
      {workspaceSessions.length ? <select className="max-w-xl rounded-md border bg-background px-3 py-2 text-sm" value={workspaceSessions.some((item) => item.id === selectedSessionId) ? selectedSessionId : ""} onChange={(event) => selectSession(event.target.value)} disabled={connected}><option value="" disabled>Select a session workspace</option>{workspaceSessions.map((session) => <option key={session.id} value={session.id}>{session.title} — {session.workspace}</option>)}</select> : null}
      <section className="terminal-surface flex min-h-96 flex-1 flex-col" aria-label="Terminal">
        <div className="flex items-center gap-2 border-b border-white/10 px-4 py-3 text-xs text-slate-400"><TerminalSquare className="size-4" />local shell · {connected ? "connected" : "disconnected"}</div>
        <pre className="min-h-0 flex-1 overflow-auto whitespace-pre-wrap p-4 font-mono text-sm text-slate-300">{output || (snapshot.terminalRemoteBackend ? "Embedded terminal is only supported for local terminal backends." : "Connect a session workspace to start the terminal.")}</pre>
        {error ? <p className="border-t border-white/10 px-4 py-2 text-xs text-amber-300">{error}</p> : null}
        <form onSubmit={submit} className="flex gap-2 border-t border-white/10 p-3"><Input value={input} onChange={(event) => setInput(event.target.value)} disabled={!connected} className="border-white/10 bg-white/5 font-mono text-slate-200" placeholder={connected ? "Enter a command" : "Terminal disconnected"} /><Button size="icon" disabled={!connected || !input}><Send /></Button></form>
      </section>
      {!workspaceSessions.length ? <p className="flex items-center gap-2 text-xs text-muted-foreground"><Cable className="size-3" />Create a conversation with a local workspace before opening a terminal.</p> : null}
    </div>
  );
}

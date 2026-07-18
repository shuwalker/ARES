import {
  Bot,
  Check,
  ChevronDown,
  CircleDot,
  Copy,
  LoaderCircle,
  MessageCircle,
  PanelRight,
  Plus,
  Search,
  Send,
  Square,
  Star,
  Terminal,
  UserRound,
  Wrench,
} from "lucide-react";
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent,
} from "react";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { useAres } from "@/shared/ares-context";
import { useLocalProfile } from "@/shared/local-profile";
import type { SessionSummary } from "@/shared/contracts";

function relativeSessionTime(value?: string) {
  if (!value) return "";
  const elapsed = Math.max(0, Date.now() - new Date(value).getTime());
  const minutes = Math.floor(elapsed / 60_000);
  if (minutes < 1) return "now";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d`;
  return new Date(value).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function sessionDateGroup(session: SessionSummary) {
  if (session.pinned) return "★ Pinned";
  if (!session.updatedAt) return "Older";
  const now = new Date();
  const updated = new Date(session.updatedAt);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const day = new Date(updated.getFullYear(), updated.getMonth(), updated.getDate());
  const days = Math.floor((today.getTime() - day.getTime()) / 86_400_000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  if (days < 7) return "This week";
  if (days < 14) return "Last week";
  return "Older";
}

export function ConversationPage() {
  const { profile } = useLocalProfile();
  const {
    snapshot,
    currentSession,
    selectedSessionId,
    selectSession,
    createSession,
    sendMessage,
    streamText,
    streamReasoning,
    streamTools,
    streamState,
    chatNotice,
    cancelResponse,
  } = useAres();
  const [draft, setDraft] = useState("");
  const [railOpen, setRailOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [sessionSearch, setSessionSearch] = useState("");
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(() => {
    try {
      return new Set(JSON.parse(localStorage.getItem("ares.chat.session-groups-collapsed") || "[]") as string[]);
    } catch {
      return new Set();
    }
  });
  const transcriptRef = useRef<HTMLDivElement>(null);
  const assistantName = snapshot.settings?.assistantName || profile.assistantName || "ARES";
  const activeModel = currentSession?.model || "Hermes Agent";
  const isBusy = streamState !== "idle";
  const hasConversation = Boolean(currentSession?.messages.length || streamText || isBusy);
  const sessionGroups = useMemo(() => {
    const query = sessionSearch.trim().toLowerCase();
    const groups = new Map<string, SessionSummary[]>();
    snapshot.sessions
      .filter((session) => !query || `${session.title} ${session.workspace} ${session.model}`.toLowerCase().includes(query))
      .sort((a, b) => Number(b.pinned) - Number(a.pinned) || String(b.updatedAt || "").localeCompare(String(a.updatedAt || "")))
      .forEach((session) => {
        const label = sessionDateGroup(session);
        groups.set(label, [...(groups.get(label) || []), session]);
      });
    return [...groups.entries()];
  }, [sessionSearch, snapshot.sessions]);

  useEffect(() => {
    const transcript = transcriptRef.current;
    if (!transcript) return;
    transcript.scrollTo({ top: transcript.scrollHeight, behavior: streamText ? "auto" : "smooth" });
  }, [currentSession?.messages.length, streamReasoning, streamText, streamTools, streamState]);

  useEffect(() => {
    localStorage.setItem("ares.chat.session-groups-collapsed", JSON.stringify([...collapsedGroups]));
  }, [collapsedGroups]);

  function submit(event: FormEvent) {
    event.preventDefault();
    const message = draft.trim();
    if (!message || isBusy) return;
    setDraft("");
    void sendMessage(message);
  }

  function handleComposerKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      event.currentTarget.form?.requestSubmit();
    }
  }

  async function copyLastResponse() {
    const lastAssistant = [...(currentSession?.messages || [])]
      .reverse()
      .find((message) => message.role !== "user")?.text;
    const text = streamText || lastAssistant;
    if (!text) return;
    await navigator.clipboard.writeText(text);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  const rail = (
    <aside className="flex h-full min-h-0 flex-col overflow-hidden rounded-lg border bg-card shadow-sm">
      <div className="border-b p-3">
        <div className="flex items-center gap-2 text-sm font-semibold">
          <span className={cn(
            "size-2 rounded-full",
            snapshot.connection === "available" ? "bg-status-available" :
              snapshot.connection === "limited" ? "bg-status-limited" : "bg-status-unavailable",
          )} />
          {assistantName}
        </div>
        <div className="mt-3 rounded-md border bg-muted/45 px-3 py-2">
          <p className="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">Model</p>
          <p className="mt-1 truncate text-xs font-medium" title={activeModel}>{activeModel}</p>
        </div>
        <Button className="mt-3 w-full" size="sm" onClick={() => void createSession()}>
          <Plus /> New chat
        </Button>
      </div>

      <div className="flex min-h-0 flex-1 flex-col">
        <div className="px-3 pb-2 pt-3">
          <div className="flex items-center justify-between">
            <p className="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">Sessions</p>
            <span className="text-xs text-muted-foreground">{snapshot.sessions.length}</span>
          </div>
          <label className="mt-2 flex h-8 items-center gap-2 rounded-md border bg-background px-2 text-muted-foreground focus-within:border-ring focus-within:text-foreground">
            <Search className="size-3.5 shrink-0" />
            <input
              value={sessionSearch}
              onChange={(event) => setSessionSearch(event.target.value)}
              placeholder="Search sessions"
              className="min-w-0 flex-1 bg-transparent text-xs text-foreground outline-none placeholder:text-muted-foreground"
            />
          </label>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-2 pb-2">
          {sessionGroups.length ? sessionGroups.map(([label, sessions]) => {
            const collapsed = collapsedGroups.has(label);
            return (
              <section key={label} className="mb-2">
                <button
                  type="button"
                  onClick={() => setCollapsedGroups((previous) => {
                    const next = new Set(previous);
                    if (next.has(label)) next.delete(label);
                    else next.add(label);
                    return next;
                  })}
                  className="flex w-full items-center gap-1 px-1.5 py-1 text-[0.62rem] font-semibold uppercase tracking-[0.12em] text-muted-foreground hover:text-foreground"
                  aria-expanded={!collapsed}
                >
                  <ChevronDown className={cn("size-3 transition-transform", collapsed && "-rotate-90")} />
                  <span>{label}</span>
                  <span className="ml-auto font-normal tracking-normal opacity-60">{sessions.length}</span>
                </button>
                {!collapsed ? <div className="space-y-0.5">
                  {sessions.map((session) => {
                    const active = selectedSessionId === session.id;
                    return (
                      <button
                        key={session.id}
                        type="button"
                        onClick={() => {
                          selectSession(session.id);
                          setRailOpen(false);
                        }}
                        className={cn(
                          "group relative w-full overflow-hidden rounded-md border px-2.5 py-2 text-left transition-colors",
                          active
                            ? "border-border bg-accent pl-4 text-accent-foreground"
                            : "border-transparent text-muted-foreground hover:bg-muted hover:text-foreground",
                        )}
                        aria-current={active ? "true" : undefined}
                      >
                        {active ? <span className="absolute bottom-2 left-1.5 top-2 w-0.5 rounded-full bg-primary/70" /> : null}
                        <span className="flex min-w-0 items-center gap-1.5">
                          {session.pinned ? <Star className="size-3 shrink-0 fill-current opacity-65" /> : null}
                          <span className="min-w-0 flex-1 truncate text-xs font-medium">{session.title || "Untitled chat"}</span>
                          {session.isStreaming ? (
                            <span className="flex shrink-0 items-center gap-1 text-[0.6rem] text-status-available">
                              <span className="size-1.5 animate-pulse rounded-full bg-current" /> live
                            </span>
                          ) : (
                            <span className="shrink-0 text-[0.62rem] text-muted-foreground/70">{relativeSessionTime(session.updatedAt)}</span>
                          )}
                        </span>
                        <span className="mt-1 flex min-w-0 items-center gap-1.5 truncate text-[0.64rem] text-muted-foreground/75">
                          <span>{session.messageCount} {session.messageCount === 1 ? "msg" : "msgs"}</span>
                          {session.model ? <><span aria-hidden="true">·</span><span className="truncate">{session.model}</span></> : null}
                          {session.readOnly ? <><span aria-hidden="true">·</span><span>read-only</span></> : null}
                        </span>
                      </button>
                    );
                  })}
                </div> : null}
              </section>
            );
          }) : (
            <p className="px-3 py-6 text-center text-xs text-muted-foreground">{sessionSearch ? "No matching sessions." : "No chat sessions yet."}</p>
          )}
        </div>
      </div>
    </aside>
  );

  return (
    <div className="flex h-[calc(100dvh-4rem)] min-h-[32rem] flex-col gap-3 p-3 md:p-4">
      {railOpen ? (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button
            type="button"
            aria-label="Close chat sidebar"
            className="absolute inset-0 bg-black/60"
            onClick={() => setRailOpen(false)}
          />
          <div className="absolute bottom-0 right-0 top-0 w-72 p-3">{rail}</div>
        </div>
      ) : null}

      {chatNotice ? (
        <div className="shrink-0 rounded-md border border-status-limited/40 bg-status-limited/10 px-3 py-2 text-xs text-status-limited">
          {chatNotice}
        </div>
      ) : null}

      <div className="flex min-h-0 flex-1 gap-3">
        <section className="relative flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded-xl border border-white/10 bg-[#080a0f] text-[#ece7dc] shadow-[0_14px_45px_rgba(0,0,0,0.38)]">
          <header className="flex h-12 shrink-0 items-center gap-3 border-b border-white/10 bg-white/[0.025] px-4">
            <div className="flex gap-1.5" aria-hidden="true">
              <span className="size-2.5 rounded-full bg-[#ff605c]" />
              <span className="size-2.5 rounded-full bg-[#ffbd44]" />
              <span className="size-2.5 rounded-full bg-[#00ca4e]" />
            </div>
            <div className="min-w-0 flex-1 text-center">
              <p className="truncate text-xs font-medium text-white/75">{currentSession?.title || "New chat"}</p>
            </div>
            <Button
              type="button"
              size="icon-sm"
              variant="ghost"
              className="border border-white/10 bg-white/[0.04] text-white/70 hover:bg-white/10 hover:text-white lg:hidden"
              aria-label="Open chat sidebar"
              onClick={() => setRailOpen(true)}
            >
              <PanelRight />
            </Button>
          </header>

          <div
            ref={transcriptRef}
            className="min-h-0 flex-1 overflow-y-auto px-4 py-5 font-mono text-[0.82rem] leading-6 sm:px-7 lg:px-10"
            aria-live="polite"
          >
            {!hasConversation ? (
              <div className="grid h-full place-items-center">
                <div className="w-full max-w-md px-4 text-center">
                  <div className="mx-auto grid size-12 place-items-center rounded-lg border border-white/10 bg-white/[0.04]">
                    <Terminal className="size-5 text-[#d9cba9]" />
                  </div>
                  <h2 className="mt-4 font-sans text-lg font-semibold text-white">Start a chat with {assistantName}</h2>
                  <p className="mt-2 break-words font-sans text-sm leading-6 text-white/45">
                    Type below. Your messages, streaming responses, reasoning, and tool activity stay together in this window.
                  </p>
                </div>
              </div>
            ) : (
              <div className="mx-auto w-full max-w-4xl space-y-7">
                {currentSession?.messages.map((message) => {
                  const isUser = message.role === "user";
                  return (
                    <article key={message.id} className="grid grid-cols-[1.5rem_minmax(0,1fr)] gap-3">
                      <div className={cn(
                        "mt-0.5 grid size-6 place-items-center rounded border",
                        isUser ? "border-[#7aa2f7]/35 bg-[#7aa2f7]/10 text-[#9ab8f7]" : "border-[#d9cba9]/30 bg-[#d9cba9]/10 text-[#d9cba9]",
                      )}>
                        {isUser ? <UserRound className="size-3.5" /> : <Bot className="size-3.5" />}
                      </div>
                      <div className="min-w-0">
                        <p className={cn("mb-1 text-[0.68rem] font-semibold uppercase tracking-[0.12em]", isUser ? "text-[#9ab8f7]" : "text-[#d9cba9]")}>{isUser ? "You" : assistantName}</p>
                        <p className="whitespace-pre-wrap break-words text-white/88">{message.text}</p>
                      </div>
                    </article>
                  );
                })}

                {streamReasoning ? (
                  <details className="ml-9 rounded-md border border-white/10 bg-white/[0.025] px-3 py-2 text-white/50">
                    <summary className="cursor-pointer select-none text-[0.68rem] uppercase tracking-[0.12em]">Reasoning</summary>
                    <p className="mt-2 whitespace-pre-wrap break-words">{streamReasoning}</p>
                  </details>
                ) : null}

                {streamTools.length ? (
                  <div className="ml-9 flex flex-wrap items-center gap-2 text-[0.7rem] text-white/45">
                    <Wrench className="size-3.5" />
                    {streamTools.map((tool) => <span key={tool} className="rounded border border-white/10 bg-white/[0.03] px-2 py-0.5">{tool}</span>)}
                  </div>
                ) : null}

                {streamText ? (
                  <article className="grid grid-cols-[1.5rem_minmax(0,1fr)] gap-3">
                    <div className="mt-0.5 grid size-6 place-items-center rounded border border-[#d9cba9]/30 bg-[#d9cba9]/10 text-[#d9cba9]">
                      <Bot className="size-3.5" />
                    </div>
                    <div className="min-w-0">
                      <p className="mb-1 text-[0.68rem] font-semibold uppercase tracking-[0.12em] text-[#d9cba9]">{assistantName}</p>
                      <p className="whitespace-pre-wrap break-words text-white/88">{streamText}<span className="ml-1 inline-block h-4 w-1.5 animate-pulse bg-[#d9cba9] align-middle" /></p>
                    </div>
                  </article>
                ) : null}

                {isBusy && !streamText ? (
                  <div className="ml-9 flex items-center gap-2 text-white/45">
                    <LoaderCircle className="size-4 animate-spin" />
                    {streamState === "starting" ? "Starting response…" : "Working…"}
                  </div>
                ) : null}
              </div>
            )}
          </div>

          <div className="shrink-0 border-t border-white/10 bg-black/25 p-3 sm:p-4">
            <form onSubmit={submit} className="mx-auto max-w-4xl">
              <div className="flex items-end gap-2 rounded-lg border border-white/15 bg-white/[0.045] p-2 shadow-inner focus-within:border-[#d9cba9]/45">
                <Textarea
                  value={draft}
                  onChange={(event) => setDraft(event.target.value)}
                  onKeyDown={handleComposerKeyDown}
                  rows={2}
                  aria-label="Message"
                  placeholder={`Message ${assistantName}…`}
                  className="max-h-40 min-h-12 min-w-0 w-0 flex-1 resize-none border-0 bg-transparent px-2 py-2 font-mono text-[0.82rem] text-white shadow-none placeholder:text-white/30 focus-visible:ring-0"
                  disabled={currentSession?.readOnly || isBusy}
                />
                {isBusy ? (
                  <Button type="button" size="icon" variant="outline" className="border-white/15 bg-white/5 text-white hover:bg-white/10" aria-label="Stop response" onClick={() => void cancelResponse()}>
                    <Square />
                  </Button>
                ) : (
                  <Button type="submit" size="icon" className="bg-[#d9cba9] text-[#111318] hover:bg-[#eee3c9]" aria-label="Send message" disabled={!draft.trim()}>
                    <Send />
                  </Button>
                )}
              </div>
              <p className="mt-2 text-center font-sans text-[0.65rem] text-white/30">Enter to send · Shift+Enter for a new line</p>
            </form>
          </div>

          <Button
            type="button"
            size="sm"
            variant="ghost"
            onClick={() => void copyLastResponse()}
            disabled={!streamText && !currentSession?.messages.some((message) => message.role !== "user")}
            className="absolute bottom-[6.35rem] right-3 h-7 border border-white/10 bg-black/40 px-2 text-[0.65rem] text-white/45 backdrop-blur hover:bg-black/70 hover:text-white sm:bottom-[6.85rem] sm:right-4"
            aria-label="Copy last assistant response"
          >
            {copied ? <Check className="size-3" /> : <Copy className="size-3" />}
            {copied ? "Copied" : "Copy last"}
          </Button>
        </section>

        <div className="hidden min-h-0 w-60 shrink-0 lg:block">{rail}</div>
      </div>

      <div className="flex shrink-0 items-center gap-4 px-1 text-[0.68rem] text-muted-foreground">
        <span className="flex items-center gap-1.5"><CircleDot className="size-3" />{snapshot.connection === "available" ? "Connected" : snapshot.connection}</span>
        <span className="flex items-center gap-1.5"><MessageCircle className="size-3" />{currentSession?.messages.length || 0} messages</span>
        {streamTools.length ? <span className="flex items-center gap-1.5"><Wrench className="size-3" />{streamTools.length} active tools</span> : null}
      </div>
    </div>
  );
}

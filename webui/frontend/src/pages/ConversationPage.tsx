import {
  ArrowDown,
  Bot,
  Check,
  Copy,
  LoaderCircle,
  Send,
  Square,
  Terminal,
  UserRound,
  Wrench,
} from "lucide-react";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent,
} from "react";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Markdown } from "@/components/Markdown";
import { useAres } from "@/shared/ares-context";
import { useLocalProfile } from "@/shared/local-profile";

// ── Old ARES Graphite dark palette ──
const G = {
  bg: "#151614",
  sidebar: "#242624",
  surface: "#1B1C1A",
  surfaceSubtle: "#20211F",
  surfaceSubtleHover: "#292B28",
  border: "#343631",
  border2: "#4B4D47",
  text: "#ECEBE4",
  strong: "#FAF9F3",
  muted: "#A7A79D",
  accent: "#D7D6CE",
  accentHover: "#F4F3EC",
  accentBg: "rgba(255,255,255,0.08)",
  accentBgStrong: "rgba(255,255,255,0.14)",
  accentText: "#D7D6CE",
  inputBg: "#1E1F1D",
  focusRing: "rgba(244,243,236,0.22)",
  codeBg: "#111210",
  userBubbleBg: "#2E302D",
  userBubbleBorder: "#454741",
  userBubbleText: "#F4F3EC",
  success: "#10A37F",
  warning: "#E6B15C",
  error: "#FF6B6B",
};

const SUGGESTIONS = [
  { icon: "📁", text: "What files are in this workspace?" },
  { icon: "📅", text: "What's on my schedule today?" },
  { icon: "🗺️", text: "Help me plan a small project." },
];

function backendLabel(id: string): string {
  const labels: Record<string, string> = {
    hermes_local: "Hermes Agent",
    jros_local: "JROS",
    claude_local: "Claude Code",
    codex_local: "OpenAI Codex",
    gemini_local: "Google Gemini",
    grok_local: "xAI Grok",
    opencode_local: "OpenCode",
    cursor_local: "Cursor",
    pi_local: "Pi Coding Agent",
    openai_cloud: "OpenAI",
    xai_cloud: "xAI Grok",
    ollama_local: "Ollama",
  };
  return labels[id] || id.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}





export function ConversationPage() {
  const { profile } = useLocalProfile();
  const {
    snapshot,
    currentSession,
    selectedSessionId,
    sendMessage,
    streamText,
    streamReasoning,
    streamTools,
    streamState,
    chatNotice,
    cancelResponse,
  } = useAres();

  const [draft, setDraft] = useState("");
  const [copied, setCopied] = useState(false);
  const [showScrollBottom, setShowScrollBottom] = useState(false);
  const [selectedBackend, setSelectedBackend] = useState<string>(() => {
    return currentSession?.backendId || snapshot.backends.find((b) => b.available)?.id || "";
  });
  const transcriptRef = useRef<HTMLDivElement>(null);

  const assistantName = snapshot.settings?.assistantName || profile.assistantName || "ARES";
  const isBusy = streamState !== "idle";
  const hasConversation = Boolean(currentSession?.messages.length || streamText || isBusy);

  const activeStreamId = currentSession?.activeStreamId;

  useEffect(() => {
    if (currentSession?.backendId) {
      setSelectedBackend(currentSession.backendId);
    }
  }, [currentSession?.backendId]);

  // Auto-scroll to bottom on new content
  useEffect(() => {
    const el = transcriptRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
    if (nearBottom || streamText) {
      el.scrollTo({ top: el.scrollHeight, behavior: streamText ? "auto" : "smooth" });
    }
  }, [currentSession?.messages.length, streamText, streamReasoning, streamTools, streamState]);

  const onScroll = useCallback(() => {
    const el = transcriptRef.current;
    if (!el) return;
    setShowScrollBottom(el.scrollHeight - el.scrollTop - el.clientHeight > 120);
  }, []);

  const submit = useCallback((event: FormEvent) => {
    event.preventDefault();
    const message = draft.trim();
    if (!message || isBusy) return;
    setDraft("");
    void sendMessage(message, selectedBackend);
  }, [draft, isBusy, sendMessage, selectedBackend]);

  const handleComposerKeyDown = useCallback((event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      event.currentTarget.form?.requestSubmit();
    }
  }, []);

  const copyLastResponse = useCallback(async () => {
    const lastAssistant = [...(currentSession?.messages || [])]
      .reverse()
      .find((message) => message.role !== "user")?.text;
    const text = streamText || lastAssistant;
    if (!text) return;
    await navigator.clipboard.writeText(text);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }, [currentSession?.messages, streamText]);

  const lastAssistantText = useMemo(() => {
    if (streamText) return streamText;
    const last = [...(currentSession?.messages || [])].reverse().find((m) => m.role !== "user");
    return last?.text;
  }, [currentSession?.messages, streamText]);

  return (
    <div
      className="flex min-h-0 flex-1 flex-col"
      style={{ backgroundColor: G.bg, color: G.text }}
    >
      {/* ── Messages shell ── */}
      <div
        ref={transcriptRef}
        onScroll={onScroll}
        className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden"
        style={{ backgroundColor: G.bg }}
        aria-live="polite"
      >
        {!hasConversation ? (
          /* ── Empty state ── */
          <div
            className="flex h-full flex-col items-center justify-center px-6 py-10"
            style={{
              background: "radial-gradient(ellipse at 50% 20%, rgba(255,255,255,0.05) 0%, transparent 55%)",
            }}
          >
            <div
              className="mb-4 grid size-16 place-items-center rounded-2xl border"
              style={{ borderColor: G.border, backgroundColor: G.surfaceSubtle }}
            >
              <Terminal size={28} style={{ color: G.accent }} />
            </div>
            <h1 className="text-xl font-semibold" style={{ color: G.strong }}>What can I help with?</h1>
            <p className="mt-1 max-w-sm text-center text-[13px]" style={{ color: G.muted }}>
              Ask anything, run commands, explore files, or manage your scheduled tasks.
            </p>
            <div className="mt-5 flex w-full max-w-sm flex-col gap-2">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s.text}
                  type="button"
                  className="flex items-center gap-2 rounded-lg border px-3 py-2.5 text-left text-[13px] transition-all"
                  style={{
                    borderColor: G.border,
                    backgroundColor: G.inputBg,
                    color: G.muted,
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.borderColor = G.border2;
                    e.currentTarget.style.backgroundColor = G.accentBg;
                    e.currentTarget.style.color = G.text;
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.borderColor = G.border;
                    e.currentTarget.style.backgroundColor = G.inputBg;
                    e.currentTarget.style.color = G.muted;
                  }}
                  onClick={() => {
                    setDraft(s.text);
                    (document.querySelector('textarea[aria-label="Message"]') as HTMLTextAreaElement | null)?.focus();
                  }}
                >
                  <span className="text-base">{s.icon}</span>
                  <span>{s.text}</span>
                </button>
              ))}
            </div>

            {/* Backend selector for new conversations */}
            <div className="mt-6 flex flex-wrap items-center justify-center gap-2">
              {snapshot.backends.map((backend) => (
                <button
                  key={backend.id}
                  type="button"
                  onClick={() => setSelectedBackend(backend.id)}
                  disabled={!backend.available}
                  className="rounded-md border px-2.5 py-1 text-[11px] transition-all"
                  style={{
                    borderColor: selectedBackend === backend.id ? G.accent : G.border,
                    backgroundColor: selectedBackend === backend.id ? G.accentBg : G.surface,
                    color: backend.available ? (selectedBackend === backend.id ? G.accentText : G.muted) : "rgba(255,255,255,0.3)",
                    cursor: backend.available ? "pointer" : "not-allowed",
                  }}
                >
                  {backendLabel(backend.id)}
                  {!backend.available && (
                    <span className="ml-1.5 inline-block size-1.5 rounded-full bg-red-500" />
                  )}
                </button>
              ))}
            </div>
          </div>
        ) : (
          /* ── Messages ── */
          <div className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-5 pb-28 pt-6">
            {(currentSession?.messages || []).map((message) => {
              const isUser = message.role === "user";
              return (
                <div
                  key={message.id}
                  className={`flex w-full ${isUser ? "justify-end" : "justify-start"}`}
                >
                  {!isUser && (
                    <div className="mr-2 mt-1 flex h-7 w-7 shrink-0 items-center justify-center rounded-md" style={{ backgroundColor: G.surfaceSubtle }}>
                      <Bot size={16} style={{ color: G.accent }} />
                    </div>
                  )}
                  <div
                    className={`max-w-[85%] rounded-2xl px-4 py-2.5 text-[14px] leading-[1.45] ${isUser ? "rounded-tr-sm" : "rounded-tl-sm"}`}
                    style={{
                      backgroundColor: isUser ? G.userBubbleBg : G.surfaceSubtle,
                      color: isUser ? G.userBubbleText : G.text,
                      border: isUser ? `1px solid ${G.userBubbleBorder}` : "1px solid transparent",
                      whiteSpace: "pre-wrap",
                      wordBreak: "break-word",
                    }}
                    children={<Markdown content={message.text} />}
                  />
                </div>
              );
            })}

            {streamState !== "idle" && (
              <div className="flex w-full justify-start">
                <div className="mr-2 mt-1 flex h-7 w-7 shrink-0 items-center justify-center rounded-md" style={{ backgroundColor: G.surfaceSubtle }}>
                  <Bot size={16} style={{ color: G.accent }} />
                </div>
                <div
                  className="max-w-[85%] rounded-2xl rounded-tl-sm px-4 py-2.5 text-[14px] leading-[1.45]"
                  style={{ backgroundColor: G.surfaceSubtle, color: G.text }}
                >
                  {streamText ? (
                    <Markdown content={streamText} streaming />
                  ) : streamState === "starting" ? (
                    <div className="flex items-center gap-2">
                      <LoaderCircle size={16} className="animate-spin" />
                      <span style={{ color: G.muted }}>Starting…</span>
                    </div>
                  ) : (
                    <div className="flex items-center gap-2">
                      <span className="inline-block size-2 animate-pulse rounded-full" style={{ backgroundColor: G.accent }} />
                      <span style={{ color: G.muted }}>Thinking…</span>
                    </div>
                  )}

                  {streamReasoning ? (
                    <div className="mt-2 border-t border-dashed pt-2 text-[12px] italic" style={{ borderColor: G.border, color: G.muted }}>
                      {streamReasoning}
                    </div>
                  ) : null}

                  {streamTools.length > 0 ? (
                    <div className="mt-2 flex flex-wrap gap-1">
                      {streamTools.map((tool) => (
                        <span
                          key={tool}
                          className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px]"
                          style={{ backgroundColor: G.accentBg, color: G.accentText }}
                        >
                          <Wrench size={10} />
                          {tool}
                        </span>
                      ))}
                    </div>
                  ) : null}
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* ── Composer ── */}
      <div className="shrink-0 px-4 pb-4 pt-2" style={{ backgroundColor: G.bg }}>
        {chatNotice ? (
          <div
            className="mb-2 rounded-md border px-3 py-2 text-xs"
            style={{ borderColor: `${G.warning}40`, backgroundColor: `${G.warning}10`, color: G.warning }}
          >
            {chatNotice}
          </div>
        ) : null}

        <form onSubmit={submit} className="mx-auto w-full max-w-3xl">
          <div
            className="flex items-end gap-2 rounded-[14px] border p-2 shadow-sm transition-[border-color,box-shadow] duration-200"
            style={{
              backgroundColor: G.surface,
              borderColor: G.border2,
            }}
          >
            <Textarea
              value={draft}
              onChange={(event) => setDraft(event.target.value)}
              onKeyDown={handleComposerKeyDown}
              rows={2}
              aria-label="Message"
              placeholder={`Message ${assistantName}…`}
              className="max-h-40 min-h-12 min-w-0 flex-1 resize-none border-0 bg-transparent px-2 py-2 text-[14px] leading-[1.45] shadow-none placeholder:text-white/30 focus-visible:ring-0"
              style={{
                color: G.text,
                fontWeight: 430,
              }}
              disabled={currentSession?.readOnly || isBusy}
            />
            {isBusy ? (
              <Button
                type="button"
                size="icon"
                variant="outline"
                className="h-9 w-9 shrink-0 border text-white hover:bg-white/10"
                style={{ borderColor: "rgba(255,255,255,0.15)", backgroundColor: "rgba(255,255,255,0.05)" }}
                aria-label="Stop response"
                onClick={() => void cancelResponse()}
              >
                <Square size={14} />
              </Button>
            ) : (
              <Button
                type="submit"
                size="icon"
                className="h-9 w-9 shrink-0 rounded-lg"
                style={{
                  backgroundColor: draft.trim() ? G.accent : "rgba(255,255,255,0.08)",
                  color: draft.trim() ? G.bg : "rgba(255,255,255,0.4)",
                }}
                aria-label="Send message"
                disabled={!draft.trim()}
              >
                <Send size={16} />
              </Button>
            )}
          </div>
          <div className="mt-1.5 flex items-center justify-between text-[0.65rem]" style={{ color: "rgba(255,255,255,0.3)" }}>
            <span>Enter to send · Shift+Enter for a new line</span>
            {selectedBackend && (
              <span className="rounded px-1.5 py-0.5" style={{ backgroundColor: G.accentBg, color: G.accentText }}>
                → {backendLabel(selectedBackend)}
              </span>
            )}
          </div>
        </form>

        {/* Copy last / scroll bottom */}
        <div className="pointer-events-none absolute bottom-20 right-4 flex flex-col items-end gap-2">
          {showScrollBottom ? (
            <button
              type="button"
              onClick={() => transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: "smooth" })}
              className="pointer-events-auto flex items-center gap-1 rounded-md border px-2 py-1 text-[11px] shadow-sm"
              style={{ borderColor: G.border, backgroundColor: G.surfaceSubtle, color: G.muted }}
            >
              <ArrowDown size={12} /> Bottom
            </button>
          ) : null}
          {lastAssistantText ? (
            <button
              type="button"
              onClick={() => void copyLastResponse()}
              className="pointer-events-auto flex items-center gap-1 rounded-md border px-2 py-1 text-[11px] shadow-sm"
              style={{ borderColor: G.border, backgroundColor: G.surfaceSubtle, color: G.muted }}
            >
              {copied ? <Check size={12} /> : <Copy size={12} />}
              {copied ? "Copied" : "Copy"}
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

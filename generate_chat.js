const fs = require('fs');
const path = require('path');

const content = `import {
  ArrowDown,
  Bot,
  Check,
  Copy,
  LoaderCircle,
  Send,
  Share2,
  Square,
  Terminal,
  Wrench,
  Search,
  PenSquare,
  AlertTriangle,
  ChevronDown,
  ChevronUp,
  X
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
import { apiFetch, readableError } from "@/shared/api-client";
import { aresApi } from "@/shared/ares-api";
import type { SessionSnapshot } from "@/shared/contracts";

interface DiscoveredBackend {
  adapter_id: string;
  display_name: string;
  detected: boolean;
}

interface DiscoveryResponse {
  adapters: DiscoveredBackend[];
}

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
  {
    icon: (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
    ),
    text: "What files are in this workspace?"
  },
  {
    icon: (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1" ry="1"/><line x1="9" y1="12" x2="15" y2="12"/><line x1="9" y1="16" x2="12" y2="16"/></svg>
    ),
    text: "What's on my schedule today?"
  },
  {
    icon: (
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/></svg>
    ),
    text: "Help me plan a small project."
  },
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
  const [discoveredBackends, setDiscoveredBackends] = useState<DiscoveredBackend[]>([]);
  const [discoveryError, setDiscoveryError] = useState("");
  const [sessions, setSessions] = useState<SessionSnapshot[]>([]);
  const [loadingSessions, setLoadingSessions] = useState(true);
  const [sessionSearch, setSessionSearch] = useState("");
  
  // Hermes mock banners
  const [showOffline, setShowOffline] = useState(false);
  const [showHealth, setShowHealth] = useState(false);
  const [showApproval, setShowApproval] = useState(false);
  const [approvalCollapsed, setApprovalCollapsed] = useState(false);

  const [selectedBackend, setSelectedBackend] = useState<string>(() => currentSession?.backendId || "");
  const copiedTimer = useRef<number | undefined>(undefined);
  const transcriptRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const controller = new AbortController();
    void apiFetch<DiscoveryResponse>("/api/discover/frameworks", { signal: controller.signal })
      .then((data) => {
        if (controller.signal.aborted) return;
        setDiscoveredBackends(data.adapters || []);
        setDiscoveryError("");
      })
      .catch((error: unknown) => {
        if (!controller.signal.aborted) {
          setDiscoveryError(readableError(error, "Connections could not be discovered."));
        }
      });
      
    // Load sessions for the sidebar
    void aresApi.getSessions().then((res) => {
      setSessions(res.sessions || []);
      setLoadingSessions(false);
    }).catch(() => setLoadingSessions(false));
    
    return () => controller.abort();
  }, []);

  useEffect(() => () => {
    if (copiedTimer.current !== undefined) window.clearTimeout(copiedTimer.current);
  }, []);

  const assistantName = snapshot.settings?.assistantName || profile.assistantName || "Companion";
  const isBusy = streamState !== "idle";
  const hasConversation = Boolean(currentSession?.messages.length || streamText || isBusy);

  useEffect(() => {
    if (currentSession?.backendId) {
      setSelectedBackend(currentSession.backendId);
      return;
    }
    const elected = snapshot.connections.find((connection) => connection.selected)?.id || "";
    setSelectedBackend(elected);
  }, [currentSession?.backendId, snapshot.connections]);

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
    if (!message || isBusy || !selectedBackend) return;
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
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      if (copiedTimer.current !== undefined) window.clearTimeout(copiedTimer.current);
      copiedTimer.current = window.setTimeout(() => setCopied(false), 1600);
    } catch (reason) {
      console.error(reason);
    }
  }, [currentSession?.messages, streamText]);

  const lastAssistantText = useMemo(() => {
    if (streamText) return streamText;
    const last = [...(currentSession?.messages || [])].reverse().find((m) => m.role !== "user");
    return last?.text;
  }, [currentSession?.messages, streamText]);

  const filteredSessions = sessions.filter(s => s.title?.toLowerCase().includes(sessionSearch.toLowerCase()));

  return (
    <div className="flex h-full w-full overflow-hidden" style={{ backgroundColor: G.bg, color: G.text }}>
      
      {/* ── Left Sidebar: Session List ── */}
      <aside className="flex h-full w-[260px] flex-col shrink-0 border-r" style={{ borderColor: G.border, backgroundColor: G.sidebar }}>
        <div className="flex items-center justify-between px-4 h-12 shrink-0 border-b" style={{ borderColor: G.border }}>
          <span className="font-semibold text-[14px]">Chat</span>
          <button className="rounded p-1 transition-colors hover:bg-white/5" style={{ color: G.muted }} title="New conversation (Cmd+K)" onClick={() => window.location.href='/conversation'}>
            <PenSquare size={16} />
          </button>
        </div>
        <div className="p-3 border-b shrink-0" style={{ borderColor: G.border }}>
          <div className="relative">
            <Search size={14} className="absolute left-2.5 top-[9px]" style={{ color: G.muted }} />
            <input 
              type="search" 
              placeholder="Filter conversations..." 
              value={sessionSearch}
              onChange={(e) => setSessionSearch(e.target.value)}
              className="w-full rounded-[6px] border py-1.5 pl-8 pr-3 text-[13px] focus:outline-none transition-colors"
              style={{ backgroundColor: G.inputBg, borderColor: G.border, color: G.text }}
            />
          </div>
        </div>
        <div className="flex-1 overflow-y-auto p-2 space-y-0.5">
          {loadingSessions ? (
            <div className="p-4 text-center text-xs" style={{ color: G.muted }}>Loading...</div>
          ) : filteredSessions.length > 0 ? (
            filteredSessions.map((s) => (
              <button 
                key={s.id}
                className="w-full text-left px-3 py-2 rounded-md text-[13px] truncate transition-colors"
                style={{ 
                  color: s.id === currentSession?.id ? G.strong : G.muted,
                  backgroundColor: s.id === currentSession?.id ? G.surfaceSubtle : 'transparent',
                  fontWeight: s.id === currentSession?.id ? 500 : 400
                }}
              >
                {s.title || "Untitled Conversation"}
              </button>
            ))
          ) : (
            <div className="p-4 text-center text-xs" style={{ color: G.muted }}>No conversations found</div>
          )}
        </div>
      </aside>

      {/* ── Right Pane: Main Chat ── */}
      <main className="flex min-w-0 flex-1 flex-col relative">
        
        {/* Banners */}
        {showOffline && (
          <div className="flex flex-col sm:flex-row sm:items-center justify-between border-b px-4 py-3 text-[13px]" style={{ borderColor: '#842029', backgroundColor: '#2c0b0e', color: '#ea868f' }}>
            <div>
              <strong className="text-[#ff98a1] mr-2">Connection lost</strong> 
              Your browser reports that this device is offline.
            </div>
            <button className="mt-2 sm:mt-0 px-3 py-1.5 rounded bg-[#842029] text-white hover:bg-[#a52834] transition-colors" onClick={() => setShowOffline(false)}>Check now</button>
          </div>
        )}
        
        {showHealth && (
          <div className="flex flex-col sm:flex-row sm:items-center justify-between border-b px-4 py-3 text-[13px]" style={{ borderColor: '#664d03', backgroundColor: '#332701', color: '#ffda6a' }}>
            <div>
              <strong className="text-[#ffe69c] mr-2">Hermes agent is not responding</strong> 
              The gateway heartbeat failed. Messages may not be delivered.
            </div>
            <div className="flex gap-2 mt-2 sm:mt-0">
              <button className="px-3 py-1.5 rounded bg-[#664d03] text-white hover:bg-[#856404] transition-colors">Restart Service</button>
              <button className="px-3 py-1.5 rounded" style={{ color: '#ffda6a' }} onClick={() => setShowHealth(false)}>Dismiss</button>
            </div>
          </div>
        )}

        {/* Messages Shell */}
        <div
          ref={transcriptRef}
          onScroll={onScroll}
          className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden relative"
          style={{ backgroundColor: G.bg }}
          aria-live="polite"
        >
          {!hasConversation ? (
            /* ── Hermes Empty State ── */
            <div
              className="flex h-full flex-col items-center justify-center px-6 py-10"
              style={{
                background: "radial-gradient(ellipse at 50% 20%, rgba(255,255,255,0.05) 0%, transparent 55%)",
              }}
            >
              <div className="mb-6">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="80" height="80" aria-label="Hermes caduceus">
                  <defs>
                    <linearGradient id="hermes-mark" x1="0" y1="0" x2="1" y2="0">
                      <stop className="hm-g0" offset="0" stopColor="#08EBF1"/>
                      <stop className="hm-g1" offset="1" stopColor="#3889FD"/>
                    </linearGradient>
                  </defs>
                  <g transform="translate(-24.93 -29.13) scale(0.09075)">
                    <path fill="url(#hermes-mark)" fillRule="evenodd" d="M630.5 961.9 C634.9 960.7 638.5 957.9 640.5 953.9 C642.5 950.1 643.3 865.1 641.4 864.3 C640 863.8 623.9 872.5 618.2 876.8 C616.4 878.2 613.8 881.2 612.5 883.5 L610 887.7 610 918.4 C610 951.8 610.2 953.1 615.7 958.3 C618.3 960.8 622.4 962.7 625.5 962.9 C626 963 628.3 962.5 630.5 961.9 Z M596 913 C596.8 911.5 596.6 909.4 595.4 904.8 C592.1 892.1 595.4 881.4 605.5 872.1 C612.9 865.4 621.2 860.6 641.1 851.4 C681.3 832.9 691.1 827.1 704.5 813.6 C724.9 793.1 730 768.6 718.9 745.5 C714.9 737.4 705.5 727.4 696.7 722.1 L691.1 718.8 678.3 722.6 C671.3 724.6 664.9 726.8 664.2 727.3 C663.5 727.9 663 730.6 663 734.1 C663 739.9 663.1 740 666.8 741.9 C672.9 745 680.6 752.6 683.4 758.2 C688.9 769.3 686 781.3 675.3 791 C666.4 799.1 662.1 801.7 631.3 817.2 C598.7 833.5 587.2 840.5 578.9 849 C565.9 862.3 561.8 880.1 568.3 894.4 C574.4 907.7 592.4 919.8 596 913 Z M579.8 832.2 C582.7 830.2 586.8 827.3 589 825.8 C592.9 823.1 593 822.9 593 817.2 L593 811.4 586.6 807.2 C578.4 801.8 572.5 795.2 568.7 787.2 C566 781.5 565.8 780.1 566.2 773.5 C566.8 764.5 569.4 759.6 577.8 751.8 C589.1 741.4 603.5 735.3 666 714.8 C687.7 707.6 710.2 699.7 715.9 697.2 C741.9 685.8 757.8 670 764.5 648.7 C765.9 644.4 767 639.2 767 637.1 C767 631.5 768.1 631 777.9 631.6 C801.3 633.2 819.4 623.2 829 603.6 C831.2 599.2 833.5 593.4 834.2 590.7 C835.3 586.4 835.2 585.8 833.4 584 C831.5 582.1 830.8 582 814 583 C804.4 583.5 789.8 584.1 781.5 584.2 L766.5 584.5 766.2 577.9 C766 573.4 766.3 571 767.2 570.2 C767.9 569.6 778.4 568.4 790.4 567.6 C835.7 564.3 849.7 561.9 862.2 555.3 C878.5 546.7 889.5 529.3 893 506.4 C894.1 499.3 894 498.6 892.3 496.8 C890.4 494.9 890 495 865.4 500.4 C838.7 506.3 789.4 516.1 776.8 518.1 C766.3 519.7 766 519.5 766 511.2 C766 507.2 766.5 503.7 767.2 502.8 C767.9 502 771.2 500.7 774.5 500.1 C788.7 497.1 852.9 480.7 868.5 476 C877.9 473.2 889.8 468.8 895 466.3 C903 462.5 905.8 460.4 913.1 453.1 C922.9 443.2 928.3 433.9 932.5 419.5 C935.4 409.5 937.6 393.5 936.6 389.7 C935.3 384.3 933.5 384.5 914.3 392.1 C879.6 406 825.4 423.1 754.6 442.4 C728.5 449.6 719.1 452.5 717.2 454.2 C711.9 459.2 712 457.7 712 516.7 C712 551.6 711.6 572.9 710.9 575.2 C709.6 580 703.8 585.7 699.1 587 C697.1 587.5 689.9 588.2 683 588.6 C674 589.1 670 589.7 668.8 590.8 C667.2 592.1 667 594.3 667 608 C667 621.6 667.2 624.1 668.8 625.8 C670.4 627.8 671.8 627.9 694.9 628.2 C710.4 628.4 719.8 628.9 720.8 629.6 C723.1 631.2 720.6 639.8 715.9 646.9 C706.4 661.1 694.2 667.1 631 689 C581.4 706.1 563.9 713.8 550.3 724.7 C512.3 755 518.4 806 563.1 831.3 C567.7 833.9 572.2 836 573.1 836 C573.9 836 577 834.3 579.8 832.2 Z M626.3 807.4 C633.5 803.8 640.2 800.1 641.1 799.4 C642.5 798.1 642.7 794.2 642.5 766.5 C642.5 749.2 642.1 734.7 641.7 734.4 C641 733.7 613.6 743.6 611.2 745.3 C610.3 746 610 754.1 610 779.5 C610 797.7 610.3 813 610.7 813.3 C611.8 814.5 612.7 814.1 626.3 807.4 Z M571.1 699.2 L584.5 693.4 584.8 685.5 C585 681.2 584.7 677.3 584.1 676.7 C583.6 676.2 579.9 674.7 575.8 673.3 C567.5 670.5 554.7 664.2 548.4 660 C538.6 653.2 530.5 640.3 531.2 632.6 L531.5 629.5 541 628.9 C546.2 628.5 557.7 628.2 566.5 628.1 C577.6 628 583 627.6 583.8 626.8 C585.5 625.1 585.5 591.6 583.8 590.3 C583.1 589.7 576.5 589 569.1 588.6 C555.2 587.9 550.4 586.7 546.1 582.7 C541 578 541 578.1 541 518.8 C541 466.4 540.9 463.3 539 459.3 C536.5 453.7 533.3 451.9 518.7 448.1 C442.4 428 363.2 402.9 330.3 388.3 C322.4 384.9 322 384.8 319.5 386.4 C317.3 387.9 317 388.7 317 393.9 C317 397.1 317.7 403.5 318.5 408.1 C324.3 439.3 338.4 458 364.5 469.2 C374.6 473.5 396.4 479.7 441.3 491 C464.8 496.9 484.7 502.3 485.5 503 C486.6 503.9 487 506.3 487 511.2 C487 519.5 486.6 519.8 476.7 518.1 C461.5 515.5 412.5 505.6 391.5 500.9 C379.4 498.2 368.3 495.7 366.7 495.3 C364.8 494.9 363.3 495.3 361.9 496.6 C360 498.3 359.9 499.2 360.5 505.4 C362.5 526 373.6 544.9 388.9 554 C401.6 561.5 417.9 564.4 468 568.1 C477.1 568.7 485.1 569.7 485.8 570.3 C487.5 571.7 487.4 582.4 485.6 583.9 C484.2 585.1 473.4 584.7 432.5 582.4 C422.2 581.8 421.4 581.9 419.7 583.8 C417.9 585.8 417.9 586.1 419.5 591.6 C424.1 607.4 434.2 620.5 446.4 626.5 C455.1 630.8 461.3 632 474.1 632 C479.5 632 484.1 632.4 484.4 632.9 C484.8 633.4 485.6 637.4 486.4 641.7 C489.7 660.4 500.4 676.9 516.5 688 C526.3 694.7 549.1 704.8 555.1 704.9 C556.5 705 563.7 702.4 571.1 699.2 Z M628.9 678.9 C635.3 676.6 641 674.2 641.5 673.5 C643.1 671.6 642.5 576.3 640.9 574.4 C639.4 572.5 613.1 572.3 611.2 574.2 C610.3 575.1 610 588.7 610 629 C610 658.5 610.3 683 610.7 683.4 C611.8 684.5 616 683.5 628.9 678.9 Z M636.1 556 C654.1 552.6 669.6 536.9 673.6 517.8 C677.9 497.7 668.2 476.3 650 465.8 C636.2 457.8 615.8 458 601.7 466.3 C595.3 470.1 586.1 480.5 582.7 487.8 C570 514.9 585.4 547.4 614.7 555.5 C620.6 557.1 629 557.3 636.1 556 Z"/>
                  </g>
                </svg>
              </div>
              <h2 className="text-[22px] font-semibold tracking-tight" style={{ color: G.strong }}>What can I help with?</h2>
              <p className="mt-2 mb-8 text-[14px]" style={{ color: G.muted }}>
                Ask anything, run commands, explore files, or manage your scheduled tasks.
              </p>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3 w-full max-w-[700px]">
                {SUGGESTIONS.map((s) => (
                  <button
                    key={s.text}
                    type="button"
                    className="flex flex-col items-start gap-2 rounded-[10px] border p-4 text-left transition-all"
                    style={{
                      borderColor: G.border,
                      backgroundColor: G.surfaceSubtle,
                      color: G.muted,
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.borderColor = G.border2;
                      e.currentTarget.style.backgroundColor = G.surfaceSubtleHover;
                      e.currentTarget.style.color = G.text;
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.borderColor = G.border;
                      e.currentTarget.style.backgroundColor = G.surfaceSubtle;
                      e.currentTarget.style.color = G.muted;
                    }}
                    onClick={() => {
                      setDraft(s.text);
                      (document.querySelector('textarea[aria-label="Message"]') as HTMLTextAreaElement | null)?.focus();
                    }}
                  >
                    <div style={{ color: G.strong }}>{s.icon}</div>
                    <span className="text-[13px] leading-tight font-medium" style={{ color: G.text }}>{s.text}</span>
                  </button>
                ))}
              </div>

              {/* Worker selector for new conversations */}
              <div className="mt-12 flex flex-col items-center">
                <p className="text-[11px] uppercase tracking-wider mb-3 font-semibold" style={{ color: G.muted }}>
                  Worker for this chat
                </p>
                <div className="flex flex-wrap items-center justify-center gap-2">
                  {discoveredBackends.map((backend) => (
                    <button
                      key={backend.adapter_id}
                      type="button"
                      onClick={() => setSelectedBackend(backend.adapter_id)}
                      disabled={!backend.detected}
                      className="rounded-full border px-3 py-1.5 text-[12px] font-medium transition-all flex items-center gap-2 shadow-sm"
                      style={{
                        borderColor: selectedBackend === backend.adapter_id ? G.accent : G.border,
                        backgroundColor: selectedBackend === backend.adapter_id ? G.accentBg : G.surface,
                        color: backend.detected ? (selectedBackend === backend.adapter_id ? G.accentText : G.muted) : "rgba(255,255,255,0.3)",
                        cursor: backend.detected ? "pointer" : "not-allowed",
                      }}
                    >
                      {!backend.detected && <span className="size-1.5 rounded-full bg-red-500" />}
                      {backend.detected && selectedBackend === backend.adapter_id && <span className="size-1.5 rounded-full bg-[#08EBF1]" />}
                      {backend.display_name || backendLabel(backend.adapter_id)}
                    </button>
                  ))}
                </div>
                {discoveryError ? (
                  <p className="mt-3 text-center text-xs" role="status" style={{ color: G.warning }}>
                    {discoveryError} You can still use the session's configured connection.
                  </p>
                ) : null}
              </div>
            </div>
          ) : (
            /* ── Messages ── */
            <div className="mx-auto flex w-full max-w-[800px] flex-col gap-6 px-5 pb-28 pt-8">
              {(currentSession?.messages || []).map((message) => {
                const isUser = message.role === "user";
                return (
                  <div
                    key={message.id}
                    className={`flex w-full ${isUser ? "justify-end" : "justify-start"}`}
                  >
                    {!isUser && (
                      <div className="mr-3 mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border shadow-sm" style={{ backgroundColor: G.surfaceSubtle, borderColor: G.border2 }}>
                        <Bot size={16} style={{ color: G.accent }} />
                      </div>
                    )}
                    <div className={`flex max-w-[85%] flex-col gap-1 ${isUser ? "items-end" : "items-start"}`}>
                      <div
                        className={`px-4 py-3 text-[14px] leading-[1.6] shadow-sm`}
                        style={{
                          backgroundColor: isUser ? G.userBubbleBg : 'transparent',
                          color: isUser ? G.userBubbleText : G.text,
                          border: isUser ? `1px solid ${G.userBubbleBorder}` : "none",
                          borderRadius: isUser ? '16px 16px 4px 16px' : '0px',
                          whiteSpace: "pre-wrap",
                          wordBreak: "break-word",
                        }}
                      >
                        <Markdown content={message.text} />
                      </div>
                      {!isUser && (message.workerId || currentSession?.backendId || selectedBackend) ? (
                        <span className="px-2 font-mono text-[10px] uppercase tracking-wider opacity-60" style={{ color: G.muted }}>
                          via worker · {backendLabel(message.workerId || currentSession?.backendId || selectedBackend)}
                        </span>
                      ) : null}
                    </div>
                  </div>
                );
              })}

              {streamState !== "idle" && (
                <div className="flex w-full justify-start">
                  <div className="mr-3 mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border shadow-sm" style={{ backgroundColor: G.surfaceSubtle, borderColor: G.border2 }}>
                    <Bot size={16} style={{ color: G.accent }} />
                  </div>
                  <div
                    className="max-w-[85%] px-4 py-3 text-[14px] leading-[1.6]"
                    style={{ color: G.text }}
                  >
                    {streamText ? (
                      <Markdown content={streamText} streaming />
                    ) : streamState === "starting" ? (
                      <div className="flex items-center gap-2">
                        <LoaderCircle size={16} className="animate-spin text-[#08EBF1]" />
                        <span style={{ color: G.muted }}>Starting…</span>
                      </div>
                    ) : (
                      <div className="flex items-center gap-2">
                        <span className="inline-block size-2 animate-pulse rounded-full bg-[#3889FD]" />
                        <span style={{ color: G.muted }}>Thinking…</span>
                      </div>
                    )}

                    {streamReasoning ? (
                      <div className="mt-3 border-l-2 pl-3 py-1 text-[13px] italic" style={{ borderColor: '#3889FD', color: G.muted }}>
                        {streamReasoning}
                      </div>
                    ) : null}

                    {streamTools.length > 0 ? (
                      <div className="mt-3 flex flex-wrap gap-1.5">
                        {streamTools.map((tool) => (
                          <span
                            key={tool}
                            className="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-[11px] font-medium shadow-sm border"
                            style={{ backgroundColor: G.surfaceSubtle, borderColor: G.border, color: G.text }}
                          >
                            <Wrench size={12} className="opacity-70" />
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
        <div className="shrink-0 relative border-t px-6 py-4 z-10" style={{ borderColor: G.border, backgroundColor: G.bg }}>
          
          {/* Hermes Approval Card Placeholder */}
          {showApproval && (
            <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-4 w-full max-w-[600px] rounded-xl border shadow-2xl overflow-hidden z-20" style={{ borderColor: G.border2, backgroundColor: G.surface }}>
              <div className="flex justify-between items-center px-4 py-2.5 border-b text-sm" style={{ backgroundColor: '#2b2b2b', borderColor: G.border }}>
                 <span className="font-semibold text-white flex items-center gap-2"><AlertTriangle size={14} className="text-yellow-400"/> Approval required</span>
                 <div className="flex items-center gap-1">
                   <button className="p-1 hover:bg-white/10 rounded" onClick={() => setApprovalCollapsed(!approvalCollapsed)}>
                     {approvalCollapsed ? <ChevronUp size={14} className="text-white"/> : <ChevronDown size={14} className="text-white"/>}
                   </button>
                   <button className="p-1 hover:bg-white/10 rounded" onClick={() => setShowApproval(false)}>
                     <X size={14} className="text-white"/>
                   </button>
                 </div>
              </div>
              {!approvalCollapsed && (
                <div className="p-4">
                  <div className="text-[13px] text-gray-300 mb-4">
                     Hermes is requesting permission to execute the following command:
                  </div>
                  <div className="bg-black/50 p-3 rounded-md font-mono text-xs text-green-400 border border-black/30 overflow-x-auto">
                    $ rm -rf /tmp/cache/*
                  </div>
                  <div className="flex justify-end gap-2 mt-4">
                    <button className="px-4 py-1.5 rounded-md text-[13px] border hover:bg-white/5 transition-colors" style={{ borderColor: G.border2, color: G.text }} onClick={() => setShowApproval(false)}>Deny</button>
                    <button className="px-4 py-1.5 rounded-md text-[13px] bg-[#3889FD] text-white hover:bg-[#08EBF1] hover:text-black transition-colors" onClick={() => setShowApproval(false)}>Approve</button>
                  </div>
                </div>
              )}
            </div>
          )}

          {chatNotice ? (
            <div
              className="mb-3 mx-auto max-w-[800px] rounded-lg border px-4 py-2.5 text-[13px] shadow-sm flex items-center gap-2"
              style={{ borderColor: `${G.warning}40`, backgroundColor: `${G.warning}10`, color: G.warning }}
            >
              <AlertTriangle size={14} />
              {chatNotice}
            </div>
          ) : null}

          <form onSubmit={submit} className="mx-auto w-full max-w-[800px]">
            <div
              className="flex items-end gap-2 rounded-2xl border p-2 shadow-sm transition-[border-color,box-shadow] duration-200"
              style={{
                backgroundColor: G.inputBg,
                borderColor: G.border2,
              }}
            >
              <Textarea
                value={draft}
                onChange={(event) => setDraft(event.target.value)}
                onKeyDown={handleComposerKeyDown}
                rows={1}
                aria-label="Message"
                placeholder={`Message ${assistantName}…`}
                className="max-h-40 min-h-[44px] min-w-0 flex-1 resize-none border-0 bg-transparent px-3 py-3 text-[14.5px] leading-[1.5] shadow-none placeholder:text-white/30 focus-visible:ring-0"
                style={{
                  color: G.text,
                  fontWeight: 400,
                }}
                disabled={currentSession?.readOnly || isBusy || !selectedBackend}
              />
              {isBusy ? (
                <Button
                  type="button"
                  size="icon"
                  variant="outline"
                  className="h-10 w-10 shrink-0 rounded-xl border text-white hover:bg-white/10"
                  style={{ borderColor: "rgba(255,255,255,0.15)", backgroundColor: "rgba(255,255,255,0.05)" }}
                  aria-label="Stop response"
                  onClick={() => void cancelResponse()}
                >
                  <Square size={16} fill="currentColor" />
                </Button>
              ) : (
                <Button
                  type="submit"
                  size="icon"
                  className="h-10 w-10 shrink-0 rounded-xl transition-colors"
                  style={{
                    backgroundColor: draft.trim() ? G.strong : "rgba(255,255,255,0.05)",
                    color: draft.trim() ? G.bg : "rgba(255,255,255,0.3)",
                  }}
                  aria-label="Send message"
                  disabled={!draft.trim() || !selectedBackend}
                >
                  <Send size={18} />
                </Button>
              )}
            </div>
            
            <div className="mt-2 flex items-center justify-between text-[11px] font-medium" style={{ color: G.muted }}>
              <div className="flex gap-4">
                <span><kbd className="font-sans px-1 py-0.5 rounded bg-white/5 border border-white/10">Enter</kbd> to send</span>
                <span><kbd className="font-sans px-1 py-0.5 rounded bg-white/5 border border-white/10">Shift</kbd> + <kbd className="font-sans px-1 py-0.5 rounded bg-white/5 border border-white/10">Enter</kbd> for new line</span>
              </div>
              
              <div className="flex gap-2">
                {/* Temporary buttons to test UI elements */}
                <button type="button" onClick={() => setShowApproval(!showApproval)} className="hover:text-white underline">Toggle Approval UI</button>
                <button type="button" onClick={() => setShowHealth(!showHealth)} className="hover:text-white underline">Toggle Health</button>
                <button type="button" onClick={() => setShowOffline(!showOffline)} className="hover:text-white underline">Toggle Offline</button>
              </div>
            </div>
          </form>

          {/* Copy last / scroll bottom */}
          <div className="pointer-events-none absolute bottom-full mb-4 right-6 flex flex-col items-end gap-2">
            {showScrollBottom ? (
              <button
                type="button"
                onClick={() => transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: "smooth" })}
                className="pointer-events-auto flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[12px] font-medium shadow-md transition-colors hover:bg-white/10"
                style={{ borderColor: G.border2, backgroundColor: G.surface, color: G.text }}
              >
                <ArrowDown size={14} /> Bottom
              </button>
            ) : null}
            {lastAssistantText ? (
              <button
                type="button"
                onClick={() => void copyLastResponse()}
                className="pointer-events-auto flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[12px] font-medium shadow-md transition-colors hover:bg-white/10"
                style={{ borderColor: G.border2, backgroundColor: G.surface, color: G.text }}
              >
                {copied ? <Check size={14} className="text-green-400" /> : <Copy size={14} />}
                {copied ? "Copied" : "Copy"}
              </button>
            ) : null}
          </div>
        </div>
      </main>
    </div>
  );
}
`;

fs.writeFileSync(path.join('/Users/matthewjenkins/GitHub/ARES/webui/frontend/src/pages', 'ConversationPage.tsx'), content);

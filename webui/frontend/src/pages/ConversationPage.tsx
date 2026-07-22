import {
  ArrowDown,
  Bot,
  Check,
  Copy,
  LoaderCircle,
  Square,
  Wrench,
  AlertTriangle,
  ChevronDown,
  ChevronUp,
  X,
  Paperclip,
  Bookmark,
  Mic,
  MicOff,
  Boxes,
  Folder,
  FileText,
  GitBranch,
  Settings,
  Server,
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

import { Markdown } from "@/components/Markdown";
import { useAres } from "@/shared/ares-context";
import { useWorkbenchPanel } from "@/shared/workbench-panel";
import { apiFetch, readableError } from "@/shared/api-client";

// Hermes-matching dark blue palette
const H = {
  bg: "#0f1117",
  surface: "#1a1d28",
  surfaceHover: "#1f2236",
  surfaceActive: "#252840",
  border: "#1e2130",
  border2: "#2a2d42",
  text: "#e2e4f0",
  strong: "#f0f2ff",
  muted: "#6b7194",
  accentGlow: "#08EBF1",
  accentBlue: "#3889FD",
  accent: "#5b7cf6",
  inputBg: "#161822",
  inputBorder: "#252840",
  chipBg: "#1e2130",
  chipBorder: "#2a2d42",
  chipText: "#9094b8",
  sendBtn: "#f0f2ff",
  sendBtnText: "#0f1117",
};

// Hermes Caduceus SVG
const CaduceusSVG = () => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="72" height="72" aria-label="Hermes caduceus">
    <defs>
      <linearGradient id="hermes-mark-cp" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stopColor="#08EBF1"/>
        <stop offset="1" stopColor="#3889FD"/>
      </linearGradient>
    </defs>
    <g transform="translate(-24.93 -29.13) scale(0.09075)">
      <path fill="url(#hermes-mark-cp)" fillRule="evenodd" d="M630.5 961.9 C634.9 960.7 638.5 957.9 640.5 953.9 C642.5 950.1 643.3 865.1 641.4 864.3 C640 863.8 623.9 872.5 618.2 876.8 C616.4 878.2 613.8 881.2 612.5 883.5 L610 887.7 610 918.4 C610 951.8 610.2 953.1 615.7 958.3 C618.3 960.8 622.4 962.7 625.5 962.9 C626 963 628.3 962.5 630.5 961.9 Z M596 913 C596.8 911.5 596.6 909.4 595.4 904.8 C592.1 892.1 595.4 881.4 605.5 872.1 C612.9 865.4 621.2 860.6 641.1 851.4 C681.3 832.9 691.1 827.1 704.5 813.6 C724.9 793.1 730 768.6 718.9 745.5 C714.9 737.4 705.5 727.4 696.7 722.1 L691.1 718.8 678.3 722.6 C671.3 724.6 664.9 726.8 664.2 727.3 C663.5 727.9 663 730.6 663 734.1 C663 739.9 663.1 740 666.8 741.9 C672.9 745 680.6 752.6 683.4 758.2 C688.9 769.3 686 781.3 675.3 791 C666.4 799.1 662.1 801.7 631.3 817.2 C598.7 833.5 587.2 840.5 578.9 849 C565.9 862.3 561.8 880.1 568.3 894.4 C574.4 907.7 592.4 919.8 596 913 Z M579.8 832.2 C582.7 830.2 586.8 827.3 589 825.8 C592.9 823.1 593 822.9 593 817.2 L593 811.4 586.6 807.2 C578.4 801.8 572.5 795.2 568.7 787.2 C566 781.5 565.8 780.1 566.2 773.5 C566.8 764.5 569.4 759.6 577.8 751.8 C589.1 741.4 603.5 735.3 666 714.8 C687.7 707.6 710.2 699.7 715.9 697.2 C741.9 685.8 757.8 670 764.5 648.7 C765.9 644.4 767 639.2 767 637.1 C767 631.5 768.1 631 777.9 631.6 C801.3 633.2 819.4 623.2 829 603.6 C831.2 599.2 833.5 593.4 834.2 590.7 C835.3 586.4 835.2 585.8 833.4 584 C831.5 582.1 830.8 582 814 583 C804.4 583.5 789.8 584.1 781.5 584.2 L766.5 584.5 766.2 577.9 C766 573.4 766.3 571 767.2 570.2 C767.9 569.6 778.4 568.4 790.4 567.6 C835.7 564.3 849.7 561.9 862.2 555.3 C878.5 546.7 889.5 529.3 893 506.4 C894.1 499.3 894 498.6 892.3 496.8 C890.4 494.9 890 495 865.4 500.4 C838.7 506.3 789.4 516.1 776.8 518.1 C766.3 519.7 766 519.5 766 511.2 C766 507.2 766.5 503.7 767.2 502.8 C767.9 502 771.2 500.7 774.5 500.1 C788.7 497.1 852.9 480.7 868.5 476 C877.9 473.2 889.8 468.8 895 466.3 C903 462.5 905.8 460.4 913.1 453.1 C922.9 443.2 928.3 433.9 932.5 419.5 C935.4 409.5 937.6 393.5 936.6 389.7 C935.3 384.3 933.5 384.5 914.3 392.1 C879.6 406 825.4 423.1 754.6 442.4 C728.5 449.6 719.1 452.5 717.2 454.2 C711.9 459.2 712 457.7 712 516.7 C712 551.6 711.6 572.9 710.9 575.2 C709.6 580 703.8 585.7 699.1 587 C697.1 587.5 689.9 588.2 683 588.6 C674 589.1 670 589.7 668.8 590.8 C667.2 592.1 667 594.3 667 608 C667 621.6 667.2 624.1 668.8 625.8 C670.4 627.8 671.8 627.9 694.9 628.2 C710.4 628.4 719.8 628.9 720.8 629.6 C723.1 631.2 720.6 639.8 715.9 646.9 C706.4 661.1 694.2 667.1 631 689 C581.4 706.1 563.9 713.8 550.3 724.7 C512.3 755 518.4 806 563.1 831.3 C567.7 833.9 572.2 836 573.1 836 C573.9 836 577 834.3 579.8 832.2 Z M628.9 807.4 C633.5 803.8 640.2 800.1 641.1 799.4 C642.5 798.1 642.7 794.2 642.5 766.5 C642.5 749.2 642.1 734.7 641.7 734.4 C641 733.7 613.6 743.6 611.2 745.3 C610.3 746 610 754.1 610 779.5 C610 797.7 610.3 813 610.7 813.3 C611.8 814.5 612.7 814.1 626.3 807.4 Z M571.1 699.2 L584.5 693.4 584.8 685.5 C585 681.2 584.7 677.3 584.1 676.7 C583.6 676.2 579.9 674.7 575.8 673.3 C567.5 670.5 554.7 664.2 548.4 660 C538.6 653.2 530.5 640.3 531.2 632.6 L531.5 629.5 541 628.9 C546.2 628.5 557.7 628.2 566.5 628.1 C577.6 628 583 627.6 583.8 626.8 C585.5 625.1 585.5 591.6 583.8 590.3 C583.1 589.7 576.5 589 569.1 588.6 C555.2 587.9 550.4 586.7 546.1 582.7 C541 578 541 578.1 541 518.8 C541 466.4 540.9 463.3 539 459.3 C536.5 453.7 533.3 451.9 518.7 448.1 C442.4 428 363.2 402.9 330.3 388.3 C322.4 384.9 322 384.8 319.5 386.4 C317.3 387.9 317 388.7 317 393.9 C317 397.1 317.7 403.5 318.5 408.1 C324.3 439.3 338.4 458 364.5 469.2 C374.6 473.5 396.4 479.7 441.3 491 C464.8 496.9 484.7 502.3 485.5 503 C486.6 503.9 487 506.3 487 511.2 C487 519.5 486.6 519.8 476.7 518.1 C461.5 515.5 412.5 505.6 391.5 500.9 C379.4 498.2 368.3 495.7 366.7 495.3 C364.8 494.9 363.3 495.3 361.9 496.6 C360 498.3 359.9 499.2 360.5 505.4 C362.5 526 373.6 544.9 388.9 554 C401.6 561.5 417.9 564.4 468 568.1 C477.1 568.7 485.1 569.7 485.8 570.3 C487.5 571.7 487.4 582.4 485.6 583.9 C484.2 585.1 473.4 584.7 432.5 582.4 C422.2 581.8 421.4 581.9 419.7 583.8 C417.9 585.8 417.9 586.1 419.5 591.6 C424.1 607.4 434.2 620.5 446.4 626.5 C455.1 630.8 461.3 632 474.1 632 C479.5 632 484.1 632.4 484.4 632.9 C484.8 633.4 485.6 637.4 486.4 641.7 C489.7 660.4 500.4 676.9 516.5 688 C526.3 694.7 549.1 704.8 555.1 704.9 C556.5 705 563.7 702.4 571.1 699.2 Z M628.9 678.9 C635.3 676.6 641 674.2 641.5 673.5 C643.1 671.6 642.5 576.3 640.9 574.4 C639.4 572.5 613.1 572.3 611.2 574.2 C610.3 575.1 610 588.7 610 629 C610 658.5 610.3 683 610.7 683.4 C611.8 684.5 616 683.5 628.9 678.9 Z M636.1 556 C654.1 552.6 669.6 536.9 673.6 517.8 C677.9 497.7 668.2 476.3 650 465.8 C636.2 457.8 615.8 458 601.7 466.3 C595.3 470.1 586.1 480.5 582.7 487.8 C570 514.9 585.4 547.4 614.7 555.5 C620.6 557.1 629 557.3 636.1 556 Z"/>
    </g>
  </svg>
);

function IconBtn({ children, title, onClick }: { children: React.ReactNode; title: string; onClick?: () => void }) {
  return (
    <button type="button" title={title} onClick={onClick}
      style={{ display: "inline-flex", alignItems: "center", justifyContent: "center", width: 28, height: 28, borderRadius: 6, border: "none", background: "transparent", color: H.muted, cursor: "pointer", transition: "color 0.15s, background 0.15s" }}
      onMouseEnter={(e) => { e.currentTarget.style.color = H.text; e.currentTarget.style.background = "rgba(255,255,255,0.06)"; }}
      onMouseLeave={(e) => { e.currentTarget.style.color = H.muted; e.currentTarget.style.background = "transparent"; }}>
      {children}
    </button>
  );
}

function ComposerChip({ icon, label, onClick }: { icon: React.ReactNode; label: string; onClick?: () => void }) {
  const [hover, setHover] = useState(false);
  return (
    <button type="button" onClick={onClick} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{ display: "inline-flex", alignItems: "center", gap: 5, height: 26, padding: "0 10px", borderRadius: 6, border: `1px solid ${hover ? H.border2 : H.chipBorder}`, background: hover ? H.surfaceHover : H.chipBg, color: hover ? H.text : H.chipText, fontSize: 12, fontWeight: 500, cursor: "pointer", transition: "all 0.15s", whiteSpace: "nowrap" }}>
      <span style={{ opacity: 0.7 }}>{icon}</span>
      <span>{label}</span>
      <ChevronDown size={9} style={{ opacity: 0.5 }} />
    </button>
  );
}

interface DiscoveredBackend {
  adapter_id: string;
  display_name: string;
  detected: boolean;
}

interface DiscoveryResponse {
  adapters: DiscoveredBackend[];
}

const SAVED_PROMPT_TEMPLATES = [
  { label: "Code Review", prompt: "Please review this code for performance, security vulnerabilities, and adherence to clean architecture principles:" },
  { label: "Debug Error", prompt: "Help me diagnose and debug the root cause of this error. Trace the failure path step by step:" },
  { label: "Refactor Code", prompt: "Refactor this code to make it more modular, readable, and maintainable while maintaining exact backward compatibility:" },
  { label: "System Architecture", prompt: "Outline a high-level technical architecture and implementation plan for the following feature requirement:" },
];

export function ConversationPage() {
  const workbenchPanel = useWorkbenchPanel();
  const {
    snapshot,
    currentSession,
    selectedSessionId,
    createSession,
    sendMessage,
    streamText,
    streamReasoning,
    streamTools,
    streamState,
    chatNotice,
    cancelResponse,
  } = useAres();

  const sessionLoading = Boolean(selectedSessionId && !currentSession && !chatNotice);
  const [draft, setDraft] = useState("");
  const [copied, setCopied] = useState(false);
  const [showScrollBottom, setShowScrollBottom] = useState(false);
  const [discoveredBackends, setDiscoveredBackends] = useState<DiscoveredBackend[]>([]);
  const [discoveryError, setDiscoveryError] = useState("");
  const [selectedBackend, setSelectedBackend] = useState<string>(() => currentSession?.backendId || "");
  const [showApproval, setShowApproval] = useState(false);
  const [approvalCollapsed, setApprovalCollapsed] = useState(false);

  // Attachments, saved prompts, dictation, workspace, backend, model
  const [attachedFiles, setAttachedFiles] = useState<File[]>([]);
  const [showSavedPrompts, setShowSavedPrompts] = useState(false);
  const [showBackendMenu, setShowBackendMenu] = useState(false);
  const [showModelMenu, setShowModelMenu] = useState(false);
  const [showWorkspaceMenu, setShowWorkspaceMenu] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [selectedModel, setSelectedModel] = useState<string>("");
  const [selectedModelProvider, setSelectedModelProvider] = useState<string>("");
  const [workspaceOverride, setWorkspaceOverride] = useState<string>("");
  const [backendCatalog, setBackendCatalog] = useState<
    Array<{
      id: string;
      available?: boolean;
      inventory?: {
        models?: Array<{
          id: string;
          label?: string;
          location?: string;
          in_use?: boolean;
          provider?: string | null;
          notes?: string | null;
        }>;
        providers?: Array<{ id: string; label?: string; status?: string; notes?: string }>;
        active_execution?: { model?: string | null; provider?: string | null };
      };
    }>
  >([]);

  const [wsSearchQuery, setWsSearchQuery] = useState("");
  const [backendSearchQuery, setBackendSearchQuery] = useState("");

  const copiedTimer = useRef<number | undefined>(undefined);
  const transcriptRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const recognitionRef = useRef<any>(null);

  // Close menus when clicking outside
  useEffect(() => {
    const handleDocumentClick = () => {
      setShowWorkspaceMenu(false);
      setShowBackendMenu(false);
      setShowModelMenu(false);
    };
    document.addEventListener("click", handleDocumentClick);
    return () => document.removeEventListener("click", handleDocumentClick);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    void apiFetch<DiscoveryResponse>("/api/discover/frameworks", { signal: controller.signal })
      .then((data) => {
        if (controller.signal.aborted) return;
        setDiscoveredBackends(data.adapters || []);
        setDiscoveryError("");
      })
      .catch((error: unknown) => {
        if (!controller.signal.aborted) setDiscoveryError(readableError(error, "Connections could not be discovered."));
      });
    void apiFetch<{ backends?: typeof backendCatalog }>("/api/backends", { signal: controller.signal })
      .then((data) => {
        if (!controller.signal.aborted) setBackendCatalog(data.backends || []);
      })
      .catch(() => undefined);
    return () => controller.abort();
  }, []);

  useEffect(() => () => {
    if (copiedTimer.current !== undefined) window.clearTimeout(copiedTimer.current);
  }, []);

  const isBusy = streamState !== "idle";
  const hasConversation = Boolean(currentSession?.messages.length || streamText || isBusy);
  const isReadOnlyCli = Boolean(currentSession?.readOnly || currentSession?.source === "cli");

  useEffect(() => {
    if (currentSession?.backendId) {
      setSelectedBackend(currentSession.backendId);
    } else {
      const elected = snapshot.connections.find((c) => c.selected)?.id || "";
      if (elected) setSelectedBackend(elected);
    }
    // Session workspace is the agent's working folder unless user overrides.
    if (currentSession?.workspace) setWorkspaceOverride("");
    if (currentSession?.model) {
      setSelectedModel(currentSession.model);
      setSelectedModelProvider(currentSession.provider || "");
    }
  }, [currentSession?.backendId, currentSession?.workspace, currentSession?.model, currentSession?.provider, snapshot.connections]);

  useEffect(() => {
    const el = transcriptRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
    if (nearBottom || streamText) el.scrollTo({ top: el.scrollHeight, behavior: streamText ? "auto" : "smooth" });
  }, [currentSession?.messages.length, streamText, streamReasoning, streamTools, streamState]);

  const onScroll = useCallback(() => {
    const el = transcriptRef.current;
    if (!el) return;
    setShowScrollBottom(el.scrollHeight - el.scrollTop - el.clientHeight > 120);
  }, []);

  // Dictation handling
  const toggleDictation = useCallback(() => {
    if (isListening) {
      if (recognitionRef.current) recognitionRef.current.stop();
      setIsListening(false);
      return;
    }

    const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SpeechRecognition) {
      alert("Browser speech recognition is not supported in this browser.");
      return;
    }

    try {
      const recognition = new SpeechRecognition();
      recognition.continuous = true;
      recognition.interimResults = true;
      recognition.lang = "en-US";

      recognition.onresult = (event: any) => {
        let transcriptText = "";
        for (let i = event.resultIndex; i < event.results.length; i++) {
          transcriptText += event.results[i][0].transcript;
        }
        setDraft((prev) => prev + (prev ? " " : "") + transcriptText);
      };

      recognition.onerror = () => setIsListening(false);
      recognition.onend = () => setIsListening(false);

      recognition.start();
      recognitionRef.current = recognition;
      setIsListening(true);
    } catch {
      setIsListening(false);
    }
  }, [isListening]);

  const submit = useCallback(async (event: FormEvent) => {
    event.preventDefault();
    let message = draft.trim();
    if (!message && attachedFiles.length === 0) return;
    if (isBusy || isReadOnlyCli) return;

    if (attachedFiles.length > 0) {
      const fileNames = attachedFiles.map((f) => f.name).join(", ");
      message = `[Attached files: ${fileNames}]\n\n${message}`;
    }

    setDraft("");
    setAttachedFiles([]);
    if (textareaRef.current) textareaRef.current.style.height = "auto";
    const workspace =
      workspaceOverride.trim()
      || currentSession?.workspace
      || snapshot.workspaces?.[0]?.path
      || undefined;
    void sendMessage(message, {
      backendId: selectedBackend || undefined,
      model: selectedModel || undefined,
      provider: selectedModelProvider || undefined,
      workspace,
    });
  }, [
    draft, attachedFiles, isBusy, isReadOnlyCli, sendMessage, selectedBackend,
    selectedModel, selectedModelProvider, workspaceOverride, currentSession, snapshot.workspaces,
  ]);

  const handleComposerKeyDown = useCallback((event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      event.currentTarget.form?.requestSubmit();
    }
  }, []);

  const copyLastResponse = useCallback(async () => {
    const lastAssistant = [...(currentSession?.messages || [])].reverse().find((m) => m.role !== "user")?.text;
    const text = streamText || lastAssistant;
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      if (copiedTimer.current !== undefined) window.clearTimeout(copiedTimer.current);
      copiedTimer.current = window.setTimeout(() => setCopied(false), 1600);
    } catch (reason) { console.error(reason); }
  }, [currentSession?.messages, streamText]);

  const lastAssistantText = useMemo(() => {
    if (streamText) return streamText;
    return [...(currentSession?.messages || [])].reverse().find((m) => m.role !== "user")?.text;
  }, [currentSession?.messages, streamText]);

  // Agent working folder: session workspace > override > first known workspace.
  const workspacePath =
    workspaceOverride.trim()
    || currentSession?.workspace
    || snapshot.workspaces?.[0]?.path
    || "";
  const activeWorkspaceLabel = (() => {
    if (!workspacePath) return "Working folder";
    if (workspacePath === "~" || workspacePath === "/") return workspacePath;
    const segments = workspacePath.replace(/\/+$/, "").split("/").filter(Boolean);
    return segments[segments.length - 1] || workspacePath;
  })();

  // Live backends: only available connections / detected adapters.
  const backendOptions = useMemo(() => {
    const fromConnections = snapshot.connections
      .filter((c) => c.available !== false && c.state !== "offline")
      .map((c) => ({
        id: c.id,
        label: c.name || c.id,
        detail: c.detail || c.kind,
        available: Boolean(c.available),
      }));
    if (fromConnections.length) return fromConnections;
    return discoveredBackends
      .filter((b) => b.detected)
      .map((b) => ({
        id: b.adapter_id,
        label: b.display_name || b.adapter_id,
        detail: b.adapter_id,
        available: true,
      }));
  }, [snapshot.connections, discoveredBackends]);

  const activeBackendMeta = backendOptions.find((b) => b.id === selectedBackend)
    || backendOptions.find((b) => b.id === snapshot.connections.find((c) => c.selected)?.id);
  const activeBackendLabel = activeBackendMeta?.label
    || (selectedBackend ? selectedBackend.replace(/_/g, " ") : "Select backend");

  // Models auto-detected from that backend's adapter inventory only
  // (configured providers + installed local models).
  const modelsForBackend = useMemo(() => {
    const entry = backendCatalog.find((b) => b.id === selectedBackend);
    const inv = entry?.inventory;
    const listed = (inv?.models || []).filter((m) => {
      if (!m.id || m.id.startsWith("(")) return false;
      // Reject accidental dict-stringified ids from bad catalog data
      if (m.id.includes("{") || m.id.includes("'default'")) return false;
      return true;
    });
    // Active first, then local, then cloud
    const rank = (m: (typeof listed)[number]) =>
      (m.in_use ? 0 : 10) + (m.location === "local" ? 0 : m.location === "cloud" ? 1 : 2);
    return [...listed].sort((a, b) => rank(a) - rank(b) || a.id.localeCompare(b.id));
  }, [backendCatalog, selectedBackend]);

  const providersForBackend = useMemo(() => {
    const entry = backendCatalog.find((b) => b.id === selectedBackend);
    return entry?.inventory?.providers || [];
  }, [backendCatalog, selectedBackend]);

  // When backend or catalog changes, keep model valid for that backend only.
  useEffect(() => {
    if (!selectedBackend) return;
    if (selectedModel && modelsForBackend.some((m) => m.id === selectedModel)) return;
    const preferred = modelsForBackend.find((m) => m.in_use) || modelsForBackend[0];
    if (preferred) {
      setSelectedModel(preferred.id);
      setSelectedModelProvider(preferred.provider || "");
    } else {
      setSelectedModel("");
      setSelectedModelProvider("");
    }
  }, [selectedBackend, modelsForBackend, selectedModel]);

  const activeModelLabel = (() => {
    if (!selectedModel) return modelsForBackend.length ? "Pick model" : "No models";
    const hit = modelsForBackend.find((m) => m.id === selectedModel);
    if (!hit) return selectedModel;
    const loc = hit.location && hit.location !== "unknown" ? ` · ${hit.location}` : "";
    return `${hit.label || hit.id}${loc}`;
  })();

  const filteredBackends = useMemo(() => {
    const q = backendSearchQuery.trim().toLowerCase();
    if (!q) return backendOptions;
    return backendOptions.filter(
      (b) => b.label.toLowerCase().includes(q) || b.id.toLowerCase().includes(q),
    );
  }, [backendOptions, backendSearchQuery]);

  const workspaceChoices = useMemo(() => {
    const paths = new Map<string, string>();
    for (const w of snapshot.workspaces || []) {
      if (w.path) paths.set(w.path, w.label || w.path);
    }
    if (currentSession?.workspace) {
      paths.set(currentSession.workspace, currentSession.workspace);
    }
    return Array.from(paths.entries()).map(([path, label]) => ({ path, label }));
  }, [snapshot.workspaces, currentSession?.workspace]);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: H.bg, color: H.text, position: "relative" }}>

      {/* Hidden file input for Attach button */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        style={{ display: "none" }}
        onChange={(e) => {
          if (e.target.files) {
            const files = Array.from(e.target.files);
            setAttachedFiles((prev) => [...prev, ...files]);
          }
        }}
      />

      {/* Messages area */}
      <div ref={transcriptRef} onScroll={onScroll} style={{ flex: 1, overflowY: "auto", overflowX: "hidden", position: "relative" }}>
        {sessionLoading ? (
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", minHeight: "100%", gap: 12, color: H.muted }}>
            <LoaderCircle size={22} style={{ color: H.accentGlow }} className="animate-spin" />
            <p style={{ fontSize: 13, margin: 0 }}>Loading conversation…</p>
          </div>
        ) : !hasConversation ? (
          /* Empty state */
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", minHeight: "100%", padding: "40px 24px", textAlign: "center", background: `radial-gradient(ellipse at 50% 25%, rgba(56,137,253,0.06) 0%, transparent 60%)` }}>
            <div style={{ marginBottom: 20 }}><CaduceusSVG /></div>
            <h2 style={{ fontSize: 22, fontWeight: 700, color: H.strong, margin: 0 }}>What can I help with?</h2>
            <p style={{ fontSize: 14, color: H.muted, margin: "8px 0 28px", lineHeight: 1.6, maxWidth: 380 }}>
              Ask anything, run commands, explore files, or manage your scheduled tasks.
            </p>
            <div style={{ display: "flex", flexDirection: "column", gap: 8, width: "100%", maxWidth: 520 }}>
              {[
                { icon: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>, text: "What files are in this workspace?" },
                { icon: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1"/><line x1="9" y1="12" x2="15" y2="12"/><line x1="9" y1="16" x2="12" y2="16"/></svg>, text: "What's on my schedule today?" },
                { icon: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/></svg>, text: "Help me plan a small project." },
              ].map((s) => (
                <button key={s.text} type="button" onClick={() => { setDraft(s.text); textareaRef.current?.focus(); }}
                  style={{ display: "flex", alignItems: "center", gap: 12, padding: "11px 16px", borderRadius: 10, border: `1px solid ${H.border2}`, background: H.surface, color: H.text, fontSize: 14, textAlign: "left", cursor: "pointer", transition: "all 0.15s" }}
                  onMouseEnter={(e) => { e.currentTarget.style.background = H.surfaceHover; e.currentTarget.style.borderColor = H.accent + "55"; }}
                  onMouseLeave={(e) => { e.currentTarget.style.background = H.surface; e.currentTarget.style.borderColor = H.border2; }}>
                  <span style={{ color: H.muted, flexShrink: 0 }}>{s.icon}</span>
                  <span>{s.text}</span>
                </button>
              ))}
            </div>
            {discoveryError && <p style={{ marginTop: 16, fontSize: 12, color: "#fbbf24" }}>{discoveryError}</p>}
          </div>
        ) : (
          /* Messages */
          <div style={{ maxWidth: 760, margin: "0 auto", width: "100%", padding: "28px 24px 120px", display: "flex", flexDirection: "column", gap: 22 }}>
            {(currentSession?.messages || []).map((message) => {
              const isUser = message.role === "user";
              return (
                <div key={message.id} style={{ display: "flex", width: "100%", justifyContent: isUser ? "flex-end" : "flex-start" }}>
                  {!isUser && (
                    <div style={{ width: 30, height: 30, borderRadius: "50%", flexShrink: 0, background: H.surface, border: `1px solid ${H.border2}`, display: "flex", alignItems: "center", justifyContent: "center", marginRight: 10, marginTop: 2 }}>
                      <Bot size={14} style={{ color: H.accentGlow }} />
                    </div>
                  )}
                  <div style={{ maxWidth: "85%", display: "flex", flexDirection: "column", alignItems: isUser ? "flex-end" : "flex-start", gap: 4 }}>
                    <div style={{ padding: "9px 14px", fontSize: 14, lineHeight: 1.6, background: isUser ? H.surfaceActive : "transparent", color: isUser ? H.strong : H.text, border: isUser ? `1px solid ${H.border2}` : "none", borderRadius: isUser ? "14px 14px 4px 14px" : 0, whiteSpace: "pre-wrap", wordBreak: "break-word" }}>
                      <Markdown content={message.text} />
                    </div>
                  </div>
                </div>
              );
            })}
            {streamState !== "idle" && (
              <div style={{ display: "flex", width: "100%" }}>
                <div style={{ width: 30, height: 30, borderRadius: "50%", flexShrink: 0, background: H.surface, border: `1px solid ${H.border2}`, display: "flex", alignItems: "center", justifyContent: "center", marginRight: 10, marginTop: 2 }}>
                  <Bot size={14} style={{ color: H.accentGlow }} />
                </div>
                <div style={{ maxWidth: "85%", fontSize: 14, lineHeight: 1.6, color: H.text }}>
                  {streamText ? <Markdown content={streamText} streaming /> : streamState === "starting" ? (
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <LoaderCircle size={15} style={{ color: H.accentGlow }} />
                      <span style={{ color: H.muted }}>Starting…</span>
                    </div>
                  ) : (
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <span style={{ width: 7, height: 7, borderRadius: "50%", background: H.accentBlue, display: "inline-block" }} />
                      <span style={{ color: H.muted }}>Thinking…</span>
                    </div>
                  )}
                  {streamReasoning && <div style={{ marginTop: 10, borderLeft: `2px solid ${H.accentBlue}`, paddingLeft: 12, fontSize: 13, fontStyle: "italic", color: H.muted }}>{streamReasoning}</div>}
                  {streamTools.length > 0 && (
                    <div style={{ marginTop: 10, display: "flex", flexWrap: "wrap", gap: 6 }}>
                      {streamTools.map((tool) => (
                        <span key={tool} style={{ display: "inline-flex", alignItems: "center", gap: 5, padding: "3px 8px", borderRadius: 6, fontSize: 11, fontWeight: 500, background: H.surface, border: `1px solid ${H.border}`, color: H.text }}>
                          <Wrench size={10} style={{ opacity: 0.7 }} />{tool}
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Floating scroll / copy buttons */}
      <div style={{ position: "absolute", bottom: 110, right: 20, display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 6, pointerEvents: "none", zIndex: 10 }}>
        {showScrollBottom && (
          <button type="button" onClick={() => transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: "smooth" })}
            style={{ pointerEvents: "auto", display: "flex", alignItems: "center", gap: 6, padding: "5px 12px", borderRadius: 999, border: `1px solid ${H.border2}`, background: H.surface, color: H.text, fontSize: 12, fontWeight: 500, cursor: "pointer" }}>
            <ArrowDown size={13} /> Bottom
          </button>
        )}
        {lastAssistantText && (
          <button type="button" onClick={() => void copyLastResponse()}
            style={{ pointerEvents: "auto", display: "flex", alignItems: "center", gap: 6, padding: "5px 12px", borderRadius: 999, border: `1px solid ${H.border2}`, background: H.surface, color: H.text, fontSize: 12, fontWeight: 500, cursor: "pointer" }}>
            {copied ? <Check size={13} style={{ color: "#4ade80" }} /> : <Copy size={13} />}
            {copied ? "Copied" : "Copy"}
          </button>
        )}
      </div>

      {/* COMPOSER */}
      <div style={{ flexShrink: 0, padding: "0 16px 14px", background: H.bg, position: "relative", zIndex: 10 }}>

        {/* Approval card */}
        {showApproval && (
          <div style={{ marginBottom: 8, borderRadius: 12, border: `1px solid ${H.border2}`, background: H.surface, overflow: "hidden", boxShadow: "0 8px 32px rgba(0,0,0,0.5)", maxWidth: 740, margin: "0 auto 8px" }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "9px 14px", borderBottom: `1px solid ${H.border}` }}>
              <span style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 13, fontWeight: 600, color: H.strong }}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
                Approval required
              </span>
              <div style={{ display: "flex", gap: 4 }}>
                <button onClick={() => setApprovalCollapsed(!approvalCollapsed)} style={{ background: "transparent", border: "none", color: H.muted, cursor: "pointer", padding: 4 }}>{approvalCollapsed ? <ChevronDown size={14} /> : <ChevronUp size={14} />}</button>
                <button onClick={() => setShowApproval(false)} style={{ background: "transparent", border: "none", color: H.muted, cursor: "pointer", padding: 4 }}><X size={14} /></button>
              </div>
            </div>
            {!approvalCollapsed && (
              <div style={{ padding: "12px 14px" }}>
                <p style={{ fontSize: 13, color: H.muted, marginBottom: 10 }}>Agent is requesting permission to execute:</p>
                <code style={{ display: "block", background: "#0a0c14", padding: "8px 12px", borderRadius: 7, fontFamily: "monospace", fontSize: 12, color: "#4ade80", border: `1px solid ${H.border}`, marginBottom: 12, overflowX: "auto" }}>$ rm -rf /tmp/cache/*</code>
                <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                  {["Allow once", "Allow session", "Always allow", "Deny", "Skip all ⚡"].map((label) => (
                    <button key={label} type="button" onClick={() => setShowApproval(false)}
                      style={{ padding: "5px 12px", borderRadius: 7, fontSize: 12, cursor: "pointer", fontWeight: 500, background: label === "Allow once" ? H.accent : label === "Deny" ? "#3b1219" : H.surface, color: label === "Allow once" ? "#fff" : label === "Deny" ? "#fca5a5" : H.text, border: label === "Allow once" ? "none" : label === "Deny" ? "1px solid #7f1d1d" : `1px solid ${H.border2}` }}>
                      {label}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {isReadOnlyCli && (
          <div style={{ marginBottom: 8, maxWidth: 740, margin: "0 auto 8px", padding: "9px 14px", borderRadius: 8, border: "1px solid rgba(56,137,253,0.35)", background: "rgba(56,137,253,0.08)", color: H.accentBlue, fontSize: 12 }}>
            CLI / imported session (read-only). Switch to a <strong>WebUI</strong> session in the deck to talk to a backend.
          </div>
        )}
        {!isReadOnlyCli && (
          <div style={{ marginBottom: 8, maxWidth: 740, margin: "0 auto 8px", padding: "6px 12px", borderRadius: 8, border: `1px solid ${H.border}`, background: H.surface, color: H.muted, fontSize: 11 }}>
            Worker console — messages go to the selected backend as-is (no Companion SI prompt). Profile & app theme live in App settings.
          </div>
        )}
        {chatNotice && (
          <div style={{ marginBottom: 8, maxWidth: 740, margin: "0 auto 8px", padding: "9px 14px", borderRadius: 8, border: "1px solid rgba(251,191,36,0.3)", background: "rgba(251,191,36,0.08)", color: "#fbbf24", fontSize: 13, display: "flex", alignItems: "center", gap: 8 }}>
            <AlertTriangle size={13} />{chatNotice}
          </div>
        )}

        {/* Saved Prompts Popover */}
        {showSavedPrompts && (
          <div style={{ maxWidth: 740, margin: "0 auto 8px", padding: 10, borderRadius: 10, border: `1px solid ${H.border2}`, background: H.surface, boxShadow: "0 8px 24px rgba(0,0,0,0.4)" }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 6, paddingBottom: 4, borderBottom: `1px solid ${H.border}` }}>
              <span style={{ fontSize: 12, fontWeight: 600, color: H.text }}>Saved Prompts</span>
              <button type="button" onClick={() => setShowSavedPrompts(false)} style={{ background: "transparent", border: "none", color: H.muted, cursor: "pointer" }}><X size={12} /></button>
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6 }}>
              {SAVED_PROMPT_TEMPLATES.map((item) => (
                <button
                  key={item.label}
                  type="button"
                  onClick={() => {
                    setDraft((prev) => prev ? `${prev}\n\n${item.prompt}` : item.prompt);
                    setShowSavedPrompts(false);
                    textareaRef.current?.focus();
                  }}
                  style={{ textAlign: "left", padding: "6px 8px", borderRadius: 6, border: `1px solid ${H.border2}`, background: H.chipBg, color: H.text, fontSize: 11, cursor: "pointer" }}
                >
                  <div style={{ fontWeight: 600, color: H.accentGlow }}>{item.label}</div>
                  <div style={{ color: H.muted, fontSize: 10, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{item.prompt}</div>
                </button>
              ))}
            </div>
          </div>
        )}

        <form onSubmit={(e) => void submit(e)} style={{ maxWidth: 740, margin: "0 auto" }}>
          <div style={{ borderRadius: 14, border: `1px solid ${H.inputBorder}`, background: H.inputBg, boxShadow: "0 2px 16px rgba(0,0,0,0.35)", transition: "border-color 0.2s" }}>

            {/* Attached files tray */}
            {attachedFiles.length > 0 && (
              <div style={{ display: "flex", flexWrap: "wrap", gap: 6, padding: "8px 12px 0" }}>
                {attachedFiles.map((file, idx) => (
                  <span key={idx} style={{ display: "inline-flex", alignItems: "center", gap: 6, padding: "3px 8px", borderRadius: 6, background: H.surface, border: `1px solid ${H.border2}`, fontSize: 11, color: H.text }}>
                    <FileText size={11} style={{ color: H.accentGlow }} />
                    <span style={{ maxWidth: 120, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{file.name}</span>
                    <button type="button" onClick={() => setAttachedFiles((prev) => prev.filter((_, i) => i !== idx))} style={{ background: "transparent", border: "none", color: H.muted, cursor: "pointer", padding: 0 }}>
                      <X size={10} />
                    </button>
                  </span>
                ))}
              </div>
            )}

            {/* Listening indicator */}
            {isListening && (
              <div style={{ padding: "6px 14px", fontSize: 11, fontWeight: 600, color: "#f43f5e", display: "flex", alignItems: "center", gap: 6 }}>
                <span style={{ width: 6, height: 6, borderRadius: "50%", background: "#f43f5e", display: "inline-block" }} />
                Listening for speech dictation…
              </div>
            )}

            <textarea
              ref={textareaRef}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={handleComposerKeyDown}
              rows={1}
              aria-label="Message"
              placeholder={
                isReadOnlyCli
                  ? "CLI session is read-only — open a WebUI session to chat"
                  : `Message ${activeBackendLabel}…`
              }
              disabled={isBusy || isReadOnlyCli}
              style={{ width: "100%", padding: "13px 16px 8px", background: "transparent", border: "none", outline: "none", color: H.text, fontSize: 14.5, lineHeight: 1.5, resize: "none", fontFamily: "inherit", boxSizing: "border-box", maxHeight: 180, overflowY: "auto" }}
              onInput={(e) => { const el = e.currentTarget; el.style.height = "auto"; el.style.height = Math.min(el.scrollHeight, 180) + "px"; }}
            />

            {/* Toolbar */}
            <div style={{ display: "flex", alignItems: "center", padding: "4px 8px 8px", gap: 3, flexWrap: "wrap" }}>
              <IconBtn title="Attach files" onClick={() => fileInputRef.current?.click()}><Paperclip size={15} /></IconBtn>
              <IconBtn title="Saved prompts" onClick={() => setShowSavedPrompts(!showSavedPrompts)}><Bookmark size={15} /></IconBtn>
              <IconBtn title="Dictate" onClick={toggleDictation}>
                {isListening ? <MicOff size={15} style={{ color: "#f43f5e" }} /> : <Mic size={15} />}
              </IconBtn>

              <div style={{ width: 1, height: 16, background: H.border2, margin: "0 3px" }} />

              {/* Working folder — agent cwd / project context */}
              <div style={{ position: "relative", display: "inline-flex", alignItems: "center", borderRadius: 6, border: `1px solid ${H.chipBorder}`, background: H.chipBg, height: 26, overflow: "visible" }} onClick={(e) => e.stopPropagation()}>
                <button
                  type="button"
                  title="Browse files in working folder"
                  onClick={workbenchPanel.toggle}
                  style={{ display: "inline-flex", alignItems: "center", justifyContent: "center", padding: "0 6px", height: "100%", border: "none", borderRight: `1px solid ${H.chipBorder}`, background: "transparent", color: H.chipText, cursor: "pointer" }}
                >
                  <Folder size={12} />
                </button>

                <button
                  type="button"
                  title={workspacePath || "Working folder"}
                  onClick={() => {
                    setShowWorkspaceMenu(!showWorkspaceMenu);
                    setShowBackendMenu(false);
                    setShowModelMenu(false);
                  }}
                  style={{ display: "inline-flex", alignItems: "center", gap: 5, height: "100%", padding: "0 8px", border: "none", background: "transparent", color: H.chipText, fontSize: 12, fontWeight: 500, cursor: "pointer", maxWidth: 140 }}
                >
                  <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{activeWorkspaceLabel}</span>
                  <ChevronDown size={9} style={{ opacity: 0.5, flexShrink: 0 }} />
                </button>

                {showWorkspaceMenu && (
                  <div style={{ position: "absolute", left: 0, bottom: 34, zIndex: 40, width: 360, borderRadius: 12, border: `1px solid ${H.border2}`, background: "#131622", boxShadow: "0 16px 48px rgba(0,0,0,0.7)", fontSize: 12, overflow: "hidden" }}>
                    <div style={{ padding: "10px 14px 6px", fontSize: 11, fontWeight: 600, color: H.muted, borderBottom: `1px solid ${H.border}` }}>
                      Agent working folder (cwd / context)
                    </div>
                    <div style={{ padding: "12px 14px", background: "rgba(124,58,237,0.12)", borderBottom: `1px solid ${H.border}` }}>
                      <div style={{ fontWeight: 600, color: H.strong, fontSize: 13, marginBottom: 2 }}>{activeWorkspaceLabel}</div>
                      <div style={{ fontSize: 11, color: H.muted, fontFamily: "monospace", wordBreak: "break-all" }}>
                        {workspacePath || "No working folder set"}
                      </div>
                    </div>
                    <div style={{ padding: "8px 10px", borderBottom: `1px solid ${H.border}` }}>
                      <input
                        type="text"
                        value={wsSearchQuery}
                        onChange={(e) => setWsSearchQuery(e.target.value)}
                        placeholder="Filter known folders…"
                        style={{ width: "100%", boxSizing: "border-box", background: "#0c0e18", border: `1px solid ${H.border}`, borderRadius: 8, padding: "6px 10px", color: H.text, fontSize: 12, outline: "none" }}
                      />
                    </div>
                    <div style={{ maxHeight: 160, overflowY: "auto", padding: "6px 8px" }}>
                      {workspaceChoices
                        .filter((w) => {
                          const q = wsSearchQuery.trim().toLowerCase();
                          if (!q) return true;
                          return w.path.toLowerCase().includes(q) || w.label.toLowerCase().includes(q);
                        })
                        .map((w) => (
                          <button
                            key={w.path}
                            type="button"
                            onClick={() => {
                              setWorkspaceOverride(w.path);
                              setShowWorkspaceMenu(false);
                            }}
                            style={{
                              display: "block", width: "100%", textAlign: "left", padding: "8px 10px", marginBottom: 4,
                              borderRadius: 6, border: `1px solid ${workspacePath === w.path ? H.accent : H.border}`,
                              background: workspacePath === w.path ? "rgba(124,58,237,0.1)" : "transparent",
                              color: H.text, cursor: "pointer",
                            }}
                          >
                            <div style={{ fontWeight: 600, fontSize: 12 }}>{w.label.split("/").filter(Boolean).pop() || w.label}</div>
                            <div style={{ fontSize: 10, color: H.muted, fontFamily: "monospace", wordBreak: "break-all" }}>{w.path}</div>
                          </button>
                        ))}
                    </div>
                    <div style={{ display: "flex", flexDirection: "column", borderTop: `1px solid ${H.border}` }}>
                      <button
                        type="button"
                        onClick={() => {
                          const path = prompt("Working folder for this agent:", workspacePath || "");
                          if (path?.trim()) setWorkspaceOverride(path.trim());
                          setShowWorkspaceMenu(false);
                        }}
                        style={{ display: "flex", alignItems: "flex-start", gap: 12, padding: "10px 14px", background: "transparent", border: "none", borderBottom: `1px solid ${H.border}`, color: H.text, textAlign: "left", cursor: "pointer" }}
                      >
                        <Folder size={16} style={{ color: H.accentGlow, marginTop: 2, flexShrink: 0 }} />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: 12.5, color: H.strong }}>Set working folder…</div>
                          <div style={{ fontSize: 11, color: H.muted, marginTop: 2 }}>cwd / project context for the backend</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          void createSession(workspacePath || undefined);
                          setShowWorkspaceMenu(false);
                        }}
                        style={{ display: "flex", alignItems: "flex-start", gap: 12, padding: "10px 14px", background: "transparent", border: "none", borderBottom: `1px solid ${H.border}`, color: H.text, textAlign: "left", cursor: "pointer" }}
                      >
                        <GitBranch size={16} style={{ color: H.accentGlow, marginTop: 2, flexShrink: 0 }} />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: 12.5, color: H.strong }}>New WebUI session here</div>
                          <div style={{ fontSize: 11, color: H.muted, marginTop: 2 }}>Fresh conversation in this folder</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          workbenchPanel.toggle();
                          setShowWorkspaceMenu(false);
                        }}
                        style={{ display: "flex", alignItems: "flex-start", gap: 12, padding: "10px 14px", background: "transparent", border: "none", color: H.text, textAlign: "left", cursor: "pointer" }}
                      >
                        <Settings size={16} style={{ color: H.muted, marginTop: 2, flexShrink: 0 }} />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: 12.5, color: H.strong }}>Browse files</div>
                          <div style={{ fontSize: 11, color: H.muted, marginTop: 2 }}>Open workspace panel</div>
                        </div>
                      </button>
                    </div>
                  </div>
                )}
              </div>

              {/* Backend chip — framework/runtime (distinct Server icon) */}
              <div style={{ position: "relative" }} onClick={(e) => e.stopPropagation()}>
                <ComposerChip
                  icon={<Server size={12} />}
                  label={activeBackendLabel}
                  onClick={() => {
                    if (isReadOnlyCli) return;
                    setShowBackendMenu(!showBackendMenu);
                    setShowWorkspaceMenu(false);
                    setShowModelMenu(false);
                  }}
                />
                {showBackendMenu && !isReadOnlyCli && (
                  <div style={{ position: "absolute", left: 0, bottom: 34, zIndex: 40, width: 320, borderRadius: 12, border: `1px solid ${H.border2}`, background: "#131622", boxShadow: "0 16px 48px rgba(0,0,0,0.7)", fontSize: 12, overflow: "hidden" }}>
                    <div style={{ padding: "10px 14px 6px", fontSize: 11, fontWeight: 600, color: H.muted, borderBottom: `1px solid ${H.border}` }}>
                      Backend (worker runtime)
                    </div>
                    <div style={{ padding: "8px 10px", borderBottom: `1px solid ${H.border}` }}>
                      <input
                        type="text"
                        value={backendSearchQuery}
                        onChange={(e) => setBackendSearchQuery(e.target.value)}
                        placeholder="Filter backends…"
                        style={{ width: "100%", background: "#0c0e18", border: `1px solid ${H.border}`, borderRadius: 8, padding: "6px 10px", color: H.text, fontSize: 12, outline: "none", boxSizing: "border-box" }}
                      />
                    </div>
                    <div style={{ maxHeight: 240, overflowY: "auto", padding: "8px 10px" }}>
                      {filteredBackends.length === 0 ? (
                        <p style={{ margin: 0, padding: 8, color: H.muted, fontSize: 11 }}>No backends available.</p>
                      ) : (
                        filteredBackends.map((b) => (
                          <button
                            key={b.id}
                            type="button"
                            onClick={() => {
                              setSelectedBackend(b.id);
                              setSelectedModel("");
                              setSelectedModelProvider("");
                              setShowBackendMenu(false);
                            }}
                            style={{
                              display: "flex", flexDirection: "column", width: "100%", padding: "8px 10px", marginBottom: 4,
                              borderRadius: 6, border: `1px solid ${selectedBackend === b.id ? H.accent : H.border}`,
                              background: selectedBackend === b.id ? "rgba(124,58,237,0.1)" : "transparent",
                              color: H.text, textAlign: "left", cursor: "pointer",
                            }}
                          >
                            <span style={{ fontWeight: 600, fontSize: 12, display: "inline-flex", alignItems: "center", gap: 6 }}>
                              <Server size={11} style={{ opacity: 0.7 }} />
                              {b.label}
                            </span>
                            <span style={{ fontSize: 10, color: H.muted, fontFamily: "monospace" }}>{b.id}</span>
                          </button>
                        ))
                      )}
                    </div>
                  </div>
                )}
              </div>

              {/* Model chip — only models configured for the selected backend (Boxes icon) */}
              <div style={{ position: "relative" }} onClick={(e) => e.stopPropagation()}>
                <ComposerChip
                  icon={<Boxes size={12} />}
                  label={activeModelLabel}
                  onClick={() => {
                    if (isReadOnlyCli || modelsForBackend.length === 0) return;
                    setShowModelMenu(!showModelMenu);
                    setShowWorkspaceMenu(false);
                    setShowBackendMenu(false);
                  }}
                />
                {showModelMenu && !isReadOnlyCli && modelsForBackend.length > 0 && (
                  <div style={{ position: "absolute", left: 0, bottom: 34, zIndex: 40, width: 340, borderRadius: 12, border: `1px solid ${H.border2}`, background: "#131622", boxShadow: "0 16px 48px rgba(0,0,0,0.7)", fontSize: 12, overflow: "hidden" }}>
                    <div style={{ padding: "10px 14px 6px", fontSize: 11, fontWeight: 600, color: H.muted, borderBottom: `1px solid ${H.border}` }}>
                      Models for {activeBackendLabel}
                    </div>
                    {providersForBackend.length > 0 && (
                      <div style={{ padding: "8px 12px", borderBottom: `1px solid ${H.border}`, fontSize: 10, color: H.muted }}>
                        <span style={{ fontWeight: 700, textTransform: "uppercase", letterSpacing: "0.06em" }}>Providers: </span>
                        {providersForBackend.map((p) => p.label || p.id).join(" · ")}
                      </div>
                    )}
                    <div style={{ maxHeight: 260, overflowY: "auto", padding: "8px 10px" }}>
                      {(["local", "cloud", "unknown"] as const).map((loc) => {
                        const group = modelsForBackend.filter((m) => (m.location || "unknown") === loc);
                        if (!group.length) return null;
                        return (
                          <div key={loc} style={{ marginBottom: 8 }}>
                            <div style={{ fontSize: 10, fontWeight: 700, textTransform: "uppercase", letterSpacing: "0.08em", color: H.muted, margin: "4px 2px 6px" }}>
                              {loc === "local" ? "Local / installed" : loc === "cloud" ? "Cloud / configured" : "Other"}
                            </div>
                            {group.map((m) => (
                              <button
                                key={`${m.id}-${m.provider || ""}`}
                                type="button"
                                onClick={() => {
                                  setSelectedModel(m.id);
                                  setSelectedModelProvider(m.provider || "");
                                  setShowModelMenu(false);
                                }}
                                style={{
                                  display: "block", width: "100%", textAlign: "left", padding: "8px 10px", marginBottom: 4,
                                  borderRadius: 6, border: `1px solid ${selectedModel === m.id ? H.accent : H.border}`,
                                  background: selectedModel === m.id ? "rgba(124,58,237,0.1)" : "transparent", color: H.text, cursor: "pointer",
                                }}
                              >
                                <div style={{ fontWeight: 600, fontSize: 12, display: "inline-flex", alignItems: "center", gap: 6 }}>
                                  <Boxes size={11} style={{ opacity: 0.7 }} />
                                  {m.label || m.id}
                                  {m.in_use ? (
                                    <span style={{ fontSize: 9, fontWeight: 700, padding: "1px 5px", borderRadius: 4, background: H.accent, color: "#fff" }}>ACTIVE</span>
                                  ) : null}
                                </div>
                                <div style={{ fontSize: 10, color: H.muted, fontFamily: "monospace" }}>
                                  {m.provider || "—"}{m.notes ? ` · ${m.notes}` : ""}
                                </div>
                              </button>
                            ))}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>

              <div style={{ flex: 1 }} />

              {isBusy ? (
                <button type="button" onClick={() => void cancelResponse()} title="Stop response"
                  style={{ width: 34, height: 34, borderRadius: "50%", border: `1px solid ${H.border2}`, background: H.surface, color: H.text, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>
                  <Square size={14} fill="currentColor" />
                </button>
              ) : (
                <button type="submit" disabled={!draft.trim() && attachedFiles.length === 0} title="Send message"
                  style={{ width: 34, height: 34, borderRadius: "50%", border: "none", background: draft.trim() || attachedFiles.length > 0 ? H.sendBtn : "rgba(255,255,255,0.06)", color: draft.trim() || attachedFiles.length > 0 ? H.sendBtnText : "rgba(255,255,255,0.25)", cursor: draft.trim() || attachedFiles.length > 0 ? "pointer" : "default", display: "flex", alignItems: "center", justifyContent: "center", transition: "background 0.15s, color 0.15s" }}>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/></svg>
                </button>
              )}
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}

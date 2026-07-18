import {
  AlertTriangle,
  Check,
  Copy,
  Download,
  ExternalLink,
  FileText,
  LoaderCircle,
  MessageCircle,
  Printer,
  QrCode,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { apiFetch, readableError } from "@/shared/api-client";
import { translateMessage } from "@/shared/translators";
import type { ConversationMessage } from "@/shared/contracts";

// ── Types ────────────────────────────────────────────────────────────────────

interface SharedConversation {
  title: string;
  messages: ConversationMessage[];
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function translateShare(value: unknown): SharedConversation {
  const payload = value && typeof value === "object" ? (value as Record<string, unknown>) : {};
  const raw = payload.share && typeof payload.share === "object" ? (payload.share as Record<string, unknown>) : {};
  return {
    title: String(raw.title || "Shared conversation"),
    messages: Array.isArray(raw.messages) ? raw.messages.map(translateMessage) : [],
  };
}

/** Convert conversation to a simple Markdown string. */
function toMarkdown(title: string, messages: ConversationMessage[], url: string): string {
  const lines: string[] = [`# ${title}`, "", `> Shared via ARES — ${url}`, ""];
  for (const m of messages) {
    const label = m.role === "user" ? "**You**" : m.role === "system" ? "**System**" : m.role === "tool" ? "**Tool**" : "**Assistant**";
    lines.push(`### ${label}`, "", m.text, "");
  }
  return lines.join("\n");
}

function downloadBlob(blob: Blob, filename: string) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}

// ── QR Placeholder ───────────────────────────────────────────────────────────

function QrPlaceholder({ url }: { url: string }) {
  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <button
            type="button"
            className="flex size-28 items-center justify-center rounded-lg border border-dashed border-border bg-surface text-muted-foreground transition-colors hover:border-border2 hover:text-accent"
            onClick={() => void navigator.clipboard.writeText(url).catch(() => {})}
            aria-label="QR code placeholder — click to copy link"
          >
            <QrCode className="size-10" />
          </button>
        </TooltipTrigger>
        <TooltipContent>QR code coming soon — click to copy link</TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}

// ── Loading skeleton ─────────────────────────────────────────────────────────

function LoadingSkeleton() {
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Skeleton className="h-3 w-24" />
        <Skeleton className="h-8 w-3/4" />
        <Skeleton className="h-4 w-20" />
      </div>
      <Card>
        <CardContent className="divide-y">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="py-5 space-y-3">
              <Skeleton className="h-3 w-16" />
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-5/6" />
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}

// ── Error state ──────────────────────────────────────────────────────────────

function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <Card>
      <CardContent className="grid place-items-center gap-4 py-16 text-center">
        <div className="flex size-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
          <AlertTriangle className="size-6" />
        </div>
        <div>
          <h1 className="text-xl font-semibold">Share unavailable</h1>
          <p className="mt-2 max-w-md text-sm text-muted-foreground">{message}</p>
        </div>
        <Button variant="outline" size="sm" onClick={onRetry}>
          <LoaderCircle className="animate-spin" /> Try again
        </Button>
      </CardContent>
    </Card>
  );
}

// ── Main page ────────────────────────────────────────────────────────────────

export function SharePage() {
  const { token = "" } = useParams();
  const [share, setShare] = useState<SharedConversation | null>(null);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [printMode, setPrintMode] = useState(false);

  const loadShare = useCallback(() => {
    setShare(null);
    setError("");
    if (!token) {
      setError("Missing share token.");
      return;
    }
    apiFetch(`/api/share/${encodeURIComponent(token)}`)
      .then((payload) => setShare(translateShare(payload)))
      .catch((reason) => setError(readableError(reason, "This shared conversation is unavailable.")));
  }, [token]);

  useEffect(() => {
    loadShare();
  }, [loadShare]);

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(window.location.href);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      setError("The browser could not copy this link.");
    }
  }

  function exportMarkdown() {
    if (!share) return;
    const md = toMarkdown(share.title, share.messages, window.location.href);
    downloadBlob(new Blob([md], { type: "text/markdown;charset=utf-8" }), `${share.title.replace(/[^a-z0-9]+/gi, "-").toLowerCase()}.md`);
  }

  function handlePrint() {
    setPrintMode(true);
    // Let React render the print-friendly view, then trigger print.
    requestAnimationFrame(() => {
      window.print();
      setPrintMode(false);
    });
  }

  // ── Render ────────────────────────────────────────────────────────────────

  if (printMode && share) {
    return (
      <main className="min-h-dvh bg-white text-black print:bg-white print:text-black">
        <div className="mx-auto max-w-3xl px-6 py-8">
          <h1 className="text-2xl font-bold">{share.title}</h1>
          <p className="mt-1 text-sm text-gray-500">{share.messages.length} message{share.messages.length === 1 ? "" : "s"} · Shared via ARES</p>
          <hr className="my-6 border-gray-200" />
          {share.messages.map((message) => (
            <article key={message.id} className="mb-6">
              <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-500">{message.role}</p>
              <p className="whitespace-pre-wrap break-words text-sm leading-6 text-gray-900">{message.text}</p>
            </article>
          ))}
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-dvh bg-background px-4 py-8 text-foreground sm:px-6">
      <div className="mx-auto max-w-4xl">
        {/* ── Header ──────────────────────────────────────────────────────── */}
        <header className="mb-8 flex flex-wrap items-center justify-between gap-4 border-b pb-5">
          <div>
            <p className="text-sm font-semibold">ARES shared conversation</p>
            <p className="text-xs text-muted-foreground">Read-only snapshot</p>
          </div>
          <div className="flex flex-wrap gap-2">
            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button variant="outline" size="sm" onClick={() => void copyLink()}>
                    {copied ? <Check className="text-status-ok" /> : <Copy />}
                    {copied ? "Copied" : "Copy link"}
                  </Button>
                </TooltipTrigger>
                <TooltipContent>{copied ? "Link copied to clipboard" : "Copy share link to clipboard"}</TooltipContent>
              </Tooltip>
            </TooltipProvider>

            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button variant="outline" size="sm" onClick={exportMarkdown} disabled={!share}>
                    <Download />
                    Export .md
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Download conversation as Markdown</TooltipContent>
              </Tooltip>
            </TooltipProvider>

            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button variant="outline" size="sm" onClick={handlePrint} disabled={!share}>
                    <Printer />
                    Print
                  </Button>
                </TooltipTrigger>
                <TooltipContent>Print-friendly view</TooltipContent>
              </Tooltip>
            </TooltipProvider>

            <Button asChild variant="outline" size="sm">
              <Link to="/">
                <ExternalLink />
                Open ARES
              </Link>
            </Button>
          </div>
        </header>

        {/* ── Error ───────────────────────────────────────────────────────── */}
        {error ? (
          <ErrorState message={error} onRetry={loadShare} />
        ) : !share ? (
          <LoadingSkeleton />
        ) : (
          <>
            {/* ── Title + meta ────────────────────────────────────────────── */}
            <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p className="text-xs uppercase tracking-widest text-muted-foreground">Public share</p>
                <h1 className="mt-2 text-3xl font-semibold tracking-tight">{share.title}</h1>
                <p className="mt-2 text-sm text-muted-foreground">
                  {share.messages.length} message{share.messages.length === 1 ? "" : "s"}
                </p>
              </div>
              <QrPlaceholder url={window.location.href} />
            </div>

            {/* ── Messages ─────────────────────────────────────────────────── */}
            <Card>
              <CardContent className="divide-y">
                {share.messages.length ? (
                  share.messages.map((message) => (
                    <article key={message.id} className="py-5">
                      <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{message.role}</p>
                      <p className="whitespace-pre-wrap break-words text-sm leading-6">{message.text}</p>
                    </article>
                  ))
                ) : (
                  <div className="grid place-items-center py-12 text-center text-muted-foreground">
                    <MessageCircle className="mb-3 size-8" />
                    <p>This shared conversation has no visible messages.</p>
                  </div>
                )}
              </CardContent>
            </Card>

            {/* ── Footer ───────────────────────────────────────────────────── */}
            <footer className="mt-8 flex flex-wrap items-center justify-between gap-2 border-t pt-5 text-xs text-muted-foreground">
              <p>Shared via ARES</p>
              <div className="flex gap-3">
                <button type="button" className="hover:text-foreground transition-colors" onClick={exportMarkdown}>
                  <FileText className="mr-1 inline size-3 align-[-2px]" />
                  Markdown
                </button>
                <button type="button" className="hover:text-foreground transition-colors" onClick={handlePrint}>
                  <Printer className="mr-1 inline size-3 align-[-2px]" />
                  Print
                </button>
              </div>
            </footer>
          </>
        )}
      </div>
    </main>
  );
}
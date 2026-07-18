import { Copy, ExternalLink, MessageCircle } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { apiFetch, readableError } from "@/shared/api-client";
import { translateMessage } from "@/shared/translators";
import type { ConversationMessage } from "@/shared/contracts";

interface SharedConversation {
  title: string;
  messages: ConversationMessage[];
}

function translateShare(value: unknown): SharedConversation {
  const payload = value && typeof value === "object" ? value as Record<string, unknown> : {};
  const raw = payload.share && typeof payload.share === "object" ? payload.share as Record<string, unknown> : {};
  return {
    title: String(raw.title || "Shared conversation"),
    messages: Array.isArray(raw.messages) ? raw.messages.map(translateMessage) : [],
  };
}

export function SharePage() {
  const { token = "" } = useParams();
  const [share, setShare] = useState<SharedConversation | null>(null);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!token) { setError("Missing share token."); return; }
    apiFetch(`/api/share/${encodeURIComponent(token)}`)
      .then((payload) => setShare(translateShare(payload)))
      .catch((reason) => setError(readableError(reason, "This shared conversation is unavailable.")));
  }, [token]);

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(window.location.href);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1200);
    } catch {
      setError("The browser could not copy this link.");
    }
  }

  return (
    <main className="min-h-dvh bg-background px-4 py-8 text-foreground sm:px-6">
      <div className="mx-auto max-w-4xl">
        <header className="mb-8 flex flex-wrap items-center justify-between gap-4 border-b pb-5">
          <div>
            <p className="text-sm font-semibold">ARES shared conversation</p>
            <p className="text-xs text-muted-foreground">Read-only snapshot</p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => void copyLink()}><Copy />{copied ? "Copied" : "Copy link"}</Button>
            <Button asChild variant="outline"><Link to="/"><ExternalLink />Open ARES</Link></Button>
          </div>
        </header>
        {error ? (
          <Card><CardContent className="py-12 text-center"><h1 className="text-xl font-semibold">Share unavailable</h1><p className="mt-2 text-sm text-status-limited">{error}</p></CardContent></Card>
        ) : !share ? (
          <Card><CardContent className="py-12 text-center text-sm text-muted-foreground">Loading shared conversation…</CardContent></Card>
        ) : (
          <>
            <div className="mb-6"><p className="text-xs uppercase tracking-widest text-muted-foreground">Public share</p><h1 className="mt-2 text-3xl font-semibold tracking-tight">{share.title}</h1><p className="mt-2 text-sm text-muted-foreground">{share.messages.length} message{share.messages.length === 1 ? "" : "s"}</p></div>
            <Card><CardContent className="divide-y">
              {share.messages.length ? share.messages.map((message) => <article key={message.id} className="py-5"><p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{message.role}</p><p className="whitespace-pre-wrap break-words text-sm leading-6">{message.text}</p></article>) : <div className="grid place-items-center py-12 text-center text-muted-foreground"><MessageCircle className="mb-3 size-8" /><p>This shared conversation has no visible messages.</p></div>}
            </CardContent></Card>
          </>
        )}
      </div>
    </main>
  );
}

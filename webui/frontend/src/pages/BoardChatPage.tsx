import {
  ArrowRight,
  ChevronDown,
  GripVertical,
  LoaderCircle,
  MessageCircle,
  NotepadText,
  Plus,
  Send,
  Square,
  Trash2,
  X,
} from "lucide-react";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type Dispatch,
  type FormEvent,
  type KeyboardEvent,
  type SetStateAction,
} from "react";

import { EmptyState } from "@/components/EmptyState";
import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { Markdown } from "@/components/Markdown";
import { useAres } from "@/shared/ares-context";
import { readableError } from "@/shared/api-client";
import { useProductState } from "@/shared/use-product-state";

// ── Types ────────────────────────────────────────────────────────────────

type ColumnId = "todo" | "in_progress" | "done";
type CardKind = "chat" | "task" | "note";

interface BoardCard {
  id: string;
  kind: CardKind;
  title: string;
  description?: string;
  column: ColumnId;
  order: number;
  sessionId?: string;
  createdAt: string;
}

interface BoardState {
  cards: BoardCard[];
}

// ── Column config ─────────────────────────────────────────────────────────

const COLUMNS: { id: ColumnId; label: string; accent: string }[] = [
  { id: "todo", label: "To Do", accent: "bg-muted-foreground/20" },
  { id: "in_progress", label: "In Progress", accent: "bg-primary/60" },
  { id: "done", label: "Done", accent: "bg-status-available/60" },
];

function nextId(): string {
  return `card-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

const KIND_ICONS: Record<CardKind, typeof MessageCircle> = {
  chat: MessageCircle,
  task: ArrowRight,
  note: NotepadText,
};

const KIND_LABELS: Record<CardKind, string> = {
  chat: "Chat",
  task: "Task",
  note: "Note",
};

// ── Inline Chat Panel ─────────────────────────────────────────────────────

function ChatPanel({
  card,
  onClose,
}: {
  card: BoardCard;
  onClose: () => void;
}) {
  const { snapshot, currentSession, selectSession, createSession, sendMessage, streamText, streamState, cancelResponse } = useAres();
  const [draft, setDraft] = useState("");
  const [messages, setMessages] = useState<{ role: string; text: string }[]>([]);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const isBusy = streamState !== "idle";

  // Auto-scroll
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: "smooth" });
  }, [messages.length, streamText]);

  // If the card has a sessionId, select it
  useEffect(() => {
    if (card.sessionId) {
      selectSession(card.sessionId);
    }
  }, [card.sessionId, selectSession]);

  // Mirror stream into local messages when stream completes
  useEffect(() => {
    if (streamState === "idle" && currentSession?.id === card.sessionId) {
      if (!currentSession) return;
      const assistant = currentSession.messages.slice(-1)[0];
      if (assistant && assistant.role !== "user" && !messages.some((m) => m.text === assistant.text && m.role === assistant.role)) {
        setMessages((prev) => [...prev, { role: assistant.role, text: assistant.text }]);
      }
    }
  }, [streamState, currentSession, card.sessionId, messages]);

  const submit = useCallback(async (e: FormEvent) => {
    e.preventDefault();
    const text = draft.trim();
    if (!text || isBusy) return;
    setDraft("");
    setError(null);
    setMessages((prev) => [...prev, { role: "user", text }]);

    try {
      let sessionId = card.sessionId;
      if (!sessionId) {
        const session = await createSession();
        sessionId = session.id;
        // The parent will need to know the sessionId; we'll bubble up via onClose pattern or a callback
        // For simplicity we just use the ares context's current session
      }
      await sendMessage(text);
    } catch (err) {
      setError(readableError(err, "Failed to send message."));
    }
  }, [draft, isBusy, card.sessionId, createSession, sendMessage]);

  const handleKeyDown = useCallback((e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      e.currentTarget.form?.requestSubmit();
    }
  }, []);

  const displayMessages = useMemo(() => {
    const base = [...messages];
    // Show optimistic user messages from current session if it matches
    if (currentSession?.id === card.sessionId) {
      if (!currentSession) return base;
      for (const m of currentSession.messages) {
        if (!base.some((b) => b.text === m.text && b.role === m.role)) {
          base.push({ role: m.role, text: m.text });
        }
      }
    }
    return base;
  }, [messages, currentSession, card.sessionId]);

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-4 py-3">
        <MessageCircle className="size-4 text-primary" />
        <h3 className="min-w-0 flex-1 truncate text-sm font-semibold">{card.title}</h3>
        <Button variant="ghost" size="icon-sm" onClick={onClose} aria-label="Close chat">
          <X className="size-4" />
        </Button>
      </div>

      {/* Messages */}
      <div ref={scrollRef} className="min-h-0 flex-1 overflow-y-auto px-4 py-3 space-y-3">
        {displayMessages.length === 0 && !streamText && (
          <p className="py-8 text-center text-sm text-muted-foreground">
            Send a message to start chatting with your Companion.
          </p>
        )}
        {displayMessages.map((m, i) => (
          <div
            key={i}
            className={`flex ${m.role === "user" ? "justify-end" : "justify-start"}`}
          >
            <div
              className={`max-w-[80%] rounded-lg px-3 py-2 text-sm ${
                m.role === "user"
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted"
              }`}
            >
              {m.role !== "user" ? <Markdown content={m.text} /> : m.text}
            </div>
          </div>
        ))}
        {streamText && (
          <div className="flex justify-start">
            <div className="max-w-[80%] rounded-lg bg-muted px-3 py-2 text-sm">
              <Markdown content={streamText} />
            </div>
          </div>
        )}
        {isBusy && !streamText && (
          <div className="flex justify-start">
            <div className="rounded-lg bg-muted px-3 py-2">
              <LoaderCircle className="size-4 animate-spin text-muted-foreground" />
            </div>
          </div>
        )}
        {error && (
          <p className="rounded border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
            {error}
          </p>
        )}
      </div>

      {/* Composer */}
      <form onSubmit={submit} className="flex items-end gap-2 border-t px-4 py-3">
        <Textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Message ARES…"
          className="min-h-10 max-h-32 resize-none"
          rows={1}
          disabled={isBusy}
        />
        {isBusy ? (
          <Button type="button" variant="ghost" size="icon-sm" onClick={() => void cancelResponse()} aria-label="Cancel">
            <Square className="size-4" />
          </Button>
        ) : (
          <Button type="submit" size="icon-sm" disabled={!draft.trim()}>
            <Send className="size-4" />
          </Button>
        )}
      </form>
    </div>
  );
}

// ── Board Card Component ─────────────────────────────────────────────────

function BoardCardItem({
  card,
  onOpen,
  onMoveLeft,
  onMoveRight,
  onDelete,
  canMoveLeft,
  canMoveRight,
}: {
  card: BoardCard;
  onOpen: () => void;
  onMoveLeft: () => void;
  onMoveRight: () => void;
  onDelete: () => void;
  canMoveLeft: boolean;
  canMoveRight: boolean;
}) {
  const Icon = KIND_ICONS[card.kind];
  const colIdx = COLUMNS.findIndex((c) => c.id === card.column);

  return (
    <div
      className="group relative rounded-lg border bg-card p-3 transition-shadow hover:shadow-md cursor-pointer"
      onClick={onOpen}
    >
      <div className="flex items-start gap-2">
        <Icon className="size-4 mt-0.5 shrink-0 text-muted-foreground" />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium leading-tight truncate">{card.title}</p>
          {card.description && (
            <p className="mt-0.5 text-xs text-muted-foreground line-clamp-2">{card.description}</p>
          )}
        </div>
        <Badge variant="outline" className="shrink-0 text-[10px]">
          {KIND_LABELS[card.kind]}
        </Badge>
      </div>
      {/* Move / delete controls */}
      <div className="mt-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
        {canMoveLeft && (
          <Button variant="ghost" size="icon-sm" className="h-6 w-6" onClick={(e) => { e.stopPropagation(); onMoveLeft(); }} aria-label="Move left">
            <ChevronDown className="size-3 rotate-90" />
          </Button>
        )}
        {canMoveRight && (
          <Button variant="ghost" size="icon-sm" className="h-6 w-6" onClick={(e) => { e.stopPropagation(); onMoveRight(); }} aria-label="Move right">
            <ChevronDown className="size-3 -rotate-90" />
          </Button>
        )}
        <div className="flex-1" />
        <Button variant="ghost" size="icon-sm" className="h-6 w-6 text-muted-foreground hover:text-destructive" onClick={(e) => { e.stopPropagation(); onDelete(); }} aria-label="Delete card">
          <Trash2 className="size-3" />
        </Button>
      </div>
    </div>
  );
}

// ── Add Card Dialog ───────────────────────────────────────────────────────

function AddCardDialog({
  open,
  onOpenChange,
  column,
  onAdd,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  column: ColumnId;
  onAdd: (card: Omit<BoardCard, "id" | "order" | "column" | "createdAt">) => void;
}) {
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [kind, setKind] = useState<CardKind>("task");

  useEffect(() => {
    if (open) { setTitle(""); setDescription(""); setKind("task"); }
  }, [open]);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    onAdd({ kind, title: title.trim(), description: description.trim() || undefined });
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add card to {COLUMNS.find((c) => c.id === column)?.label}</DialogTitle>
          <DialogDescription>Create a new chat session, task, or note on your board.</DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="grid gap-4 py-2">
          <div className="grid gap-2">
            <label className="text-sm font-medium">Type</label>
            <div className="flex gap-2">
              {(["chat", "task", "note"] as CardKind[]).map((k) => {
                const KIcon = KIND_ICONS[k];
                return (
                  <Button
                    key={k}
                    type="button"
                    variant={kind === k ? "default" : "outline"}
                    size="sm"
                    onClick={() => setKind(k)}
                    className="gap-1.5"
                  >
                    <KIcon className="size-3.5" />
                    {KIND_LABELS[k]}
                  </Button>
                );
              })}
            </div>
          </div>
          <div className="grid gap-2">
            <label className="text-sm font-medium">Title</label>
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="rounded-md border bg-transparent px-3 py-2 text-sm outline-none focus:border-ring"
              placeholder="Enter card title…"
              autoFocus
            />
          </div>
          <div className="grid gap-2">
            <label className="text-sm font-medium">Description</label>
            <Textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Optional description…"
              rows={2}
            />
          </div>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button type="submit" disabled={!title.trim()}>Add card</Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ── Main BoardChatPage ────────────────────────────────────────────────────

export function BoardChatPage() {
  const [board, setBoardState, boardStatus] = useProductState<BoardState>("board", { cards: [] });
  const setBoard: Dispatch<SetStateAction<BoardState>> = setBoardState;
  const [activeCard, setActiveCard] = useState<BoardCard | null>(null);
  const [addColumn, setAddColumn] = useState<ColumnId | null>(null);

  const addCard = useCallback((column: ColumnId, input: Omit<BoardCard, "id" | "order" | "column" | "createdAt">) => {
    setBoard((prev) => {
      const existing = prev.cards.filter((c) => c.column === column);
      const card: BoardCard = {
        ...input,
        id: nextId(),
        column,
        order: existing.length,
        createdAt: new Date().toISOString(),
      };
      return { ...prev, cards: [...prev.cards, card] };
    });
  }, []);

  const moveCard = useCallback((cardId: string, targetColumn: ColumnId) => {
    setBoard((prev) => {
      const cards = prev.cards.map((c) => {
        if (c.id !== cardId) return c;
        const existingInTarget = prev.cards.filter((x) => x.column === targetColumn);
        return { ...c, column: targetColumn, order: existingInTarget.length };
      });
      // Re-index order within source column after removal
      const sourceCard = prev.cards.find((c) => c.id === cardId);
      if (!sourceCard) return { ...prev, cards };
      const sourceColumn = sourceCard.column;
      const reindexed = cards
        .filter((c) => c.column === sourceColumn)
        .sort((a, b) => a.order - b.order)
        .map((c, i) => ({ ...c, order: i }));
      const otherColumns = cards.filter((c) => c.column !== sourceColumn);
      return { ...prev, cards: [...otherColumns, ...reindexed] };
    });
  }, []);

  const deleteCard = useCallback((cardId: string) => {
    setBoard((prev) => {
      const cards = prev.cards.filter((c) => c.id !== cardId);
      // Re-index
      for (const col of COLUMNS) {
        let idx = 0;
        for (const c of cards) {
          if (c.column === col.id) { c.order = idx++; }
        }
      }
      return { ...prev, cards };
    });
    if (activeCard?.id === cardId) setActiveCard(null);
  }, [activeCard]);

  const cardsByColumn = useMemo(() => {
    const map: Record<ColumnId, BoardCard[]> = { todo: [], in_progress: [], done: [] };
    for (const c of board.cards) {
      map[c.column]?.push(c);
    }
    for (const col of COLUMNS) {
      map[col.id].sort((a, b) => a.order - b.order);
    }
    return map;
  }, [board.cards]);

  return (
    <div className="page-stack">
      <PageHeader
        title="Board Chat"
        description="Organize chat sessions, tasks, and notes in a kanban board. Open any card to chat with your Companion."
      />

      {boardStatus.error && <p className="text-sm text-destructive" role="alert">{boardStatus.error}</p>}

      {boardStatus.loading ? (
        <div className="grid min-h-64 place-items-center text-sm text-muted-foreground">
          <span className="inline-flex items-center gap-2"><LoaderCircle className="size-4 animate-spin" />Loading board…</span>
        </div>
      ) : (
      <div className="grid gap-4 md:grid-cols-3">
        {COLUMNS.map((col) => (
          <div key={col.id} className="flex flex-col rounded-lg border bg-muted/20">
            {/* Column header */}
            <div className="flex items-center gap-2 px-3 py-2 border-b">
              <div className={`size-2.5 rounded-full ${col.accent}`} />
              <h3 className="text-sm font-semibold">{col.label}</h3>
              <Badge variant="secondary" className="ml-auto text-[10px]">
                {cardsByColumn[col.id].length}
              </Badge>
              <Button
                variant="ghost"
                size="icon-sm"
                className="ml-1"
                onClick={() => setAddColumn(col.id)}
                aria-label={`Add card to ${col.label}`}
              >
                <Plus className="size-3.5" />
              </Button>
            </div>

            {/* Cards */}
            <div className="flex-1 space-y-2 p-3 min-h-[200px]">
              {cardsByColumn[col.id].length === 0 && (
                <EmptyState
                  icon={GripVertical}
                  title="No cards"
                  description="Add a card or move one here."
                />
              )}
              {cardsByColumn[col.id].map((card) => {
                const colIdx = COLUMNS.findIndex((c) => c.id === col.id);
                return (
                  <BoardCardItem
                    key={card.id}
                    card={card}
                    onOpen={() => setActiveCard(card)}
                    onMoveLeft={colIdx > 0 ? () => moveCard(card.id, COLUMNS[colIdx - 1].id) : () => {}}
                    onMoveRight={colIdx < COLUMNS.length - 1 ? () => moveCard(card.id, COLUMNS[colIdx + 1].id) : () => {}}
                    onDelete={() => deleteCard(card.id)}
                    canMoveLeft={colIdx > 0}
                    canMoveRight={colIdx < COLUMNS.length - 1}
                  />
                );
              })}
            </div>
          </div>
        ))}
      </div>
      )}

      {/* ── Add-card dialog ── */}
      {addColumn && (
        <AddCardDialog
          open={addColumn !== null}
          onOpenChange={(open) => { if (!open) setAddColumn(null); }}
          column={addColumn}
          onAdd={(input) => addCard(addColumn, input)}
        />
      )}

      {/* ── Chat dialog ── */}
      {activeCard && (
        <Dialog open={!!activeCard} onOpenChange={(open) => { if (!open) setActiveCard(null); }}>
          <DialogContent className="sm:max-w-2xl h-[70vh] grid-rows-[auto_1fr_auto] p-0">
            <ChatPanel card={activeCard} onClose={() => setActiveCard(null)} />
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}

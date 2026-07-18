import { useState, useCallback, useRef, useEffect } from "react";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  StickyNote,
  Square,
  Trash2,
  Edit3,
  Plus,
  GripVertical,
  X,
  Check,
  Type,
  Palette,
} from "lucide-react";

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

type CanvasItemType = "sticky" | "card";

interface CanvasItem {
  id: string;
  type: CanvasItemType;
  x: number;
  y: number;
  width: number;
  height: number;
  title: string;
  content: string;
  color: string;
  createdAt: number;
}

/* ------------------------------------------------------------------ */
/*  Constants                                                          */
/* ------------------------------------------------------------------ */

const STORAGE_KEY = "ares-canvas-items";

const STICKY_COLORS: Record<string, { bg: string; border: string; header: string }> = {
  yellow: {
    bg: "oklch(0.92 0.06 95)",
    border: "oklch(0.82 0.10 90)",
    header: "oklch(0.85 0.08 92)",
  },
  pink: {
    bg: "oklch(0.90 0.06 340)",
    border: "oklch(0.80 0.10 335)",
    header: "oklch(0.84 0.08 338)",
  },
  blue: {
    bg: "oklch(0.90 0.06 250)",
    border: "oklch(0.80 0.10 245)",
    header: "oklch(0.84 0.08 248)",
  },
  green: {
    bg: "oklch(0.90 0.07 155)",
    border: "oklch(0.80 0.11 150)",
    header: "oklch(0.84 0.09 152)",
  },
  purple: {
    bg: "oklch(0.88 0.07 300)",
    border: "oklch(0.78 0.11 295)",
    header: "oklch(0.82 0.09 298)",
  },
  orange: {
    bg: "oklch(0.90 0.08 70)",
    border: "oklch(0.80 0.12 65)",
    header: "oklch(0.84 0.10 68)",
  },
};

const CARD_COLORS: Record<string, { bg: string; border: string }> = {
  default: {
    bg: "var(--card)",
    border: "var(--border)",
  },
  primary: {
    bg: "oklch(0.22 0.03 252)",
    border: "oklch(0.48 0.15 252)",
  },
  accent: {
    bg: "oklch(0.24 0.04 250)",
    border: "oklch(0.50 0.10 250)",
  },
  muted: {
    bg: "var(--muted)",
    border: "color-mix(in oklab, var(--border) 60%, var(--muted-foreground))",
  },
};

const DEFAULT_STICKY_COLOR = "yellow";
const DEFAULT_CARD_COLOR = "default";

/* ------------------------------------------------------------------ */
/*  Persistence helpers                                                */
/* ------------------------------------------------------------------ */

function loadItems(): CanvasItem[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw) as CanvasItem[];
  } catch {
    /* corrupted – start fresh */
  }
  return defaultItems();
}

function saveItems(items: CanvasItem[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
}

function defaultItems(): CanvasItem[] {
  return [
    {
      id: "welcome-1",
      type: "sticky",
      x: 60,
      y: 40,
      width: 220,
      height: 180,
      title: "💡 Welcome",
      content: "This is your freeform canvas. Drag items around, double-click to edit, or use the toolbar to create new notes and cards.",
      color: "yellow",
      createdAt: Date.now(),
    },
    {
      id: "card-1",
      type: "card",
      x: 340,
      y: 60,
      width: 280,
      height: 160,
      title: "🧠 Synthetic Person",
      content: "Use this space to map out thoughts, plans, and relationships for your synthetic person.",
      color: "default",
      createdAt: Date.now(),
    },
    {
      id: "sticky-2",
      type: "sticky",
      x: 680,
      y: 40,
      width: 200,
      height: 150,
      title: "📌 Quick Notes",
      content: "Sticky notes auto-save to localStorage.",
      color: "blue",
      createdAt: Date.now(),
    },
  ];
}

let _idCounter = 0;
function nextId(): string {
  _idCounter++;
  return `item-${Date.now()}-${_idCounter}`;
}

/* ------------------------------------------------------------------ */
/*  Drag hook                                                          */
/* ------------------------------------------------------------------ */

function useDrag(
  onMove: (dx: number, dy: number) => void,
): { onMouseDown: React.MouseEventHandler; style: undefined } {
  const dragRef = useRef<{
    startX: number;
    startY: number;
  } | null>(null);

  const onMouseDown = useCallback<React.MouseEventHandler>((e) => {
    /* only left button */
    if (e.button !== 0) return;
    e.preventDefault();
    dragRef.current = { startX: e.clientX, startY: e.clientY };

    const handleMove = (ev: MouseEvent) => {
      if (!dragRef.current) return;
      const dx = ev.clientX - dragRef.current.startX;
      const dy = ev.clientY - dragRef.current.startY;
      dragRef.current = { startX: ev.clientX, startY: ev.clientY };
      onMove(dx, dy);
    };

    const handleUp = () => {
      dragRef.current = null;
      window.removeEventListener("mousemove", handleMove);
      window.removeEventListener("mouseup", handleUp);
    };

    window.addEventListener("mousemove", handleMove);
    window.addEventListener("mouseup", handleUp);
  }, [onMove]);

  return { onMouseDown, style: undefined };
}

/* ------------------------------------------------------------------ */
/*  CanvasPannable – scrollable/pannable whiteboard area               */
/* ------------------------------------------------------------------ */

function CanvasPannable({
  children,
  scrollRef,
}: {
  children: React.ReactNode;
  scrollRef: React.RefObject<HTMLDivElement | null>;
}) {
  const [isPanning, setIsPanning] = useState(false);
  const panRef = useRef<{ startX: number; startY: number; scrollLeft: number; scrollTop: number } | null>(null);

  const onMouseDown = useCallback<React.MouseEventHandler>((e) => {
    /* only if clicking on the canvas background itself */
    if ((e.target as HTMLElement).dataset.canvasBg === undefined) return;
    if (e.button !== 0) return;
    setIsPanning(true);
    const el = scrollRef.current;
    if (!el) return;
    panRef.current = {
      startX: e.clientX,
      startY: e.clientY,
      scrollLeft: el.scrollLeft,
      scrollTop: el.scrollTop,
    };
  }, [scrollRef]);

  useEffect(() => {
    if (!isPanning) return;
    const handleMove = (ev: MouseEvent) => {
      const el = scrollRef.current;
      const start = panRef.current;
      if (!el || !start) return;
      el.scrollLeft = start.scrollLeft - (ev.clientX - start.startX);
      el.scrollTop = start.scrollTop - (ev.clientY - start.startY);
    };
    const handleUp = () => {
      setIsPanning(false);
      panRef.current = null;
    };
    window.addEventListener("mousemove", handleMove);
    window.addEventListener("mouseup", handleUp);
    return () => {
      window.removeEventListener("mousemove", handleMove);
      window.removeEventListener("mouseup", handleUp);
    };
  }, [isPanning, scrollRef]);

  return (
    <div
      ref={scrollRef}
      data-canvas-bg
      onMouseDown={onMouseDown}
      className={`flex-1 w-full overflow-auto relative select-none ${isPanning ? "cursor-grabbing" : "cursor-grab"}`}
      style={{
        background:
          "radial-gradient(circle at 1px 1px, color-mix(in oklab, var(--muted-foreground) 12%, transparent) 1px, transparent 0)",
        backgroundSize: "24px 24px",
        backgroundPosition: "0 0",
      }}
    >
      <div
        data-canvas-bg
        className="relative"
        style={{ width: 6000, height: 4000, minWidth: "100%", minHeight: "100%" }}
      >
        {children}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  StickyNoteItem                                                     */
/* ------------------------------------------------------------------ */

function StickyNoteItem({
  item,
  onMove,
  onUpdate,
  onDelete,
  onEdit,
  editing,
}: {
  item: CanvasItem;
  onMove: (dx: number, dy: number) => void;
  onUpdate: (patch: Partial<CanvasItem>) => void;
  onDelete: () => void;
  onEdit: () => void;
  editing: boolean;
}) {
  const palette = STICKY_COLORS[item.color] ?? STICKY_COLORS[DEFAULT_STICKY_COLOR];
  const [editTitle, setEditTitle] = useState(item.title);
  const [editContent, setEditContent] = useState(item.content);
  const drag = useDrag(onMove);

  /* dark-mode overrides for sticky note readability */
  const isDark =
    typeof window !== "undefined" &&
    document.documentElement.classList.contains("dark");

  const darkBg = isDark
    ? `color-mix(in oklab, ${palette.bg} 12%, var(--card))`
    : palette.bg;
  const darkBorder = isDark
    ? `color-mix(in oklab, ${palette.border} 30%, var(--border))`
    : palette.border;
  const darkHeader = isDark
    ? `color-mix(in oklab, ${palette.header} 15%, var(--card))`
    : palette.header;
  const textColor = isDark ? "var(--foreground)" : "oklch(0.20 0.02 60)";

  useEffect(() => {
    setEditTitle(item.title);
    setEditContent(item.content);
  }, [item.title, item.content]);

  const commitEdit = () => {
    onUpdate({ title: editTitle, content: editContent });
    onEdit(); /* toggles off */
  };

  return (
    <div
      className="group absolute rounded-lg shadow-lg transition-shadow hover:shadow-xl"
      style={{
        left: item.x,
        top: item.y,
        width: item.width,
        minHeight: item.height,
        background: darkBg,
        border: `2px solid ${darkBorder}`,
        color: textColor,
      }}
    >
      {/* ---- drag handle + actions ---- */}
      <div
        {...drag}
        className="flex items-center gap-1 px-2 py-1 rounded-t-lg cursor-grab active:cursor-grabbing"
        style={{ background: darkHeader }}
      >
        <GripVertical className="size-3.5 shrink-0 opacity-40" />
        <span className="flex-1 truncate text-xs font-semibold select-none">
          {editing ? null : item.title}
        </span>
        <div className="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
          <Button
            variant="ghost"
            size="icon-xs"
            onClick={(e) => {
              e.stopPropagation();
              onEdit();
            }}
            aria-label="Edit note"
          >
            <Edit3 className="size-3" />
          </Button>
          <Button
            variant="ghost"
            size="icon-xs"
            onClick={(e) => {
              e.stopPropagation();
              onDelete();
            }}
            aria-label="Delete note"
          >
            <Trash2 className="size-3" />
          </Button>
        </div>
      </div>

      {/* ---- body ---- */}
      {editing ? (
        <div className="p-2 flex flex-col gap-1.5">
          <Input
            value={editTitle}
            onChange={(e) => setEditTitle(e.target.value)}
            className="h-7 text-xs font-semibold"
            style={{ background: darkHeader, color: textColor, borderColor: darkBorder }}
            autoFocus
            onKeyDown={(e) => {
              if (e.key === "Enter") commitEdit();
              if (e.key === "Escape") onEdit();
            }}
          />
          <Textarea
            value={editContent}
            onChange={(e) => setEditContent(e.target.value)}
            className="text-xs min-h-[5rem]"
            style={{ background: darkBg, color: textColor, borderColor: darkBorder }}
            onKeyDown={(e) => {
              if (e.key === "Escape") onEdit();
            }}
          />
          <div className="flex justify-end gap-1">
            <Button variant="ghost" size="xs" onClick={onEdit}>
              <X className="size-3" />
            </Button>
            <Button variant="default" size="xs" onClick={commitEdit}>
              <Check className="size-3" />
            </Button>
          </div>
        </div>
      ) : (
        <div
          className="px-2.5 pb-2 pt-1 text-xs whitespace-pre-wrap leading-relaxed select-text"
          onDoubleClick={(e) => {
            e.stopPropagation();
            onEdit();
          }}
        >
          {item.content}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  CardItem                                                           */
/* ------------------------------------------------------------------ */

function CardItem({
  item,
  onMove,
  onUpdate,
  onDelete,
  onEdit,
  editing,
}: {
  item: CanvasItem;
  onMove: (dx: number, dy: number) => void;
  onUpdate: (patch: Partial<CanvasItem>) => void;
  onDelete: () => void;
  onEdit: () => void;
  editing: boolean;
}) {
  const palette = CARD_COLORS[item.color] ?? CARD_COLORS[DEFAULT_CARD_COLOR];
  const [editTitle, setEditTitle] = useState(item.title);
  const [editContent, setEditContent] = useState(item.content);
  const drag = useDrag(onMove);

  useEffect(() => {
    setEditTitle(item.title);
    setEditContent(item.content);
  }, [item.title, item.content]);

  const commitEdit = () => {
    onUpdate({ title: editTitle, content: editContent });
    onEdit();
  };

  return (
    <div
      className="group absolute rounded-lg shadow-md border-2 transition-shadow hover:shadow-lg"
      style={{
        left: item.x,
        top: item.y,
        width: item.width,
        minHeight: item.height,
        background: palette.bg,
        borderColor: palette.border,
        color: "var(--foreground)",
      }}
    >
      {/* ---- drag handle + actions ---- */}
      <div
        {...drag}
        className="flex items-center gap-1.5 px-2 py-1.5 border-b cursor-grab active:cursor-grabbing"
        style={{ borderColor: palette.border }}
      >
        <GripVertical className="size-3.5 shrink-0 opacity-40" />
        <span className="flex-1 truncate text-sm font-semibold select-none">
          {editing ? null : item.title}
        </span>
        <div className="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
          <Button
            variant="ghost"
            size="icon-xs"
            onClick={(e) => {
              e.stopPropagation();
              onEdit();
            }}
            aria-label="Edit card"
          >
            <Edit3 className="size-3" />
          </Button>
          <Button
            variant="ghost"
            size="icon-xs"
            onClick={(e) => {
              e.stopPropagation();
              onDelete();
            }}
            aria-label="Delete card"
          >
            <Trash2 className="size-3" />
          </Button>
        </div>
      </div>

      {/* ---- body ---- */}
      {editing ? (
        <div className="p-3 flex flex-col gap-2">
          <Input
            value={editTitle}
            onChange={(e) => setEditTitle(e.target.value)}
            className="h-8 text-sm font-semibold"
            autoFocus
            onKeyDown={(e) => {
              if (e.key === "Enter") commitEdit();
              if (e.key === "Escape") onEdit();
            }}
          />
          <Textarea
            value={editContent}
            onChange={(e) => setEditContent(e.target.value)}
            className="text-sm min-h-[6rem]"
            onKeyDown={(e) => {
              if (e.key === "Escape") onEdit();
            }}
          />
          <div className="flex justify-end gap-1">
            <Button variant="ghost" size="xs" onClick={onEdit}>
              <X className="size-3" />
            </Button>
            <Button variant="default" size="xs" onClick={commitEdit}>
              <Check className="size-3" />
            </Button>
          </div>
        </div>
      ) : (
        <div
          className="px-3 pb-3 pt-2 text-sm whitespace-pre-wrap leading-relaxed select-text"
          onDoubleClick={(e) => {
            e.stopPropagation();
            onEdit();
          }}
        >
          {item.content}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  ColorPickerPopover                                                 */
/* ------------------------------------------------------------------ */

function ColorPickerPopover({
  colors,
  current,
  onSelect,
  anchorRef,
  onClose,
}: {
  colors: string[];
  current: string;
  onSelect: (c: string) => void;
  anchorRef: React.RefObject<HTMLButtonElement | null>;
  onClose: () => void;
}) {
  return (
    <div
      className="absolute z-50 mt-1 flex gap-1 rounded-md border bg-popover p-2 shadow-md"
      style={{ top: "100%", left: 0 }}
    >
      {colors.map((c) => (
        <button
          key={c}
          onClick={() => {
            onSelect(c);
            onClose();
          }}
          className={`size-6 rounded-full border-2 transition-transform hover:scale-110 ${
            c === current ? "ring-2 ring-ring scale-110" : ""
          }`}
          style={{
            background:
              STICKY_COLORS[c]?.bg ?? CARD_COLORS[c]?.bg ?? "var(--muted)",
            borderColor:
              STICKY_COLORS[c]?.border ?? CARD_COLORS[c]?.border ?? "var(--border)",
          }}
          aria-label={`Color ${c}`}
        />
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  CanvasPage                                                         */
/* ------------------------------------------------------------------ */

export function CanvasPage() {
  const [items, setItems] = useState<CanvasItem[]>(loadItems);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [addType, setAddType] = useState<CanvasItemType | null>(null);
  const [newTitle, setNewTitle] = useState("");
  const [newContent, setNewContent] = useState("");
  const [newColor, setNewColor] = useState(DEFAULT_STICKY_COLOR);
  const [showColorPicker, setShowColorPicker] = useState(false);
  const colorBtnRef = useRef<HTMLButtonElement>(null);
  const scrollRef = useRef<HTMLDivElement | null>(null);

  /* persist on every change */
  useEffect(() => {
    saveItems(items);
  }, [items]);

  /* ---- CRUD ---- */

  const updateItem = useCallback(
    (id: string, patch: Partial<CanvasItem>) =>
      setItems((prev) => prev.map((it) => (it.id === id ? { ...it, ...patch } : it))),
    [],
  );

  const deleteItem = useCallback(
    (id: string) => setItems((prev) => prev.filter((it) => it.id !== id)),
    [],
  );

  const moveItem = useCallback(
    (id: string, dx: number, dy: number) =>
      setItems((prev) =>
        prev.map((it) => (it.id === id ? { ...it, x: it.x + dx, y: it.y + dy } : it)),
      ),
    [],
  );

  const startAdd = useCallback((type: CanvasItemType) => {
    setAddType(type);
    setNewTitle(type === "sticky" ? "📝 New Note" : "📋 New Card");
    setNewContent("");
    setNewColor(type === "sticky" ? DEFAULT_STICKY_COLOR : DEFAULT_CARD_COLOR);
  }, []);

  const commitAdd = useCallback(() => {
    if (!addType) return;
    const scrollEl = scrollRef.current;
    /* place near the current scroll position + offset */
    const offsetX = scrollEl ? scrollEl.scrollLeft + 80 : 80;
    const offsetY = scrollEl ? scrollEl.scrollTop + 60 : 60;
    const item: CanvasItem = {
      id: nextId(),
      type: addType,
      x: offsetX + Math.round(Math.random() * 40),
      y: offsetY + Math.round(Math.random() * 40),
      width: addType === "sticky" ? 220 : 280,
      height: addType === "sticky" ? 180 : 160,
      title: newTitle || (addType === "sticky" ? "📝 Note" : "📋 Card"),
      content: newContent,
      color: newColor,
      createdAt: Date.now(),
    };
    setItems((prev) => [...prev, item]);
    setAddType(null);
    setNewTitle("");
    setNewContent("");
  }, [addType, newTitle, newContent, newColor]);

  const clearAll = useCallback(() => {
    if (window.confirm("Clear all items from the canvas? This cannot be undone.")) {
      setItems([]);
    }
  }, []);

  const resetToDefaults = useCallback(() => {
    setItems(defaultItems());
  }, []);

  /* ---- render ---- */

  const colorOptions = addType === "sticky" ? Object.keys(STICKY_COLORS) : Object.keys(CARD_COLORS);

  return (
    <div className="flex h-full flex-col">
      <PageHeader
        title="Canvas & Synthetic Person"
        description="Freeform workspace — sticky notes, cards, and whiteboard for the synthetic person. Drag to rearrange, double-click to edit."
        action={
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={startAdd.bind(null, "sticky")}>
              <StickyNote className="size-4" />
              <span className="hidden sm:inline">Note</span>
            </Button>
            <Button variant="outline" size="sm" onClick={startAdd.bind(null, "card")}>
              <Square className="size-4" />
              <span className="hidden sm:inline">Card</span>
            </Button>
            <Button variant="ghost" size="sm" onClick={resetToDefaults}>
              Reset
            </Button>
            <Button variant="ghost" size="sm" className="text-destructive" onClick={clearAll}>
              <Trash2 className="size-4" />
            </Button>
          </div>
        }
      />

      {/* ---- Add-item bar ---- */}
      {addType && (
        <div className="mx-4 mb-2 flex flex-wrap items-center gap-2 rounded-md border bg-card p-3 shadow-sm">
          <Type className="size-4 text-muted-foreground" />
          <Input
            value={newTitle}
            onChange={(e) => setNewTitle(e.target.value)}
            placeholder="Title"
            className="h-8 w-48 text-sm"
            autoFocus
            onKeyDown={(e) => {
              if (e.key === "Enter") commitAdd();
              if (e.key === "Escape") setAddType(null);
            }}
          />
          <Textarea
            value={newContent}
            onChange={(e) => setNewContent(e.target.value)}
            placeholder="Content (optional)"
            className="min-h-[2rem] w-64 text-sm"
            onKeyDown={(e) => {
              if (e.key === "Escape") setAddType(null);
            }}
          />
          <div className="relative">
            <Button
              ref={colorBtnRef}
              variant="outline"
              size="icon-sm"
              onClick={() => setShowColorPicker((v) => !v)}
              aria-label="Pick color"
            >
              <Palette className="size-4" />
            </Button>
            {showColorPicker && (
              <ColorPickerPopover
                colors={colorOptions}
                current={newColor}
                onSelect={setNewColor}
                anchorRef={colorBtnRef}
                onClose={() => setShowColorPicker(false)}
              />
            )}
          </div>
          <Button size="sm" onClick={commitAdd}>
            <Plus className="size-4" />
            Add
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setAddType(null)}>
            Cancel
          </Button>
        </div>
      )}

      {/* ---- Canvas area ---- */}
      <CanvasPannable scrollRef={scrollRef}>
        {items.map((item) =>
          item.type === "sticky" ? (
            <StickyNoteItem
              key={item.id}
              item={item}
              onMove={(dx, dy) => moveItem(item.id, dx, dy)}
              onUpdate={(patch) => updateItem(item.id, patch)}
              onDelete={() => deleteItem(item.id)}
              onEdit={() =>
                setEditingId((prev) => (prev === item.id ? null : item.id))
              }
              editing={editingId === item.id}
            />
          ) : (
            <CardItem
              key={item.id}
              item={item}
              onMove={(dx, dy) => moveItem(item.id, dx, dy)}
              onUpdate={(patch) => updateItem(item.id, patch)}
              onDelete={() => deleteItem(item.id)}
              onEdit={() =>
                setEditingId((prev) => (prev === item.id ? null : item.id))
              }
              editing={editingId === item.id}
            />
          ),
        )}
      </CanvasPannable>
    </div>
  );
}
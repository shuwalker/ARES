import {
  ChevronDown,
  LoaderCircle,
  Plus,
  RefreshCw,
  Trash2,
} from "lucide-react";
import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type FormEvent,
} from "react";

import { EmptyState } from "@/components/EmptyState";
import { PageHeader } from "@/components/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { readableError } from "@/shared/api-client";
import {
  aresApi,
  type KanbanBoardMeta,
  type KanbanTask,
} from "@/shared/ares-api";

// Matches api.kanban_bridge.BOARD_COLUMNS
const BOARD_COLUMNS = ["triage", "todo", "ready", "running", "blocked", "done"] as const;
type ColumnId = (typeof BOARD_COLUMNS)[number];

const COLUMN_META: Record<ColumnId, { label: string; accent: string }> = {
  triage: { label: "Triage", accent: "bg-muted-foreground/30" },
  todo: { label: "To Do", accent: "bg-muted-foreground/20" },
  ready: { label: "Ready", accent: "bg-sky-500/60" },
  running: { label: "Running", accent: "bg-primary/60" },
  blocked: { label: "Blocked", accent: "bg-amber-500/60" },
  done: { label: "Done", accent: "bg-status-available/60" },
};

function columnLabel(status: string): string {
  return COLUMN_META[status as ColumnId]?.label ?? status;
}

function TaskCard({
  task,
  onOpen,
  onMoveLeft,
  onMoveRight,
  onArchive,
  canMoveLeft,
  canMoveRight,
  busy,
}: {
  task: KanbanTask;
  onOpen: () => void;
  onMoveLeft: () => void;
  onMoveRight: () => void;
  onArchive: () => void;
  canMoveLeft: boolean;
  canMoveRight: boolean;
  busy: boolean;
}) {
  return (
    <div
      className="group relative cursor-pointer rounded-lg border bg-card p-3 transition-shadow hover:shadow-md"
      onClick={onOpen}
    >
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium leading-tight">{task.title}</p>
          {task.body ? (
            <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{String(task.body)}</p>
          ) : null}
        </div>
        {typeof task.priority === "number" && task.priority > 0 ? (
          <Badge variant="outline" className="shrink-0 text-[10px]">
            P{task.priority}
          </Badge>
        ) : null}
      </div>
      <div className="mt-2 flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100">
        {canMoveLeft ? (
          <Button
            variant="ghost"
            size="icon-sm"
            className="h-6 w-6"
            disabled={busy}
            onClick={(event) => {
              event.stopPropagation();
              onMoveLeft();
            }}
            aria-label="Move left"
          >
            <ChevronDown className="size-3 rotate-90" />
          </Button>
        ) : null}
        {canMoveRight ? (
          <Button
            variant="ghost"
            size="icon-sm"
            className="h-6 w-6"
            disabled={busy}
            onClick={(event) => {
              event.stopPropagation();
              onMoveRight();
            }}
            aria-label="Move right"
          >
            <ChevronDown className="size-3 -rotate-90" />
          </Button>
        ) : null}
        <div className="flex-1" />
        <Button
          variant="ghost"
          size="icon-sm"
          className="h-6 w-6 text-muted-foreground hover:text-destructive"
          disabled={busy}
          onClick={(event) => {
            event.stopPropagation();
            onArchive();
          }}
          aria-label="Archive task"
        >
          <Trash2 className="size-3" />
        </Button>
      </div>
    </div>
  );
}

function AddTaskDialog({
  open,
  onOpenChange,
  column,
  onAdd,
  busy,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  column: ColumnId;
  onAdd: (input: { title: string; body?: string }) => Promise<void>;
  busy: boolean;
}) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");

  useEffect(() => {
    if (open) {
      setTitle("");
      setBody("");
    }
  }, [open]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!title.trim() || busy) return;
    await onAdd({ title: title.trim(), body: body.trim() || undefined });
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add task to {columnLabel(column)}</DialogTitle>
          <DialogDescription>
            Create a task on the shared ARES kanban board (persisted via /api/kanban).
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={(event) => void submit(event)} className="grid gap-4 py-2">
          <div className="grid gap-2">
            <label className="text-sm font-medium">Title</label>
            <input
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              className="rounded-md border bg-transparent px-3 py-2 text-sm outline-none focus:border-ring"
              placeholder="Enter task title…"
              autoFocus
            />
          </div>
          <div className="grid gap-2">
            <label className="text-sm font-medium">Description</label>
            <Textarea
              value={body}
              onChange={(event) => setBody(event.target.value)}
              placeholder="Optional description…"
              rows={2}
            />
          </div>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={!title.trim() || busy}>
              {busy ? <LoaderCircle className="size-4 animate-spin" /> : null}
              Add task
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function TaskDetailDialog({
  task,
  open,
  onOpenChange,
}: {
  task: KanbanTask | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  if (!task) return null;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{task.title}</DialogTitle>
          <DialogDescription>
            Status: {columnLabel(task.status)}
            {task.assignee ? ` · Assignee: ${task.assignee}` : ""}
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3 text-sm">
          {task.body ? (
            <p className="whitespace-pre-wrap text-muted-foreground">{String(task.body)}</p>
          ) : (
            <p className="text-muted-foreground">No description.</p>
          )}
          <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
            {typeof task.priority === "number" ? <Badge variant="outline">Priority {task.priority}</Badge> : null}
            {task.tenant ? <Badge variant="secondary">{String(task.tenant)}</Badge> : null}
            {typeof task.comment_count === "number" && task.comment_count > 0 ? (
              <Badge variant="outline">{task.comment_count} comments</Badge>
            ) : null}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

export function BoardChatPage() {
  const [boards, setBoards] = useState<KanbanBoardMeta[]>([]);
  const [currentBoard, setCurrentBoard] = useState<string>("");
  const [tasksByColumn, setTasksByColumn] = useState<Record<string, KanbanTask[]>>({});
  const [loading, setLoading] = useState(true);
  const [mutating, setMutating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [unavailable, setUnavailable] = useState(false);
  const [addColumn, setAddColumn] = useState<ColumnId | null>(null);
  const [activeTask, setActiveTask] = useState<KanbanTask | null>(null);
  const [readOnly, setReadOnly] = useState(false);

  const loadBoard = useCallback(async (boardSlug?: string) => {
    setLoading(true);
    setError(null);
    setUnavailable(false);
    try {
      const listed = await aresApi.kanbanBoards();
      const boardList: KanbanBoardMeta[] = Array.isArray(listed.boards)
        ? listed.boards
        : Array.isArray(listed)
          ? (listed as KanbanBoardMeta[])
          : [];
      setBoards(boardList);

      const preferred =
        boardSlug
        || (typeof listed.current === "string" ? listed.current : "")
        || boardList.find((board) => board.is_current)?.slug
        || boardList[0]?.slug
        || "default";
      setCurrentBoard(preferred);

      const payload = await aresApi.kanbanBoard(preferred);
      setReadOnly(Boolean(payload.read_only));
      const next: Record<string, KanbanTask[]> = {};
      for (const column of BOARD_COLUMNS) next[column] = [];
      for (const column of payload.columns ?? []) {
        const name = String(column.name || "").toLowerCase();
        next[name] = Array.isArray(column.tasks) ? column.tasks : [];
      }
      setTasksByColumn(next);
    } catch (reason) {
      const message = readableError(reason, "Could not load kanban board.");
      setError(message);
      // 503 from missing ares_cli.kanban_db is an honest unavailable state.
      if (/503|unavailable|kanban/i.test(message)) {
        setUnavailable(true);
      }
      setTasksByColumn({});
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadBoard();
  }, [loadBoard]);

  const totalTasks = useMemo(
    () => Object.values(tasksByColumn).reduce((sum, tasks) => sum + tasks.length, 0),
    [tasksByColumn],
  );

  const createTask = useCallback(
    async (column: ColumnId, input: { title: string; body?: string }) => {
      setMutating(true);
      setError(null);
      try {
        await aresApi.kanbanCreateTask({
          title: input.title,
          body: input.body,
          status: column,
          board: currentBoard || undefined,
        });
        await loadBoard(currentBoard);
      } catch (reason) {
        setError(readableError(reason, "Could not create task."));
      } finally {
        setMutating(false);
      }
    },
    [currentBoard, loadBoard],
  );

  const moveTask = useCallback(
    async (task: KanbanTask, target: ColumnId) => {
      if (task.status === target || readOnly) return;
      setMutating(true);
      setError(null);
      try {
        await aresApi.kanbanPatchTask(task.id, { status: target }, currentBoard || undefined);
        await loadBoard(currentBoard);
      } catch (reason) {
        setError(readableError(reason, "Could not move task."));
      } finally {
        setMutating(false);
      }
    },
    [currentBoard, loadBoard, readOnly],
  );

  const archiveTask = useCallback(
    async (task: KanbanTask) => {
      if (readOnly) return;
      if (!confirm(`Archive task “${task.title}”?`)) return;
      setMutating(true);
      setError(null);
      try {
        await aresApi.kanbanPatchTask(task.id, { status: "archived" }, currentBoard || undefined);
        if (activeTask?.id === task.id) setActiveTask(null);
        await loadBoard(currentBoard);
      } catch (reason) {
        setError(readableError(reason, "Could not archive task."));
      } finally {
        setMutating(false);
      }
    },
    [activeTask, currentBoard, loadBoard, readOnly],
  );

  return (
    <div className="page-stack">
      <PageHeader
        title="Board"
        description="Shared kanban board backed by /api/kanban. Move tasks across triage → done, or archive them."
        action={
          <div className="flex items-center gap-2">
            {boards.length > 1 ? (
              <select
                className="rounded-md border bg-background px-2 py-1.5 text-sm"
                value={currentBoard}
                onChange={(event) => void loadBoard(event.target.value)}
                disabled={loading}
              >
                {boards.map((board) => (
                  <option key={board.slug} value={board.slug}>
                    {board.name || board.title || board.slug}
                  </option>
                ))}
              </select>
            ) : null}
            <Button size="sm" variant="outline" onClick={() => void loadBoard(currentBoard)} disabled={loading}>
              <RefreshCw className={loading ? "animate-spin" : ""} />
              Refresh
            </Button>
          </div>
        }
      />

      {error ? (
        <p className="text-sm text-destructive" role="alert">
          {error}
        </p>
      ) : null}

      {loading ? (
        <div className="grid min-h-64 place-items-center text-sm text-muted-foreground">
          <span className="inline-flex items-center gap-2">
            <LoaderCircle className="size-4 animate-spin" />
            Loading board…
          </span>
        </div>
      ) : unavailable ? (
        <EmptyState
          icon={Plus}
          title="Kanban unavailable"
          description="The kanban data service is not installed or not reachable. Install the ARES agent kanban package, then refresh."
        />
      ) : (
        <>
          <p className="text-xs text-muted-foreground">
            {totalTasks} task{totalTasks === 1 ? "" : "s"}
            {currentBoard ? ` on board “${currentBoard}”` : ""}
            {readOnly ? " · read-only" : ""}
          </p>
          <div className="grid gap-3 overflow-x-auto pb-2 xl:grid-cols-6 md:grid-cols-3">
            {BOARD_COLUMNS.map((columnId) => {
              const colIdx = BOARD_COLUMNS.indexOf(columnId);
              const tasks = tasksByColumn[columnId] ?? [];
              return (
                <div key={columnId} className="flex min-w-[180px] flex-col rounded-lg border bg-muted/20">
                  <div className="flex items-center gap-2 border-b px-3 py-2">
                    <div className={`size-2.5 rounded-full ${COLUMN_META[columnId].accent}`} />
                    <h3 className="text-sm font-semibold">{COLUMN_META[columnId].label}</h3>
                    <Badge variant="secondary" className="ml-auto text-[10px]">
                      {tasks.length}
                    </Badge>
                    {!readOnly ? (
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="ml-1"
                        onClick={() => setAddColumn(columnId)}
                        aria-label={`Add task to ${COLUMN_META[columnId].label}`}
                      >
                        <Plus className="size-3.5" />
                      </Button>
                    ) : null}
                  </div>
                  <div className="min-h-[200px] flex-1 space-y-2 p-3">
                    {tasks.length === 0 ? (
                      <EmptyState
                        icon={Plus}
                        title="No tasks"
                        description="Add a task or move one here."
                      />
                    ) : null}
                    {tasks.map((task) => (
                      <TaskCard
                        key={task.id}
                        task={task}
                        busy={mutating}
                        canMoveLeft={colIdx > 0 && !readOnly}
                        canMoveRight={colIdx < BOARD_COLUMNS.length - 1 && !readOnly}
                        onOpen={() => setActiveTask(task)}
                        onMoveLeft={() => void moveTask(task, BOARD_COLUMNS[colIdx - 1])}
                        onMoveRight={() => void moveTask(task, BOARD_COLUMNS[colIdx + 1])}
                        onArchive={() => void archiveTask(task)}
                      />
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}

      {addColumn ? (
        <AddTaskDialog
          open={addColumn !== null}
          onOpenChange={(open) => {
            if (!open) setAddColumn(null);
          }}
          column={addColumn}
          busy={mutating}
          onAdd={(input) => createTask(addColumn, input)}
        />
      ) : null}

      <TaskDetailDialog
        task={activeTask}
        open={!!activeTask}
        onOpenChange={(open) => {
          if (!open) setActiveTask(null);
        }}
      />
    </div>
  );
}

import { and, asc, desc, eq, inArray, isNotNull, isNull, ne, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import type { Db } from "@paperclipai/db";
import {
  agents,
  issues,
  workflowLifeAdminEvents,
  workflowLifeAdminIssueLinks,
  workflowLifeAdmin,
  workflowStages,
  workflows,
  routines,
} from "@paperclipai/db";
import { notFound } from "../errors.js";
import { visibleIssueCondition } from "./issue-visibility.js";

export const WORKFLOW_ATTENTION_DEFAULT_LIMIT = 50;
export const WORKFLOW_ATTENTION_MAX_LIMIT = 100;
export const DOMAIN_LIFE_ADMIN_EVENTS_DEFAULT_LIMIT = 50;
export const DOMAIN_LIFE_ADMIN_EVENTS_MAX_LIMIT = 100;
export const DOMAIN_LIFE_ADMIN_EVENTS_MAX_TYPES = 10;
export const LIFE_ADMIN_CHILDREN_TREE_MAX_NODES = 1_000;
export const LIFE_ADMIN_CHILDREN_TREE_MAX_DEPTH = 10;

export type AttentionCaller =
  | { type: "user"; userId: string }
  | { type: "agent"; agentId: string };

type LifeAdminRow = typeof workflowLifeAdmin.$inferSelect;
type StageRow = typeof workflowStages.$inferSelect;
type WorkflowRow = typeof workflows.$inferSelect;

export type ActiveWork = {
  issueId: string;
  issueIdentifier: string | null;
  issueTitle: string;
  issueRole: "work" | "automation";
  agentId: string;
  agentName: string;
  startedAt: Date | null;
};

function life_adminDisplay(row: { life_admin: LifeAdminRow; stage: StageRow; workflow: WorkflowRow }) {
  return {
    id: row.life_admin.id,
    life_adminKey: row.life_admin.life_adminKey,
    title: row.life_admin.title,
    summary: row.life_admin.summary,
    version: row.life_admin.version,
    terminalKind: row.life_admin.terminalKind,
    parentLifeAdminId: row.life_admin.parentLifeAdminId,
    updatedAt: row.life_admin.updatedAt,
    createdAt: row.life_admin.createdAt,
    workflow: { id: row.workflow.id, key: row.workflow.key, name: row.workflow.name },
    stage: { id: row.stage.id, key: row.stage.key, name: row.stage.name, kind: row.stage.kind },
  };
}

// Review-stage approver semantics (B1 model): requireApproval=false awaits
// anyone; requireApproval=true awaits the configured approver (any_human,
// user, or a specific agent). Legacy rows may still store reviewerKind
// ("human"/"any") instead — honor it when present.
// SQL-side so busy domains can't truncate an agent's review feed.
function reviewStageAwaitsCallerSql(caller: AttentionCaller) {
  if (caller.type === "user") return sql`true`;
  return sql`(
    coalesce(${workflowStages.config}->>'reviewerKind', '') = 'any'
    or (
      coalesce(${workflowStages.config}->>'reviewerKind', '') <> 'human'
      and (
        coalesce((${workflowStages.config}->>'requireApproval')::boolean, false) = false
        or (
          ${workflowStages.config}->'approver'->>'kind' = 'agent'
          and ${workflowStages.config}->'approver'->>'id' = ${caller.agentId}
        )
      )
    )
  )`;
}

function boundedLimit(limit: number | undefined, fallback: number, max: number) {
  return Math.min(max, Math.max(1, Math.floor(limit ?? fallback)));
}

function payloadString(value: unknown, key: string) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = (value as Record<string, unknown>)[key];
  return typeof raw === "string" && raw.trim().length > 0 ? raw.trim() : null;
}

function stageAutomationFromConfig(stage: typeof workflowStages.$inferSelect) {
  const config = stage.config && typeof stage.config === "object" && !Array.isArray(stage.config)
    ? stage.config as Record<string, unknown>
    : {};
  const onEnter = config.onEnter && typeof config.onEnter === "object" && !Array.isArray(config.onEnter)
    ? config.onEnter as Record<string, unknown>
    : null;
  if (onEnter?.type !== "run_routine" || typeof onEnter.routineId !== "string" || !onEnter.routineId.trim()) {
    return null;
  }
  return {
    id: typeof onEnter.id === "string" && onEnter.id.trim() ? onEnter.id.trim() : `${stage.id}:on_enter`,
    routineId: onEnter.routineId.trim(),
  };
}

export async function listWorkflowAttention(
  db: Db,
  input: { domainId: string; caller: AttentionCaller; limit?: number },
) {
  const limit = boundedLimit(input.limit, WORKFLOW_ATTENTION_DEFAULT_LIMIT, WORKFLOW_ATTENTION_MAX_LIMIT);

  const suggestionAgent = alias(agents, "suggestion_agent");
  const suggestionToStage = alias(workflowStages, "suggestion_to_stage");
  const suggestionRows = await db
    .select({
      life_admin: workflowLifeAdmin,
      workflow: workflows,
      stage: workflowStages,
      toStage: suggestionToStage,
      suggestingAgent: { id: suggestionAgent.id, name: suggestionAgent.name },
    })
    .from(workflowLifeAdmin)
    .innerJoin(workflows, eq(workflowLifeAdmin.workflowId, workflows.id))
    .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
    .leftJoin(suggestionToStage, and(
      eq(suggestionToStage.workflowId, workflowLifeAdmin.workflowId),
      eq(suggestionToStage.key, sql`${workflowLifeAdmin.pendingSuggestion}->>'toStageKey'`),
    ))
    .leftJoin(suggestionAgent, sql`${suggestionAgent.id}::text = ${workflowLifeAdmin.pendingSuggestion}->>'suggestedByAgentId'`)
    .where(and(
      eq(workflowLifeAdmin.domainId, input.domainId),
      eq(workflows.domainId, input.domainId),
      isNull(workflowLifeAdmin.terminalKind),
      isNotNull(workflowLifeAdmin.pendingSuggestion),
    ))
    .orderBy(desc(workflowLifeAdmin.updatedAt))
    .limit(limit);

  const suggestions = suggestionRows.map((row) => {
    const suggestion = row.life_admin.pendingSuggestion!;
    return {
      life_admin: life_adminDisplay(row),
      suggestion: {
        id: suggestion.id,
        fromStageKey: row.stage.key,
        fromStageName: row.stage.name,
        toStageKey: suggestion.toStageKey,
        toStageName: row.toStage?.name ?? null,
        rationale: suggestion.rationale,
        confidence: suggestion.confidence ?? null,
        createdAt: suggestion.createdAt,
        suggestedBy: row.suggestingAgent?.id
          ? { agentId: row.suggestingAgent.id, agentName: row.suggestingAgent.name }
          : null,
      },
    };
  });

  const reviewRows = await db
    .select({ life_admin: workflowLifeAdmin, workflow: workflows, stage: workflowStages })
    .from(workflowLifeAdmin)
    .innerJoin(workflows, eq(workflowLifeAdmin.workflowId, workflows.id))
    .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
    .where(and(
      eq(workflowLifeAdmin.domainId, input.domainId),
      eq(workflows.domainId, input.domainId),
      eq(workflowStages.kind, "review"),
      isNull(workflowLifeAdmin.terminalKind),
      reviewStageAwaitsCallerSql(input.caller),
    ))
    .orderBy(asc(workflowLifeAdmin.createdAt))
    .limit(limit);

  const reviews = reviewRows
    .map((row) => {
      const config = (row.stage.config ?? {}) as Record<string, unknown>;
      return {
        life_admin: life_adminDisplay(row),
        review: {
          expectedVersion: row.life_admin.version,
          approveToStageKey: typeof config.approveToStageKey === "string" ? config.approveToStageKey : null,
          rejectToStageKey: typeof config.rejectToStageKey === "string" ? config.rejectToStageKey : null,
          requestChangesToStageKey: typeof config.requestChangesToStageKey === "string" ? config.requestChangesToStageKey : null,
          requireRejectReason: config.requireRejectReason !== false,
          requireRequestChangesReason: config.requireRequestChangesReason !== false,
          reviewerKind:
            typeof config.reviewerKind === "string"
              ? config.reviewerKind
              : config.requireApproval === false
                ? "any"
                : "human",
        },
      };
    });

  const driftRows = await db
    .selectDistinctOn([workflowLifeAdminEvents.lifeAdminId], {
      event: workflowLifeAdminEvents,
      life_admin: workflowLifeAdmin,
      workflow: workflows,
      stage: workflowStages,
    })
    .from(workflowLifeAdminEvents)
    .innerJoin(workflowLifeAdmin, eq(workflowLifeAdminEvents.lifeAdminId, workflowLifeAdmin.id))
    .innerJoin(workflows, eq(workflowLifeAdmin.workflowId, workflows.id))
    .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
    .where(and(
      eq(workflowLifeAdminEvents.domainId, input.domainId),
      eq(workflowLifeAdminEvents.type, "upstream_drift"),
      eq(workflowLifeAdmin.domainId, input.domainId),
      isNull(workflowLifeAdmin.terminalKind),
      sql`not exists (
        select 1
        from workflow_life_admin_events ack
        where ack.domain_id = ${workflowLifeAdminEvents.domainId}
          and ack.life_admin_id = ${workflowLifeAdminEvents.lifeAdminId}
          and ack.type = 'drift_acknowledged'
          and ack.created_at > ${workflowLifeAdminEvents.createdAt}
      )`,
    ))
    .orderBy(asc(workflowLifeAdminEvents.lifeAdminId), desc(workflowLifeAdminEvents.createdAt))
    .limit(limit);

  const driftLifeAdminIds = driftRows.map((row) => row.life_admin.id);
  const upstreamLifeAdminIds = [...new Set(driftRows
    .map((row) => (row.event.payload as Record<string, unknown>).upstreamLifeAdminId)
    .filter((value): value is string => typeof value === "string"))];

  const [activeWorkByLifeAdmin, workIssuesByLifeAdmin, upstreamLifeAdmin] = await Promise.all([
    loadActiveWorkForLifeAdmin(db, input.domainId, driftLifeAdminIds),
    loadOpenWorkIssuesForLifeAdmin(db, input.domainId, driftLifeAdminIds),
    upstreamLifeAdminIds.length === 0
      ? Promise.resolve([] as Array<{ life_admin: LifeAdminRow; workflow: WorkflowRow }>)
      : db
        .select({ life_admin: workflowLifeAdmin, workflow: workflows })
        .from(workflowLifeAdmin)
        .innerJoin(workflows, eq(workflowLifeAdmin.workflowId, workflows.id))
        .where(and(eq(workflowLifeAdmin.domainId, input.domainId), inArray(workflowLifeAdmin.id, upstreamLifeAdminIds))),
  ]);
  const upstreamById = new Map(upstreamLifeAdmin.map((row) => [row.life_admin.id, row]));

  const headsUp = driftRows.map((row) => {
    const payload = row.event.payload as Record<string, unknown>;
    const upstream = typeof payload.upstreamLifeAdminId === "string" ? upstreamById.get(payload.upstreamLifeAdminId) : undefined;
    return {
      life_admin: life_adminDisplay(row),
      drift: {
        eventId: row.event.id,
        createdAt: row.event.createdAt,
        previousVersion: typeof payload.previousVersion === "number" ? payload.previousVersion : null,
        version: typeof payload.version === "number" ? payload.version : null,
        upstream: upstream
          ? {
            lifeAdminId: upstream.life_admin.id,
            life_adminKey: upstream.life_admin.life_adminKey,
            title: upstream.life_admin.title,
            workflowId: upstream.workflow.id,
            workflowName: upstream.workflow.name,
          }
          : {
            lifeAdminId: typeof payload.upstreamLifeAdminId === "string" ? payload.upstreamLifeAdminId : null,
            life_adminKey: typeof payload.upstreamLifeAdminKey === "string" ? payload.upstreamLifeAdminKey : null,
            title: null,
            workflowId: typeof payload.upstreamWorkflowId === "string" ? payload.upstreamWorkflowId : null,
            workflowName: null,
          },
      },
      activeWork: activeWorkByLifeAdmin.get(row.life_admin.id) ?? null,
      workIssue: workIssuesByLifeAdmin.get(row.life_admin.id) ?? null,
    };
  });

  return {
    suggestions,
    reviews,
    headsUp,
    counts: { suggestions: suggestions.length, reviews: reviews.length, headsUp: headsUp.length },
  };
}

export async function listDomainLifeAdminEvents(
  db: Db,
  input: { domainId: string; types?: string[]; limit?: number; offset?: number },
) {
  const limit = boundedLimit(input.limit, DOMAIN_LIFE_ADMIN_EVENTS_DEFAULT_LIMIT, DOMAIN_LIFE_ADMIN_EVENTS_MAX_LIMIT);
  const offset = Math.max(0, Math.floor(input.offset ?? 0));
  const fromStage = alias(workflowStages, "from_stage");
  const toStage = alias(workflowStages, "to_stage");
  const actorAgent = alias(agents, "actor_agent");

  const rows = await db
    .select({
      event: workflowLifeAdminEvents,
      life_admin: {
        id: workflowLifeAdmin.id,
        life_adminKey: workflowLifeAdmin.life_adminKey,
        title: workflowLifeAdmin.title,
        terminalKind: workflowLifeAdmin.terminalKind,
      },
      workflow: { id: workflows.id, key: workflows.key, name: workflows.name },
      fromStage: { id: fromStage.id, key: fromStage.key, name: fromStage.name, kind: fromStage.kind },
      toStage: { id: toStage.id, key: toStage.key, name: toStage.name, kind: toStage.kind },
      actorAgent: { id: actorAgent.id, name: actorAgent.name },
    })
    .from(workflowLifeAdminEvents)
    .innerJoin(workflowLifeAdmin, eq(workflowLifeAdminEvents.lifeAdminId, workflowLifeAdmin.id))
    .innerJoin(workflows, eq(workflowLifeAdmin.workflowId, workflows.id))
    .leftJoin(fromStage, eq(workflowLifeAdminEvents.fromStageId, fromStage.id))
    .leftJoin(toStage, eq(workflowLifeAdminEvents.toStageId, toStage.id))
    .leftJoin(actorAgent, eq(workflowLifeAdminEvents.actorAgentId, actorAgent.id))
    .where(and(
      eq(workflowLifeAdminEvents.domainId, input.domainId),
      eq(workflowLifeAdmin.domainId, input.domainId),
      input.types && input.types.length > 0 ? inArray(workflowLifeAdminEvents.type, input.types) : undefined,
    ))
    .orderBy(desc(workflowLifeAdminEvents.createdAt), desc(workflowLifeAdminEvents.id))
    .limit(limit + 1)
    .offset(offset);

  const hasMore = rows.length > limit;
  const pageRows = hasMore ? rows.slice(0, limit) : rows;
  const automationRows = pageRows.filter((row) =>
    row.event.type === "automation_executed" || row.event.type === "automation_failed"
  );
  const routineIds = [...new Set(automationRows
    .map((row) => payloadString(row.event.payload, "routineId"))
    .filter((id): id is string => Boolean(id)))];
  const issueIds = [...new Set(automationRows
    .map((row) => payloadString(row.event.payload, "issueId"))
    .filter((id): id is string => Boolean(id)))];
  const automationWorkflowIds = [...new Set(automationRows.map((row) => row.workflow.id))];
  const [routineRows, issueRowsForEvents, workflowStageRows] = await Promise.all([
    routineIds.length > 0
      ? db
          .select({ id: routines.id, title: routines.title })
          .from(routines)
          .where(and(eq(routines.domainId, input.domainId), inArray(routines.id, routineIds)))
      : Promise.resolve([]),
    issueIds.length > 0
      ? db
          .select({ id: issues.id, identifier: issues.identifier, title: issues.title, status: issues.status })
          .from(issues)
          .where(and(eq(issues.domainId, input.domainId), inArray(issues.id, issueIds)))
      : Promise.resolve([]),
    automationWorkflowIds.length > 0
      ? db
          .select()
          .from(workflowStages)
          .where(inArray(workflowStages.workflowId, automationWorkflowIds))
      : Promise.resolve([]),
  ]);
  const routinesById = new Map(routineRows.map((routine) => [routine.id, routine]));
  const issuesById = new Map(issueRowsForEvents.map((issue) => [issue.id, issue]));
  const stagesByAutomationId = new Map<string, typeof workflowStages.$inferSelect>();
  const stagesByRoutineId = new Map<string, typeof workflowStages.$inferSelect>();
  for (const stage of workflowStageRows) {
    const automation = stageAutomationFromConfig(stage);
    if (!automation) continue;
    stagesByAutomationId.set(automation.id, stage);
    stagesByRoutineId.set(automation.routineId, stage);
  }
  const items = pageRows.map((row) => {
    const routineId = payloadString(row.event.payload, "routineId");
    const issueId = payloadString(row.event.payload, "issueId");
    const automationId = payloadString(row.event.payload, "automationId");
    const automationStage = (
      (automationId ? stagesByAutomationId.get(automationId) : undefined) ??
      (routineId ? stagesByRoutineId.get(routineId) : undefined)
    );
    const routine = routineId ? routinesById.get(routineId) ?? null : null;
    const issue = issueId ? issuesById.get(issueId) ?? null : null;
    return {
      ...row.event,
      life_admin: row.life_admin,
      workflow: row.workflow,
      fromStage: row.fromStage?.id ? row.fromStage : null,
      toStage: row.toStage?.id ? row.toStage : null,
      actorAgent: row.actorAgent?.id ? row.actorAgent : null,
      automation: row.event.type === "automation_executed" || row.event.type === "automation_failed"
        ? {
            routine: routine ? { id: routine.id, title: routine.title } : null,
            issue: issue ? { id: issue.id, identifier: issue.identifier, title: issue.title, status: issue.status } : null,
            routineRunId: payloadString(row.event.payload, "routineRunId"),
            stage: automationStage
              ? { id: automationStage.id, key: automationStage.key, name: automationStage.name, kind: automationStage.kind }
              : null,
          }
        : undefined,
    };
  });

  return {
    items,
    pagination: { limit, offset, nextOffset: hasMore ? offset + limit : null, hasMore },
  };
}

export type LifeAdminChildrenRollup = { total: number; done: number; dropped: number; inMotion: number };

type SubtreeRow = {
  id: string;
  parent_life_admin_id: string | null;
  workflow_id: string;
  stage_id: string;
  life_admin_key: string;
  title: string;
  terminal_kind: string | null;
  created_at: string | Date;
  updated_at: string | Date;
  depth: number;
};

export type LifeAdminChildNode = {
  id: string;
  life_adminKey: string;
  title: string;
  terminalKind: string | null;
  createdAt: Date;
  updatedAt: Date;
  workflow: { id: string; key: string; name: string };
  stage: { id: string; key: string; name: string; kind: string };
  rollup: LifeAdminChildrenRollup;
  childGroups: Array<{ workflow: { id: string; key: string; name: string }; life_admin: LifeAdminChildNode[] }>;
};

export async function getLifeAdminChildrenTree(db: Db, domainId: string, lifeAdminId: string) {
  const result = await db.execute(sql`
    with recursive subtree as (
      select id, parent_life_admin_id, workflow_id, stage_id, life_admin_key, title, terminal_kind, created_at, updated_at, 0 as depth
      from workflow_life_admin
      where domain_id = ${domainId} and id = ${lifeAdminId}
      union all
      select child.id, child.parent_life_admin_id, child.workflow_id, child.stage_id, child.life_admin_key, child.title,
             child.terminal_kind, child.created_at, child.updated_at, parent.depth + 1
      from workflow_life_admin child
      join subtree parent on child.parent_life_admin_id = parent.id
      where child.domain_id = ${domainId}
        and child.hidden_from_board_at is null
        and parent.depth < ${LIFE_ADMIN_CHILDREN_TREE_MAX_DEPTH}
    )
    select * from subtree limit ${LIFE_ADMIN_CHILDREN_TREE_MAX_NODES + 1}
  `);
  const rows = Array.from(result) as SubtreeRow[];
  if (rows.length === 0) throw notFound("Workflow life_admin not found");
  const truncated = rows.length > LIFE_ADMIN_CHILDREN_TREE_MAX_NODES;
  const bounded = truncated ? rows.slice(0, LIFE_ADMIN_CHILDREN_TREE_MAX_NODES) : rows;

  const workflowIds = [...new Set(bounded.map((row) => row.workflow_id))];
  const stageIds = [...new Set(bounded.map((row) => row.stage_id))];
  const [workflowRows, stageRows] = await Promise.all([
    db.select({ id: workflows.id, key: workflows.key, name: workflows.name })
      .from(workflows)
      .where(and(eq(workflows.domainId, domainId), inArray(workflows.id, workflowIds))),
    db.select({ id: workflowStages.id, key: workflowStages.key, name: workflowStages.name, kind: workflowStages.kind })
      .from(workflowStages)
      .where(inArray(workflowStages.id, stageIds)),
  ]);
  const workflowById = new Map(workflowRows.map((row) => [row.id, row]));
  const stageById = new Map(stageRows.map((row) => [row.id, row]));

  const nodeById = new Map<string, LifeAdminChildNode>();
  const childRowsByParent = new Map<string, SubtreeRow[]>();
  for (const row of bounded) {
    if (row.id !== lifeAdminId && row.parent_life_admin_id) {
      const list = childRowsByParent.get(row.parent_life_admin_id) ?? [];
      list.push(row);
      childRowsByParent.set(row.parent_life_admin_id, list);
    }
  }

  function buildNode(row: SubtreeRow): LifeAdminChildNode {
    const childRows = (childRowsByParent.get(row.id) ?? [])
      .sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());
    const children = childRows.map(buildNode);
    const rollup: LifeAdminChildrenRollup = { total: 0, done: 0, dropped: 0, inMotion: 0 };
    for (const child of children) {
      rollup.total += 1 + child.rollup.total;
      rollup.done += (child.terminalKind === "done" ? 1 : 0) + child.rollup.done;
      rollup.dropped += (child.terminalKind === "cancelled" ? 1 : 0) + child.rollup.dropped;
      rollup.inMotion += (child.terminalKind === null ? 1 : 0) + child.rollup.inMotion;
    }
    const workflow = workflowById.get(row.workflow_id) ?? { id: row.workflow_id, key: "", name: "" };
    const groups = new Map<string, { workflow: { id: string; key: string; name: string }; life_admin: LifeAdminChildNode[] }>();
    for (const child of children) {
      const group = groups.get(child.workflow.id) ?? { workflow: child.workflow, life_admin: [] };
      group.life_admin.push(child);
      groups.set(child.workflow.id, group);
    }
    const childGroups = [...groups.values()].sort((a, b) => {
      if (a.workflow.id === row.workflow_id && b.workflow.id !== row.workflow_id) return -1;
      if (b.workflow.id === row.workflow_id && a.workflow.id !== row.workflow_id) return 1;
      return a.workflow.name.localeCompare(b.workflow.name);
    });
    const node: LifeAdminChildNode = {
      id: row.id,
      life_adminKey: row.life_admin_key,
      title: row.title,
      terminalKind: row.terminal_kind,
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at),
      workflow,
      stage: stageById.get(row.stage_id) ?? { id: row.stage_id, key: "", name: "", kind: "" },
      rollup,
      childGroups,
    };
    nodeById.set(row.id, node);
    return node;
  }

  const rootRow = bounded.find((row) => row.id === lifeAdminId);
  if (!rootRow) throw notFound("Workflow life_admin not found");
  const root = buildNode(rootRow);

  return {
    life_admin: root,
    rollup: root.rollup,
    childGroups: root.childGroups,
    truncated,
    totalNodes: bounded.length,
  };
}

export async function getDirectChildrenSummary(
  db: Db,
  domainId: string,
  lifeAdminId: string,
): Promise<LifeAdminChildrenRollup> {
  const [counts] = await db
    .select({
      total: sql<number>`count(*)::int`,
      done: sql<number>`count(*) filter (where ${workflowLifeAdmin.terminalKind} = 'done')::int`,
      dropped: sql<number>`count(*) filter (where ${workflowLifeAdmin.terminalKind} = 'cancelled')::int`,
      inMotion: sql<number>`count(*) filter (where ${workflowLifeAdmin.terminalKind} is null)::int`,
    })
    .from(workflowLifeAdmin)
    .where(and(
      eq(workflowLifeAdmin.domainId, domainId),
      eq(workflowLifeAdmin.parentLifeAdminId, lifeAdminId),
      isNull(workflowLifeAdmin.hiddenFromBoardAt),
    ));
  return counts ?? { total: 0, done: 0, dropped: 0, inMotion: 0 };
}

export async function loadActiveWorkForLifeAdmin(
  db: Db,
  domainId: string,
  lifeAdminIds: string[],
): Promise<Map<string, ActiveWork | null>> {
  const map = new Map<string, ActiveWork | null>(lifeAdminIds.map((id) => [id, null]));
  if (lifeAdminIds.length === 0) return map;
  const rows = await db
    .select({
      lifeAdminId: workflowLifeAdminIssueLinks.lifeAdminId,
      issueId: issues.id,
      issueIdentifier: issues.identifier,
      issueTitle: issues.title,
      issueRole: workflowLifeAdminIssueLinks.role,
      agentId: issues.assigneeAgentId,
      agentName: agents.name,
      startedAt: issues.startedAt,
      issueUpdatedAt: issues.updatedAt,
    })
    .from(workflowLifeAdminIssueLinks)
    .innerJoin(issues, eq(workflowLifeAdminIssueLinks.issueId, issues.id))
    .innerJoin(agents, eq(issues.assigneeAgentId, agents.id))
    .where(and(
      eq(workflowLifeAdminIssueLinks.domainId, domainId),
      inArray(workflowLifeAdminIssueLinks.lifeAdminId, lifeAdminIds),
      inArray(workflowLifeAdminIssueLinks.role, ["work", "automation"]),
      eq(issues.domainId, domainId),
      eq(issues.status, "in_progress"),
      visibleIssueCondition(),
    ))
    .orderBy(desc(issues.updatedAt));
  for (const row of rows) {
    if (map.get(row.lifeAdminId)) continue;
    map.set(row.lifeAdminId, {
      issueId: row.issueId,
      issueIdentifier: row.issueIdentifier,
      issueTitle: row.issueTitle,
      issueRole: row.issueRole as "work" | "automation",
      agentId: row.agentId!,
      agentName: row.agentName,
      startedAt: row.startedAt ?? row.issueUpdatedAt,
    });
  }
  return map;
}

type DescendantActiveWorkCountRow = {
  root_id: string;
  count: number;
};

export async function loadDescendantActiveWorkCountsForLifeAdmin(
  db: Db,
  domainId: string,
  lifeAdminIds: string[],
): Promise<Map<string, number>> {
  const uniqueLifeAdminIds = [...new Set(lifeAdminIds)];
  const map = new Map<string, number>(uniqueLifeAdminIds.map((id) => [id, 0]));
  if (uniqueLifeAdminIds.length === 0) return map;

  const rootValues = sql.join(uniqueLifeAdminIds.map((id) => sql`(${id}::uuid)`), sql`, `);
  const rows = Array.from(await db.execute(sql`
    with recursive roots(root_id) as (
      values ${rootValues}
    ),
    subtree(root_id, id, depth) as (
      select roots.root_id, roots.root_id, 0
      from roots
      join workflow_life_admin root_life_admin
        on root_life_admin.id = roots.root_id
       and root_life_admin.domain_id = ${domainId}
      union all
      select subtree.root_id, child.id, subtree.depth + 1
      from workflow_life_admin child
      join subtree on child.parent_life_admin_id = subtree.id
      where child.domain_id = ${domainId}
        and child.hidden_from_board_at is null
        and subtree.depth < ${LIFE_ADMIN_CHILDREN_TREE_MAX_DEPTH}
    )
    select subtree.root_id, count(distinct subtree.id)::int as count
    from subtree
    join workflow_life_admin_issue_links link
      on link.domain_id = ${domainId}
     and link.life_admin_id = subtree.id
     and link.role in ('work', 'automation')
    join issues issue
      on issue.id = link.issue_id
     and issue.domain_id = ${domainId}
     and issue.status = 'in_progress'
     and issue.hidden_at is null
    join agents agent on agent.id = issue.assignee_agent_id
    where subtree.depth > 0
    group by subtree.root_id
  `)) as DescendantActiveWorkCountRow[];

  for (const row of rows) {
    map.set(row.root_id, row.count);
  }
  return map;
}

type WorkflowDescendantActiveWorkCountRow = {
  workflow_id: string;
  count: number;
};

export async function loadWorkflowDescendantActiveWorkCounts(
  db: Db,
  domainId: string,
  workflowIds: string[],
): Promise<Map<string, number>> {
  const uniqueWorkflowIds = [...new Set(workflowIds)];
  const map = new Map<string, number>(uniqueWorkflowIds.map((id) => [id, 0]));
  if (uniqueWorkflowIds.length === 0) return map;

  const workflowValues = sql.join(uniqueWorkflowIds.map((id) => sql`(${id}::uuid)`), sql`, `);
  const rows = Array.from(await db.execute(sql`
    with recursive target_workflows(workflow_id) as (
      values ${workflowValues}
    ),
    roots(root_workflow_id, root_life_admin_id) as (
      select target_workflows.workflow_id, root_life_admin.id
      from target_workflows
      join workflow_life_admin root_life_admin
        on root_life_admin.workflow_id = target_workflows.workflow_id
       and root_life_admin.domain_id = ${domainId}
    ),
    subtree(root_workflow_id, root_life_admin_id, id, depth) as (
      select roots.root_workflow_id, roots.root_life_admin_id, roots.root_life_admin_id, 0
      from roots
      union all
      select subtree.root_workflow_id, subtree.root_life_admin_id, child.id, subtree.depth + 1
      from workflow_life_admin child
      join subtree on child.parent_life_admin_id = subtree.id
      where child.domain_id = ${domainId}
        and child.hidden_from_board_at is null
        and subtree.depth < ${LIFE_ADMIN_CHILDREN_TREE_MAX_DEPTH}
    )
    select subtree.root_workflow_id as workflow_id, count(distinct subtree.id)::int as count
    from subtree
    join workflow_life_admin_issue_links link
      on link.domain_id = ${domainId}
     and link.life_admin_id = subtree.id
     and link.role in ('work', 'automation')
    join issues issue
      on issue.id = link.issue_id
     and issue.domain_id = ${domainId}
     and issue.status = 'in_progress'
     and issue.hidden_at is null
    join agents agent on agent.id = issue.assignee_agent_id
    where subtree.depth > 0
    group by subtree.root_workflow_id
  `)) as WorkflowDescendantActiveWorkCountRow[];

  for (const row of rows) {
    map.set(row.workflow_id, row.count);
  }
  return map;
}

async function loadOpenWorkIssuesForLifeAdmin(db: Db, domainId: string, lifeAdminIds: string[]) {
  const map = new Map<string, { issueId: string; issueIdentifier: string | null; title: string; status: string }>();
  if (lifeAdminIds.length === 0) return map;
  const rows = await db
    .select({
      lifeAdminId: workflowLifeAdminIssueLinks.lifeAdminId,
      issueId: issues.id,
      issueIdentifier: issues.identifier,
      title: issues.title,
      status: issues.status,
    })
    .from(workflowLifeAdminIssueLinks)
    .innerJoin(issues, eq(workflowLifeAdminIssueLinks.issueId, issues.id))
    .where(and(
      eq(workflowLifeAdminIssueLinks.domainId, domainId),
      inArray(workflowLifeAdminIssueLinks.lifeAdminId, lifeAdminIds),
      eq(workflowLifeAdminIssueLinks.role, "work"),
      eq(issues.domainId, domainId),
      ne(issues.status, "done"),
      ne(issues.status, "cancelled"),
      visibleIssueCondition(),
    ))
    .orderBy(desc(issues.updatedAt));
  for (const row of rows) {
    if (map.has(row.lifeAdminId)) continue;
    map.set(row.lifeAdminId, {
      issueId: row.issueId,
      issueIdentifier: row.issueIdentifier,
      title: row.title,
      status: row.status,
    });
  }
  return map;
}

export type WorkflowConnections = { upstreamWorkflowIds: string[]; downstreamWorkflowIds: string[] };

export async function loadWorkflowConnections(
  db: Db,
  domainId: string,
): Promise<Map<string, WorkflowConnections>> {
  const parentLifeAdmin = alias(workflowLifeAdmin, "parent_life_admin");
  const rows = await db
    .selectDistinct({
      parentWorkflowId: parentLifeAdmin.workflowId,
      childWorkflowId: workflowLifeAdmin.workflowId,
    })
    .from(workflowLifeAdmin)
    .innerJoin(parentLifeAdmin, eq(workflowLifeAdmin.parentLifeAdminId, parentLifeAdmin.id))
    .where(and(
      eq(workflowLifeAdmin.domainId, domainId),
      eq(parentLifeAdmin.domainId, domainId),
      ne(workflowLifeAdmin.workflowId, parentLifeAdmin.workflowId),
    ));
  const map = new Map<string, WorkflowConnections>();
  const entry = (workflowId: string) => {
    let value = map.get(workflowId);
    if (!value) {
      value = { upstreamWorkflowIds: [], downstreamWorkflowIds: [] };
      map.set(workflowId, value);
    }
    return value;
  };
  for (const row of rows) {
    entry(row.childWorkflowId).upstreamWorkflowIds.push(row.parentWorkflowId);
    entry(row.parentWorkflowId).downstreamWorkflowIds.push(row.childWorkflowId);
  }
  for (const value of map.values()) {
    value.upstreamWorkflowIds.sort();
    value.downstreamWorkflowIds.sort();
  }
  return map;
}

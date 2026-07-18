import { Router, type Request } from "express";
import { z } from "zod";
import { and, asc, desc, eq, ilike, inArray, isNotNull, isNull, ne, or, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import type { Db } from "@paperclipai/db";
import {
  agents,
  documents,
  documentRevisions,
  heartbeatRuns,
  issueDocuments,
  issues as issueRows,
  issueRelations,
  workflowAutomationExecutions,
  workflowLifeAdminBlockers,
  workflowLifeAdminDocuments,
  workflowLifeAdminEvents,
  workflowLifeAdminIssueLinks,
  workflowLifeAdmin,
  workflowDocuments,
  workflowStages,
  workflowTransitions,
  workflows,
  routines,
} from "@paperclipai/db";
import { validate } from "../middleware/validate.js";
import { badRequest, conflict, forbidden, HttpError, notFound, unauthorized, unprocessable } from "../errors.js";
import {
  WORKFLOW_LIFE_ADMIN_EVENTS_DEFAULT_LIMIT,
  WORKFLOW_LIFE_ADMIN_EVENTS_MAX_LIMIT,
  WORKFLOW_CONTEXT_PACK_EVENT_LIMIT,
  ensureWorkflowLifeAdminBodyDocumentFromSummary,
  workflowService,
  resolveWorkflowLifeAdminConversationSource,
  type WorkflowActor,
  type WorkflowStageConfig,
  type WorkflowStageKind,
} from "../services/workflows.js";
import {
  DOMAIN_LIFE_ADMIN_EVENTS_DEFAULT_LIMIT,
  DOMAIN_LIFE_ADMIN_EVENTS_MAX_LIMIT,
  DOMAIN_LIFE_ADMIN_EVENTS_MAX_TYPES,
  getLifeAdminChildrenTree,
  getDirectChildrenSummary,
  loadDescendantActiveWorkCountsForLifeAdmin,
  listDomainLifeAdminEvents,
  listWorkflowAttention,
  loadActiveWorkForLifeAdmin,
  loadWorkflowDescendantActiveWorkCounts,
  loadWorkflowConnections,
  WORKFLOW_ATTENTION_DEFAULT_LIMIT,
  WORKFLOW_ATTENTION_MAX_LIMIT,
  type AttentionCaller,
} from "../services/workflows-aggregation.js";
import { accessService } from "../services/access.js";
import { authorizationService } from "../services/authorization.js";
import { issueService } from "../services/issues.js";
import { assertDomainAccess } from "./authz.js";
import {
  computeWorkflowHealth,
  deriveLifeAdminType,
  envConfigSchema,
  issueDocumentKeySchema,
  WORKFLOW_LIFE_ADMIN_BODY_DOCUMENT_KEY,
  workflowAutomationRetryRequestSchema,
  workflowAutomationRetryScopeSchema,
  type WorkflowStageAutomation,
  type WorkflowLifeAdminLiveness,
  type WorkflowHealthFailedAutomationInput,
  type WorkflowHealthStageInput,
} from "@paperclipai/shared";
import { documentAnnotationService } from "../services/document-annotations.js";
import { logActivity } from "../services/activity-log.js";
import {
  formatWorkflowConversationBodyDocumentContextMarkdown,
  loadWorkflowConversationBodyDocumentContext,
} from "../services/workflow-conversation-context.js";
import { resolveActorSourceTrustForIssue } from "../services/source-trust.js";
import {
  formatWorkflowLifeAdminOutputContextMarkdown,
  workflowLifeAdminOutputsService,
  summarizeWorkflowLifeAdminOutputsForContext,
} from "../services/workflow-life_admin-outputs.js";

/** Per-stage instructions document keys look like `stage-instructions:{stageId}`. */
const STAGE_INSTRUCTIONS_PREFIX = "stage-instructions:";
type WorkflowRouteDb = Db | Parameters<Parameters<Db["transaction"]>[0]>[0];

const stageKindSchema = z.enum(["open", "working", "review", "done", "cancelled"]);
const jsonObjectSchema = z.record(z.string(), z.unknown());
const stageConfigSchema = z.record(z.string(), z.unknown()).default({});
const life_adminPatchSchema = z.object({
  title: z.string().trim().min(1).max(500).optional(),
  summary: z.string().max(8_000).nullable().optional(),
  fields: jsonObjectSchema.optional(),
  workspaceRef: jsonObjectSchema.nullable().optional(),
  parentLifeAdminId: z.string().uuid().nullable().optional(),
  expectedVersion: z.number().int().positive().optional(),
  leaseToken: z.string().uuid().nullable().optional(),
});
const ingestLifeAdminSchema = z.object({
  life_adminKey: z.string().max(1_024).nullable().optional(),
  title: z.string().trim().min(1).max(500),
  summary: z.string().max(8_000).nullable().optional(),
  fields: jsonObjectSchema.optional(),
  stageKey: z.string().trim().min(1).max(120).optional(),
  parentLifeAdminId: z.string().uuid().nullable().optional(),
  requestKey: z.string().trim().min(1).max(512).optional(),
  workspaceRef: jsonObjectSchema.nullable().optional(),
  blockedByLifeAdminIds: z.array(z.string().uuid()).max(100).optional(),
  blockedByLifeAdminKeys: z.array(z.string().max(1_024)).max(100).optional(),
});
const createWorkflowSchema = z.object({
  key: z.string().trim().min(1).max(120),
  name: z.string().trim().min(1).max(200),
  description: z.string().max(8_000).nullable().optional(),
  projectId: z.string().uuid().nullable().optional(),
  enforceTransitions: z.boolean().optional(),
  stages: z.array(z.object({
    key: z.string().trim().min(1).max(120),
    name: z.string().trim().min(1).max(200),
    kind: stageKindSchema,
    position: z.number().int().optional(),
    config: stageConfigSchema.optional(),
  })).optional(),
});
const updateWorkflowSchema = z.object({
  name: z.string().trim().min(1).max(200).optional(),
  description: z.string().max(8_000).nullable().optional(),
  enforceTransitions: z.boolean().optional(),
  archived: z.boolean().optional(),
});
const createStageSchema = z.object({
  key: z.string().trim().min(1).max(120),
  name: z.string().trim().min(1).max(200),
  kind: stageKindSchema,
  position: z.number().int(),
  config: stageConfigSchema.optional(),
});
const updateStageSchema = z.object({
  key: z.string().trim().min(1).max(120).optional(),
  name: z.string().trim().min(1).max(200).optional(),
  kind: stageKindSchema.optional(),
  position: z.number().int().optional(),
  config: stageConfigSchema.optional(),
});
const updateStageAutomationEnvSchema = z.object({
  env: envConfigSchema.nullable(),
  baseRoutineRevisionId: z.string().uuid().nullable().optional(),
});
const replaceTransitionsSchema = z.object({
  transitions: z.array(z.object({
    fromStageKey: z.string().trim().min(1).max(120),
    toStageKey: z.string().trim().min(1).max(120),
    label: z.string().max(200).nullable().optional(),
  })).max(500),
  enforceTransitions: z.boolean().optional(),
});
const batchIngestSchema = z.object({ items: z.array(ingestLifeAdminSchema).max(200) });
const breakdownLifeAdminSchema = z.object({
  items: z.array(z.object({
    key: z.string().trim().min(1).max(200),
    title: z.string().trim().min(1).max(500),
    summary: z.string().max(8_000).nullable().optional(),
    fields: jsonObjectSchema.optional(),
  })).max(200),
});
const claimLifeAdminSchema = z.object({ leaseSeconds: z.number().int().positive().max(86_400).optional() });
const releaseLifeAdminSchema = z.object({
  leaseToken: z.string().uuid().nullable().optional(),
  force: z.boolean().optional(),
});
const transitionLifeAdminSchema = z.object({
  toStageKey: z.string().trim().min(1).max(120),
  expectedVersion: z.number().int().positive(),
  leaseToken: z.string().uuid().nullable().optional(),
  reason: z.string().max(4_000).nullable().optional(),
  force: z.boolean().optional(),
  acceptSuggestionId: z.string().uuid().optional(),
});
const suggestTransitionSchema = z.object({
  toStageKey: z.string().trim().min(1).max(120),
  rationale: z.string().trim().min(1).max(8_000),
  confidence: z.number().min(0).max(1).optional(),
});
const resolveSuggestionSchema = z.object({
  suggestionId: z.string().uuid(),
  resolution: z.enum(["accept", "dismiss"]),
  expectedVersion: z.number().int().positive().optional(),
  reason: z.string().max(4_000).nullable().optional(),
  leaseToken: z.string().uuid().nullable().optional(),
});
const acknowledgeDriftSchema = z.object({
  expectedVersion: z.number().int().positive().optional(),
});
const retryAutomationQuerySchema = z.object({
  scope: workflowAutomationRetryScopeSchema.default("previous_stage"),
  targetStageId: z.string().uuid().optional(),
});
const reviewEditsSchema = z.object({
  title: z.string().trim().min(1).max(500).optional(),
  summary: z.string().max(8_000).nullable().optional(),
  fields: jsonObjectSchema.optional(),
  parentLifeAdminId: z.string().uuid().nullable().optional(),
});
const reviewLifeAdminSchema = z.object({
  decision: z.enum(["approve", "reject", "request_changes"]),
  reason: z.string().max(4_000).nullable().optional(),
  edits: reviewEditsSchema.optional(),
  expectedVersion: z.number().int().positive(),
  leaseToken: z.string().uuid().nullable().optional(),
});
const blockersSchema = z.object({ blockedByLifeAdminIds: z.array(z.string().uuid()).max(100) });
const issueLinkRoleSchema = z.enum(["origin", "conversation", "work", "automation"]);
const createIssueLinkSchema = z.object({
  issueId: z.string().uuid(),
  role: issueLinkRoleSchema,
});
const bulkReviewSchema = z.object({
  items: z.array(reviewLifeAdminSchema.extend({ lifeAdminId: z.string().uuid() })).max(100),
});
const upsertWorkflowDocumentSchema = z.object({
  title: z.string().trim().min(1).max(200).optional(),
  body: z.string().max(200_000),
  baseRevisionId: z.string().uuid().nullable().optional(),
});
const upsertWorkflowLifeAdminDocumentSchema = z.object({
  title: z.string().trim().min(1).max(200).optional(),
  format: z.string().trim().min(1).max(80).optional().default("markdown"),
  body: z.string().max(200_000),
  changeSummary: z.string().trim().max(1_000).nullable().optional(),
  baseRevisionId: z.string().uuid().nullable().optional(),
});
const intakeFieldTypes = new Set(["select", "text", "multiline"]);

function stageAutomationRoutineId(config: unknown) {
  if (!config || typeof config !== "object" || Array.isArray(config)) return null;
  const onEnter = (config as { onEnter?: unknown }).onEnter;
  if (!onEnter || typeof onEnter !== "object" || Array.isArray(onEnter)) return null;
  const record = onEnter as Record<string, unknown>;
  return record.type === "run_routine" && typeof record.routineId === "string" ? record.routineId : null;
}

function readAutomationContextValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function stageAutomationContext(config: Record<string, unknown>) {
  const onEnter = config.onEnter;
  const record = onEnter && typeof onEnter === "object" && !Array.isArray(onEnter)
    ? onEnter as Record<string, unknown>
    : {};
  return {
    projectId: readAutomationContextValue(record.projectId),
    projectWorkspaceId: readAutomationContextValue(record.projectWorkspaceId),
    executionWorkspaceId: readAutomationContextValue(record.executionWorkspaceId),
    executionWorkspacePreference: readAutomationContextValue(record.executionWorkspacePreference),
    executionWorkspaceSettings:
      record.executionWorkspaceSettings && typeof record.executionWorkspaceSettings === "object" && !Array.isArray(record.executionWorkspaceSettings)
        ? record.executionWorkspaceSettings
        : null,
  };
}

function withDerivedStageAutomation(
  stage: typeof workflowStages.$inferSelect,
  routineById: Map<string, {
    assigneeAgentId: string | null;
    title: string;
    description: string | null;
    env: WorkflowStageAutomation["env"];
    latestRevisionId: string | null;
    latestRevisionNumber: number;
  }>,
) {
  const config = stage.config && typeof stage.config === "object" && !Array.isArray(stage.config)
    ? { ...(stage.config as Record<string, unknown>) }
    : {};
  const routineId = stageAutomationRoutineId(config);
  const routine = routineId ? routineById.get(routineId) : null;
  if (!routine) return { ...stage, config };
  return {
    ...stage,
    config: {
      ...config,
      automation: {
        routineId,
        assigneeAgentId: routine.assigneeAgentId,
        titleTemplate: routine.title,
        instructionsBody: routine.description ?? "",
        ...stageAutomationContext(config),
        env: routine.env ?? null,
        latestRoutineRevisionId: routine.latestRevisionId,
        latestRoutineRevisionNumber: routine.latestRevisionNumber,
      },
    },
  };
}

function extractIntakeFormFields(stage: typeof workflowStages.$inferSelect | null) {
  const baseFields = [{ key: "title", label: "Name", type: "text", required: true, options: [] as string[] }];
  const variables = stage?.config && typeof stage.config === "object" && !Array.isArray(stage.config)
    ? (stage.config as { variables?: unknown }).variables
    : null;
  if (!Array.isArray(variables)) return baseFields;

  return [
    ...baseFields,
    ...variables.flatMap((raw) => {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
      const variable = raw as Record<string, unknown>;
      const routineName = typeof variable.name === "string" && variable.name.trim().length > 0
        ? variable.name.trim()
        : null;
      const legacyKey = typeof variable.key === "string" && variable.key.trim().length > 0
        ? variable.key.trim()
        : null;

      const options = Array.isArray(variable.options)
        ? variable.options.filter((option): option is string => typeof option === "string" && option.trim().length > 0)
        : [];

      // Routine variable shape (body-driven `{{name}}`): every variable on the
      // stage becomes an Add-item field; routine types map onto intake types.
      if (routineName) {
        const rawType = typeof variable.type === "string" ? variable.type : "text";
        const type = rawType === "select"
          ? "select"
          : rawType === "textarea" || rawType === "multiline"
            ? "multiline"
            : "text";
        const label = typeof variable.label === "string" && variable.label.trim().length > 0
          ? variable.label.trim()
          : routineName;
        return [{ key: routineName, label, type, required: variable.required === true, options }];
      }

      // Legacy workflow variable shape: opt-in via `showInAddForm`, keyed by `key`.
      if (!legacyKey) return [];
      if (variable.showInAddForm !== true) return [];
      if (typeof variable.label !== "string" || variable.label.trim().length === 0) return [];
      const type = typeof variable.type === "string" && intakeFieldTypes.has(variable.type) ? variable.type : "text";
      return [{
        key: legacyKey,
        label: variable.label,
        type,
        required: variable.required === true,
        options,
      }];
    }),
  ];
}

function isPgUniqueViolation(error: unknown) {
  return (error as { code?: unknown })?.code === "23505";
}

function codedConflictForUnique(error: unknown): never {
  if (isPgUniqueViolation(error)) {
    throw conflict("Duplicate workflow resource key", { code: "duplicate_key" });
  }
  throw error;
}

function assertWorkflowDomainAccess(req: Request, domainId: string) {
  try {
    assertDomainAccess(req, domainId);
  } catch (error) {
    if (
      error instanceof HttpError &&
      error.status === 403 &&
      (error.message.includes("another domain") || error.message.includes("does not have access"))
    ) {
      throw notFound("Workflow resource not found");
    }
    throw error;
  }
}

function actorForMutation(req: Request): WorkflowActor {
  if (req.actor.type === "agent") {
    if (!req.actor.agentId) throw unauthorized();
    if (!req.actor.runId) throw unprocessable("Agent workflow mutations require a run id", { code: "run_id_required" });
    return { type: "agent", agentId: req.actor.agentId, runId: req.actor.runId };
  }
  if (req.actor.type === "board") {
    return { type: "user", userId: req.actor.userId ?? "board" };
  }
  throw unauthorized();
}

function attentionCallerFor(req: Request): AttentionCaller {
  if (req.actor.type === "agent") {
    if (!req.actor.agentId) throw unauthorized();
    return { type: "agent", agentId: req.actor.agentId };
  }
  if (req.actor.type === "board") {
    return { type: "user", userId: req.actor.userId ?? "board" };
  }
  throw unauthorized();
}

function parseEventTypesQuery(value: unknown): string[] | undefined {
  if (value === undefined) return undefined;
  const raw = Array.isArray(value) ? value : [value];
  const types = raw
    .flatMap((item) => String(item).split(","))
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
  if (types.length === 0) return undefined;
  if (types.length > DOMAIN_LIFE_ADMIN_EVENTS_MAX_TYPES) {
    throw badRequest(`types accepts at most ${DOMAIN_LIFE_ADMIN_EVENTS_MAX_TYPES} values`);
  }
  for (const type of types) {
    if (!/^[a-z_]{1,64}$/.test(type)) throw badRequest(`Invalid event type: ${type}`);
  }
  return [...new Set(types)];
}

function parseOptionalNonNegativeInteger(value: unknown, name: string) {
  if (value === undefined) return null;
  if (Array.isArray(value)) throw badRequest(`${name} must be a single integer`);
  const raw = typeof value === "string" ? value.trim() : String(value);
  if (!/^\d+$/.test(raw)) throw badRequest(`${name} must be a non-negative integer`);
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed)) throw badRequest(`${name} is too large`);
  return parsed;
}

function parseLifeAdminEventsQuery(query: Request["query"]) {
  const requestedLimit = parseOptionalNonNegativeInteger(query.limit, "limit");
  const offset = parseOptionalNonNegativeInteger(query.offset, "offset") ?? 0;
  if (requestedLimit === 0) throw badRequest("limit must be a positive integer");
  return {
    limit: Math.min(requestedLimit ?? WORKFLOW_LIFE_ADMIN_EVENTS_DEFAULT_LIMIT, WORKFLOW_LIFE_ADMIN_EVENTS_MAX_LIMIT),
    offset,
  };
}

async function resolveWorkflowDomainId(db: Db, workflowId: string) {
  const row = await db
    .select({ domainId: workflows.domainId })
    .from(workflows)
    .where(eq(workflows.id, workflowId))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!row) throw notFound("Workflow not found");
  return row.domainId;
}

async function resolveLifeAdminDomainId(db: Db, lifeAdminId: string) {
  const row = await db
    .select({ domainId: workflowLifeAdmin.domainId })
    .from(workflowLifeAdmin)
    .where(eq(workflowLifeAdmin.id, lifeAdminId))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!row) throw notFound("Workflow life_admin not found");
  return row.domainId;
}

async function assertWorkflowAccess(db: Db, req: Request, workflowId: string) {
  const domainId = await resolveWorkflowDomainId(db, workflowId);
  assertWorkflowDomainAccess(req, domainId);
  return domainId;
}

async function assertWorkflowWriteAccess(
  req: Request,
  input: {
    access: ReturnType<typeof accessService>;
    domainId: string;
    workflowId: string;
  },
) {
  assertWorkflowDomainAccess(req, input.domainId);
  const decision = await input.access.decide({
    actor: req.actor,
    action: "workflows:write",
    resource: { type: "domain", domainId: input.domainId },
    scope: { workflowId: input.workflowId },
  });
  if (!decision.allowed) {
    throw new HttpError(403, decision.explanation, {
      code: decision.code ?? "workflow_write_forbidden",
      reason: decision.reason,
      workflowId: input.workflowId,
    });
  }
}

function mapWorkflowDocumentRevision(row: {
  id: string;
  domainId: string;
  documentId: string;
  workflowId: string;
  key: string;
  revisionNumber: number;
  title: string | null;
  format: string;
  body: string;
  changeSummary: string | null;
  createdByAgentId: string | null;
  createdByUserId: string | null;
  createdAt: Date;
}) {
  return row;
}

async function getWorkflowDocumentRow(db: Db, input: { domainId: string; workflowId: string; key: string }) {
  return db
    .select({ link: workflowDocuments, document: documents, revision: documentRevisions })
    .from(workflowDocuments)
    .innerJoin(documents, eq(workflowDocuments.documentId, documents.id))
    .leftJoin(documentRevisions, eq(documents.latestRevisionId, documentRevisions.id))
    .where(and(
      eq(workflowDocuments.domainId, input.domainId),
      eq(workflowDocuments.workflowId, input.workflowId),
      eq(workflowDocuments.key, input.key),
    ))
    .limit(1)
    .then((rows) => rows[0] ?? null);
}

async function listWorkflowDocumentRevisions(db: Db, input: { domainId: string; workflowId: string; key: string }) {
  return db
    .select({
      id: documentRevisions.id,
      domainId: documentRevisions.domainId,
      documentId: documentRevisions.documentId,
      workflowId: workflowDocuments.workflowId,
      key: workflowDocuments.key,
      revisionNumber: documentRevisions.revisionNumber,
      title: documentRevisions.title,
      format: documentRevisions.format,
      body: documentRevisions.body,
      changeSummary: documentRevisions.changeSummary,
      createdByAgentId: documentRevisions.createdByAgentId,
      createdByUserId: documentRevisions.createdByUserId,
      createdAt: documentRevisions.createdAt,
    })
    .from(workflowDocuments)
    .innerJoin(documents, eq(workflowDocuments.documentId, documents.id))
    .innerJoin(documentRevisions, eq(documentRevisions.documentId, documents.id))
    .where(and(
      eq(workflowDocuments.domainId, input.domainId),
      eq(workflowDocuments.workflowId, input.workflowId),
      eq(workflowDocuments.key, input.key),
    ))
    .orderBy(desc(documentRevisions.revisionNumber))
    .then((rows) => rows.map(mapWorkflowDocumentRevision));
}

function parseDocumentKey(rawKey: unknown) {
  const parsed = issueDocumentKeySchema.safeParse(String(rawKey ?? "").trim().toLowerLifeAdmin());
  if (!parsed.success) {
    throw badRequest("Invalid document key", parsed.error.issues);
  }
  return parsed.data;
}

function mapWorkflowLifeAdminDocumentRevision(row: {
  id: string;
  domainId: string;
  documentId: string;
  lifeAdminId: string;
  key: string;
  revisionNumber: number;
  title: string | null;
  format: string;
  body: string;
  changeSummary: string | null;
  createdByAgentId: string | null;
  createdByUserId: string | null;
  createdAt: Date;
}) {
  return row;
}

async function getWorkflowLifeAdminDocumentRow(db: WorkflowRouteDb, input: { domainId: string; lifeAdminId: string; key: string }) {
  return db
    .select({ link: workflowLifeAdminDocuments, document: documents, revision: documentRevisions })
    .from(workflowLifeAdminDocuments)
    .innerJoin(documents, eq(workflowLifeAdminDocuments.documentId, documents.id))
    .leftJoin(documentRevisions, eq(documents.latestRevisionId, documentRevisions.id))
    .where(and(
      eq(workflowLifeAdminDocuments.domainId, input.domainId),
      eq(workflowLifeAdminDocuments.lifeAdminId, input.lifeAdminId),
      eq(workflowLifeAdminDocuments.key, input.key),
    ))
    .limit(1)
    .then((rows: Array<{ link: typeof workflowLifeAdminDocuments.$inferSelect; document: typeof documents.$inferSelect; revision: typeof documentRevisions.$inferSelect | null }>) => rows[0] ?? null);
}

async function listWorkflowLifeAdminDocumentRevisions(db: Db, input: { domainId: string; lifeAdminId: string; key: string }) {
  return db
    .select({
      id: documentRevisions.id,
      domainId: documentRevisions.domainId,
      documentId: documentRevisions.documentId,
      lifeAdminId: workflowLifeAdminDocuments.lifeAdminId,
      key: workflowLifeAdminDocuments.key,
      revisionNumber: documentRevisions.revisionNumber,
      title: documentRevisions.title,
      format: documentRevisions.format,
      body: documentRevisions.body,
      changeSummary: documentRevisions.changeSummary,
      createdByAgentId: documentRevisions.createdByAgentId,
      createdByUserId: documentRevisions.createdByUserId,
      createdAt: documentRevisions.createdAt,
    })
    .from(workflowLifeAdminDocuments)
    .innerJoin(documents, eq(workflowLifeAdminDocuments.documentId, documents.id))
    .innerJoin(documentRevisions, eq(documentRevisions.documentId, documents.id))
    .where(and(
      eq(workflowLifeAdminDocuments.domainId, input.domainId),
      eq(workflowLifeAdminDocuments.lifeAdminId, input.lifeAdminId),
      eq(workflowLifeAdminDocuments.key, input.key),
    ))
    .orderBy(desc(documentRevisions.revisionNumber))
    .then((rows) => rows.map(mapWorkflowLifeAdminDocumentRevision));
}

async function resolveLifeAdminWorkflowId(db: Db, input: { domainId: string; lifeAdminId: string }) {
  const row = await db
    .select({ workflowId: workflowLifeAdmin.workflowId })
    .from(workflowLifeAdmin)
    .where(and(eq(workflowLifeAdmin.domainId, input.domainId), eq(workflowLifeAdmin.id, input.lifeAdminId)))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!row) throw notFound("Workflow life_admin not found");
  return row.workflowId;
}

function activityActorForWorkflowRoute(actor: WorkflowActor) {
  if (actor.type === "agent") {
    return { actorType: "agent" as const, actorId: actor.agentId, agentId: actor.agentId, runId: actor.runId };
  }
  if (actor.type === "user") {
    return { actorType: "user" as const, actorId: actor.userId, agentId: null, runId: null };
  }
  return { actorType: "system" as const, actorId: "workflow", agentId: null, runId: null };
}

function issueIdFromWorkflowRouteRunContext(contextSnapshot: unknown) {
  if (!contextSnapshot || typeof contextSnapshot !== "object" || Array.isArray(contextSnapshot)) return null;
  const context = contextSnapshot as Record<string, unknown>;
  const issueId = context.issueId ?? context.taskId;
  return typeof issueId === "string" && issueId.trim().length > 0 ? issueId.trim() : null;
}

async function sourceTrustForWorkflowLifeAdminDocumentWrite(
  dbOrTx: Db | any,
  input: {
    domainId: string;
    lifeAdminId: string;
    actor: WorkflowActor;
  },
) {
  if (input.actor.type !== "agent") return null;

  const conversationSource = await resolveWorkflowLifeAdminConversationSource(dbOrTx, input.domainId, input.lifeAdminId);
  let issue = conversationSource?.isActive ? conversationSource.issue : null;

  if (!issue) {
    const runIssueId = await dbOrTx
      .select({ contextSnapshot: heartbeatRuns.contextSnapshot })
      .from(heartbeatRuns)
      .where(and(
        eq(heartbeatRuns.domainId, input.domainId),
        eq(heartbeatRuns.id, input.actor.runId),
        eq(heartbeatRuns.agentId, input.actor.agentId),
      ))
      .limit(1)
      .then((rows: Array<{ contextSnapshot: unknown }>) =>
        issueIdFromWorkflowRouteRunContext(rows[0]?.contextSnapshot),
      );

    issue = runIssueId
      ? await dbOrTx
          .select()
          .from(issueRows)
          .where(and(eq(issueRows.domainId, input.domainId), eq(issueRows.id, runIssueId)))
          .limit(1)
          .then((rows: Array<typeof issueRows.$inferSelect>) => rows[0] ?? null)
      : null;
  }

  if (!issue) return null;

  return resolveActorSourceTrustForIssue({
    db: dbOrTx as Db,
    issue: {
      id: issue.id,
      domainId: issue.domainId,
      projectId: issue.projectId,
      executionPolicy: issue.executionPolicy,
    },
    actor: {
      actorType: "agent",
      actorId: input.actor.agentId,
      agentId: input.actor.agentId,
      runId: input.actor.runId,
    },
  });
}

async function assertLifeAdminAccess(db: Db, req: Request, lifeAdminId: string) {
  const domainId = await resolveLifeAdminDomainId(db, lifeAdminId);
  assertWorkflowDomainAccess(req, domainId);
  return domainId;
}

async function getStagesByKey(db: Db, workflowId: string) {
  const rows = await db.select().from(workflowStages).where(eq(workflowStages.workflowId, workflowId));
  return new Map(rows.map((stage) => [stage.key, stage]));
}

async function writeRouteEvent(
  db: Pick<Db, "insert">,
  input: {
    domainId: string;
    lifeAdminId: string;
    type: string;
    actor: WorkflowActor;
    payload?: Record<string, unknown>;
  },
) {
  const actorPatch = input.actor.type === "agent"
    ? { actorType: "agent", actorAgentId: input.actor.agentId, runId: input.actor.runId }
    : input.actor.type === "user"
      ? { actorType: "user", actorUserId: input.actor.userId }
      : { actorType: "system" };
  const [event] = await db.insert(workflowLifeAdminEvents).values({
    domainId: input.domainId,
    lifeAdminId: input.lifeAdminId,
    type: input.type,
    ...actorPatch,
    payload: input.payload ?? {},
  }).returning();
  return event!;
}

async function getIssueMutationTarget(db: Db, input: { domainId: string; issueId: string }) {
  return db
    .select({
      id: issueRows.id,
      domainId: issueRows.domainId,
      projectId: issueRows.projectId,
      parentId: issueRows.parentId,
      assigneeAgentId: issueRows.assigneeAgentId,
      assigneeUserId: issueRows.assigneeUserId,
      status: issueRows.status,
    })
    .from(issueRows)
    .where(and(eq(issueRows.id, input.issueId), eq(issueRows.domainId, input.domainId)))
    .limit(1)
    .then((rows) => rows[0] ?? null);
}

async function assertIssueLinkMutationAllowed(
  req: Request,
  input: {
    access: ReturnType<typeof accessService>;
    issuesSvc: ReturnType<typeof issueService>;
    issue: NonNullable<Awaited<ReturnType<typeof getIssueMutationTarget>>>;
  },
) {
  const decision = await input.access.decide({
    actor: req.actor,
    action: "issue:mutate",
    resource: {
      type: "issue",
      domainId: input.issue.domainId,
      issueId: input.issue.id,
      projectId: input.issue.projectId,
      parentIssueId: input.issue.parentId,
      assigneeAgentId: input.issue.assigneeAgentId,
      assigneeUserId: input.issue.assigneeUserId,
      status: input.issue.status,
    },
    scope: {
      issueId: input.issue.id,
      projectId: input.issue.projectId,
      parentIssueId: input.issue.parentId,
      assigneeAgentId: input.issue.assigneeAgentId,
      assigneeUserId: input.issue.assigneeUserId,
    },
  });
  if (!decision.allowed) {
    throw forbidden("Issue is outside this actor's authorization boundary");
  }
  if (req.actor.type !== "agent") return;
  const actorAgentId = req.actor.agentId;
  if (!actorAgentId) throw forbidden("Agent authentication required");
  if (input.issue.assigneeAgentId === null) return;
  if (input.issue.assigneeAgentId !== actorAgentId) {
    if (input.issue.status === "in_progress") {
      throw conflict("Issue is checked out by another agent", {
        issueId: input.issue.id,
        assigneeAgentId: input.issue.assigneeAgentId,
        actorAgentId,
      });
    }
    throw forbidden("Agent cannot mutate another agent's issue");
  }
  if (input.issue.status !== "in_progress") return;
  const runId = req.actor.runId?.trim();
  if (!runId) throw unauthorized("Agent run id required");
  await input.issuesSvc.assertCheckoutOwner(input.issue.id, actorAgentId, runId);
}

export function workflowRoutes(db: Db, options: Parameters<typeof workflowService>[1] = {}) {
  const router = Router();
  const svc = workflowService(db, options);
  const outputsSvc = workflowLifeAdminOutputsService(db);
  const access = accessService(db);
  const issuesSvc = issueService(db);
  const documentAnnotationsSvc = documentAnnotationService(db);

  router.get("/domains/:domainId/workflows", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertWorkflowDomainAccess(req, domainId);
    const rows = await db
      .select({
        workflow: workflows,
        stageCount: sql<number>`count(distinct ${workflowStages.id})::int`,
        openLifeAdminCount: sql<number>`count(distinct ${workflowLifeAdmin.id}) filter (where ${workflowLifeAdmin.terminalKind} is null)::int`,
        attentionCount: sql<number>`count(distinct ${workflowLifeAdmin.id}) filter (where ${workflowLifeAdmin.terminalKind} is null and (${workflowLifeAdmin.pendingSuggestion} is not null or (${workflowLifeAdmin.stageId} = ${workflowStages.id} and ${workflowStages.kind} = 'review')))::int`,
        inMotionCount: sql<number>`count(distinct ${workflowLifeAdmin.id}) filter (where ${workflowLifeAdmin.terminalKind} is null and ${workflowLifeAdmin.stageId} = ${workflowStages.id} and ${workflowStages.kind} = 'working')::int`,
        lastActivityAt: sql<string | null>`max(${workflowLifeAdmin.updatedAt})`,
      })
      .from(workflows)
      .leftJoin(workflowStages, eq(workflowStages.workflowId, workflows.id))
      .leftJoin(workflowLifeAdmin, eq(workflowLifeAdmin.workflowId, workflows.id))
      .where(eq(workflows.domainId, domainId))
      .groupBy(workflows.id)
      .orderBy(asc(workflows.createdAt));
    const workflowIds = rows.map((row) => row.workflow.id);
    const [connections, descendantActiveWorkCounts, stageRows] = await Promise.all([
      loadWorkflowConnections(db, domainId),
      loadWorkflowDescendantActiveWorkCounts(db, domainId, workflowIds),
      workflowIds.length > 0
        ? db
        .select()
        .from(workflowStages)
        .where(inArray(workflowStages.workflowId, workflowIds))
        .orderBy(asc(workflowStages.position), asc(workflowStages.createdAt))
        : Promise.resolve([]),
    ]);
    const stagesByWorkflowId = new Map<string, typeof stageRows>();
    for (const stage of stageRows) {
      const stages = stagesByWorkflowId.get(stage.workflowId) ?? [];
      stages.push(stage);
      stagesByWorkflowId.set(stage.workflowId, stages);
    }
    res.json(rows.map((row) => ({
      ...row.workflow,
      stageCount: row.stageCount,
      stages: stagesByWorkflowId.get(row.workflow.id) ?? [],
      openLifeAdminCount: row.openLifeAdminCount,
      attentionCount: row.attentionCount,
      inMotionCount: row.inMotionCount,
      descendantActiveWorkCount: descendantActiveWorkCounts.get(row.workflow.id) ?? 0,
      lastActivityAt: row.lastActivityAt,
      connections: connections.get(row.workflow.id) ?? { upstreamWorkflowIds: [], downstreamWorkflowIds: [] },
    })));
  });

  router.get("/domains/:domainId/workflows-attention", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertWorkflowDomainAccess(req, domainId);
    const caller = attentionCallerFor(req);
    const requestedLimit = parseOptionalNonNegativeInteger(req.query.limit, "limit");
    if (requestedLimit === 0) throw badRequest("limit must be a positive integer");
    const limit = Math.min(requestedLimit ?? WORKFLOW_ATTENTION_DEFAULT_LIMIT, WORKFLOW_ATTENTION_MAX_LIMIT);
    res.json(await listWorkflowAttention(db, { domainId, caller, limit }));
  });

  router.get("/domains/:domainId/life_admin-events", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertWorkflowDomainAccess(req, domainId);
    const types = parseEventTypesQuery(req.query.types);
    const requestedLimit = parseOptionalNonNegativeInteger(req.query.limit, "limit");
    if (requestedLimit === 0) throw badRequest("limit must be a positive integer");
    const limit = Math.min(requestedLimit ?? DOMAIN_LIFE_ADMIN_EVENTS_DEFAULT_LIMIT, DOMAIN_LIFE_ADMIN_EVENTS_MAX_LIMIT);
    const offset = parseOptionalNonNegativeInteger(req.query.offset, "offset") ?? 0;
    res.json(await listDomainLifeAdminEvents(db, { domainId, types, limit, offset }));
  });

  router.post("/domains/:domainId/workflows", validate(createWorkflowSchema), async (req, res) => {
    const domainId = req.params.domainId as string;
    assertWorkflowDomainAccess(req, domainId);
    const actor = actorForMutation(req);
    const decision = await access.decide({
      actor: req.actor,
      action: "workflows:write",
      resource: { type: "domain", domainId },
      scope: null,
    });
    if (!decision.allowed) {
      throw new HttpError(403, decision.explanation, {
        code: decision.code ?? "workflow_write_forbidden",
        reason: decision.reason,
      });
    }
    try {
      const created = await svc.createWorkflow({
        domainId,
        key: req.body.key,
        name: req.body.name,
        description: req.body.description,
        projectId: req.body.projectId,
        enforceTransitions: req.body.enforceTransitions,
        stages: req.body.stages?.map((stage: {
          key: string;
          name: string;
          kind: WorkflowStageKind;
          position?: number;
          config?: Record<string, unknown>;
        }) => ({
          ...stage,
          kind: stage.kind as WorkflowStageKind,
          config: stage.config as WorkflowStageConfig | undefined,
        })),
        actor,
      });
      res.status(201).json(created);
    } catch (error) {
      codedConflictForUnique(error);
    }
  });

  router.get("/domains/:domainId/review-life_admin", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertWorkflowDomainAccess(req, domainId);
    const workflowId = typeof req.query.workflowId === "string" ? req.query.workflowId : undefined;
    const parentLifeAdminId = typeof req.query.parentLifeAdminId === "string" ? req.query.parentLifeAdminId : undefined;
    res.json(await svc.listReviewLifeAdmin({ domainId, workflowId, parentLifeAdminId }));
  });

  router.post("/domains/:domainId/review-life_admin/bulk", validate(bulkReviewSchema), async (req, res) => {
    const domainId = req.params.domainId as string;
    assertWorkflowDomainAccess(req, domainId);
    const actor = actorForMutation(req);
    const results = [];
    for (const item of req.body.items) {
      try {
        results.push({ lifeAdminId: item.lifeAdminId, ok: true, result: await svc.reviewLifeAdmin({ domainId, ...item, actor }) });
      } catch (error) {
        const httpError = error as { status?: number; message?: string; details?: unknown };
        const details = httpError.details && typeof httpError.details === "object" && !Array.isArray(httpError.details)
          ? httpError.details as Record<string, unknown>
          : null;
        results.push({
          lifeAdminId: item.lifeAdminId,
          ok: false,
          error: {
            status: httpError.status ?? 500,
            message: httpError.message ?? "Unknown error",
            code: typeof details?.code === "string" ? details.code : undefined,
            details: httpError.details,
          },
        });
      }
    }
    res.json({ results });
  });

  router.get("/workflows/:workflowId", async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    const [workflow, stages, transitions, documentKeys] = await Promise.all([
      db.select().from(workflows).where(and(eq(workflows.id, workflowId), eq(workflows.domainId, domainId))).then((rows) => rows[0] ?? null),
      db.select().from(workflowStages).where(eq(workflowStages.workflowId, workflowId)).orderBy(asc(workflowStages.position)),
      db.select().from(workflowTransitions).where(eq(workflowTransitions.workflowId, workflowId)),
      db.select({ key: workflowDocuments.key, documentId: workflowDocuments.documentId })
        .from(workflowDocuments)
        .where(and(eq(workflowDocuments.domainId, domainId), eq(workflowDocuments.workflowId, workflowId))),
    ]);
    if (!workflow) throw notFound("Workflow not found");
    const automationRoutineIds = stages.flatMap((stage) => {
      const routineId = stageAutomationRoutineId(stage.config);
      return routineId ? [routineId] : [];
    });
    const routineRows = automationRoutineIds.length > 0
      ? await db
          .select({
            id: routines.id,
            assigneeAgentId: routines.assigneeAgentId,
            title: routines.title,
            description: routines.description,
            env: routines.env,
            latestRevisionId: routines.latestRevisionId,
            latestRevisionNumber: routines.latestRevisionNumber,
          })
          .from(routines)
          .where(and(eq(routines.domainId, domainId), inArray(routines.id, automationRoutineIds)))
      : [];
    const routineById = new Map(routineRows.map((row) => [
      row.id,
      {
        assigneeAgentId: row.assigneeAgentId,
        title: row.title,
        description: row.description,
        env: row.env,
        latestRevisionId: row.latestRevisionId,
        latestRevisionNumber: row.latestRevisionNumber,
      },
    ]));
    res.json({ ...workflow, stages: stages.map((stage) => withDerivedStageAutomation(stage, routineById)), transitions, documentKeys });
  });

  // Setup-health warnings: surface any configuration that won't actually run
  // (paused teammate, missing instructions, no approver, broken hand-off links,
  // unset required details) in plain prosumer language. Assembles the cross-
  // entity inputs the pure `computeWorkflowHealth` needs.
  router.get("/workflows/:workflowId/health", async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    const [workflow, stages, instructionDocs, domainAgents, domainWorkflows, domainStages, failedAutomationRows] = await Promise.all([
      db.select().from(workflows)
        .where(and(eq(workflows.id, workflowId), eq(workflows.domainId, domainId)))
        .then((rows) => rows[0] ?? null),
      db.select().from(workflowStages).where(eq(workflowStages.workflowId, workflowId)).orderBy(asc(workflowStages.position)),
      db.select({ key: workflowDocuments.key, body: documentRevisions.body })
        .from(workflowDocuments)
        .innerJoin(documents, eq(workflowDocuments.documentId, documents.id))
        .leftJoin(documentRevisions, eq(documents.latestRevisionId, documentRevisions.id))
        .where(and(
          eq(workflowDocuments.domainId, domainId),
          eq(workflowDocuments.workflowId, workflowId),
          ilike(workflowDocuments.key, `${STAGE_INSTRUCTIONS_PREFIX}%`),
        )),
      db.select({ id: agents.id, name: agents.name, status: agents.status })
        .from(agents)
        .where(eq(agents.domainId, domainId)),
      db.select({ id: workflows.id, name: workflows.name })
        .from(workflows)
        .where(eq(workflows.domainId, domainId)),
      db.select({
        workflowId: workflowStages.workflowId,
        key: workflowStages.key,
        name: workflowStages.name,
        kind: workflowStages.kind,
        config: workflowStages.config,
      })
        .from(workflowStages)
        .innerJoin(workflows, eq(workflowStages.workflowId, workflows.id))
        .where(eq(workflows.domainId, domainId))
        .orderBy(asc(workflowStages.position), asc(workflowStages.createdAt)),
      db.select({
        lifeAdminId: workflowLifeAdmin.id,
        life_adminTitle: workflowLifeAdmin.title,
        stageId: workflowStages.id,
        stageKey: workflowStages.key,
        stageName: workflowStages.name,
        error: workflowAutomationExecutions.error,
      })
        .from(workflowAutomationExecutions)
        .innerJoin(workflowLifeAdmin, eq(workflowAutomationExecutions.lifeAdminId, workflowLifeAdmin.id))
        .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
        .where(and(
          eq(workflowAutomationExecutions.domainId, domainId),
          eq(workflowLifeAdmin.workflowId, workflowId),
          eq(workflowAutomationExecutions.status, "failed"),
          isNull(workflowLifeAdmin.terminalKind),
        ))
        .orderBy(desc(workflowAutomationExecutions.updatedAt))
        .limit(50),
    ]);
    if (!workflow) throw notFound("Workflow not found");

    const automationRoutineIds = stages.flatMap((stage) => {
      const routineId = stageAutomationRoutineId(stage.config);
      return routineId ? [routineId] : [];
    });
    const routineRows = automationRoutineIds.length > 0
      ? await db
          .select({
            id: routines.id,
            assigneeAgentId: routines.assigneeAgentId,
            title: routines.title,
            description: routines.description,
            env: routines.env,
            latestRevisionId: routines.latestRevisionId,
            latestRevisionNumber: routines.latestRevisionNumber,
          })
          .from(routines)
          .where(and(eq(routines.domainId, domainId), inArray(routines.id, automationRoutineIds)))
      : [];
    const routineById = new Map(routineRows.map((row) => [
      row.id,
      {
        assigneeAgentId: row.assigneeAgentId,
        title: row.title,
        description: row.description,
        env: row.env,
        latestRevisionId: row.latestRevisionId,
        latestRevisionNumber: row.latestRevisionNumber,
      },
    ]));

    const bodyByStageId = new Map<string, string>();
    for (const doc of instructionDocs) {
      if (!doc.key.startsWith(STAGE_INSTRUCTIONS_PREFIX)) continue;
      bodyByStageId.set(doc.key.slice(STAGE_INSTRUCTIONS_PREFIX.length), doc.body ?? "");
    }

    const agentsById: Record<string, { id: string; name: string | null; status: string }> = {};
    for (const agent of domainAgents) agentsById[agent.id] = agent;

    const stagesByWorkflowId = new Map<string, Array<{ key: string; name: string; kind: string; config: Record<string, unknown> | null }>>();
    for (const stage of domainStages) {
      const list = stagesByWorkflowId.get(stage.workflowId) ?? [];
      list.push({
        key: stage.key,
        name: stage.name,
        kind: stage.kind,
        config: (stage.config ?? null) as Record<string, unknown> | null,
      });
      stagesByWorkflowId.set(stage.workflowId, list);
    }
    const workflowsById: Record<string, { id: string; name: string; stages: Array<{ key: string; name: string; kind: string; config: Record<string, unknown> | null }> }> = {};
    for (const p of domainWorkflows) {
      workflowsById[p.id] = { id: p.id, name: p.name, stages: stagesByWorkflowId.get(p.id) ?? [] };
    }

    const healthStages: WorkflowHealthStageInput[] = stages.map((stage) => {
      const stageWithAutomation = withDerivedStageAutomation(stage, routineById);
      const automation = (stageWithAutomation.config as { automation?: { instructionsBody?: string | null } }).automation;
      return {
        id: stage.id,
        key: stage.key,
        name: stage.name,
        kind: stage.kind,
        config: (stageWithAutomation.config ?? null) as Record<string, unknown> | null,
        instructionsBody: automation?.instructionsBody ?? bodyByStageId.get(stage.id) ?? "",
      };
    });
    const failedAutomations: WorkflowHealthFailedAutomationInput[] = failedAutomationRows.map((row) => ({
      stageId: row.stageId,
      stageKey: row.stageKey,
      stageName: row.stageName,
      lifeAdminId: row.lifeAdminId,
      life_adminTitle: row.life_adminTitle,
      error: row.error,
    }));

    res.json(computeWorkflowHealth({ workflowId, stages: healthStages, agentsById, workflowsById, failedAutomations }));
  });

  router.get("/workflows/:workflowId/intake-form", async (req, res) => {
    const workflowId = req.params.workflowId as string;
    await assertWorkflowAccess(db, req, workflowId);
    const firstStage = await db
      .select()
      .from(workflowStages)
      .where(eq(workflowStages.workflowId, workflowId))
      .orderBy(asc(workflowStages.position), asc(workflowStages.createdAt))
      .limit(1)
      .then((rows) => rows[0] ?? null);
    res.json({
      workflowId,
      stageId: firstStage?.id ?? null,
      stageName: firstStage?.name ?? null,
      fields: extractIntakeFormFields(firstStage),
    });
  });

  router.patch("/workflows/:workflowId", validate(updateWorkflowSchema), async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    actorForMutation(req);
    const patch: Partial<typeof workflows.$inferInsert> = { updatedAt: new Date() };
    if (req.body.name !== undefined) patch.name = req.body.name;
    if (req.body.description !== undefined) patch.description = req.body.description;
    if (req.body.enforceTransitions !== undefined) patch.enforceTransitions = req.body.enforceTransitions;
    if (req.body.archived !== undefined) patch.archivedAt = req.body.archived ? new Date() : null;
    const [updated] = await db
      .update(workflows)
      .set(patch)
      .where(and(eq(workflows.id, workflowId), eq(workflows.domainId, domainId)))
      .returning();
    res.json(updated);
  });

  router.post("/workflows/:workflowId/stages", validate(createStageSchema), async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);
    try {
      const stage = await svc.createStage({
        domainId,
        workflowId,
        key: req.body.key,
        name: req.body.name,
        kind: req.body.kind,
        position: req.body.position,
        config: req.body.config,
        actor,
      });
      res.status(201).json(stage);
    } catch (error) {
      codedConflictForUnique(error);
    }
  });

  router.patch("/workflows/:workflowId/stages/:stageId", validate(updateStageSchema), async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const stageId = req.params.stageId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);
    try {
      res.json(await svc.updateStage({ domainId, workflowId, stageId, patch: req.body, actor }));
    } catch (error) {
      codedConflictForUnique(error);
    }
  });

  router.patch("/workflows/:workflowId/stages/:stageId/automation-env", validate(updateStageAutomationEnvSchema), async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const stageId = req.params.stageId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);
    res.json(await svc.updateStageAutomationEnv({
      domainId,
      workflowId,
      stageId,
      env: req.body.env,
      baseRoutineRevisionId: req.body.baseRoutineRevisionId ?? null,
      actor,
    }));
  });

  router.delete("/workflows/:workflowId/stages/:stageId", async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const stageId = req.params.stageId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);
    const result = await svc.deleteStage({
      domainId,
      workflowId,
      stageId,
      moveLifeAdminToStageId: typeof req.query.moveLifeAdminToStageId === "string" ? req.query.moveLifeAdminToStageId : null,
      actor,
    });
    res.json(result);
  });

  router.put("/workflows/:workflowId/transitions", validate(replaceTransitionsSchema), async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    actorForMutation(req);
    const byKey = await getStagesByKey(db, workflowId);
    const transitions = req.body.transitions.map((edge: z.infer<typeof replaceTransitionsSchema>["transitions"][number]) => {
      const from = byKey.get(edge.fromStageKey);
      const to = byKey.get(edge.toStageKey);
      if (!from || !to) throw unprocessable("Transition references unknown stage", { code: "validation" });
      return { workflowId, fromStageId: from.id, toStageId: to.id, label: edge.label ?? null };
    });
    const result = await db.transaction(async (tx) => {
      await tx.delete(workflowTransitions).where(eq(workflowTransitions.workflowId, workflowId));
      if (req.body.enforceTransitions !== undefined) {
        await tx.update(workflows).set({ enforceTransitions: req.body.enforceTransitions, updatedAt: new Date() })
          .where(and(eq(workflows.id, workflowId), eq(workflows.domainId, domainId)));
      }
      return transitions.length ? tx.insert(workflowTransitions).values(transitions).returning() : [];
    });
    res.json({ transitions: result });
  });

  router.get("/workflows/:workflowId/documents/:key", async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const key = req.params.key as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    const row = await getWorkflowDocumentRow(db, { domainId, workflowId, key });
    if (!row) throw notFound("Workflow document not found");
    res.json(row);
  });

  router.put("/workflows/:workflowId/documents/:key", validate(upsertWorkflowDocumentSchema), async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const key = req.params.key as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);
    const result = await db.transaction(async (tx) => {
      const existing = await tx
        .select({ link: workflowDocuments, document: documents, revision: documentRevisions })
        .from(workflowDocuments)
        .innerJoin(documents, eq(workflowDocuments.documentId, documents.id))
        .leftJoin(documentRevisions, eq(documents.latestRevisionId, documentRevisions.id))
        .where(and(eq(workflowDocuments.domainId, domainId), eq(workflowDocuments.workflowId, workflowId), eq(workflowDocuments.key, key)))
        .limit(1)
        .then((rows) => rows[0] ?? null);

      if (existing && req.body.baseRevisionId && req.body.baseRevisionId !== existing.document.latestRevisionId) {
        throw conflict("Workflow document was updated by someone else", {
          code: "stale_base_revision",
          latestRevision: existing.revision
            ? {
                id: existing.revision.id,
                revisionNumber: existing.revision.revisionNumber,
                title: existing.revision.title,
                createdAt: existing.revision.createdAt,
                createdByAgentId: existing.revision.createdByAgentId,
                createdByUserId: existing.revision.createdByUserId,
              }
            : null,
          latestRevisionId: existing.document.latestRevisionId,
          latestRevisionNumber: existing.document.latestRevisionNumber,
        });
      }

      if (!existing && req.body.baseRevisionId) {
        throw conflict("Workflow document does not exist yet", {
          code: "stale_base_revision",
          latestRevision: null,
          latestRevisionId: null,
          latestRevisionNumber: null,
        });
      }

      const now = new Date();
      const [document] = existing
        ? await tx.update(documents).set({
          title: req.body.title ?? key,
          updatedAt: now,
          updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
          updatedByUserId: actor.type === "user" ? actor.userId : null,
        }).where(eq(documents.id, existing.document.id)).returning()
        : await tx.insert(documents).values({
          domainId,
          title: req.body.title ?? key,
          latestBody: req.body.body,
          latestRevisionNumber: 1,
          createdByAgentId: actor.type === "agent" ? actor.agentId : null,
          createdByUserId: actor.type === "user" ? actor.userId : null,
          updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
          updatedByUserId: actor.type === "user" ? actor.userId : null,
        }).returning();
      const [revision] = await tx.insert(documentRevisions).values({
        domainId,
        documentId: document!.id,
        revisionNumber: existing ? existing.document.latestRevisionNumber + 1 : 1,
        title: req.body.title ?? document!.title,
        body: req.body.body,
        createdByAgentId: actor.type === "agent" ? actor.agentId : null,
        createdByUserId: actor.type === "user" ? actor.userId : null,
        createdByRunId: actor.type === "agent" ? actor.runId : null,
        createdAt: now,
      }).returning();
      await tx.update(documents).set({
        latestBody: req.body.body,
        latestRevisionId: revision!.id,
        latestRevisionNumber: revision!.revisionNumber,
        updatedAt: now,
        updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
        updatedByUserId: actor.type === "user" ? actor.userId : null,
      }).where(eq(documents.id, document!.id));
      if (!existing) {
        await tx.insert(workflowDocuments).values({ domainId, workflowId, documentId: document!.id, key, createdAt: now, updatedAt: now });
      } else {
        await tx.update(workflowDocuments).set({ updatedAt: now }).where(eq(workflowDocuments.documentId, document!.id));
      }
      return {
        document: {
          ...document!,
          latestBody: req.body.body,
          latestRevisionId: revision!.id,
          latestRevisionNumber: revision!.revisionNumber,
          updatedAt: now,
          updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
          updatedByUserId: actor.type === "user" ? actor.userId : null,
        },
        revision,
      };
    });
    res.json(result);
  });

  router.get("/workflows/:workflowId/documents/:key/revisions", async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const key = req.params.key as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    const revisions = await listWorkflowDocumentRevisions(db, { domainId, workflowId, key });
    res.json(revisions);
  });

  router.post("/workflows/:workflowId/documents/:key/revisions/:revisionId/restore", async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const key = req.params.key as string;
    const revisionId = req.params.revisionId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);

    const result = await db.transaction(async (tx) => {
      const existing = await tx
        .select({ link: workflowDocuments, document: documents, revision: documentRevisions })
        .from(workflowDocuments)
        .innerJoin(documents, eq(workflowDocuments.documentId, documents.id))
        .leftJoin(documentRevisions, eq(documents.latestRevisionId, documentRevisions.id))
        .where(and(eq(workflowDocuments.domainId, domainId), eq(workflowDocuments.workflowId, workflowId), eq(workflowDocuments.key, key)))
        .limit(1)
        .then((rows) => rows[0] ?? null);
      if (!existing) throw notFound("Workflow document not found");

      const sourceRevision = await tx
        .select()
        .from(documentRevisions)
        .where(and(eq(documentRevisions.id, revisionId), eq(documentRevisions.documentId, existing.document.id)))
        .limit(1)
        .then((rows) => rows[0] ?? null);
      if (!sourceRevision) throw notFound("Workflow document revision not found");

      if (existing.document.latestRevisionId === sourceRevision.id) {
        throw conflict("Selected revision is already the latest revision", {
          currentRevisionId: existing.document.latestRevisionId,
        });
      }

      const now = new Date();
      const nextRevisionNumber = existing.document.latestRevisionNumber + 1;
      const [restoredRevision] = await tx.insert(documentRevisions).values({
        domainId,
        documentId: existing.document.id,
        revisionNumber: nextRevisionNumber,
        title: sourceRevision.title ?? null,
        format: sourceRevision.format,
        body: sourceRevision.body,
        changeSummary: `Restored from revision ${sourceRevision.revisionNumber}`,
        createdByAgentId: actor.type === "agent" ? actor.agentId : null,
        createdByUserId: actor.type === "user" ? actor.userId : null,
        createdByRunId: actor.type === "agent" ? actor.runId : null,
        createdAt: now,
      }).returning();

      const [document] = await tx.update(documents).set({
        title: sourceRevision.title ?? null,
        format: sourceRevision.format,
        latestBody: sourceRevision.body,
        latestRevisionId: restoredRevision!.id,
        latestRevisionNumber: nextRevisionNumber,
        updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
        updatedByUserId: actor.type === "user" ? actor.userId : null,
        updatedAt: now,
      }).where(eq(documents.id, existing.document.id)).returning();

      await tx.update(workflowDocuments).set({ updatedAt: now }).where(eq(workflowDocuments.documentId, existing.document.id));

      return {
        document: { ...document!, latestRevisionId: restoredRevision!.id },
        revision: restoredRevision!,
        restoredFromRevisionId: sourceRevision.id,
        restoredFromRevisionNumber: sourceRevision.revisionNumber,
      };
    });

    res.json(result);
  });

  router.post("/workflows/:workflowId/life_admin", validate(ingestLifeAdminSchema), async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);
    const result = await svc.ingestLifeAdmin({ domainId, workflowId, ...req.body, actor });
    res.status(result.created ? 201 : 200).json(result);
  });

  router.post("/workflows/:workflowId/life_admin/batch", validate(batchIngestSchema), async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);
    res.json(await svc.ingestLifeAdmin({ domainId, workflowId, items: req.body.items, actor }));
  });

  router.post("/life_admin/:lifeAdminId/breakdown", validate(breakdownLifeAdminSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const target = await svc.resolveBreakdownTarget({ domainId, lifeAdminId });
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId: target.targetWorkflow.id });
    const actor = actorForMutation(req);
    res.json(await svc.breakdownLifeAdmin({ domainId, lifeAdminId, items: req.body.items, actor }));
  });

  router.get("/workflows/:workflowId/life_admin", async (req, res) => {
    const workflowId = req.params.workflowId as string;
    const domainId = await assertWorkflowAccess(db, req, workflowId);
    const stageKey = typeof req.query.stageKey === "string" ? req.query.stageKey : undefined;
    const q = typeof req.query.q === "string" ? req.query.q : undefined;
    const terminal = req.query.terminal === "true" ? true : req.query.terminal === "false" ? false : undefined;
    const includeRetired = req.query.includeRetired === "true";
    const parentLifeAdminId = typeof req.query.parentLifeAdminId === "string" ? req.query.parentLifeAdminId : undefined;
    const parentLifeAdmin = alias(workflowLifeAdmin, "parent_life_admin");
    const parentWorkflow = alias(workflows, "parent_workflow");
    const rows = await db
      .select({
        life_admin: workflowLifeAdmin,
        stage: workflowStages,
        parentLifeAdmin: {
          id: parentLifeAdmin.id,
          life_adminKey: parentLifeAdmin.life_adminKey,
          title: parentLifeAdmin.title,
          workflowId: parentLifeAdmin.workflowId,
        },
        parentWorkflow: {
          id: parentWorkflow.id,
          key: parentWorkflow.key,
          name: parentWorkflow.name,
        },
      })
      .from(workflowLifeAdmin)
      .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
      .leftJoin(parentLifeAdmin, and(
        eq(parentLifeAdmin.domainId, domainId),
        eq(parentLifeAdmin.id, workflowLifeAdmin.parentLifeAdminId),
      ))
      .leftJoin(parentWorkflow, and(
        eq(parentWorkflow.domainId, domainId),
        eq(parentWorkflow.id, parentLifeAdmin.workflowId),
      ))
      .where(and(
        eq(workflowLifeAdmin.domainId, domainId),
        eq(workflowLifeAdmin.workflowId, workflowId),
        stageKey ? eq(workflowStages.key, stageKey) : undefined,
        parentLifeAdminId ? eq(workflowLifeAdmin.parentLifeAdminId, parentLifeAdminId) : undefined,
        includeRetired ? undefined : isNull(workflowLifeAdmin.hiddenFromBoardAt),
        terminal === true ? isNotNull(workflowLifeAdmin.terminalKind) : terminal === false ? isNull(workflowLifeAdmin.terminalKind) : undefined,
        q ? or(ilike(workflowLifeAdmin.title, `%${q}%`), ilike(workflowLifeAdmin.summary, `%${q}%`)) : undefined,
      ))
      .orderBy(asc(workflowLifeAdmin.createdAt));
    const lifeAdminIds = rows.map((row) => row.life_admin.id);
    const [activeWork, descendantActiveWorkCounts] = await Promise.all([
      loadActiveWorkForLifeAdmin(db, domainId, lifeAdminIds),
      loadDescendantActiveWorkCountsForLifeAdmin(db, domainId, lifeAdminIds),
    ]);
    res.json(rows.map((row) => ({
      life_admin: row.life_admin,
      stage: row.stage,
      parentLifeAdmin: row.parentLifeAdmin?.id && row.parentWorkflow?.id
        ? {
            life_admin: row.parentLifeAdmin,
            workflow: row.parentWorkflow,
          }
        : null,
      activeWork: activeWork.get(row.life_admin.id) ?? null,
      descendantActiveWorkCount: descendantActiveWorkCounts.get(row.life_admin.id) ?? 0,
    })));
  });

  router.get("/life_admin/:lifeAdminId", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const detail = await getLifeAdminDetail(db, domainId, lifeAdminId);
    res.json(detail);
  });

  router.get("/life_admin/:lifeAdminId/documents/:key", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const key = parseDocumentKey(req.params.key);
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const row = await db.transaction(async (tx) => {
      const existing = await getWorkflowLifeAdminDocumentRow(tx, { domainId, lifeAdminId, key });
      if (existing || key !== "body") return existing;
      const lifeAdminRow = await tx
        .select({ summary: workflowLifeAdmin.summary })
        .from(workflowLifeAdmin)
        .where(and(eq(workflowLifeAdmin.domainId, domainId), eq(workflowLifeAdmin.id, lifeAdminId)))
        .limit(1)
        .then((rows) => rows[0] ?? null);
      if (!lifeAdminRow?.summary?.trim()) return null;
      await ensureWorkflowLifeAdminBodyDocumentFromSummary(tx, {
        domainId,
        lifeAdminId,
        summary: lifeAdminRow.summary,
        actor: { type: "system" },
      });
      return getWorkflowLifeAdminDocumentRow(tx, { domainId, lifeAdminId, key });
    });
    if (!row) throw notFound("Workflow life_admin document not found");
    res.json(row);
  });

  router.put("/life_admin/:lifeAdminId/documents/:key", validate(upsertWorkflowLifeAdminDocumentSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const key = parseDocumentKey(req.params.key);
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const workflowId = await resolveLifeAdminWorkflowId(db, { domainId, lifeAdminId });
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);
    const sourceTrust = await sourceTrustForWorkflowLifeAdminDocumentWrite(db, { domainId, lifeAdminId, actor });

    const result = await db.transaction(async (tx) => {
      const existing = await tx
        .select({ link: workflowLifeAdminDocuments, document: documents, revision: documentRevisions })
        .from(workflowLifeAdminDocuments)
        .innerJoin(documents, eq(workflowLifeAdminDocuments.documentId, documents.id))
        .leftJoin(documentRevisions, eq(documents.latestRevisionId, documentRevisions.id))
        .where(and(
          eq(workflowLifeAdminDocuments.domainId, domainId),
          eq(workflowLifeAdminDocuments.lifeAdminId, lifeAdminId),
          eq(workflowLifeAdminDocuments.key, key),
        ))
        .limit(1)
        .then((rows) => rows[0] ?? null);

      if (existing && !req.body.baseRevisionId) {
        throw conflict("Workflow life_admin document update requires baseRevisionId", {
          code: "stale_base_revision",
          latestRevisionId: existing.document.latestRevisionId,
          latestRevisionNumber: existing.document.latestRevisionNumber,
        });
      }
      if (existing && req.body.baseRevisionId !== existing.document.latestRevisionId) {
        throw conflict("Workflow life_admin document was updated by someone else", {
          code: "stale_base_revision",
          latestRevision: existing.revision
            ? {
              id: existing.revision.id,
              revisionNumber: existing.revision.revisionNumber,
              title: existing.revision.title,
              createdAt: existing.revision.createdAt,
              createdByAgentId: existing.revision.createdByAgentId,
              createdByUserId: existing.revision.createdByUserId,
            }
            : null,
          latestRevisionId: existing.document.latestRevisionId,
          latestRevisionNumber: existing.document.latestRevisionNumber,
        });
      }
      if (!existing && req.body.baseRevisionId) {
        throw conflict("Workflow life_admin document does not exist yet", {
          code: "stale_base_revision",
          latestRevision: null,
          latestRevisionId: null,
          latestRevisionNumber: null,
        });
      }

      const now = new Date();
      const [document] = existing
        ? await tx.update(documents).set({
          title: req.body.title ?? existing.document.title,
          format: req.body.format,
          updatedAt: now,
          updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
          updatedByUserId: actor.type === "user" ? actor.userId : null,
          sourceTrust,
        }).where(eq(documents.id, existing.document.id)).returning()
        : await tx.insert(documents).values({
          domainId,
          title: req.body.title ?? key,
          format: req.body.format,
          latestBody: req.body.body,
          latestRevisionNumber: 1,
          createdByAgentId: actor.type === "agent" ? actor.agentId : null,
          createdByUserId: actor.type === "user" ? actor.userId : null,
          updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
          updatedByUserId: actor.type === "user" ? actor.userId : null,
          sourceTrust,
          createdAt: now,
          updatedAt: now,
        }).returning();
      const nextRevisionNumber = existing ? existing.document.latestRevisionNumber + 1 : 1;
      const [revision] = await tx.insert(documentRevisions).values({
        domainId,
        documentId: document!.id,
        revisionNumber: nextRevisionNumber,
        title: req.body.title ?? document!.title,
        format: req.body.format,
        body: req.body.body,
        changeSummary: req.body.changeSummary ?? null,
        createdByAgentId: actor.type === "agent" ? actor.agentId : null,
        createdByUserId: actor.type === "user" ? actor.userId : null,
        createdByRunId: actor.type === "agent" ? actor.runId : null,
        createdAt: now,
      }).returning();
      await tx.update(documents).set({
        title: req.body.title ?? document!.title,
        format: req.body.format,
        latestBody: req.body.body,
        latestRevisionId: revision!.id,
        latestRevisionNumber: revision!.revisionNumber,
        updatedAt: now,
        updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
        updatedByUserId: actor.type === "user" ? actor.userId : null,
        sourceTrust,
      }).where(eq(documents.id, document!.id));
      if (!existing) {
        await tx.insert(workflowLifeAdminDocuments).values({ domainId, lifeAdminId, documentId: document!.id, key, createdAt: now, updatedAt: now });
      } else {
        await tx.update(workflowLifeAdminDocuments).set({ updatedAt: now }).where(eq(workflowLifeAdminDocuments.documentId, document!.id));
      }

      if (key === "body") {
        const conversationSource = await resolveWorkflowLifeAdminConversationSource(tx, domainId, lifeAdminId);
        if (conversationSource?.isActive) {
          await tx.insert(issueDocuments).values({
            domainId,
            issueId: conversationSource.issue.id,
            documentId: document!.id,
            key: WORKFLOW_LIFE_ADMIN_BODY_DOCUMENT_KEY,
            createdAt: now,
            updatedAt: now,
          }).onConflictDoUpdate({
            target: [issueDocuments.domainId, issueDocuments.issueId, issueDocuments.key],
            set: { documentId: document!.id, updatedAt: now },
          });
        }
      }

      const linkedIssueDocuments = await tx
        .select({ issueId: issueDocuments.issueId, key: issueDocuments.key })
        .from(issueDocuments)
        .where(and(eq(issueDocuments.domainId, domainId), eq(issueDocuments.documentId, document!.id)));

      return {
        created: !existing,
        document: {
          ...document!,
          title: req.body.title ?? document!.title,
          format: req.body.format,
          latestBody: req.body.body,
          latestRevisionId: revision!.id,
          latestRevisionNumber: revision!.revisionNumber,
          updatedAt: now,
          updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
          updatedByUserId: actor.type === "user" ? actor.userId : null,
          sourceTrust,
        },
        revision,
        linkedIssueDocuments,
      };
    });

    if (!result.created) {
      await Promise.all(result.linkedIssueDocuments.map((link) =>
        documentAnnotationsSvc.remapOpenThreadsForDocument({
          issueId: link.issueId,
          key: link.key,
          documentId: result.document.id,
          nextRevisionId: result.document.latestRevisionId,
          nextRevisionNumber: result.document.latestRevisionNumber,
          nextBody: result.document.latestBody,
        })
      ));
    }
    await logActivity(db, {
      domainId,
      ...activityActorForWorkflowRoute(actor),
      action: result.created ? "workflow.life_admin_document_created" : "workflow.life_admin_document_updated",
      entityType: "workflow_life_admin",
      entityId: lifeAdminId,
      details: {
        key,
        documentId: result.document.id,
        revisionId: result.revision!.id,
        revisionNumber: result.revision!.revisionNumber,
        linkedIssueIds: result.linkedIssueDocuments.map((link) => link.issueId),
      },
    });
    res.json({ document: result.document, revision: result.revision });
  });

  router.get("/life_admin/:lifeAdminId/documents/:key/revisions", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const key = parseDocumentKey(req.params.key);
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const revisions = await listWorkflowLifeAdminDocumentRevisions(db, { domainId, lifeAdminId, key });
    res.json(revisions);
  });

  router.post("/life_admin/:lifeAdminId/documents/:key/revisions/:revisionId/restore", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const key = parseDocumentKey(req.params.key);
    const revisionId = req.params.revisionId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const workflowId = await resolveLifeAdminWorkflowId(db, { domainId, lifeAdminId });
    await assertWorkflowWriteAccess(req, { access, domainId, workflowId });
    const actor = actorForMutation(req);

    const result = await db.transaction(async (tx) => {
      const existing = await tx
        .select({ link: workflowLifeAdminDocuments, document: documents, revision: documentRevisions })
        .from(workflowLifeAdminDocuments)
        .innerJoin(documents, eq(workflowLifeAdminDocuments.documentId, documents.id))
        .leftJoin(documentRevisions, eq(documents.latestRevisionId, documentRevisions.id))
        .where(and(
          eq(workflowLifeAdminDocuments.domainId, domainId),
          eq(workflowLifeAdminDocuments.lifeAdminId, lifeAdminId),
          eq(workflowLifeAdminDocuments.key, key),
        ))
        .limit(1)
        .then((rows) => rows[0] ?? null);
      if (!existing) throw notFound("Workflow life_admin document not found");

      const sourceRevision = await tx
        .select()
        .from(documentRevisions)
        .where(and(eq(documentRevisions.id, revisionId), eq(documentRevisions.documentId, existing.document.id)))
        .limit(1)
        .then((rows) => rows[0] ?? null);
      if (!sourceRevision) throw notFound("Workflow life_admin document revision not found");
      if (existing.document.latestRevisionId === sourceRevision.id) {
        throw conflict("Selected revision is already the latest revision", {
          currentRevisionId: existing.document.latestRevisionId,
        });
      }

      const now = new Date();
      const nextRevisionNumber = existing.document.latestRevisionNumber + 1;
      const [restoredRevision] = await tx.insert(documentRevisions).values({
        domainId,
        documentId: existing.document.id,
        revisionNumber: nextRevisionNumber,
        title: sourceRevision.title ?? null,
        format: sourceRevision.format,
        body: sourceRevision.body,
        changeSummary: `Restored from revision ${sourceRevision.revisionNumber}`,
        createdByAgentId: actor.type === "agent" ? actor.agentId : null,
        createdByUserId: actor.type === "user" ? actor.userId : null,
        createdByRunId: actor.type === "agent" ? actor.runId : null,
        createdAt: now,
      }).returning();
      const [document] = await tx.update(documents).set({
        title: sourceRevision.title ?? null,
        format: sourceRevision.format,
        latestBody: sourceRevision.body,
        latestRevisionId: restoredRevision!.id,
        latestRevisionNumber: nextRevisionNumber,
        updatedByAgentId: actor.type === "agent" ? actor.agentId : null,
        updatedByUserId: actor.type === "user" ? actor.userId : null,
        updatedAt: now,
      }).where(eq(documents.id, existing.document.id)).returning();
      await tx.update(workflowLifeAdminDocuments).set({ updatedAt: now }).where(eq(workflowLifeAdminDocuments.documentId, existing.document.id));

      const linkedIssueDocuments = await tx
        .select({ issueId: issueDocuments.issueId, key: issueDocuments.key })
        .from(issueDocuments)
        .where(and(eq(issueDocuments.domainId, domainId), eq(issueDocuments.documentId, existing.document.id)));

      return {
        document: document!,
        revision: restoredRevision!,
        restoredFromRevisionId: sourceRevision.id,
        restoredFromRevisionNumber: sourceRevision.revisionNumber,
        linkedIssueDocuments,
      };
    });

    await Promise.all(result.linkedIssueDocuments.map((link) =>
      documentAnnotationsSvc.remapOpenThreadsForDocument({
        issueId: link.issueId,
        key: link.key,
        documentId: result.document.id,
        nextRevisionId: result.document.latestRevisionId,
        nextRevisionNumber: result.document.latestRevisionNumber,
        nextBody: result.document.latestBody,
      })
    ));
    await logActivity(db, {
      domainId,
      ...activityActorForWorkflowRoute(actor),
      action: "workflow.life_admin_document_restored",
      entityType: "workflow_life_admin",
      entityId: lifeAdminId,
      details: {
        key,
        documentId: result.document.id,
        revisionId: result.revision.id,
        revisionNumber: result.revision.revisionNumber,
        restoredFromRevisionId: result.restoredFromRevisionId,
        restoredFromRevisionNumber: result.restoredFromRevisionNumber,
        linkedIssueIds: result.linkedIssueDocuments.map((link) => link.issueId),
      },
    });
    res.json(result);
  });

  // Direct children of a life_admin, scoped by parent rather than workflow. Children can be
  // parented across workflows (release -> feature -> content trees), so this must not
  // filter by a single workflowId the way GET /workflows/:workflowId/life_admin does — that
  // filter hides cross-workflow children even though childCount counts them.
  router.get("/life_admin/:lifeAdminId/children", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const rows = await db
      .select({ life_admin: workflowLifeAdmin, stage: workflowStages })
      .from(workflowLifeAdmin)
      .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
      .where(and(
        eq(workflowLifeAdmin.domainId, domainId),
        eq(workflowLifeAdmin.parentLifeAdminId, lifeAdminId),
        isNull(workflowLifeAdmin.hiddenFromBoardAt),
      ))
      .orderBy(asc(workflowLifeAdmin.createdAt));
    const lifeAdminIds = rows.map((row) => row.life_admin.id);
    const [activeWork, descendantActiveWorkCounts] = await Promise.all([
      loadActiveWorkForLifeAdmin(db, domainId, lifeAdminIds),
      loadDescendantActiveWorkCountsForLifeAdmin(db, domainId, lifeAdminIds),
    ]);
    res.json(rows.map((row) => ({
      ...row,
      activeWork: activeWork.get(row.life_admin.id) ?? null,
      descendantActiveWorkCount: descendantActiveWorkCounts.get(row.life_admin.id) ?? 0,
    })));
  });

  router.patch("/life_admin/:lifeAdminId", validate(life_adminPatchSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    const updated = await svc.patchLifeAdminContent({ domainId, lifeAdminId, ...req.body, actor });
    res.json(updated);
  });

  router.post("/life_admin/:lifeAdminId/claim", validate(claimLifeAdminSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    if (actor.type === "system") throw forbidden();
    const claimed = await svc.claimLifeAdmin({ domainId, lifeAdminId, actor, leaseMs: req.body.leaseSeconds ? req.body.leaseSeconds * 1000 : undefined });
    res.json({ life_admin: claimed, leaseToken: claimed.leaseToken, leaseExpiresAt: claimed.leaseExpiresAt });
  });

  router.post("/life_admin/:lifeAdminId/release", validate(releaseLifeAdminSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    if (req.body.force && actor.type === "agent") throw new HttpError(403, "Agents cannot force-release workflow leases", { code: "forbidden" });
    res.json(await svc.releaseLifeAdmin({ domainId, lifeAdminId, actor, leaseToken: req.body.leaseToken, force: req.body.force }));
  });

  router.post("/life_admin/:lifeAdminId/transition", validate(transitionLifeAdminSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    res.json(await svc.transitionLifeAdmin({
      domainId,
      lifeAdminId,
      toStageKey: req.body.toStageKey,
      expectedVersion: req.body.expectedVersion,
      leaseToken: req.body.leaseToken,
      reason: req.body.reason,
      force: req.body.force,
      suggestionId: req.body.acceptSuggestionId,
      actor,
    }));
  });

  router.post("/life_admin/:lifeAdminId/suggest-transition", validate(suggestTransitionSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    res.json(await svc.suggestTransition({ domainId, lifeAdminId, ...req.body, actor }));
  });

  router.post("/life_admin/:lifeAdminId/resolve-suggestion", validate(resolveSuggestionSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    res.json(await svc.resolveSuggestion({
      domainId,
      lifeAdminId,
      suggestionId: req.body.suggestionId,
      decision: req.body.resolution,
      expectedVersion: req.body.expectedVersion,
      reason: req.body.reason,
      leaseToken: req.body.leaseToken,
      actor,
    }));
  });

  router.post("/life_admin/:lifeAdminId/acknowledge-drift", validate(acknowledgeDriftSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    res.json(await svc.acknowledgeDrift({
      domainId,
      lifeAdminId,
      expectedVersion: req.body.expectedVersion,
      actor,
    }));
  });

  router.post("/life_admin/:lifeAdminId/review", validate(reviewLifeAdminSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    res.json(await svc.reviewLifeAdmin({ domainId, lifeAdminId, ...req.body, actor }));
  });

  router.put("/life_admin/:lifeAdminId/blockers", validate(blockersSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    res.json(await svc.replaceBlockers({ domainId, lifeAdminId, blockedByLifeAdminIds: req.body.blockedByLifeAdminIds, actor }));
  });

  router.post("/life_admin/:lifeAdminId/open-conversation", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    const conversationSource = await resolveWorkflowLifeAdminConversationSource(db, domainId, lifeAdminId);
    if (conversationSource?.isActive) {
      res.json({ issue: conversationSource.issue, created: false });
      return;
    }
    const detail = await getLifeAdminDetail(db, domainId, lifeAdminId);
    const [bodyDocumentContext, outputSummaries] = await Promise.all([
      loadWorkflowConversationBodyDocumentContext(db, { domainId, lifeAdminId }),
      outputsSvc.listLifeAdminOutputs(domainId, lifeAdminId).then((outputs) => summarizeWorkflowLifeAdminOutputsForContext(outputs)),
    ]);
    const result = await db.transaction(async (tx) => {
      const existingConversationSource = await resolveWorkflowLifeAdminConversationSource(tx, domainId, lifeAdminId);
      if (existingConversationSource?.isActive) {
        return { issue: existingConversationSource.issue, created: false };
      }
      const [issue] = await tx.insert(issueRows).values({
        domainId,
        title: `Discuss: ${detail.life_admin.title}`,
        description: buildLifeAdminContextMarkdown(detail, bodyDocumentContext, outputSummaries),
        status: "todo",
        priority: "medium",
        parentId: existingConversationSource?.issue?.id ?? conversationSource?.issue?.id ?? null,
        originKind: "workflow_life_admin_conversation",
        originId: detail.life_admin.id,
        createdByAgentId: actor.type === "agent" ? actor.agentId : null,
        createdByUserId: actor.type === "user" ? actor.userId : null,
      }).returning();
      await tx.insert(workflowLifeAdminIssueLinks).values({
        domainId,
        lifeAdminId,
        issueId: issue!.id,
        role: "conversation",
        createdByRunId: actor.type === "agent" ? actor.runId : null,
      });
      if (bodyDocumentContext.bodyDocument) {
        await tx.insert(issueDocuments).values({
          domainId,
          issueId: issue!.id,
          documentId: bodyDocumentContext.bodyDocument.id,
          key: WORKFLOW_LIFE_ADMIN_BODY_DOCUMENT_KEY,
          createdAt: new Date(),
          updatedAt: new Date(),
        }).onConflictDoNothing();
      }
      await writeRouteEvent(tx, {
        domainId,
        lifeAdminId,
        type: "conversation_opened",
        actor,
        payload: { issueId: issue!.id },
      });
      return { issue: issue!, created: true };
    });
    res.status(result.created ? 201 : 200).json(result);
  });

  router.get("/life_admin/:lifeAdminId/issue-links", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const links = await db
      .select({ link: workflowLifeAdminIssueLinks, issue: issueRows })
      .from(workflowLifeAdminIssueLinks)
      .innerJoin(issueRows, eq(workflowLifeAdminIssueLinks.issueId, issueRows.id))
      .where(and(
        eq(workflowLifeAdminIssueLinks.domainId, domainId),
        eq(workflowLifeAdminIssueLinks.lifeAdminId, lifeAdminId),
        eq(issueRows.domainId, domainId),
      ))
      .orderBy(asc(workflowLifeAdminIssueLinks.createdAt));
    res.json(links);
  });

  router.get("/life_admin/:lifeAdminId/outputs", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    res.json(await outputsSvc.listLifeAdminOutputs(domainId, lifeAdminId));
  });

  router.post("/life_admin/:lifeAdminId/issue-links", validate(createIssueLinkSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    const targetIssue = await getIssueMutationTarget(db, { domainId, issueId: req.body.issueId });
    if (!targetIssue) throw notFound("Issue not found");
    await assertIssueLinkMutationAllowed(req, { access, issuesSvc, issue: targetIssue });
    try {
      const link = await db.transaction(async (tx) => {
        const [created] = await tx.insert(workflowLifeAdminIssueLinks).values({
          domainId,
          lifeAdminId,
          issueId: req.body.issueId,
          role: req.body.role,
          createdByRunId: actor.type === "agent" ? actor.runId : null,
        }).returning();
        await writeRouteEvent(tx, {
          domainId,
          lifeAdminId,
          type: "issue_linked",
          actor,
          payload: { issueId: req.body.issueId, role: req.body.role },
        });
        return created!;
      });
      res.status(201).json(link);
    } catch (error) {
      codedConflictForUnique(error);
    }
  });

  router.delete("/life_admin/:lifeAdminId/issue-links/:linkId", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const linkId = req.params.linkId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    const existingLink = await db
      .select({ issueId: workflowLifeAdminIssueLinks.issueId })
      .from(workflowLifeAdminIssueLinks)
      .where(and(
        eq(workflowLifeAdminIssueLinks.id, linkId),
        eq(workflowLifeAdminIssueLinks.domainId, domainId),
        eq(workflowLifeAdminIssueLinks.lifeAdminId, lifeAdminId),
      ))
      .limit(1)
      .then((rows) => rows[0] ?? null);
    if (!existingLink) throw notFound("Workflow life_admin issue link not found");
    const targetIssue = await getIssueMutationTarget(db, { domainId, issueId: existingLink.issueId });
    if (!targetIssue) throw notFound("Issue not found");
    await assertIssueLinkMutationAllowed(req, { access, issuesSvc, issue: targetIssue });
    const deleted = await db.transaction(async (tx) => {
      const [removed] = await tx
        .delete(workflowLifeAdminIssueLinks)
        .where(and(
          eq(workflowLifeAdminIssueLinks.id, linkId),
          eq(workflowLifeAdminIssueLinks.domainId, domainId),
          eq(workflowLifeAdminIssueLinks.lifeAdminId, lifeAdminId),
        ))
        .returning();
      if (!removed) return null;
      await writeRouteEvent(tx, {
        domainId,
        lifeAdminId,
        type: "issue_unlinked",
        actor,
        payload: { issueId: removed.issueId, role: removed.role, linkId: removed.id },
        });
      return removed;
    });
    res.json({ deleted: true });
  });

  router.get("/life_admin/:lifeAdminId/events", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const pagination = parseLifeAdminEventsQuery(req.query);
    res.json(await svc.listLifeAdminEventsPage(domainId, lifeAdminId, pagination));
  });

  router.get("/life_admin/:lifeAdminId/children/tree", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    res.json(await getLifeAdminChildrenTree(db, domainId, lifeAdminId));
  });

  router.get("/life_admin/:lifeAdminId/rollup", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    res.json(await svc.getLifeAdminRollup(domainId, lifeAdminId));
  });

  router.get("/life_admin/:lifeAdminId/context-pack", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const detail = await getLifeAdminDetail(db, domainId, lifeAdminId);
    const [events, outputs, childOutcomes] = await Promise.all([
      svc.listLifeAdminEventsPage(domainId, lifeAdminId, {
        limit: WORKFLOW_CONTEXT_PACK_EVENT_LIMIT,
        order: "desc",
      }),
      outputsSvc.listLifeAdminOutputs(domainId, lifeAdminId),
      getChildOutcomeSummaries(db, domainId, lifeAdminId),
    ]);
    const outputSummaries = summarizeWorkflowLifeAdminOutputsForContext(outputs);
    res.json({
      life_admin: {
        id: detail.life_admin.id,
        life_adminKey: detail.life_admin.life_adminKey,
        title: detail.life_admin.title,
        version: detail.life_admin.version,
        untrustedContent: {
          summary: detail.life_admin.summary,
          fields: detail.life_admin.fields,
        },
      },
      stage: detail.stage,
      allowedTransitions: detail.allowedNextStages,
      linkedIssues: detail.links,
      blockers: detail.blockers,
      childOutcomes,
      outputSummaries,
      events: [...events.items].reverse(),
    });
  });

  router.get("/life_admin/:lifeAdminId/automation/retry-plan", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const query = retryAutomationQuerySchema.parse(req.query);
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const plan = await svc.getAutomationRetryPlan({
      domainId,
      lifeAdminId,
      scope: query.scope,
      targetStageId: query.targetStageId,
    });
    if (plan.targetStage) {
      await assertStageAutomationTargetWriteAccess(db, req, { access, domainId, stage: plan.targetStage });
    }
    res.json(plan);
  });

  router.post("/life_admin/:lifeAdminId/automation/retry", validate(workflowAutomationRetryRequestSchema), async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    const actor = actorForMutation(req);
    const plan = await svc.getAutomationRetryPlan({
      domainId,
      lifeAdminId,
      scope: req.body.scope,
      targetStageId: req.body.targetStageId,
    });
    if (plan.targetStage) {
      await assertStageAutomationTargetWriteAccess(db, req, { access, domainId, stage: plan.targetStage });
    }
    res.json(await svc.retryStageAutomation({
      domainId,
      lifeAdminId,
      scope: req.body.scope,
      targetStageId: req.body.targetStageId,
      expectedVersion: req.body.expectedVersion,
      cleanup: req.body.cleanup,
      actor,
    }));
  });

  router.post("/life_admin/:lifeAdminId/automations/:automationId/retry", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const automationId = req.params.automationId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    await assertCurrentStageAutomationTargetWriteAccess(db, req, { access, domainId, lifeAdminId, automationId });
    const actor = actorForMutation(req);
    res.json(await svc.retryAutomation({ domainId, lifeAdminId, automationId, actor }));
  });

  router.post("/life_admin/:lifeAdminId/automation/current-stage/rerun", async (req, res) => {
    const lifeAdminId = req.params.lifeAdminId as string;
    const domainId = await assertLifeAdminAccess(db, req, lifeAdminId);
    await assertCurrentStageAutomationTargetWriteAccess(db, req, { access, domainId, lifeAdminId });
    const actor = actorForMutation(req);
    res.json(await svc.rerunCurrentStageAutomation({ domainId, lifeAdminId, actor }));
  });

  return router;
}

async function getLifeAdminDetail(db: Db, domainId: string, lifeAdminId: string) {
  const row = await db
    .select({ life_admin: workflowLifeAdmin, stage: workflowStages, workflow: workflows })
    .from(workflowLifeAdmin)
    .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
    .innerJoin(workflows, eq(workflowLifeAdmin.workflowId, workflows.id))
    .where(and(eq(workflowLifeAdmin.domainId, domainId), eq(workflowLifeAdmin.id, lifeAdminId)))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!row) throw notFound("Workflow life_admin not found");
  const parentLifeAdminPromise = row.life_admin.parentLifeAdminId
    ? db
      .select({ life_admin: workflowLifeAdmin, stage: workflowStages, workflow: workflows })
      .from(workflowLifeAdmin)
      .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
      .innerJoin(workflows, eq(workflowLifeAdmin.workflowId, workflows.id))
      .where(and(
        eq(workflowLifeAdmin.domainId, domainId),
        eq(workflowLifeAdmin.id, row.life_admin.parentLifeAdminId),
        eq(workflows.domainId, domainId),
      ))
      .limit(1)
      .then((rows) => rows[0] ?? null)
    : Promise.resolve(null);
  const [
    allowedNextStages,
    links,
    blockers,
    blocks,
    childrenCounts,
    activeWorkByLifeAdmin,
    descendantActiveWorkCounts,
    parentLifeAdmin,
    conversationSource,
    liveness,
    builtFromAutomation,
  ] = await Promise.all([
    db.select().from(workflowStages).where(eq(workflowStages.workflowId, row.life_admin.workflowId)).orderBy(asc(workflowStages.position)),
    db.select().from(workflowLifeAdminIssueLinks).where(and(eq(workflowLifeAdminIssueLinks.domainId, domainId), eq(workflowLifeAdminIssueLinks.lifeAdminId, lifeAdminId))),
    db.select().from(workflowLifeAdminBlockers).where(and(eq(workflowLifeAdminBlockers.domainId, domainId), eq(workflowLifeAdminBlockers.lifeAdminId, lifeAdminId))),
    db.select().from(workflowLifeAdminBlockers).where(and(eq(workflowLifeAdminBlockers.domainId, domainId), eq(workflowLifeAdminBlockers.blockedByLifeAdminId, lifeAdminId))),
    getDirectChildrenSummary(db, domainId, lifeAdminId),
    loadActiveWorkForLifeAdmin(db, domainId, [lifeAdminId]),
    loadDescendantActiveWorkCountsForLifeAdmin(db, domainId, [lifeAdminId]),
    parentLifeAdminPromise,
    resolveWorkflowLifeAdminConversationSource(db, domainId, lifeAdminId),
    deriveWorkflowLifeAdminLiveness(db, domainId, row),
    loadBuiltFromAutomation(db, domainId, row.life_admin),
  ]);
  return {
    ...row,
    // Derived, invisible: a life_admin's "type" is simply which workflow it lives in.
    // Used internally for display and ingest sanity-checks; not a user field.
    lifeAdminType: deriveLifeAdminType(row.workflow),
    allowedNextStages,
    links,
    blockers,
    blocks,
    childrenSummary: {
      childCount: childrenCounts.total,
      terminalChildCount: childrenCounts.done + childrenCounts.dropped,
      loadedChildren: childrenCounts.total,
      descendantActiveWorkCount: descendantActiveWorkCounts.get(lifeAdminId) ?? 0,
      ...childrenCounts,
    },
    activeWork: activeWorkByLifeAdmin.get(lifeAdminId) ?? null,
    liveness,
    conversationSource,
    builtFromAutomation,
    parentLifeAdmin,
    pendingSuggestion: row.life_admin.pendingSuggestion,
  };
}

function stageAutomationId(stage: typeof workflowStages.$inferSelect) {
  const config = stage.config && typeof stage.config === "object" && !Array.isArray(stage.config)
    ? stage.config as WorkflowStageConfig
    : null;
  const onEnter = config?.onEnter;
  if (!onEnter || onEnter.type !== "run_routine" || !onEnter.routineId) return null;
  return typeof onEnter.id === "string" ? onEnter.id : `${stage.id}:on_enter`;
}

async function loadBuiltFromAutomation(
  db: Db,
  domainId: string,
  lifeAdminRow: typeof workflowLifeAdmin.$inferSelect,
) {
  if (!lifeAdminRow.automationAttemptId) return null;
  const row = await db
    .select({
      execution: workflowAutomationExecutions,
      sourceLifeAdmin: workflowLifeAdmin,
      sourceWorkflow: workflows,
      routine: routines,
    })
    .from(workflowAutomationExecutions)
    .innerJoin(workflowLifeAdmin, and(
      eq(workflowLifeAdmin.domainId, domainId),
      eq(workflowLifeAdmin.id, workflowAutomationExecutions.lifeAdminId),
    ))
    .innerJoin(workflows, and(
      eq(workflows.domainId, domainId),
      eq(workflows.id, workflowLifeAdmin.workflowId),
    ))
    .innerJoin(routines, and(
      eq(routines.domainId, domainId),
      eq(routines.id, workflowAutomationExecutions.routineId),
    ))
    .where(and(
      eq(workflowAutomationExecutions.domainId, domainId),
      eq(workflowAutomationExecutions.id, lifeAdminRow.automationAttemptId),
    ))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!row) return null;

  const stages = await db
    .select()
    .from(workflowStages)
    .where(eq(workflowStages.workflowId, row.sourceWorkflow.id));
  const stage = stages.find((candidate) => stageAutomationId(candidate) === row.execution.automationId) ?? null;

  return {
    execution: {
      id: row.execution.id,
      automationId: row.execution.automationId,
      status: row.execution.status,
    },
    routine: {
      id: row.routine.id,
      title: row.routine.title,
    },
    workflow: {
      id: row.sourceWorkflow.id,
      key: row.sourceWorkflow.key,
      name: row.sourceWorkflow.name,
    },
    stage: stage
      ? {
        id: stage.id,
        key: stage.key,
        name: stage.name,
        kind: stage.kind,
      }
      : null,
    life_admin: {
      id: row.sourceLifeAdmin.id,
      life_adminKey: row.sourceLifeAdmin.life_adminKey,
      title: row.sourceLifeAdmin.title,
      workflowId: row.sourceLifeAdmin.workflowId,
    },
  };
}

function isLiveIssueStatus(status: string) {
  return status === "todo" || status === "in_progress" || status === "in_review";
}

function isWaitingIssueStatus(status: string) {
  return status === "backlog" || status === "todo" || status === "in_review";
}

function summarizeLinkedIssue(issue: typeof issueRows.$inferSelect) {
  return {
    id: issue.id,
    identifier: issue.identifier,
    title: issue.title,
    status: issue.status,
  };
}

function readBreakdownRequestKeys(payload: unknown): string[] {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return [];
  const keys = (payload as Record<string, unknown>).requestKeys;
  if (!Array.isArray(keys)) return [];
  return [...new Set(keys.filter((key): key is string => typeof key === "string" && key.trim().length > 0))];
}

function readStageBreakdownConfig(config: unknown) {
  if (!config || typeof config !== "object" || Array.isArray(config)) return null;
  const raw = (config as Record<string, unknown>).breakdown;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  return raw as Record<string, unknown>;
}

function stageHasChildrenTerminalGate(config: unknown) {
  if (!config || typeof config !== "object" || Array.isArray(config)) return false;
  const record = config as Record<string, unknown>;
  return record.requireChildrenTerminal === true ||
    (typeof record.autoAdvanceOnChildrenTerminal === "string" && record.autoAdvanceOnChildrenTerminal.trim().length > 0);
}

function readStageAutomationId(stage: typeof workflowStages.$inferSelect) {
  if (!stage.config || typeof stage.config !== "object" || Array.isArray(stage.config)) return null;
  const onEnterValue = (stage.config as Record<string, unknown>).onEnter;
  if (!onEnterValue || typeof onEnterValue !== "object" || Array.isArray(onEnterValue)) return null;
  const onEnter = onEnterValue as Record<string, unknown>;
  const rawId = typeof onEnter.id === "string" ? onEnter.id.trim() : "";
  const routineId = typeof onEnter.routineId === "string" ? onEnter.routineId.trim() : "";
  if (onEnter.type !== "run_routine" || routineId.length === 0) return null;
  return rawId.length > 0 ? rawId : `${stage.id}:on_enter`;
}

function readStageAutomationTargetWorkflowId(stage: typeof workflowStages.$inferSelect) {
  if (!readStageAutomationId(stage)) return null;
  const breakdown = readStageBreakdownConfig(stage.config);
  const targetWorkflowId = typeof breakdown?.targetWorkflowId === "string" ? breakdown.targetWorkflowId.trim() : "";
  return targetWorkflowId.length > 0 ? targetWorkflowId : null;
}

async function assertStageAutomationTargetWriteAccess(
  db: Db,
  req: Request,
  input: {
    access: ReturnType<typeof accessService>;
    domainId: string;
    stage: { id: string };
  },
) {
  const stage = await db
    .select()
    .from(workflowStages)
    .where(eq(workflowStages.id, input.stage.id))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!stage) throw notFound("Workflow stage not found");
  const targetWorkflowId = readStageAutomationTargetWorkflowId(stage);
  if (!targetWorkflowId) return;
  await assertWorkflowWriteAccess(req, {
    access: input.access,
    domainId: input.domainId,
    workflowId: targetWorkflowId,
  });
}

async function assertCurrentStageAutomationTargetWriteAccess(
  db: Db,
  req: Request,
  input: {
    access: ReturnType<typeof accessService>;
    domainId: string;
    lifeAdminId: string;
    automationId?: string;
  },
) {
  const row = await db
    .select({ stage: workflowStages })
    .from(workflowLifeAdmin)
    .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
    .where(and(eq(workflowLifeAdmin.domainId, input.domainId), eq(workflowLifeAdmin.id, input.lifeAdminId)))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!row) throw notFound("Workflow life_admin not found");

  const currentAutomationId = readStageAutomationId(row.stage);
  if (input.automationId && currentAutomationId !== input.automationId) return;

  const targetWorkflowId = readStageAutomationTargetWorkflowId(row.stage);
  if (!targetWorkflowId) return;

  await assertWorkflowWriteAccess(req, {
    access: input.access,
    domainId: input.domainId,
    workflowId: targetWorkflowId,
  });
}

function parsePermissionPreflightFingerprint(fingerprint: string | null) {
  if (!fingerprint) return null;
  const parts = fingerprint.split(":");
  if (parts.length < 7) return null;
  const lifeAdminId = parts[0];
  const stageId = parts[1];
  const targetWorkflowId = parts[parts.length - 4];
  const principalId = parts[parts.length - 3];
  const permissionKey = parts.slice(parts.length - 2).join(":");
  const automationId = parts.slice(2, parts.length - 4).join(":");
  if (!lifeAdminId || !stageId || !automationId || !targetWorkflowId || !principalId || !permissionKey) return null;
  return { lifeAdminId, stageId, automationId, targetWorkflowId, principalId, permissionKey };
}

async function latestBreakdownCreatedEvent(db: Db, domainId: string, lifeAdminId: string) {
  return db
    .select()
    .from(workflowLifeAdminEvents)
    .where(and(
      eq(workflowLifeAdminEvents.domainId, domainId),
      eq(workflowLifeAdminEvents.lifeAdminId, lifeAdminId),
      eq(workflowLifeAdminEvents.type, "updated"),
      sql`${workflowLifeAdminEvents.payload}->>'kind' = 'breakdown_created'`,
    ))
    .orderBy(desc(workflowLifeAdminEvents.createdAt), desc(workflowLifeAdminEvents.id))
    .limit(1)
    .then((rows) => rows[0] ?? null);
}

async function deriveWorkflowLifeAdminLiveness(
  db: Db,
  domainId: string,
  row: { life_admin: typeof workflowLifeAdmin.$inferSelect; stage: typeof workflowStages.$inferSelect },
): Promise<WorkflowLifeAdminLiveness> {
  if (row.life_admin.terminalKind) {
    return {
      state: "terminal",
      reason: "terminal",
      message: `Workflow item is terminal (${row.life_admin.terminalKind}).`,
    };
  }

  if (row.life_admin.leaseToken && row.life_admin.leaseExpiresAt && row.life_admin.leaseExpiresAt.getTime() > Date.now()) {
    return {
      state: "live",
      reason: "lease_active",
      message: "Workflow item has an active lease.",
    };
  }

  const blockerLifeAdmin = await db
    .select({
      id: workflowLifeAdmin.id,
      title: workflowLifeAdmin.title,
      terminalKind: workflowLifeAdmin.terminalKind,
    })
    .from(workflowLifeAdminBlockers)
    .innerJoin(workflowLifeAdmin, eq(workflowLifeAdminBlockers.blockedByLifeAdminId, workflowLifeAdmin.id))
    .where(and(
      eq(workflowLifeAdminBlockers.domainId, domainId),
      eq(workflowLifeAdminBlockers.lifeAdminId, row.life_admin.id),
      or(isNull(workflowLifeAdmin.terminalKind), ne(workflowLifeAdmin.terminalKind, "done")),
    ))
    .orderBy(asc(workflowLifeAdmin.createdAt))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (blockerLifeAdmin) {
    return {
      state: "blocked",
      reason: "life_admin_blocked",
      message: `Workflow item is blocked by "${blockerLifeAdmin.title}".`,
      blocker: {
        lifeAdminId: blockerLifeAdmin.id,
        title: blockerLifeAdmin.title,
        terminalKind: blockerLifeAdmin.terminalKind,
      },
    };
  }

  const linkedIssues = await db
    .select({ link: workflowLifeAdminIssueLinks, issue: issueRows })
    .from(workflowLifeAdminIssueLinks)
    .innerJoin(issueRows, eq(workflowLifeAdminIssueLinks.issueId, issueRows.id))
    .where(and(
      eq(workflowLifeAdminIssueLinks.domainId, domainId),
      eq(workflowLifeAdminIssueLinks.lifeAdminId, row.life_admin.id),
      inArray(workflowLifeAdminIssueLinks.role, ["automation", "work"]),
      eq(issueRows.domainId, domainId),
      isNull(issueRows.hiddenAt),
    ))
    .orderBy(desc(issueRows.updatedAt), desc(workflowLifeAdminIssueLinks.createdAt));
  const blockedIssue = linkedIssues.find(({ issue }) => issue.status === "blocked");
  if (blockedIssue) {
    const blocker = await db
      .select({
        id: issueRows.id,
        identifier: issueRows.identifier,
        title: issueRows.title,
        status: issueRows.status,
      })
      .from(issueRelations)
      .innerJoin(issueRows, eq(issueRelations.issueId, issueRows.id))
      .where(and(
        eq(issueRelations.domainId, domainId),
        eq(issueRelations.type, "blocks"),
        eq(issueRelations.relatedIssueId, blockedIssue.issue.id),
      ))
      .orderBy(asc(issueRows.title))
      .limit(1)
      .then((rows) => rows[0] ?? null);
    return {
      state: "blocked",
      reason: "linked_issue_blocked",
      message: `Linked ${blockedIssue.link.role} task is blocked.`,
      issue: summarizeLinkedIssue(blockedIssue.issue),
      blocker: blocker
        ? { issueId: blocker.id, title: blocker.title, status: blocker.status }
        : null,
    };
  }
  const activeIssue = linkedIssues.find(({ issue }) => issue.status === "in_progress");
  if (activeIssue) {
    return {
      state: "live",
      reason: "linked_issue_active",
      message: `Linked ${activeIssue.link.role} task is in progress.`,
      issue: summarizeLinkedIssue(activeIssue.issue),
    };
  }
  const waitingIssue = linkedIssues.find(({ issue }) => isWaitingIssueStatus(issue.status));
  if (waitingIssue) {
    return {
      state: isLiveIssueStatus(waitingIssue.issue.status) ? "waiting" : "attention",
      reason: "linked_issue_waiting",
      message: `Linked ${waitingIssue.link.role} task is ${waitingIssue.issue.status}.`,
      issue: summarizeLinkedIssue(waitingIssue.issue),
    };
  }

  const latestAutomation = await db
    .select()
    .from(workflowAutomationExecutions)
    .where(and(
      eq(workflowAutomationExecutions.domainId, domainId),
      eq(workflowAutomationExecutions.lifeAdminId, row.life_admin.id),
    ))
    .orderBy(desc(workflowAutomationExecutions.updatedAt), desc(workflowAutomationExecutions.createdAt))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (latestAutomation?.status === "failed") {
    const fingerprint = latestAutomation.error?.startsWith("permission_preflight_failed:")
      ? latestAutomation.error.slice("permission_preflight_failed:".length)
      : null;
    const parsedFingerprint = parsePermissionPreflightFingerprint(fingerprint);
    if (parsedFingerprint?.permissionKey === "workflows:write") {
      const decision = await authorizationService(db).decide({
        actor: {
          type: "agent",
          agentId: parsedFingerprint.principalId,
          domainId,
          source: "agent_key",
        },
        action: "workflows:write",
        resource: { type: "domain", domainId },
        scope: { workflowId: parsedFingerprint.targetWorkflowId },
      });
      if (decision.allowed) {
        return {
          state: "attention",
          reason: "automation_failed",
          message: "Workflow automation permission has been restored; retry the failed automation ledger.",
          automation: {
            automationId: latestAutomation.automationId,
            routineId: latestAutomation.routineId,
            executionId: latestAutomation.id,
            error: latestAutomation.error,
            fingerprint,
          },
        };
      }
    }
    return {
      state: fingerprint ? "blocked" : "attention",
      reason: fingerprint ? "permission_preflight_failed" : "automation_failed",
      message: fingerprint
        ? "Workflow automation is blocked until the configured assignee can write to the target workflow."
        : "Workflow automation failed and needs retry or recovery.",
      automation: {
        automationId: latestAutomation.automationId,
        routineId: latestAutomation.routineId,
        executionId: latestAutomation.id,
        error: latestAutomation.error,
        fingerprint,
      },
    };
  }

  const breakdownConfig = readStageBreakdownConfig(row.stage.config);
  if (breakdownConfig) {
    const breakdownEvent = await latestBreakdownCreatedEvent(db, domainId, row.life_admin.id);
    if (!breakdownEvent) {
      return {
        state: "attention",
        reason: "breakdown_pending",
        message: "Breakdown stage has not recorded breakdown_created evidence yet.",
      };
    }
    const expectedRequestKeys = readBreakdownRequestKeys(breakdownEvent.payload);
    const createdRows = expectedRequestKeys.length > 0
      ? await db
        .select({ requestKey: workflowLifeAdmin.requestKey })
        .from(workflowLifeAdmin)
        .where(and(
          eq(workflowLifeAdmin.domainId, domainId),
          eq(workflowLifeAdmin.parentLifeAdminId, row.life_admin.id),
          inArray(workflowLifeAdmin.requestKey, expectedRequestKeys),
          isNull(workflowLifeAdmin.hiddenFromBoardAt),
        ))
      : [];
    const createdRequestKeys = [...new Set(createdRows
      .map((child) => child.requestKey)
      .filter((key): key is string => typeof key === "string"))];
    const missingRequestKeys = expectedRequestKeys.filter((key) => !createdRequestKeys.includes(key));
    if (missingRequestKeys.length > 0) {
      return {
        state: "blocked",
        reason: "breakdown_incomplete",
        message: "Breakdown evidence does not match created child life_admin.",
        breakdown: { expectedRequestKeys, createdRequestKeys, missingRequestKeys },
      };
    }
    const waitForPieces = breakdownConfig.waitForPieces === true;
    if (waitForPieces && row.life_admin.childCount !== row.life_admin.terminalChildCount) {
      return {
        state: "waiting",
        reason: "children_waiting",
        message: "Workflow item is waiting for child items to finish.",
        breakdown: { expectedRequestKeys, createdRequestKeys, missingRequestKeys: [] },
      };
    }
  }

  if (stageHasChildrenTerminalGate(row.stage.config) && row.life_admin.childCount !== row.life_admin.terminalChildCount) {
    return {
      state: "waiting",
      reason: "children_waiting",
      message: "Workflow item is waiting for child items to finish.",
    };
  }

  if (row.stage.kind === "review") {
    return {
      state: "waiting",
      reason: "review_waiting",
      message: "Workflow item is waiting for stage review.",
    };
  }

  return {
    state: "attention",
    reason: "no_action_path",
    message: "No lease, linked work, blocker, automation retry, review, or breakdown action path is visible.",
  };
}

function buildLifeAdminContextMarkdown(
  detail: Awaited<ReturnType<typeof getLifeAdminDetail>>,
  bodyDocumentContext?: Awaited<ReturnType<typeof loadWorkflowConversationBodyDocumentContext>> | null,
  outputSummaries?: ReturnType<typeof summarizeWorkflowLifeAdminOutputsForContext> | null,
) {
  const bodyDocumentMarkdown = formatWorkflowConversationBodyDocumentContextMarkdown(bodyDocumentContext ?? null);
  const outputMarkdown = formatWorkflowLifeAdminOutputContextMarkdown(outputSummaries ?? null);
  return [
    "## Workflow LifeAdmin Context",
    "",
    "## Conversation Instructions",
    "",
    "This task is the conversation thread for the linked workflow item.",
    "Treat user comments in this thread as feedback on that workflow item unless the user explicitly says otherwise.",
    "Iterate the workflow item body document unless the user explicitly asks for item metadata, stage changes, or follow-up work.",
    "Inspect connected documents and outputs when present; if feedback affects a connected document, revise it too so the item and supporting documents stay in sync.",
    "Editing this discussion task itself is not the primary deliverable unless the user specifically requests it.",
    "",
    bodyDocumentMarkdown,
    bodyDocumentMarkdown ? "" : null,
    outputMarkdown,
    outputMarkdown ? "" : null,
    "## Workflow Item Context",
    "",
    `Item: ${detail.life_admin.title}`,
    `Workflow: ${detail.workflow.name} (${detail.workflow.key})`,
    `Stage: ${detail.stage.name} (${detail.stage.key}, ${detail.stage.kind})`,
    `Item link: /PAP/workflows/${detail.workflow.id}/items/${detail.life_admin.id}`,
    "",
    "```json",
    JSON.stringify({
      workflow: {
        id: detail.workflow.id,
        key: detail.workflow.key,
        name: detail.workflow.name,
      },
      life_admin: {
        id: detail.life_admin.id,
        life_adminKey: detail.life_admin.life_adminKey,
        title: detail.life_admin.title,
        version: detail.life_admin.version,
        untrustedContent: {
          summary: detail.life_admin.summary,
          fields: detail.life_admin.fields,
        },
      },
      stage: {
        id: detail.stage.id,
        key: detail.stage.key,
        name: detail.stage.name,
        kind: detail.stage.kind,
      },
    }, null, 2),
    "```",
  ].filter((line) => line !== null).join("\n");
}

async function getChildOutcomeSummaries(db: Db, domainId: string, lifeAdminId: string) {
  const children = await db
    .select({ life_admin: workflowLifeAdmin, stage: workflowStages, workflow: workflows })
    .from(workflowLifeAdmin)
    .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
    .innerJoin(workflows, eq(workflowLifeAdmin.workflowId, workflows.id))
    .where(and(eq(workflowLifeAdmin.domainId, domainId), eq(workflowLifeAdmin.parentLifeAdminId, lifeAdminId)))
    .orderBy(asc(workflowLifeAdmin.createdAt));
  if (children.length === 0) return [];

  const childIds = children.map((row) => row.life_admin.id);
  const reviewEvents = await db
    .select()
    .from(workflowLifeAdminEvents)
    .where(and(
      eq(workflowLifeAdminEvents.domainId, domainId),
      inArray(workflowLifeAdminEvents.lifeAdminId, childIds),
      eq(workflowLifeAdminEvents.type, "review_decided"),
    ))
    .orderBy(desc(workflowLifeAdminEvents.createdAt), desc(workflowLifeAdminEvents.id));
  const latestReviewByLifeAdminId = new Map<string, typeof workflowLifeAdminEvents.$inferSelect>();
  for (const event of reviewEvents) {
    if (!latestReviewByLifeAdminId.has(event.lifeAdminId)) latestReviewByLifeAdminId.set(event.lifeAdminId, event);
  }

  return children.map((row) => {
    const review = latestReviewByLifeAdminId.get(row.life_admin.id);
    const reviewPayload = review?.payload && typeof review.payload === "object" && !Array.isArray(review.payload)
      ? review.payload as Record<string, unknown>
      : {};
    const decision = typeof reviewPayload.decision === "string" ? reviewPayload.decision : null;
    const reason = typeof reviewPayload.reason === "string" ? reviewPayload.reason : null;
    return {
      id: row.life_admin.id,
      life_adminKey: row.life_admin.life_adminKey,
      title: row.life_admin.title,
      href: `/workflows/${row.workflow.id}/items/${row.life_admin.id}`,
      workflow: { id: row.workflow.id, key: row.workflow.key, name: row.workflow.name },
      stage: { id: row.stage.id, key: row.stage.key, name: row.stage.name, kind: row.stage.kind },
      status: row.life_admin.terminalKind ? "terminal" : "open",
      terminalKind: row.life_admin.terminalKind,
      approved: decision === "approve" ? true : row.life_admin.terminalKind === "done" ? true : null,
      rejected: decision === "reject" ? true : row.life_admin.terminalKind === "cancelled" ? true : null,
      reason,
    };
  });
}

import { Router, type Request, type Response } from "express";
import multer from "multer";
import { z } from "zod";
import { and, asc, desc, eq, ilike, inArray, isNull, or, sql } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import {
  agents,
  assets,
  lifeAdminAttachments,
  lifeAdminDocuments,
  lifeAdminEvents,
  lifeAdminIssueLinks,
  lifeAdminLabels,
  life_admin,
  domains,
  documents,
  documentRevisions,
  issues,
  labels,
  projects,
} from "@paperclipai/db";
import {
  createDocumentAnnotationCommentSchema,
  createDocumentAnnotationThreadSchema,
  updateDocumentAnnotationThreadSchema,
  isUuidLike,
} from "@paperclipai/shared";
import { normalizeContentType } from "../attachment-types.js";
import { badRequest, conflict, forbidden, notFound, unprocessable } from "../errors.js";
import { validate } from "../middleware/validate.js";
import { instanceSettingsService } from "../services/instance-settings.js";
import { documentAnnotationService, logActivity } from "../services/index.js";
import type { StorageService } from "../storage/types.js";
import { assertDomainAccess, getActorInfo } from "./authz.js";

type LifeAdminRouteDb = Db | Parameters<Parameters<Db["transaction"]>[0]>[0];
type LifeAdminActor = ReturnType<typeof getActorInfo>;

const LIFE_ADMIN_STATUSES = ["draft", "in_progress", "in_review", "approved", "done", "cancelled"] as const;
const LIFE_ADMIN_LINK_ROLES = ["origin", "work", "reference"] as const;
const DEFAULT_EVENTS_LIMIT = 100;
const MAX_EVENTS_LIMIT = 500;

const jsonObjectSchema = z.record(z.string(), z.unknown());
const lifeAdminStatusSchema = z.enum(LIFE_ADMIN_STATUSES);
const lifeAdminTypeSchema = z.string().trim().min(1).max(120);
const lifeAdminKeySchema = z.string().trim().min(1).max(512);
const documentKeySchema = z.string().trim().min(1).max(120).regex(/^[A-Za-z0-9_.:-]+$/);

const createLifeAdminSchema = z.object({
  projectId: z.string().uuid().nullable().optional(),
  lifeAdminType: lifeAdminTypeSchema,
  key: lifeAdminKeySchema.nullable().optional(),
  title: z.string().trim().min(1).max(500),
  summary: z.string().max(8_000).nullable().optional(),
  status: lifeAdminStatusSchema.optional(),
  fields: jsonObjectSchema.optional(),
  parentLifeAdminId: z.string().uuid().nullable().optional(),
}).strict();

const patchLifeAdminSchema = z.object({
  projectId: z.string().uuid().nullable().optional(),
  title: z.string().trim().min(1).max(500).optional(),
  summary: z.string().max(8_000).nullable().optional(),
  status: lifeAdminStatusSchema.optional(),
  fields: jsonObjectSchema.optional(),
  parentLifeAdminId: z.string().uuid().nullable().optional(),
  labels: z.array(z.string().uuid()).max(100).optional(),
  labelIds: z.array(z.string().uuid()).max(100).optional(),
}).strict();

const createIssueLinkSchema = z.object({
  issueId: z.string().uuid(),
  role: z.enum(LIFE_ADMIN_LINK_ROLES),
}).strict();

const upsertLifeAdminDocumentSchema = z.object({
  title: z.string().trim().min(1).max(200).optional(),
  format: z.string().trim().min(1).max(80).optional().default("markdown"),
  body: z.string().max(200_000),
  changeSummary: z.string().trim().max(1_000).nullable().optional(),
  baseRevisionId: z.string().uuid().nullable().optional(),
}).strict();

const queryListParamSchema = z.union([z.string(), z.array(z.string())]).optional();

const listLifeAdminQuerySchema = z.object({
  type: z.string().trim().min(1).max(120).optional(),
  types: queryListParamSchema,
  status: z.string().trim().min(1).max(120).optional(),
  statuses: queryListParamSchema,
  project: z.string().uuid().optional(),
  projectId: z.string().uuid().optional(),
  projectIds: queryListParamSchema,
  includeNoProject: z.enum(["true", "false", "1", "0"]).optional(),
  label: z.string().uuid().optional(),
  labelId: z.string().uuid().optional(),
  parent: z.string().uuid().optional(),
  q: z.string().trim().min(1).max(200).optional(),
  includeAncestors: z.enum(["true", "false", "1", "0"]).optional(),
  limit: z.coerce.number().int().min(1).max(200).optional().default(100),
}).strict();

const listEventsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(MAX_EVENTS_LIMIT).optional().default(DEFAULT_EVENTS_LIMIT),
}).strict();

function eventActorValues(actor: LifeAdminActor) {
  return {
    actorType: actor.actorType,
    actorUserId: actor.actorType === "user" ? actor.actorId : null,
    actorAgentId: actor.agentId,
    runId: actor.runId && isUuidLike(actor.runId) ? actor.runId : null,
  };
}

async function assertLifeAdminEnabled(db: Db) {
  const experimental = await instanceSettingsService(db).getExperimental();
  if (!experimental.enableLifeAdmin) {
    throw forbidden("LifeAdmin are disabled");
  }
}

async function lockLifeAdminUpsertKey(db: LifeAdminRouteDb, input: { domainId: string; lifeAdminType: string; key: string | null | undefined }) {
  const lockKey = `paperclip:life_admin-upsert:${input.domainId}:${input.lifeAdminType}:${input.key ?? "<null>"}`;
  await db.execute(sql`select pg_advisory_xact_lock(hashtext(${lockKey}))`);
}

async function lockLifeAdminDocumentKey(db: LifeAdminRouteDb, input: { domainId: string; lifeAdminId: string; key: string }) {
  const lockKey = `paperclip:life_admin-document:${input.domainId}:${input.lifeAdminId}:${input.key}`;
  await db.execute(sql`select pg_advisory_xact_lock(hashtext(${lockKey}))`);
}

async function lockLifeAdminLabels(db: LifeAdminRouteDb, input: { domainId: string; lifeAdminId: string }) {
  const lockKey = `paperclip:life_admin-labels:${input.domainId}:${input.lifeAdminId}`;
  await db.execute(sql`select pg_advisory_xact_lock(hashtext(${lockKey}))`);
}

function parseDocumentKey(raw: string | undefined) {
  const parsed = documentKeySchema.safeParse(raw);
  if (!parsed.success) throw badRequest("Invalid document key", parsed.error.issues);
  return parsed.data;
}

function parseBooleanQuery(value: unknown) {
  return value === true || value === "true" || value === "1";
}

function parseQueryList(value: string | string[] | undefined): string[] {
  const values = Array.isArray(value) ? value : value ? [value] : [];
  return values.flatMap((item) => item.split(",")).map((item) => item.trim()).filter(Boolean);
}

function annotationActorInput(req: Request) {
  const actor = getActorInfo(req);
  return {
    actor,
    annotationActor: {
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      userId: actor.actorType === "user" ? actor.actorId : null,
      runId: actor.runId,
    },
  };
}

async function loadLifeAdminByIdOrIdentifier(db: LifeAdminRouteDb, idOrIdentifier: string, domainIds?: string[]) {
  if (domainIds && domainIds.length === 0) return null;
  const normalizedIdentifier = idOrIdentifier.trim().toUpperLifeAdmin();
  const identityWhere = isUuidLike(idOrIdentifier)
    ? or(eq(life_admin.id, idOrIdentifier), eq(life_admin.identifier, normalizedIdentifier))
    : eq(life_admin.identifier, normalizedIdentifier);
  const where = domainIds
    ? and(identityWhere, inArray(life_admin.domainId, domainIds))
    : identityWhere;
  return db.select().from(life_admin).where(where).limit(1).then((rows) => rows[0] ?? null);
}

async function loadIssueByIdOrIdentifier(db: LifeAdminRouteDb, idOrIdentifier: string, domainIds?: string[]) {
  if (domainIds && domainIds.length === 0) return null;
  const normalizedIdentifier = idOrIdentifier.trim().toUpperLifeAdmin();
  const identityWhere = isUuidLike(idOrIdentifier)
    ? or(eq(issues.id, idOrIdentifier), eq(issues.identifier, normalizedIdentifier))
    : eq(issues.identifier, normalizedIdentifier);
  const where = domainIds
    ? and(identityWhere, inArray(issues.domainId, domainIds))
    : identityWhere;
  return db
    .select({ id: issues.id, domainId: issues.domainId })
    .from(issues)
    .where(where)
    .limit(1)
    .then((rows) => rows[0] ?? null);
}

function lifeAdminLookupDomainIds(req: Request) {
  if (req.actor.type === "agent") return req.actor.domainId ? [req.actor.domainId] : [];
  if (req.actor.type === "board" && req.actor.source === "local_implicit") return undefined;
  if (req.actor.type === "board" && Array.isArray(req.actor.domainIds) && req.actor.domainIds.length > 0) {
    return req.actor.domainIds;
  }
  if (req.actor.type === "board" && req.actor.isInstanceAdmin) return undefined;
  return [];
}

async function assertLifeAdminAccess(db: Db, req: Request, idOrIdentifier: string) {
  const row = await loadLifeAdminByIdOrIdentifier(db, idOrIdentifier, lifeAdminLookupDomainIds(req));
  if (!row) throw notFound("LifeAdmin not found");
  assertDomainAccess(req, row.domainId);
  return row;
}

// The workflows feature registers its own /life_admin/:lifeAdminId routes after this
// router. On paths both features share, return null (caller falls through via
// next()) when the id is not a new-LifeAdmin row so workflow life_admin requests still
// reach their handler regardless of the enableLifeAdmin flag.
async function resolveSharedPathLifeAdmin(db: Db, req: Request, idOrIdentifier: string) {
  const domainIds = lifeAdminLookupDomainIds(req);
  const row = await loadLifeAdminByIdOrIdentifier(db, idOrIdentifier, domainIds);
  if (!row) return null;
  await assertLifeAdminEnabled(db);
  assertDomainAccess(req, row.domainId);
  return row;
}

async function assertProjectBelongsToDomain(db: LifeAdminRouteDb, input: { domainId: string; projectId: string | null }) {
  if (!input.projectId) return;
  const row = await db
    .select({ id: projects.id })
    .from(projects)
    .where(and(eq(projects.id, input.projectId), eq(projects.domainId, input.domainId)))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!row) throw unprocessable("Project does not belong to domain");
}

async function assertParentLifeAdminBelongsToDomain(db: LifeAdminRouteDb, input: {
  domainId: string;
  lifeAdminId?: string;
  parentLifeAdminId: string | null;
}) {
  if (!input.parentLifeAdminId) return;
  if (input.lifeAdminId && input.parentLifeAdminId === input.lifeAdminId) {
    throw unprocessable("A life_admin cannot be its own parent");
  }
  const row = await db
    .select({ id: life_admin.id })
    .from(life_admin)
    .where(and(eq(life_admin.id, input.parentLifeAdminId), eq(life_admin.domainId, input.domainId)))
    .limit(1)
    .then((rows) => rows[0] ?? null);
  if (!row) throw unprocessable("Parent life_admin does not belong to domain");
}

async function assertLabelsBelongToDomain(db: LifeAdminRouteDb, domainId: string, labelIds: string[]) {
  if (labelIds.length === 0) return;
  const uniqueIds = [...new Set(labelIds)];
  const rows = await db
    .select({ id: labels.id })
    .from(labels)
    .where(and(eq(labels.domainId, domainId), inArray(labels.id, uniqueIds)));
  if (rows.length !== uniqueIds.length) {
    throw unprocessable("One or more labels do not belong to domain");
  }
}

async function insertLifeAdminEvent(db: LifeAdminRouteDb, input: {
  domainId: string;
  lifeAdminId: string;
  kind: typeof lifeAdminEvents.$inferInsert["kind"];
  actor: LifeAdminActor;
  payload?: Record<string, unknown>;
}) {
  const now = new Date();
  const [event] = await db.insert(lifeAdminEvents).values({
    domainId: input.domainId,
    lifeAdminId: input.lifeAdminId,
    kind: input.kind,
    ...eventActorValues(input.actor),
    payload: input.payload ?? {},
    createdAt: now,
    updatedAt: now,
  }).returning();
  return event!;
}

async function resolveIssueForRun(db: LifeAdminRouteDb, domainId: string, runId: string | null | undefined) {
  if (!runId || !isUuidLike(runId)) return null;
  return db
    .select({ id: issues.id })
    .from(issues)
    .where(and(
      eq(issues.domainId, domainId),
      or(
        eq(issues.executionRunId, runId),
        eq(issues.checkoutRunId, runId),
        eq(issues.originRunId, runId),
      ),
    ))
    .orderBy(desc(issues.updatedAt), desc(issues.createdAt))
    .limit(1)
    .then((rows) => rows[0] ?? null);
}

/** Batch resolve agent display names for a set of agent ids. */
async function resolveAgentNames(db: LifeAdminRouteDb, agentIds: (string | null)[]) {
  const valid = [...new Set(agentIds.filter((id): id is string => !!id))];
  if (valid.length === 0) return new Map<string, string>();
  const rows = await db
    .select({ id: agents.id, name: agents.name })
    .from(agents)
    .where(inArray(agents.id, valid));
  return new Map(rows.map((row) => [row.id, row.name]));
}

/**
 * Batch resolve run → issue attribution. Mirrors resolveIssueForRun's precedence
 * (latest-updated issue whose execution/checkout/origin run matches), but for a
 * whole set of runs at once so the activity feed / revisions rail avoid N+1s.
 */
async function resolveIssuesForRuns(db: LifeAdminRouteDb, domainId: string, runIds: (string | null)[]) {
  const valid = [...new Set(runIds.filter((id): id is string => !!id && isUuidLike(id)))];
  const map = new Map<string, { id: string; identifier: string; title: string; status: string }>();
  if (valid.length === 0) return map;
  const rows = await db
    .select({
      id: issues.id,
      identifier: issues.identifier,
      title: issues.title,
      status: issues.status,
      executionRunId: issues.executionRunId,
      checkoutRunId: issues.checkoutRunId,
      originRunId: issues.originRunId,
      updatedAt: issues.updatedAt,
      createdAt: issues.createdAt,
    })
    .from(issues)
    .where(and(
      eq(issues.domainId, domainId),
      or(
        inArray(issues.executionRunId, valid),
        inArray(issues.checkoutRunId, valid),
        inArray(issues.originRunId, valid),
      ),
    ))
    .orderBy(desc(issues.updatedAt), desc(issues.createdAt));
  for (const runId of valid) {
    const match = rows.find(
      (row) => row.executionRunId === runId || row.checkoutRunId === runId || row.originRunId === runId,
    );
    if (match) {
      map.set(runId, { id: match.id, identifier: match.identifier ?? match.id, title: match.title, status: match.status });
    }
  }
  return map;
}

function payloadIssueIdForEvent(kind: string, payload: Record<string, unknown> | null | undefined) {
  if (kind !== "issue_linked" && kind !== "issue_unlinked") return null;
  const issueId = payload?.issueId;
  return typeof issueId === "string" && isUuidLike(issueId) ? issueId : null;
}

async function resolveIssuesByIds(db: LifeAdminRouteDb, domainId: string, issueIds: (string | null)[]) {
  const valid = [...new Set(issueIds.filter((id): id is string => !!id && isUuidLike(id)))];
  const map = new Map<string, { id: string; identifier: string; title: string; status: string }>();
  if (valid.length === 0) return map;
  const rows = await db
    .select({
      id: issues.id,
      identifier: issues.identifier,
      title: issues.title,
      status: issues.status,
    })
    .from(issues)
    .where(and(eq(issues.domainId, domainId), inArray(issues.id, valid)));
  for (const row of rows) {
    map.set(row.id, { id: row.id, identifier: row.identifier ?? row.id, title: row.title, status: row.status });
  }
  return map;
}

async function autoLinkRunIssue(db: LifeAdminRouteDb, input: {
  domainId: string;
  lifeAdminId: string;
  actor: LifeAdminActor;
  role: "origin" | "work";
}) {
  const issue = await resolveIssueForRun(db, input.domainId, input.actor.runId);
  if (!issue) return null;
  const now = new Date();
  const [link] = await db.insert(lifeAdminIssueLinks).values({
    domainId: input.domainId,
    lifeAdminId: input.lifeAdminId,
    issueId: issue.id,
    role: input.role,
    createdByRunId: input.actor.runId && isUuidLike(input.actor.runId) ? input.actor.runId : null,
    createdAt: now,
    updatedAt: now,
  }).onConflictDoNothing({
    target: [lifeAdminIssueLinks.lifeAdminId, lifeAdminIssueLinks.issueId],
  }).returning();
  if (!link) return null;
  await insertLifeAdminEvent(db, {
    domainId: input.domainId,
    lifeAdminId: input.lifeAdminId,
    kind: "issue_linked",
    actor: input.actor,
    payload: { issueId: issue.id, role: input.role, autoLinked: true },
  });
  return link;
}

async function nextLifeAdminIdentity(db: LifeAdminRouteDb, domainId: string) {
  await db.execute(sql`select pg_advisory_xact_lock(hashtext(${`paperclip:life_admin:${domainId}`}))`);
  const [domain] = await db
    .select({ issuePrefix: domains.issuePrefix })
    .from(domains)
    .where(eq(domains.id, domainId))
    .limit(1);
  if (!domain) throw notFound("Domain not found");
  const [maxRow] = await db
    .select({ maxNum: sql<number>`coalesce(max(${life_admin.lifeAdminNumber}), 0)` })
    .from(life_admin)
    .where(eq(life_admin.domainId, domainId));
  const lifeAdminNumber = (maxRow?.maxNum ?? 0) + 1;
  return {
    lifeAdminNumber,
    identifier: `${domain.issuePrefix.toUpperLifeAdmin()}-C${lifeAdminNumber}`,
  };
}

function completedAtForStatus(status: string, previous?: Date | null) {
  if (status === "done" || status === "cancelled") return previous ?? new Date();
  return null;
}

type PatchLifeAdminBody = z.infer<typeof patchLifeAdminSchema>;

export function buildLifeAdminPatchUpdateValues(
  body: PatchLifeAdminBody,
  lifeAdminRow: Pick<typeof life_admin.$inferSelect, "status" | "completedAt">,
  now: Date,
) {
  const status = body.status ?? lifeAdminRow.status;
  return {
    ...(Object.hasOwn(body, "projectId") ? { projectId: body.projectId ?? null } : {}),
    ...(body.title !== undefined ? { title: body.title } : {}),
    ...(Object.hasOwn(body, "summary") ? { summary: body.summary ?? null } : {}),
    ...(body.status !== undefined ? { status, completedAt: completedAtForStatus(status, lifeAdminRow.completedAt) } : {}),
    ...(body.fields !== undefined ? { fields: body.fields } : {}),
    ...(Object.hasOwn(body, "parentLifeAdminId") ? { parentLifeAdminId: body.parentLifeAdminId ?? null } : {}),
    updatedAt: now,
  };
}

async function loadLifeAdminDetail(db: LifeAdminRouteDb, row: typeof life_admin.$inferSelect) {
  const [labelRows, linkRows, documentRows, attachmentRows] = await Promise.all([
    db
      .select({ label: labels })
      .from(lifeAdminLabels)
      .innerJoin(labels, eq(lifeAdminLabels.labelId, labels.id))
      .where(and(eq(lifeAdminLabels.domainId, row.domainId), eq(lifeAdminLabels.lifeAdminId, row.id)))
      .orderBy(asc(labels.name)),
    db
      .select({ link: lifeAdminIssueLinks, issue: issues })
      .from(lifeAdminIssueLinks)
      .innerJoin(issues, eq(lifeAdminIssueLinks.issueId, issues.id))
      .where(and(eq(lifeAdminIssueLinks.domainId, row.domainId), eq(lifeAdminIssueLinks.lifeAdminId, row.id)))
      .orderBy(asc(lifeAdminIssueLinks.createdAt)),
    db
      .select({ link: lifeAdminDocuments, document: documents })
      .from(lifeAdminDocuments)
      .innerJoin(documents, eq(lifeAdminDocuments.documentId, documents.id))
      .where(and(eq(lifeAdminDocuments.domainId, row.domainId), eq(lifeAdminDocuments.lifeAdminId, row.id)))
      .orderBy(asc(lifeAdminDocuments.key)),
    db
      .select({ link: lifeAdminAttachments, asset: assets })
      .from(lifeAdminAttachments)
      .innerJoin(assets, eq(lifeAdminAttachments.assetId, assets.id))
      .where(and(eq(lifeAdminAttachments.domainId, row.domainId), eq(lifeAdminAttachments.lifeAdminId, row.id)))
      .orderBy(asc(lifeAdminAttachments.createdAt)),
  ]);
  const parent = row.parentLifeAdminId
    ? await db
      .select({
        id: life_admin.id,
        identifier: life_admin.identifier,
        title: life_admin.title,
        lifeAdminType: life_admin.lifeAdminType,
        status: life_admin.status,
      })
      .from(life_admin)
      .where(eq(life_admin.id, row.parentLifeAdminId))
      .limit(1)
      .then((rows) => rows[0] ?? null)
    : null;
  return {
    ...row,
    parent,
    labels: labelRows.map((item) => item.label),
    issueLinks: linkRows.map((item) => ({
      ...item.link,
      issue: {
        id: item.issue.id,
        identifier: item.issue.identifier,
        title: item.issue.title,
        status: item.issue.status,
      },
    })),
    documents: documentRows.map((item) => ({
      key: item.link.key,
      document: item.document,
    })),
    attachments: attachmentRows.map((item) => ({
      id: item.link.id,
      asset: item.asset,
      createdAt: item.link.createdAt,
      updatedAt: item.link.updatedAt,
    })),
  };
}

async function loadLifeAdminDocumentLink(db: LifeAdminRouteDb, input: { domainId: string; lifeAdminId: string; key: string }) {
  return db
    .select({ link: lifeAdminDocuments, document: documents })
    .from(lifeAdminDocuments)
    .innerJoin(documents, eq(lifeAdminDocuments.documentId, documents.id))
    .where(and(
      eq(lifeAdminDocuments.domainId, input.domainId),
      eq(lifeAdminDocuments.lifeAdminId, input.lifeAdminId),
      eq(lifeAdminDocuments.key, input.key),
    ))
    .limit(1)
    .then((rows) => rows[0] ?? null);
}

async function includeLifeAdminAncestors(
  db: LifeAdminRouteDb,
  domainId: string,
  baseRows: Array<typeof life_admin.$inferSelect>,
) {
  const baseIds = new Set(baseRows.map((row) => row.id));
  const rowsById = new Map(baseRows.map((row) => [row.id, row]));
  const ancestorRows: Array<typeof life_admin.$inferSelect> = [];
  let pending = [...new Set(
    baseRows
      .map((row) => row.parentLifeAdminId)
      .filter((id): id is string => {
        if (!id) return false;
        return !rowsById.has(id);
      }),
  )];

  while (pending.length > 0) {
    const ancestors = await db
      .select()
      .from(life_admin)
      .where(and(eq(life_admin.domainId, domainId), inArray(life_admin.id, pending)));
    const nextPending = new Set<string>();
    for (const row of ancestors) {
      if (rowsById.has(row.id)) continue;
      rowsById.set(row.id, row);
      ancestorRows.push(row);
      if (row.parentLifeAdminId && !rowsById.has(row.parentLifeAdminId)) {
        nextPending.add(row.parentLifeAdminId);
      }
    }
    pending = [...nextPending];
  }

  return [...baseRows, ...ancestorRows].map((row) => ({
    ...row,
    matchesListFilters: baseIds.has(row.id),
  }));
}

function lifeAdminDocumentResponse(input: { key: string; document: typeof documents.$inferSelect }) {
  return {
    ...input.document,
    key: input.key,
    body: input.document.latestBody,
  };
}

function singleFileUpload(req: Request, res: Response, maxBytes: number) {
  const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: maxBytes, files: 1 },
  }).single("file");
  return new Promise<void>((resolve, reject) => {
    upload(req, res, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

export function lifeAdminRoutes(db: Db, storage: StorageService) {
  const router = Router();
  const documentAnnotationsSvc = documentAnnotationService(db);

  async function logLifeAdminAnnotationRemaps(input: {
    lifeAdminRow: typeof life_admin.$inferSelect;
    key: string;
    document: Pick<typeof documents.$inferSelect, "id" | "latestRevisionId" | "latestRevisionNumber">;
    body: string;
    actor: LifeAdminActor;
  }) {
    const remapped = await documentAnnotationsSvc.remapOpenThreadsForLifeAdminDocument({
      lifeAdminId: input.lifeAdminRow.id,
      key: input.key,
      documentId: input.document.id,
      nextRevisionId: input.document.latestRevisionId,
      nextRevisionNumber: input.document.latestRevisionNumber,
      nextBody: input.body,
    });
    for (const remap of remapped) {
      await logActivity(db, {
        domainId: input.lifeAdminRow.domainId,
        actorType: input.actor.actorType,
        actorId: input.actor.actorId,
        agentId: input.actor.agentId,
        runId: input.actor.runId,
        action: "life_admin.document_annotation_remapped",
        entityType: "life_admin",
        entityId: input.lifeAdminRow.id,
        details: {
          key: input.key,
          documentKey: input.key,
          documentId: input.document.id,
          threadId: remap.thread.id,
          revisionNumber: input.document.latestRevisionNumber,
          anchorState: remap.thread.anchorState,
          anchorConfidence: remap.thread.anchorConfidence,
          snapshotId: remap.snapshot.id,
        },
      });
    }
  }

  router.post("/domains/:domainId/life_admin", validate(createLifeAdminSchema), async (req, res) => {
    await assertLifeAdminEnabled(db);
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const actor = getActorInfo(req);
    const body = req.body as z.infer<typeof createLifeAdminSchema>;

    const result = await db.transaction(async (tx) => {
      await assertProjectBelongsToDomain(tx, { domainId, projectId: body.projectId ?? null });
      await assertParentLifeAdminBelongsToDomain(tx, { domainId, parentLifeAdminId: body.parentLifeAdminId ?? null });
      await lockLifeAdminUpsertKey(tx, { domainId, lifeAdminType: body.lifeAdminType, key: body.key });
      const keyFilter = body.key ? eq(life_admin.key, body.key) : isNull(life_admin.key);

      const now = new Date();
      const existing = await tx
        .select()
        .from(life_admin)
        .where(and(eq(life_admin.domainId, domainId), eq(life_admin.lifeAdminType, body.lifeAdminType), keyFilter))
        .limit(1)
        .then((rows) => rows[0] ?? null);

      if (existing) {
        const status = body.status ?? existing.status;
        const [updated] = await tx.update(life_admin).set({
          projectId: body.projectId ?? existing.projectId,
          title: body.title,
          summary: body.summary ?? existing.summary,
          status,
          fields: body.fields ?? existing.fields,
          parentLifeAdminId: body.parentLifeAdminId ?? existing.parentLifeAdminId,
          completedAt: completedAtForStatus(status, existing.completedAt),
          updatedAt: now,
        }).where(eq(life_admin.id, existing.id)).returning();
        await insertLifeAdminEvent(tx, {
          domainId,
          lifeAdminId: existing.id,
          kind: "updated",
          actor,
          payload: { upsert: true },
        });
        await autoLinkRunIssue(tx, { domainId, lifeAdminId: existing.id, actor, role: "origin" });
        return { created: false, row: updated! };
      }

      const identity = await nextLifeAdminIdentity(tx, domainId);
      const status = body.status ?? "draft";
      const [created] = await tx.insert(life_admin).values({
        domainId,
        projectId: body.projectId ?? null,
        ...identity,
        lifeAdminType: body.lifeAdminType,
        key: body.key ?? null,
        title: body.title,
        summary: body.summary ?? null,
        status,
        fields: body.fields ?? {},
        parentLifeAdminId: body.parentLifeAdminId ?? null,
        createdByAgentId: actor.agentId,
        createdByUserId: actor.actorType === "user" ? actor.actorId : null,
        completedAt: completedAtForStatus(status),
        createdAt: now,
        updatedAt: now,
      }).returning();
      await insertLifeAdminEvent(tx, {
        domainId,
        lifeAdminId: created!.id,
        kind: "created",
        actor,
        payload: { lifeAdminType: body.lifeAdminType, key: body.key ?? null },
      });
      await autoLinkRunIssue(tx, { domainId, lifeAdminId: created!.id, actor, role: "origin" });
      return { created: true, row: created! };
    });

    res.status(result.created ? 201 : 200).json(await loadLifeAdminDetail(db, result.row));
  });

  router.get("/domains/:domainId/life_admin", async (req, res) => {
    await assertLifeAdminEnabled(db);
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const parsed = listLifeAdminQuerySchema.safeParse(req.query);
    if (!parsed.success) throw badRequest("Invalid life_admin list query", parsed.error.issues);
    const query = parsed.data;
    const filters = [eq(life_admin.domainId, domainId)];
    const typeFilters = parseQueryList(query.types ?? query.type);
    if (typeFilters.length === 1) filters.push(eq(life_admin.lifeAdminType, typeFilters[0]!));
    else if (typeFilters.length > 1) filters.push(inArray(life_admin.lifeAdminType, typeFilters));

    const statusFilters = parseQueryList(query.statuses ?? (query.status === "active" ? undefined : query.status));
    if (query.status === "active" && statusFilters.length === 0) {
      filters.push(sql`${life_admin.status} not in ('done', 'cancelled')`);
    } else if (statusFilters.length > 0) {
      for (const status of statusFilters) {
        if (!LIFE_ADMIN_STATUSES.includes(status as (typeof LIFE_ADMIN_STATUSES)[number])) {
          throw badRequest("Invalid life_admin status");
        }
      }
      filters.push(statusFilters.length === 1 ? eq(life_admin.status, statusFilters[0]!) : inArray(life_admin.status, statusFilters));
    }

    const projectFilters = parseQueryList(query.projectIds ?? query.projectId ?? query.project);
    for (const projectId of projectFilters) {
      if (!isUuidLike(projectId)) throw badRequest("Invalid project id");
    }
    const includeNoProject = parseBooleanQuery(query.includeNoProject);
    if (projectFilters.length > 0 && includeNoProject) {
      filters.push(or(inArray(life_admin.projectId, projectFilters), isNull(life_admin.projectId))!);
    } else if (projectFilters.length === 1) {
      filters.push(eq(life_admin.projectId, projectFilters[0]!));
    } else if (projectFilters.length > 1) {
      filters.push(inArray(life_admin.projectId, projectFilters));
    } else if (includeNoProject) {
      filters.push(isNull(life_admin.projectId));
    }
    if (query.parent) filters.push(eq(life_admin.parentLifeAdminId, query.parent));
    const labelId = query.labelId ?? query.label;
    if (labelId) {
      filters.push(sql`${life_admin.id} in (
        select ${lifeAdminLabels.lifeAdminId} from ${lifeAdminLabels}
        where ${lifeAdminLabels.domainId} = ${domainId} and ${lifeAdminLabels.labelId} = ${labelId}
      )`);
    }
    if (query.q) {
      const pattern = `%${query.q.replaceAll("%", "\\%").replaceAll("_", "\\_")}%`;
      filters.push(or(
        ilike(life_admin.identifier, pattern),
        ilike(life_admin.title, pattern),
        ilike(life_admin.summary, pattern),
        ilike(life_admin.key, pattern),
      )!);
    }

    const rows = await db
      .select()
      .from(life_admin)
      .where(and(...filters))
      .orderBy(desc(life_admin.updatedAt), desc(life_admin.createdAt))
      .limit(query.limit);
    res.json(parseBooleanQuery(query.includeAncestors) ? await includeLifeAdminAncestors(db, domainId, rows) : rows);
  });

  router.get("/life_admin/:id/documents/:key", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    const link = await loadLifeAdminDocumentLink(db, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
    if (!link) throw notFound("LifeAdmin document not found");
    res.json(lifeAdminDocumentResponse({ key, document: link.document }));
  });

  router.get("/life_admin/:id/documents/:key/annotations", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    const status = req.query.status === "resolved" || req.query.status === "all" ? req.query.status : "open";
    const threads = await documentAnnotationsSvc.listThreadsForLifeAdminDocument(lifeAdminRow.id, key, {
      status,
      includeComments: parseBooleanQuery(req.query.includeComments),
    });
    res.json(threads);
  });

  router.get("/life_admin/:id/documents/:key/annotations/:threadId", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    const thread = await documentAnnotationsSvc.getThreadForLifeAdminDocument(
      lifeAdminRow.id,
      key,
      req.params.threadId as string,
    );
    if (!thread) throw notFound("Annotation thread not found");
    res.json(thread);
  });

  router.post(
    "/life_admin/:id/documents/:key/annotations",
    validate(createDocumentAnnotationThreadSchema),
    async (req, res, next) => {
      const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
      if (!lifeAdminRow) return next();
      const key = parseDocumentKey(req.params.key as string);
      const { actor, annotationActor } = annotationActorInput(req);
      const thread = await documentAnnotationsSvc.createLifeAdminThread(
        lifeAdminRow.id,
        key,
        req.body,
        annotationActor,
      );
      const firstComment = thread.comments[0];
      await logActivity(db, {
        domainId: lifeAdminRow.domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "life_admin.document_annotation_thread_created",
        entityType: "life_admin",
        entityId: lifeAdminRow.id,
        details: {
          key: thread.documentKey,
          documentKey: thread.documentKey,
          documentId: thread.documentId,
          threadId: thread.id,
          commentId: firstComment?.id ?? null,
          revisionNumber: thread.currentRevisionNumber,
          quote: thread.selectedText.slice(0, 240),
        },
      });
      res.status(201).json(thread);
    },
  );

  router.post(
    "/life_admin/:id/documents/:key/annotations/:threadId/comments",
    validate(createDocumentAnnotationCommentSchema),
    async (req, res, next) => {
      const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
      if (!lifeAdminRow) return next();
      const key = parseDocumentKey(req.params.key as string);
      const { actor, annotationActor } = annotationActorInput(req);
      const comment = await documentAnnotationsSvc.addLifeAdminComment(
        lifeAdminRow.id,
        key,
        req.params.threadId as string,
        req.body,
        annotationActor,
      );
      await logActivity(db, {
        domainId: lifeAdminRow.domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "life_admin.document_annotation_comment_added",
        entityType: "life_admin",
        entityId: lifeAdminRow.id,
        details: {
          key,
          documentKey: key,
          threadId: comment.threadId,
          commentId: comment.id,
          bodySnippet: comment.body.slice(0, 120),
        },
      });
      res.status(201).json(comment);
    },
  );

  router.patch(
    "/life_admin/:id/documents/:key/annotations/:threadId",
    validate(updateDocumentAnnotationThreadSchema),
    async (req, res, next) => {
      const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
      if (!lifeAdminRow) return next();
      const key = parseDocumentKey(req.params.key as string);
      const { actor, annotationActor } = annotationActorInput(req);
      const thread = await documentAnnotationsSvc.updateLifeAdminThread(
        lifeAdminRow.id,
        key,
        req.params.threadId as string,
        req.body,
        annotationActor,
      );
      await logActivity(db, {
        domainId: lifeAdminRow.domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: thread.status === "resolved"
          ? "life_admin.document_annotation_thread_resolved"
          : "life_admin.document_annotation_thread_reopened",
        entityType: "life_admin",
        entityId: lifeAdminRow.id,
        details: {
          key: thread.documentKey,
          documentKey: thread.documentKey,
          documentId: thread.documentId,
          threadId: thread.id,
          status: thread.status,
        },
      });
      res.json(thread);
    },
  );

  router.put("/life_admin/:id/documents/:key", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    const actor = getActorInfo(req);
    const body = upsertLifeAdminDocumentSchema.parse(req.body);

    const result = await db.transaction(async (tx) => {
      await lockLifeAdminDocumentKey(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      const existing = await tx
        .select({ link: lifeAdminDocuments, document: documents, revision: documentRevisions })
        .from(lifeAdminDocuments)
        .innerJoin(documents, eq(lifeAdminDocuments.documentId, documents.id))
        .leftJoin(documentRevisions, eq(documents.latestRevisionId, documentRevisions.id))
        .where(and(
          eq(lifeAdminDocuments.domainId, lifeAdminRow.domainId),
          eq(lifeAdminDocuments.lifeAdminId, lifeAdminRow.id),
          eq(lifeAdminDocuments.key, key),
        ))
        .limit(1)
        .then((rows) => rows[0] ?? null);

      if (existing?.document.lockedAt) {
        throw conflict("Document is locked", {
          key,
          documentId: existing.document.id,
          lockedAt: existing.document.lockedAt,
        });
      }
      if (existing && !body.baseRevisionId) {
        throw conflict("LifeAdmin document update requires baseRevisionId", {
          code: "stale_base_revision",
          latestRevisionId: existing.document.latestRevisionId,
          latestRevisionNumber: existing.document.latestRevisionNumber,
        });
      }
      if (existing && body.baseRevisionId !== existing.document.latestRevisionId) {
        throw conflict("LifeAdmin document was updated by someone else", {
          code: "stale_base_revision",
          latestRevisionId: existing.document.latestRevisionId,
          latestRevisionNumber: existing.document.latestRevisionNumber,
          latestRevision: existing.revision,
        });
      }
      if (!existing && body.baseRevisionId) {
        throw conflict("LifeAdmin document does not exist yet", {
          code: "stale_base_revision",
          latestRevisionId: null,
          latestRevisionNumber: null,
        });
      }

      const now = new Date();
      const [document] = existing
        ? await tx.update(documents).set({
          title: body.title ?? existing.document.title,
          format: body.format,
          updatedAt: now,
          updatedByAgentId: actor.agentId,
          updatedByUserId: actor.actorType === "user" ? actor.actorId : null,
        }).where(eq(documents.id, existing.document.id)).returning()
        : await tx.insert(documents).values({
          domainId: lifeAdminRow.domainId,
          title: body.title ?? key,
          format: body.format,
          latestBody: body.body,
          latestRevisionNumber: 1,
          createdByAgentId: actor.agentId,
          createdByUserId: actor.actorType === "user" ? actor.actorId : null,
          updatedByAgentId: actor.agentId,
          updatedByUserId: actor.actorType === "user" ? actor.actorId : null,
          createdAt: now,
          updatedAt: now,
        }).returning();
      const nextRevisionNumber = existing ? existing.document.latestRevisionNumber + 1 : 1;
      const [revision] = await tx.insert(documentRevisions).values({
        domainId: lifeAdminRow.domainId,
        documentId: document!.id,
        revisionNumber: nextRevisionNumber,
        title: body.title ?? document!.title,
        format: body.format,
        body: body.body,
        changeSummary: body.changeSummary ?? null,
        createdByAgentId: actor.agentId,
        createdByUserId: actor.actorType === "user" ? actor.actorId : null,
        createdByRunId: actor.runId && isUuidLike(actor.runId) ? actor.runId : null,
        createdAt: now,
      }).returning();
      await tx.update(documents).set({
        title: body.title ?? document!.title,
        format: body.format,
        latestBody: body.body,
        latestRevisionId: revision!.id,
        latestRevisionNumber: revision!.revisionNumber,
        updatedByAgentId: actor.agentId,
        updatedByUserId: actor.actorType === "user" ? actor.actorId : null,
        updatedAt: now,
      }).where(eq(documents.id, document!.id));
      if (!existing) {
        await tx.insert(lifeAdminDocuments).values({
          domainId: lifeAdminRow.domainId,
          lifeAdminId: lifeAdminRow.id,
          documentId: document!.id,
          key,
          createdAt: now,
          updatedAt: now,
        });
      } else {
        await tx.update(lifeAdminDocuments).set({ updatedAt: now }).where(eq(lifeAdminDocuments.documentId, document!.id));
      }
      await insertLifeAdminEvent(tx, {
        domainId: lifeAdminRow.domainId,
        lifeAdminId: lifeAdminRow.id,
        kind: "document_revised",
        actor,
        payload: { key, documentId: document!.id, revisionId: revision!.id, revisionNumber: revision!.revisionNumber },
      });
      await autoLinkRunIssue(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, actor, role: "work" });
      return {
        document: {
          ...document!,
          title: body.title ?? document!.title,
          format: body.format,
          latestBody: body.body,
          latestRevisionId: revision!.id,
          latestRevisionNumber: revision!.revisionNumber,
          updatedAt: now,
        },
        revision,
      };
    });
    await logLifeAdminAnnotationRemaps({
      lifeAdminRow,
      key,
      document: result.document,
      body: result.document.latestBody,
      actor,
    });
    res.json(result);
  });

  router.post("/life_admin/:id/documents/:key/lock", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    const actor = getActorInfo(req);
    const result = await db.transaction(async (tx) => {
      await lockLifeAdminDocumentKey(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      const link = await loadLifeAdminDocumentLink(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      if (!link) throw notFound("LifeAdmin document not found");
      if (link.document.lockedAt) return lifeAdminDocumentResponse({ key, document: link.document });
      const now = new Date();
      const [document] = await tx.update(documents).set({
        lockedAt: now,
        lockedByAgentId: actor.agentId,
        lockedByUserId: actor.actorType === "user" ? actor.actorId : null,
        updatedAt: now,
      }).where(eq(documents.id, link.document.id)).returning();
      await tx.update(lifeAdminDocuments).set({ updatedAt: now }).where(eq(lifeAdminDocuments.documentId, link.document.id));
      return lifeAdminDocumentResponse({ key, document: document! });
    });
    res.json(result);
  });

  router.post("/life_admin/:id/documents/:key/unlock", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    const result = await db.transaction(async (tx) => {
      await lockLifeAdminDocumentKey(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      const link = await loadLifeAdminDocumentLink(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      if (!link) throw notFound("LifeAdmin document not found");
      if (!link.document.lockedAt) return lifeAdminDocumentResponse({ key, document: link.document });
      const now = new Date();
      const [document] = await tx.update(documents).set({
        lockedAt: null,
        lockedByAgentId: null,
        lockedByUserId: null,
        updatedAt: now,
      }).where(eq(documents.id, link.document.id)).returning();
      await tx.update(lifeAdminDocuments).set({ updatedAt: now }).where(eq(lifeAdminDocuments.documentId, link.document.id));
      return lifeAdminDocumentResponse({ key, document: document! });
    });
    res.json(result);
  });

  router.post("/life_admin/:id/documents/:key/revisions/:revisionId/restore", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    const revisionId = req.params.revisionId as string;
    const actor = getActorInfo(req);

    const result = await db.transaction(async (tx) => {
      await lockLifeAdminDocumentKey(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      const existing = await loadLifeAdminDocumentLink(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      if (!existing) throw notFound("LifeAdmin document not found");
      if (existing.document.lockedAt) {
        throw conflict("Document is locked", {
          key,
          documentId: existing.document.id,
          lockedAt: existing.document.lockedAt,
        });
      }
      const sourceRevision = await tx
        .select()
        .from(documentRevisions)
        .where(and(eq(documentRevisions.id, revisionId), eq(documentRevisions.documentId, existing.document.id)))
        .limit(1)
        .then((rows) => rows[0] ?? null);
      if (!sourceRevision) throw notFound("LifeAdmin document revision not found");
      if (existing.document.latestRevisionId === sourceRevision.id) {
        throw conflict("Selected revision is already the latest revision", {
          currentRevisionId: existing.document.latestRevisionId,
        });
      }

      const now = new Date();
      const nextRevisionNumber = existing.document.latestRevisionNumber + 1;
      const [restoredRevision] = await tx.insert(documentRevisions).values({
        domainId: lifeAdminRow.domainId,
        documentId: existing.document.id,
        revisionNumber: nextRevisionNumber,
        title: sourceRevision.title ?? null,
        format: sourceRevision.format,
        body: sourceRevision.body,
        changeSummary: `Restored from revision ${sourceRevision.revisionNumber}`,
        createdByAgentId: actor.agentId,
        createdByUserId: actor.actorType === "user" ? actor.actorId : null,
        createdByRunId: actor.runId && isUuidLike(actor.runId) ? actor.runId : null,
        createdAt: now,
      }).returning();
      const [document] = await tx.update(documents).set({
        title: sourceRevision.title ?? null,
        format: sourceRevision.format,
        latestBody: sourceRevision.body,
        latestRevisionId: restoredRevision!.id,
        latestRevisionNumber: nextRevisionNumber,
        updatedByAgentId: actor.agentId,
        updatedByUserId: actor.actorType === "user" ? actor.actorId : null,
        updatedAt: now,
      }).where(eq(documents.id, existing.document.id)).returning();
      await tx.update(lifeAdminDocuments).set({ updatedAt: now }).where(eq(lifeAdminDocuments.documentId, existing.document.id));
      await insertLifeAdminEvent(tx, {
        domainId: lifeAdminRow.domainId,
        lifeAdminId: lifeAdminRow.id,
        kind: "document_revised",
        actor,
        payload: {
          key,
          documentId: existing.document.id,
          revisionId: restoredRevision!.id,
          revisionNumber: restoredRevision!.revisionNumber,
          restoredFromRevisionId: sourceRevision.id,
          restoredFromRevisionNumber: sourceRevision.revisionNumber,
        },
      });
      await autoLinkRunIssue(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, actor, role: "work" });
      return {
        document: lifeAdminDocumentResponse({ key, document: document! }),
        revision: restoredRevision!,
        restoredFromRevisionId: sourceRevision.id,
        restoredFromRevisionNumber: sourceRevision.revisionNumber,
      };
    });
    await logLifeAdminAnnotationRemaps({
      lifeAdminRow,
      key,
      document: result.document,
      body: result.document.body,
      actor,
    });
    res.json(result);
  });

  router.delete("/life_admin/:id/documents/:key", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    await db.transaction(async (tx) => {
      await lockLifeAdminDocumentKey(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      const link = await loadLifeAdminDocumentLink(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, key });
      if (!link) return;
      if (link.document.lockedAt) {
        throw conflict("Document is locked", {
          key,
          documentId: link.document.id,
          lockedAt: link.document.lockedAt,
        });
      }
      await tx.delete(lifeAdminDocuments).where(eq(lifeAdminDocuments.documentId, link.document.id));
      await tx.delete(documents).where(eq(documents.id, link.document.id));
    });
    res.json({ ok: true });
  });

  router.post("/life_admin/:id/links", validate(createIssueLinkSchema), async (req, res) => {
    await assertLifeAdminEnabled(db);
    const lifeAdminRow = await assertLifeAdminAccess(db, req, req.params.id as string);
    const actor = getActorInfo(req);
    const body = req.body as z.infer<typeof createIssueLinkSchema>;

    const result = await db.transaction(async (tx) => {
      const issue = await tx
        .select({ id: issues.id })
        .from(issues)
        .where(and(eq(issues.id, body.issueId), eq(issues.domainId, lifeAdminRow.domainId)))
        .limit(1)
        .then((rows) => rows[0] ?? null);
      if (!issue) throw unprocessable("Issue does not belong to life_admin domain");
      const now = new Date();
      const [link] = await tx.insert(lifeAdminIssueLinks).values({
        domainId: lifeAdminRow.domainId,
        lifeAdminId: lifeAdminRow.id,
        issueId: body.issueId,
        role: body.role,
        createdByRunId: actor.runId && isUuidLike(actor.runId) ? actor.runId : null,
        createdAt: now,
        updatedAt: now,
      }).onConflictDoNothing({
        target: [lifeAdminIssueLinks.lifeAdminId, lifeAdminIssueLinks.issueId],
      }).returning();
      if (link) {
        await insertLifeAdminEvent(tx, {
          domainId: lifeAdminRow.domainId,
          lifeAdminId: lifeAdminRow.id,
          kind: "issue_linked",
          actor,
          payload: { issueId: body.issueId, role: body.role, autoLinked: false },
        });
      }
      return link ?? await tx
        .select()
        .from(lifeAdminIssueLinks)
        .where(and(eq(lifeAdminIssueLinks.lifeAdminId, lifeAdminRow.id), eq(lifeAdminIssueLinks.issueId, body.issueId)))
        .limit(1)
        .then((rows) => rows[0]);
    });
    res.status(201).json(result);
  });

  router.post("/life_admin/:id/attachments", async (req, res) => {
    await assertLifeAdminEnabled(db);
    const lifeAdminRow = await assertLifeAdminAccess(db, req, req.params.id as string);
    const actor = getActorInfo(req);
    const [domain] = await db
      .select({ attachmentMaxBytes: domains.attachmentMaxBytes })
      .from(domains)
      .where(eq(domains.id, lifeAdminRow.domainId))
      .limit(1);
    const maxBytes = domain?.attachmentMaxBytes ?? 10 * 1024 * 1024;

    try {
      await singleFileUpload(req, res, maxBytes);
    } catch (err) {
      if (err instanceof multer.MulterError) {
        if (err.code === "LIMIT_FILE_SIZE") {
          throw unprocessable(`Attachment exceeds ${maxBytes} bytes`);
        }
        throw badRequest(err.message);
      }
      throw err;
    }
    const file = (req as Request & { file?: { mimetype: string; buffer: Buffer; originalname: string } }).file;
    if (!file) throw badRequest("Missing file field 'file'");
    if (file.buffer.length <= 0) throw unprocessable("Attachment is empty");

    const stored = await storage.putFile({
      domainId: lifeAdminRow.domainId,
      namespace: `life_admin/${lifeAdminRow.id}`,
      originalFilename: file.originalname || null,
      contentType: normalizeContentType(file.mimetype),
      body: file.buffer,
    });
    const result = await db.transaction(async (tx) => {
      const now = new Date();
      const [asset] = await tx.insert(assets).values({
        domainId: lifeAdminRow.domainId,
        provider: stored.provider,
        objectKey: stored.objectKey,
        contentType: stored.contentType,
        byteSize: stored.byteSize,
        sha256: stored.sha256,
        originalFilename: stored.originalFilename,
        createdByAgentId: actor.agentId,
        createdByUserId: actor.actorType === "user" ? actor.actorId : null,
        createdAt: now,
        updatedAt: now,
      }).returning();
      const [attachment] = await tx.insert(lifeAdminAttachments).values({
        domainId: lifeAdminRow.domainId,
        lifeAdminId: lifeAdminRow.id,
        assetId: asset!.id,
        createdAt: now,
        updatedAt: now,
      }).returning();
      await insertLifeAdminEvent(tx, {
        domainId: lifeAdminRow.domainId,
        lifeAdminId: lifeAdminRow.id,
        kind: "attachment_added",
        actor,
        payload: { attachmentId: attachment!.id, assetId: asset!.id, originalFilename: asset!.originalFilename },
      });
      await autoLinkRunIssue(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, actor, role: "work" });
      return { ...attachment!, asset };
    });
    res.status(201).json(result);
  });

  router.get("/life_admin/:id/events", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const parsed = listEventsQuerySchema.safeParse(req.query);
    if (!parsed.success) throw badRequest("Invalid life_admin events query", parsed.error.issues);
    const rows = await db
      .select()
      .from(lifeAdminEvents)
      .where(and(eq(lifeAdminEvents.domainId, lifeAdminRow.domainId), eq(lifeAdminEvents.lifeAdminId, lifeAdminRow.id)))
      .orderBy(desc(lifeAdminEvents.createdAt), desc(lifeAdminEvents.id))
      .limit(parsed.data.limit);
    // Enrich each row with its actor's display name, run→issue attribution,
    // and the linked issue captured in link/unlink payloads.
    const payloadIssueIds = rows.map((row) => payloadIssueIdForEvent(row.kind, row.payload));
    const [agentNames, issueMap, payloadIssueMap] = await Promise.all([
      resolveAgentNames(db, rows.map((row) => row.actorAgentId)),
      resolveIssuesForRuns(db, lifeAdminRow.domainId, rows.map((row) => row.runId)),
      resolveIssuesByIds(db, lifeAdminRow.domainId, payloadIssueIds),
    ]);
    res.json(rows.map((row) => ({
      ...row,
      actorAgentName: row.actorAgentId ? agentNames.get(row.actorAgentId) ?? null : null,
      issue: payloadIssueMap.get(payloadIssueIdForEvent(row.kind, row.payload) ?? "")
        ?? (row.runId ? issueMap.get(row.runId) ?? null : null),
    })));
  });

  router.get("/life_admin/:id/documents/:key/revisions", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const key = parseDocumentKey(req.params.key as string);
    const link = await db
      .select({ documentId: lifeAdminDocuments.documentId, document: documents })
      .from(lifeAdminDocuments)
      .innerJoin(documents, eq(lifeAdminDocuments.documentId, documents.id))
      .where(and(
        eq(lifeAdminDocuments.domainId, lifeAdminRow.domainId),
        eq(lifeAdminDocuments.lifeAdminId, lifeAdminRow.id),
        eq(lifeAdminDocuments.key, key),
      ))
      .limit(1)
      .then((rows) => rows[0] ?? null);
    if (!link) throw notFound("LifeAdmin document not found");
    const revisions = await db
      .select()
      .from(documentRevisions)
      .where(and(
        eq(documentRevisions.domainId, lifeAdminRow.domainId),
        eq(documentRevisions.documentId, link.documentId),
      ))
      .orderBy(desc(documentRevisions.revisionNumber));
    const [agentNames, issueMap] = await Promise.all([
      resolveAgentNames(db, revisions.map((rev) => rev.createdByAgentId)),
      resolveIssuesForRuns(db, lifeAdminRow.domainId, revisions.map((rev) => rev.createdByRunId)),
    ]);
    res.json({
      key,
      document: {
        id: link.document.id,
        title: link.document.title,
        format: link.document.format,
        latestRevisionId: link.document.latestRevisionId,
        latestRevisionNumber: link.document.latestRevisionNumber,
      },
      revisions: revisions.map((rev) => ({
        id: rev.id,
        revisionNumber: rev.revisionNumber,
        title: rev.title,
        format: rev.format,
        body: rev.body,
        changeSummary: rev.changeSummary,
        createdAt: rev.createdAt,
        createdByAgentId: rev.createdByAgentId,
        createdByUserId: rev.createdByUserId,
        createdByRunId: rev.createdByRunId,
        actorAgentName: rev.createdByAgentId ? agentNames.get(rev.createdByAgentId) ?? null : null,
        issue: rev.createdByRunId ? issueMap.get(rev.createdByRunId) ?? null : null,
      })),
    });
  });

  router.get("/issues/:issueId/life_admin", async (req, res) => {
    await assertLifeAdminEnabled(db);
    const issueIdOrIdentifier = (req.params.issueId as string).trim();
    const issue = await loadIssueByIdOrIdentifier(db, issueIdOrIdentifier, lifeAdminLookupDomainIds(req));
    if (!issue) throw notFound("Issue not found");
    assertDomainAccess(req, issue.domainId);
    const rows = await db
      .select({ link: lifeAdminIssueLinks, lifeAdminRow: life_admin })
      .from(lifeAdminIssueLinks)
      .innerJoin(life_admin, eq(lifeAdminIssueLinks.lifeAdminId, life_admin.id))
      .where(and(eq(lifeAdminIssueLinks.domainId, issue.domainId), eq(lifeAdminIssueLinks.issueId, issue.id)))
      .orderBy(asc(lifeAdminIssueLinks.createdAt));
    res.json(rows.map((row) => ({
      id: row.link.id,
      role: row.link.role,
      createdAt: row.link.createdAt,
      life_admin: {
        id: row.lifeAdminRow.id,
        identifier: row.lifeAdminRow.identifier,
        title: row.lifeAdminRow.title,
        lifeAdminType: row.lifeAdminRow.lifeAdminType,
        status: row.lifeAdminRow.status,
      },
    })));
  });

  router.get("/life_admin/:id", async (req, res, next) => {
    const row = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!row) return next();
    res.json(await loadLifeAdminDetail(db, row));
  });

  router.patch("/life_admin/:id", async (req, res, next) => {
    const lifeAdminRow = await resolveSharedPathLifeAdmin(db, req, req.params.id as string);
    if (!lifeAdminRow) return next();
    const actor = getActorInfo(req);
    const body = patchLifeAdminSchema.parse(req.body);
    const nextLabelIds = body.labelIds ?? body.labels;

    const updated = await db.transaction(async (tx) => {
      await assertProjectBelongsToDomain(tx, { domainId: lifeAdminRow.domainId, projectId: body.projectId ?? null });
      await assertParentLifeAdminBelongsToDomain(tx, {
        domainId: lifeAdminRow.domainId,
        lifeAdminId: lifeAdminRow.id,
        parentLifeAdminId: body.parentLifeAdminId ?? null,
      });
      if (nextLabelIds) await assertLabelsBelongToDomain(tx, lifeAdminRow.domainId, nextLabelIds);

      const now = new Date();
      const [row] = await tx.update(life_admin).set(buildLifeAdminPatchUpdateValues(body, lifeAdminRow, now)).where(eq(life_admin.id, lifeAdminRow.id)).returning();

      if (nextLabelIds) {
        await lockLifeAdminLabels(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id });
        const current = await tx
          .select({ labelId: lifeAdminLabels.labelId })
          .from(lifeAdminLabels)
          .where(and(eq(lifeAdminLabels.domainId, lifeAdminRow.domainId), eq(lifeAdminLabels.lifeAdminId, lifeAdminRow.id)));
        const currentIds = new Set(current.map((item) => item.labelId));
        const desiredIds = new Set(nextLabelIds);
        const added = [...desiredIds].filter((id) => !currentIds.has(id));
        const removed = [...currentIds].filter((id) => !desiredIds.has(id));
        if (removed.length > 0) {
          await tx.delete(lifeAdminLabels).where(and(eq(lifeAdminLabels.lifeAdminId, lifeAdminRow.id), inArray(lifeAdminLabels.labelId, removed)));
          for (const labelId of removed) {
            await insertLifeAdminEvent(tx, {
              domainId: lifeAdminRow.domainId,
              lifeAdminId: lifeAdminRow.id,
              kind: "label_removed",
              actor,
              payload: { labelId },
            });
          }
        }
        if (added.length > 0) {
          await tx.insert(lifeAdminLabels).values(added.map((labelId) => ({
            domainId: lifeAdminRow.domainId,
            lifeAdminId: lifeAdminRow.id,
            labelId,
            createdAt: now,
            updatedAt: now,
          }))).onConflictDoNothing();
          for (const labelId of added) {
            await insertLifeAdminEvent(tx, {
              domainId: lifeAdminRow.domainId,
              lifeAdminId: lifeAdminRow.id,
              kind: "label_added",
              actor,
              payload: { labelId },
            });
          }
        }
      }

      const kind = body.status !== undefined
        ? "status_changed"
        : body.fields !== undefined
          ? "fields_changed"
          : Object.hasOwn(body, "parentLifeAdminId") && body.parentLifeAdminId
            ? "child_linked"
            : "updated";
      await insertLifeAdminEvent(tx, {
        domainId: lifeAdminRow.domainId,
        lifeAdminId: lifeAdminRow.id,
        kind,
        actor,
        payload: {
          previousStatus: body.status !== undefined ? lifeAdminRow.status : undefined,
          status: body.status,
          parentLifeAdminId: body.parentLifeAdminId,
        },
      });
      await autoLinkRunIssue(tx, { domainId: lifeAdminRow.domainId, lifeAdminId: lifeAdminRow.id, actor, role: "work" });
      return row!;
    });
    res.json(await loadLifeAdminDetail(db, updated));
  });

  return router;
}

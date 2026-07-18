import { randomUUID } from "node:crypto";
import { Router, type Request } from "express";
import { and, count as countFn, eq } from "drizzle-orm";
import { z } from "zod";
import type { Db } from "@paperclipai/db";
import { agents as agentsTable } from "@paperclipai/db";
import {
  DEFAULT_FEEDBACK_DATA_SHARING_TERMS_VERSION,
  domainArtifactsQuerySchema,
  domainPortabilityExportSchema,
  domainPortabilityImportSchema,
  domainPortabilityPreviewSchema,
  createDomainSchema,
  feedbackTargetTypeSchema,
  feedbackTraceStatusSchema,
  feedbackVoteValueSchema,
  updateDomainBrandingSchema,
  updateDomainSchema,
} from "@paperclipai/shared";
import { badRequest, forbidden } from "../errors.js";
import { validate } from "../middleware/validate.js";
import {
  accessService,
  agentService,
  budgetService,
  domainArtifactsService,
  domainPortabilityService,
  domainService,
  feedbackService,
  logActivity,
  workJournalService,
} from "../services/index.js";
import type { StorageService } from "../storage/types.js";
import { assertBoard, assertDomainAccess, assertInstanceAdmin, getActorInfo } from "./authz.js";
import { DOMAIN_IMPORT_ROUTE_PATH } from "./domain-import-paths.js";

export function domainRoutes(db: Db, storage?: StorageService) {
  const router = Router();
  const svc = domainService(db);
  const agents = agentService(db);
  const portability = domainPortabilityService(db, storage);
  const access = accessService(db);
  const budgets = budgetService(db);
  const artifacts = domainArtifactsService(db, storage);
  const feedback = feedbackService(db);
  const importJobs = new Map<string, ImportJobRecord>();
  const importJobTerminalRetentionMs = 5 * 60 * 1000;

  function parseBooleanQuery(value: unknown) {
    return value === true || value === "true" || value === "1";
  }

  function parseDateQuery(value: unknown, field: string) {
    if (typeof value !== "string" || value.trim().length === 0) return undefined;
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      throw badRequest(`Invalid ${field} query value`);
    }
    return parsed;
  }

  function parseIntegerQuery(value: unknown, field: string) {
    if (value === undefined || value === null || value === "") return undefined;
    const parsed = typeof value === "string" ? Number(value) : NaN;
    if (!Number.isFinite(parsed)) {
      throw badRequest(`Invalid ${field} query value`);
    }
    return Math.floor(parsed);
  }

  const journalQuerySchema = z.object({
    from: z.string().optional(),
    to: z.string().optional(),
    userId: z.string().min(1).optional(),
    goalId: z.string().uuid().optional(),
    projectId: z.string().uuid().optional(),
    issueId: z.string().uuid().optional(),
    limit: z.string().optional(),
    offset: z.string().optional(),
  }).passthrough();

  function assertImportTargetAccess(
    req: Request,
    target: { mode: "new_domain" } | { mode: "existing_domain"; domainId: string },
  ) {
    if (target.mode === "new_domain") {
      assertInstanceAdmin(req);
      return;
    }
    assertDomainAccess(req, target.domainId);
  }

  async function assertSameDomainCeoAgentOrBoard(req: Request, domainId: string, capability: string) {
    assertDomainAccess(req, domainId);
    if (req.actor.type === "board") {
      return;
    }
    if (!req.actor.agentId) throw forbidden("Agent authentication required");

    const actorAgent = await agents.getById(req.actor.agentId);
    if (!actorAgent || actorAgent.domainId !== domainId) {
      throw forbidden("Agent key cannot access another domain");
    }
    if (actorAgent.role !== "ceo") {
      throw forbidden(`Only CEO agents can manage ${capability}`);
    }
  }

  router.get("/", async (req, res) => {
    assertBoard(req);
    const result = await svc.list();
    if (req.actor.source === "local_implicit" || req.actor.isInstanceAdmin) {
      res.json(result);
      return;
    }
    const allowed = new Set(req.actor.domainIds ?? []);
    res.json(result.filter((domain) => allowed.has(domain.id)));
  });

  router.get("/stats", async (req, res) => {
    assertBoard(req);
    const allowed = req.actor.source === "local_implicit" || req.actor.isInstanceAdmin
      ? null
      : new Set(req.actor.domainIds ?? []);
    const stats = await svc.stats();
    if (!allowed) {
      res.json(stats);
      return;
    }
    const filtered = Object.fromEntries(Object.entries(stats).filter(([domainId]) => allowed.has(domainId)));
    res.json(filtered);
  });

  // Common malformed path when domainId is empty in "/api/domains/{domainId}/issues".
  router.get("/issues", (_req, res) => {
    res.status(400).json({
      error: "Missing domainId in path. Use /api/domains/{domainId}/issues.",
    });
  });

  router.get("/:domainId/artifacts", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const query = domainArtifactsQuerySchema.parse(req.query);
    res.json(await artifacts.list(domainId, query));
  });

  router.get("/:domainId/journal", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);

    const domainScopeDecision = await access.decide({
      actor: req.actor,
      action: "domain_scope:read",
      resource: { type: "domain", domainId },
    });
    if (!domainScopeDecision.allowed) {
      res.status(403).json({ error: "Journal is outside this actor's authorization boundary" });
      return;
    }

    const query = journalQuerySchema.parse(req.query);
    const journal = workJournalService(db);
    const result = await journal.getJournal({
      domainId,
      from: parseDateQuery(query.from, "from"),
      to: parseDateQuery(query.to, "to"),
      userId: query.userId,
      goalId: query.goalId,
      projectId: query.projectId,
      issueId: query.issueId,
      limit: parseIntegerQuery(query.limit, "limit"),
      offset: parseIntegerQuery(query.offset, "offset"),
      canReadIssue: async (issue) => {
        const decision = await access.decide({
          actor: req.actor,
          action: "issue:read",
          resource: {
            type: "issue",
            domainId: issue.domainId,
            issueId: issue.id,
            projectId: issue.projectId,
            parentIssueId: issue.parentId,
            assigneeAgentId: issue.assigneeAgentId,
            assigneeUserId: issue.assigneeUserId,
            status: issue.status,
          },
          scope: {
            issueId: issue.id,
            projectId: issue.projectId,
            parentIssueId: issue.parentId,
            assigneeAgentId: issue.assigneeAgentId,
            assigneeUserId: issue.assigneeUserId,
          },
        });
        return decision.allowed;
      },
    });
    res.json(result);
  });

  router.get("/:domainId", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    // Allow agents (CEO) to read their own domain; board always allowed
    if (req.actor.type !== "agent") {
      assertBoard(req);
    }
    const domain = await svc.getById(domainId);
    if (!domain) {
      res.status(404).json({ error: "Domain not found" });
      return;
    }
    res.json(domain);
  });

  router.get("/:domainId/feedback-traces", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    assertBoard(req);

    const targetTypeRaw = typeof req.query.targetType === "string" ? req.query.targetType : undefined;
    const voteRaw = typeof req.query.vote === "string" ? req.query.vote : undefined;
    const statusRaw = typeof req.query.status === "string" ? req.query.status : undefined;
    const issueId = typeof req.query.issueId === "string" && req.query.issueId.trim().length > 0 ? req.query.issueId : undefined;
    const projectId = typeof req.query.projectId === "string" && req.query.projectId.trim().length > 0
      ? req.query.projectId
      : undefined;

    const traces = await feedback.listFeedbackTraces({
      domainId,
      issueId,
      projectId,
      targetType: targetTypeRaw ? feedbackTargetTypeSchema.parse(targetTypeRaw) : undefined,
      vote: voteRaw ? feedbackVoteValueSchema.parse(voteRaw) : undefined,
      status: statusRaw ? feedbackTraceStatusSchema.parse(statusRaw) : undefined,
      from: parseDateQuery(req.query.from, "from"),
      to: parseDateQuery(req.query.to, "to"),
      sharedOnly: parseBooleanQuery(req.query.sharedOnly),
      includePayload: parseBooleanQuery(req.query.includePayload),
    });
    res.json(traces);
  });

  router.post("/:domainId/export", async (req, res) => {
    const domainId = req.params.domainId as string;
    await assertSameDomainCeoAgentOrBoard(req, domainId, "domain exports");
    const body = domainPortabilityExportSchema.parse(req.body);
    const result = await portability.exportBundle(domainId, body);
    res.json(result);
  });

  router.post("/import/preview", async (req, res) => {
    assertBoard(req);
    const body = domainPortabilityPreviewSchema.parse(req.body);
    assertImportTargetAccess(req, body.target);
    const preview = await portability.previewImport(body);
    res.json(preview);
  });

  router.get("/import/jobs/:jobId", async (req, res) => {
    assertCloudTenantCaller(req);
    cleanupTerminalImportJobs(importJobs, importJobTerminalRetentionMs);
    const job = importJobs.get(req.params.jobId as string);
    if (!job || job.cloudTenantKey !== cloudTenantRequestKey(req)) {
      res.status(404).json({ error: "Import job not found" });
      return;
    }
    res.json(importJobResponse(job));
  });

  router.post(DOMAIN_IMPORT_ROUTE_PATH, async (req, res) => {
    assertBoard(req);
    const rawImportBody: unknown = req.body;
    const actor = getActorInfo(req);
    const boardUserId = req.actor.type === "board" ? req.actor.userId : null;
    if (req.header("x-paperclip-cloud-async-import") === "1") {
      assertCloudTenantCaller(req);
      cleanupTerminalImportJobs(importJobs, importJobTerminalRetentionMs);
      const job = createImportJob(cloudTenantRequestKey(req));
      importJobs.set(job.id, job);
      const operation = async () => {
        const importBody = domainPortabilityImportSchema.parse(rawImportBody);
        assertImportTargetAccess(req, importBody.target);
        const activity = importedDomainActivityContext(actor, importBody.include ?? null);
        const result = await portability.importBundle(importBody, boardUserId);
        await logImportedDomainActivity(db, activity, result);
        return result;
      };
      res.status(202).json(importJobAcceptedResponse(job));
      setImmediate(() => {
        void runImportJob(job, operation);
      });
      return;
    }

    const importBody = domainPortabilityImportSchema.parse(rawImportBody);
    assertImportTargetAccess(req, importBody.target);
    const activity = importedDomainActivityContext(actor, importBody.include ?? null);
    const result = await portability.importBundle(importBody, boardUserId);
    await logImportedDomainActivity(db, activity, result);
    res.json(result);
  });

  router.post("/:domainId/exports/preview", async (req, res) => {
    const domainId = req.params.domainId as string;
    await assertSameDomainCeoAgentOrBoard(req, domainId, "domain exports");
    const body = domainPortabilityExportSchema.parse(req.body);
    const preview = await portability.previewExport(domainId, body);
    res.json(preview);
  });

  router.post("/:domainId/exports", async (req, res) => {
    const domainId = req.params.domainId as string;
    await assertSameDomainCeoAgentOrBoard(req, domainId, "domain exports");
    const body = domainPortabilityExportSchema.parse(req.body);
    const result = await portability.exportBundle(domainId, body);
    res.json(result);
  });

  router.post("/:domainId/imports/preview", async (req, res) => {
    const domainId = req.params.domainId as string;
    await assertSameDomainCeoAgentOrBoard(req, domainId, "domain imports");
    const body = domainPortabilityPreviewSchema.parse(req.body);
    if (body.target.mode === "existing_domain" && body.target.domainId !== domainId) {
      throw forbidden("Safe import route can only target the route domain");
    }
    if (body.collisionStrategy === "replace") {
      throw forbidden("Safe import route does not allow replace collision strategy");
    }
    const preview = await portability.previewImport(body, {
      mode: "agent_safe",
      sourceDomainId: domainId,
    });
    res.json(preview);
  });

  router.post("/:domainId/imports/apply", async (req, res) => {
    const domainId = req.params.domainId as string;
    await assertSameDomainCeoAgentOrBoard(req, domainId, "domain imports");
    const body = domainPortabilityImportSchema.parse(req.body);
    if (body.target.mode === "existing_domain" && body.target.domainId !== domainId) {
      throw forbidden("Safe import route can only target the route domain");
    }
    if (body.collisionStrategy === "replace") {
      throw forbidden("Safe import route does not allow replace collision strategy");
    }
    const actor = getActorInfo(req);
    const result = await portability.importBundle(body, req.actor.type === "board" ? req.actor.userId : null, {
      mode: "agent_safe",
      sourceDomainId: domainId,
    });
    await logActivity(db, {
      domainId: result.domain.id,
      actorType: actor.actorType,
      actorId: actor.actorId,
      entityType: "domain",
      entityId: result.domain.id,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.imported",
      details: {
        include: body.include ?? null,
        agentCount: result.agents.length,
        warningCount: result.warnings.length,
        domainAction: result.domain.action,
        importMode: "agent_safe",
      },
    });
    res.json(result);
  });

  router.post("/", validate(createDomainSchema), async (req, res) => {
    assertBoard(req);
    if (!(req.actor.source === "local_implicit" || req.actor.isInstanceAdmin)) {
      throw forbidden("Instance admin required");
    }
    const ownerPrincipalId = req.actor.userId ?? "local-board";
    const domain = await svc.create({
      ...req.body,
      defaultResponsibleUserId: req.body.defaultResponsibleUserId ?? ownerPrincipalId,
    });
    await access.ensureMembership(domain.id, "user", ownerPrincipalId, "owner", "active");
    await access.ensureRoleDefaultGrants(
      domain.id,
      ownerPrincipalId,
      "owner",
      req.actor.userId ?? null,
    );
    await logActivity(db, {
      domainId: domain.id,
      actorType: "user",
      actorId: req.actor.userId ?? "board",
      action: "domain.created",
      entityType: "domain",
      entityId: domain.id,
      details: { name: domain.name },
    });
    if (domain.budgetMonthlyCents > 0) {
      await budgets.upsertPolicy(
        domain.id,
        {
          scopeType: "domain",
          scopeId: domain.id,
          amount: domain.budgetMonthlyCents,
          windowKind: "calendar_month_utc",
        },
        req.actor.userId ?? "board",
      );
    }
    res.status(201).json(domain);
  });

  router.patch("/:domainId", async (req, res) => {
    const domainId = req.params.domainId as string;
    await assertSameDomainCeoAgentOrBoard(req, domainId, "domain settings");

    const actor = getActorInfo(req);
    let body: Record<string, unknown>;

    if (req.actor.type === "agent") {
      body = updateDomainBrandingSchema.parse(req.body);
    } else {
      body = updateDomainSchema.parse(req.body);
    }

    const existingDomain = await svc.getById(domainId);
    if (!existingDomain) {
      res.status(404).json({ error: "Domain not found" });
      return;
    }

    if (req.actor.type !== "agent") {
      if (body.feedbackDataSharingEnabled === true && !existingDomain.feedbackDataSharingEnabled) {
        body = {
          ...body,
          feedbackDataSharingConsentAt: new Date(),
          feedbackDataSharingConsentByUserId: req.actor.userId ?? "local-board",
          feedbackDataSharingTermsVersion:
            typeof body.feedbackDataSharingTermsVersion === "string" && body.feedbackDataSharingTermsVersion.length > 0
              ? body.feedbackDataSharingTermsVersion
              : DEFAULT_FEEDBACK_DATA_SHARING_TERMS_VERSION,
        };
      }
    }

    const transitionsToArchived =
      body.status === "archived" && existingDomain.status !== "archived";
    const transitionsArchivedToActive =
      body.status === "active" && existingDomain.status === "archived";
    let transitionsPausedToActiveWithArchivePausedAgents = false;
    if (body.status === "active" && existingDomain.status === "paused") {
      const [archivedPausedCount] = await db
        .select({ value: countFn() })
        .from(agentsTable)
        .where(and(
          eq(agentsTable.domainId, domainId),
          eq(agentsTable.status, "paused"),
          eq(agentsTable.pauseReason, "domain_archived"),
        ));
      transitionsPausedToActiveWithArchivePausedAgents =
        Number(archivedPausedCount?.value ?? 0) > 0;
    }
    const lifecycleEventEmittedByService =
      transitionsToArchived ||
      transitionsArchivedToActive ||
      transitionsPausedToActiveWithArchivePausedAgents;

    const domain = await svc.update(domainId, body, actor);
    if (!domain) {
      res.status(404).json({ error: "Domain not found" });
      return;
    }
    if (!lifecycleEventEmittedByService) {
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.updated",
        entityType: "domain",
        entityId: domainId,
        details: body,
      });
    }
    res.json(domain);
  });

  router.patch("/:domainId/branding", async (req, res) => {
    const domainId = req.params.domainId as string;
    await assertSameDomainCeoAgentOrBoard(req, domainId, "domain branding");
    const body = updateDomainBrandingSchema.parse(req.body);
    const domain = await svc.update(domainId, body);
    if (!domain) {
      res.status(404).json({ error: "Domain not found" });
      return;
    }
    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.branding_updated",
      entityType: "domain",
      entityId: domainId,
      details: body,
    });
    res.json(domain);
  });

  router.post("/:domainId/archive", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    assertBoard(req);
    const domain = await svc.archive(domainId, getActorInfo(req));
    if (!domain) {
      res.status(404).json({ error: "Domain not found" });
      return;
    }
    res.json(domain);
  });

  router.delete("/:domainId", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    assertBoard(req);
    const domain = await svc.remove(domainId);
    if (!domain) {
      res.status(404).json({ error: "Domain not found" });
      return;
    }
    res.json({ ok: true });
  });

  return router;
}

type DomainImportResult = {
  domain: { id: string; action: unknown };
  agents: unknown[];
  warnings: unknown[];
};

interface ImportJobRecord {
  id: string;
  cloudTenantKey: string;
  status: "running" | "succeeded" | "failed";
  createdAt: string;
  updatedAt: string;
  completedAt?: string;
  error?: { message: string };
  result?: {
    domainId: string;
    agentCount: number;
    warningCount: number;
    domainAction: unknown;
  };
}

interface ImportedDomainActivityContext {
  actorType: "user" | "agent";
  actorId: string;
  agentId: string | null;
  runId: string | null;
  include: unknown;
}

function assertCloudTenantCaller(req: Request) {
  if (req.actor.source !== "cloud_tenant") {
    throw forbidden("Trusted Cloud tenant access required");
  }
}

function cloudTenantRequestKey(req: Request) {
  return [
    req.actor.userId ?? "",
    req.header("x-paperclip-cloud-stack-id")?.trim() ?? "",
    req.header("x-paperclip-cloud-paperclip-domain-id")?.trim() ?? "",
  ].join(":");
}

function createImportJob(cloudTenantKey: string): ImportJobRecord {
  const now = new Date().toISOString();
  return {
    id: `tenant-import-${randomUUID()}`,
    cloudTenantKey,
    status: "running",
    createdAt: now,
    updatedAt: now,
  };
}

async function runImportJob(
  job: ImportJobRecord,
  operation: () => Promise<DomainImportResult>,
) {
  try {
    const result = await operation();
    const now = new Date().toISOString();
    job.status = "succeeded";
    job.updatedAt = now;
    job.completedAt = now;
    job.result = {
      domainId: result.domain.id,
      agentCount: result.agents.length,
      warningCount: result.warnings.length,
      domainAction: result.domain.action,
    };
  } catch (error) {
    const now = new Date().toISOString();
    job.status = "failed";
    job.updatedAt = now;
    job.completedAt = now;
    job.error = { message: errorMessage(error) };
  }
}

function importedDomainActivityContext(
  actor: ReturnType<typeof getActorInfo>,
  include: unknown,
): ImportedDomainActivityContext {
  return {
    actorType: actor.actorType,
    actorId: actor.actorId,
    agentId: actor.agentId,
    runId: actor.runId,
    include,
  };
}

async function logImportedDomainActivity(
  db: Db,
  activity: ImportedDomainActivityContext,
  result: DomainImportResult,
) {
  await logActivity(db, {
    domainId: result.domain.id,
    actorType: activity.actorType,
    actorId: activity.actorId,
    action: "domain.imported",
    entityType: "domain",
    entityId: result.domain.id,
    agentId: activity.agentId,
    runId: activity.runId,
    details: {
      include: activity.include,
      agentCount: result.agents.length,
      warningCount: result.warnings.length,
      domainAction: result.domain.action,
    },
  });
}

function importJobAcceptedResponse(job: ImportJobRecord) {
  return {
    job: {
      id: job.id,
      status: job.status,
    },
    statusUrl: `/api/domains/import/jobs/${encodeURIComponent(job.id)}`,
    retryAfterMs: 1000,
  };
}

function importJobResponse(job: ImportJobRecord) {
  const isTerminal = job.status === "succeeded" || job.status === "failed";
  const response: Record<string, unknown> = {
    job: {
      id: job.id,
      status: job.status,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      ...(job.completedAt ? { completedAt: job.completedAt } : {}),
      ...(job.error ? { error: job.error } : {}),
      ...(job.result ? { result: job.result } : {}),
    },
    ...(isTerminal ? {} : { retryAfterMs: 1000 }),
  };
  if (job.error?.message) {
    response.error = job.error.message;
    response.message = job.error.message;
    response.reason = job.error.message;
  }
  return response;
}

function cleanupTerminalImportJobs(importJobs: Map<string, ImportJobRecord>, terminalRetentionMs: number) {
  const now = Date.now();
  for (const [jobId, job] of importJobs) {
    if (job.status === "running" || !job.completedAt) continue;
    if (now - Date.parse(job.completedAt) > terminalRetentionMs) {
      importJobs.delete(jobId);
    }
  }
}

function errorMessage(error: unknown) {
  return error instanceof Error && error.message.trim() ? error.message : String(error);
}

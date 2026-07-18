import { Router, type Request } from "express";
import type { Db } from "@paperclipai/db";
import {
  catalogSkillListQuerySchema,
  domainSkillCommentCreateSchema,
  domainSkillCommentUpdateSchema,
  domainSkillCreateSchema,
  domainSkillFileDeleteSchema,
  domainSkillFileUpdateSchema,
  domainSkillForkSchema,
  domainSkillImportSchema,
  domainSkillInstallCatalogSchema,
  domainSkillInstallUpdateSchema,
  domainSkillListQuerySchema,
  domainSkillProjectScanRequestSchema,
  domainSkillResetSchema,
  domainSkillTestInputCreateSchema,
  domainSkillTestInputUpdateSchema,
  domainSkillTestRunTemplateCreateSchema,
  domainSkillTestRunTemplateUpdateSchema,
  domainSkillTestRunCreateSchema,
  domainSkillTestRunListQuerySchema,
  domainSkillUpdateSchema,
  domainSkillVersionCreateSchema,
} from "@paperclipai/shared";
import { trackSkillImported } from "@paperclipai/shared/telemetry";
import { validate } from "../middleware/validate.js";
import { accessService, agentService, domainSkillService, heartbeatService, issueService, logActivity } from "../services/index.js";
import {
  getCatalogSkillOrThrow,
  listCatalogSkillsOrEmpty,
  readCatalogSkillFile,
} from "../services/skills-catalog.js";
import { forbidden, HttpError } from "../errors.js";
import { assertAuthenticated, assertDomainAccess, getActorInfo } from "./authz.js";
import { getTelemetryClient } from "../telemetry.js";
import { authorizationDeniedDetails } from "../services/authorization.js";
import {
  changeConsentGateService,
  skillChangeTargetKey,
  skillImportChangeTargetKey,
  skillSlugChangeTargetKey,
  skillsScanProjectsChangeTargetKey,
} from "../services/change-consent-gate.js";

type SkillTelemetryInput = {
  key: string;
  slug: string;
  sourceType: string;
  sourceLocator: string | null;
  metadata: Record<string, unknown> | null;
};

export function domainSkillRoutes(db: Db) {
  const router = Router();
  const agents = agentService(db);
  const access = accessService(db);
  const svc = domainSkillService(db);
  const issues = issueService(db);
  const heartbeat = heartbeatService(db);

  function asString(value: unknown): string | null {
    if (typeof value !== "string") return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  function deriveTrackedSkillRef(skill: SkillTelemetryInput): string | null {
    if (skill.sourceType === "skills_sh") {
      return skill.key;
    }
    if (skill.sourceType !== "github") {
      return null;
    }
    const hostname = asString(skill.metadata?.hostname);
    if (hostname !== "github.com") {
      return null;
    }
    return skill.key;
  }

  function firstQueryString(value: unknown): string | undefined {
    if (typeof value === "string") return value;
    if (Array.isArray(value) && typeof value[0] === "string") return value[0];
    return undefined;
  }

  function queryStringArray(value: unknown): string[] {
    if (typeof value === "string") return [value];
    if (Array.isArray(value)) return value.filter((entry): entry is string => typeof entry === "string");
    return [];
  }

  function skillActor(req: Request) {
    if (req.actor.type === "agent") {
      return { type: "agent" as const, agentId: req.actor.agentId ?? null };
    }
    if (req.actor.type === "board") {
      return { type: "user" as const, userId: req.actor.userId ?? null };
    }
    return { type: "system" as const };
  }

  function skillMutationTargets(input: {
    skillId?: string | null;
    slug?: unknown;
    source?: unknown;
    catalogSkillId?: unknown;
    scanProjects?: boolean;
  }) {
    const targetKeys: string[] = [];
    const skillId = asString(input.skillId);
    const slug = asString(input.slug);
    const source = asString(input.source);
    const catalogSkillId = asString(input.catalogSkillId);
    if (skillId) targetKeys.push(skillChangeTargetKey(skillId));
    if (slug) targetKeys.push(skillSlugChangeTargetKey(slug));
    if (source) targetKeys.push(skillImportChangeTargetKey(source));
    if (catalogSkillId) targetKeys.push(skillImportChangeTargetKey(catalogSkillId));
    if (input.scanProjects) targetKeys.push(skillsScanProjectsChangeTargetKey());
    return targetKeys;
  }

  async function assertCanMutateDomainSkills(req: Request, domainId: string, targetKeys: string[] = []) {
    assertDomainAccess(req, domainId);
    const decision = await access.decide({
      actor: req.actor,
      action: "skill_config:update",
      resource: { type: "domain", domainId },
    });
    if (decision.allowed) {
      return;
    }

    if (decision.reason === "deny_missing_consent" && req.actor.type === "agent" && targetKeys.length > 0) {
      try {
        await changeConsentGateService(db).assertConsented({
          domainId,
          actorAgentId: req.actor.agentId,
          actorRunId: req.actor.runId ?? null,
          targetKeys,
        });
      } catch (err) {
        if (err instanceof HttpError && err.status === 403) {
          throw forbidden(decision.explanation, authorizationDeniedDetails(decision));
        }
        throw err;
      }

      const consentedDecision = await access.decide({
        actor: req.actor,
        action: "skill_config:update",
        resource: { type: "domain", domainId },
        scope: { consentedChange: true },
      });
      if (consentedDecision.allowed) {
        return;
      }
      throw forbidden(consentedDecision.explanation, { reason: consentedDecision.reason });
    }

    throw forbidden(decision.explanation, { reason: decision.reason });
  }

  async function assertCanStartSkillTestRuns(req: Request, domainId: string) {
    assertDomainAccess(req, domainId);

    if (req.actor.type === "board") {
      if (req.actor.source === "local_implicit" || req.actor.isInstanceAdmin) return;
      const allowed = await access.canUser(domainId, req.actor.userId, "tasks:assign");
      if (!allowed) {
        throw forbidden("Missing permission: tasks:assign");
      }
      return;
    }

    if (!req.actor.agentId) {
      throw forbidden("Agent authentication required");
    }

    const actorAgent = await agents.getById(req.actor.agentId);
    if (!actorAgent || actorAgent.domainId !== domainId) {
      throw forbidden("Agent key cannot access another domain");
    }
    const allowedByGrant = await access.hasPermission(domainId, "agent", actorAgent.id, "tasks:assign");
    if (!allowedByGrant) {
      throw forbidden("Missing permission: tasks:assign");
    }
  }

  router.get("/skills/catalog", async (req, res) => {
    assertAuthenticated(req);
    const query = catalogSkillListQuerySchema.parse({
      kind: firstQueryString(req.query.kind),
      category: firstQueryString(req.query.category),
      q: firstQueryString(req.query.q),
    });
    res.json(listCatalogSkillsOrEmpty(query));
  });

  router.get("/skills/catalog/:catalogId/files", async (req, res) => {
    assertAuthenticated(req);
    const catalogRef = firstQueryString(req.query.ref) ?? (req.params.catalogId as string);
    const relativePath = firstQueryString(req.query.path) ?? "SKILL.md";
    res.json(await readCatalogSkillFile(catalogRef, relativePath));
  });

  router.get("/skills/catalog/:catalogId", async (req, res) => {
    assertAuthenticated(req);
    const catalogRef = firstQueryString(req.query.ref) ?? (req.params.catalogId as string);
    res.json(getCatalogSkillOrThrow(catalogRef));
  });

  router.get("/domains/:domainId/skills", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.list(domainId, domainSkillListQuerySchema.parse({
      q: firstQueryString(req.query.q),
      sort: firstQueryString(req.query.sort),
      categories: [
        ...queryStringArray(req.query.category),
        ...queryStringArray(req.query.categories),
        ...queryStringArray(req.query["categories[]"]),
      ],
      scope: firstQueryString(req.query.scope),
      include: [
        ...queryStringArray(req.query.include),
        ...queryStringArray(req.query["include[]"]),
      ],
    }));
    res.json(result);
  });

  router.get("/domains/:domainId/skills/categories", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    res.json(await svc.categoryCounts(domainId));
  });

  router.get("/domains/:domainId/skills/:skillId", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.detail(domainId, skillId, skillActor(req));
    if (!result) {
      res.status(404).json({ error: "Skill not found" });
      return;
    }
    res.json(result);
  });

  router.get("/domains/:domainId/skills/:skillId/fork-precheck", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.forkPrecheck(domainId, skillId, skillActor(req));
    if (!result) {
      res.status(404).json({ error: "Skill not found" });
      return;
    }
    res.json(result);
  });

  router.get("/domains/:domainId/skills/:skillId/versions", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    res.json(await svc.listVersions(domainId, skillId));
  });

  router.get("/domains/:domainId/skills/:skillId/versions/:versionId", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    const versionId = req.params.versionId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.getVersion(domainId, skillId, versionId);
    if (!result) {
      res.status(404).json({ error: "Skill version not found" });
      return;
    }
    res.json(result);
  });

  router.get("/domains/:domainId/skills/:skillId/test-inputs", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    res.json(await svc.listTestInputs(domainId, skillId));
  });

  router.post(
    "/domains/:domainId/skills/:skillId/test-inputs",
    validate(domainSkillTestInputCreateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId);
      const result = await svc.createTestInput(domainId, skillId, req.body, skillActor(req));
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_test_input_created",
        entityType: "domain_skill_test_input",
        entityId: result.id,
        details: { skillId, name: result.name },
      });
      res.status(201).json(result);
    },
  );

  router.patch(
    "/domains/:domainId/skills/:skillId/test-inputs/:inputId",
    validate(domainSkillTestInputUpdateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      const inputId = req.params.inputId as string;
      await assertCanMutateDomainSkills(req, domainId);
      const result = await svc.updateTestInput(domainId, skillId, inputId, req.body);
      if (!result) {
        res.status(404).json({ error: "Test input not found" });
        return;
      }
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_test_input_updated",
        entityType: "domain_skill_test_input",
        entityId: result.id,
        details: { skillId, changedKeys: Object.keys(req.body).sort() },
      });
      res.json(result);
    },
  );

  router.delete("/domains/:domainId/skills/:skillId/test-inputs/:inputId", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    const inputId = req.params.inputId as string;
    await assertCanMutateDomainSkills(req, domainId);
    const result = await svc.deleteTestInput(domainId, skillId, inputId);
    if (!result) {
      res.status(404).json({ error: "Test input not found" });
      return;
    }
    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.skill_test_input_deleted",
      entityType: "domain_skill_test_input",
      entityId: result.id,
      details: { skillId, name: result.name },
    });
    res.json(result);
  });

  router.get("/domains/:domainId/skill-test-run-templates", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    res.json(await svc.listTestRunTemplates(domainId));
  });

  router.post(
    "/domains/:domainId/skill-test-run-templates",
    validate(domainSkillTestRunTemplateCreateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      await assertCanMutateDomainSkills(req, domainId);
      const result = await svc.createTestRunTemplate(domainId, req.body, skillActor(req));
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_test_run_template_created",
        entityType: "domain_skill_test_run_template",
        entityId: result.id,
        details: { name: result.name },
      });
      res.status(201).json(result);
    },
  );

  router.patch(
    "/domains/:domainId/skill-test-run-templates/:templateId",
    validate(domainSkillTestRunTemplateUpdateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const templateId = req.params.templateId as string;
      await assertCanMutateDomainSkills(req, domainId);
      const result = await svc.updateTestRunTemplate(domainId, templateId, req.body, skillActor(req));
      if (!result) {
        res.status(404).json({ error: "Test run template not found" });
        return;
      }
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_test_run_template_updated",
        entityType: "domain_skill_test_run_template",
        entityId: result.id,
        details: { changedKeys: Object.keys(req.body).sort() },
      });
      res.json(result);
    },
  );

  router.delete("/domains/:domainId/skill-test-run-templates/:templateId", async (req, res) => {
    const domainId = req.params.domainId as string;
    const templateId = req.params.templateId as string;
    await assertCanMutateDomainSkills(req, domainId);
    const result = await svc.deleteTestRunTemplate(domainId, templateId);
    if (!result) {
      res.status(404).json({ error: "Test run template not found" });
      return;
    }
    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.skill_test_run_template_deleted",
      entityType: "domain_skill_test_run_template",
      entityId: result.id,
      details: { name: result.name },
    });
    res.json(result);
  });

  router.get("/domains/:domainId/skills/:skillId/test-runs", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    const query = domainSkillTestRunListQuerySchema.parse({
      inputId: firstQueryString(req.query.inputId),
    });
    res.json(await svc.listTestRuns(domainId, skillId, query));
  });

  router.get("/domains/:domainId/skills/:skillId/test-runs/:runId", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    const runId = req.params.runId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.getTestRunDetail(domainId, skillId, runId);
    if (!result) {
      res.status(404).json({ error: "Test run not found" });
      return;
    }
    res.json(result);
  });

  router.post(
    "/domains/:domainId/skills/:skillId/test-runs",
    validate(domainSkillTestRunCreateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanStartSkillTestRuns(req, domainId);
      const actor = getActorInfo(req);
      const result = await svc.createTestRun(domainId, skillId, req.body, skillActor(req), {
        createHarnessIssue: async (harnessIssue) => {
          const created = await issues.create(domainId, {
            ...harnessIssue,
            priority: "medium",
            createdByAgentId: actor.agentId,
            createdByUserId: actor.actorType === "user" ? actor.actorId : null,
            actorRunId: actor.runId,
          });
          await logActivity(db, {
            domainId,
            actorType: actor.actorType,
            actorId: actor.actorId,
            agentId: actor.agentId,
            runId: actor.runId,
            action: "issue.created",
            entityType: "issue",
            entityId: created.id,
            details: {
              title: created.title,
              identifier: created.identifier,
              harnessKind: "skill_test",
              source: "domain_skill_test_run",
              skillId,
            },
          });
          return { id: created.id };
        },
        wakeHarnessIssue: async (issueId, agentId) => heartbeat.wakeup(agentId, {
          source: "assignment",
          triggerDetail: "system",
          reason: "skill_test_run_created",
          payload: { issueId, skillId },
          requestedByActorType: actor.actorType,
          requestedByActorId: actor.actorId,
          contextSnapshot: { issueId, source: "domain.skill_test_run" },
        }),
        cleanupHarnessIssue: async (issueId) => {
          const issue = await issues.getById(issueId);
          if (!issue || issue.domainId !== domainId) return;
          await issues.update(issueId, {
            status: "cancelled",
            hiddenAt: new Date(),
            actorAgentId: actor.agentId ?? null,
            actorUserId: actor.actorType === "user" ? actor.actorId : null,
          });
          await logActivity(db, {
            domainId,
            actorType: actor.actorType,
            actorId: actor.actorId,
            agentId: actor.agentId,
            runId: actor.runId,
            action: "domain.skill_test_harness_issue_cleaned_up",
            entityType: "issue",
            entityId: issueId,
            details: { skillId },
          });
        },
      });
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_test_run_created",
        entityType: "domain_skill_test_run",
        entityId: result.id,
        details: {
          skillId,
          inputId: result.inputId,
          skillVersionId: result.skillVersionId,
          agentId: result.agentId,
          issueId: result.issueId,
        },
      });
      res.status(201).json(result);
    },
  );

  router.post("/domains/:domainId/skills/:skillId/test-runs/:runId/cancel", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    const runId = req.params.runId as string;
    await assertCanStartSkillTestRuns(req, domainId);
    const actor = getActorInfo(req);
    const result = await svc.cancelTestRun(domainId, skillId, runId, {
      cancelHarnessIssue: async (issueId) => {
        const issue = await issues.getById(issueId);
        if (!issue || issue.domainId !== domainId) return;
        if (issue.executionRunId) {
          await heartbeat.cancelRun(issue.executionRunId, "Cancelled by skill test run request");
        }
        if (issue.status !== "done" && issue.status !== "cancelled") {
          await issues.update(issueId, {
            status: "cancelled",
            actorAgentId: actor.agentId ?? null,
            actorUserId: actor.actorType === "user" ? actor.actorId : null,
          });
        }
      },
    });
    if (!result) {
      res.status(404).json({ error: "Test run not found" });
      return;
    }
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.skill_test_run_cancelled",
      entityType: "domain_skill_test_run",
      entityId: result.id,
      details: { skillId, issueId: result.issueId },
    });
    res.json(result);
  });

  router.delete("/domains/:domainId/skills/:skillId/test-runs/:runId", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    const runId = req.params.runId as string;
    await assertCanStartSkillTestRuns(req, domainId);
    const actor = getActorInfo(req);
    const result = await svc.deleteTestRun(domainId, skillId, runId, {
      hideHarnessIssue: async (issueId) => {
        const issue = await issues.getById(issueId);
        if (!issue || issue.domainId !== domainId) return;
        await issues.update(issueId, {
          hiddenAt: new Date(),
          actorAgentId: actor.agentId ?? null,
          actorUserId: actor.actorType === "user" ? actor.actorId : null,
        });
      },
    });
    if (!result) {
      res.status(404).json({ error: "Test run not found" });
      return;
    }
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.skill_test_run_deleted",
      entityType: "domain_skill_test_run",
      entityId: result.id,
      details: { skillId, issueId: result.issueId },
    });
    res.json(result);
  });

  router.post(
    "/domains/:domainId/skills/:skillId/versions",
    validate(domainSkillVersionCreateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ skillId }));
      const result = await svc.createVersion(domainId, skillId, req.body, skillActor(req));
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_version_created",
        entityType: "domain_skill_version",
        entityId: result.id,
        details: {
          skillId,
          revisionNumber: result.revisionNumber,
          label: result.label,
        },
      });
      res.status(201).json(result);
    },
  );

  router.post("/domains/:domainId/skills/:skillId/star", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.starSkill(domainId, skillId, skillActor(req));
    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.skill_starred",
      entityType: "domain_skill",
      entityId: skillId,
      details: { starCount: result.starCount },
    });
    res.json(result);
  });

  router.delete("/domains/:domainId/skills/:skillId/star", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.unstarSkill(domainId, skillId, skillActor(req));
    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.skill_unstarred",
      entityType: "domain_skill",
      entityId: skillId,
      details: { starCount: result.starCount },
    });
    res.json(result);
  });

  router.post(
    "/domains/:domainId/skills/:skillId/fork",
    validate(domainSkillForkSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({
        skillId,
        slug: req.body.slug,
      }));
      const result = await svc.forkSkill(domainId, skillId, req.body, skillActor(req));
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_forked",
        entityType: "domain_skill",
        entityId: result.skill.id,
        details: {
          sourceSkillId: skillId,
          slug: result.skill.slug,
          name: result.skill.name,
          reassignedAgentIds: result.reassignments.map((entry: { agentId: string }) => entry.agentId),
        },
      });
      res.status(201).json(result);
    },
  );

  router.get("/domains/:domainId/skills/:skillId/comments", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    res.json(await svc.listComments(domainId, skillId));
  });

  router.post(
    "/domains/:domainId/skills/:skillId/comments",
    validate(domainSkillCommentCreateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      assertDomainAccess(req, domainId);
      const result = await svc.createComment(domainId, skillId, req.body, skillActor(req));
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_comment_created",
        entityType: "domain_skill_comment",
        entityId: result.id,
        details: { skillId, parentCommentId: result.parentCommentId },
      });
      res.status(201).json(result);
    },
  );

  router.patch(
    "/domains/:domainId/skills/:skillId/comments/:commentId",
    validate(domainSkillCommentUpdateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      const commentId = req.params.commentId as string;
      assertDomainAccess(req, domainId);
      const result = await svc.updateComment(domainId, skillId, commentId, req.body, skillActor(req));
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_comment_updated",
        entityType: "domain_skill_comment",
        entityId: result.id,
        details: { skillId },
      });
      res.json(result);
    },
  );

  router.delete("/domains/:domainId/skills/:skillId/comments/:commentId", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    const commentId = req.params.commentId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.deleteComment(domainId, skillId, commentId, skillActor(req));
    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.skill_comment_deleted",
      entityType: "domain_skill_comment",
      entityId: result.id,
      details: { skillId },
    });
    res.json(result);
  });

  router.get("/domains/:domainId/skills/:skillId/update-status", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.updateStatus(domainId, skillId);
    if (!result) {
      res.status(404).json({ error: "Skill not found" });
      return;
    }
    res.json(result);
  });

  router.get("/domains/:domainId/skills/:skillId/files", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    const relativePath = String(req.query.path ?? "SKILL.md");
    assertDomainAccess(req, domainId);
    const result = await svc.readFile(domainId, skillId, relativePath);
    if (!result) {
      res.status(404).json({ error: "Skill not found" });
      return;
    }
    res.json(result);
  });

  router.post(
    "/domains/:domainId/skills",
    validate(domainSkillCreateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({
        slug: req.body.slug,
      }));
      const result = await svc.createLocalSkill(domainId, req.body, skillActor(req));

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_created",
        entityType: "domain_skill",
        entityId: result.id,
        details: {
          slug: result.slug,
          name: result.name,
        },
      });

      res.status(201).json(result);
    },
  );

  router.patch(
    "/domains/:domainId/skills/:skillId",
    validate(domainSkillUpdateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ skillId }));
      const result = await svc.updateSkill(domainId, skillId, req.body);

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_updated",
        entityType: "domain_skill",
        entityId: result.id,
        details: {
          slug: result.slug,
          categories: result.categories,
          sharingScope: result.sharingScope,
        },
      });

      res.json(result);
    },
  );

  router.patch(
    "/domains/:domainId/skills/:skillId/files",
    validate(domainSkillFileUpdateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ skillId }));
      const result = await svc.updateFile(
        domainId,
        skillId,
        String(req.body.path ?? ""),
        String(req.body.content ?? ""),
        skillActor(req),
      );

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_file_updated",
        entityType: "domain_skill",
        entityId: skillId,
        details: {
          path: result.path,
          markdown: result.markdown,
        },
      });

      res.json(result);
    },
  );

  router.delete(
    "/domains/:domainId/skills/:skillId/files",
    validate(domainSkillFileDeleteSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId);
      const result = await svc.deleteFile(domainId, skillId, req.body, skillActor(req));

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_file_deleted",
        entityType: "domain_skill",
        entityId: skillId,
        details: {
          path: result.path,
          target: result.target,
          deletedPaths: result.deletedPaths,
        },
      });

      res.json(result);
    },
  );

  router.post(
    "/domains/:domainId/skills/import",
    validate(domainSkillImportSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const source = String(req.body.source ?? "");
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ source }));
      const result = await svc.importFromSource(domainId, source);

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skills_imported",
        entityType: "domain",
        entityId: domainId,
        details: {
          source,
          importedCount: result.imported.length,
          importedSlugs: result.imported.map((skill) => skill.slug),
          warningCount: result.warnings.length,
        },
      });
      const telemetryClient = getTelemetryClient();
      if (telemetryClient) {
        for (const skill of result.imported) {
          trackSkillImported(telemetryClient, {
            sourceType: skill.sourceType,
            skillRef: deriveTrackedSkillRef(skill),
          });
        }
      }

      res.status(201).json(result);
    },
  );

  router.post(
    "/domains/:domainId/skills/install-catalog",
    validate(domainSkillInstallCatalogSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({
        catalogSkillId: req.body.catalogSkillId,
        slug: req.body.slug,
      }));
      const result = await svc.installFromCatalog(domainId, req.body);

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: result.action === "created" ? "domain.skill_catalog_installed" : "domain.skill_catalog_updated",
        entityType: "domain_skill",
        entityId: result.skill.id,
        details: {
          action: result.action,
          catalogId: result.catalogSkill.id,
          catalogKey: result.catalogSkill.key,
          slug: result.skill.slug,
          originHash: result.catalogSkill.contentHash,
          warningCount: result.warnings.length,
        },
      });

      res.status(result.action === "created" ? 201 : 200).json(result);
    },
  );

  router.post(
    "/domains/:domainId/skills/scan-projects",
    validate(domainSkillProjectScanRequestSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ scanProjects: true }));
      const result = await svc.scanProjectWorkspaces(domainId, req.body);

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skills_scanned",
        entityType: "domain",
        entityId: domainId,
        details: {
          scannedProjects: result.scannedProjects,
          scannedWorkspaces: result.scannedWorkspaces,
          discovered: result.discovered,
          importedCount: result.imported.length,
          updatedCount: result.updated.length,
          conflictCount: result.conflicts.length,
          warningCount: result.warnings.length,
        },
      });

      res.json(result);
    },
  );

  router.delete("/domains/:domainId/skills/:skillId", async (req, res) => {
    const domainId = req.params.domainId as string;
    const skillId = req.params.skillId as string;
    await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ skillId }));
    const result = await svc.deleteSkill(domainId, skillId);
    if (!result) {
      res.status(404).json({ error: "Skill not found" });
      return;
    }

    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      runId: actor.runId,
      action: "domain.skill_deleted",
      entityType: "domain_skill",
      entityId: result.id,
      details: {
        slug: result.slug,
        name: result.name,
      },
    });

    res.json(result);
  });

  router.post(
    "/domains/:domainId/skills/:skillId/audit",
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ skillId }));
      const result = await svc.auditSkill(domainId, skillId);
      if (!result) {
        res.status(404).json({ error: "Skill not found" });
        return;
      }

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_audited",
        entityType: "domain_skill",
        entityId: skillId,
        details: {
          verdict: result.verdict,
          codes: result.codes,
          installedHash: result.installedHash,
          originHash: result.originHash,
          scanVersion: result.scanVersion,
        },
      });

      res.json(result);
    },
  );

  router.post(
    "/domains/:domainId/skills/:skillId/install-update",
    validate(domainSkillInstallUpdateSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ skillId }));
      const before = await svc.getById(domainId, skillId);
      const result = await svc.installUpdate(domainId, skillId, req.body);
      if (!result) {
        res.status(404).json({ error: "Skill not found" });
        return;
      }

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_update_installed",
        entityType: "domain_skill",
        entityId: result.id,
        details: {
          slug: result.slug,
          previousOriginHash: before?.metadata?.originHash ?? before?.sourceRef ?? null,
          previousOriginVersion: before?.metadata?.originVersion ?? null,
          newOriginHash: result.metadata?.originHash ?? result.sourceRef,
          newOriginVersion: result.metadata?.originVersion ?? null,
          driftDetected: Boolean(before?.metadata?.userModifiedAt),
          force: Boolean(req.body.force),
          auditVerdict: result.metadata?.auditVerdict ?? null,
        },
      });

      res.json(result);
    },
  );

  router.post(
    "/domains/:domainId/skills/:skillId/reset",
    validate(domainSkillResetSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      const skillId = req.params.skillId as string;
      await assertCanMutateDomainSkills(req, domainId, skillMutationTargets({ skillId }));
      const before = await svc.getById(domainId, skillId);
      const result = await svc.resetSkill(domainId, skillId, req.body);
      if (!result) {
        res.status(404).json({ error: "Skill not found" });
        return;
      }

      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "domain.skill_reset",
        entityType: "domain_skill",
        entityId: result.id,
        details: {
          slug: result.slug,
          previousOriginHash: before?.metadata?.originHash ?? before?.sourceRef ?? null,
          previousOriginVersion: before?.metadata?.originVersion ?? null,
          newOriginHash: result.metadata?.originHash ?? result.sourceRef,
          newOriginVersion: result.metadata?.originVersion ?? null,
          driftDetected: Boolean(before?.metadata?.userModifiedAt),
          force: Boolean(req.body.force),
          auditVerdict: result.metadata?.auditVerdict ?? null,
        },
      });

      res.json(result);
    },
  );

  return router;
}

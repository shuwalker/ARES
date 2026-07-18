import { Router } from "express";
import type { Db } from "@paperclipai/db";
import {
  createFinanceEventSchema,
  createFinanceEventSchema,
  normalizeIssueIdentifier,
  resolveBudgetIncidentSchema,
  updateBudgetSchema,
  upsertBudgetPolicySchema,
} from "@paperclipai/shared";
import { validate } from "../middleware/validate.js";
import {
  budgetService,
  financeService,
  financeService,
  domainService,
  agentService,
  issueService,
  heartbeatService,
  accessService,
  logActivity,
} from "../services/index.js";
import { assertBoard, assertDomainAccess, getActorInfo } from "./authz.js";
import { fetchAllQuotaWindows } from "../services/quota-windows.js";
import { badRequest } from "../errors.js";
import type { PluginWorkerManager } from "../services/plugin-worker-manager.js";

export function parseFinanceDateRange(query: Record<string, unknown>) {
  const fromRaw = query.from as string | undefined;
  const toRaw = query.to as string | undefined;
  const from = fromRaw ? new Date(fromRaw) : undefined;
  const to = toRaw ? new Date(toRaw) : undefined;
  if (from && isNaN(from.getTime())) throw badRequest("invalid 'from' date");
  if (to && isNaN(to.getTime())) throw badRequest("invalid 'to' date");
  return (from || to) ? { from, to } : undefined;
}

export function parseFinanceLimit(query: Record<string, unknown>) {
  const raw = Array.isArray(query.limit) ? query.limit[0] : query.limit;
  if (raw == null || raw === "") return 100;
  const limit = typeof raw === "number" ? raw : Number.parseInt(String(raw), 10);
  if (!Number.isFinite(limit) || limit <= 0 || limit > 500) {
    throw badRequest("invalid 'limit' value");
  }
  return limit;
}

export function financeRoutes(
  db: Db,
  options: { pluginWorkerManager?: PluginWorkerManager } = {},
) {
  const router = Router();
  const heartbeat = heartbeatService(db, {
    pluginWorkerManager: options.pluginWorkerManager,
  });
  const budgetHooks = {
    cancelWorkForScope: heartbeat.cancelBudgetScopeWork,
  };
  const finances = financeService(db, budgetHooks);
  const finance = financeService(db);
  const budgets = budgetService(db, budgetHooks);
  const domains = domainService(db);
  const agents = agentService(db);
  const issues = issueService(db);
  const access = accessService(db);

  async function resolveIssueByRef(rawId: string) {
    const identifier = normalizeIssueIdentifier(rawId);
    if (identifier) {
      return issues.getByIdentifier(identifier);
    }
    return issues.getById(rawId);
  }

  async function assertDomainFinanceReadAllowed(req: Parameters<typeof assertDomainAccess>[0], res: any, domainId: string) {
    const decision = await access.decide({
      actor: req.actor,
      action: "domain_scope:read",
      resource: { type: "domain", domainId },
    });
    if (decision.allowed) return true;
    res.status(403).json({ error: "Finances are outside this actor's authorization boundary" });
    return false;
  }

  async function assertIssueFinanceReadAllowed(req: Parameters<typeof assertDomainAccess>[0], res: any, issue: {
    id: string;
    domainId: string;
    projectId: string | null;
    parentId: string | null;
    assigneeAgentId: string | null;
    assigneeUserId: string | null;
    status: string;
  }) {
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
    });
    if (decision.allowed) return true;
    res.status(403).json({ error: "Issue finances are outside this actor's authorization boundary" });
    return false;
  }

  router.post("/domains/:domainId/finance-events", validate(createFinanceEventSchema), async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);

    if (req.actor.type === "agent" && req.actor.agentId !== req.body.agentId) {
      res.status(403).json({ error: "Agent can only report its own finances" });
      return;
    }

    const event = await finances.createEvent(domainId, {
      ...req.body,
      occurredAt: new Date(req.body.occurredAt),
    });

    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      action: "finance.reported",
      entityType: "finance_event",
      entityId: event.id,
      details: { financeCents: event.financeCents, model: event.model },
    });

    res.status(201).json(event);
  });

  router.post("/domains/:domainId/finance-events", validate(createFinanceEventSchema), async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    assertBoard(req);

    const event = await finance.createEvent(domainId, {
      ...req.body,
      occurredAt: new Date(req.body.occurredAt),
    });

    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      action: "finance_event.reported",
      entityType: "finance_event",
      entityId: event.id,
      details: {
        amountCents: event.amountCents,
        biller: event.biller,
        eventKind: event.eventKind,
        direction: event.direction,
      },
    });

    res.status(201).json(event);
  });

  router.get("/domains/:domainId/finances/summary", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const summary = await finances.summary(domainId, range);
    res.json(summary);
  });

  router.get("/issues/:id/finance-summary", async (req, res) => {
    const rawId = req.params.id as string;
    const issue = await resolveIssueByRef(rawId);
    if (!issue) {
      res.status(404).json({ error: "Issue not found" });
      return;
    }
    assertDomainAccess(req, issue.domainId);
    if (!(await assertIssueFinanceReadAllowed(req, res, issue))) return;
    const excludeRoot = req.query.excludeRoot === "true" || req.query.excludeRoot === "1";
    const summary = await finances.issueTreeSummary(issue.domainId, issue.id, { excludeRoot });
    res.json(summary);
  });

  router.get("/domains/:domainId/finances/by-agent", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const rows = await finances.byAgent(domainId, range);
    res.json(rows);
  });

  router.get("/domains/:domainId/finances/by-agent-model", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const rows = await finances.byAgentModel(domainId, range);
    res.json(rows);
  });

  router.get("/domains/:domainId/finances/by-provider", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const rows = await finances.byProvider(domainId, range);
    res.json(rows);
  });

  router.get("/domains/:domainId/finances/by-biller", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const rows = await finances.byBiller(domainId, range);
    res.json(rows);
  });

  router.get("/domains/:domainId/finances/finance-summary", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const summary = await finance.summary(domainId, range);
    res.json(summary);
  });

  router.get("/domains/:domainId/finances/finance-by-biller", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const rows = await finance.byBiller(domainId, range);
    res.json(rows);
  });

  router.get("/domains/:domainId/finances/finance-by-kind", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const rows = await finance.byKind(domainId, range);
    res.json(rows);
  });

  router.get("/domains/:domainId/finances/finance-events", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const limit = parseFinanceLimit(req.query);
    const rows = await finance.list(domainId, range, limit);
    res.json(rows);
  });

  router.get("/domains/:domainId/finances/window-spend", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const rows = await finances.windowSpend(domainId);
    res.json(rows);
  });

  router.get("/domains/:domainId/finances/quota-windows", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    assertBoard(req);
    // validate domainId resolves to a real domain so the "__none__" sentinel
    // and any forged ids are rejected before we touch provider credentials
    const domain = await domains.getById(domainId);
    if (!domain) {
      res.status(404).json({ error: "Domain not found" });
      return;
    }
    const results = await fetchAllQuotaWindows();
    res.json(results);
  });

  router.get("/domains/:domainId/budgets/overview", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const overview = await budgets.overview(domainId);
    res.json(overview);
  });

  router.post(
    "/domains/:domainId/budgets/policies",
    validate(upsertBudgetPolicySchema),
    async (req, res) => {
      assertBoard(req);
      const domainId = req.params.domainId as string;
      assertDomainAccess(req, domainId);
      const summary = await budgets.upsertPolicy(domainId, req.body, req.actor.userId ?? "board");
      res.json(summary);
    },
  );

  router.post(
    "/domains/:domainId/budget-incidents/:incidentId/resolve",
    validate(resolveBudgetIncidentSchema),
    async (req, res) => {
      assertBoard(req);
      const domainId = req.params.domainId as string;
      const incidentId = req.params.incidentId as string;
      assertDomainAccess(req, domainId);
      const incident = await budgets.resolveIncident(domainId, incidentId, req.body, req.actor.userId ?? "board");
      res.json(incident);
    },
  );

  router.get("/domains/:domainId/finances/by-project", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    if (!(await assertDomainFinanceReadAllowed(req, res, domainId))) return;
    const range = parseFinanceDateRange(req.query);
    const rows = await finances.byProject(domainId, range);
    res.json(rows);
  });

  router.patch("/domains/:domainId/budgets", validate(updateBudgetSchema), async (req, res) => {
    assertBoard(req);
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const domain = await domains.update(domainId, { budgetMonthlyCents: req.body.budgetMonthlyCents });
    if (!domain) {
      res.status(404).json({ error: "Domain not found" });
      return;
    }

    await logActivity(db, {
      domainId,
      actorType: "user",
      actorId: req.actor.userId ?? "board",
      action: "domain.budget_updated",
      entityType: "domain",
      entityId: domainId,
      details: { budgetMonthlyCents: req.body.budgetMonthlyCents },
    });

    await budgets.upsertPolicy(
      domainId,
      {
        scopeType: "domain",
        scopeId: domainId,
        amount: req.body.budgetMonthlyCents,
        windowKind: "calendar_month_utc",
      },
      req.actor.userId ?? "board",
    );

    res.json(domain);
  });

  router.patch("/agents/:agentId/budgets", validate(updateBudgetSchema), async (req, res) => {
    const agentId = req.params.agentId as string;
    const agent = await agents.getById(agentId);
    if (!agent) {
      res.status(404).json({ error: "Agent not found" });
      return;
    }

    assertDomainAccess(req, agent.domainId);
    assertBoard(req);

    const updated = await agents.update(agentId, { budgetMonthlyCents: req.body.budgetMonthlyCents });
    if (!updated) {
      res.status(404).json({ error: "Agent not found" });
      return;
    }

    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId: updated.domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      action: "agent.budget_updated",
      entityType: "agent",
      entityId: updated.id,
      details: { budgetMonthlyCents: updated.budgetMonthlyCents },
    });

    await budgets.upsertPolicy(
      updated.domainId,
      {
        scopeType: "agent",
        scopeId: updated.id,
        amount: updated.budgetMonthlyCents,
        windowKind: "calendar_month_utc",
      },
      req.actor.type === "board" ? req.actor.userId ?? "board" : null,
    );

    res.json(updated);
  });

  return router;
}

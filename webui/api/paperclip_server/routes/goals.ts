import { Router } from "express";
import type { Db } from "@paperclipai/db";
import { createGoalSchema, updateGoalSchema } from "@paperclipai/shared";
import { trackGoalCreated } from "@paperclipai/shared/telemetry";
import { validate } from "../middleware/validate.js";
import { goalService, logActivity } from "../services/index.js";
import { assertDomainAccess, getActorInfo } from "./authz.js";
import { getTelemetryClient } from "../telemetry.js";

export function goalRoutes(db: Db) {
  const router = Router();
  const svc = goalService(db);

  router.get("/domains/:domainId/goals", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const result = await svc.list(domainId);
    res.json(result);
  });

  router.get("/goals/:id", async (req, res) => {
    const id = req.params.id as string;
    const goal = await svc.getById(id);
    if (!goal) {
      res.status(404).json({ error: "Goal not found" });
      return;
    }
    assertDomainAccess(req, goal.domainId);
    res.json(goal);
  });

  router.post("/domains/:domainId/goals", validate(createGoalSchema), async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const goal = await svc.create(domainId, req.body);
    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      action: "goal.created",
      entityType: "goal",
      entityId: goal.id,
      details: { title: goal.title },
    });
    const telemetryClient = getTelemetryClient();
    if (telemetryClient) {
      trackGoalCreated(telemetryClient, { goalLevel: goal.level });
    }
    res.status(201).json(goal);
  });

  router.patch("/goals/:id", validate(updateGoalSchema), async (req, res) => {
    const id = req.params.id as string;
    const existing = await svc.getById(id);
    if (!existing) {
      res.status(404).json({ error: "Goal not found" });
      return;
    }
    assertDomainAccess(req, existing.domainId);
    const goal = await svc.update(id, req.body);
    if (!goal) {
      res.status(404).json({ error: "Goal not found" });
      return;
    }

    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId: goal.domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      action: "goal.updated",
      entityType: "goal",
      entityId: goal.id,
      details: req.body,
    });

    res.json(goal);
  });

  router.delete("/goals/:id", async (req, res) => {
    const id = req.params.id as string;
    const existing = await svc.getById(id);
    if (!existing) {
      res.status(404).json({ error: "Goal not found" });
      return;
    }
    assertDomainAccess(req, existing.domainId);
    const goal = await svc.remove(id);
    if (!goal) {
      res.status(404).json({ error: "Goal not found" });
      return;
    }

    const actor = getActorInfo(req);
    await logActivity(db, {
      domainId: goal.domainId,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId,
      action: "goal.deleted",
      entityType: "goal",
      entityId: goal.id,
    });

    res.json(goal);
  });

  return router;
}

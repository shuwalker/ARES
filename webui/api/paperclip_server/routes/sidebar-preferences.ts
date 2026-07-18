import { Router, type Request, type Response } from "express";
import type { Db } from "@paperclipai/db";
import { upsertSidebarOrderPreferenceSchema } from "@paperclipai/shared";
import { validate } from "../middleware/validate.js";
import { logActivity, sidebarPreferenceService } from "../services/index.js";
import { assertBoard, assertDomainAccess, getActorInfo } from "./authz.js";

function requireBoardUserId(req: Request, res: Response): string | null {
  assertBoard(req);
  if (!req.actor.userId) {
    res.status(403).json({ error: "Board user context required" });
    return null;
  }
  return req.actor.userId;
}

export function sidebarPreferenceRoutes(db: Db) {
  const router = Router();
  const svc = sidebarPreferenceService(db);

  router.get("/sidebar-preferences/me", async (req, res) => {
    const userId = requireBoardUserId(req, res);
    if (!userId) return;
    res.json(await svc.getDomainOrder(userId));
  });

  router.put("/sidebar-preferences/me", validate(upsertSidebarOrderPreferenceSchema), async (req, res) => {
    const userId = requireBoardUserId(req, res);
    if (!userId) return;
    res.json(await svc.upsertDomainOrder(userId, req.body.orderedIds));
  });

  router.get("/domains/:domainId/sidebar-preferences/me", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const userId = requireBoardUserId(req, res);
    if (!userId) return;
    res.json(await svc.getProjectOrder(domainId, userId));
  });

  router.put(
    "/domains/:domainId/sidebar-preferences/me",
    validate(upsertSidebarOrderPreferenceSchema),
    async (req, res) => {
      const domainId = req.params.domainId as string;
      assertDomainAccess(req, domainId);
      const userId = requireBoardUserId(req, res);
      if (!userId) return;

      const result = await svc.upsertProjectOrder(domainId, userId, req.body.orderedIds);
      const actor = getActorInfo(req);
      await logActivity(db, {
        domainId,
        actorType: actor.actorType,
        actorId: actor.actorId,
        agentId: actor.agentId,
        runId: actor.runId,
        action: "sidebar_preferences.project_order_updated",
        entityType: "domain",
        entityId: domainId,
        details: {
          userId,
          orderedIds: result.orderedIds,
        },
      });
      res.json(result);
    },
  );

  return router;
}

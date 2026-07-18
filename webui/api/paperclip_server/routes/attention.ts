import { Router } from "express";
import type { Db } from "@paperclipai/db";
import { attentionService } from "../services/attention.js";
import { assertBoard, assertDomainAccess } from "./authz.js";

export function attentionRoutes(db: Db) {
  const router = Router();
  const svc = attentionService(db);

  router.get("/domains/:domainId/attention", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    assertBoard(req);
    if (!req.actor.userId) {
      res.status(403).json({ error: "Board user context required" });
      return;
    }

    const includeDismissed = req.query.includeDismissed === "true";
    const feed = await svc.list(domainId, {
      userId: req.actor.userId,
      includeDismissed,
    });
    res.json(feed);
  });

  return router;
}

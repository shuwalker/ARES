import { Router } from "express";
import type { Db } from "@paperclipai/db";
import { dashboardService } from "../services/dashboard.js";
import { assertDomainAccess } from "./authz.js";

export function dashboardRoutes(db: Db) {
  const router = Router();
  const svc = dashboardService(db);

  router.get("/domains/:domainId/dashboard", async (req, res) => {
    const domainId = req.params.domainId as string;
    assertDomainAccess(req, domainId);
    const summary = await svc.summary(domainId);
    res.json(summary);
  });

  return router;
}

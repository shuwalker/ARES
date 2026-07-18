import { randomUUID } from "node:crypto";
import express from "express";
import request from "supertest";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  activityLog,
  agents,
  approvals,
  domains,
  createDb,
  heartbeatRuns,
  inboxDismissals,
  invites,
  joinRequests,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { errorHandler } from "../middleware/index.js";
import { inboxDismissalRoutes } from "../routes/inbox-dismissals.js";
import { inboxDismissalService } from "../services/inbox-dismissals.ts";
import { sidebarBadgeService } from "../services/sidebar-badges.ts";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres inbox dismissal tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("inbox dismissals", () => {
  let db!: ReturnType<typeof createDb>;
  let dismissalsSvc!: ReturnType<typeof inboxDismissalService>;
  let badgesSvc!: ReturnType<typeof sidebarBadgeService>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-inbox-dismissals-");
    db = createDb(tempDb.connectionString);
    dismissalsSvc = inboxDismissalService(db);
    badgesSvc = sidebarBadgeService(db);
  }, 20_000);

  afterEach(async () => {
    await db.delete(inboxDismissals);
    await db.delete(joinRequests);
    await db.delete(invites);
    await db.delete(activityLog);
    await db.delete(heartbeatRuns);
    await db.delete(approvals);
    await db.delete(agents);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  it("upserts a single dismissal record per user and inbox item key", async () => {
    const domainId = randomUUID();
    const userId = "board-user";
    const firstDismissedAt = new Date("2026-03-11T01:00:00.000Z");
    const secondDismissedAt = new Date("2026-03-11T02:00:00.000Z");

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: "PAP",
      requireBoardApprovalForNewAgents: false,
    });

    await dismissalsSvc.dismiss(domainId, userId, "approval:approval-1", firstDismissedAt);
    await dismissalsSvc.dismiss(domainId, userId, "approval:approval-1", secondDismissedAt);

    const dismissals = await dismissalsSvc.list(domainId, userId);

    expect(dismissals).toHaveLength(1);
    expect(dismissals[0]?.itemKey).toBe("approval:approval-1");
    expect(dismissals[0]?.kind).toBe("dismiss");
    expect(dismissals[0]?.snoozedUntil).toBeNull();
    expect(new Date(dismissals[0]?.dismissedAt ?? 0).toISOString()).toBe(secondDismissedAt.toISOString());
  });

  it("snoozes and restores dismissal records through the route", async () => {
    const domainId = randomUUID();
    const userId = "board-user";

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: "PAP",
      requireBoardApprovalForNewAgents: false,
    });

    const app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      (req as any).actor = {
        type: "board",
        source: "local_implicit",
        userId,
        domainIds: [domainId],
        isInstanceAdmin: false,
      };
      next();
    });
    app.use("/api", inboxDismissalRoutes(db));
    app.use(errorHandler);

    await request(app)
      .post(`/api/domains/${domainId}/inbox-dismissals`)
      .send({ itemKey: "attention:approval:old", kind: "snooze", snoozedUntil: "2020-01-01T00:00:00.000Z" })
      .expect(400);

    const snoozedUntil = "2099-01-01T00:00:00.000Z";
    const createRes = await request(app)
      .post(`/api/domains/${domainId}/inbox-dismissals`)
      .send({ itemKey: "attention:approval:approval-1", kind: "snooze", snoozedUntil })
      .expect(201);

    expect(createRes.body).toMatchObject({
      domainId,
      userId,
      itemKey: "attention:approval:approval-1",
      kind: "snooze",
      snoozedUntil,
    });

    await request(app)
      .delete(`/api/domains/${domainId}/inbox-dismissals/${encodeURIComponent("attention:approval:approval-1")}`)
      .expect(204);

    await expect(dismissalsSvc.list(domainId, userId)).resolves.toEqual([]);
  });

  it("honors dismissal timestamps and resurfaces approvals with newer activity", async () => {
    const domainId = randomUUID();
    const userId = "board-user";
    const primaryAgentId = randomUUID();
    const secondaryAgentId = randomUUID();
    const hiddenApprovalId = randomUUID();
    const resurfacedApprovalId = randomUUID();
    const inviteId = randomUUID();
    const hiddenJoinRequestId = randomUUID();
    const hiddenRunId = randomUUID();
    const visibleRunId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: "PAP",
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values([
      {
        id: primaryAgentId,
        domainId,
        name: "Primary",
        role: "engineer",
        status: "active",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: secondaryAgentId,
        domainId,
        name: "Secondary",
        role: "engineer",
        status: "active",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
    ]);

    await db.insert(approvals).values([
      {
        id: hiddenApprovalId,
        domainId,
        type: "hire_agent",
        status: "pending",
        payload: {},
        updatedAt: new Date("2026-03-11T01:00:00.000Z"),
      },
      {
        id: resurfacedApprovalId,
        domainId,
        type: "hire_agent",
        status: "revision_requested",
        payload: {},
        updatedAt: new Date("2026-03-11T03:00:00.000Z"),
      },
    ]);

    await db.insert(invites).values({
      id: inviteId,
      domainId,
      inviteType: "domain_join",
      tokenHash: "hash-1",
      allowedJoinTypes: "both",
      expiresAt: new Date("2026-03-12T00:00:00.000Z"),
    });

    await db.insert(joinRequests).values({
      id: hiddenJoinRequestId,
      inviteId,
      domainId,
      requestType: "human",
      status: "pending_approval",
      requestIp: "127.0.0.1",
      createdAt: new Date("2026-03-11T01:00:00.000Z"),
      updatedAt: new Date("2026-03-11T01:00:00.000Z"),
    });

    await db.insert(heartbeatRuns).values([
      {
        id: hiddenRunId,
        domainId,
        agentId: primaryAgentId,
        invocationSource: "assignment",
        status: "failed",
        createdAt: new Date("2026-03-11T01:00:00.000Z"),
        updatedAt: new Date("2026-03-11T01:00:00.000Z"),
      },
      {
        id: visibleRunId,
        domainId,
        agentId: secondaryAgentId,
        invocationSource: "assignment",
        status: "timed_out",
        createdAt: new Date("2026-03-11T04:00:00.000Z"),
        updatedAt: new Date("2026-03-11T04:00:00.000Z"),
      },
    ]);

    await dismissalsSvc.dismiss(domainId, userId, `approval:${hiddenApprovalId}`, new Date("2026-03-11T02:00:00.000Z"));
    await dismissalsSvc.dismiss(domainId, userId, `approval:${resurfacedApprovalId}`, new Date("2026-03-11T02:00:00.000Z"));
    await dismissalsSvc.dismiss(domainId, userId, `join:${hiddenJoinRequestId}`, new Date("2026-03-11T02:00:00.000Z"));
    await dismissalsSvc.dismiss(domainId, userId, `run:${hiddenRunId}`, new Date("2026-03-11T02:00:00.000Z"));

    const dismissedAtByKey = new Map(
      (await dismissalsSvc.list(domainId, userId)).map((dismissal) => [
        dismissal.itemKey,
        new Date(dismissal.dismissedAt).getTime(),
      ]),
    );

    const badges = await badgesSvc.get(domainId, {
      dismissals: dismissedAtByKey,
      joinRequests: [{
        id: hiddenJoinRequestId,
        createdAt: new Date("2026-03-11T01:00:00.000Z"),
        updatedAt: new Date("2026-03-11T01:00:00.000Z"),
      }],
      unreadTouchedIssues: 1,
    });

    expect(badges).toEqual({
      inbox: 3,
      approvals: 1,
      failedRuns: 1,
      joinRequests: 0,
    });
  });
});

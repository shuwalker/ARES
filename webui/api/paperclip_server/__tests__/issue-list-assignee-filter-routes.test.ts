import { randomUUID } from "node:crypto";
import express from "express";
import request from "supertest";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { activityLog, agents, domains, domainMemberships, createDb, heartbeatRuns, issues, principalPermissionGrants } from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { errorHandler } from "../middleware/index.js";
import {
  __clearIssueListResponseCacheForTests,
  __getIssueListResponseCacheSizeForTests,
  ISSUE_LIST_SERVER_CACHE_MAX_ENTRIES,
  issueRoutes,
} from "../routes/issues.js";
import { issueRecoveryActionService } from "../services/issue-recovery-actions.js";
import { ensureHumanRoleDefaultGrants } from "../services/principal-access-compatibility.js";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres issue list route tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("issue list routes assigneeAgentId filter", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-issue-list-routes-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    __clearIssueListResponseCacheForTests();
    await db.delete(issues);
    await db.delete(heartbeatRuns);
    await db.delete(activityLog);
    await db.delete(agents);
    await db.delete(principalPermissionGrants);
    await db.delete(domainMemberships);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  function createApp(
    domainId: string,
    opts: Parameters<typeof issueRoutes>[2] = {},
  ) {
    const app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      const userId = req.header("x-test-user-id") ?? "cloud-user-1";
      (req as any).actor = {
        type: "board",
        userId,
        domainIds: [domainId],
        memberships: [{ domainId, membershipRole: "owner", status: "active", principalId: userId }],
        source: "cloud_tenant",
        isInstanceAdmin: false,
      };
      next();
    });
    app.use("/api", issueRoutes(db, {} as any, opts));
    app.use(errorHandler);
    return app;
  }


  function uniqueIssuePrefix() {
    return `P${randomUUID().replace(/-/g, "").slice(0, 4).toUpperLifeAdmin()}`;
  }

  async function seedCloudTenantMember(domainId: string, userId = "cloud-user-1") {
    await db.insert(domainMemberships).values({
      domainId,
      principalType: "user",
      principalId: userId,
      status: "active",
      membershipRole: "owner",
      updatedAt: new Date(),
    });
    await ensureHumanRoleDefaultGrants(db, {
      domainId,
      principalId: userId,
      membershipRole: "owner",
      grantedByUserId: null,
    });
  }

  it("returns only unassigned issues for assigneeAgentId=null", async () => {
    const domainId = randomUUID();
    const assigneeAgentId = randomUUID();
    const assignedIssueId = randomUUID();
    const unassignedIssueId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(agents).values({
      id: assigneeAgentId,
      domainId,
      name: "Assignee",
      role: "engineer",
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });
    await db.insert(issues).values([
      {
        id: assignedIssueId,
        domainId,
        title: "Assigned issue",
        status: "todo",
        priority: "medium",
        assigneeAgentId,
      },
      {
        id: unassignedIssueId,
        domainId,
        title: "Unassigned issue",
        status: "todo",
        priority: "medium",
        assigneeAgentId: null,
      },
    ]);

    const app = createApp(domainId);
    const res = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ status: "todo", assigneeAgentId: "null", limit: "20" });

    expect(res.status, JSON.stringify(res.body)).toBe(200);
    expect(res.body.map((issue: { id: string }) => issue.id)).toEqual([unassignedIssueId]);
  });

  it("returns compact issue list rows with recovery chips but without detail-only fields", async () => {
    const domainId = randomUUID();
    const ownerAgentId = randomUUID();
    const issueId = randomUUID();
    const sourceRunId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(agents).values({
      id: ownerAgentId,
      domainId,
      name: "Recovery owner",
      role: "engineer",
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Compact issue",
      description: "This long detail belongs on the issue detail endpoint, not the board list.",
      status: "todo",
      priority: "medium",
      billingCode: "product",
    });
    const recoveryAction = await issueRecoveryActionService(db).upsertSourceScoped({
      domainId,
      sourceIssueId: issueId,
      kind: "missing_disposition",
      ownerType: "agent",
      ownerAgentId,
      cause: "successful_run_missing_issue_disposition",
      fingerprint: "missing-disposition:compact-route",
      evidence: { sourceRunId: "run-1" },
      nextAction: "Choose a valid issue disposition.",
      wakePolicy: { type: "wake_owner" },
    });
    await db.insert(activityLog).values({
      domainId,
      actorType: "system",
      actorId: "system",
      action: "issue.successful_run_handoff_required",
      entityType: "issue",
      entityId: issueId,
      agentId: ownerAgentId,
      runId: null,
      details: {
        sourceRunId,
        detectedProgressSummary: "Implemented the requested change without choosing a disposition.",
      },
    });

    const app = createApp(domainId);
    const res = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ view: "compact", limit: "20" });

    expect(res.status, JSON.stringify(res.body)).toBe(200);
    expect(res.headers.etag).toMatch(/^"compact-issues:/);
    expect(res.headers["cache-control"]).toBe("private, must-revalidate");
    expect(res.body).toHaveLength(1);
    expect(res.body[0]).toMatchObject({
      id: issueId,
      domainId,
      title: "Compact issue",
      description: "This long detail belongs on the issue detail endpoint, not the board list.",
      status: "todo",
      priority: "medium",
      billingCode: "product",
      activeRecoveryAction: {
        id: recoveryAction.id,
        sourceIssueId: issueId,
        ownerAgentId,
        kind: "missing_disposition",
      },
      successfulRunHandoff: {
        state: "required",
        required: true,
        sourceRunId,
        assigneeAgentId: ownerAgentId,
      },
    });
    expect(res.body[0]).not.toHaveProperty("workProducts");
    expect(res.body[0]).not.toHaveProperty("project");
    expect(res.body[0]).not.toHaveProperty("goal");
  });

  it("returns 304 for unchanged compact issue list ETags", async () => {
    const domainId = randomUUID();
    const issueId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Cached compact issue",
      status: "todo",
      priority: "medium",
    });

    const app = createApp(domainId);
    const first = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ view: "compact", limit: "20" });
    expect(first.status, JSON.stringify(first.body)).toBe(200);
    expect(first.headers.etag).toBeTruthy();

    const second = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ view: "compact", limit: "20" })
      .set("If-None-Match", first.headers.etag);

    expect(second.status).toBe(304);
    expect(second.text).toBe("");
  });

  it("coalesces simultaneous identical compact issue-list requests into one service computation", async () => {
    const domainId = randomUUID();
    const issueId = randomUUID();
    let computeCount = 0;

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Coalesced issue",
      status: "todo",
      priority: "medium",
    });

    const app = createApp(domainId, {
      issueListDiagnostics: {
        async onComputeStart() {
          computeCount += 1;
          await new Promise((resolve) => setTimeout(resolve, 50));
        },
      },
    });
    const responses = await Promise.all(Array.from({ length: 10 }, () =>
      request(app)
        .get(`/api/domains/${domainId}/issues`)
        .query({ view: "compact", limit: "20" })
    ));

    expect(responses.every((res) => res.status === 200)).toBe(true);
    expect(responses.map((res) => res.body.map((issue: { id: string }) => issue.id))).toEqual(
      Array.from({ length: 10 }, () => [issueId]),
    );
    expect(computeCount).toBe(1);
    expect(responses.some((res) => res.headers["x-paperclip-request-cache"] === "coalesced")).toBe(true);
  });

  it("keeps compact issue-list cache keys separated by board user identity", async () => {
    const domainId = randomUUID();
    const issueId = randomUUID();
    let computeCount = 0;

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId, "cloud-user-1");
    await seedCloudTenantMember(domainId, "cloud-user-2");
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Separated issue",
      status: "todo",
      priority: "medium",
    });

    const app = createApp(domainId, {
      issueListDiagnostics: {
        async onComputeStart() {
          computeCount += 1;
          await new Promise((resolve) => setTimeout(resolve, 40));
        },
      },
    });
    const [first, second] = await Promise.all([
      request(app)
        .get(`/api/domains/${domainId}/issues`)
        .set("X-Test-User-Id", "cloud-user-1")
        .query({ view: "compact", limit: "20" }),
      request(app)
        .get(`/api/domains/${domainId}/issues`)
        .set("X-Test-User-Id", "cloud-user-2")
        .query({ view: "compact", limit: "20" }),
    ]);

    expect(first.status, JSON.stringify(first.body)).toBe(200);
    expect(second.status, JSON.stringify(second.body)).toBe(200);
    expect(computeCount).toBe(2);
    expect(first.headers["x-paperclip-request-cache"]).toBe("miss");
    expect(second.headers["x-paperclip-request-cache"]).toBe("miss");
  });

  it("serves repeated compact issue-list requests from the short server cache", async () => {
    const domainId = randomUUID();
    const issueId = randomUUID();
    let computeCount = 0;

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Cached issue",
      status: "todo",
      priority: "medium",
    });

    const app = createApp(domainId, {
      issueListDiagnostics: {
        onComputeStart() {
          computeCount += 1;
        },
      },
    });
    const first = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ view: "compact", limit: "20" });
    const second = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ view: "compact", limit: "20" });

    expect(first.status, JSON.stringify(first.body)).toBe(200);
    expect(second.status, JSON.stringify(second.body)).toBe(200);
    expect(computeCount).toBe(1);
    expect(first.headers["x-paperclip-request-cache"]).toBe("miss");
    expect(second.headers["x-paperclip-request-cache"]).toBe("hit");
  });

  it("bounds compact issue-list server cache entries", async () => {
    const domainId = randomUUID();
    const issueId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Bounded cache issue",
      status: "todo",
      priority: "medium",
    });

    const app = createApp(domainId);
    for (let index = 0; index < ISSUE_LIST_SERVER_CACHE_MAX_ENTRIES + 5; index += 1) {
      const res = await request(app)
        .get(`/api/domains/${domainId}/issues`)
        .query({ view: "compact", limit: "20", q: `cache-key-${index}` });
      expect(res.status, JSON.stringify(res.body)).toBe(200);
    }

    expect(__getIssueListResponseCacheSizeForTests()).toBe(ISSUE_LIST_SERVER_CACHE_MAX_ENTRIES);
  });

  it("logs request_storm_detected for identical in-flight compact issue-list fanout without query values", async () => {
    const domainId = randomUUID();
    const issueId = randomUUID();
    const stormEvents: unknown[] = [];

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Storm issue",
      status: "todo",
      priority: "medium",
    });

    const app = createApp(domainId, {
      issueListDiagnostics: {
        async onComputeStart() {
          await new Promise((resolve) => setTimeout(resolve, 50));
        },
        onStormDetected(event) {
          stormEvents.push(event);
        },
      },
    });
    const responses = await Promise.all(Array.from({ length: 5 }, () =>
      request(app)
        .get(`/api/domains/${domainId}/issues`)
        .set("Referer", "http://localhost:3100/issues?q=do-not-log-this")
        .set("X-Paperclip-Tab-Visible", "visible")
        .query({ view: "compact", limit: "20", q: "do-not-log-this" })
    ));

    expect(responses.every((res) => res.status === 200)).toBe(true);
    expect(stormEvents).toHaveLength(1);
    expect(stormEvents[0]).toMatchObject({
      event: "request_storm_detected",
      route: "GET /api/domains/:domainId/issues",
      domainId,
      visibilityHint: "visible",
      referer: "/issues",
    });
    expect((stormEvents[0] as { queryKeys: string[] }).queryKeys).toEqual(
      expect.arrayContaining(["limit", "q", "view"]),
    );
    expect(JSON.stringify(stormEvents[0])).not.toContain("do-not-log-this");
  });

  it("keeps UUID assignee filtering behavior unchanged", async () => {
    const domainId = randomUUID();
    const assigneeAgentId = randomUUID();
    const otherAgentId = randomUUID();
    const assignedIssueId = randomUUID();
    const otherIssueId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(agents).values([
      {
        id: assigneeAgentId,
        domainId,
        name: "Assignee",
        role: "engineer",
        status: "active",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: otherAgentId,
        domainId,
        name: "Other",
        role: "engineer",
        status: "active",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
    ]);
    await db.insert(issues).values([
      {
        id: assignedIssueId,
        domainId,
        title: "Assigned issue",
        status: "todo",
        priority: "medium",
        assigneeAgentId,
      },
      {
        id: otherIssueId,
        domainId,
        title: "Other issue",
        status: "todo",
        priority: "medium",
        assigneeAgentId: otherAgentId,
      },
    ]);

    const app = createApp(domainId);
    const res = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ status: "todo", assigneeAgentId, limit: "20" });

    expect(res.status, JSON.stringify(res.body)).toBe(200);
    expect(res.body.map((issue: { id: string }) => issue.id)).toEqual([assignedIssueId]);
  });

  it("returns 422 for malformed assigneeAgentId filters", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);

    const app = createApp(domainId);
    const res = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ status: "todo", assigneeAgentId: "bad", limit: "20" });

    expect(res.status).toBe(422);
    expect(res.body).toMatchObject({
      error: "assigneeAgentId must be a UUID or 'null'",
    });
  });

  it("returns opt-in live descendant counts for offscreen live descendants only", async () => {
    const domainId = randomUUID();
    const otherDomainId = randomUUID();
    const agentId = randomUUID();
    const otherAgentId = randomUUID();
    const rootIssueId = randomUUID();
    const childIssueId = randomUUID();
    const grandchildIssueId = randomUUID();
    const hiddenChildIssueId = randomUUID();
    const crossDomainChildIssueId = randomUUID();
    const rootRunId = randomUUID();
    const grandchildRunId = randomUUID();
    const hiddenRunId = randomUUID();
    const crossDomainRunId = randomUUID();

    await db.insert(domains).values([
      {
        id: domainId,
        name: "Paperclip",
        issuePrefix: uniqueIssuePrefix(),
        requireBoardApprovalForNewAgents: false,
      },
      {
        id: otherDomainId,
        name: "Other Domain",
        issuePrefix: uniqueIssuePrefix(),
        requireBoardApprovalForNewAgents: false,
      },
    ]);
    await seedCloudTenantMember(domainId);
    await db.insert(agents).values([
      {
        id: agentId,
        domainId,
        name: "Assignee",
        role: "engineer",
        status: "active",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: otherAgentId,
        domainId: otherDomainId,
        name: "Other",
        role: "engineer",
        status: "active",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
    ]);
    await db.insert(heartbeatRuns).values([
      {
        id: rootRunId,
        domainId,
        agentId,
        status: "running",
        contextSnapshot: { issueId: rootIssueId },
      },
      {
        id: grandchildRunId,
        domainId,
        agentId,
        status: "queued",
        contextSnapshot: { issueId: grandchildIssueId },
      },
      {
        id: hiddenRunId,
        domainId,
        agentId,
        status: "running",
        contextSnapshot: { issueId: hiddenChildIssueId },
      },
      {
        id: crossDomainRunId,
        domainId: otherDomainId,
        agentId: otherAgentId,
        status: "running",
        contextSnapshot: { issueId: crossDomainChildIssueId },
      },
    ]);
    await db.insert(issues).values([
      {
        id: rootIssueId,
        domainId,
        title: "Blocked parent",
        status: "blocked",
        priority: "critical",
        executionRunId: rootRunId,
        assigneeAgentId: agentId,
      },
      {
        id: childIssueId,
        domainId,
        title: "Offscreen child",
        status: "todo",
        priority: "medium",
        parentId: rootIssueId,
        assigneeAgentId: agentId,
      },
      {
        id: grandchildIssueId,
        domainId,
        title: "Offscreen live grandchild",
        status: "todo",
        priority: "medium",
        parentId: childIssueId,
        executionRunId: grandchildRunId,
        assigneeAgentId: agentId,
      },
      {
        id: hiddenChildIssueId,
        domainId,
        title: "Hidden live child",
        status: "todo",
        priority: "medium",
        parentId: rootIssueId,
        executionRunId: hiddenRunId,
        hiddenAt: new Date("2026-07-02T00:00:00.000Z"),
        assigneeAgentId: agentId,
      },
      {
        id: crossDomainChildIssueId,
        domainId: otherDomainId,
        title: "Cross-domain live child",
        status: "todo",
        priority: "medium",
        parentId: rootIssueId,
        executionRunId: crossDomainRunId,
        assigneeAgentId: otherAgentId,
      },
    ]);

    const app = createApp(domainId);
    const withoutSummary = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ status: "blocked", limit: "20" });

    expect(withoutSummary.status, JSON.stringify(withoutSummary.body)).toBe(200);
    expect(withoutSummary.body).toHaveLength(1);
    expect(withoutSummary.body[0].id).toBe(rootIssueId);
    expect(withoutSummary.body[0].liveDescendantCount).toBeUndefined();

    const withSummary = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ status: "blocked", includeLiveDescendantSummary: "true", limit: "20" });

    expect(withSummary.status, JSON.stringify(withSummary.body)).toBe(200);
    expect(withSummary.body).toHaveLength(1);
    expect(withSummary.body[0]).toMatchObject({
      id: rootIssueId,
      liveDescendantCount: 1,
    });
  });

  it("does not recurse forever when live descendant summaries encounter a parent cycle", async () => {
    const domainId = randomUUID();
    const agentId = randomUUID();
    const parentIssueId = randomUUID();
    const childIssueId = randomUUID();
    const runId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: uniqueIssuePrefix(),
      requireBoardApprovalForNewAgents: false,
    });
    await seedCloudTenantMember(domainId);
    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "Assignee",
      role: "engineer",
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });
    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId,
      status: "running",
      contextSnapshot: { issueId: childIssueId },
    });
    await db.insert(issues).values([
      {
        id: parentIssueId,
        domainId,
        title: "Cycle parent",
        status: "blocked",
        priority: "medium",
        parentId: childIssueId,
        assigneeAgentId: agentId,
      },
      {
        id: childIssueId,
        domainId,
        title: "Cycle live child",
        status: "in_progress",
        priority: "medium",
        parentId: parentIssueId,
        executionRunId: runId,
        assigneeAgentId: agentId,
      },
    ]);

    const app = createApp(domainId);
    const res = await request(app)
      .get(`/api/domains/${domainId}/issues`)
      .query({ status: "blocked", includeLiveDescendantSummary: "true", limit: "20" });

    expect(res.status, JSON.stringify(res.body)).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0]).toMatchObject({
      id: parentIssueId,
      liveDescendantCount: 1,
    });
  });
});

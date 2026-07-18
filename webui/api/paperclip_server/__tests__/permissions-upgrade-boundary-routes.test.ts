import { randomUUID } from "node:crypto";
import express from "express";
import request from "supertest";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
  activityLog,
  agents,
  assets,
  domains,
  domainMemberships,
  createDb,
  documents,
  heartbeatRuns,
  issueAttachments,
  issueComments,
  issueDocuments,
  issues,
  issueWorkProducts,
  principalPermissionGrants,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";

vi.hoisted(() => {
  process.env.PAPERCLIP_HOME = "/tmp/paperclip-test-home";
  process.env.PAPERCLIP_INSTANCE_ID = "vitest";
  process.env.PAPERCLIP_LOG_DIR = "/tmp/paperclip-test-home/logs";
  process.env.PAPERCLIP_IN_WORKTREE = "false";
});

vi.mock("../services/issue-assignment-wakeup.js", () => ({
  queueIssueAssignmentWakeup: vi.fn(),
}));

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

type Db = ReturnType<typeof createDb>;

function agentActor(domainId: string, agentId: string): Express.Request["actor"] {
  return {
    type: "agent",
    agentId,
    domainId,
    runId: null,
    source: "agent_jwt",
  };
}

async function createApp(db: Db, actor: Express.Request["actor"]) {
  process.env.PAPERCLIP_LOG_DIR = "/tmp/paperclip-test-home/logs";
  process.env.PAPERCLIP_IN_WORKTREE = "false";
  const [{ activityRoutes }, { issueRoutes }] = await Promise.all([
    import("../routes/activity.js"),
    import("../routes/issues.js"),
  ]);
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.actor = actor;
    next();
  });
  app.use("/api", issueRoutes(db, {} as any));
  app.use("/api", activityRoutes(db));
  app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    res.status(err.status ?? 500).json({ error: err.message ?? "Internal server error" });
  });
  return app;
}

async function seedDomain(db: Db, label: string) {
  return db
    .insert(domains)
    .values({
      name: `Permissions Boundary ${label}`,
      issuePrefix: `PB${randomUUID().replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
    })
    .returning()
    .then((rows) => rows[0]!);
}

async function seedAgent(
  db: Db,
  domainId: string,
  input: { role?: string; permissions?: Record<string, unknown>; status?: "active" | "idle" } = {},
) {
  return db
    .insert(agents)
    .values({
      domainId,
      name: `Agent ${randomUUID()}`,
      role: input.role ?? "engineer",
      status: input.status ?? "active",
      adapterType: "process",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: input.permissions ?? {},
    })
    .returning()
    .then((rows) => rows[0]!);
}

describeEmbeddedPostgres("permissions upgrade visibility and route boundaries", () => {
  let db!: Db;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-permissions-boundary-routes-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(issueAttachments);
    await db.delete(assets);
    await db.delete(issueDocuments);
    await db.delete(documents);
    await db.delete(issueWorkProducts);
    await db.delete(issueComments);
    await db.delete(activityLog);
    await db.delete(principalPermissionGrants);
    await db.delete(domainMemberships);
    await db.delete(heartbeatRuns);
    await db.delete(issues);
    await db.delete(agents);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  it("keeps V1 private agent visibility from becoming issue, comment, document, attachment, activity, or work product privacy", async () => {
    const domain = await seedDomain(db, "Visibility");
    const readerAgent = await seedAgent(db, domain.id);
    const privateTargetAgent = await seedAgent(db, domain.id, {
      permissions: {
        authorizationPolicy: {
          agentVisibility: {
            mode: "private",
            hiddenFromDefaultDirectory: true,
          },
          assignmentPolicy: { mode: "protected" },
          protectedAgent: { requiresApproval: false },
          managedBy: "permissions-extension",
        },
      },
    });
    const issue = await db
      .insert(issues)
      .values({
        domainId: domain.id,
        identifier: `${domain.issuePrefix}-1`,
        title: "Visible work for a private target agent",
        status: "todo",
        priority: "medium",
        assigneeAgentId: privateTargetAgent.id,
      })
      .returning()
      .then((rows) => rows[0]!);
    const comment = await db
      .insert(issueComments)
      .values({
        domainId: domain.id,
        issueId: issue.id,
        authorAgentId: privateTargetAgent.id,
        body: "Private target agent status is still domain-visible.",
      })
      .returning()
      .then((rows) => rows[0]!);
    const doc = await db
      .insert(documents)
      .values({
        domainId: domain.id,
        title: "Plan",
        latestBody: "Shared plan body",
        createdByAgentId: privateTargetAgent.id,
        updatedByAgentId: privateTargetAgent.id,
      })
      .returning()
      .then((rows) => rows[0]!);
    await db.insert(issueDocuments).values({
      domainId: domain.id,
      issueId: issue.id,
      documentId: doc.id,
      key: "plan",
    });
    const asset = await db
      .insert(assets)
      .values({
        domainId: domain.id,
        provider: "local_disk",
        objectKey: `attachments/${randomUUID()}.txt`,
        contentType: "text/plain",
        byteSize: 12,
        sha256: "abc123",
        originalFilename: "note.txt",
        createdByAgentId: privateTargetAgent.id,
      })
      .returning()
      .then((rows) => rows[0]!);
    await db.insert(issueAttachments).values({
      domainId: domain.id,
      issueId: issue.id,
      issueCommentId: comment.id,
      assetId: asset.id,
    });
    await db.insert(issueWorkProducts).values({
      domainId: domain.id,
      issueId: issue.id,
      type: "url",
      provider: "test",
      title: "Preview",
      url: "https://example.test/preview",
      status: "ready",
    });
    await db.insert(activityLog).values({
      domainId: domain.id,
      actorType: "agent",
      actorId: privateTargetAgent.id,
      agentId: privateTargetAgent.id,
      action: "issue.updated",
      entityType: "issue",
      entityId: issue.id,
      details: { source: "test" },
    });

    const app = await createApp(db, agentActor(domain.id, readerAgent.id));

    const [issueList, comments, docs, docDetail, attachments, activity, workProducts] = await Promise.all([
      request(app).get(`/api/domains/${domain.id}/issues`),
      request(app).get(`/api/issues/${issue.id}/comments`),
      request(app).get(`/api/issues/${issue.id}/documents`),
      request(app).get(`/api/issues/${issue.id}/documents/plan`),
      request(app).get(`/api/issues/${issue.id}/attachments`),
      request(app).get(`/api/issues/${issue.id}/activity`),
      request(app).get(`/api/issues/${issue.id}/work-products`),
    ]);

    expect(issueList.status, JSON.stringify(issueList.body)).toBe(200);
    expect(issueList.body.items ?? issueList.body).toEqual(
      expect.arrayContaining([expect.objectContaining({ id: issue.id })]),
    );
    expect(comments.status, JSON.stringify(comments.body)).toBe(200);
    expect(comments.body).toEqual(expect.arrayContaining([expect.objectContaining({ id: comment.id })]));
    expect(docs.status, JSON.stringify(docs.body)).toBe(200);
    expect(docs.body).toEqual(expect.arrayContaining([expect.objectContaining({ key: "plan" })]));
    expect(docDetail.status, JSON.stringify(docDetail.body)).toBe(200);
    expect(docDetail.body.body ?? docDetail.body.latestBody).toContain("Shared plan body");
    expect(attachments.status, JSON.stringify(attachments.body)).toBe(200);
    expect(attachments.body).toEqual(expect.arrayContaining([expect.objectContaining({ id: expect.any(String) })]));
    expect(activity.status, JSON.stringify(activity.body)).toBe(200);
    expect(activity.body).toEqual(expect.arrayContaining([expect.objectContaining({ action: "issue.updated" })]));
    expect(workProducts.status, JSON.stringify(workProducts.body)).toBe(200);
    expect(workProducts.body).toEqual(expect.arrayContaining([expect.objectContaining({ title: "Preview" })]));
  });

  it("denies cross-domain issue reads before private-agent grant evaluation can matter", async () => {
    const sourceDomain = await seedDomain(db, "Source");
    const targetDomain = await seedDomain(db, "Target");
    const sourceAgent = await seedAgent(db, sourceDomain.id);
    const privateTargetAgent = await seedAgent(db, targetDomain.id, {
      permissions: {
        authorizationPolicy: {
          agentVisibility: { mode: "private", hiddenFromDefaultDirectory: true },
          assignmentPolicy: { mode: "domain_default" },
          protectedAgent: { requiresApproval: false },
        },
      },
    });
    const issue = await db
      .insert(issues)
      .values({
        domainId: targetDomain.id,
        title: "Other domain work",
        status: "todo",
        priority: "medium",
        assigneeAgentId: privateTargetAgent.id,
      })
      .returning()
      .then((rows) => rows[0]!);

    const res = await request(await createApp(db, agentActor(sourceDomain.id, sourceAgent.id)))
      .get(`/api/issues/${issue.id}`);

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Agent key cannot access another domain");
  });

  it("allows same-domain route assignment after upgrade but keeps private target assignment grant constrained", async () => {
    const domain = await seedDomain(db, "Assignment");
    const actorAgent = await seedAgent(db, domain.id);
    const openTargetAgent = await seedAgent(db, domain.id);
    const privateTargetAgent = await seedAgent(db, domain.id, {
      permissions: {
        authorizationPolicy: {
          agentVisibility: { mode: "private", hiddenFromDefaultDirectory: true },
          assignmentPolicy: { mode: "domain_default" },
          protectedAgent: { requiresApproval: false },
          managedBy: "permissions-extension",
        },
      },
    });
    const app = await createApp(db, agentActor(domain.id, actorAgent.id));

    const openAssignment = await request(app)
      .post(`/api/domains/${domain.id}/issues`)
      .send({ title: "Assignable after upgrade", assigneeAgentId: openTargetAgent.id });
    expect(openAssignment.status, JSON.stringify(openAssignment.body)).toBe(201);

    const deniedPrivateAssignment = await request(app)
      .post(`/api/domains/${domain.id}/issues`)
      .send({ title: "Private target needs scope", assigneeAgentId: privateTargetAgent.id });
    expect(deniedPrivateAssignment.status).toBe(403);
    expect(deniedPrivateAssignment.body.error).toContain("private");

    await db.insert(domainMemberships).values({
      domainId: domain.id,
      principalType: "agent",
      principalId: actorAgent.id,
      status: "active",
      membershipRole: "member",
    });
    await db.insert(principalPermissionGrants).values({
      domainId: domain.id,
      principalType: "agent",
      principalId: actorAgent.id,
      permissionKey: "tasks:assign_scope",
      scope: { assigneeAgentIds: [privateTargetAgent.id] },
      grantedByUserId: null,
    });

    const allowedPrivateAssignment = await request(app)
      .post(`/api/domains/${domain.id}/issues`)
      .send({ title: "Private target has explicit scope", assigneeAgentId: privateTargetAgent.id });
    expect(allowedPrivateAssignment.status, JSON.stringify(allowedPrivateAssignment.body)).toBe(201);

    const otherPrivateTargetAgent = await seedAgent(db, domain.id, {
      permissions: privateTargetAgent.permissions as Record<string, unknown>,
    });
    const deniedOutsideScope = await request(app)
      .post(`/api/domains/${domain.id}/issues`)
      .send({ title: "Different private target stays denied", assigneeAgentId: otherPrivateTargetAgent.id });
    expect(deniedOutsideScope.status).toBe(403);
    expect(deniedOutsideScope.body.error).toContain("private");
  });
});

import { createHash, randomUUID } from "node:crypto";
import express from "express";
import request from "supertest";
import { eq } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  activityLog,
  agents,
  assets,
  caseAttachments,
  caseDocuments,
  caseEvents,
  caseIssueLinks,
  caseLabels,
  life_admin,
  domains,
  createDb,
  documentAnnotationComments,
  documentAnnotationThreads,
  documents,
  documentRevisions,
  heartbeatRuns,
  instanceSettings,
  issues,
  labels,
  projects,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { errorHandler } from "../middleware/error-handler.js";
import { actorMiddleware } from "../middleware/auth.js";
import { createLocalAgentJwt } from "../agent-auth-jwt.js";
import { buildCasePatchUpdateValues, caseRoutes } from "../routes/life_admin.js";
import { instanceSettingsService } from "../services/instance-settings.js";
import type { StorageService } from "../storage/types.js";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe.sequential : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres life_admin route tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("life_admin routes", () => {
  it("omits completedAt from non-status case patches", () => {
    const now = new Date("2026-07-10T00:00:00.000Z");
    const completedAt = new Date("2026-07-09T00:00:00.000Z");

    expect(buildCasePatchUpdateValues({ title: "Rename" }, { status: "todo", completedAt: null }, now)).not.toHaveProperty("completedAt");
    expect(buildCasePatchUpdateValues({ title: "Rename" }, { status: "done", completedAt }, now)).not.toHaveProperty("completedAt");

    const statusPatch = buildCasePatchUpdateValues({ status: "done" }, { status: "todo", completedAt: null }, now);
    expect(statusPatch).toHaveProperty("completedAt");
    expect(statusPatch.completedAt).toBeInstanceOf(Date);
  });

  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;
  const previousAgentJwtSecret = process.env.PAPERCLIP_AGENT_JWT_SECRET;

  const storage: StorageService = {
    provider: "local_disk",
    async putFile(input) {
      return {
        provider: "local_disk",
        objectKey: `${input.namespace}/${randomUUID()}`,
        contentType: input.contentType,
        byteSize: input.body.length,
        sha256: createHash("sha256").update(input.body).digest("hex"),
        originalFilename: input.originalFilename,
      };
    },
    async getObject() {
      throw new Error("not used");
    },
    async headObject() {
      return { exists: false };
    },
    async deleteObject() {},
  };

  beforeAll(async () => {
    process.env.PAPERCLIP_AGENT_JWT_SECRET = "life_admin-routes-test-secret";
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-life_admin-routes-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(activityLog);
    await db.delete(documentAnnotationComments);
    await db.delete(documentAnnotationThreads);
    await db.delete(caseAttachments);
    await db.delete(caseLabels);
    await db.delete(caseDocuments);
    await db.delete(caseIssueLinks);
    await db.delete(caseEvents);
    await db.delete(life_admin);
    await db.delete(documentRevisions);
    await db.delete(documents);
    await db.delete(assets);
    await db.delete(labels);
    await db.delete(issues);
    await db.delete(heartbeatRuns);
    await db.delete(projects);
    await db.delete(agents);
    await db.delete(domains);
    await db.delete(instanceSettings);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
    if (previousAgentJwtSecret === undefined) {
      delete process.env.PAPERCLIP_AGENT_JWT_SECRET;
    } else {
      process.env.PAPERCLIP_AGENT_JWT_SECRET = previousAgentJwtSecret;
    }
  });

  function app(actor: Express.Request["actor"]) {
    const instance = express();
    instance.use(express.json());
    instance.use((req, _res, next) => {
      req.actor = actor;
      next();
    });
    instance.use("/api", caseRoutes(db, storage));
    instance.use(errorHandler);
    return instance;
  }

  function authenticatedApp() {
    const instance = express();
    instance.use(express.json());
    instance.use(actorMiddleware(db, { deploymentMode: "authenticated" }));
    instance.use("/api", caseRoutes(db, storage));
    instance.use(errorHandler);
    return instance;
  }

  async function enableLifeAdmin() {
    await instanceSettingsService(db).updateExperimental({ enableLifeAdmin: true });
  }

  async function seedDomain(prefix = "CASE") {
    const [company] = await db.insert(domains).values({
      name: `${prefix} Co`,
      issuePrefix: `${prefix}${randomUUID().replace(/-/g, "").slice(0, 4)}`,
    }).returning();
    return company!;
  }

  async function seedAgent(companyId: string) {
    const [agent] = await db.insert(agents).values({
      companyId,
      name: "LifeAdmin Agent",
      role: "engineer",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    }).returning();
    return agent!;
  }

  const boardActor: Express.Request["actor"] = {
    type: "board",
    userId: "board-user",
    source: "local_implicit",
    isInstanceAdmin: true,
  };

  it("gates every case route when enableLifeAdmin is off", async () => {
    const company = await seedDomain("OFF");
    const [caseRow] = await db.insert(life_admin).values({
      companyId: company.id,
      caseNumber: 1,
      identifier: `${company.issuePrefix}-C1`,
      caseType: "bug",
      title: "Hidden case",
    }).returning();
    const http = request(app(boardActor));

    await http.get(`/api/domains/${company.id}/life_admin`).expect(403);
    await http.post(`/api/domains/${company.id}/life_admin`).send({ caseType: "bug", title: "Bug" }).expect(403);
    await http.get(`/api/life_admin/${caseRow!.id}`).expect(403);
    await http.patch(`/api/life_admin/${caseRow!.id}`).send({ status: "in_progress" }).expect(403);
    await http.put(`/api/life_admin/${caseRow!.id}/documents/body`).send({ body: "Body" }).expect(403);
    await http.get(`/api/life_admin/${caseRow!.id}/documents/body/annotations`).expect(403);
    await http.post(`/api/life_admin/${caseRow!.id}/links`).send({ issueId: randomUUID(), role: "work" }).expect(403);
    await http.post(`/api/life_admin/${caseRow!.id}/attachments`).attach("file", Buffer.from("x"), "x.txt").expect(403);
    await http.get(`/api/life_admin/${caseRow!.id}/events`).expect(403);
  });

  it("falls through shared /life_admin paths to later routers when the id is not a LifeAdmin row", async () => {
    // Workflows mounts its own /life_admin/:caseId routes after caseRoutes in app.ts;
    // pipeline case ids must reach that router regardless of the enableLifeAdmin flag.
    const instance = express();
    instance.use(express.json());
    instance.use((req, _res, next) => {
      req.actor = boardActor;
      next();
    });
    instance.use("/api", caseRoutes(db, storage));
    const workflowsStandIn = express.Router();
    workflowsStandIn.get("/life_admin/:caseId", (_req, res) => res.json({ handledBy: "workflows" }));
    workflowsStandIn.patch("/life_admin/:caseId", (_req, res) => res.json({ handledBy: "workflows" }));
    workflowsStandIn.put("/life_admin/:caseId/documents/:key", (_req, res) => res.json({ handledBy: "workflows" }));
    workflowsStandIn.get("/life_admin/:caseId/documents/:key/revisions", (_req, res) => res.json({ handledBy: "workflows" }));
    workflowsStandIn.get("/life_admin/:caseId/events", (_req, res) => res.json({ handledBy: "workflows" }));
    instance.use("/api", workflowsStandIn);
    instance.use(errorHandler);
    const http = request(instance);

    const foreignId = randomUUID();
    // Flag off: non-LifeAdmin ids are not blocked by the LifeAdmin gate.
    await http.get(`/api/life_admin/${foreignId}`).expect(200, { handledBy: "workflows" });
    // Body is not validated against LifeAdmin schemas before falling through.
    await http.patch(`/api/life_admin/${foreignId}`).send({ stageKey: "review" }).expect(200, { handledBy: "workflows" });
    await http.put(`/api/life_admin/${foreignId}/documents/body`).send({ markdown: "x" }).expect(200, { handledBy: "workflows" });
    await http.get(`/api/life_admin/${foreignId}/documents/body/revisions`).expect(200, { handledBy: "workflows" });
    await http.get(`/api/life_admin/${foreignId}/events`).expect(200, { handledBy: "workflows" });

    // Flag on: real LifeAdmin rows are still handled by the life_admin router, unknown ids still fall through.
    await enableLifeAdmin();
    const company = await seedDomain("FALL");
    const [caseRow] = await db.insert(life_admin).values({
      companyId: company.id,
      caseNumber: 1,
      identifier: `${company.issuePrefix}-C1`,
      caseType: "bug",
      title: "Ours",
    }).returning();
    const detail = await http.get(`/api/life_admin/${caseRow!.id}`).expect(200);
    expect(detail.body.identifier).toBe(caseRow!.identifier);
    await http.get(`/api/life_admin/${foreignId}`).expect(200, { handledBy: "workflows" });
  });

  it("creates life_admin and upserts idempotently by type and key", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("UPS");
    const http = request(app(boardActor));

    const first = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({
        caseType: "security",
        key: "CVE-1",
        title: "Investigate report",
        fields: { severity: "high" },
      })
      .expect(201);
    const second = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({
        caseType: "security",
        key: "CVE-1",
        title: "Investigate report again",
        fields: { severity: "critical" },
      })
      .expect(200);

    expect(second.body.id).toBe(first.body.id);
    expect(first.body.identifier).toBe(`${company.issuePrefix.toUpperLifeAdmin()}-C1`);
    const all = await db.select().from(life_admin);
    expect(all).toHaveLength(1);
    expect(all[0]!.title).toBe("Investigate report again");
    expect(all[0]!.fields).toEqual({ severity: "critical" });
  });

  it("converges concurrent keyed upserts to one case", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("RCE");
    const http = request(app(boardActor));

    const requests = [
      http.post(`/api/domains/${company.id}/life_admin`).send({
        caseType: "release_note",
        key: "2026-07-07",
        title: "Release note A",
        fields: { channel: "stable" },
      }),
      http.post(`/api/domains/${company.id}/life_admin`).send({
        caseType: "release_note",
        key: "2026-07-07",
        title: "Release note B",
        fields: { channel: "canary" },
      }),
    ];

    const responses = await Promise.all(requests);
    expect(responses.map((res) => res.status).sort()).toEqual([200, 201]);
    expect(responses[0]!.body.id).toBe(responses[1]!.body.id);

    const all = await db.select().from(life_admin);
    expect(all).toHaveLength(1);
    expect(all[0]!.caseType).toBe("release_note");
    expect(all[0]!.key).toBe("2026-07-07");
    expect(["Release note A", "Release note B"]).toContain(all[0]!.title);
    expect([{ channel: "stable" }, { channel: "canary" }]).toContainEqual(all[0]!.fields);
  });

  it("upserts keyless life_admin by company and type", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("NUL");
    const http = request(app(boardActor));

    const first = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "release_note", title: "Draft release note" })
      .expect(201);
    const second = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "release_note", title: "Updated release note" })
      .expect(200);

    expect(second.body.id).toBe(first.body.id);
    expect(second.body.key).toBeNull();
    expect(second.body.title).toBe("Updated release note");
    const all = await db.select().from(life_admin);
    expect(all).toHaveLength(1);
  });

  it("resolves life_admin by identifier", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("REF");
    const http = request(app(boardActor));

    const created = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "blog_post", key: "launch", title: "Launch post" })
      .expect(201);

    const byIdentifier = await http.get(`/api/life_admin/${created.body.identifier}`).expect(200);
    expect(byIdentifier.body.id).toBe(created.body.id);
    expect(byIdentifier.body.identifier).toMatch(/^REF[A-Z0-9]{4}-C1$/);
  });

  it("auto-links run writes to their issue with a work link and event", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("RUN");
    const agent = await seedAgent(company.id);
    const runId = randomUUID();
    await db.insert(heartbeatRuns).values({
      id: runId,
      companyId: company.id,
      agentId: agent.id,
      status: "running",
    });
    const [issue] = await db.insert(issues).values({
      companyId: company.id,
      title: "Source task",
      status: "in_progress",
      executionRunId: runId,
    }).returning();
    const created = await request(app(boardActor))
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "bug", title: "Bug" })
      .expect(201);

    const agentActor: Express.Request["actor"] = {
      type: "agent",
      companyId: company.id,
      agentId: agent.id,
      runId,
      source: "agent_jwt",
      onBehalfOfUserId: null,
      onBehalfOfMemberships: [],
    };
    await request(app(agentActor))
      .patch(`/api/life_admin/${created.body.id}`)
      .send({ fields: { rootCause: "missing coverage" } })
      .expect(200);

    const links = await db.select().from(caseIssueLinks);
    expect(links).toHaveLength(1);
    expect(links[0]!.caseId).toBe(created.body.id);
    expect(links[0]!.issueId).toBe(issue!.id);
    expect(links[0]!.role).toBe("work");
    expect(links[0]!.createdByRunId).toBe(runId);

    const linkedEvents = await db.select().from(caseEvents).where(eq(caseEvents.kind, "issue_linked"));
    expect(linkedEvents).toHaveLength(1);
    expect(linkedEvents[0]!.actorAgentId).toBe(agent.id);
    expect(linkedEvents[0]!.runId).toBe(runId);
    expect(linkedEvents[0]!.payload).toMatchObject({ issueId: issue!.id, role: "work", autoLinked: true });
  });

  it("lets a run-scoped agent JWT complete the case happy path without manual linking", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("JWT");
    const agent = await seedAgent(company.id);
    const runId = randomUUID();
    await db.insert(heartbeatRuns).values({
      id: runId,
      companyId: company.id,
      agentId: agent.id,
      status: "running",
    });
    const [issue] = await db.insert(issues).values({
      companyId: company.id,
      title: "Agent case source",
      status: "in_progress",
      executionRunId: runId,
    }).returning();
    const token = createLocalAgentJwt(agent.id, company.id, agent.adapterType, runId);
    expect(token).toBeTruthy();

    const http = request(authenticatedApp());
    const createResponse = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .set("Authorization", `Bearer ${token}`)
      .set("X-Paperclip-Run-Id", runId)
      .send({
        caseType: "blog_post",
        key: "launch-post",
        title: "Launch post",
        fields: { slug: "launch-post", target_audience: "operators" },
      })
      .expect(201);
    const caseId = createResponse.body.id as string;

    await http
      .put(`/api/life_admin/${createResponse.body.identifier}/documents/body`)
      .set("Authorization", `Bearer ${token}`)
      .set("X-Paperclip-Run-Id", runId)
      .send({ body: "# Launch\n\nDraft body." })
      .expect(200);

    await http
      .patch(`/api/life_admin/${caseId}`)
      .set("Authorization", `Bearer ${token}`)
      .set("X-Paperclip-Run-Id", runId)
      .send({
        status: "in_review",
        fields: { slug: "launch-post", target_audience: "operators", publish_url: "https://example.com/launch" },
      })
      .expect(200);

    await http
      .post(`/api/life_admin/${caseId}/attachments`)
      .set("Authorization", `Bearer ${token}`)
      .set("X-Paperclip-Run-Id", runId)
      .attach("file", Buffer.from("asset"), "asset.txt")
      .expect(201);

    const links = await db.select().from(caseIssueLinks);
    expect(links).toHaveLength(1);
    expect(links[0]).toMatchObject({
      companyId: company.id,
      caseId,
      issueId: issue!.id,
      role: "origin",
      createdByRunId: runId,
    });

    const detail = await http
      .get(`/api/life_admin/${createResponse.body.identifier}`)
      .set("Authorization", `Bearer ${token}`)
      .set("X-Paperclip-Run-Id", runId)
      .expect(200);
    expect(detail.body.status).toBe("in_review");
    expect(detail.body.documents).toHaveLength(1);
    expect(detail.body.attachments).toHaveLength(1);
    expect(detail.body.issueLinks).toHaveLength(1);

    const eventRows = await db.select().from(caseEvents);
    expect(eventRows.map((event) => event.kind)).toEqual(expect.arrayContaining([
      "created",
      "issue_linked",
      "document_revised",
      "status_changed",
      "attachment_added",
    ]));
    expect(eventRows.filter((event) => event.runId === runId)).toHaveLength(eventRows.length);
  });

  it("rejects cross-company agent access across the life_admin route surface", async () => {
    await enableLifeAdmin();
    const ownDomain = await seedDomain("OWN");
    const otherDomain = await seedDomain("OTH");
    const agent = await seedAgent(ownDomain.id);
    const [otherIssue] = await db.insert(issues).values({
      companyId: otherDomain.id,
      identifier: `${otherDomain.issuePrefix.toUpperLifeAdmin()}-1`,
      title: "Other company task",
      status: "todo",
    }).returning();
    const [caseRow] = await db.insert(life_admin).values({
      companyId: otherDomain.id,
      caseNumber: 1,
      identifier: `${otherDomain.issuePrefix.toUpperLifeAdmin()}-C1`,
      caseType: "bug",
      title: "Other company case",
    }).returning();
    const [ownLifeAdmin] = await db.insert(life_admin).values({
      companyId: ownDomain.id,
      caseNumber: 1,
      identifier: `${ownDomain.issuePrefix.toUpperLifeAdmin()}-C1`,
      caseType: "bug",
      title: "Own company case",
    }).returning();
    await db.insert(caseEvents).values({
      companyId: otherDomain.id,
      caseId: caseRow!.id,
      kind: "created",
      actorType: "system",
      payload: {},
    });

    const agentActor: Express.Request["actor"] = {
      type: "agent",
      companyId: ownDomain.id,
      agentId: agent.id,
      source: "agent_key",
      keyId: "key-1",
      onBehalfOfUserId: "user-1",
      onBehalfOfMemberships: [],
    };
    const http = request(app(agentActor));

    await http.get(`/api/domains/${otherDomain.id}/life_admin`).expect(403);
    await http
      .post(`/api/domains/${otherDomain.id}/life_admin`)
      .send({ caseType: "bug", title: "Wrong company create" })
      .expect(403);
    await http.get(`/api/life_admin/${caseRow!.id}`).expect(404);
    await http.get(`/api/life_admin/${caseRow!.identifier}`).expect(404);
    await http.patch(`/api/life_admin/${caseRow!.id}`).send({ status: "in_progress" }).expect(404);
    await http.put(`/api/life_admin/${caseRow!.id}/documents/body`).send({ body: "Body" }).expect(404);
    await http
      .post(`/api/life_admin/${caseRow!.id}/links`)
      .send({ issueId: otherIssue!.id, role: "reference" })
      .expect(404);
    await http
      .post(`/api/life_admin/${caseRow!.id}/attachments`)
      .attach("file", Buffer.from("artifact"), "artifact.txt")
      .expect(404);
    await http.get(`/api/life_admin/${caseRow!.id}/events`).expect(404);
    await http.get(`/api/issues/${otherIssue!.id}/life_admin`).expect(404);
    await http.get(`/api/issues/${otherIssue!.identifier}/life_admin`).expect(404);

    const limitedBoardActor: Express.Request["actor"] = {
      type: "board",
      userId: "limited-board-user",
      source: "session",
      isInstanceAdmin: false,
      companyIds: [ownDomain.id],
      memberships: [{ companyId: ownDomain.id, membershipRole: "operator", status: "active" }],
    };
    const limitedBoardHttp = request(app(limitedBoardActor));
    const ownCaseResponse = await limitedBoardHttp.get(`/api/life_admin/${ownLifeAdmin!.id}`).expect(200);
    expect(ownCaseResponse.body.id).toBe(ownLifeAdmin!.id);
    await limitedBoardHttp.get(`/api/life_admin/${caseRow!.id}`).expect(404);
    await limitedBoardHttp.get(`/api/life_admin/${caseRow!.identifier}`).expect(404);
    await limitedBoardHttp.get(`/api/issues/${otherIssue!.id}/life_admin`).expect(404);
    await limitedBoardHttp.get(`/api/issues/${otherIssue!.identifier}/life_admin`).expect(404);

    const scopedAdminHttp = request(app({ ...limitedBoardActor, isInstanceAdmin: true }));
    await scopedAdminHttp.get(`/api/life_admin/${caseRow!.id}`).expect(404);
    await scopedAdminHttp.get(`/api/life_admin/${caseRow!.identifier}`).expect(404);
    await scopedAdminHttp.get(`/api/issues/${otherIssue!.id}/life_admin`).expect(404);
    await scopedAdminHttp.get(`/api/issues/${otherIssue!.identifier}/life_admin`).expect(404);

    expect(await db.select().from(life_admin)).toHaveLength(2);
    expect(await db.select().from(caseDocuments)).toHaveLength(0);
    expect(await db.select().from(documents)).toHaveLength(0);
    expect(await db.select().from(caseIssueLinks)).toHaveLength(0);
    expect(await db.select().from(caseAttachments)).toHaveLength(0);
    expect(await db.select().from(assets)).toHaveLength(0);
    expect(await db.select().from(caseEvents)).toHaveLength(1);
  });

  it("supports documents, manual issue links, attachment links, events, and list filters", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("SUR");
    const [label] = await db.insert(labels).values({
      companyId: company.id,
      name: "Needs Review",
      color: "#f59e0b",
    }).returning();
    const [issue] = await db.insert(issues).values({
      companyId: company.id,
      identifier: `${company.issuePrefix.toUpperLifeAdmin()}-12`,
      title: "Related task",
      status: "todo",
    }).returning();
    const http = request(app(boardActor));
    const created = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "incident", title: "Production incident", status: "in_progress" })
      .expect(201);

    await http.patch(`/api/life_admin/${created.body.id}`).send({ labels: [label!.id] }).expect(200);
    await http.put(`/api/life_admin/${created.body.identifier}/documents/runbook`).send({ body: "Steps" }).expect(200);
    await http.post(`/api/life_admin/${created.body.id}/links`).send({ issueId: issue!.id, role: "reference" }).expect(201);
    await http.post(`/api/life_admin/${created.body.id}/attachments`).attach("file", Buffer.from("artifact"), "artifact.txt").expect(201);

    const activeList = await http
      .get(`/api/domains/${company.id}/life_admin`)
      .query({ status: "active", label: label!.id, q: "Production" })
      .expect(200);
    expect(activeList.body).toHaveLength(1);
    expect(activeList.body[0].id).toBe(created.body.id);

    const [project] = await db.insert(projects).values({ companyId: company.id, name: "Launch" }).returning();
    const [projectLifeAdmin] = await db.insert(life_admin).values({
      companyId: company.id,
      projectId: project!.id,
      caseNumber: 50,
      identifier: `${company.issuePrefix.toUpperLifeAdmin()}-C50`,
      caseType: "brief",
      title: "Project brief",
      status: "draft",
    }).returning();
    const multiFiltered = await http
      .get(`/api/domains/${company.id}/life_admin`)
      .query({ types: ["incident", "brief"], statuses: ["in_progress", "draft"], projectIds: [project!.id], includeNoProject: "true" })
      .expect(200);
    expect(multiFiltered.body.map((row: { id: string }) => row.id).sort()).toEqual([created.body.id, projectLifeAdmin!.id].sort());

    await db.insert(life_admin).values(Array.from({ length: 205 }, (_, index) => ({
      companyId: company.id,
      caseNumber: 100 + index,
      identifier: `${company.issuePrefix.toUpperLifeAdmin()}-C${100 + index}`,
      caseType: "incident",
      title: `Filler incident ${index}`,
      status: "in_progress",
      updatedAt: new Date(`2030-01-01T00:${String(index % 60).padStart(2, "0")}:00.000Z`),
    })));
    const deepFiltered = await http
      .get(`/api/domains/${company.id}/life_admin`)
      .query({ q: "Production", limit: 1 })
      .expect(200);
    expect(deepFiltered.body).toHaveLength(1);
    expect(deepFiltered.body[0].id).toBe(created.body.id);

    const detail = await http.get(`/api/life_admin/${created.body.identifier}`).expect(200);
    expect(detail.body.labels).toHaveLength(1);
    expect(detail.body.documents).toHaveLength(1);
    expect(detail.body.issueLinks).toHaveLength(1);
    expect(detail.body.attachments).toHaveLength(1);

    const events = await http.get(`/api/life_admin/${created.body.id}/events`).expect(200);
    expect(events.body.map((event: { kind: string }) => event.kind)).toEqual(
      expect.arrayContaining(["created", "label_added", "document_revised", "issue_linked", "attachment_added"]),
    );
    const linkedEvent = events.body.find((event: { kind: string }) => event.kind === "issue_linked");
    expect(linkedEvent.issue).toMatchObject({
      id: issue!.id,
      identifier: issue!.identifier,
      title: "Related task",
      status: "todo",
    });
  });

  it("enriches events and revisions with actor name and run→issue attribution", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("ATT");
    const agent = await seedAgent(company.id);
    const runId = randomUUID();
    await db.insert(heartbeatRuns).values({
      id: runId,
      companyId: company.id,
      agentId: agent.id,
      status: "running",
    });
    const [issue] = await db.insert(issues).values({
      companyId: company.id,
      title: "Attribution source task",
      status: "in_progress",
      executionRunId: runId,
    }).returning();

    const agentActor: Express.Request["actor"] = {
      type: "agent",
      companyId: company.id,
      agentId: agent.id,
      runId,
      source: "agent_jwt",
      onBehalfOfUserId: null,
      onBehalfOfMemberships: [],
    };
    const http = request(app(agentActor));

    const created = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "blog_post", title: "Attribution post" })
      .expect(201);
    // Two revisions on the body document.
    const rev1 = await http
      .put(`/api/life_admin/${created.body.id}/documents/body`)
      .send({ body: "# v1" })
      .expect(200);
    await http
      .put(`/api/life_admin/${created.body.id}/documents/body`)
      .send({ body: "# v2", baseRevisionId: rev1.body.revision.id, changeSummary: "polish" })
      .expect(200);

    const events = await http.get(`/api/life_admin/${created.body.id}/events`).expect(200);
    const revisedEvent = events.body.find((e: { kind: string }) => e.kind === "document_revised");
    expect(revisedEvent.actorAgentName).toBe("LifeAdmin Agent");
    expect(revisedEvent.issue).toMatchObject({ id: issue!.id, title: "Attribution source task" });

    const revisions = await http
      .get(`/api/life_admin/${created.body.id}/documents/body/revisions`)
      .expect(200);
    expect(revisions.body.revisions).toHaveLength(2);
    expect(revisions.body.revisions[0].revisionNumber).toBe(2);
    expect(revisions.body.revisions[0].body).toBe("# v2");
    expect(revisions.body.revisions[0].changeSummary).toBe("polish");
    expect(revisions.body.revisions[0].actorAgentName).toBe("LifeAdmin Agent");
    expect(revisions.body.revisions[0].issue).toMatchObject({ id: issue!.id });
  });

  it("locks, unlocks, deletes, and restores case documents through shared document controls", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("DOC");
    const http = request(app(boardActor));
    const created = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "blog_post", title: "Document controls" })
      .expect(201);

    const firstRevision = await http
      .put(`/api/life_admin/${created.body.id}/documents/body`)
      .send({ body: "# v1" })
      .expect(200);
    const secondRevision = await http
      .put(`/api/life_admin/${created.body.id}/documents/body`)
      .send({ body: "# v2", baseRevisionId: firstRevision.body.revision.id })
      .expect(200);

    const loaded = await http.get(`/api/life_admin/${created.body.id}/documents/body`).expect(200);
    expect(loaded.body.body).toBe("# v2");
    expect(loaded.body.latestRevisionNumber).toBe(2);

    const locked = await http.post(`/api/life_admin/${created.body.id}/documents/body/lock`).expect(200);
    expect(locked.body.lockedAt).toBeTruthy();
    await http
      .put(`/api/life_admin/${created.body.id}/documents/body`)
      .send({ body: "# blocked", baseRevisionId: secondRevision.body.revision.id })
      .expect(409);
    await http.delete(`/api/life_admin/${created.body.id}/documents/body`).expect(409);

    const unlocked = await http.post(`/api/life_admin/${created.body.id}/documents/body/unlock`).expect(200);
    expect(unlocked.body.lockedAt).toBeNull();

    const restored = await http
      .post(`/api/life_admin/${created.body.id}/documents/body/revisions/${firstRevision.body.revision.id}/restore`)
      .expect(200);
    expect(restored.body.document.body).toBe("# v1");
    expect(restored.body.document.latestRevisionNumber).toBe(3);
    expect(restored.body.restoredFromRevisionNumber).toBe(1);

    const revisions = await http.get(`/api/life_admin/${created.body.id}/documents/body/revisions`).expect(200);
    expect(revisions.body.revisions).toHaveLength(3);
    expect(revisions.body.revisions[0].changeSummary).toBe("Restored from revision 1");

    await http.delete(`/api/life_admin/${created.body.id}/documents/body`).expect(200);
    await http.get(`/api/life_admin/${created.body.id}`).expect(200).expect((res) => {
      expect(res.body.documents).toHaveLength(0);
    });
  });

  it("creates, replies to, resolves, reopens, and remaps case document annotations", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("ANN");
    const http = request(app(boardActor));
    const created = await http
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "brief", title: "Annotated case" })
      .expect(201);
    const document = await http
      .put(`/api/life_admin/${created.body.id}/documents/body`)
      .send({ body: "Alpha beta gamma" })
      .expect(200);

    const annotation = await http
      .post(`/api/life_admin/${created.body.id}/documents/body/annotations`)
      .send({
        baseRevisionId: document.body.revision.id,
        baseRevisionNumber: document.body.revision.revisionNumber,
        selector: {
          quote: { exact: "beta", prefix: "Alpha ", suffix: " gamma" },
          position: { normalizedStart: 6, normalizedEnd: 10, markdownStart: 6, markdownEnd: 10 },
        },
        body: "Clarify this word.",
      })
      .expect(201);

    expect(annotation.body.caseId).toBe(created.body.id);
    expect(annotation.body.issueId).toBeNull();
    expect(annotation.body.routineId).toBeNull();
    expect(annotation.body.comments[0].caseId).toBe(created.body.id);

    const listed = await http
      .get(`/api/life_admin/${created.body.identifier}/documents/body/annotations?status=all&includeComments=true`)
      .expect(200);
    expect(listed.body).toHaveLength(1);
    expect(listed.body[0].comments).toHaveLength(1);

    const reply = await http
      .post(`/api/life_admin/${created.body.id}/documents/body/annotations/${annotation.body.id}/comments`)
      .send({ body: "Added context." })
      .expect(201);
    expect(reply.body.caseId).toBe(created.body.id);

    const resolved = await http
      .patch(`/api/life_admin/${created.body.id}/documents/body/annotations/${annotation.body.id}`)
      .send({ status: "resolved" })
      .expect(200);
    expect(resolved.body.status).toBe("resolved");

    const reopened = await http
      .patch(`/api/life_admin/${created.body.id}/documents/body/annotations/${annotation.body.id}`)
      .send({ status: "open" })
      .expect(200);
    expect(reopened.body.status).toBe("open");

    const updatedDocument = await http
      .put(`/api/life_admin/${created.body.id}/documents/body`)
      .send({
        body: "Alpha beta gamma delta",
        baseRevisionId: document.body.revision.id,
      })
      .expect(200);
    const remapped = await http
      .get(`/api/life_admin/${created.body.id}/documents/body/annotations/${annotation.body.id}`)
      .expect(200);
    expect(remapped.body.currentRevisionNumber).toBe(updatedDocument.body.revision.revisionNumber);
    expect(remapped.body.comments).toHaveLength(2);

    const activities = await db
      .select({ action: activityLog.action, entityType: activityLog.entityType, entityId: activityLog.entityId })
      .from(activityLog)
      .where(eq(activityLog.entityId, created.body.id));
    expect(activities).toEqual(expect.arrayContaining([
      expect.objectContaining({ entityType: "case", action: "case.document_annotation_thread_created" }),
      expect.objectContaining({ entityType: "case", action: "case.document_annotation_comment_added" }),
      expect.objectContaining({ entityType: "case", action: "case.document_annotation_thread_resolved" }),
      expect.objectContaining({ entityType: "case", action: "case.document_annotation_thread_reopened" }),
      expect.objectContaining({ entityType: "case", action: "case.document_annotation_remapped" }),
    ]));
  });

  it("lists children by parent, exposes parent in detail, and lists life_admin for an issue", async () => {
    await enableLifeAdmin();
    const company = await seedDomain("TREE");
    const boardHttp = request(app(boardActor));
    const parent = await boardHttp
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "epic", title: "Parent epic" })
      .expect(201);
    const child = await boardHttp
      .post(`/api/domains/${company.id}/life_admin`)
      .send({ caseType: "task", title: "Child task", parentCaseId: parent.body.id })
      .expect(201);

    const children = await boardHttp
      .get(`/api/domains/${company.id}/life_admin`)
      .query({ parent: parent.body.id })
      .expect(200);
    expect(children.body).toHaveLength(1);
    expect(children.body[0].id).toBe(child.body.id);

    const searchOnly = await boardHttp
      .get(`/api/domains/${company.id}/life_admin`)
      .query({ q: "Child task" })
      .expect(200);
    expect(searchOnly.body.map((row: { id: string }) => row.id)).toEqual([child.body.id]);

    const searchWithAncestors = await boardHttp
      .get(`/api/domains/${company.id}/life_admin`)
      .query({ q: "Child task", includeAncestors: "true" })
      .expect(200);
    expect(searchWithAncestors.body).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: child.body.id, matchesListFilters: true }),
      expect.objectContaining({ id: parent.body.id, matchesListFilters: false }),
    ]));

    const childDetail = await boardHttp.get(`/api/life_admin/${child.body.id}`).expect(200);
    expect(childDetail.body.parent).toMatchObject({ id: parent.body.id, identifier: parent.body.identifier });

    // Link the child case to an issue, then resolve life_admin-for-issue.
    const [issue] = await db.insert(issues).values({
      companyId: company.id,
      title: "Issue with life_admin",
      status: "todo",
    }).returning();
    await boardHttp
      .post(`/api/life_admin/${child.body.id}/links`)
      .send({ issueId: issue!.id, role: "work" })
      .expect(201);

    const forIssue = await boardHttp.get(`/api/issues/${issue!.id}/life_admin`).expect(200);
    expect(forIssue.body).toHaveLength(1);
    expect(forIssue.body[0]).toMatchObject({ role: "work" });
    expect(forIssue.body[0].case).toMatchObject({ id: child.body.id, identifier: child.body.identifier, status: child.body.status });
  });
});

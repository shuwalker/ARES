import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockDomainService = vi.hoisted(() => ({
  list: vi.fn(),
  stats: vi.fn(),
  getById: vi.fn(),
  create: vi.fn(),
  update: vi.fn(),
  archive: vi.fn(),
  remove: vi.fn(),
}));

const mockAgentService = vi.hoisted(() => ({
  getById: vi.fn(),
}));

const mockAccessService = vi.hoisted(() => ({
  ensureMembership: vi.fn(),
}));

const mockBudgetService = vi.hoisted(() => ({
  upsertPolicy: vi.fn(),
}));

const mockDomainPortabilityService = vi.hoisted(() => ({
  exportBundle: vi.fn(),
  previewExport: vi.fn(),
  previewImport: vi.fn(),
  importBundle: vi.fn(),
}));

const mockDomainArtifactsService = vi.hoisted(() => ({
  list: vi.fn(),
}));

const mockLogActivity = vi.hoisted(() => vi.fn());
const mockFeedbackService = vi.hoisted(() => ({
  listIssueVotesForUser: vi.fn(),
  listFeedbackTraces: vi.fn(),
  getFeedbackTraceById: vi.fn(),
  saveIssueVote: vi.fn(),
}));

vi.mock("../services/access.js", () => ({
  accessService: () => mockAccessService,
}));

vi.mock("../services/activity-log.js", () => ({
  logActivity: mockLogActivity,
}));

vi.mock("../services/agents.js", () => ({
  agentService: () => mockAgentService,
}));

vi.mock("../services/budgets.js", () => ({
  budgetService: () => mockBudgetService,
}));

vi.mock("../services/domains.js", () => ({
  domainService: () => mockDomainService,
}));

vi.mock("../services/domain-portability.js", () => ({
  domainPortabilityService: () => mockDomainPortabilityService,
}));

vi.mock("../services/feedback.js", () => ({
  feedbackService: () => mockFeedbackService,
}));

vi.mock("../services/index.js", () => ({
  accessService: () => mockAccessService,
  agentService: () => mockAgentService,
  budgetService: () => mockBudgetService,
  domainArtifactsService: () => mockDomainArtifactsService,
  domainPortabilityService: () => mockDomainPortabilityService,
  domainService: () => mockDomainService,
  feedbackService: () => mockFeedbackService,
  logActivity: mockLogActivity,
}));

function registerDomainRouteMocks() {
  vi.doMock("../services/index.js", () => ({
    accessService: () => mockAccessService,
    agentService: () => mockAgentService,
    budgetService: () => mockBudgetService,
    domainArtifactsService: () => mockDomainArtifactsService,
    domainPortabilityService: () => mockDomainPortabilityService,
    domainService: () => mockDomainService,
    feedbackService: () => mockFeedbackService,
    logActivity: mockLogActivity,
  }));
}

let appImportCounter = 0;

async function createApp(actor: Record<string, unknown>) {
  registerDomainRouteMocks();
  appImportCounter += 1;
  const routeModulePath = `../routes/domains.js?domain-portability-routes-${appImportCounter}`;
  const middlewareModulePath = `../middleware/index.js?domain-portability-routes-${appImportCounter}`;
  const [{ domainRoutes }, { errorHandler }] = await Promise.all([
    import(routeModulePath) as Promise<typeof import("../routes/domains.js")>,
    import(middlewareModulePath) as Promise<typeof import("../middleware/index.js")>,
  ]);
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    (req as any).actor = actor;
    next();
  });
  app.use("/api/domains", domainRoutes({} as any));
  app.use(errorHandler);
  return app;
}

const domainId = "11111111-1111-4111-8111-111111111111";
const otherDomainId = "22222222-2222-4222-8222-222222222222";
const ceoAgentId = "ceo-agent";
const engineerAgentId = "engineer-agent";

const exportRequest = {
  include: { domain: true, agents: true, projects: true },
};

function createExportResult() {
  return {
    rootPath: "paperclip",
    manifest: {
      agents: [],
      skills: [],
      projects: [],
      issues: [],
      envInputs: [],
      includes: { domain: true, agents: true, projects: true, issues: false, skills: false },
      domain: null,
      schemaVersion: 1,
      generatedAt: "2026-01-01T00:00:00.000Z",
      source: null,
    },
    files: {},
    warnings: [],
  };
}

const importRequest = {
  source: { type: "inline", files: { "DOMAIN.md": "---\nname: Test\n---\n" } },
  include: { domain: true, agents: true, projects: false, issues: false },
  target: { mode: "existing_domain", domainId },
  collisionStrategy: "rename",
};

const cloudHeaders = {
  "x-paperclip-cloud-stack-id": "stack-alpha",
  "x-paperclip-cloud-paperclip-domain-id": domainId,
};

function cloudTenantActor() {
  return {
    type: "board",
    userId: "cloud-user-1",
    userName: "Cloud User",
    userEmail: "cloud-user@example.com",
    domainIds: [domainId],
    memberships: [{ domainId, membershipRole: "owner", status: "active" }],
    isInstanceAdmin: true,
    source: "cloud_tenant",
  };
}

function createImportResult(action = "updated") {
  return {
    domain: { id: domainId, action },
    agents: [{ id: "agent-1" }],
    warnings: [],
  };
}

async function waitForImportJobStatus(app: express.Express, statusUrl: string, status: string) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const res = await request(app).get(statusUrl).set(cloudHeaders);
    if (res.body.job?.status === status) {
      return res;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error(`Timed out waiting for import job to reach ${status}`);
}

async function waitForCondition(condition: () => boolean, label: string) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (condition()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error(`Timed out waiting for ${label}`);
}

describe.sequential("domain portability routes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockAgentService.getById.mockImplementation(async (id: string) => ({
      id,
      domainId,
      role: id === ceoAgentId ? "ceo" : "engineer",
    }));
    mockDomainPortabilityService.exportBundle.mockResolvedValue(createExportResult());
    mockDomainPortabilityService.previewExport.mockResolvedValue({
      rootPath: "paperclip",
      manifest: { agents: [], skills: [], projects: [], issues: [], envInputs: [], includes: { domain: true, agents: true, projects: true, issues: false, skills: false }, domain: null, schemaVersion: 1, generatedAt: new Date().toISOString(), source: null },
      files: {},
      fileInventory: [],
      counts: { files: 0, agents: 0, skills: 0, projects: 0, issues: 0 },
      warnings: [],
      paperclipExtensionPath: ".paperclip.yaml",
    });
    mockDomainPortabilityService.previewImport.mockResolvedValue({ ok: true });
    mockDomainPortabilityService.importBundle.mockResolvedValue({
      domain: { id: domainId, action: "created" },
      agents: [],
      warnings: [],
    });
  });

  it.sequential("rejects non-CEO agents from CEO-safe export preview routes", async () => {
    const app = await createApp({
      type: "agent",
      agentId: engineerAgentId,
      domainId,
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post(`/api/domains/${domainId}/exports/preview`)
      .send(exportRequest);

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Only CEO agents");
    expect(mockDomainPortabilityService.previewExport).not.toHaveBeenCalled();
  });

  it.sequential("rejects non-CEO export preview callers before validating request shape", async () => {
    const app = await createApp({
      type: "agent",
      agentId: engineerAgentId,
      domainId,
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post(`/api/domains/${domainId}/exports/preview`)
      .send({ agents: [123] });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Only CEO agents");
    expect(mockDomainPortabilityService.previewExport).not.toHaveBeenCalled();
  });

  it.sequential("rejects non-CEO agents from legacy and CEO-safe export bundle routes", async () => {
    const app = await createApp({
      type: "agent",
      agentId: engineerAgentId,
      domainId,
      source: "agent_key",
      runId: "run-1",
    });

    for (const path of [`/api/domains/${domainId}/export`, `/api/domains/${domainId}/exports`]) {
      const res = await request(app).post(path).send(exportRequest);

      expect(res.status).toBe(403);
      expect(res.body.error).toContain("Only CEO agents");
    }
    expect(mockDomainPortabilityService.exportBundle).not.toHaveBeenCalled();
  });

  it.sequential("allows CEO agents to use domain-scoped export preview routes", async () => {
    mockDomainPortabilityService.previewExport.mockResolvedValue({
      rootPath: "paperclip",
      manifest: { agents: [], skills: [], projects: [], issues: [], envInputs: [], includes: { domain: true, agents: true, projects: true, issues: false, skills: false }, domain: null, schemaVersion: 1, generatedAt: new Date().toISOString(), source: null },
      files: {},
      fileInventory: [],
      counts: { files: 0, agents: 0, skills: 0, projects: 0, issues: 0 },
      warnings: [],
      paperclipExtensionPath: ".paperclip.yaml",
    });
    const app = await createApp({
      type: "agent",
      agentId: ceoAgentId,
      domainId,
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post(`/api/domains/${domainId}/exports/preview`)
      .send(exportRequest);

    expect(res.status).toBe(200);
    expect(res.body.rootPath).toBe("paperclip");
  });

  it.sequential("allows CEO agents to export through legacy and CEO-safe bundle routes", async () => {
    mockDomainPortabilityService.exportBundle.mockResolvedValue(createExportResult());
    const app = await createApp({
      type: "agent",
      agentId: ceoAgentId,
      domainId,
      source: "agent_key",
      runId: "run-1",
    });

    for (const path of [`/api/domains/${domainId}/export`, `/api/domains/${domainId}/exports`]) {
      const res = await request(app).post(path).send(exportRequest);

      expect(res.status).toBe(200);
      expect(res.body.rootPath).toBe("paperclip");
    }
    expect(mockDomainPortabilityService.exportBundle).toHaveBeenCalledTimes(2);
    expect(mockDomainPortabilityService.exportBundle).toHaveBeenNthCalledWith(1, domainId, exportRequest);
    expect(mockDomainPortabilityService.exportBundle).toHaveBeenNthCalledWith(2, domainId, exportRequest);
  });

  it.sequential("allows board users to export through legacy and CEO-safe bundle routes", async () => {
    mockDomainPortabilityService.exportBundle.mockResolvedValue(createExportResult());
    const app = await createApp({
      type: "board",
      userId: "user-1",
      domainIds: [domainId],
      source: "session",
      isInstanceAdmin: false,
    });

    for (const path of [`/api/domains/${domainId}/export`, `/api/domains/${domainId}/exports`]) {
      const res = await request(app).post(path).send(exportRequest);

      expect(res.status).toBe(200);
      expect(res.body.rootPath).toBe("paperclip");
    }
    expect(mockDomainPortabilityService.exportBundle).toHaveBeenCalledTimes(2);
  });

  it.sequential("rejects CEO agents from exporting another domain before services run", async () => {
    const app = await createApp({
      type: "agent",
      agentId: ceoAgentId,
      domainId,
      source: "agent_key",
      runId: "run-1",
    });

    for (const path of [
      `/api/domains/${otherDomainId}/export`,
      `/api/domains/${otherDomainId}/exports`,
      `/api/domains/${otherDomainId}/exports/preview`,
    ]) {
      const res = await request(app).post(path).send(exportRequest);

      expect(res.status).toBe(403);
      expect(res.body.error).toContain("another domain");
    }
    expect(mockDomainPortabilityService.exportBundle).not.toHaveBeenCalled();
    expect(mockDomainPortabilityService.previewExport).not.toHaveBeenCalled();
    expect(mockLogActivity).not.toHaveBeenCalled();
  });

  it.sequential("rejects replace collision strategy on CEO-safe import routes", async () => {
    const app = await createApp({
      type: "agent",
      agentId: ceoAgentId,
      domainId: "11111111-1111-4111-8111-111111111111",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post("/api/domains/11111111-1111-4111-8111-111111111111/imports/preview")
      .send({
        source: { type: "inline", files: { "DOMAIN.md": "---\nname: Test\n---\n" } },
        include: { domain: true, agents: true, projects: false, issues: false },
        target: { mode: "existing_domain", domainId: "11111111-1111-4111-8111-111111111111" },
        collisionStrategy: "replace",
      });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("does not allow replace");
    expect(mockDomainPortabilityService.previewImport).not.toHaveBeenCalled();
  });

  it.sequential("rejects CEO agents from previewing or applying imports against another route domain", async () => {
    const app = await createApp({
      type: "agent",
      agentId: ceoAgentId,
      domainId,
      source: "agent_key",
      runId: "run-1",
    });

    for (const path of [
      `/api/domains/${otherDomainId}/imports/preview`,
      `/api/domains/${otherDomainId}/imports/apply`,
    ]) {
      const res = await request(app).post(path).send({
        ...importRequest,
        target: { mode: "existing_domain", domainId: otherDomainId },
      });

      expect(res.status).toBe(403);
      expect(res.body.error).toContain("another domain");
    }
    expect(mockDomainPortabilityService.previewImport).not.toHaveBeenCalled();
    expect(mockDomainPortabilityService.importBundle).not.toHaveBeenCalled();
    expect(mockLogActivity).not.toHaveBeenCalled();
  });

  it.sequential("rejects CEO-safe import bodies that target a different domain than the route", async () => {
    const app = await createApp({
      type: "agent",
      agentId: ceoAgentId,
      domainId,
      source: "agent_key",
      runId: "run-1",
    });

    for (const path of [
      `/api/domains/${domainId}/imports/preview`,
      `/api/domains/${domainId}/imports/apply`,
    ]) {
      const res = await request(app).post(path).send({
        ...importRequest,
        target: { mode: "existing_domain", domainId: otherDomainId },
      });

      expect(res.status).toBe(403);
      expect(res.body.error).toContain("only target the route domain");
    }
    expect(mockDomainPortabilityService.previewImport).not.toHaveBeenCalled();
    expect(mockDomainPortabilityService.importBundle).not.toHaveBeenCalled();
    expect(mockLogActivity).not.toHaveBeenCalled();
  });

  it.sequential("keeps global import preview routes board-only", async () => {
    const app = await createApp({
      type: "agent",
      agentId: engineerAgentId,
      domainId: "11111111-1111-4111-8111-111111111111",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post("/api/domains/import/preview")
      .send({
        source: { type: "inline", files: { "DOMAIN.md": "---\nname: Test\n---\n" } },
        include: { domain: true, agents: true, projects: false, issues: false },
        target: { mode: "existing_domain", domainId: "11111111-1111-4111-8111-111111111111" },
        collisionStrategy: "rename",
      });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Board access required");
  });

  it.sequential("keeps global import preview board-only before validating request shape", async () => {
    const app = await createApp({
      type: "agent",
      agentId: engineerAgentId,
      domainId: "11111111-1111-4111-8111-111111111111",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post("/api/domains/import/preview")
      .send({ target: { mode: "existing_domain", domainId: "not-a-uuid" } });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Board access required");
    expect(mockDomainPortabilityService.previewImport).not.toHaveBeenCalled();
  });

  it.sequential("requires instance admin for new-domain import preview", async () => {
    const app = await createApp({
      type: "board",
      userId: "user-1",
      domainIds: ["11111111-1111-4111-8111-111111111111"],
      source: "session",
      isInstanceAdmin: false,
    });

    const res = await request(app)
      .post("/api/domains/import/preview")
      .send({
        source: { type: "inline", files: { "DOMAIN.md": "---\nname: Test\n---\n" } },
        include: { domain: true, agents: true, projects: false, issues: false },
        target: { mode: "new_domain", newDomainName: "Imported Test" },
        collisionStrategy: "rename",
      });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Instance admin");
    expect(mockDomainPortabilityService.previewImport).not.toHaveBeenCalled();
  });

  it.sequential("rejects replace collision strategy on CEO-safe import apply routes", async () => {
    const app = await createApp({
      type: "agent",
      agentId: ceoAgentId,
      domainId: "11111111-1111-4111-8111-111111111111",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post("/api/domains/11111111-1111-4111-8111-111111111111/imports/apply")
      .send({
        source: { type: "inline", files: { "DOMAIN.md": "---\nname: Test\n---\n" } },
        include: { domain: true, agents: true, projects: false, issues: false },
        target: { mode: "existing_domain", domainId: "11111111-1111-4111-8111-111111111111" },
        collisionStrategy: "replace",
      });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("does not allow replace");
    expect(mockDomainPortabilityService.importBundle).not.toHaveBeenCalled();
  });

  it.sequential("rejects non-CEO agents from CEO-safe import preview routes", async () => {
    const app = await createApp({
      type: "agent",
      agentId: engineerAgentId,
      domainId: "11111111-1111-4111-8111-111111111111",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post("/api/domains/11111111-1111-4111-8111-111111111111/imports/preview")
      .send({
        source: { type: "inline", files: { "DOMAIN.md": "---\nname: Test\n---\n" } },
        include: { domain: true, agents: true, projects: false, issues: false },
        target: { mode: "existing_domain", domainId: "11111111-1111-4111-8111-111111111111" },
        collisionStrategy: "rename",
      });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Only CEO agents");
    expect(mockDomainPortabilityService.previewImport).not.toHaveBeenCalled();
  });

  it.sequential("rejects non-CEO import preview callers before validating request shape", async () => {
    const app = await createApp({
      type: "agent",
      agentId: engineerAgentId,
      domainId: "11111111-1111-4111-8111-111111111111",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post("/api/domains/11111111-1111-4111-8111-111111111111/imports/preview")
      .send({ target: { mode: "existing_domain", domainId: "not-a-uuid" } });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Only CEO agents");
    expect(mockDomainPortabilityService.previewImport).not.toHaveBeenCalled();
  });

  it.sequential("rejects non-CEO agents from CEO-safe import apply routes", async () => {
    const app = await createApp({
      type: "agent",
      agentId: engineerAgentId,
      domainId: "11111111-1111-4111-8111-111111111111",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .post("/api/domains/11111111-1111-4111-8111-111111111111/imports/apply")
      .send({
        source: { type: "inline", files: { "DOMAIN.md": "---\nname: Test\n---\n" } },
        include: { domain: true, agents: true, projects: false, issues: false },
        target: { mode: "existing_domain", domainId: "11111111-1111-4111-8111-111111111111" },
        collisionStrategy: "rename",
      });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Only CEO agents");
    expect(mockDomainPortabilityService.importBundle).not.toHaveBeenCalled();
  });

  it.sequential("requires instance admin for new-domain import apply", async () => {
    const app = await createApp({
      type: "board",
      userId: "user-1",
      domainIds: ["11111111-1111-4111-8111-111111111111"],
      source: "session",
      isInstanceAdmin: false,
    });

    const res = await request(app)
      .post("/api/domains/import")
      .send({
        source: { type: "inline", files: { "DOMAIN.md": "---\nname: Test\n---\n" } },
        include: { domain: true, agents: true, projects: false, issues: false },
        target: { mode: "new_domain", newDomainName: "Imported Test" },
        collisionStrategy: "rename",
      });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Instance admin");
    expect(mockDomainPortabilityService.importBundle).not.toHaveBeenCalled();
  });

  it.sequential("accepts trusted Cloud async import jobs and reports success by job id", async () => {
    let resolveImport: (value: ReturnType<typeof createImportResult>) => void = () => undefined;
    const pendingImport = new Promise<ReturnType<typeof createImportResult>>((resolve) => {
      resolveImport = resolve;
    });
    mockDomainPortabilityService.importBundle.mockReturnValueOnce(pendingImport);
    const app = await createApp(cloudTenantActor());

    const accepted = await request(app)
      .post("/api/domains/import")
      .set("x-paperclip-cloud-async-import", "1")
      .set(cloudHeaders)
      .send(importRequest);

    expect(accepted.status).toBe(202);
    expect(accepted.body.job.status).toBe("running");
    expect(accepted.body.statusUrl).toMatch(/^\/api\/domains\/import\/jobs\/tenant-import-/);
    expect(accepted.body.retryAfterMs).toBe(1000);
    await waitForCondition(() => mockDomainPortabilityService.importBundle.mock.calls.length === 1, "import job start");
    expect(mockDomainPortabilityService.importBundle).toHaveBeenCalledWith(importRequest, "cloud-user-1");
    expect(mockLogActivity).not.toHaveBeenCalled();

    resolveImport(createImportResult("updated"));
    const succeeded = await waitForImportJobStatus(app, accepted.body.statusUrl, "succeeded");

    expect(succeeded.status).toBe(200);
    expect(succeeded.body.job.status).toBe("succeeded");
    expect(succeeded.body.job.result.domainId).toBe(domainId);
    expect(succeeded.body.retryAfterMs).toBeUndefined();
    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      action: "domain.imported",
      domainId,
      details: expect.objectContaining({
        agentCount: 1,
        warningCount: 0,
        domainAction: "updated",
      }),
    }));

    const nowSpy = vi.spyOn(Date, "now").mockReturnValue(Date.parse(succeeded.body.job.completedAt) + (5 * 60 * 1000) + 1);
    try {
      const expired = await request(app).get(accepted.body.statusUrl).set(cloudHeaders);
      expect(expired.status).toBe(404);
      expect(expired.body.error).toBe("Import job not found");
    } finally {
      nowSpy.mockRestore();
    }
  });

  it.sequential("reports trusted Cloud async import job failures with the tenant error message", async () => {
    mockDomainPortabilityService.importBundle.mockRejectedValueOnce(new Error("tenant import exploded"));
    const app = await createApp(cloudTenantActor());

    const accepted = await request(app)
      .post("/api/domains/import")
      .set("x-paperclip-cloud-async-import", "1")
      .set(cloudHeaders)
      .send(importRequest);

    expect(accepted.status).toBe(202);
    const failed = await waitForImportJobStatus(app, accepted.body.statusUrl, "failed");

    expect(failed.status).toBe(200);
    expect(failed.body.job.status).toBe("failed");
    expect(failed.body.job.error.message).toBe("tenant import exploded");
    expect(failed.body.retryAfterMs).toBeUndefined();
    expect(failed.body.message).toBe("tenant import exploded");
    expect(mockLogActivity).not.toHaveBeenCalled();
  });

  it.sequential("accepts trusted Cloud async import jobs before validating the full import payload", async () => {
    const app = await createApp(cloudTenantActor());

    const accepted = await request(app)
      .post("/api/domains/import")
      .set("x-paperclip-cloud-async-import", "1")
      .set(cloudHeaders)
      .send({ target: { mode: "existing_domain", domainId } });

    expect(accepted.status).toBe(202);
    expect(accepted.body.job.status).toBe("running");
    expect(mockDomainPortabilityService.importBundle).not.toHaveBeenCalled();

    const failed = await waitForImportJobStatus(app, accepted.body.statusUrl, "failed");

    expect(failed.status).toBe(200);
    expect(failed.body.job.status).toBe("failed");
    expect(failed.body.job.error.message).toEqual(expect.any(String));
    expect(mockDomainPortabilityService.importBundle).not.toHaveBeenCalled();
    expect(mockLogActivity).not.toHaveBeenCalled();
  });

  it.sequential("keeps global import apply synchronous when Cloud async opt-in is absent", async () => {
    mockDomainPortabilityService.importBundle.mockResolvedValueOnce(createImportResult("created"));
    const app = await createApp(cloudTenantActor());

    const res = await request(app)
      .post("/api/domains/import")
      .set(cloudHeaders)
      .send(importRequest);

    expect(res.status).toBe(200);
    expect(res.body.domain.id).toBe(domainId);
    expect(res.body.domain.action).toBe("created");
    expect(res.body.job).toBeUndefined();
    expect(mockDomainPortabilityService.importBundle).toHaveBeenCalledWith(importRequest, "cloud-user-1");
    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      action: "domain.imported",
      domainId,
    }));
  });
});

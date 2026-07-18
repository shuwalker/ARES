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

function createDomain() {
  const now = new Date("2026-03-19T02:00:00.000Z");
  return {
    id: "domain-1",
    name: "Paperclip",
    description: null,
    status: "active",
    issuePrefix: "PAP",
    issueCounter: 568,
    budgetMonthlyCents: 0,
    spentMonthlyCents: 0,
    requireBoardApprovalForNewAgents: false,
    brandColor: "#123456",
    logoAssetId: "11111111-1111-4111-8111-111111111111",
    logoUrl: "/api/assets/11111111-1111-4111-8111-111111111111/content",
    createdAt: now,
    updatedAt: now,
  };
}

async function createApp(actor: Record<string, unknown>) {
  const [{ domainRoutes }, { errorHandler }] = await Promise.all([
    vi.importActual<typeof import("../routes/domains.js")>("../routes/domains.js"),
    vi.importActual<typeof import("../middleware/index.js")>("../middleware/index.js"),
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

describe("PATCH /api/domains/:domainId/branding", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.doUnmock("../routes/domains.js");
    vi.doUnmock("../routes/authz.js");
    vi.doUnmock("../middleware/index.js");
    vi.clearAllMocks();
  });

  it("rejects non-CEO agent callers", async () => {
    mockAgentService.getById.mockResolvedValue({
      id: "agent-1",
      domainId: "domain-1",
      role: "engineer",
    });
    const app = await createApp({
      type: "agent",
      agentId: "agent-1",
      domainId: "domain-1",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1/branding")
      .send({ logoAssetId: "11111111-1111-4111-8111-111111111111" });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Only CEO agents");
    expect(mockDomainService.update).not.toHaveBeenCalled();
  });

  it("rejects non-CEO agent callers before validating branding body shape", async () => {
    mockAgentService.getById.mockResolvedValue({
      id: "agent-1",
      domainId: "domain-1",
      role: "engineer",
    });
    const app = await createApp({
      type: "agent",
      agentId: "agent-1",
      domainId: "domain-1",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1/branding")
      .send({ status: "archived" });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Only CEO agents");
    expect(mockDomainService.update).not.toHaveBeenCalled();
  });

  it("allows CEO agent callers to update branding fields", async () => {
    const domain = createDomain();
    mockAgentService.getById.mockResolvedValue({
      id: "agent-1",
      domainId: "domain-1",
      role: "ceo",
    });
    mockDomainService.update.mockResolvedValue(domain);
    const app = await createApp({
      type: "agent",
      agentId: "agent-1",
      domainId: "domain-1",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1/branding")
      .send({
        logoAssetId: "11111111-1111-4111-8111-111111111111",
        brandColor: "#123456",
      });

    expect(res.status).toBe(200);
    expect(res.body.logoAssetId).toBe(domain.logoAssetId);
    expect(mockDomainService.update).toHaveBeenCalledWith("domain-1", {
      logoAssetId: "11111111-1111-4111-8111-111111111111",
      brandColor: "#123456",
    });
    expect(mockLogActivity).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        domainId: "domain-1",
        actorType: "agent",
        actorId: "agent-1",
        agentId: "agent-1",
        runId: "run-1",
        action: "domain.branding_updated",
        details: {
          logoAssetId: "11111111-1111-4111-8111-111111111111",
          brandColor: "#123456",
        },
      }),
    );
  });

  it("allows board callers to update branding fields", async () => {
    const domain = createDomain();
    mockDomainService.update.mockResolvedValue({
      ...domain,
      brandColor: null,
      logoAssetId: null,
      logoUrl: null,
    });
    const app = await createApp({
      type: "board",
      userId: "user-1",
      source: "local_implicit",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1/branding")
      .send({ brandColor: null, logoAssetId: null });

    expect(res.status).toBe(200);
    expect(res.body.brandColor ?? null).toBeNull();
    expect(res.body.logoAssetId ?? null).toBeNull();
  });

  it("rejects non-branding fields in the request body", async () => {
    const app = await createApp({
      type: "board",
      userId: "user-1",
      source: "local_implicit",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1/branding")
      .send({
        logoAssetId: "11111111-1111-4111-8111-111111111111",
        status: "archived",
      });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Validation error");
    expect(mockDomainService.update).not.toHaveBeenCalled();
  });
});

describe("PATCH /api/domains/:domainId", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.doUnmock("../routes/domains.js");
    vi.doUnmock("../routes/authz.js");
    vi.doUnmock("../middleware/index.js");
    vi.clearAllMocks();
  });

  it("rejects non-CEO agent callers before loading the domain or validating settings body shape", async () => {
    mockAgentService.getById.mockResolvedValue({
      id: "agent-1",
      domainId: "domain-1",
      role: "engineer",
    });
    const app = await createApp({
      type: "agent",
      agentId: "agent-1",
      domainId: "domain-1",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1")
      .send({ status: "archived" });

    expect(res.status).toBe(403);
    expect(res.body.error).toContain("Only CEO agents");
    expect(mockDomainService.getById).not.toHaveBeenCalled();
    expect(mockDomainService.update).not.toHaveBeenCalled();
  });

  it("allows CEO agent callers to update only branding fields through the general settings route", async () => {
    const domain = createDomain();
    mockAgentService.getById.mockResolvedValue({
      id: "agent-1",
      domainId: "domain-1",
      role: "ceo",
    });
    mockDomainService.getById.mockResolvedValue(domain);
    mockDomainService.update.mockResolvedValue({
      ...domain,
      name: "New Name",
    });
    const app = await createApp({
      type: "agent",
      agentId: "agent-1",
      domainId: "domain-1",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1")
      .send({ name: "New Name" });

    expect(res.status).toBe(200);
    expect(mockDomainService.update).toHaveBeenCalledWith("domain-1", { name: "New Name" }, expect.objectContaining({
      actorType: "agent",
      actorId: "agent-1",
    }));
  });

  it("rejects CEO agent attempts to update lifecycle, budget, consent, or prefix fields", async () => {
    const domain = createDomain();
    mockAgentService.getById.mockResolvedValue({
      id: "agent-1",
      domainId: "domain-1",
      role: "ceo",
    });
    mockDomainService.getById.mockResolvedValue(domain);
    const app = await createApp({
      type: "agent",
      agentId: "agent-1",
      domainId: "domain-1",
      source: "agent_key",
      runId: "run-1",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1")
      .send({
        status: "archived",
        budgetMonthlyCents: 1000,
        spentMonthlyCents: 500,
        requireBoardApprovalForNewAgents: true,
        feedbackDataSharingEnabled: true,
        issuePrefix: "BAD",
      });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Validation error");
    expect(mockDomainService.update).not.toHaveBeenCalled();
    expect(mockLogActivity).not.toHaveBeenCalled();
  });

  it("keeps full domain settings updates board-only", async () => {
    const domain = createDomain();
    mockDomainService.getById.mockResolvedValue(domain);
    mockDomainService.update.mockResolvedValue({
      ...domain,
      status: "paused",
    });
    const app = await createApp({
      type: "board",
      userId: "user-1",
      source: "local_implicit",
    });

    const res = await request(app)
      .patch("/api/domains/domain-1")
      .send({ status: "paused" });

    expect(res.status).toBe(200);
    expect(mockDomainService.update).toHaveBeenCalledWith("domain-1", { status: "paused" }, expect.objectContaining({
      actorType: "user",
      actorId: "user-1",
    }));
  });
});

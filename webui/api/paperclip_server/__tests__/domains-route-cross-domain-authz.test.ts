import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const domainAId = "11111111-1111-4111-8111-111111111111";
const domainBId = "22222222-2222-4222-8222-222222222222";
const ceoAgentId = "ceo-agent-a";

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
  ensureRoleDefaultGrants: vi.fn(),
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

const mockFeedbackService = vi.hoisted(() => ({
  listFeedbackTraces: vi.fn(),
}));

const mockLogActivity = vi.hoisted(() => vi.fn());

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
  const routeModulePath = `../routes/domains.js?cross-domain-authz-${appImportCounter}`;
  const middlewareModulePath = `../middleware/index.js?cross-domain-authz-${appImportCounter}`;
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

function createDomain(id: string) {
  const now = new Date("2026-06-18T00:00:00.000Z");
  return {
    id,
    name: id === domainAId ? "Domain A" : "Domain B",
    description: null,
    status: "active",
    issuePrefix: id === domainAId ? "CPA" : "CPB",
    issueCounter: 1,
    budgetMonthlyCents: 0,
    spentMonthlyCents: 0,
    requireBoardApprovalForNewAgents: false,
    feedbackDataSharingEnabled: false,
    brandColor: "#123456",
    logoAssetId: null,
    logoUrl: null,
    attachmentMaxBytes: 25_000_000,
    createdAt: now,
    updatedAt: now,
  };
}

const exportRequest = {
  include: { domain: true, agents: true, projects: true },
};

function exportResult() {
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
      generatedAt: "2026-06-18T00:00:00.000Z",
      source: null,
    },
    files: {},
    warnings: [],
  };
}

function exportPreviewResult() {
  return {
    ...exportResult(),
    fileInventory: [],
    counts: { files: 0, agents: 0, skills: 0, projects: 0, issues: 0 },
    paperclipExtensionPath: ".paperclip.yaml",
  };
}

function importRequest(targetDomainId = domainBId) {
  return {
    source: { type: "inline", files: { "DOMAIN.md": "---\nname: Imported\n---\n" } },
    include: { domain: true, agents: true, projects: false, issues: false },
    target: { mode: "existing_domain", domainId: targetDomainId },
    collisionStrategy: "rename",
  };
}

function importResult(domainId = domainBId) {
  return {
    domain: { id: domainId, action: "updated" },
    agents: [],
    warnings: [],
  };
}

function resetMockDefaults() {
  mockDomainService.getById.mockImplementation(async (id: string) => {
    if (id === domainAId || id === domainBId) return createDomain(id);
    return null;
  });
  mockDomainService.update.mockImplementation(async (id: string, body: Record<string, unknown>) => ({
    ...createDomain(id),
    ...body,
  }));
  mockDomainService.archive.mockImplementation(async (id: string) => ({
    ...createDomain(id),
    status: "archived",
  }));
  mockDomainService.remove.mockImplementation(async (id: string) => createDomain(id));
  mockAgentService.getById.mockImplementation(async (id: string) => {
    if (id === ceoAgentId) return { id, domainId: domainAId, role: "ceo" };
    return null;
  });
  mockDomainPortabilityService.exportBundle.mockResolvedValue(exportResult());
  mockDomainPortabilityService.previewExport.mockResolvedValue(exportPreviewResult());
  mockDomainPortabilityService.previewImport.mockResolvedValue({ ok: true });
  mockDomainPortabilityService.importBundle.mockResolvedValue(importResult());
}

function assertNoTargetMutationSideEffects() {
  expect(mockDomainService.update).not.toHaveBeenCalled();
  expect(mockDomainService.archive).not.toHaveBeenCalled();
  expect(mockDomainService.remove).not.toHaveBeenCalled();
  expect(mockDomainPortabilityService.exportBundle).not.toHaveBeenCalled();
  expect(mockDomainPortabilityService.previewExport).not.toHaveBeenCalled();
  expect(mockDomainPortabilityService.previewImport).not.toHaveBeenCalled();
  expect(mockDomainPortabilityService.importBundle).not.toHaveBeenCalled();
  expect(mockLogActivity).not.toHaveBeenCalled();
}

function domainACeoActor() {
  return {
    type: "agent",
    agentId: ceoAgentId,
    domainId: domainAId,
    source: "agent_key",
    runId: "run-1",
  };
}

function boardActor(input: {
  userId: string;
  domainIds?: string[];
  memberships?: Array<{ domainId: string; membershipRole: string; status: string }>;
  isInstanceAdmin?: boolean;
  source?: string;
}) {
  return {
    type: "board",
    userId: input.userId,
    source: input.source ?? "session",
    domainIds: input.domainIds ?? [],
    memberships: input.memberships ?? [],
    isInstanceAdmin: input.isInstanceAdmin ?? false,
  };
}

describe.sequential("domain route cross-domain authorization", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.doUnmock("../routes/authz.js");
    vi.doUnmock("../middleware/index.js");
    vi.clearAllMocks();
    resetMockDefaults();
  });

  it.each([
    {
      label: "GET /api/domains/:domainId",
      request: (app: express.Express) => request(app).get(`/api/domains/${domainBId}`),
    },
    {
      label: "PATCH /api/domains/:domainId",
      request: (app: express.Express) => request(app).patch(`/api/domains/${domainBId}`).send({ description: "Nope" }),
    },
    {
      label: "PATCH /api/domains/:domainId/branding",
      request: (app: express.Express) => request(app).patch(`/api/domains/${domainBId}/branding`).send({ brandColor: "#654321" }),
    },
    {
      label: "POST /api/domains/:domainId/archive",
      request: (app: express.Express) => request(app).post(`/api/domains/${domainBId}/archive`).send({}),
    },
    {
      label: "DELETE /api/domains/:domainId",
      request: (app: express.Express) => request(app).delete(`/api/domains/${domainBId}`),
    },
    {
      label: "POST /api/domains/:domainId/export",
      request: (app: express.Express) => request(app).post(`/api/domains/${domainBId}/export`).send(exportRequest),
    },
    {
      label: "POST /api/domains/:domainId/exports/preview",
      request: (app: express.Express) => request(app).post(`/api/domains/${domainBId}/exports/preview`).send(exportRequest),
    },
    {
      label: "POST /api/domains/:domainId/imports/preview",
      request: (app: express.Express) => request(app).post(`/api/domains/${domainBId}/imports/preview`).send(importRequest()),
    },
    {
      label: "POST /api/domains/:domainId/imports/apply",
      request: (app: express.Express) => request(app).post(`/api/domains/${domainBId}/imports/apply`).send(importRequest()),
    },
  ])("rejects a domain A CEO attempting domain B operation: $label", async ({ request: buildRequest }) => {
    const app = await createApp(domainACeoActor());

    const res = await buildRequest(app);

    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/another domain|access to this domain|active domain access/i);
    assertNoTargetMutationSideEffects();
  });

  it("allows a same-domain CEO to use CEO-safe domain routes without allowing board-only lifecycle routes", async () => {
    const app = await createApp(domainACeoActor());

    await request(app).get(`/api/domains/${domainAId}`).expect(200);
    await request(app).patch(`/api/domains/${domainAId}`).send({ brandColor: "#abcdef" }).expect(200);
    await request(app).patch(`/api/domains/${domainAId}/branding`).send({ brandColor: "#abcdef" }).expect(200);
    await request(app).post(`/api/domains/${domainAId}/export`).send(exportRequest).expect(200);
    await request(app).post(`/api/domains/${domainAId}/exports/preview`).send(exportRequest).expect(200);
    await request(app).post(`/api/domains/${domainAId}/imports/preview`).send(importRequest(domainAId)).expect(200);
    await request(app).post(`/api/domains/${domainAId}/imports/apply`).send(importRequest(domainAId)).expect(200);

    const archive = await request(app).post(`/api/domains/${domainAId}/archive`).send({});
    expect(archive.status).toBe(403);
    expect(archive.body.error).toContain("Board access required");
    const remove = await request(app).delete(`/api/domains/${domainAId}`);
    expect(remove.status).toBe(403);
    expect(remove.body.error).toContain("Board access required");
  });

  it("covers board actor access for non-member, viewer, active member, local trusted board, and instance admin without target membership", async () => {
    const nonMemberApp = await createApp(boardActor({ userId: "outsider" }));
    const nonMember = await request(nonMemberApp).get(`/api/domains/${domainBId}`);
    expect(nonMember.status).toBe(403);
    expect(nonMember.body.error).toContain("access to this domain");

    vi.clearAllMocks();
    resetMockDefaults();
    const viewerApp = await createApp(boardActor({
      userId: "viewer",
      domainIds: [domainBId],
      memberships: [{ domainId: domainBId, membershipRole: "viewer", status: "active" }],
    }));
    await request(viewerApp).get(`/api/domains/${domainBId}`).expect(200);
    const viewerWrite = await request(viewerApp).patch(`/api/domains/${domainBId}`).send({ description: "Nope" });
    expect(viewerWrite.status).toBe(403);
    expect(viewerWrite.body.error).toContain("Viewer access is read-only");
    expect(mockDomainService.update).not.toHaveBeenCalled();
    expect(mockLogActivity).not.toHaveBeenCalled();

    vi.clearAllMocks();
    resetMockDefaults();
    const memberApp = await createApp(boardActor({
      userId: "member",
      domainIds: [domainBId],
      memberships: [{ domainId: domainBId, membershipRole: "member", status: "active" }],
    }));
    await request(memberApp).patch(`/api/domains/${domainBId}`).send({ description: "Updated" }).expect(200);
    await request(memberApp).patch(`/api/domains/${domainBId}/branding`).send({ brandColor: "#abcdef" }).expect(200);
    await request(memberApp).post(`/api/domains/${domainBId}/archive`).send({}).expect(200);
    await request(memberApp).delete(`/api/domains/${domainBId}`).expect(200);
    await request(memberApp).post(`/api/domains/${domainBId}/export`).send(exportRequest).expect(200);
    await request(memberApp).post(`/api/domains/${domainBId}/exports/preview`).send(exportRequest).expect(200);
    await request(memberApp).post(`/api/domains/${domainBId}/imports/preview`).send(importRequest()).expect(200);
    await request(memberApp).post(`/api/domains/${domainBId}/imports/apply`).send(importRequest()).expect(200);

    vi.clearAllMocks();
    resetMockDefaults();
    const localTrustedApp = await createApp(boardActor({
      userId: "local-board",
      source: "local_implicit",
      isInstanceAdmin: true,
    }));
    await request(localTrustedApp).get(`/api/domains/${domainBId}`).expect(200);
    await request(localTrustedApp).patch(`/api/domains/${domainBId}`).send({ description: "Local" }).expect(200);

    vi.clearAllMocks();
    resetMockDefaults();
    const adminWithoutMembershipApp = await createApp(boardActor({
      userId: "instance-admin",
      isInstanceAdmin: true,
    }));
    const adminRead = await request(adminWithoutMembershipApp).get(`/api/domains/${domainBId}`);
    expect(adminRead.status).toBe(403);
    expect(adminRead.body.error).toContain("access to this domain");
    const adminWrite = await request(adminWithoutMembershipApp).patch(`/api/domains/${domainBId}`).send({ description: "Admin" });
    expect(adminWrite.status).toBe(403);
    expect(adminWrite.body.error).toContain("access to this domain");
    assertNoTargetMutationSideEffects();
  });
});

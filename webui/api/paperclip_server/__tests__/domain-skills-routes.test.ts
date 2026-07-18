import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockAgentService = vi.hoisted(() => ({
  getById: vi.fn(),
}));

const mockAccessService = vi.hoisted(() => ({
  canUser: vi.fn(),
  decide: vi.fn(),
  hasPermission: vi.fn(),
}));

const mockDomainSkillService = vi.hoisted(() => ({
  list: vi.fn(),
  categoryCounts: vi.fn(),
  detail: vi.fn(),
  listVersions: vi.fn(),
  getVersion: vi.fn(),
  createVersion: vi.fn(),
  starSkill: vi.fn(),
  unstarSkill: vi.fn(),
  forkSkill: vi.fn(),
  forkPrecheck: vi.fn(),
  listComments: vi.fn(),
  createComment: vi.fn(),
  updateComment: vi.fn(),
  deleteComment: vi.fn(),
  importFromSource: vi.fn(),
  installFromCatalog: vi.fn(),
  createLocalSkill: vi.fn(),
  updateSkill: vi.fn(),
  updateFile: vi.fn(),
  deleteFile: vi.fn(),
  scanProjectWorkspaces: vi.fn(),
  deleteSkill: vi.fn(),
  auditSkill: vi.fn(),
  getById: vi.fn(),
  installUpdate: vi.fn(),
  resetSkill: vi.fn(),
  listTestInputs: vi.fn(),
  createTestInput: vi.fn(),
  updateTestInput: vi.fn(),
  deleteTestInput: vi.fn(),
  listTestRunTemplates: vi.fn(),
  createTestRunTemplate: vi.fn(),
  updateTestRunTemplate: vi.fn(),
  deleteTestRunTemplate: vi.fn(),
  createTestRun: vi.fn(),
  listTestRuns: vi.fn(),
  getTestRunDetail: vi.fn(),
  cancelTestRun: vi.fn(),
  deleteTestRun: vi.fn(),
  pruneExpiredTestHarnessIssues: vi.fn(),
}));

const mockIssueService = vi.hoisted(() => ({
  create: vi.fn(),
  getById: vi.fn(),
  update: vi.fn(),
}));

const mockHeartbeatService = vi.hoisted(() => ({
  wakeup: vi.fn(),
  cancelRun: vi.fn(),
}));

const mockCatalogService = vi.hoisted(() => ({
  listCatalogSkillsOrEmpty: vi.fn(),
  getCatalogSkillOrThrow: vi.fn(),
  readCatalogSkillFile: vi.fn(),
}));

const mockLogActivity = vi.hoisted(() => vi.fn());
const mockTrackSkillImported = vi.hoisted(() => vi.fn());
const mockGetTelemetryClient = vi.hoisted(() => vi.fn());
const mockReflectionCoachMutationGate = vi.hoisted(() => ({
  assertConsented: vi.fn(),
}));

function allowSkillChangeDecision(reason = "allow_direct_change") {
  return {
    allowed: true,
    action: "skill_config:update",
    reason,
    explanation: "Allowed.",
    grant: {
      principalType: "agent",
      principalId: "agent-1",
      permissionKey: reason === "allow_consented_change" ? "skills:suggest-changes" : "skills:create",
      scope: null,
    },
  };
}

function denySkillChangeDecision(reason = "deny_no_grant", explanation = "Missing permission: skills:create or skills:suggest-changes.") {
  return {
    allowed: false,
    action: "skill_config:update",
    reason,
    explanation,
  };
}

function registerModuleMocks() {
  vi.doMock("../routes/authz.js", async () => vi.importActual("../routes/authz.js"));

  vi.doMock("@paperclipai/shared/telemetry", () => ({
    trackSkillImported: mockTrackSkillImported,
    trackErrorHandlerCrash: vi.fn(),
  }));

  vi.doMock("../telemetry.js", () => ({
    getTelemetryClient: mockGetTelemetryClient,
  }));

  vi.doMock("../services/access.js", () => ({
    accessService: () => mockAccessService,
  }));

  vi.doMock("../services/activity-log.js", () => ({
    logActivity: mockLogActivity,
  }));

  vi.doMock("../services/agents.js", () => ({
    agentService: () => mockAgentService,
  }));

  vi.doMock("../services/domain-skills.js", () => ({
    domainSkillService: () => mockDomainSkillService,
  }));

  vi.doMock("../services/skills-catalog.js", () => mockCatalogService);

  vi.doMock("../services/change-consent-gate.js", async () => {
    const actual = await vi.importActual<typeof import("../services/change-consent-gate.js")>(
      "../services/change-consent-gate.js",
    );
    return {
      ...actual,
      changeConsentGateService: () => mockReflectionCoachMutationGate,
    };
  });

  vi.doMock("../services/index.js", () => ({
    accessService: () => mockAccessService,
    agentService: () => mockAgentService,
    domainSkillService: () => mockDomainSkillService,
    issueService: () => mockIssueService,
    heartbeatService: () => mockHeartbeatService,
    logActivity: mockLogActivity,
  }));
}

async function createApp(actor: Record<string, unknown>) {
  const [{ domainSkillRoutes }, { errorHandler }] = await Promise.all([
    vi.importActual<typeof import("../routes/domain-skills.js")>("../routes/domain-skills.js"),
    vi.importActual<typeof import("../middleware/index.js")>("../middleware/index.js"),
  ]);
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    (req as any).actor = actor;
    next();
  });
  app.use("/api", domainSkillRoutes({} as any));
  app.use(errorHandler);
  return app;
}

describe("domain skill mutation permissions", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.doUnmock("@paperclipai/shared/telemetry");
    vi.doUnmock("../telemetry.js");
    vi.doUnmock("../services/access.js");
    vi.doUnmock("../services/activity-log.js");
    vi.doUnmock("../services/agents.js");
    vi.doUnmock("../services/domain-skills.js");
    vi.doUnmock("../services/skills-catalog.js");
    vi.doUnmock("../services/change-consent-gate.js");
    vi.doUnmock("../services/index.js");
    vi.doUnmock("../routes/domain-skills.js");
    vi.doUnmock("../routes/authz.js");
    vi.doUnmock("../middleware/index.js");
    registerModuleMocks();
    vi.clearAllMocks();
    mockGetTelemetryClient.mockReturnValue({ track: vi.fn() });
    mockDomainSkillService.importFromSource.mockResolvedValue({
      imported: [],
      warnings: [],
    });
    mockCatalogService.listCatalogSkillsOrEmpty.mockReturnValue([]);
    mockDomainSkillService.list.mockResolvedValue([]);
    mockDomainSkillService.categoryCounts.mockResolvedValue([]);
    mockDomainSkillService.detail.mockResolvedValue(null);
    mockDomainSkillService.listVersions.mockResolvedValue([]);
    mockDomainSkillService.getVersion.mockResolvedValue(null);
    mockDomainSkillService.createVersion.mockResolvedValue({
      id: "version-1",
      domainId: "domain-1",
      domainSkillId: "skill-1",
      revisionNumber: 1,
      label: "v1",
      fileInventory: [{ path: "SKILL.md", kind: "skill", content: "# Skill" }],
      authorAgentId: null,
      authorUserId: "board",
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
    });
    mockDomainSkillService.starSkill.mockResolvedValue({
      skillId: "skill-1",
      starred: true,
      starCount: 1,
    });
    mockDomainSkillService.unstarSkill.mockResolvedValue({
      skillId: "skill-1",
      starred: false,
      starCount: 0,
    });
    const forkedSkill = {
      id: "skill-fork",
      domainId: "domain-1",
      key: "domain/domain-1/review-fork",
      slug: "review-fork",
      name: "Review Fork",
      description: null,
      markdown: "# Review",
      sourceType: "local_path",
      sourceLocator: "/tmp/review-fork",
      sourceRef: null,
      trustLevel: "markdown_only",
      compatibility: "compatible",
      fileInventory: [{ path: "SKILL.md", kind: "skill" }],
      iconUrl: null,
      color: null,
      tagline: null,
      authorName: null,
      homepageUrl: null,
      categories: [],
      sharingScope: "domain",
      publicShareToken: null,
      forkedFromSkillId: "skill-1",
      forkedFromDomainId: "domain-1",
      starCount: 0,
      installCount: 1,
      forkCount: 0,
      currentVersionId: null,
      metadata: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:00:00.000Z"),
    };
    mockDomainSkillService.forkSkill.mockResolvedValue({
      skill: forkedSkill,
      original: {
        id: "skill-1",
        name: "Review",
        slug: "review",
        sourceType: "github",
        sourceLocator: "https://github.com/acme/review",
        sourceRef: "abc123",
      },
      reassignments: [],
    });
    mockDomainSkillService.forkPrecheck.mockResolvedValue({
      skillId: "skill-1",
      original: {
        id: "skill-1",
        name: "Review",
        slug: "review",
        sourceType: "github",
        sourceLocator: "https://github.com/acme/review",
        sourceRef: "abc123",
      },
      agentUsageCount: 0,
      usedByAgents: [],
      existingForks: [],
    });
    mockDomainSkillService.listComments.mockResolvedValue([]);
    mockDomainSkillService.createComment.mockResolvedValue({
      id: "comment-1",
      domainId: "domain-1",
      domainSkillId: "skill-1",
      parentCommentId: null,
      authorAgentId: null,
      authorUserId: "board",
      body: "Looks good",
      deletedAt: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:00:00.000Z"),
    });
    mockDomainSkillService.updateComment.mockResolvedValue({
      id: "comment-1",
      domainId: "domain-1",
      domainSkillId: "skill-1",
      parentCommentId: null,
      authorAgentId: null,
      authorUserId: "board",
      body: "Updated",
      deletedAt: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:00:00.000Z"),
    });
    mockDomainSkillService.deleteComment.mockResolvedValue({
      id: "comment-1",
      domainId: "domain-1",
      domainSkillId: "skill-1",
      parentCommentId: null,
      authorAgentId: null,
      authorUserId: "board",
      body: "Updated",
      deletedAt: new Date("2026-05-26T00:01:00.000Z"),
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:01:00.000Z"),
    });
    mockDomainSkillService.installFromCatalog.mockResolvedValue({
      action: "created",
      skill: {
        id: "skill-1",
        domainId: "domain-1",
        key: "paperclipai/bundled/software-development/review",
        slug: "review",
        name: "review",
        description: "Review code",
        markdown: "# Review",
        sourceType: "catalog",
        sourceLocator: "/tmp/review",
        sourceRef: "sha256:abc",
        trustLevel: "markdown_only",
        compatibility: "compatible",
        fileInventory: [{ path: "SKILL.md", kind: "skill" }],
        metadata: {
          sourceKind: "catalog",
          catalogId: "paperclipai:bundled:software-development:review",
          originHash: "sha256:abc",
        },
        createdAt: new Date("2026-05-26T00:00:00.000Z"),
        updatedAt: new Date("2026-05-26T00:00:00.000Z"),
      },
      catalogSkill: {
        id: "paperclipai:bundled:software-development:review",
        key: "paperclipai/bundled/software-development/review",
        kind: "bundled",
        category: "software-development",
        slug: "review",
        name: "review",
        description: "Review code",
        path: "catalog/bundled/software-development/review",
        entrypoint: "SKILL.md",
        trustLevel: "markdown_only",
        compatibility: "compatible",
        defaultInstall: false,
        recommendedForRoles: ["engineer"],
        requires: [],
        tags: ["review"],
        files: [{ path: "SKILL.md", kind: "skill", sizeBytes: 8, sha256: "abc" }],
        contentHash: "sha256:abc",
      },
      warnings: [],
    });
    mockDomainSkillService.createLocalSkill.mockResolvedValue({
      id: "skill-1",
      domainId: "domain-1",
      key: "domain/domain-1/review",
      slug: "review",
      name: "Review",
      description: null,
      markdown: "# Review",
      sourceType: "local_path",
      sourceLocator: "/tmp/review",
      sourceRef: null,
      trustLevel: "markdown_only",
      compatibility: "compatible",
      fileInventory: [{ path: "SKILL.md", kind: "skill" }],
      iconUrl: null,
      color: null,
      tagline: null,
      authorName: null,
      homepageUrl: null,
      categories: [],
      sharingScope: "domain",
      publicShareToken: null,
      forkedFromSkillId: null,
      forkedFromDomainId: null,
      starCount: 0,
      installCount: 1,
      forkCount: 0,
      currentVersionId: null,
      metadata: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:00:00.000Z"),
    });
    mockDomainSkillService.updateSkill.mockResolvedValue({
      id: "skill-1",
      slug: "review",
      categories: ["memory", "review"],
      sharingScope: "domain",
    });
    mockDomainSkillService.updateFile.mockResolvedValue({
      skillId: "skill-1",
      path: "SKILL.md",
      kind: "skill",
      content: "# Review",
      language: "markdown",
      markdown: true,
      editable: true,
    });
    mockDomainSkillService.deleteFile.mockResolvedValue({
      skillId: "skill-1",
      path: "references",
      target: "folder",
      deletedPaths: ["references/example.md"],
    });
    mockDomainSkillService.scanProjectWorkspaces.mockResolvedValue({
      scannedProjects: 0,
      scannedWorkspaces: 0,
      discovered: 0,
      imported: [],
      updated: [],
      skipped: [],
      conflicts: [],
      warnings: [],
    });
    mockDomainSkillService.deleteSkill.mockResolvedValue({
      id: "skill-1",
      slug: "find-skills",
      name: "Find Skills",
    });
    mockDomainSkillService.auditSkill.mockResolvedValue({
      skillId: "skill-1",
      installedHash: "sha256:abc",
      originHash: "sha256:abc",
      verdict: "pass",
      codes: [],
      findings: [],
      scannedAt: "2026-05-26T00:00:00.000Z",
      scanVersion: "1",
    });
    mockDomainSkillService.getById.mockResolvedValue({
      id: "skill-1",
      slug: "review",
      sourceRef: "sha256:abc",
      metadata: { originHash: "sha256:abc" },
    });
    mockDomainSkillService.installUpdate.mockResolvedValue({
      id: "skill-1",
      slug: "review",
      sourceRef: "sha256:def",
      metadata: { originHash: "sha256:def" },
    });
    mockDomainSkillService.resetSkill.mockResolvedValue({
      id: "skill-1",
      slug: "review",
      sourceRef: "sha256:def",
      metadata: { originHash: "sha256:def" },
    });
    mockDomainSkillService.pruneExpiredTestHarnessIssues.mockResolvedValue({ pruned: 0 });
    mockDomainSkillService.listTestInputs.mockResolvedValue([]);
    mockDomainSkillService.createTestInput.mockResolvedValue({
      id: "11111111-1111-4111-8111-111111111111",
      domainId: "domain-1",
      skillId: "skill-1",
      name: "smoke/input",
      content: "Try the skill",
      createdBy: "board",
      deletedAt: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:00:00.000Z"),
    });
    mockDomainSkillService.updateTestInput.mockResolvedValue({
      id: "11111111-1111-4111-8111-111111111111",
      domainId: "domain-1",
      skillId: "skill-1",
      name: "smoke/renamed",
      content: "Try the skill again",
      createdBy: "board",
      deletedAt: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:01:00.000Z"),
    });
    mockDomainSkillService.deleteTestInput.mockResolvedValue({
      id: "11111111-1111-4111-8111-111111111111",
      domainId: "domain-1",
      skillId: "skill-1",
      name: "smoke/renamed",
      content: "Try the skill again",
      createdBy: "board",
      deletedAt: new Date("2026-05-26T00:02:00.000Z"),
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:02:00.000Z"),
    });
    const templateResponse = {
      id: "66666666-6666-4666-8666-666666666666",
      domainId: "domain-1",
      name: "Custom template",
      description: "Custom run guidance",
      body: "Run {{skillName}} into {{outputDocumentKey}}.",
      builtIn: false,
      createdByAgentId: null,
      createdByUserId: "local-board",
      updatedByAgentId: null,
      updatedByUserId: "local-board",
      deletedAt: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:00:00.000Z"),
    };
    mockDomainSkillService.listTestRunTemplates.mockResolvedValue([{
      ...templateResponse,
      id: "built-in:default-test-template",
      name: "Default test template",
      description: "Paperclip default",
      body: "Default {{skillName}}",
      builtIn: true,
      createdByUserId: null,
      updatedByUserId: null,
    }, templateResponse]);
    mockDomainSkillService.createTestRunTemplate.mockResolvedValue(templateResponse);
    mockDomainSkillService.updateTestRunTemplate.mockResolvedValue({
      ...templateResponse,
      name: "Renamed template",
      updatedAt: new Date("2026-05-26T00:01:00.000Z"),
    });
    mockDomainSkillService.deleteTestRunTemplate.mockResolvedValue({
      ...templateResponse,
      deletedAt: new Date("2026-05-26T00:02:00.000Z"),
      updatedAt: new Date("2026-05-26T00:02:00.000Z"),
    });
    mockDomainSkillService.listTestRuns.mockResolvedValue([]);
    mockDomainSkillService.getTestRunDetail.mockResolvedValue(null);
    mockDomainSkillService.createTestRun.mockResolvedValue({
      id: "22222222-2222-4222-8222-222222222222",
      domainId: "domain-1",
      skillId: "skill-1",
      inputId: "11111111-1111-4111-8111-111111111111",
      inputSnapshot: "Try the skill",
      skillVersionId: "33333333-3333-4333-8333-333333333333",
      agentId: "55555555-5555-4555-8555-555555555555",
      agentConfigSnapshot: { adapterType: "codex_local" },
      issueId: "44444444-4444-4444-8444-444444444444",
      templateId: "built-in:default-test-template",
      templateName: "Default test template",
      templateBody: "Default {{skillName}}",
      renderedTemplateBody: "Default Review",
      harnessIssueDescription: "Try the skill\n\n---\n\nDefault Review",
      status: "queued",
      outputDocumentKey: "output",
      outputSnapshot: "",
      error: null,
      deletedAt: null,
      supersededAt: null,
      harnessIssueExpiresAt: null,
      harnessIssueDeletedAt: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:00:00.000Z"),
      finance: { financeCents: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
      taskExpired: false,
    });
    mockDomainSkillService.cancelTestRun.mockResolvedValue({
      id: "22222222-2222-4222-8222-222222222222",
      domainId: "domain-1",
      skillId: "skill-1",
      inputId: "11111111-1111-4111-8111-111111111111",
      inputSnapshot: "Try the skill",
      skillVersionId: "33333333-3333-4333-8333-333333333333",
      agentId: "55555555-5555-4555-8555-555555555555",
      agentConfigSnapshot: { adapterType: "codex_local" },
      issueId: "44444444-4444-4444-8444-444444444444",
      templateId: "built-in:default-test-template",
      templateName: "Default test template",
      templateBody: "Default {{skillName}}",
      renderedTemplateBody: "Default Review",
      harnessIssueDescription: "Try the skill\n\n---\n\nDefault Review",
      status: "cancelled",
      outputDocumentKey: "output",
      outputSnapshot: "",
      error: "Cancelled by operator",
      deletedAt: null,
      supersededAt: null,
      harnessIssueExpiresAt: null,
      harnessIssueDeletedAt: null,
      createdAt: new Date("2026-05-26T00:00:00.000Z"),
      updatedAt: new Date("2026-05-26T00:01:00.000Z"),
      finance: { financeCents: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
      taskExpired: false,
    });
    mockIssueService.create.mockResolvedValue({
      id: "44444444-4444-4444-8444-444444444444",
      domainId: "domain-1",
      identifier: "PAP-999",
      title: "Skill test: Review",
    });
    mockIssueService.getById.mockResolvedValue({
      id: "44444444-4444-4444-8444-444444444444",
      domainId: "domain-1",
      status: "in_progress",
      executionRunId: "run-1",
    });
    mockIssueService.update.mockResolvedValue({});
    mockHeartbeatService.wakeup.mockResolvedValue({});
    mockHeartbeatService.cancelRun.mockResolvedValue({});
    mockCatalogService.listCatalogSkillsOrEmpty.mockReturnValue([]);
    mockCatalogService.getCatalogSkillOrThrow.mockReturnValue({
      id: "paperclipai:bundled:software-development:review",
      key: "paperclipai/bundled/software-development/review",
      kind: "bundled",
      category: "software-development",
      slug: "review",
      name: "review",
      description: "Review code",
      path: "catalog/bundled/software-development/review",
      entrypoint: "SKILL.md",
      trustLevel: "markdown_only",
      compatibility: "compatible",
      defaultInstall: false,
      recommendedForRoles: ["engineer"],
      requires: [],
      tags: ["review"],
      files: [{ path: "SKILL.md", kind: "skill", sizeBytes: 8, sha256: "abc" }],
      contentHash: "sha256:abc",
    });
    mockCatalogService.readCatalogSkillFile.mockResolvedValue({
      catalogSkillId: "paperclipai:bundled:software-development:review",
      path: "SKILL.md",
      kind: "skill",
      content: "# Review",
      language: "markdown",
      markdown: true,
    });
    mockLogActivity.mockResolvedValue(undefined);
    mockAccessService.canUser.mockResolvedValue(true);
    mockAccessService.decide.mockResolvedValue(allowSkillChangeDecision());
    mockAccessService.hasPermission.mockResolvedValue(false);
    mockReflectionCoachMutationGate.assertConsented.mockResolvedValue(undefined);
  });

  it("allows local board operators to mutate domain skills", async () => {
    const res = await request(await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" });

    expect([200, 201], JSON.stringify(res.body)).toContain(res.status);
    expect(res.body).toEqual({
      imported: [],
      warnings: [],
    });
  });

  it("allows board users with skills:create to create, import, install, update, delete, audit, and reset domain skills", async () => {
    const app = await createApp({
      type: "board",
      userId: "board-user",
      domainIds: ["domain-1"],
      source: "session",
      isInstanceAdmin: false,
    });

    await request(app)
      .post("/api/domains/domain-1/skills")
      .send({ name: "Review", slug: "review", markdown: "# Review" })
      .expect(201);
    await request(app)
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" })
      .expect(201);
    await request(app)
      .post("/api/domains/domain-1/skills/install-catalog")
      .send({ catalogSkillId: "paperclipai:bundled:software-development:review" })
      .expect(201);
    await request(app)
      .patch("/api/domains/domain-1/skills/skill-1")
      .send({ description: "Updated" })
      .expect(200);
    await request(app)
      .delete("/api/domains/domain-1/skills/skill-1")
      .expect(200);
    await request(app)
      .post("/api/domains/domain-1/skills/skill-1/audit")
      .send({})
      .expect(200);
    await request(app)
      .post("/api/domains/domain-1/skills/skill-1/reset")
      .send({})
      .expect(200);

    expect(mockAccessService.decide).toHaveBeenCalledWith(expect.objectContaining({
      action: "skill_config:update",
      resource: { type: "domain", domainId: "domain-1" },
    }));
    expect(mockAccessService.canUser).not.toHaveBeenCalledWith("domain-1", "board-user", "agents:create");
    expect(mockDomainSkillService.createLocalSkill).toHaveBeenCalled();
    expect(mockDomainSkillService.importFromSource).toHaveBeenCalled();
    expect(mockDomainSkillService.installFromCatalog).toHaveBeenCalled();
    expect(mockDomainSkillService.updateSkill).toHaveBeenCalled();
    expect(mockDomainSkillService.deleteSkill).toHaveBeenCalled();
    expect(mockDomainSkillService.auditSkill).toHaveBeenCalled();
    expect(mockDomainSkillService.resetSkill).toHaveBeenCalled();
  });

  it("blocks board users without skills:create from mutating domain skills", async () => {
    mockAccessService.decide.mockResolvedValue(denySkillChangeDecision());

    const res = await request(await createApp({
      type: "board",
      userId: "board-user",
      domainIds: ["domain-1"],
      source: "session",
      isInstanceAdmin: false,
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" });

    expect(res.status, JSON.stringify(res.body)).toBe(403);
    expect(res.body.error).toBe("Missing permission: skills:create or skills:suggest-changes.");
    expect(mockAccessService.decide).toHaveBeenCalledWith(expect.objectContaining({
      action: "skill_config:update",
      resource: { type: "domain", domainId: "domain-1" },
    }));
    expect(mockAccessService.canUser).not.toHaveBeenCalledWith("domain-1", "board-user", "agents:create");
    expect(mockDomainSkillService.importFromSource).not.toHaveBeenCalled();
  });

  it("serves catalog listing without mutating domain skills", async () => {
    mockCatalogService.listCatalogSkillsOrEmpty.mockReturnValue([
      {
        id: "paperclipai:bundled:software-development:review",
        key: "paperclipai/bundled/software-development/review",
        kind: "bundled",
        category: "software-development",
        slug: "review",
        name: "review",
        description: "Review code",
        path: "catalog/bundled/software-development/review",
        entrypoint: "SKILL.md",
        trustLevel: "markdown_only",
        compatibility: "compatible",
        defaultInstall: false,
        recommendedForRoles: ["engineer"],
        requires: [],
        tags: ["review"],
        files: [{ path: "SKILL.md", kind: "skill", sizeBytes: 8, sha256: "abc" }],
        contentHash: "sha256:abc",
      },
    ]);

    const res = await request(await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    }))
      .get("/api/skills/catalog?kind=bundled&q=review");

    expect(res.status, JSON.stringify(res.body)).toBe(200);
    expect(mockCatalogService.listCatalogSkillsOrEmpty).toHaveBeenCalledWith({ kind: "bundled", q: "review" });
    expect(mockDomainSkillService.importFromSource).not.toHaveBeenCalled();
    expect(mockDomainSkillService.installFromCatalog).not.toHaveBeenCalled();
    expect(mockLogActivity).not.toHaveBeenCalled();
  });

  it("requires authentication for catalog read routes", async () => {
    const app = await createApp({ type: "none" });

    const list = await request(app).get("/api/skills/catalog");
    const detail = await request(app).get("/api/skills/catalog/review");
    const file = await request(app).get("/api/skills/catalog/review/files?path=SKILL.md");

    expect(list.status, JSON.stringify(list.body)).toBe(401);
    expect(detail.status, JSON.stringify(detail.body)).toBe(401);
    expect(file.status, JSON.stringify(file.body)).toBe(401);
    expect(mockCatalogService.listCatalogSkillsOrEmpty).not.toHaveBeenCalled();
    expect(mockCatalogService.getCatalogSkillOrThrow).not.toHaveBeenCalled();
    expect(mockCatalogService.readCatalogSkillFile).not.toHaveBeenCalled();
  });

  it("serves catalog detail and files by catalog reference", async () => {
    const app = await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    });

    const detail = await request(app)
      .get("/api/skills/catalog/review");
    const file = await request(app)
      .get("/api/skills/catalog/review/files?path=SKILL.md");

    expect(detail.status, JSON.stringify(detail.body)).toBe(200);
    expect(file.status, JSON.stringify(file.body)).toBe(200);
    expect(mockCatalogService.getCatalogSkillOrThrow).toHaveBeenCalledWith("review");
    expect(mockCatalogService.readCatalogSkillFile).toHaveBeenCalledWith("review", "SKILL.md");
    expect(mockLogActivity).not.toHaveBeenCalled();
  });

  it("installs catalog skills with mutation permissions and logs provenance", async () => {
    const res = await request(await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    }))
      .post("/api/domains/domain-1/skills/install-catalog")
      .send({
        catalogSkillId: "paperclipai:bundled:software-development:review",
        slug: "review",
      });

    expect(res.status, JSON.stringify(res.body)).toBe(201);
    expect(mockDomainSkillService.installFromCatalog).toHaveBeenCalledWith("domain-1", {
      catalogSkillId: "paperclipai:bundled:software-development:review",
      slug: "review",
    });
    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      domainId: "domain-1",
      action: "domain.skill_catalog_installed",
      entityType: "domain_skill",
      entityId: "skill-1",
      details: expect.objectContaining({
        catalogId: "paperclipai:bundled:software-development:review",
        catalogKey: "paperclipai/bundled/software-development/review",
        originHash: "sha256:abc",
      }),
    }));
  });

  it("tracks public GitHub skill imports with an explicit skill reference", async () => {
    mockDomainSkillService.importFromSource.mockResolvedValue({
      imported: [
        {
          id: "skill-1",
          domainId: "domain-1",
          key: "vercel-labs/agent-browser/find-skills",
          slug: "find-skills",
          name: "Find Skills",
          description: null,
          markdown: "# Find Skills",
          sourceType: "github",
          sourceLocator: "https://github.com/vercel-labs/agent-browser",
          sourceRef: null,
          trustLevel: "markdown_only",
          compatibility: "compatible",
          fileInventory: [],
          metadata: {
            hostname: "github.com",
            owner: "vercel-labs",
            repo: "agent-browser",
          },
          createdAt: new Date(),
          updatedAt: new Date(),
        },
      ],
      warnings: [],
    });

    const res = await request(await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" });

    expect([200, 201], JSON.stringify(res.body)).toContain(res.status);
    expect(mockTrackSkillImported).toHaveBeenCalledWith(expect.anything(), {
      sourceType: "github",
      skillRef: "vercel-labs/agent-browser/find-skills",
    });
  });

  it("does not expose a skill reference for non-public skill imports", async () => {
    mockDomainSkillService.importFromSource.mockResolvedValue({
      imported: [
        {
          id: "skill-1",
          domainId: "domain-1",
          key: "private-skill",
          slug: "private-skill",
          name: "Private Skill",
          description: null,
          markdown: "# Private Skill",
          sourceType: "github",
          sourceLocator: "https://ghe.example.com/acme/private-skill",
          sourceRef: null,
          trustLevel: "markdown_only",
          compatibility: "compatible",
          fileInventory: [],
          metadata: {
            hostname: "ghe.example.com",
            owner: "acme",
            repo: "private-skill",
          },
          createdAt: new Date(),
          updatedAt: new Date(),
        },
      ],
      warnings: [],
    });

    const res = await request(await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://ghe.example.com/acme/private-skill" });

    expect([200, 201], JSON.stringify(res.body)).toContain(res.status);
    expect(mockTrackSkillImported).toHaveBeenCalledWith(expect.anything(), {
      sourceType: "github",
      skillRef: null,
    });
  });

  it("does not expose a skill reference when GitHub metadata is missing", async () => {
    mockDomainSkillService.importFromSource.mockResolvedValue({
      imported: [
        {
          id: "skill-1",
          domainId: "domain-1",
          key: "unknown/private-skill",
          slug: "private-skill",
          name: "Private Skill",
          description: null,
          markdown: "# Private Skill",
          sourceType: "github",
          sourceLocator: "https://github.com/acme/private-skill",
          sourceRef: null,
          trustLevel: "markdown_only",
          compatibility: "compatible",
          fileInventory: [],
          metadata: null,
          createdAt: new Date(),
          updatedAt: new Date(),
        },
      ],
      warnings: [],
    });

    const res = await request(await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/acme/private-skill" });

    expect([200, 201], JSON.stringify(res.body)).toContain(res.status);
    expect(mockTrackSkillImported).toHaveBeenCalledWith(expect.anything(), {
      sourceType: "github",
      skillRef: null,
    });
  });

  it("blocks same-domain agents without skill change grants from mutating domain skills", async () => {
    mockAccessService.decide.mockResolvedValue(denySkillChangeDecision());
    mockAgentService.getById.mockResolvedValue({
      id: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      permissions: { canCreateSkills: false },
    });

    const res = await request(await createApp({
      type: "agent",
      agentId: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      runId: "run-1",
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" });

    expect(res.status, JSON.stringify(res.body)).toBe(403);
    expect(res.body.error).toBe("Missing permission: skills:create or skills:suggest-changes.");
    expect(mockAccessService.decide).toHaveBeenCalledWith(expect.objectContaining({
      action: "skill_config:update",
      resource: { type: "domain", domainId: "domain-1" },
    }));
    expect(mockAccessService.hasPermission).not.toHaveBeenCalledWith("domain-1", "agent", "55555555-5555-4555-8555-555555555555", "agents:create");
    expect(mockDomainSkillService.importFromSource).not.toHaveBeenCalled();
  });

  it("blocks agent catalog installs for other domains", async () => {
    mockAgentService.getById.mockResolvedValue({
      id: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      permissions: { canCreateSkills: true },
    });

    const res = await request(await createApp({
      type: "agent",
      agentId: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      runId: "run-1",
    }))
      .post("/api/domains/domain-2/skills/install-catalog")
      .send({ catalogSkillId: "paperclipai:bundled:software-development:review" });

    expect(res.status, JSON.stringify(res.body)).toBe(403);
    expect(mockDomainSkillService.installFromCatalog).not.toHaveBeenCalled();
  });

  it("passes store list filters and category count requests to the service", async () => {
    const app = await createApp({ type: "board", source: "local_implicit" });

    await request(app)
      .get("/api/domains/domain-1/skills?sort=stars&categories[]=memory&category=git&scope=domain&q=review&include=lastEditor")
      .expect(200);
    expect(mockDomainSkillService.list).toHaveBeenCalledWith("domain-1", {
      q: "review",
      sort: "stars",
      categories: ["git", "memory"],
      scope: "domain",
      include: ["lastEditor"],
    });

    await request(app).get("/api/domains/domain-1/skills/categories").expect(200);
    expect(mockDomainSkillService.categoryCounts).toHaveBeenCalledWith("domain-1");
  });

  it("accepts category updates and logs the skill mutation", async () => {
    const app = await createApp({ type: "board", source: "local_implicit", userId: "user-1" });

    const res = await request(app)
      .patch("/api/domains/domain-1/skills/skill-1")
      .send({ categories: ["memory", "review"], sharingScope: "domain" })
      .expect(200);

    expect(res.body).toMatchObject({
      id: "skill-1",
      categories: ["memory", "review"],
      sharingScope: "domain",
    });
    expect(mockDomainSkillService.updateSkill).toHaveBeenCalledWith("domain-1", "skill-1", {
      categories: ["memory", "review"],
      sharingScope: "domain",
    });
    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      domainId: "domain-1",
      actorType: "user",
      actorId: "user-1",
      action: "domain.skill_updated",
      entityType: "domain_skill",
      entityId: "skill-1",
      details: {
        slug: "review",
        categories: ["memory", "review"],
        sharingScope: "domain",
      },
    }));
  });

  it("creates skill versions and logs the mutation", async () => {
    const app = await createApp({ type: "board", source: "local_implicit", userId: "user-1" });

    await request(app)
      .post("/api/domains/domain-1/skills/skill-1/versions")
      .send({ label: "v1" })
      .expect(201);

    expect(mockDomainSkillService.createVersion).toHaveBeenCalledWith("domain-1", "skill-1", { label: "v1" }, {
      type: "user",
      userId: "user-1",
    });
    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      action: "domain.skill_version_created",
      entityType: "domain_skill_version",
      entityId: "version-1",
    }));
  });

  it("deletes skill files and logs the mutation", async () => {
    const app = await createApp({ type: "board", source: "local_implicit", userId: "user-1" });

    const res = await request(app)
      .delete("/api/domains/domain-1/skills/skill-1/files")
      .send({ path: "references", target: "folder" });

    expect(res.status, JSON.stringify(res.body)).toBe(200);

    expect(mockDomainSkillService.deleteFile).toHaveBeenCalledWith("domain-1", "skill-1", {
      path: "references",
      target: "folder",
    }, {
      type: "user",
      userId: "user-1",
    });
    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      action: "domain.skill_file_deleted",
      entityType: "domain_skill",
      entityId: "skill-1",
      details: {
        path: "references",
        target: "folder",
        deletedPaths: ["references/example.md"],
      },
    }));
  });

  it("stars, forks, and comments on skills through domain-scoped endpoints", async () => {
    const app = await createApp({ type: "board", source: "local_implicit", userId: "user-1" });

    await request(app).post("/api/domains/domain-1/skills/skill-1/star").send({}).expect(200);
    expect(mockDomainSkillService.starSkill).toHaveBeenCalledWith("domain-1", "skill-1", {
      type: "user",
      userId: "user-1",
    });

    const forkRes = await request(app)
      .post("/api/domains/domain-1/skills/skill-1/fork")
      .send({ slug: "review-fork", reassignAgentIds: ["11111111-1111-4111-8111-111111111111"] })
      .expect(201);
    expect(forkRes.body).toMatchObject({
      skill: { id: "skill-fork", slug: "review-fork" },
      original: { id: "skill-1", slug: "review" },
      reassignments: [],
    });
    expect(mockDomainSkillService.forkSkill).toHaveBeenCalledWith(
      "domain-1",
      "skill-1",
      { slug: "review-fork", reassignAgentIds: ["11111111-1111-4111-8111-111111111111"] },
      {
        type: "user",
        userId: "user-1",
      },
    );

    await request(app).get("/api/domains/domain-1/skills/skill-1/fork-precheck").expect(200);
    expect(mockDomainSkillService.forkPrecheck).toHaveBeenCalledWith("domain-1", "skill-1", {
      type: "user",
      userId: "user-1",
    });

    await request(app).post("/api/domains/domain-1/skills/skill-1/comments").send({ body: "Looks good" }).expect(201);
    expect(mockDomainSkillService.createComment).toHaveBeenCalledWith("domain-1", "skill-1", { body: "Looks good" }, {
      type: "user",
      userId: "user-1",
    });

    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      action: "domain.skill_starred",
      entityId: "skill-1",
    }));
    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      action: "domain.skill_forked",
      entityId: "skill-fork",
    }));
    expect(mockLogActivity).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      action: "domain.skill_comment_created",
      entityId: "comment-1",
    }));
  });

  it("does not synthesize a shared board user id for board actors without user ids", async () => {
    const app = await createApp({ type: "board", source: "local_implicit" });

    await request(app).post("/api/domains/domain-1/skills/skill-1/star").send({}).expect(200);

    expect(mockDomainSkillService.starSkill).toHaveBeenCalledWith("domain-1", "skill-1", {
      type: "user",
      userId: null,
    });
  });

  it("allows agents with direct skills:create grants to mutate domain skills", async () => {
    mockAccessService.decide.mockResolvedValue(allowSkillChangeDecision("allow_direct_change"));
    mockAgentService.getById.mockResolvedValue({
      id: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      permissions: { canCreateSkills: false },
    });

    const res = await request(await createApp({
      type: "agent",
      agentId: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      runId: "run-1",
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" });

    expect(res.status, JSON.stringify(res.body)).toBe(201);
    expect(mockAccessService.decide).toHaveBeenCalledWith(expect.objectContaining({
      action: "skill_config:update",
      resource: { type: "domain", domainId: "domain-1" },
    }));
    expect(mockReflectionCoachMutationGate.assertConsented).not.toHaveBeenCalled();
    expect(mockDomainSkillService.importFromSource).toHaveBeenCalledWith(
      "domain-1",
      "https://github.com/vercel-labs/agent-browser",
    );
  });

  it("rejects suggest-tier skill mutations when the consent gate is not satisfied", async () => {
    const { forbidden } = await import("../errors.js");
    mockAccessService.decide.mockResolvedValue(denySkillChangeDecision(
      "deny_missing_consent",
      "Permission skills:suggest-changes requires accepted change consent before applying this mutation.",
    ));
    mockReflectionCoachMutationGate.assertConsented.mockRejectedValue(forbidden("gate required", {
      code: "reflection_coach_mutation_gate_required",
    }));

    const res = await request(await createApp({
      type: "agent",
      agentId: "reflection-coach",
      domainId: "domain-1",
      runId: "run-apply",
    }))
      .post("/api/domains/domain-1/skills")
      .send({ name: "Reflection Draft", slug: "reflection-draft", markdown: "# Draft" });

    expect(res.status, JSON.stringify(res.body)).toBe(403);
    expect(res.body.error).toBe("Permission skills:suggest-changes requires accepted change consent before applying this mutation.");
    expect(mockReflectionCoachMutationGate.assertConsented).toHaveBeenCalledWith({
      domainId: "domain-1",
      actorAgentId: "reflection-coach",
      actorRunId: "run-apply",
      targetKeys: ["skill-slug:reflection-draft"],
    });
    expect(mockDomainSkillService.createLocalSkill).not.toHaveBeenCalled();
  });

  it("does not convert consent gate service failures into authorization denials", async () => {
    mockAccessService.decide.mockResolvedValue(denySkillChangeDecision(
      "deny_missing_consent",
      "Permission skills:suggest-changes requires accepted change consent before applying this mutation.",
    ));
    mockReflectionCoachMutationGate.assertConsented.mockRejectedValue(new Error("database unavailable"));

    const res = await request(await createApp({
      type: "agent",
      agentId: "reflection-coach",
      domainId: "domain-1",
      runId: "run-apply",
    }))
      .post("/api/domains/domain-1/skills")
      .send({ name: "Reflection Draft", slug: "reflection-draft", markdown: "# Draft" });

    expect(res.status, JSON.stringify(res.body)).toBe(500);
    expect(res.body.error).toBe("Internal server error");
    expect(mockReflectionCoachMutationGate.assertConsented).toHaveBeenCalledWith({
      domainId: "domain-1",
      actorAgentId: "reflection-coach",
      actorRunId: "run-apply",
      targetKeys: ["skill-slug:reflection-draft"],
    });
    expect(mockDomainSkillService.createLocalSkill).not.toHaveBeenCalled();
  });

  it("allows suggest-tier skill mutations after accepted change consent", async () => {
    mockAccessService.decide
      .mockResolvedValueOnce(denySkillChangeDecision(
        "deny_missing_consent",
        "Permission skills:suggest-changes requires accepted change consent before applying this mutation.",
      ))
      .mockResolvedValueOnce(allowSkillChangeDecision("allow_consented_change"));
    mockAgentService.getById.mockResolvedValue({
      id: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      permissions: {},
    });

    const res = await request(await createApp({
      type: "agent",
      agentId: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      runId: "run-1",
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" });

    expect(res.status, JSON.stringify(res.body)).toBe(201);
    expect(mockReflectionCoachMutationGate.assertConsented).toHaveBeenCalledWith({
      domainId: "domain-1",
      actorAgentId: "55555555-5555-4555-8555-555555555555",
      actorRunId: "run-1",
      targetKeys: ["skill-import:https://github.com/vercel-labs/agent-browser"],
    });
    expect(mockAccessService.decide).toHaveBeenLastCalledWith(expect.objectContaining({
      action: "skill_config:update",
      resource: { type: "domain", domainId: "domain-1" },
      scope: { consentedChange: true },
    }));
    expect(mockDomainSkillService.importFromSource).toHaveBeenCalledWith(
      "domain-1",
      "https://github.com/vercel-labs/agent-browser",
    );
  });

  it("blocks same-domain agents without skill change or suggest grants", async () => {
    mockAccessService.decide.mockResolvedValue(denySkillChangeDecision());
    mockAgentService.getById.mockResolvedValue({
      id: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      permissions: {},
    });

    const res = await request(await createApp({
      type: "agent",
      agentId: "55555555-5555-4555-8555-555555555555",
      domainId: "domain-1",
      runId: "run-1",
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" });

    expect(res.status, JSON.stringify(res.body)).toBe(403);
    expect(res.body.error).toBe("Missing permission: skills:create or skills:suggest-changes.");
    expect(mockAccessService.decide).toHaveBeenCalledWith(expect.objectContaining({
      action: "skill_config:update",
      resource: { type: "domain", domainId: "domain-1" },
    }));
    expect(mockDomainSkillService.importFromSource).not.toHaveBeenCalled();
  });

  it("does not allow explicit agents:create grants to mutate domain skills", async () => {
    mockAccessService.decide.mockResolvedValue(denySkillChangeDecision());
    mockAgentService.getById.mockResolvedValue({
      id: "agent-1",
      domainId: "domain-1",
      permissions: { canCreateSkills: false },
    });
    mockAccessService.hasPermission.mockImplementation(async (
      _domainId: string,
      _principalType: string,
      _principalId: string,
      key: string,
    ) => key === "agents:create");

    const res = await request(await createApp({
      type: "agent",
      agentId: "agent-1",
      domainId: "domain-1",
      runId: "run-1",
    }))
      .post("/api/domains/domain-1/skills/import")
      .send({ source: "https://github.com/vercel-labs/agent-browser" });

    expect(res.status, JSON.stringify(res.body)).toBe(403);
    expect(res.body.error).toBe("Missing permission: skills:create or skills:suggest-changes.");
    expect(mockAccessService.decide).toHaveBeenCalledWith(expect.objectContaining({
      action: "skill_config:update",
      resource: { type: "domain", domainId: "domain-1" },
    }));
    expect(mockAccessService.hasPermission).not.toHaveBeenCalledWith("domain-1", "agent", "agent-1", "agents:create");
    expect(mockDomainSkillService.importFromSource).not.toHaveBeenCalled();
  });

  it("routes skill test input CRUD through skills mutation permissions", async () => {
    const app = await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    });

    const created = await request(app)
      .post("/api/domains/domain-1/skills/skill-1/test-inputs")
      .send({ name: "smoke/input", content: "Try the skill" });
    expect(created.status, JSON.stringify(created.body)).toBe(201);
    expect(mockDomainSkillService.createTestInput).toHaveBeenCalledWith(
      "domain-1",
      "skill-1",
      { name: "smoke/input", content: "Try the skill" },
      { type: "user", userId: "local-board" },
    );

    const updated = await request(app)
      .patch("/api/domains/domain-1/skills/skill-1/test-inputs/11111111-1111-4111-8111-111111111111")
      .send({ name: "smoke/renamed", content: "Try the skill again" });
    expect(updated.status, JSON.stringify(updated.body)).toBe(200);
    expect(mockDomainSkillService.updateTestInput).toHaveBeenCalledWith(
      "domain-1",
      "skill-1",
      "11111111-1111-4111-8111-111111111111",
      { name: "smoke/renamed", content: "Try the skill again" },
    );

    const removed = await request(app)
      .delete("/api/domains/domain-1/skills/skill-1/test-inputs/11111111-1111-4111-8111-111111111111");
    expect(removed.status, JSON.stringify(removed.body)).toBe(200);
    expect(mockDomainSkillService.deleteTestInput).toHaveBeenCalledWith(
      "domain-1",
      "skill-1",
      "11111111-1111-4111-8111-111111111111",
    );
  });

  it("routes skill test run template CRUD through skills mutation permissions", async () => {
    const app = await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    });

    const listed = await request(app).get("/api/domains/domain-1/skill-test-run-templates");
    expect(listed.status, JSON.stringify(listed.body)).toBe(200);
    expect(mockDomainSkillService.listTestRunTemplates).toHaveBeenCalledWith("domain-1");

    const created = await request(app)
      .post("/api/domains/domain-1/skill-test-run-templates")
      .send({ name: "Custom template", description: "Custom run guidance", body: "Run {{skillName}}." });
    expect(created.status, JSON.stringify(created.body)).toBe(201);
    expect(mockDomainSkillService.createTestRunTemplate).toHaveBeenCalledWith(
      "domain-1",
      { name: "Custom template", description: "Custom run guidance", body: "Run {{skillName}}." },
      { type: "user", userId: "local-board" },
    );

    const updated = await request(app)
      .patch("/api/domains/domain-1/skill-test-run-templates/66666666-6666-4666-8666-666666666666")
      .send({ name: "Renamed template" });
    expect(updated.status, JSON.stringify(updated.body)).toBe(200);
    expect(mockDomainSkillService.updateTestRunTemplate).toHaveBeenCalledWith(
      "domain-1",
      "66666666-6666-4666-8666-666666666666",
      { name: "Renamed template" },
      { type: "user", userId: "local-board" },
    );

    const removed = await request(app)
      .delete("/api/domains/domain-1/skill-test-run-templates/66666666-6666-4666-8666-666666666666");
    expect(removed.status, JSON.stringify(removed.body)).toBe(200);
    expect(mockDomainSkillService.deleteTestRunTemplate).toHaveBeenCalledWith(
      "domain-1",
      "66666666-6666-4666-8666-666666666666",
    );
  });

  it("creates and cancels skill test runs through hidden issue orchestration", async () => {
    mockDomainSkillService.createTestRun.mockImplementationOnce(async (
      _domainId: string,
      _skillId: string,
      _body: unknown,
      _actor: unknown,
      deps: {
        createHarnessIssue: (input: Record<string, unknown>) => Promise<unknown>;
        wakeHarnessIssue: (issueId: string, agentId: string) => Promise<unknown>;
      },
    ) => {
      await deps.createHarnessIssue({
        id: "44444444-4444-4444-8444-444444444444",
        title: "Skill test: Review",
        description: "Try the skill",
        assigneeAgentId: "55555555-5555-4555-8555-555555555555",
        harnessKind: "skill_test",
        workMode: "skill_test",
        status: "todo",
        originKind: "skill_test",
        originId: "22222222-2222-4222-8222-222222222222",
        originFingerprint: "skill_test:22222222-2222-4222-8222-222222222222",
      });
      await deps.wakeHarnessIssue("44444444-4444-4444-8444-444444444444", "55555555-5555-4555-8555-555555555555");
      return {
        id: "22222222-2222-4222-8222-222222222222",
        domainId: "domain-1",
        skillId: "skill-1",
        inputId: "11111111-1111-4111-8111-111111111111",
        inputSnapshot: "Try the skill",
        skillVersionId: "33333333-3333-4333-8333-333333333333",
        agentId: "55555555-5555-4555-8555-555555555555",
        agentConfigSnapshot: { adapterType: "codex_local" },
        issueId: "44444444-4444-4444-8444-444444444444",
        templateId: "built-in:default-test-template",
        templateName: "Default test template",
        templateBody: "Default {{skillName}}",
        renderedTemplateBody: "Default Review",
        harnessIssueDescription: "Try the skill\n\n---\n\nDefault Review",
        status: "queued",
        outputDocumentKey: "output",
        outputSnapshot: "",
        error: null,
        deletedAt: null,
        supersededAt: null,
        harnessIssueExpiresAt: null,
        harnessIssueDeletedAt: null,
        createdAt: new Date("2026-05-26T00:00:00.000Z"),
        updatedAt: new Date("2026-05-26T00:00:00.000Z"),
        finance: { financeCents: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
        taskExpired: false,
      };
    });
    mockDomainSkillService.cancelTestRun.mockImplementationOnce(async (
      _domainId: string,
      _skillId: string,
      _runId: string,
      deps: { cancelHarnessIssue: (issueId: string) => Promise<unknown> },
    ) => {
      await deps.cancelHarnessIssue("44444444-4444-4444-8444-444444444444");
      return {
        id: "22222222-2222-4222-8222-222222222222",
        domainId: "domain-1",
        skillId: "skill-1",
        inputId: "11111111-1111-4111-8111-111111111111",
        inputSnapshot: "Try the skill",
        skillVersionId: "33333333-3333-4333-8333-333333333333",
        agentId: "55555555-5555-4555-8555-555555555555",
        agentConfigSnapshot: { adapterType: "codex_local" },
        issueId: "44444444-4444-4444-8444-444444444444",
        templateId: "built-in:default-test-template",
        templateName: "Default test template",
        templateBody: "Default {{skillName}}",
        renderedTemplateBody: "Default Review",
        harnessIssueDescription: "Try the skill\n\n---\n\nDefault Review",
        status: "cancelled",
        outputDocumentKey: "output",
        outputSnapshot: "",
        error: "Cancelled by operator",
        deletedAt: null,
        supersededAt: null,
        harnessIssueExpiresAt: null,
        harnessIssueDeletedAt: null,
        createdAt: new Date("2026-05-26T00:00:00.000Z"),
        updatedAt: new Date("2026-05-26T00:01:00.000Z"),
        finance: { financeCents: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
        taskExpired: false,
      };
    });

    const app = await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    });

    const created = await request(app)
      .post("/api/domains/domain-1/skills/skill-1/test-runs")
      .send({ inputId: "11111111-1111-4111-8111-111111111111", agentId: "55555555-5555-4555-8555-555555555555" });
    expect(created.status, JSON.stringify(created.body)).toBe(201);
    expect(mockIssueService.create).toHaveBeenCalledWith("domain-1", expect.objectContaining({
      harnessKind: "skill_test",
      workMode: "skill_test",
      assigneeAgentId: "55555555-5555-4555-8555-555555555555",
      description: "Try the skill",
    }));
    expect(mockHeartbeatService.wakeup).toHaveBeenCalledWith("55555555-5555-4555-8555-555555555555", expect.objectContaining({
      reason: "skill_test_run_created",
      payload: expect.objectContaining({ issueId: "44444444-4444-4444-8444-444444444444", skillId: "skill-1" }),
    }));

    const cancelled = await request(app)
      .post("/api/domains/domain-1/skills/skill-1/test-runs/22222222-2222-4222-8222-222222222222/cancel")
      .send({});
    expect(cancelled.status, JSON.stringify(cancelled.body)).toBe(200);
    expect(mockHeartbeatService.cancelRun).toHaveBeenCalledWith("run-1", "Cancelled by skill test run request");
    expect(mockIssueService.update).toHaveBeenCalledWith("44444444-4444-4444-8444-444444444444", expect.objectContaining({
      status: "cancelled",
      actorUserId: "local-board",
    }));
  });

  it("does not prune expired harness issues from test run reads", async () => {
    mockDomainSkillService.listTestRuns.mockResolvedValueOnce([]);
    mockDomainSkillService.getTestRunDetail.mockResolvedValueOnce({
      id: "22222222-2222-4222-8222-222222222222",
      domainId: "domain-1",
      skillId: "skill-1",
      status: "succeeded",
      harnessContent: { available: false, unavailableReason: "expired", documents: [], attachments: [], workProducts: [] },
    });

    const app = await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    });

    const listed = await request(app)
      .get("/api/domains/domain-1/skills/skill-1/test-runs");
    expect(listed.status, JSON.stringify(listed.body)).toBe(200);

    const detail = await request(app)
      .get("/api/domains/domain-1/skills/skill-1/test-runs/22222222-2222-4222-8222-222222222222");
    expect(detail.status, JSON.stringify(detail.body)).toBe(200);

    expect(mockDomainSkillService.listTestRuns).toHaveBeenCalledWith("domain-1", "skill-1", {});
    expect(mockDomainSkillService.getTestRunDetail).toHaveBeenCalledWith(
      "domain-1",
      "skill-1",
      "22222222-2222-4222-8222-222222222222",
    );
    expect(mockDomainSkillService.pruneExpiredTestHarnessIssues).not.toHaveBeenCalled();
  });

  it("deletes a terminal test run and hides its harness task", async () => {
    mockIssueService.getById.mockResolvedValueOnce({
      id: "44444444-4444-4444-8444-444444444444",
      domainId: "domain-1",
      status: "done",
      executionRunId: null,
    });
    mockDomainSkillService.deleteTestRun.mockImplementationOnce(async (
      _domainId: string,
      _skillId: string,
      _runId: string,
      deps: { hideHarnessIssue: (issueId: string) => Promise<unknown> },
    ) => {
      await deps.hideHarnessIssue("44444444-4444-4444-8444-444444444444");
      return {
        id: "22222222-2222-4222-8222-222222222222",
        domainId: "domain-1",
        skillId: "skill-1",
        inputId: null,
        inputSnapshot: "Try the skill",
        skillVersionId: "33333333-3333-4333-8333-333333333333",
        agentId: "55555555-5555-4555-8555-555555555555",
        agentConfigSnapshot: { adapterType: "codex_local" },
        issueId: "44444444-4444-4444-8444-444444444444",
        templateId: "built-in:default-test-template",
        templateName: "Default test template",
        templateBody: "Default {{skillName}}",
        renderedTemplateBody: "Default Review",
        harnessIssueDescription: "Try the skill\n\n---\n\nDefault Review",
        status: "succeeded",
        outputDocumentKey: "output",
        outputSnapshot: "",
        error: null,
        deletedAt: new Date("2026-05-26T00:02:00.000Z"),
        supersededAt: null,
        harnessIssueExpiresAt: null,
        harnessIssueDeletedAt: null,
        createdAt: new Date("2026-05-26T00:00:00.000Z"),
        updatedAt: new Date("2026-05-26T00:02:00.000Z"),
        finance: { financeCents: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
        taskExpired: false,
      };
    });

    const app = await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    });

    const deleted = await request(app)
      .delete("/api/domains/domain-1/skills/skill-1/test-runs/22222222-2222-4222-8222-222222222222");
    expect(deleted.status, JSON.stringify(deleted.body)).toBe(200);
    expect(mockDomainSkillService.deleteTestRun).toHaveBeenCalled();
    expect(mockIssueService.update).toHaveBeenCalledWith(
      "44444444-4444-4444-8444-444444444444",
      expect.objectContaining({ hiddenAt: expect.any(Date) }),
    );
  });

  it("returns 404 when deleting a missing test run", async () => {
    mockDomainSkillService.deleteTestRun.mockResolvedValueOnce(null);
    const app = await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    });
    const res = await request(app)
      .delete("/api/domains/domain-1/skills/skill-1/test-runs/22222222-2222-4222-8222-222222222222");
    expect(res.status).toBe(404);
  });

  it("returns a blocking error when attempting to delete a skill still used by agents", async () => {
    const { unprocessable } = await import("../errors.js");
    mockDomainSkillService.deleteSkill.mockImplementationOnce(async () => {
      throw unprocessable(
        'Cannot delete skill "Find Skills" while it is still used by Builder, Reviewer. Detach it from those agents first.',
      );
    });

    const res = await request(await createApp({
      type: "board",
      userId: "local-board",
      domainIds: ["domain-1"],
      source: "local_implicit",
      isInstanceAdmin: false,
    }))
      .delete("/api/domains/domain-1/skills/skill-1");

    expect(res.status, JSON.stringify(res.body)).toBe(422);
    expect(res.body).toEqual({
      error: 'Cannot delete skill "Find Skills" while it is still used by Builder, Reviewer. Detach it from those agents first.',
    });
    expect(mockDomainSkillService.deleteSkill).toHaveBeenCalledWith("domain-1", "skill-1");
    expect(mockLogActivity).not.toHaveBeenCalled();
  });
});

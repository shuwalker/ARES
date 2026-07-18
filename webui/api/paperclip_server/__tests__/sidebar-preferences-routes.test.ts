import express from "express";
import request from "supertest";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockSidebarPreferenceService = vi.hoisted(() => ({
  getDomainOrder: vi.fn(),
  upsertDomainOrder: vi.fn(),
  getProjectOrder: vi.fn(),
  upsertProjectOrder: vi.fn(),
}));
const mockLogActivity = vi.hoisted(() => vi.fn());

function registerModuleMocks() {
  vi.doMock("../services/index.js", () => ({
    sidebarPreferenceService: () => mockSidebarPreferenceService,
    logActivity: mockLogActivity,
  }));
}

async function createApp(actor: Record<string, unknown>) {
  const [{ sidebarPreferenceRoutes }, { errorHandler }] = await Promise.all([
    import("../routes/sidebar-preferences.js"),
    import("../middleware/index.js"),
  ]);
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.actor = actor as never;
    next();
  });
  app.use("/api", sidebarPreferenceRoutes({} as never));
  app.use(errorHandler);
  return app;
}

const ORDERED_IDS = [
  "11111111-1111-4111-8111-111111111111",
  "22222222-2222-4222-8222-222222222222",
];

describe("sidebar preference routes", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.doUnmock("../services/index.js");
    vi.doUnmock("../routes/sidebar-preferences.js");
    vi.doUnmock("../routes/authz.js");
    vi.doUnmock("../middleware/index.js");
    registerModuleMocks();
    vi.clearAllMocks();
    mockSidebarPreferenceService.getDomainOrder.mockResolvedValue({
      orderedIds: ORDERED_IDS,
      updatedAt: null,
    });
    mockSidebarPreferenceService.upsertDomainOrder.mockResolvedValue({
      orderedIds: ORDERED_IDS,
      updatedAt: null,
    });
    mockSidebarPreferenceService.getProjectOrder.mockResolvedValue({
      orderedIds: ORDERED_IDS,
      updatedAt: null,
    });
    mockSidebarPreferenceService.upsertProjectOrder.mockResolvedValue({
      orderedIds: ORDERED_IDS,
      updatedAt: null,
    });
  });

  it("returns domain rail order for board users", async () => {
    const app = await createApp({
      type: "board",
      userId: "user-1",
      source: "session",
      isInstanceAdmin: false,
      domainIds: ["domain-1"],
    });

    const res = await request(app).get("/api/sidebar-preferences/me");

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      orderedIds: ORDERED_IDS,
      updatedAt: null,
    });
    expect(mockSidebarPreferenceService.getDomainOrder).toHaveBeenCalledWith("user-1");
  });

  it("updates domain rail order for board users", async () => {
    const app = await createApp({
      type: "board",
      userId: "user-1",
      source: "local_implicit",
      isInstanceAdmin: true,
      domainIds: ["domain-1"],
    });

    const res = await request(app)
      .put("/api/sidebar-preferences/me")
      .send({ orderedIds: ORDERED_IDS });

    expect(res.status).toBe(200);
    expect(mockSidebarPreferenceService.upsertDomainOrder).toHaveBeenCalledWith("user-1", ORDERED_IDS);
  });

  it("returns project order for domains the board user can access", async () => {
    const app = await createApp({
      type: "board",
      userId: "user-1",
      source: "session",
      isInstanceAdmin: false,
      domainIds: ["domain-1"],
    });

    const res = await request(app).get("/api/domains/domain-1/sidebar-preferences/me");

    expect(res.status).toBe(200);
    expect(mockSidebarPreferenceService.getProjectOrder).toHaveBeenCalledWith("domain-1", "user-1");
  });

  it("logs project order updates for domain-scoped writes", async () => {
    const app = await createApp({
      type: "board",
      userId: "user-1",
      source: "session",
      isInstanceAdmin: false,
      domainIds: ["domain-1"],
      runId: "run-1",
    });

    const res = await request(app)
      .put("/api/domains/domain-1/sidebar-preferences/me")
      .send({ orderedIds: ORDERED_IDS });

    expect(res.status).toBe(200);
    expect(mockSidebarPreferenceService.upsertProjectOrder).toHaveBeenCalledWith("domain-1", "user-1", ORDERED_IDS);
    expect(mockLogActivity).toHaveBeenCalledWith(
      {} as never,
      expect.objectContaining({
        domainId: "domain-1",
        action: "sidebar_preferences.project_order_updated",
        details: expect.objectContaining({
          userId: "user-1",
          orderedIds: ORDERED_IDS,
        }),
      }),
    );
  });

  it("rejects domain-scoped reads when the board user lacks domain access", async () => {
    const app = await createApp({
      type: "board",
      userId: "user-1",
      source: "session",
      isInstanceAdmin: false,
      domainIds: ["domain-2"],
    });

    const res = await request(app).get("/api/domains/domain-1/sidebar-preferences/me");

    expect(res.status).toBe(403);
    expect(mockSidebarPreferenceService.getProjectOrder).not.toHaveBeenCalled();
  });

  it("rejects agent callers", async () => {
    const app = await createApp({
      type: "agent",
      agentId: "agent-1",
      domainId: "domain-1",
      source: "agent_key",
    });

    const res = await request(app).get("/api/sidebar-preferences/me");

    expect(res.status).toBe(403);
    expect(mockSidebarPreferenceService.getDomainOrder).not.toHaveBeenCalled();
  });
});

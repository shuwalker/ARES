import express from "express";
import request from "supertest";
import { describe, expect, it, vi } from "vitest";
import { domainRoutes } from "../routes/domains.js";

vi.mock("../services/index.js", () => ({
  domainService: () => ({
    list: vi.fn(),
    stats: vi.fn(),
    getById: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    archive: vi.fn(),
    remove: vi.fn(),
  }),
  domainPortabilityService: () => ({
    exportBundle: vi.fn(),
    previewExport: vi.fn(),
    previewImport: vi.fn(),
    importBundle: vi.fn(),
  }),
  domainArtifactsService: () => ({
    list: vi.fn(),
  }),
  accessService: () => ({
    canUser: vi.fn(),
    ensureMembership: vi.fn(),
  }),
  budgetService: () => ({
    upsertPolicy: vi.fn(),
  }),
  agentService: () => ({
    getById: vi.fn(),
  }),
  feedbackService: () => ({
    listIssueVotesForUser: vi.fn(),
    listFeedbackTraces: vi.fn(),
    getFeedbackTraceById: vi.fn(),
    saveIssueVote: vi.fn(),
  }),
  logActivity: vi.fn(),
}));

describe("domain routes malformed issue path guard", () => {
  it("returns a clear error when domainId is missing for issues list path", async () => {
    const app = express();
    app.use((req, _res, next) => {
      (req as any).actor = {
        type: "agent",
        agentId: "agent-1",
        domainId: "domain-1",
        source: "agent_key",
      };
      next();
    });
    app.use("/api/domains", domainRoutes({} as any));

    const res = await request(app).get("/api/domains/issues");

    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: "Missing domainId in path. Use /api/domains/{domainId}/issues.",
    });
  });
});

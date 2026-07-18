import { randomUUID } from "node:crypto";
import { and, eq } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
  activityLog,
  agents,
  agentRuntimeState,
  agentWakeupRequests,
  domains,
  domainMemberships,
  domainSkills,
  createDb,
  heartbeatRunEvents,
  heartbeatRuns,
  issueComments,
  issues,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { heartbeatService } from "../services/heartbeat.ts";
import { runningProcesses } from "../adapters/index.ts";

const mockAdapterExecute = vi.hoisted(() =>
  vi.fn(async () => ({
    exitCode: 0,
    signal: null,
    timedOut: false,
    errorMessage: null,
    summary: "Responsible-user invariant test run.",
    provider: "test",
    model: "test-model",
  })),
);

vi.mock("../adapters/index.ts", async () => {
  const actual = await vi.importActual<typeof import("../adapters/index.ts")>("../adapters/index.ts");
  return {
    ...actual,
    getServerAdapter: vi.fn(() => ({
      supportsLocalAgentJwt: false,
      execute: mockAdapterExecute,
    })),
  };
});

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

async function waitForRun(db: ReturnType<typeof createDb>, runId: string) {
  for (let attempt = 0; attempt < 80; attempt += 1) {
    const run = await db.select().from(heartbeatRuns).where(eq(heartbeatRuns.id, runId)).then((rows) => rows[0] ?? null);
    if (run && run.status !== "queued" && run.status !== "running") return run;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  return db.select().from(heartbeatRuns).where(eq(heartbeatRuns.id, runId)).then((rows) => rows[0] ?? null);
}

describeEmbeddedPostgres("heartbeat responsible-user invariant", () => {
  let db!: ReturnType<typeof createDb>;
  let heartbeat!: ReturnType<typeof heartbeatService>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-heartbeat-responsible-user-");
    db = createDb(tempDb.connectionString);
    heartbeat = heartbeatService(db);
  }, 20_000);

  afterEach(async () => {
    mockAdapterExecute.mockClear();
    runningProcesses.clear();
    await new Promise((resolve) => setTimeout(resolve, 500));
    for (let attempt = 0; attempt < 40; attempt += 1) {
      const activeRuns = await db
        .select()
        .from(heartbeatRuns)
        .where(eq(heartbeatRuns.status, "running"));
      if (activeRuns.length === 0) break;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    await db.delete(heartbeatRunEvents);
    await db.delete(issueComments);
    await db.delete(activityLog);
    await db.delete(heartbeatRuns);
    await db.delete(agentWakeupRequests);
    await db.delete(agentRuntimeState);
    await db.delete(issues);
    await db.delete(agents);
    await db.delete(domainSkills);
    await db.delete(domainMemberships);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  async function seedDomain() {
    const domainId = randomUUID();
    const ownerUserId = `owner-${randomUUID()}`;
    const agentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: `R${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      defaultResponsibleUserId: ownerUserId,
    });
    await db.insert(domainMemberships).values({
      domainId,
      principalType: "user",
      principalId: ownerUserId,
      membershipRole: "owner",
      status: "active",
    });
    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "CodexCoder",
      role: "engineer",
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: { heartbeat: { wakeOnDemand: true, maxConcurrentRuns: 1 } },
      permissions: {},
    });

    return { domainId, ownerUserId, agentId };
  }

  it("uses the issue responsible user for comment, mention, and dependency wakes", async () => {
    const { domainId, agentId } = await seedDomain();
    const issueResponsibleUserId = `issue-owner-${randomUUID()}`;
    const commenterUserId = `commenter-${randomUUID()}`;
    const issueId = randomUUID();
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Issue-owned work",
      status: "todo",
      assigneeAgentId: agentId,
      responsibleUserId: issueResponsibleUserId,
    });

    for (const wakeReason of ["issue_commented", "issue_comment_mentioned", "issue_blockers_resolved"]) {
      const run = await heartbeat.wakeup(agentId, {
        source: "automation",
        triggerDetail: "system",
        reason: wakeReason,
        payload: { issueId, commentId: randomUUID() },
        requestedByActorType: "user",
        requestedByActorId: commenterUserId,
        contextSnapshot: { issueId, taskId: issueId, wakeReason },
      });
      expect(run).not.toBeNull();
      const completed = await waitForRun(db, run!.id);
      expect(completed?.responsibleUserId).toBe(issueResponsibleUserId);
    }
  });

  it("uses the triggering user for manual UI/API runs", async () => {
    const { agentId } = await seedDomain();
    const triggeringUserId = `manual-${randomUUID()}`;
    const run = await heartbeat.wakeup(agentId, {
      source: "on_demand",
      triggerDetail: "manual",
      requestedByActorType: "user",
      requestedByActorId: triggeringUserId,
    });

    expect(run).not.toBeNull();
    const completed = await waitForRun(db, run!.id);
    expect(completed?.responsibleUserId).toBe(triggeringUserId);
  });

  it("falls back to the domain default for system-originated runs without an issue", async () => {
    const { agentId, ownerUserId } = await seedDomain();
    const run = await heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: "productivity_review",
      requestedByActorType: "system",
      requestedByActorId: null,
      contextSnapshot: { wakeReason: "productivity_review" },
    });

    expect(run).not.toBeNull();
    const completed = await waitForRun(db, run!.id);
    expect(completed?.responsibleUserId).toBe(ownerUserId);
  });

  it("does not use an issue creator as an implicit responsible user for automated issue runs", async () => {
    const { domainId, agentId, ownerUserId } = await seedDomain();
    const creatorUserId = `creator-${randomUUID()}`;
    const issueId = randomUUID();
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Creator is not credential owner",
      status: "todo",
      assigneeAgentId: agentId,
      createdByUserId: creatorUserId,
    });

    const run = await heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: "issue_commented",
      payload: { issueId, commentId: randomUUID() },
      requestedByActorType: "user",
      requestedByActorId: `commenter-${randomUUID()}`,
      contextSnapshot: { issueId, taskId: issueId, wakeReason: "issue_commented" },
    });
    expect(run).not.toBeNull();
    const completed = await waitForRun(db, run!.id);
    expect(completed?.responsibleUserId).toBe(ownerUserId);
    expect(completed?.responsibleUserId).not.toBe(creatorUserId);
  });

  it("fails automated issue dispatch instead of falling back to the issue creator when no default exists", async () => {
    const domainId = randomUUID();
    const agentId = randomUUID();
    const issueId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Creator-only",
      issuePrefix: `C${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
    });
    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "CodexCoder",
      role: "engineer",
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: { heartbeat: { wakeOnDemand: true } },
      permissions: {},
    });
    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Creator-only issue",
      status: "todo",
      assigneeAgentId: agentId,
      createdByUserId: `creator-${randomUUID()}`,
    });

    await expect(heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: "issue_commented",
      payload: { issueId, commentId: randomUUID() },
      requestedByActorType: "user",
      requestedByActorId: `commenter-${randomUUID()}`,
      contextSnapshot: { issueId, taskId: issueId, wakeReason: "issue_commented" },
    })).rejects.toMatchObject({
      status: 422,
      details: { code: "responsible_user_unresolved" },
    });

    const runs = await db
      .select()
      .from(heartbeatRuns)
      .where(and(eq(heartbeatRuns.domainId, domainId), eq(heartbeatRuns.agentId, agentId)));
    expect(runs).toHaveLength(0);
  });

  it("fails dispatch before creating a run when no responsible user can be resolved", async () => {
    const domainId = randomUUID();
    const agentId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Ownerless",
      issuePrefix: `O${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
    });
    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "CodexCoder",
      role: "engineer",
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: { heartbeat: { wakeOnDemand: true } },
      permissions: {},
    });

    await expect(heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      requestedByActorType: "system",
    })).rejects.toMatchObject({
      status: 422,
      details: { code: "responsible_user_unresolved" },
    });

    const runs = await db
      .select()
      .from(heartbeatRuns)
      .where(and(eq(heartbeatRuns.domainId, domainId), eq(heartbeatRuns.agentId, agentId)));
    expect(runs).toHaveLength(0);
  });
});

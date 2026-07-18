import { randomUUID } from "node:crypto";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  agents,
  agentWakeupRequests,
  domains,
  createDb,
  heartbeatRunEvents,
  heartbeatRuns,
  issues,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { heartbeatService } from "../services/heartbeat.ts";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres archived-domain heartbeat guard tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("heartbeat archived-domain guard", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("heartbeat-archived-domain-guard-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(heartbeatRunEvents);
    await db.delete(heartbeatRuns);
    await db.delete(agentWakeupRequests);
    await db.delete(issues);
    await db.delete(agents);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  async function insertArchivedAgent() {
    const domainId = randomUUID();
    const agentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Archived Co",
      status: "archived",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "Archived Agent",
      role: "engineer",
      status: "idle",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {
        heartbeat: {
          enabled: true,
          intervalSec: 60,
          wakeOnDemand: true,
        },
      },
      permissions: {},
    });

    return { domainId, agentId };
  }

  async function insertInvalidOrgChainAgent() {
    const domainId = randomUUID();
    const managerId = randomUUID();
    const childId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Invalid Org Co",
      status: "active",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values([
      {
        id: managerId,
        domainId,
        name: "Terminated Manager",
        role: "cto",
        status: "terminated",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {
          heartbeat: {
            enabled: true,
            intervalSec: 60,
            wakeOnDemand: true,
          },
        },
        permissions: {},
      },
      {
        id: childId,
        domainId,
        name: "Invalid Chain Child",
        role: "engineer",
        reportsTo: managerId,
        status: "idle",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {
          heartbeat: {
            enabled: true,
            intervalSec: 60,
            wakeOnDemand: true,
          },
        },
        permissions: {},
      },
    ]);

    return { domainId, managerId, childId };
  }

  it("does not iterate archived-domain agents in tickTimers", async () => {
    const { agentId } = await insertArchivedAgent();

    const heartbeat = heartbeatService(db);
    const result = await heartbeat.tickTimers(new Date("2026-06-04T00:10:00Z"));

    expect(result).toMatchObject({
      checked: 0,
      enqueued: 0,
      skipped: 0,
    });

    const runCount = await db
      .select()
      .from(heartbeatRuns)
      .then((rows) => rows.filter((row) => row.agentId === agentId).length);
    expect(runCount).toBe(0);
  });

  it("skips background wakeups for non-active domains with a domain.inactive reason", async () => {
    const { agentId } = await insertArchivedAgent();

    const heartbeat = heartbeatService(db);
    const run = await heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: "issue_commented",
      payload: { issueId: randomUUID(), commentId: randomUUID() },
      requestedByActorType: "system",
      requestedByActorId: "comment_wake",
    });

    expect(run).toBeNull();

    const wakeup = await db
      .select({
        agentId: agentWakeupRequests.agentId,
        status: agentWakeupRequests.status,
        reason: agentWakeupRequests.reason,
        error: agentWakeupRequests.error,
      })
      .from(agentWakeupRequests)
      .then((rows) => rows.find((row) => row.agentId === agentId) ?? null);

    expect(wakeup).toMatchObject({
      status: "skipped",
      reason: "domain.inactive",
      error: "Wake suppressed because domain status is archived",
    });
  });

  it("does not advance issue monitors for archived domains", async () => {
    const { domainId, agentId } = await insertArchivedAgent();
    const issueId = randomUUID();
    const monitorScheduledAt = new Date("2026-06-04T00:00:00Z");

    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Archived-domain monitor issue",
      status: "in_progress",
      assigneeAgentId: agentId,
      monitorNextCheckAt: monitorScheduledAt,
      monitorAttemptCount: 0,
    });

    const heartbeat = heartbeatService(db);
    await heartbeat.tickTimers(new Date("2026-06-04T00:10:00Z"));

    const row = await db
      .select({
        monitorNextCheckAt: issues.monitorNextCheckAt,
        monitorWakeRequestedAt: issues.monitorWakeRequestedAt,
        monitorLastTriggeredAt: issues.monitorLastTriggeredAt,
        monitorAttemptCount: issues.monitorAttemptCount,
      })
      .from(issues)
      .then((rows) => rows[0] ?? null);

    expect(row?.monitorWakeRequestedAt).toBeNull();
    expect(row?.monitorLastTriggeredAt).toBeNull();
    expect(row?.monitorAttemptCount).toBe(0);
    expect(row?.monitorNextCheckAt?.getTime()).toBe(monitorScheduledAt.getTime());
  });

  it("does not resume queued runs for archived domains", async () => {
    const { domainId, agentId } = await insertArchivedAgent();
    const runId = randomUUID();

    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId,
      invocationSource: "timer",
      status: "queued",
    });

    const heartbeat = heartbeatService(db);
    await heartbeat.resumeQueuedRuns();

    const status = await db
      .select({ status: heartbeatRuns.status })
      .from(heartbeatRuns)
      .then((rows) => rows[0]?.status ?? null);
    expect(status).toBe("queued");
  });

  it("rejects explicit user invokes for non-active domains", async () => {
    const { agentId } = await insertArchivedAgent();

    const heartbeat = heartbeatService(db);

    await expect(heartbeat.wakeup(agentId, {
      source: "on_demand",
      triggerDetail: "manual",
      requestedByActorType: "user",
      requestedByActorId: "board-user",
    })).rejects.toMatchObject({
      status: 409,
      details: { status: "archived" },
    });

    const runCount = await db
      .select()
      .from(heartbeatRuns)
      .then((rows) => rows.filter((row) => row.agentId === agentId).length);
    expect(runCount).toBe(0);
  });

  it("rejects explicit user invokes for invalid-org-chain agents", async () => {
    const { childId } = await insertInvalidOrgChainAgent();

    const heartbeat = heartbeatService(db);

    await expect(heartbeat.wakeup(childId, {
      source: "on_demand",
      triggerDetail: "manual",
      requestedByActorType: "user",
      requestedByActorId: "board-user",
    })).rejects.toMatchObject({
      status: 409,
      details: {
        reason: "manager_terminated",
        invalidOrgChain: true,
      },
    });

    const runCount = await db
      .select()
      .from(heartbeatRuns)
      .then((rows) => rows.filter((row) => row.agentId === childId).length);
    expect(runCount).toBe(0);
  });

  it("cancels existing queued runs for invalid-org-chain agents instead of starting them", async () => {
    const { domainId, childId } = await insertInvalidOrgChainAgent();
    const wakeupRequestId = randomUUID();
    const runId = randomUUID();

    await db.insert(agentWakeupRequests).values({
      id: wakeupRequestId,
      domainId,
      agentId: childId,
      source: "assignment",
      status: "queued",
    });
    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId: childId,
      invocationSource: "assignment",
      status: "queued",
      wakeupRequestId,
    });

    const heartbeat = heartbeatService(db);
    await heartbeat.resumeQueuedRuns();

    const run = await db
      .select({
        status: heartbeatRuns.status,
        error: heartbeatRuns.error,
      })
      .from(heartbeatRuns)
      .then((rows) => rows.find((row) => row.status === "cancelled") ?? null);
    expect(run).toMatchObject({
      status: "cancelled",
      error: "Cancelled because the agent is not invokable: manager_terminated",
    });

    const wakeup = await db
      .select({
        status: agentWakeupRequests.status,
        error: agentWakeupRequests.error,
      })
      .from(agentWakeupRequests)
      .then((rows) => rows[0] ?? null);
    expect(wakeup).toMatchObject({
      status: "cancelled",
      error: "Cancelled because the agent is not invokable: manager_terminated",
    });
  });

  it("suppresses due scheduled retries for invalid-org-chain agents", async () => {
    const { domainId, childId } = await insertInvalidOrgChainAgent();
    const wakeupRequestId = randomUUID();
    const runId = randomUUID();
    const now = new Date("2026-06-04T00:10:00Z");

    await db.insert(agentWakeupRequests).values({
      id: wakeupRequestId,
      domainId,
      agentId: childId,
      source: "automation",
      status: "queued",
    });
    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId: childId,
      invocationSource: "automation",
      status: "scheduled_retry",
      wakeupRequestId,
      scheduledRetryAt: new Date("2026-06-04T00:00:00Z"),
      scheduledRetryReason: "transient_failure",
      scheduledRetryAttempt: 1,
    });

    const heartbeat = heartbeatService(db);
    const promoted = await heartbeat.promoteDueScheduledRetries(now);

    expect(promoted).toEqual({ promoted: 0, runIds: [] });
    const run = await db
      .select({
        status: heartbeatRuns.status,
        errorCode: heartbeatRuns.errorCode,
        error: heartbeatRuns.error,
      })
      .from(heartbeatRuns)
      .then((rows) => rows[0] ?? null);
    expect(run).toMatchObject({
      status: "cancelled",
      errorCode: "agent_not_invokable",
      error: "Scheduled retry suppressed because the agent is not invokable",
    });
  });
});

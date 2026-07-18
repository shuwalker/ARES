import { randomUUID } from "node:crypto";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { and, eq } from "drizzle-orm";
import {
  activityLog,
  agentConfigRevisions,
  agents,
  agentWakeupRequests,
  builtInManagedResources,
  domains,
  domainSkillVersions,
  domainSkills,
  domainMemberships,
  createDb,
  heartbeatRunEvents,
  heartbeatRuns,
  principalPermissionGrants,
  routines,
  routineTriggers,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { domainService } from "../services/domains.js";
import { readBuiltInAgentMarker } from "../services/built-in-agent-metadata.js";
import { reconcileBuiltInAgentsOnStartup } from "../services/built-in-agents.js";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres domain service tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("domainService", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-domain-service-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(routineTriggers);
    await db.delete(routines);
    await db.delete(builtInManagedResources);
    await db.delete(domainSkillVersions);
    await db.delete(domainSkills);
    await db.delete(heartbeatRunEvents);
    await db.delete(heartbeatRuns);
    await db.delete(agentWakeupRequests);
    await db.delete(agentConfigRevisions);
    await db.delete(activityLog);
    await db.delete(agents);
    await db.delete(principalPermissionGrants);
    await db.delete(domainMemberships);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  it("retries generated issue prefixes when Drizzle wraps the unique constraint error", async () => {
    await db.insert(domains).values({
      name: "Aron Existing",
      issuePrefix: "ARO",
    });

    const created = await domainService(db).create({
      name: "Aron & Sharon",
    });

    expect(created.issuePrefix).toBe("AROA");

    const rows = await db.select({ issuePrefix: domains.issuePrefix }).from(domains);
    expect(rows.map((row) => row.issuePrefix).sort()).toEqual(["ARO", "AROA"]);
  });

  it("auto-provisions one paused Reflection Coach bundle for a freshly created domain", async () => {
    const created = await domainService(db).create({
      name: "Fresh Domain",
    });

    const agentRows = await db.select().from(agents).where(eq(agents.domainId, created.id));
    const reflectionRows = agentRows.filter((row) => readBuiltInAgentMarker(row.metadata)?.key === "reflection-coach");
    expect(reflectionRows).toHaveLength(1);
    expect(reflectionRows[0]).toMatchObject({
      name: "Reflection Coach",
      status: "paused",
      budgetMonthlyCents: 0,
      spentMonthlyCents: 0,
    });

    const [skill] = await db
      .select()
      .from(domainSkills)
      .where(and(
        eq(domainSkills.domainId, created.id),
        eq(domainSkills.key, "paperclipai/bundled/paperclip-operations/reflection-coach"),
      ));
    expect(skill).toMatchObject({
      slug: "reflection-coach",
    });

    const [routine] = await db.select().from(routines).where(eq(routines.domainId, created.id));
    expect(routine).toMatchObject({
      status: "paused",
      assigneeAgentId: reflectionRows[0]!.id,
      originKind: "built_in_agent_bundle",
      originId: "reflection-coach:recent-agent-reflection",
    });
    const [trigger] = await db.select().from(routineTriggers).where(eq(routineTriggers.routineId, routine!.id));
    expect(trigger).toMatchObject({
      kind: "schedule",
      enabled: false,
    });

    await reconcileBuiltInAgentsOnStartup(db);
    const afterReconcileRows = await db.select().from(agents).where(eq(agents.domainId, created.id));
    expect(afterReconcileRows.filter((row) => readBuiltInAgentMarker(row.metadata)?.key === "reflection-coach")).toHaveLength(1);
  });

  it("archives domains by pausing runnable agents and cancelling active runs", async () => {
    const domainId = randomUUID();
    const runningAgentId = randomUUID();
    const idleAgentId = randomUUID();
    const errorAgentId = randomUUID();
    const pausedAgentId = randomUUID();
    const pendingAgentId = randomUUID();
    const terminatedAgentId = randomUUID();
    const wakeupRequestId = randomUUID();
    const runId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Archive Test Co",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values([
      {
        id: runningAgentId,
        domainId,
        name: "Running Agent",
        role: "engineer",
        status: "running",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: idleAgentId,
        domainId,
        name: "Idle Agent",
        role: "engineer",
        status: "idle",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: errorAgentId,
        domainId,
        name: "Error Agent",
        role: "engineer",
        status: "error",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: pausedAgentId,
        domainId,
        name: "Paused Agent",
        role: "engineer",
        status: "paused",
        pauseReason: "manual",
        pausedAt: new Date("2026-06-01T00:00:00Z"),
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: pendingAgentId,
        domainId,
        name: "Pending Agent",
        role: "engineer",
        status: "pending_approval",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: terminatedAgentId,
        domainId,
        name: "Terminated Agent",
        role: "engineer",
        status: "terminated",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
    ]);

    await db.insert(agentWakeupRequests).values({
      id: wakeupRequestId,
      domainId,
      agentId: runningAgentId,
      source: "timer",
      status: "queued",
    });

    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId: runningAgentId,
      invocationSource: "timer",
      status: "running",
      wakeupRequestId,
    });

    const archived = await domainService(db).archive(domainId, {
      actorType: "user",
      actorId: "test-user",
      agentId: null,
      runId: null,
    });

    expect(archived?.status).toBe("archived");

    const archiveActivity = await db
      .select({
        actorType: activityLog.actorType,
        actorId: activityLog.actorId,
        details: activityLog.details,
      })
      .from(activityLog)
      .where(and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.action, "domain.archived"),
      ));
    expect(archiveActivity).toHaveLength(1);
    expect(archiveActivity[0]).toMatchObject({
      actorType: "user",
      actorId: "test-user",
      details: { agentsPaused: 3, runsCancelled: 1 },
    });

    const rows = await db
      .select({
        id: agents.id,
        status: agents.status,
        pauseReason: agents.pauseReason,
      })
      .from(agents);

    const byId = new Map(rows.map((row) => [row.id, row]));
    expect(byId.get(runningAgentId)).toMatchObject({ status: "paused", pauseReason: "domain_archived" });
    expect(byId.get(idleAgentId)).toMatchObject({ status: "paused", pauseReason: "domain_archived" });
    expect(byId.get(errorAgentId)).toMatchObject({ status: "paused", pauseReason: "domain_archived" });
    expect(byId.get(pausedAgentId)).toMatchObject({ status: "paused", pauseReason: "manual" });
    expect(byId.get(pendingAgentId)).toMatchObject({ status: "pending_approval", pauseReason: null });
    expect(byId.get(terminatedAgentId)).toMatchObject({ status: "terminated", pauseReason: null });

    const run = await db
      .select({
        status: heartbeatRuns.status,
        error: heartbeatRuns.error,
      })
      .from(heartbeatRuns)
      .then((result) => result[0] ?? null);
    expect(run).toMatchObject({
      status: "cancelled",
      error: "Cancelled because the domain was archived",
    });

    const wakeup = await db
      .select({
        status: agentWakeupRequests.status,
        error: agentWakeupRequests.error,
      })
      .from(agentWakeupRequests)
      .then((result) => result[0] ?? null);
    expect(wakeup).toMatchObject({
      status: "cancelled",
      error: "Cancelled because the domain was archived",
    });
  });

  it("reactivates only agents paused because the domain was archived", async () => {
    const domainId = randomUUID();
    const archivedPausedAgentId = randomUUID();
    const manualPausedAgentId = randomUUID();
    const pendingAgentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Reactivate Test Co",
      status: "archived",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values([
      {
        id: archivedPausedAgentId,
        domainId,
        name: "Archived Paused Agent",
        role: "engineer",
        status: "paused",
        pauseReason: "domain_archived",
        pausedAt: new Date("2026-06-01T00:00:00Z"),
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: manualPausedAgentId,
        domainId,
        name: "Manual Paused Agent",
        role: "engineer",
        status: "paused",
        pauseReason: "manual",
        pausedAt: new Date("2026-06-01T00:00:00Z"),
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: pendingAgentId,
        domainId,
        name: "Pending Approval Agent",
        role: "engineer",
        status: "pending_approval",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
    ]);

    const reactivated = await domainService(db).update(
      domainId,
      { status: "active" },
      { actorType: "user", actorId: "test-user", agentId: null, runId: null },
    );

    expect(reactivated?.status).toBe("active");

    const reactivateActivity = await db
      .select({
        actorType: activityLog.actorType,
        actorId: activityLog.actorId,
        details: activityLog.details,
      })
      .from(activityLog)
      .where(and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.action, "domain.reactivated"),
      ));
    expect(reactivateActivity).toHaveLength(1);
    expect(reactivateActivity[0]).toMatchObject({
      actorType: "user",
      actorId: "test-user",
      details: { agentsRestored: 1 },
    });

    const rows = await db
      .select({
        id: agents.id,
        status: agents.status,
        pauseReason: agents.pauseReason,
        pausedAt: agents.pausedAt,
      })
      .from(agents);

    const byId = new Map(rows.map((row) => [row.id, row]));
    expect(byId.get(archivedPausedAgentId)).toMatchObject({
      status: "idle",
      pauseReason: null,
      pausedAt: null,
    });
    expect(byId.get(manualPausedAgentId)).toMatchObject({
      status: "paused",
      pauseReason: "manual",
    });
    expect(byId.get(pendingAgentId)).toMatchObject({
      status: "pending_approval",
      pauseReason: null,
    });
  });

  it("runs the archive cascade when update() transitions a domain to archived", async () => {
    const domainId = randomUUID();
    const runningAgentId = randomUUID();
    const idleAgentId = randomUUID();
    const pendingAgentId = randomUUID();
    const wakeupRequestId = randomUUID();
    const runId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Update Archive Test Co",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values([
      {
        id: runningAgentId,
        domainId,
        name: "Running Agent",
        role: "engineer",
        status: "running",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: idleAgentId,
        domainId,
        name: "Idle Agent",
        role: "engineer",
        status: "idle",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: pendingAgentId,
        domainId,
        name: "Pending Agent",
        role: "engineer",
        status: "pending_approval",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
    ]);

    await db.insert(agentWakeupRequests).values({
      id: wakeupRequestId,
      domainId,
      agentId: runningAgentId,
      source: "timer",
      status: "queued",
    });

    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId: runningAgentId,
      invocationSource: "timer",
      status: "running",
      wakeupRequestId,
    });

    const archived = await domainService(db).update(
      domainId,
      { status: "archived" },
      { actorType: "user", actorId: "test-user", agentId: null, runId: null },
    );

    expect(archived?.status).toBe("archived");

    const rows = await db
      .select({ id: agents.id, status: agents.status, pauseReason: agents.pauseReason })
      .from(agents);
    const byId = new Map(rows.map((row) => [row.id, row]));
    expect(byId.get(runningAgentId)).toMatchObject({ status: "paused", pauseReason: "domain_archived" });
    expect(byId.get(idleAgentId)).toMatchObject({ status: "paused", pauseReason: "domain_archived" });
    expect(byId.get(pendingAgentId)).toMatchObject({ status: "pending_approval", pauseReason: null });

    const run = await db
      .select({ status: heartbeatRuns.status, error: heartbeatRuns.error })
      .from(heartbeatRuns)
      .then((result) => result[0] ?? null);
    expect(run).toMatchObject({
      status: "cancelled",
      error: "Cancelled because the domain was archived",
    });

    const archiveActivity = await db
      .select({
        actorType: activityLog.actorType,
        actorId: activityLog.actorId,
        details: activityLog.details,
      })
      .from(activityLog)
      .where(and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.action, "domain.archived"),
      ));
    expect(archiveActivity).toHaveLength(1);
    expect(archiveActivity[0]).toMatchObject({
      actorType: "user",
      actorId: "test-user",
      details: { agentsPaused: 2, runsCancelled: 1 },
    });
  });

  it("reactivates domain_archived agents even when going via paused state (archived → paused → active)", async () => {
    const domainId = randomUUID();
    const archivedPausedAgentId = randomUUID();
    const manualPausedAgentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Indirect Reactivate Test Co",
      status: "paused",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values([
      {
        id: archivedPausedAgentId,
        domainId,
        name: "Archived Paused Agent",
        role: "engineer",
        status: "paused",
        pauseReason: "domain_archived",
        pausedAt: new Date("2026-06-01T00:00:00Z"),
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
      {
        id: manualPausedAgentId,
        domainId,
        name: "Manual Paused Agent",
        role: "engineer",
        status: "paused",
        pauseReason: "manual",
        pausedAt: new Date("2026-06-01T00:00:00Z"),
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        permissions: {},
      },
    ]);

    const reactivated = await domainService(db).update(
      domainId,
      { status: "active" },
      { actorType: "user", actorId: "test-user", agentId: null, runId: null },
    );

    expect(reactivated?.status).toBe("active");

    const rows = await db
      .select({ id: agents.id, status: agents.status, pauseReason: agents.pauseReason })
      .from(agents);
    const byId = new Map(rows.map((row) => [row.id, row]));
    expect(byId.get(archivedPausedAgentId)).toMatchObject({ status: "idle", pauseReason: null });
    expect(byId.get(manualPausedAgentId)).toMatchObject({ status: "paused", pauseReason: "manual" });

    const reactivateActivity = await db
      .select({ details: activityLog.details })
      .from(activityLog)
      .where(and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.action, "domain.reactivated"),
      ));
    expect(reactivateActivity).toHaveLength(1);
    expect(reactivateActivity[0]).toMatchObject({ details: { agentsRestored: 1 } });
  });

  it("emits domain.reactivated for archived → active even when no agents need restoring", async () => {
    const domainId = randomUUID();
    const terminatedAgentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Empty Reactivate Co",
      status: "archived",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values({
      id: terminatedAgentId,
      domainId,
      name: "Terminated Agent",
      role: "engineer",
      status: "terminated",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });

    const reactivated = await domainService(db).update(
      domainId,
      { status: "active" },
      { actorType: "user", actorId: "test-user", agentId: null, runId: null },
    );

    expect(reactivated?.status).toBe("active");

    const reactivateActivity = await db
      .select({ details: activityLog.details })
      .from(activityLog)
      .where(and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.action, "domain.reactivated"),
      ));
    expect(reactivateActivity).toHaveLength(1);
    expect(reactivateActivity[0]).toMatchObject({ details: { agentsRestored: 0 } });
  });

  it("does not emit domain.reactivated when paused → active restores no archive-paused agents", async () => {
    const domainId = randomUUID();
    const manualPausedAgentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Plain Unpause Co",
      status: "paused",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values({
      id: manualPausedAgentId,
      domainId,
      name: "Manual Paused Agent",
      role: "engineer",
      status: "paused",
      pauseReason: "manual",
      pausedAt: new Date("2026-06-01T00:00:00Z"),
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });

    const reactivated = await domainService(db).update(
      domainId,
      { status: "active" },
      { actorType: "user", actorId: "test-user", agentId: null, runId: null },
    );

    expect(reactivated?.status).toBe("active");

    const reactivateActivity = await db
      .select({ id: activityLog.id })
      .from(activityLog)
      .where(and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.action, "domain.reactivated"),
      ));
    expect(reactivateActivity).toHaveLength(0);

    const agent = await db
      .select({ status: agents.status, pauseReason: agents.pauseReason })
      .from(agents)
      .then((rows) => rows[0] ?? null);
    expect(agent).toMatchObject({ status: "paused", pauseReason: "manual" });
  });

  it("cancels orphan queued wakeup requests with no runId during archive", async () => {
    const domainId = randomUUID();
    const agentId = randomUUID();
    const orphanWakeupId = randomUUID();
    const runWakeupId = randomUUID();
    const runId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Orphan Wakeup Co",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "Idle Agent",
      role: "engineer",
      status: "idle",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });

    await db.insert(agentWakeupRequests).values([
      {
        id: orphanWakeupId,
        domainId,
        agentId,
        source: "automation",
        status: "queued",
      },
      {
        id: runWakeupId,
        domainId,
        agentId,
        source: "timer",
        status: "queued",
      },
    ]);

    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId,
      invocationSource: "timer",
      status: "running",
      wakeupRequestId: runWakeupId,
    });

    const archived = await domainService(db).archive(domainId, {
      actorType: "user",
      actorId: "test-user",
      agentId: null,
      runId: null,
    });
    expect(archived?.status).toBe("archived");

    const wakeups = await db
      .select({
        id: agentWakeupRequests.id,
        status: agentWakeupRequests.status,
        error: agentWakeupRequests.error,
      })
      .from(agentWakeupRequests);
    const byId = new Map(wakeups.map((row) => [row.id, row]));
    expect(byId.get(orphanWakeupId)).toMatchObject({
      status: "cancelled",
      error: "Cancelled because the domain was archived",
    });
    expect(byId.get(runWakeupId)).toMatchObject({
      status: "cancelled",
      error: "Cancelled because the domain was archived",
    });
  });

  it("archive() is idempotent — re-archiving emits no second cascade or activity entry", async () => {
    const domainId = randomUUID();
    const agentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Idempotent Archive Test Co",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "Idle Agent",
      role: "engineer",
      status: "idle",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });

    const actor = { actorType: "user" as const, actorId: "test-user", agentId: null, runId: null };
    const first = await domainService(db).archive(domainId, actor);
    expect(first?.status).toBe("archived");

    const second = await domainService(db).archive(domainId, actor);
    expect(second?.status).toBe("archived");

    const archiveActivity = await db
      .select({ details: activityLog.details })
      .from(activityLog)
      .where(and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.action, "domain.archived"),
      ));
    expect(archiveActivity).toHaveLength(1);
    expect(archiveActivity[0]).toMatchObject({ details: { agentsPaused: 1, runsCancelled: 0 } });
  });

  it("runs the archive cascade when update() transitions a paused domain to archived", async () => {
    const domainId = randomUUID();
    const idleAgentId = randomUUID();
    const runId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paused To Archived Test Co",
      status: "paused",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values({
      id: idleAgentId,
      domainId,
      name: "Idle Agent",
      role: "engineer",
      status: "idle",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });

    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId: idleAgentId,
      invocationSource: "timer",
      status: "queued",
    });

    const archived = await domainService(db).update(
      domainId,
      { status: "archived" },
      { actorType: "user", actorId: "test-user", agentId: null, runId: null },
    );

    expect(archived?.status).toBe("archived");

    const agent = await db
      .select({ status: agents.status, pauseReason: agents.pauseReason })
      .from(agents)
      .then((rows) => rows[0] ?? null);
    expect(agent).toMatchObject({ status: "paused", pauseReason: "domain_archived" });

    const run = await db
      .select({ status: heartbeatRuns.status })
      .from(heartbeatRuns)
      .then((rows) => rows[0] ?? null);
    expect(run?.status).toBe("cancelled");

    const archiveActivity = await db
      .select({ details: activityLog.details })
      .from(activityLog)
      .where(and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.action, "domain.archived"),
      ));
    expect(archiveActivity).toHaveLength(1);
    expect(archiveActivity[0]).toMatchObject({
      details: { agentsPaused: 1, runsCancelled: 1 },
    });
  });
});

import { randomUUID } from "node:crypto";
import { eq, sql } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  activityLog,
  agents,
  domains,
  createDb,
  executionWorkspaces,
  heartbeatRuns,
  instanceSettings,
  issueComments,
  issues,
  workflowAutomationExecutions,
  workflowLifeAdminBlockers,
  workflowLifeAdminIssueLinks,
  workflowLifeAdminEvents,
  workflowLifeAdmin,
  workflowStages,
  workflowTransitions,
  workflows,
  projectWorkspaces,
  projects,
  routineRuns,
  routines,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import {
  WORKFLOW_AUTOMATION_DEFAULT_TITLE_TEMPLATE,
  workflowService,
  type WorkflowActor,
} from "../services/workflows.ts";
import { routineService } from "../services/routines.ts";
import { instanceSettingsService } from "../services/instance-settings.ts";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres workflow service tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("workflowService", () => {
  let db!: ReturnType<typeof createDb>;
  let svc!: ReturnType<typeof workflowService>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  const userActor: WorkflowActor = { type: "user", userId: "board-user" };
  const noopHeartbeat = { wakeup: async () => null };

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-workflows-service-");
    db = createDb(tempDb.connectionString);
    svc = workflowService(db, { heartbeat: noopHeartbeat });
  }, 20_000);

  afterEach(async () => {
    await db.delete(workflowAutomationExecutions);
    await db.delete(workflowLifeAdminBlockers);
    await db.delete(workflowLifeAdminIssueLinks);
    await db.delete(workflowLifeAdminEvents);
    await db.delete(workflowLifeAdmin);
    await db.delete(workflowTransitions);
    await db.delete(workflowStages);
    await db.delete(workflows);
    await db.delete(issueComments);
    await db.delete(activityLog);
    await db.delete(routineRuns);
    await db.delete(heartbeatRuns);
    await db.delete(issues);
    await db.delete(executionWorkspaces);
    await db.delete(routines);
    await db.delete(projectWorkspaces);
    await db.delete(projects);
    await db.delete(agents);
    await db.delete(domains);
    await db.delete(instanceSettings);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  async function seedDomain() {
    const [domain] = await db.insert(domains).values({
      name: "Workflow Co",
      issuePrefix: `P${randomUUID().replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      defaultResponsibleUserId: "board-user",
    }).returning();
    return domain!;
  }

  async function seedWorkflow(options?: { enforceTransitions?: boolean }) {
    const domain = await seedDomain();
    const workflow = await svc.createWorkflow({
      domainId: domain.id,
      key: `content-${randomUUID().slice(0, 8)}`,
      name: "Content",
      enforceTransitions: options?.enforceTransitions ?? false,
      actor: userActor,
    });
    const stages = await svc.listStages(domain.id, workflow.id);
    return { domain, workflow, stages, byKey: new Map(stages.map((stage) => [stage.key, stage])) };
  }

  async function seedRoutine(domainId: string, title = "Routine") {
    const [agent] = await db.insert(agents).values({
      domainId,
      name: `${title} Agent`,
      role: "engineer",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    }).returning();
    return routineService(db, { heartbeat: noopHeartbeat }).create(domainId, {
      projectId: null,
      goalId: null,
      parentIssueId: null,
      title,
      description: null,
      assigneeAgentId: agent!.id,
      priority: "medium",
      status: "active",
      concurrencyPolicy: "always_enqueue",
      catchUpPolicy: "skip_missed",
    }, {});
  }

  async function eventCount(lifeAdminId: string) {
    const [{ count }] = await db
      .select({ count: sql<number>`count(*)::int` })
      .from(workflowLifeAdminEvents)
      .where(eq(workflowLifeAdminEvents.lifeAdminId, lifeAdminId));
    return count ?? 0;
  }

  async function seedLinkedIssue(input: {
    domainId: string;
    lifeAdminId: string;
    role: "origin" | "conversation" | "work" | "automation";
    status?: "backlog" | "todo" | "in_progress" | "in_review" | "done" | "blocked" | "cancelled";
    title?: string;
  }) {
    const [issue] = await db.insert(issues).values({
      domainId: input.domainId,
      title: input.title ?? `${input.role} issue`,
      status: input.status ?? "todo",
      priority: "medium",
    }).returning();
    await db.insert(workflowLifeAdminIssueLinks).values({
      domainId: input.domainId,
      lifeAdminId: input.lifeAdminId,
      issueId: issue!.id,
      role: input.role,
    });
    return issue!;
  }

  it("seeds default stages and protects non-empty stage deletion", async () => {
    const { domain, workflow, byKey } = await seedWorkflow();

    expect([...byKey.keys()]).toEqual(["intake", "in_progress", "review", "done", "cancelled"]);
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "stage-delete",
      title: "Stage delete guard",
      actor: userActor,
    });

    await expect(
      svc.deleteStage({ domainId: domain.id, workflowId: workflow.id, stageId: byKey.get("intake")!.id }),
    ).rejects.toMatchObject({ status: 422, details: { code: "stage_has_life_admin" } });

    await svc.deleteStage({
      domainId: domain.id,
      workflowId: workflow.id,
      stageId: byKey.get("intake")!.id,
      moveLifeAdminToStageId: byKey.get("in_progress")!.id,
    });
    const [moved] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, created.life_admin.id));
    expect(moved!.stageId).toBe(byKey.get("in_progress")!.id);
  });

  it("updates parent terminal counts when deleting a stage moves child life_admin to done", async () => {
    const { domain, workflow, byKey } = await seedWorkflow();
    const parent = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      stageKey: "in_progress",
      life_adminKey: "delete-stage-parent",
      title: "Delete stage parent",
      actor: userActor,
    });
    const child = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "delete-stage-child",
      title: "Delete stage child",
      parentLifeAdminId: parent.life_admin.id,
      actor: userActor,
    });

    await svc.deleteStage({
      domainId: domain.id,
      workflowId: workflow.id,
      stageId: byKey.get("intake")!.id,
      moveLifeAdminToStageId: byKey.get("done")!.id,
    });

    const [freshParent] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, parent.life_admin.id));
    const [freshChild] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, child.life_admin.id));
    expect(freshParent!.childCount).toBe(1);
    expect(freshParent!.terminalChildCount).toBe(1);
    expect(freshChild!.terminalKind).toBe("done");

    await expect(
      svc.transitionLifeAdmin({
        domainId: domain.id,
        lifeAdminId: parent.life_admin.id,
        toStageKey: "done",
        expectedVersion: parent.life_admin.version,
        actor: userActor,
      }),
    ).resolves.toMatchObject({ life_admin: { terminalKind: "done" } });
  });

  it("implements idempotent single and batch ingest", async () => {
    const { domain, workflow } = await seedWorkflow();

    const first = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "release-1",
      title: "Release 1",
      actor: userActor,
    });
    const second = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "release-1",
      title: "Duplicate title is ignored",
      actor: userActor,
    });

    expect(first.created).toBe(true);
    expect(second.created).toBe(false);
    expect(second.life_admin.id).toBe(first.life_admin.id);
    expect(await eventCount(first.life_admin.id)).toBe(1);

    await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "existing-2",
      title: "Existing 2",
      actor: userActor,
    });
    const batch = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      actor: userActor,
      items: [
        { life_adminKey: "new-1", title: "New 1" },
        { life_adminKey: "new-2", title: "New 2" },
        { life_adminKey: "release-1", title: "Existing 1" },
        { life_adminKey: "new-3", title: "New 3" },
        { life_adminKey: "existing-2", title: "Existing 2 again" },
      ],
    });

    expect(batch).toHaveLength(5);
    expect(batch.filter((item) => item.ok && item.created)).toHaveLength(3);
    const [{ count }] = await db.select({ count: sql<number>`count(*)::int` }).from(workflowLifeAdmin);
    expect(count).toBe(5);
  });

  it("persists workspaceRef during ingest", async () => {
    const { domain, workflow } = await seedWorkflow();
    const workspaceRef = {
      workspacePath: "exports/workflow-life_admin",
      name: "Workflow life_admin files",
    };

    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "workspace-ref",
      title: "Workspace ref",
      workspaceRef,
      actor: userActor,
    });

    expect(created.life_admin.workspaceRef).toEqual(workspaceRef);
    const [stored] = await db
      .select({ workspaceRef: workflowLifeAdmin.workspaceRef })
      .from(workflowLifeAdmin)
      .where(eq(workflowLifeAdmin.id, created.life_admin.id));
    expect(stored?.workspaceRef).toEqual(workspaceRef);
  });

  it("rejects stale content PATCH without writing an event", async () => {
    const { domain, workflow } = await seedWorkflow();
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "patch",
      title: "Patch me",
      actor: userActor,
    });
    await svc.patchLifeAdminContent({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      title: "Patched",
      expectedVersion: 1,
      actor: userActor,
    });
    const before = await eventCount(created.life_admin.id);

    await expect(
      svc.patchLifeAdminContent({
        domainId: domain.id,
        lifeAdminId: created.life_admin.id,
        title: "Stale",
        expectedVersion: 1,
        actor: userActor,
      }),
    ).rejects.toMatchObject({ status: 409, details: { code: "version_conflict", version: 2 } });
    expect(await eventCount(created.life_admin.id)).toBe(before);
  });

  it("lets exactly one parallel transition with the same expectedVersion succeed", async () => {
    const { domain, workflow } = await seedWorkflow();
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "parallel",
      title: "Parallel transition",
      actor: userActor,
    });

    const attempts = await Promise.allSettled([
      svc.transitionLifeAdmin({
        domainId: domain.id,
        lifeAdminId: created.life_admin.id,
        toStageKey: "in_progress",
        expectedVersion: 1,
        actor: userActor,
      }),
      svc.transitionLifeAdmin({
        domainId: domain.id,
        lifeAdminId: created.life_admin.id,
        toStageKey: "review",
        expectedVersion: 1,
        actor: userActor,
      }),
    ]);

    expect(attempts.filter((attempt) => attempt.status === "fulfilled")).toHaveLength(1);
    expect(attempts.filter((attempt) => attempt.status === "rejected")).toHaveLength(1);
    const [row] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, created.life_admin.id));
    expect(row!.version).toBe(2);
    expect(await eventCount(created.life_admin.id)).toBe(2);
  });

  it("enforces active leases and lets the holder transition with the lease token", async () => {
    const { domain, workflow } = await seedWorkflow();
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "lease",
      title: "Leased life_admin",
      actor: userActor,
    });
    const owner: WorkflowActor = { type: "user", userId: "owner" };
    const other: WorkflowActor = { type: "user", userId: "other" };

    const claimed = await svc.claimLifeAdmin({ domainId: domain.id, lifeAdminId: created.life_admin.id, actor: owner });
    await expect(svc.claimLifeAdmin({ domainId: domain.id, lifeAdminId: created.life_admin.id, actor: other })).rejects.toMatchObject({
      status: 409,
      details: { code: "lease_held" },
    });
    await expect(
      svc.transitionLifeAdmin({
        domainId: domain.id,
        lifeAdminId: created.life_admin.id,
        toStageKey: "in_progress",
        expectedVersion: 1,
        actor: other,
      }),
    ).rejects.toMatchObject({ status: 409, details: { code: "lease_held" } });

    const transitioned = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "in_progress",
      expectedVersion: 1,
      leaseToken: claimed.leaseToken,
      actor: owner,
    });
    expect(transitioned.life_admin.version).toBe(2);
    expect(await eventCount(created.life_admin.id)).toBe(3);
  });

  it("expires leases on read before a new claim", async () => {
    const { domain, workflow } = await seedWorkflow();
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "expired-lease",
      title: "Expired lease",
      actor: userActor,
    });
    await db.update(workflowLifeAdmin).set({
      leaseOwnerType: "user",
      leaseUserId: "old-owner",
      leaseToken: randomUUID(),
      leaseExpiresAt: new Date(Date.now() - 5_000),
    }).where(eq(workflowLifeAdmin.id, created.life_admin.id));

    const claimed = await svc.claimLifeAdmin({ domainId: domain.id, lifeAdminId: created.life_admin.id, actor: { type: "user", userId: "new-owner" } });

    expect(claimed.leaseUserId).toBe("new-owner");
    const events = await svc.listLifeAdminEvents(domain.id, created.life_admin.id);
    expect(events.map((event) => event.type)).toEqual(["ingested", "lease_expired", "claimed"]);
  });

  it("enforces transition edges only when enforceTransitions is enabled", async () => {
    const { domain, workflow } = await seedWorkflow({ enforceTransitions: true });
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "edges",
      title: "Transition edges",
      actor: userActor,
    });

    await expect(
      svc.transitionLifeAdmin({
        domainId: domain.id,
        lifeAdminId: created.life_admin.id,
        toStageKey: "done",
        expectedVersion: 1,
        actor: userActor,
      }),
    ).rejects.toMatchObject({ status: 409, details: { code: "transition_not_allowed" } });

    await db.update(workflows).set({ enforceTransitions: false }).where(eq(workflows.id, workflow.id));
    const moved = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "done",
      expectedVersion: 1,
      actor: userActor,
    });
    expect(moved.life_admin.terminalKind).toBe("done");
  });

  it("blocks transitions while blockers are not done", async () => {
    const { domain, workflow } = await seedWorkflow();
    const blocked = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "blocked",
      title: "Blocked life_admin",
      actor: userActor,
    });
    const blocker = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "blocker",
      title: "Blocking life_admin",
      actor: userActor,
    });
    await svc.replaceBlockers({
      domainId: domain.id,
      lifeAdminId: blocked.life_admin.id,
      blockedByLifeAdminIds: [blocker.life_admin.id],
      actor: userActor,
    });

    await expect(
      svc.transitionLifeAdmin({
        domainId: domain.id,
        lifeAdminId: blocked.life_admin.id,
        toStageKey: "in_progress",
        expectedVersion: 1,
        actor: userActor,
      }),
    ).rejects.toMatchObject({ status: 409, details: { code: "blocked" } });

    const reviewMove = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: blocked.life_admin.id,
      toStageKey: "review",
      expectedVersion: 1,
      actor: userActor,
    });
    expect(reviewMove.life_admin.version).toBe(2);

    await expect(
      svc.transitionLifeAdmin({
        domainId: domain.id,
        lifeAdminId: blocked.life_admin.id,
        toStageKey: "done",
        expectedVersion: 2,
        actor: userActor,
      }),
    ).rejects.toMatchObject({ status: 409, details: { code: "blocked" } });

    await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: blocker.life_admin.id,
      toStageKey: "done",
      expectedVersion: 1,
      actor: userActor,
    });
    const moved = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: blocked.life_admin.id,
      toStageKey: "in_progress",
      expectedVersion: 2,
      actor: userActor,
    });
    expect(moved.life_admin.version).toBe(3);
    const events = await svc.listLifeAdminEvents(domain.id, blocked.life_admin.id);
    expect(events.map((event) => event.type)).toContain("blockers_resolved");
  });

  it("emits blockers_resolved once for each fresh blocker set", async () => {
    const { domain, workflow } = await seedWorkflow();
    const blocked = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "blocked-again",
      title: "Blocked again",
      actor: userActor,
    });
    const firstBlocker = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "first-blocker",
      title: "First blocker",
      actor: userActor,
    });
    const secondBlocker = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "second-blocker",
      title: "Second blocker",
      actor: userActor,
    });
    const workIssue = await seedLinkedIssue({
      domainId: domain.id,
      lifeAdminId: blocked.life_admin.id,
      role: "work",
      title: "Blocked work",
    });

    await svc.replaceBlockers({
      domainId: domain.id,
      lifeAdminId: blocked.life_admin.id,
      blockedByLifeAdminIds: [firstBlocker.life_admin.id],
      actor: userActor,
    });
    await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: firstBlocker.life_admin.id,
      toStageKey: "done",
      expectedVersion: 1,
      actor: userActor,
    });

    await svc.replaceBlockers({
      domainId: domain.id,
      lifeAdminId: blocked.life_admin.id,
      blockedByLifeAdminIds: [secondBlocker.life_admin.id],
      actor: userActor,
    });
    await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: secondBlocker.life_admin.id,
      toStageKey: "done",
      expectedVersion: 1,
      actor: userActor,
    });

    const events = await svc.listLifeAdminEvents(domain.id, blocked.life_admin.id);
    expect(events.filter((event) => event.type === "blockers_resolved")).toHaveLength(2);
    const comments = await db.select().from(issueComments).where(eq(issueComments.issueId, workIssue.id));
    expect(comments).toHaveLength(2);
    expect(comments.map((comment) => comment.body).join("\n")).toContain(firstBlocker.life_admin.id);
    expect(comments.map((comment) => comment.body).join("\n")).toContain(secondBlocker.life_admin.id);
  });

  it("keeps cancelled blockers unsatisfied until replaced", async () => {
    const { domain, workflow } = await seedWorkflow();
    const blocked = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "blocked-cancelled",
      title: "Blocked life_admin",
      actor: userActor,
    });
    const blocker = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "blocker-cancelled",
      title: "Cancelled blocker",
      actor: userActor,
    });
    await svc.replaceBlockers({
      domainId: domain.id,
      lifeAdminId: blocked.life_admin.id,
      blockedByLifeAdminIds: [blocker.life_admin.id],
      actor: userActor,
    });
    await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: blocker.life_admin.id,
      toStageKey: "cancelled",
      expectedVersion: 1,
      actor: userActor,
    });

    await expect(
      svc.transitionLifeAdmin({
        domainId: domain.id,
        lifeAdminId: blocked.life_admin.id,
        toStageKey: "in_progress",
        expectedVersion: 1,
        actor: userActor,
      }),
    ).rejects.toMatchObject({ status: 409, details: { code: "blocked" } });

    await svc.replaceBlockers({ domainId: domain.id, lifeAdminId: blocked.life_admin.id, blockedByLifeAdminIds: [], actor: userActor });
    const moved = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: blocked.life_admin.id,
      toStageKey: "in_progress",
      expectedVersion: 1,
      actor: userActor,
    });
    expect(moved.life_admin.version).toBe(2);
  });

  it("posts upstream drift notices to active dependent work issues only", async () => {
    const { domain, workflow } = await seedWorkflow();
    const upstream = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "draft",
      title: "Draft",
      actor: userActor,
    });
    const workDependent = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "asset-work",
      title: "Asset work",
      blockedByLifeAdminIds: [upstream.life_admin.id],
      actor: userActor,
    });
    const conversationDependent = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "asset-conversation",
      title: "Asset conversation",
      blockedByLifeAdminIds: [upstream.life_admin.id],
      actor: userActor,
    });
    const workIssue = await seedLinkedIssue({
      domainId: domain.id,
      lifeAdminId: workDependent.life_admin.id,
      role: "work",
      title: "Asset work issue",
    });
    const conversationIssue = await seedLinkedIssue({
      domainId: domain.id,
      lifeAdminId: conversationDependent.life_admin.id,
      role: "conversation",
      title: "Conversation issue",
    });

    const updated = await svc.patchLifeAdminContent({
      domainId: domain.id,
      lifeAdminId: upstream.life_admin.id,
      title: "Draft v2",
      expectedVersion: 1,
      actor: userActor,
    });

    expect(updated.version).toBe(2);
    const workComments = await db.select().from(issueComments).where(eq(issueComments.issueId, workIssue.id));
    expect(workComments).toHaveLength(1);
    expect(workComments[0]!.authorType).toBe("system");
    expect(workComments[0]!.body).toBe(
      `Upstream life_admin [draft](/PAP/workflows/${workflow.id}/life_admin/${upstream.life_admin.id}) changed (v1→v2).`,
    );
    const conversationComments = await db.select().from(issueComments).where(eq(issueComments.issueId, conversationIssue.id));
    expect(conversationComments).toHaveLength(0);
  });

  it("skips upstream drift notices for terminal dependents and dependents without work issues", async () => {
    const { domain, workflow } = await seedWorkflow();
    const upstream = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "source",
      title: "Source",
      actor: userActor,
    });
    const terminalDependent = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      stageKey: "done",
      life_adminKey: "terminal-dependent",
      title: "Terminal dependent",
      actor: userActor,
    });
    await svc.replaceBlockers({
      domainId: domain.id,
      lifeAdminId: terminalDependent.life_admin.id,
      blockedByLifeAdminIds: [upstream.life_admin.id],
      actor: userActor,
    });
    const noWorkDependent = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "no-work-dependent",
      title: "No work dependent",
      blockedByLifeAdminIds: [upstream.life_admin.id],
      actor: userActor,
    });
    const terminalIssue = await seedLinkedIssue({
      domainId: domain.id,
      lifeAdminId: terminalDependent.life_admin.id,
      role: "work",
      title: "Terminal work issue",
    });
    const conversationIssue = await seedLinkedIssue({
      domainId: domain.id,
      lifeAdminId: noWorkDependent.life_admin.id,
      role: "conversation",
      title: "Non-work issue",
    });

    await svc.patchLifeAdminContent({
      domainId: domain.id,
      lifeAdminId: upstream.life_admin.id,
      summary: "Updated source",
      expectedVersion: 1,
      actor: userActor,
    });

    const terminalComments = await db.select().from(issueComments).where(eq(issueComments.issueId, terminalIssue.id));
    expect(terminalComments).toHaveLength(0);
    const conversationComments = await db.select().from(issueComments).where(eq(issueComments.issueId, conversationIssue.id));
    expect(conversationComments).toHaveLength(0);
  });

  it("does not bump versions or notify dependents on no-op content patches", async () => {
    const { domain, workflow } = await seedWorkflow();
    const upstream = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "noop-source",
      title: "No-op source",
      fields: { channel: "blog" },
      actor: userActor,
    });
    const dependent = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "noop-dependent",
      title: "No-op dependent",
      blockedByLifeAdminIds: [upstream.life_admin.id],
      actor: userActor,
    });
    const workIssue = await seedLinkedIssue({
      domainId: domain.id,
      lifeAdminId: dependent.life_admin.id,
      role: "work",
      title: "No-op work issue",
    });
    const beforeEvents = await eventCount(upstream.life_admin.id);

    const patched = await svc.patchLifeAdminContent({
      domainId: domain.id,
      lifeAdminId: upstream.life_admin.id,
      title: "No-op source",
      fields: { channel: "blog" },
      expectedVersion: 1,
      actor: userActor,
    });

    expect(patched.version).toBe(1);
    expect(await eventCount(upstream.life_admin.id)).toBe(beforeEvents);
    const comments = await db.select().from(issueComments).where(eq(issueComments.issueId, workIssue.id));
    expect(comments).toHaveLength(0);
  });

  it("resolves in-batch forward blocker life_admin keys", async () => {
    const { domain, workflow } = await seedWorkflow();

    const results = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      items: [
        { life_adminKey: "tweet", title: "Tweet", blockedByLifeAdminKeys: ["image", "post"] },
        { life_adminKey: "image", title: "Image" },
        { life_adminKey: "post", title: "Post" },
      ],
      actor: userActor,
    });

    expect(results.map((result) => result.ok)).toEqual([true, true, true]);
    const successful = results.filter((result): result is Extract<(typeof results)[number], { ok: true }> => result.ok);
    const byKey = new Map(successful
      .map((result) => [result.life_admin.life_adminKey, result.life_admin.id]));
    const blockers = await db
      .select()
      .from(workflowLifeAdminBlockers)
      .where(eq(workflowLifeAdminBlockers.lifeAdminId, byKey.get("tweet")!));
    expect(blockers.map((row) => row.blockedByLifeAdminId).sort()).toEqual([
      byKey.get("image")!,
      byKey.get("post")!,
    ].sort());
    const events = await svc.listLifeAdminEvents(domain.id, byKey.get("tweet")!);
    const blockersEvent = events.find((event) => event.type === "blockers_set");
    expect(blockersEvent?.payload).toMatchObject({
      blockedByLifeAdminIds: expect.arrayContaining([byKey.get("image")!, byKey.get("post")!]),
      blockedByLifeAdminKeys: ["image", "post"],
    });
  });

  it("resolves blocker life_admin keys against existing life_admin", async () => {
    const { domain, workflow } = await seedWorkflow();
    const asset = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "asset",
      title: "Asset",
      actor: userActor,
    });

    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "tweet",
      title: "Tweet",
      blockedByLifeAdminKeys: ["asset"],
      actor: userActor,
    });

    const blockers = await db
      .select()
      .from(workflowLifeAdminBlockers)
      .where(eq(workflowLifeAdminBlockers.lifeAdminId, created.life_admin.id));
    expect(blockers.map((row) => row.blockedByLifeAdminId)).toEqual([asset.life_admin.id]);
  });

  it("fails only unresolved blocker-key rows in batch ingest", async () => {
    const { domain, workflow } = await seedWorkflow();

    const results = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      items: [
        { life_adminKey: "ok", title: "OK" },
        { life_adminKey: "missing", title: "Missing", blockedByLifeAdminKeys: ["does-not-exist"] },
        { life_adminKey: "after", title: "After" },
      ],
      actor: userActor,
    });

    expect(results[0]).toMatchObject({ ok: true });
    expect(results[1]).toMatchObject({
      ok: false,
      life_adminKey: "missing",
      error: {
        status: 404,
        details: { code: "blocker_life_admin_key_not_found", missingLifeAdminKeys: ["does-not-exist"] },
      },
    });
    expect(results[2]).toMatchObject({ ok: true });
    const rows = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.workflowId, workflow.id));
    expect(rows.map((row) => row.life_adminKey).sort()).toEqual(["after", "ok"]);
  });

  it("rejects blocker cycles declared by batch life_admin keys", async () => {
    const { domain, workflow } = await seedWorkflow();

    const results = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      items: [
        { life_adminKey: "a", title: "A", blockedByLifeAdminKeys: ["b"] },
        { life_adminKey: "b", title: "B", blockedByLifeAdminKeys: ["a"] },
      ],
      actor: userActor,
    });

    expect(results).toEqual([
      expect.objectContaining({
        ok: false,
        life_adminKey: "a",
        error: expect.objectContaining({ status: 409, details: { code: "blocker_cycle", blockedByLifeAdminKeys: ["b"] } }),
      }),
      expect.objectContaining({
        ok: false,
        life_adminKey: "b",
        error: expect.objectContaining({ status: 409, details: { code: "blocker_cycle", blockedByLifeAdminKeys: ["a"] } }),
      }),
    ]);
    const rows = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.workflowId, workflow.id));
    expect(rows).toHaveLength(0);
  });

  it("rejects parent and blocker cycles and enforces parent depth", async () => {
    const { domain, workflow } = await seedWorkflow();
    const a = await svc.ingestLifeAdmin({ domainId: domain.id, workflowId: workflow.id, life_adminKey: "a", title: "A", actor: userActor });
    const b = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "b",
      title: "B",
      parentLifeAdminId: a.life_admin.id,
      actor: userActor,
    });

    await expect(
      svc.patchLifeAdminContent({
        domainId: domain.id,
        lifeAdminId: a.life_admin.id,
        parentLifeAdminId: b.life_admin.id,
        expectedVersion: 1,
        actor: userActor,
      }),
    ).rejects.toMatchObject({ status: 409, details: { code: "parent_cycle" } });

    await svc.replaceBlockers({ domainId: domain.id, lifeAdminId: a.life_admin.id, blockedByLifeAdminIds: [b.life_admin.id], actor: userActor });
    await expect(
      svc.replaceBlockers({ domainId: domain.id, lifeAdminId: b.life_admin.id, blockedByLifeAdminIds: [a.life_admin.id], actor: userActor }),
    ).rejects.toMatchObject({ status: 409, details: { code: "blocker_cycle" } });

    let parentLifeAdminId: string | null = null;
    for (let index = 0; index < 32; index += 1) {
      const created = await svc.ingestLifeAdmin({
        domainId: domain.id,
        workflowId: workflow.id,
        life_adminKey: `chain-${index}`,
        title: `Chain ${index}`,
        parentLifeAdminId,
        actor: userActor,
      });
      parentLifeAdminId = created.life_admin.id;
    }
    await expect(
      svc.ingestLifeAdmin({
        domainId: domain.id,
        workflowId: workflow.id,
        life_adminKey: "too-deep",
        title: "Too deep",
        parentLifeAdminId,
        actor: userActor,
      }),
    ).rejects.toMatchObject({ status: 422, details: { code: "parent_depth_exceeded" } });
  });

  it("rolls up a three-level tree, updates counters, and emits children_terminal once", async () => {
    const { domain, workflow } = await seedWorkflow();
    const root = await svc.ingestLifeAdmin({ domainId: domain.id, workflowId: workflow.id, life_adminKey: "root", title: "Root", actor: userActor });
    const [linkedIssue] = await db.insert(issues).values({
      domainId: domain.id,
      title: "Root conversation",
      status: "todo",
      priority: "medium",
    }).returning();
    await db.insert(workflowLifeAdminIssueLinks).values({
      domainId: domain.id,
      lifeAdminId: root.life_admin.id,
      issueId: linkedIssue!.id,
      role: "conversation",
    });
    const childA = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "child-a",
      title: "Child A",
      parentLifeAdminId: root.life_admin.id,
      actor: userActor,
    });
    const childB = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "child-b",
      title: "Child B",
      parentLifeAdminId: root.life_admin.id,
      actor: userActor,
    });
    const childC = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "child-c",
      title: "Child C",
      parentLifeAdminId: root.life_admin.id,
      actor: userActor,
    });
    const grandA = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "grand-a",
      title: "Grand A",
      parentLifeAdminId: childA.life_admin.id,
      actor: userActor,
    });
    const grandB = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "grand-b",
      title: "Grand B",
      parentLifeAdminId: childA.life_admin.id,
      actor: userActor,
    });

    await svc.transitionLifeAdmin({ domainId: domain.id, lifeAdminId: childB.life_admin.id, toStageKey: "done", expectedVersion: 1, actor: userActor });
    await svc.transitionLifeAdmin({ domainId: domain.id, lifeAdminId: childC.life_admin.id, toStageKey: "done", expectedVersion: 1, actor: userActor });
    await svc.transitionLifeAdmin({ domainId: domain.id, lifeAdminId: grandA.life_admin.id, toStageKey: "done", expectedVersion: 1, actor: userActor });
    await svc.transitionLifeAdmin({ domainId: domain.id, lifeAdminId: grandB.life_admin.id, toStageKey: "cancelled", expectedVersion: 1, actor: userActor });
    await svc.transitionLifeAdmin({ domainId: domain.id, lifeAdminId: childA.life_admin.id, toStageKey: "done", expectedVersion: 1, actor: userActor });

    expect(await svc.getLifeAdminRollup(domain.id, root.life_admin.id)).toEqual({
      total: 5,
      done: 4,
      cancelled: 1,
      open: 0,
      complete: true,
    });
    const [freshRoot] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, root.life_admin.id));
    const [freshChildA] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, childA.life_admin.id));
    expect(freshRoot!.childCount).toBe(3);
    expect(freshRoot!.terminalChildCount).toBe(3);
    expect(freshChildA!.childCount).toBe(2);
    expect(freshChildA!.terminalChildCount).toBe(2);
    const rootEvents = await svc.listLifeAdminEvents(domain.id, root.life_admin.id);
    expect(rootEvents.filter((event) => event.type === "children_terminal")).toHaveLength(1);
    const comments = await db.select().from(issueComments).where(eq(issueComments.issueId, linkedIssue!.id));
    expect(comments).toHaveLength(1);
    expect(comments[0]!.authorType).toBe("system");
    expect(comments[0]!.body).toContain("All child life_admin");
  });

  it("auto-advances a parent when all descendants are terminal", async () => {
    const domain = await seedDomain();
    const workflow = await svc.createWorkflow({
      domainId: domain.id,
      key: "auto-children",
      name: "Auto children",
      actor: userActor,
      stages: [
        { key: "intake", name: "Intake", kind: "open", config: { autoAdvanceOnChildrenTerminal: "done" } },
        { key: "done", name: "Done", kind: "done" },
        { key: "cancelled", name: "Cancelled", kind: "cancelled" },
      ],
    });
    const root = await svc.ingestLifeAdmin({ domainId: domain.id, workflowId: workflow.id, life_adminKey: "auto-root", title: "Root", actor: userActor });
    const child = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "auto-child",
      title: "Child",
      parentLifeAdminId: root.life_admin.id,
      actor: userActor,
    });

    await svc.transitionLifeAdmin({ domainId: domain.id, lifeAdminId: child.life_admin.id, toStageKey: "done", expectedVersion: 1, actor: userActor });

    const [freshRoot] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, root.life_admin.id));
    expect(freshRoot!.terminalKind).toBe("done");
    expect(freshRoot!.version).toBe(2);
    const rootEvents = await svc.listLifeAdminEvents(domain.id, root.life_admin.id);
    expect(rootEvents.map((event) => event.type)).toEqual(["ingested", "children_terminal", "transitioned"]);
  });

  it("auto-advances a leased parent when child completion triggers a system transition", async () => {
    const domain = await seedDomain();
    const workflow = await svc.createWorkflow({
      domainId: domain.id,
      key: "auto-children-lease",
      name: "Auto children lease",
      actor: userActor,
      stages: [
        { key: "intake", name: "Intake", kind: "open", config: { autoAdvanceOnChildrenTerminal: "done" } },
        { key: "done", name: "Done", kind: "done" },
        { key: "cancelled", name: "Cancelled", kind: "cancelled" },
      ],
    });
    const root = await svc.ingestLifeAdmin({ domainId: domain.id, workflowId: workflow.id, life_adminKey: "leased-root", title: "Root", actor: userActor });
    const child = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "leased-child",
      title: "Child",
      parentLifeAdminId: root.life_admin.id,
      actor: userActor,
    });
    await svc.claimLifeAdmin({
      domainId: domain.id,
      lifeAdminId: root.life_admin.id,
      actor: { type: "user", userId: "reviewer" },
    });

    await svc.transitionLifeAdmin({ domainId: domain.id, lifeAdminId: child.life_admin.id, toStageKey: "done", expectedVersion: 1, actor: userActor });

    const [freshRoot] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, root.life_admin.id));
    expect(freshRoot!.terminalKind).toBe("done");
    expect(freshRoot!.leaseToken).toBeNull();
    const rootEvents = await svc.listLifeAdminEvents(domain.id, root.life_admin.id);
    expect(rootEvents.map((event) => event.type)).toEqual(["ingested", "claimed", "children_terminal", "transitioned"]);
  });

  it("keeps child completion committed when parent children-terminal auto-advance is gated", async () => {
    const domain = await seedDomain();
    const workflow = await svc.createWorkflow({
      domainId: domain.id,
      key: "auto-children-blocked",
      name: "Auto children blocked",
      actor: userActor,
      stages: [
        { key: "intake", name: "Intake", kind: "open", config: { autoAdvanceOnChildrenTerminal: "done" } },
        { key: "done", name: "Done", kind: "done" },
        { key: "cancelled", name: "Cancelled", kind: "cancelled" },
      ],
    });
    const root = await svc.ingestLifeAdmin({ domainId: domain.id, workflowId: workflow.id, life_adminKey: "blocked-root", title: "Root", actor: userActor });
    const child = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "blocked-child",
      title: "Child",
      parentLifeAdminId: root.life_admin.id,
      actor: userActor,
    });
    const blocker = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "open-blocker",
      title: "Open blocker",
      actor: userActor,
    });
    await svc.replaceBlockers({
      domainId: domain.id,
      lifeAdminId: root.life_admin.id,
      blockedByLifeAdminIds: [blocker.life_admin.id],
      actor: userActor,
    });

    await expect(
      svc.transitionLifeAdmin({ domainId: domain.id, lifeAdminId: child.life_admin.id, toStageKey: "done", expectedVersion: 1, actor: userActor }),
    ).resolves.toMatchObject({ life_admin: { terminalKind: "done" } });

    const [freshRoot] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, root.life_admin.id));
    const [freshChild] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, child.life_admin.id));
    expect(freshRoot!.terminalKind).toBeNull();
    expect(freshRoot!.terminalChildCount).toBe(1);
    expect(freshChild!.terminalKind).toBe("done");
    const rootEvents = await svc.listLifeAdminEvents(domain.id, root.life_admin.id);
    expect(rootEvents.map((event) => event.type)).toEqual(["ingested", "blockers_set", "children_terminal"]);
  });

  it("records suggestion supersede, accept, and dismiss lifecycles", async () => {
    const { domain, workflow } = await seedWorkflow();
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "suggest-accept",
      title: "Suggestion accept",
      actor: userActor,
    });
    const first = await svc.suggestTransition({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "review",
      rationale: "Needs review",
      actor: userActor,
    });
    const second = await svc.suggestTransition({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "in_progress",
      rationale: "Actually draft first",
      actor: userActor,
    });
    expect(second.suggestion.id).not.toBe(first.suggestion.id);

    const accepted = await svc.resolveSuggestion({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      suggestionId: second.suggestion.id,
      decision: "accept",
      expectedVersion: 1,
      actor: userActor,
    });
    expect(accepted.life_admin.version).toBe(2);
    const acceptEvents = await svc.listLifeAdminEvents(domain.id, created.life_admin.id);
    expect(acceptEvents.map((event) => event.type)).toEqual([
      "ingested",
      "transition_suggested",
      "transition_suggested",
      "transitioned",
      "suggestion_resolved",
    ]);

    const dismissLifeAdmin = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "suggest-dismiss",
      title: "Suggestion dismiss",
      actor: userActor,
    });
    const suggestion = await svc.suggestTransition({
      domainId: domain.id,
      lifeAdminId: dismissLifeAdmin.life_admin.id,
      toStageKey: "review",
      rationale: "Maybe review",
      actor: userActor,
    });
    await svc.resolveSuggestion({
      domainId: domain.id,
      lifeAdminId: dismissLifeAdmin.life_admin.id,
      suggestionId: suggestion.suggestion.id,
      decision: "dismiss",
      reason: "Not ready",
      actor: userActor,
    });
    const [dismissed] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, dismissLifeAdmin.life_admin.id));
    expect(dismissed!.pendingSuggestion).toBeNull();
    expect(dismissed!.version).toBe(1);
  });

  it("writes an event for each life_admin mutation and rejects agent mutations without run provenance", async () => {
    const { domain, workflow } = await seedWorkflow();
    const agentActor = { type: "agent", agentId: randomUUID() } as WorkflowActor;
    await expect(
      svc.ingestLifeAdmin({
        domainId: domain.id,
        workflowId: workflow.id,
        life_adminKey: "bad-agent",
        title: "Bad provenance",
        actor: agentActor,
      }),
    ).rejects.toMatchObject({ status: 422, details: { code: "run_id_required" } });

    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "events",
      title: "Events",
      actor: userActor,
    });
    expect(await eventCount(created.life_admin.id)).toBe(1);
    await svc.patchLifeAdminContent({ domainId: domain.id, lifeAdminId: created.life_admin.id, title: "Updated", actor: userActor });
    expect(await eventCount(created.life_admin.id)).toBe(2);
    const claimed = await svc.claimLifeAdmin({ domainId: domain.id, lifeAdminId: created.life_admin.id, actor: { type: "user", userId: "claimer" } });
    expect(await eventCount(created.life_admin.id)).toBe(3);
    await svc.releaseLifeAdmin({ domainId: domain.id, lifeAdminId: created.life_admin.id, leaseToken: claimed.leaseToken, actor: { type: "user", userId: "claimer" } });
    expect(await eventCount(created.life_admin.id)).toBe(4);
    await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "in_progress",
      expectedVersion: 2,
      actor: userActor,
    });
    expect(await eventCount(created.life_admin.id)).toBe(5);
  });

  it("fires a stage-entry automation routine once and keeps crash-retry idempotent", async () => {
    const domain = await seedDomain();
    const routine = await seedRoutine(domain.id, "Draft on enter");
    const workflow = await svc.createWorkflow({
      domainId: domain.id,
      key: "automation",
      name: "Automation",
      actor: userActor,
      stages: [
        { key: "intake", name: "Intake", kind: "open" },
        { key: "drafting", name: "Drafting", kind: "working", config: { onEnter: { type: "run_routine", routineId: routine.id } } },
        { key: "done", name: "Done", kind: "done" },
        { key: "cancelled", name: "Cancelled", kind: "cancelled" },
      ],
    });
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "automation",
      title: "Automation life_admin",
      actor: userActor,
    });

    const moved = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "drafting",
      expectedVersion: 1,
      actor: userActor,
    });
    expect(moved.automationLedger?.routineId).toBe(routine.id);
    expect(moved.automationExecution.status).toBe("succeeded");
    const ledgers = await db.select().from(workflowAutomationExecutions);
    expect(ledgers).toHaveLength(1);
    expect(ledgers[0]!.triggeringEventId).toBe(moved.event.id);
    expect(ledgers[0]!.executionIssueId).toBeTruthy();
    const runsAfterTransition = await db.select().from(routineRuns);
    expect(runsAfterTransition).toHaveLength(1);
    const linksAfterTransition = await db.select().from(workflowLifeAdminIssueLinks);
    expect(linksAfterTransition).toHaveLength(1);
    expect(linksAfterTransition[0]!.role).toBe("automation");

    const [issue] = await db.select().from(issues).where(eq(issues.id, ledgers[0]!.executionIssueId!));
    expect(issue!.description).toContain("Workflow LifeAdmin Context");
    expect(issue!.description).toContain("untrustedContent");

    const triggerEvent = await db.insert(workflowLifeAdminEvents).values({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      type: "transitioned",
      actorType: "system",
      toStageId: moved.life_admin.stageId,
      payload: { simulatedCrash: true },
    }).returning();
    const automationId = ledgers[0]!.automationId;
    await db.insert(workflowAutomationExecutions).values({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      automationId,
      triggeringEventId: triggerEvent[0]!.id,
      routineId: routine.id,
      status: "failed",
      error: "pending_dispatch",
    });

    const firstRetry = await svc.retryAutomation({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      automationId,
      actor: userActor,
    });
    const secondRetry = await svc.retryAutomation({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      automationId,
      actor: userActor,
    });
    expect(firstRetry.status).toBe("succeeded");
    expect(secondRetry.status).toBe("succeeded");
    const runsAfterRetries = await db.select().from(routineRuns);
    expect(runsAfterRetries).toHaveLength(2);
    const crashExecutions = await db
      .select()
      .from(workflowAutomationExecutions)
      .where(eq(workflowAutomationExecutions.triggeringEventId, triggerEvent[0]!.id));
    expect(crashExecutions).toHaveLength(1);
    expect(crashExecutions[0]!.executionIssueId).toBeTruthy();
    const crashLinks = await db
      .select()
      .from(workflowLifeAdminIssueLinks)
      .where(eq(workflowLifeAdminIssueLinks.issueId, crashExecutions[0]!.executionIssueId!));
    expect(crashLinks).toHaveLength(1);
  });

  it("carries saved stage automation workspace context into the execution issue", async () => {
    const { domain, workflow, byKey } = await seedWorkflow();
    const routineSeed = await seedRoutine(domain.id, "Workspace automation seed");
    const projectId = randomUUID();
    const projectWorkspaceId = randomUUID();
    const executionWorkspaceId = randomUUID();

    await instanceSettingsService(db).updateExperimental({ enableIsolatedWorkspaces: true });
    await db.insert(projects).values({
      id: projectId,
      domainId: domain.id,
      name: "Automation project",
      status: "in_progress",
    });
    await db.insert(projectWorkspaces).values({
      id: projectWorkspaceId,
      domainId: domain.id,
      projectId,
      name: "Automation workspace",
      isPrimary: true,
      sharedWorkspaceKey: "workflow-automation-primary",
    });
    await db.insert(executionWorkspaces).values({
      id: executionWorkspaceId,
      domainId: domain.id,
      projectId,
      projectWorkspaceId,
      mode: "isolated_workspace",
      strategyType: "git_worktree",
      name: "Automation worktree",
      status: "active",
      providerType: "git_worktree",
    });

    const updatedStage = await svc.updateStage({
      domainId: domain.id,
      workflowId: workflow.id,
      stageId: byKey.get("in_progress")!.id,
      patch: {
        config: {
          automation: {
            assigneeAgentId: routineSeed.assigneeAgentId,
            instructionsBody: "Use the selected workspace.",
            projectId,
            projectWorkspaceId,
            executionWorkspaceId,
            executionWorkspacePreference: "reuse_existing",
            executionWorkspaceSettings: { mode: "isolated_workspace" },
          },
        },
      },
      actor: userActor,
    });
    expect((updatedStage.config as { onEnter?: unknown }).onEnter).toMatchObject({
      type: "run_routine",
      projectId,
      projectWorkspaceId,
      executionWorkspaceId,
      executionWorkspacePreference: "reuse_existing",
      executionWorkspaceSettings: { mode: "isolated_workspace" },
    });

    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "workspace-context",
      title: "Workspace context life_admin",
      actor: userActor,
    });
    const moved = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "in_progress",
      expectedVersion: 1,
      actor: userActor,
    });

    expect(moved.automationExecution.status).toBe("succeeded");
    const executionIssueId = moved.automationExecution.status === "succeeded"
      ? moved.automationExecution.execution.executionIssueId
      : null;
    const [issue] = await db
      .select({
        projectId: issues.projectId,
        projectWorkspaceId: issues.projectWorkspaceId,
        executionWorkspaceId: issues.executionWorkspaceId,
        executionWorkspacePreference: issues.executionWorkspacePreference,
        executionWorkspaceSettings: issues.executionWorkspaceSettings,
      })
      .from(issues)
      .where(eq(issues.id, executionIssueId!));

    expect(issue).toEqual({
      projectId,
      projectWorkspaceId,
      executionWorkspaceId,
      executionWorkspacePreference: "reuse_existing",
      executionWorkspaceSettings: { mode: "isolated_workspace" },
    });
  });

  it("defaults, preserves, and interpolates workflow automation issue title templates", async () => {
    const { domain, workflow, byKey } = await seedWorkflow();
    const routineSeed = await seedRoutine(domain.id, "Automation seed");
    const stageId = byKey.get("in_progress")!.id;

    const firstSave = await svc.updateStage({
      domainId: domain.id,
      workflowId: workflow.id,
      stageId,
      patch: {
        config: {
          automation: {
            assigneeAgentId: routineSeed.assigneeAgentId,
            instructionsBody: "Draft from {{body}} for {{life_admin_title}}.",
          },
        },
      },
      actor: userActor,
    });
    const firstRoutineId = (firstSave.config as { onEnter?: { routineId?: string } }).onEnter?.routineId;
    expect(firstRoutineId).toBeTruthy();
    const [defaultRoutine] = await db.select().from(routines).where(eq(routines.id, firstRoutineId!));
    expect(defaultRoutine!.title).toBe(WORKFLOW_AUTOMATION_DEFAULT_TITLE_TEMPLATE);
    expect((defaultRoutine!.variables ?? []).map((variable) => variable.name)).toEqual([
      "workflow_name",
      "stage_name",
      "life_admin_title",
      "body",
    ]);

    await db
      .update(routines)
      .set({ title: "Custom {{life_admin_key}}: {{life_admin_title}}" })
      .where(eq(routines.id, firstRoutineId!));
    await svc.updateStage({
      domainId: domain.id,
      workflowId: workflow.id,
      stageId,
      patch: {
        config: {
          automation: {
            assigneeAgentId: routineSeed.assigneeAgentId,
            instructionsBody: "Updated instructions for {{life_admin_title}}.",
          },
        },
      },
      actor: userActor,
    });
    const [customRoutine] = await db.select().from(routines).where(eq(routines.id, firstRoutineId!));
    expect(customRoutine!.title).toBe("Custom {{life_admin_key}}: {{life_admin_title}}");
    expect((customRoutine!.variables ?? []).map((variable) => variable.name)).toContain("life_admin_key");

    await db
      .update(routines)
      .set({ title: "In progress automation" })
      .where(eq(routines.id, firstRoutineId!));
    await svc.updateStage({
      domainId: domain.id,
      workflowId: workflow.id,
      stageId,
      patch: {
        config: {
          automation: {
            assigneeAgentId: routineSeed.assigneeAgentId,
            instructionsBody: "Runtime interpolation for {{life_admin_title}}.",
          },
        },
      },
      actor: userActor,
    });
    const [upgradedRoutine] = await db.select().from(routines).where(eq(routines.id, firstRoutineId!));
    expect(upgradedRoutine!.title).toBe(WORKFLOW_AUTOMATION_DEFAULT_TITLE_TEMPLATE);

    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "pulpit-opinion",
      title: "Pulpit opinion piece",
      body: "Agentic work should be composed, not rebuilt",
      actor: userActor,
    });
    const moved = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "in_progress",
      expectedVersion: 1,
      actor: userActor,
    });
    expect(moved.automationExecution.status).toBe("succeeded");
    const executionIssueId = moved.automationExecution.status === "succeeded"
      ? moved.automationExecution.execution.executionIssueId
      : null;
    const [issue] = await db
      .select({ title: issues.title })
      .from(issues)
      .where(eq(issues.id, executionIssueId!));
    expect(issue!.title).toBe("Content / In progress: Pulpit opinion piece");
  });

  it("rejects cross-domain stage automation routines at save and execution", async () => {
    const domain = await seedDomain();
    const otherDomain = await seedDomain();
    const routine = await seedRoutine(domain.id, "Own routine");
    const otherRoutine = await seedRoutine(otherDomain.id, "Other routine");

    await expect(svc.createWorkflow({
      domainId: domain.id,
      key: "bad-automation",
      name: "Bad automation",
      actor: userActor,
      stages: [
        { key: "intake", name: "Intake", kind: "open" },
        { key: "drafting", name: "Drafting", kind: "working", config: { onEnter: { type: "run_routine", routineId: otherRoutine.id } } },
        { key: "done", name: "Done", kind: "done" },
        { key: "cancelled", name: "Cancelled", kind: "cancelled" },
      ],
    })).rejects.toMatchObject({ status: 422, details: { code: "validation" } });

    const workflow = await svc.createWorkflow({
      domainId: domain.id,
      key: "execution-automation",
      name: "Execution automation",
      actor: userActor,
      stages: [
        { key: "intake", name: "Intake", kind: "open" },
        { key: "drafting", name: "Drafting", kind: "working", config: { onEnter: { type: "run_routine", routineId: routine.id } } },
        { key: "done", name: "Done", kind: "done" },
        { key: "cancelled", name: "Cancelled", kind: "cancelled" },
      ],
    });
    const created = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "cross-domain-execution",
      title: "Cross-domain execution",
      actor: userActor,
    });
    const moved = await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      toStageKey: "drafting",
      expectedVersion: 1,
      actor: userActor,
    });
    expect(moved.automationExecution.status).toBe("succeeded");

    const [triggerEvent] = await db.insert(workflowLifeAdminEvents).values({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      type: "transitioned",
      actorType: "system",
      toStageId: moved.life_admin.stageId,
      payload: { crossDomainRoutine: true },
    }).returning();
    const [badExecution] = await db.insert(workflowAutomationExecutions).values({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      automationId: moved.automationLedger!.automationId,
      triggeringEventId: triggerEvent!.id,
      routineId: otherRoutine.id,
      status: "failed",
      error: "pending_dispatch",
    }).returning();

    const retried = await svc.retryAutomation({
      domainId: domain.id,
      lifeAdminId: created.life_admin.id,
      automationId: moved.automationLedger!.automationId,
      actor: userActor,
    });
    expect(retried.status).toBe("failed");
    const [execution] = await db
      .select()
      .from(workflowAutomationExecutions)
      .where(eq(workflowAutomationExecutions.id, badExecution!.id));
    expect(execution!.error).toContain("same domain");
    const events = await svc.listLifeAdminEvents(domain.id, created.life_admin.id);
    expect(events.filter((event) => event.type === "automation_failed")).toHaveLength(1);
  });

  it("auto-advances after retry creates a fresh terminal child rollup", async () => {
    const domain = await seedDomain();
    const routine = await seedRoutine(domain.id, "Retry child cleanup");
    const workflow = await svc.createWorkflow({
      domainId: domain.id,
      key: "retry-child-cleanup",
      name: "Retry child cleanup",
      actor: userActor,
      stages: [
        {
          key: "build",
          name: "Build",
          kind: "working",
          config: {
            autoAdvanceOnChildrenTerminal: "review",
            onEnter: {
              type: "run_routine",
              id: "build-children",
              routineId: routine.id,
            },
          },
        },
        { key: "review", name: "Review", kind: "working" },
        { key: "done", name: "Done", kind: "done" },
        { key: "cancelled", name: "Cancelled", kind: "cancelled" },
      ],
    });
    const parent = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "parent",
      title: "Parent",
      actor: userActor,
    });
    const [event] = await db.insert(workflowLifeAdminEvents).values({
      domainId: domain.id,
      lifeAdminId: parent.life_admin.id,
      type: "transitioned",
      actorType: "system",
      toStageId: parent.life_admin.stageId,
      payload: { test: true },
    }).returning();
    const [attempt] = await db.insert(workflowAutomationExecutions).values({
      domainId: domain.id,
      lifeAdminId: parent.life_admin.id,
      automationId: "build-children",
      triggeringEventId: event!.id,
      routineId: routine.id,
      status: "failed",
      error: "boom",
    }).returning();
    const child = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "child",
      title: "Child",
      parentLifeAdminId: parent.life_admin.id,
      actor: userActor,
    });
    await db
      .update(workflowLifeAdmin)
      .set({ automationAttemptId: attempt!.id })
      .where(eq(workflowLifeAdmin.id, child.life_admin.id));
    await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: child.life_admin.id,
      toStageKey: "done",
      expectedVersion: child.life_admin.version,
      actor: userActor,
    });
    const [reviewingParent] = await db
      .select({ version: workflowLifeAdmin.version, stageKey: workflowStages.key })
      .from(workflowLifeAdmin)
      .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
      .where(eq(workflowLifeAdmin.id, parent.life_admin.id));
    expect(reviewingParent!.stageKey).toBe("review");

    const retry = await svc.retryStageAutomation({
      domainId: domain.id,
      lifeAdminId: parent.life_admin.id,
      scope: "previous_stage",
      targetStageId: event!.toStageId,
      expectedVersion: reviewingParent!.version,
      cleanup: {
        retireDirectChildren: true,
        retireDescendants: true,
        cancelLinkedAutomationIssues: true,
      },
      actor: userActor,
    });
    const retryChild = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "retry-child",
      title: "Retry child",
      parentLifeAdminId: parent.life_admin.id,
      actor: userActor,
    });
    await db
      .update(workflowLifeAdmin)
      .set({ automationAttemptId: retry.automationLedger.id })
      .where(eq(workflowLifeAdmin.id, retryChild.life_admin.id));
    await svc.transitionLifeAdmin({
      domainId: domain.id,
      lifeAdminId: retryChild.life_admin.id,
      toStageKey: "done",
      expectedVersion: retryChild.life_admin.version,
      actor: userActor,
    });

    const [freshParent] = await db
      .select({ childCount: workflowLifeAdmin.childCount, terminalChildCount: workflowLifeAdmin.terminalChildCount, stageKey: workflowStages.key })
      .from(workflowLifeAdmin)
      .innerJoin(workflowStages, eq(workflowLifeAdmin.stageId, workflowStages.id))
      .where(eq(workflowLifeAdmin.id, parent.life_admin.id));
    const [freshChild] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, child.life_admin.id));
    expect(freshParent!.childCount).toBe(2);
    expect(freshParent!.terminalChildCount).toBe(2);
    expect(freshParent!.stageKey).toBe("review");
    expect(freshChild!.terminalKind).toBe("cancelled");
    expect(freshChild!.retiredReason).toBe("automation_retry");
    const events = await svc.listLifeAdminEvents(domain.id, parent.life_admin.id);
    expect(events.filter((workflowEvent) => workflowEvent.type === "children_terminal")).toHaveLength(2);
  });

  it("updates intermediate terminal counts when retry retires descendants only", async () => {
    const domain = await seedDomain();
    const routine = await seedRoutine(domain.id, "Retry descendants only");
    const workflow = await svc.createWorkflow({
      domainId: domain.id,
      key: "retry-descendants-only",
      name: "Retry descendants only",
      actor: userActor,
      stages: [
        {
          key: "build",
          name: "Build",
          kind: "working",
          config: {
            onEnter: {
              type: "run_routine",
              id: "build-descendants",
              routineId: routine.id,
            },
          },
        },
        { key: "done", name: "Done", kind: "done" },
        { key: "cancelled", name: "Cancelled", kind: "cancelled" },
      ],
    });
    const parent = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "descendants-parent",
      title: "Descendants parent",
      actor: userActor,
    });
    const [event] = await db.insert(workflowLifeAdminEvents).values({
      domainId: domain.id,
      lifeAdminId: parent.life_admin.id,
      type: "transitioned",
      actorType: "system",
      toStageId: parent.life_admin.stageId,
      payload: { test: true },
    }).returning();
    const [attempt] = await db.insert(workflowAutomationExecutions).values({
      domainId: domain.id,
      lifeAdminId: parent.life_admin.id,
      automationId: "build-descendants",
      triggeringEventId: event!.id,
      routineId: routine.id,
      status: "failed",
      error: "boom",
    }).returning();
    const child = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "descendants-child",
      title: "Descendants child",
      parentLifeAdminId: parent.life_admin.id,
      actor: userActor,
    });
    await db
      .update(workflowLifeAdmin)
      .set({ automationAttemptId: attempt!.id })
      .where(eq(workflowLifeAdmin.id, child.life_admin.id));
    const grandchild = await svc.ingestLifeAdmin({
      domainId: domain.id,
      workflowId: workflow.id,
      life_adminKey: "descendants-grandchild",
      title: "Descendants grandchild",
      parentLifeAdminId: child.life_admin.id,
      actor: userActor,
    });

    await svc.retryStageAutomation({
      domainId: domain.id,
      lifeAdminId: parent.life_admin.id,
      scope: "current_stage",
      expectedVersion: parent.life_admin.version,
      cleanup: {
        retireDirectChildren: false,
        retireDescendants: true,
        cancelLinkedAutomationIssues: false,
      },
      actor: userActor,
    });

    const [freshParent] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, parent.life_admin.id));
    const [freshChild] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, child.life_admin.id));
    const [freshGrandchild] = await db.select().from(workflowLifeAdmin).where(eq(workflowLifeAdmin.id, grandchild.life_admin.id));
    expect(freshParent!.terminalChildCount).toBe(0);
    expect(freshChild!.terminalKind).toBeNull();
    expect(freshChild!.terminalChildCount).toBe(1);
    expect(freshGrandchild!.terminalKind).toBe("cancelled");
    expect(freshGrandchild!.retiredReason).toBe("automation_retry");
  });
});

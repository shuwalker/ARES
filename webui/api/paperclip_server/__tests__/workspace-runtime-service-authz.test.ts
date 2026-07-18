import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  agents,
  domains,
  createDb,
  executionWorkspaces,
  heartbeatRuns,
  issues,
  projectWorkspaces,
  projects,
} from "@paperclipai/db";
import { LOW_TRUST_REVIEW_PRESET } from "@paperclipai/shared";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import {
  assertCanManageExecutionWorkspaceRuntimeServices,
  assertCanManageProjectWorkspaceRuntimeServices,
} from "../routes/workspace-runtime-service-authz.js";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres workspace runtime auth tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("workspace runtime service authz helper", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-workspace-runtime-authz-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(issues);
    await db.delete(executionWorkspaces);
    await db.delete(projectWorkspaces);
    await db.delete(projects);
    await db.delete(heartbeatRuns);
    await db.delete(agents);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  async function seedDomain() {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: `PAP-${domainId.slice(0, 8)}`,
      requireBoardApprovalForNewAgents: false,
    });
    return domainId;
  }

  async function seedProjectWorkspace(domainId: string) {
    const projectId = randomUUID();
    const projectWorkspaceId = randomUUID();
    await db.insert(projects).values({
      id: projectId,
      domainId,
      name: "Workspace authz",
      status: "in_progress",
    });
    await db.insert(projectWorkspaces).values({
      id: projectWorkspaceId,
      domainId,
      projectId,
      name: "Primary",
      sourceType: "local_path",
      cwd: "/tmp/paperclip-authz-project",
      isPrimary: true,
    });
    return { projectId, projectWorkspaceId };
  }

  async function seedExecutionWorkspace(domainId: string, projectId: string, projectWorkspaceId: string) {
    const executionWorkspaceId = randomUUID();
    await db.insert(executionWorkspaces).values({
      id: executionWorkspaceId,
      domainId,
      projectId,
      projectWorkspaceId,
      mode: "isolated_workspace",
      strategyType: "git_worktree",
      name: "Execution workspace",
      status: "active",
      providerType: "local_fs",
      cwd: "/tmp/paperclip-authz-execution",
    });
    return executionWorkspaceId;
  }

  async function seedAgent(
    domainId: string,
    input: { role?: string; reportsTo?: string | null; name?: string } = {},
  ) {
    const agentId = randomUUID();
    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: input.name ?? "Agent",
      role: input.role ?? "engineer",
      reportsTo: input.reportsTo ?? null,
    });
    return agentId;
  }

  it("allows board actors to manage project workspace runtime services", async () => {
    const domainId = await seedDomain();
    const { projectWorkspaceId } = await seedProjectWorkspace(domainId);

    await expect(assertCanManageProjectWorkspaceRuntimeServices(db, {
      actor: {
        type: "board",
        userId: "board-1",
        domainIds: [domainId],
        source: "session",
        isInstanceAdmin: false,
      },
    } as any, {
      domainId,
      projectWorkspaceId,
    })).resolves.toBeUndefined();
  });

  it("allows CEO agents to manage any project workspace runtime services in their domain", async () => {
    const domainId = await seedDomain();
    const { projectWorkspaceId } = await seedProjectWorkspace(domainId);
    const ceoAgentId = await seedAgent(domainId, { role: "ceo", name: "CEO" });

    await expect(assertCanManageProjectWorkspaceRuntimeServices(db, {
      actor: {
        type: "agent",
        agentId: ceoAgentId,
        domainId,
        source: "agent_key",
      },
    } as any, {
      domainId,
      projectWorkspaceId,
    })).resolves.toBeUndefined();
  });

  it("rejects low-trust CEO runtime service mutations unless runtime.manage is granted", async () => {
    const domainId = await seedDomain();
    const { projectId, projectWorkspaceId } = await seedProjectWorkspace(domainId);
    const ceoAgentId = await seedAgent(domainId, { role: "ceo", name: "CEO" });
    await db
      .update(agents)
      .set({
        permissions: {
          trustPreset: LOW_TRUST_REVIEW_PRESET,
          authorizationPolicy: {
            trustBoundary: {
              mode: LOW_TRUST_REVIEW_PRESET,
              domainId,
              projectIds: [projectId],
            },
          },
        },
      })
      .where(eq(agents.id, ceoAgentId));

    await db.insert(issues).values({
      id: randomUUID(),
      domainId,
      projectId,
      projectWorkspaceId,
      title: "Low-trust workspace",
      status: "todo",
      priority: "medium",
      assigneeAgentId: ceoAgentId,
    });

    await expect(assertCanManageProjectWorkspaceRuntimeServices(db, {
      actor: {
        type: "agent",
        agentId: ceoAgentId,
        domainId,
        source: "agent_key",
      },
    } as any, {
      domainId,
      projectWorkspaceId,
    })).rejects.toMatchObject({
      status: 403,
      message: "Low-trust runs cannot manage workspace runtime services unless the boundary grants runtime.manage",
    });
  });

  it("allows standard CEO runtime service mutations for low-trust workspace issues", async () => {
    const domainId = await seedDomain();
    const { projectId, projectWorkspaceId } = await seedProjectWorkspace(domainId);
    const ceoAgentId = await seedAgent(domainId, { role: "ceo", name: "CEO" });

    await db.insert(issues).values({
      id: randomUUID(),
      domainId,
      projectId,
      projectWorkspaceId,
      title: "Issue-scoped low-trust workspace",
      status: "todo",
      priority: "medium",
      assigneeAgentId: ceoAgentId,
      executionPolicy: {
        authorizationPolicy: {
          trustBoundary: {
            mode: LOW_TRUST_REVIEW_PRESET,
            domainId,
            projectIds: [projectId],
          },
        },
      },
    });

    await expect(assertCanManageProjectWorkspaceRuntimeServices(db, {
      actor: {
        type: "agent",
        agentId: ceoAgentId,
        domainId,
        source: "agent_key",
      },
    } as any, {
      domainId,
      projectWorkspaceId,
    })).resolves.toBeUndefined();
  });

  it("rejects runtime service mutations when only the run policy is low-trust without runtime.manage", async () => {
    const domainId = await seedDomain();
    const { projectId, projectWorkspaceId } = await seedProjectWorkspace(domainId);
    const ceoAgentId = await seedAgent(domainId, { role: "ceo", name: "CEO" });
    const issueId = randomUUID();
    const runId = randomUUID();

    await db.insert(issues).values({
      id: issueId,
      domainId,
      projectId,
      projectWorkspaceId,
      title: "Run-scoped low-trust workspace",
      status: "in_progress",
      priority: "medium",
      assigneeAgentId: ceoAgentId,
    });
    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId: ceoAgentId,
      status: "running",
      contextSnapshot: {
        issueId,
        executionPolicy: {
          authorizationPolicy: {
            trustBoundary: {
              mode: LOW_TRUST_REVIEW_PRESET,
              domainId,
              projectIds: [projectId],
            },
          },
        },
      },
    });

    await expect(assertCanManageProjectWorkspaceRuntimeServices(db, {
      actor: {
        type: "agent",
        agentId: ceoAgentId,
        domainId,
        runId,
        source: "agent_key",
      },
    } as any, {
      domainId,
      projectWorkspaceId,
    })).rejects.toMatchObject({
      status: 403,
      message: "Low-trust runs cannot manage workspace runtime services unless the boundary grants runtime.manage",
    });
  });

  it("allows agents with a non-terminal assigned issue in the target project workspace", async () => {
    const domainId = await seedDomain();
    const { projectId, projectWorkspaceId } = await seedProjectWorkspace(domainId);
    const agentId = await seedAgent(domainId, { name: "Engineer" });

    await db.insert(issues).values({
      id: randomUUID(),
      domainId,
      projectId,
      projectWorkspaceId,
      title: "Use this workspace",
      status: "todo",
      priority: "medium",
      assigneeAgentId: agentId,
    });

    await expect(assertCanManageProjectWorkspaceRuntimeServices(db, {
      actor: {
        type: "agent",
        agentId,
        domainId,
        source: "agent_key",
      },
    } as any, {
      domainId,
      projectWorkspaceId,
    })).resolves.toBeUndefined();
  });

  it("allows managers to manage execution workspace runtime services for their reporting subtree", async () => {
    const domainId = await seedDomain();
    const { projectId, projectWorkspaceId } = await seedProjectWorkspace(domainId);
    const executionWorkspaceId = await seedExecutionWorkspace(domainId, projectId, projectWorkspaceId);
    const managerId = await seedAgent(domainId, { role: "cto", name: "Manager" });
    const reportId = await seedAgent(domainId, { reportsTo: managerId, name: "Report" });

    await db.insert(issues).values({
      id: randomUUID(),
      domainId,
      projectId,
      projectWorkspaceId,
      executionWorkspaceId,
      title: "Use execution workspace",
      status: "in_progress",
      priority: "medium",
      assigneeAgentId: reportId,
    });

    await expect(assertCanManageExecutionWorkspaceRuntimeServices(db, {
      actor: {
        type: "agent",
        agentId: managerId,
        domainId,
        source: "agent_key",
      },
    } as any, {
      domainId,
      executionWorkspaceId,
    })).resolves.toBeUndefined();
  });

  it("rejects unrelated same-domain agents without matching workspace assignments", async () => {
    const domainId = await seedDomain();
    const { projectId, projectWorkspaceId } = await seedProjectWorkspace(domainId);
    const executionWorkspaceId = await seedExecutionWorkspace(domainId, projectId, projectWorkspaceId);
    const assignedAgentId = await seedAgent(domainId, { name: "Assigned" });
    const unrelatedAgentId = await seedAgent(domainId, { name: "Unrelated" });

    await db.insert(issues).values({
      id: randomUUID(),
      domainId,
      projectId,
      projectWorkspaceId,
      executionWorkspaceId,
      title: "Assigned issue",
      status: "todo",
      priority: "medium",
      assigneeAgentId: assignedAgentId,
    });

    await expect(assertCanManageExecutionWorkspaceRuntimeServices(db, {
      actor: {
        type: "agent",
        agentId: unrelatedAgentId,
        domainId,
        source: "agent_key",
      },
    } as any, {
      domainId,
      executionWorkspaceId,
    })).rejects.toMatchObject({
      status: 403,
      message: "Missing permission to manage workspace runtime services",
    });
  });

  it("rejects completed workspace assignments so stale issues do not keep access alive", async () => {
    const domainId = await seedDomain();
    const { projectId, projectWorkspaceId } = await seedProjectWorkspace(domainId);
    const agentId = await seedAgent(domainId, { name: "Engineer" });

    await db.insert(issues).values({
      id: randomUUID(),
      domainId,
      projectId,
      projectWorkspaceId,
      title: "Completed issue",
      status: "done",
      priority: "medium",
      assigneeAgentId: agentId,
    });

    await expect(assertCanManageProjectWorkspaceRuntimeServices(db, {
      actor: {
        type: "agent",
        agentId,
        domainId,
        source: "agent_key",
      },
    } as any, {
      domainId,
      projectWorkspaceId,
    })).rejects.toMatchObject({
      status: 403,
      message: "Missing permission to manage workspace runtime services",
    });
  });
});

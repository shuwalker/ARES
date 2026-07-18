import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import express from "express";
import request from "supertest";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  activityLog,
  agents,
  domains,
  companyMemberships,
  createDb,
  documents,
  documentRevisions,
  executionWorkspaces,
  heartbeatRuns,
  instanceSettings,
  issueComments,
  issues,
  pipelineAutomationExecutions,
  pipelineCaseBlockers,
  pipelineCaseEvents,
  pipelineCaseIssueLinks,
  pipelineLifeAdmin,
  pipelineDocuments,
  pipelineStages,
  pipelineTransitions,
  workflows,
  principalPermissionGrants,
  projectWorkspaces,
  projects,
  routineRuns,
  routines,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { errorHandler } from "../middleware/error-handler.js";
import { issueRoutes } from "../routes/issues.js";
import { pipelineRoutes } from "../routes/workflows.js";
import {
  PIPELINE_AUTOMATION_DEFAULT_TITLE_TEMPLATE,
  PIPELINE_CASE_EVENTS_MAX_LIMIT,
  PIPELINE_CONTEXT_PACK_EVENT_LIMIT,
} from "../services/workflows.js";
import { instanceSettingsService } from "../services/instance-settings.js";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe.sequential : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres pipeline route tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("pipeline routes", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;
  const noopHeartbeat = { wakeup: async () => null };

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-workflows-routes-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(pipelineAutomationExecutions);
    await db.delete(pipelineCaseBlockers);
    await db.delete(pipelineCaseIssueLinks);
    await db.delete(pipelineCaseEvents);
    await db.delete(pipelineLifeAdmin);
    await db.delete(pipelineTransitions);
    await db.delete(pipelineStages);
    await db.delete(pipelineDocuments);
    await db.delete(documentRevisions);
    await db.delete(documents);
    await db.delete(issueComments);
    await db.delete(activityLog);
    await db.delete(routineRuns);
    await db.delete(heartbeatRuns);
    await db.delete(issues);
    await db.delete(executionWorkspaces);
    await db.delete(workflows);
    await db.delete(routines);
    await db.delete(projectWorkspaces);
    await db.delete(projects);
    await db.delete(principalPermissionGrants);
    await db.delete(companyMemberships);
    await db.delete(agents);
    await db.delete(domains);
    await db.delete(instanceSettings);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  function app(actor: Express.Request["actor"]) {
    const instance = express();
    instance.use(express.json());
    instance.use((req, _res, next) => {
      req.actor = actor;
      next();
    });
    instance.use("/api", pipelineRoutes(db, { heartbeat: noopHeartbeat }));
    instance.use("/api", issueRoutes(db, {} as any));
    instance.use(errorHandler);
    return instance;
  }

  async function seedDomain(name = "Workflow Co") {
    const [company] = await db.insert(domains).values({
      name,
      issuePrefix: `P${randomUUID().replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
    }).returning();
    return company!;
  }

  async function seedAutomationAgent(companyId: string) {
    const [agent] = await db.insert(agents).values({
      companyId,
      name: "Workflow Automator",
      role: "engineer",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    }).returning();
    return agent!;
  }

  async function seedProjectWorkspaceFixture(companyId: string, name = "Automation") {
    const projectId = randomUUID();
    const projectWorkspaceId = randomUUID();
    const executionWorkspaceId = randomUUID();

    await db.insert(projects).values({
      id: projectId,
      companyId,
      name: `${name} project`,
      status: "in_progress",
    });
    await db.insert(projectWorkspaces).values({
      id: projectWorkspaceId,
      companyId,
      projectId,
      name: `${name} workspace`,
      isPrimary: true,
      sharedWorkspaceKey: `${name.toLowerLifeAdmin().replace(/[^a-z0-9]+/g, "-")}-${projectWorkspaceId.slice(0, 8)}`,
    });
    await db.insert(executionWorkspaces).values({
      id: executionWorkspaceId,
      companyId,
      projectId,
      projectWorkspaceId,
      mode: "isolated_workspace",
      strategyType: "git_worktree",
      name: `${name} worktree`,
      status: "active",
      providerType: "git_worktree",
    });

    return { projectId, projectWorkspaceId, executionWorkspaceId };
  }

  const boardActor: Express.Request["actor"] = {
    type: "board",
    userId: "board-user",
    source: "local_implicit",
    isInstanceAdmin: true,
  };

  it("exposes the pipeline and case route surface", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));

    const createdWorkflow = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "content",
        name: "Content",
        stages: [
          { key: "intake", name: "Intake", kind: "open", position: 100 },
          {
            key: "review",
            name: "Review",
            kind: "review",
            position: 200,
            config: { approveToStageKey: "done", rejectToStageKey: "cancelled", requireRejectReason: true },
          },
          { key: "done", name: "Done", kind: "done", position: 900 },
          { key: "cancelled", name: "Cancelled", kind: "cancelled", position: 1000 },
        ],
      })
      .expect(201);
    const pipelineId = createdWorkflow.body.id;
    const stageId = createdWorkflow.body.stages[0].id;

    await http.get(`/api/domains/${company.id}/workflows`).expect(200);
    await http.get(`/api/workflows/${pipelineId}`).expect(200);
    await http.patch(`/api/workflows/${pipelineId}`).send({ name: "Content Ops", enforceTransitions: true }).expect(200);
    const qaStage = await http
      .post(`/api/workflows/${pipelineId}/stages`)
      .send({ key: "qa", name: "QA", kind: "working", position: 300 })
      .expect(201);
    await http.patch(`/api/workflows/${pipelineId}/stages/${qaStage.body.id}`).send({ name: "QA pass" }).expect(200);
    await http
      .put(`/api/workflows/${pipelineId}/transitions`)
      .send({ enforceTransitions: false, transitions: [{ fromStageKey: "intake", toStageKey: "review" }] })
      .expect(200);
    await http.put(`/api/workflows/${pipelineId}/documents/guidance`).send({ body: "Use the rubric." }).expect(200);
    await http.get(`/api/workflows/${pipelineId}/documents/guidance`).expect(200);

    const ingested = await http
      .post(`/api/workflows/${pipelineId}/life_admin`)
      .send({ caseKey: "case-1", title: "LifeAdmin 1", fields: { channel: "blog" } })
      .expect(201);
    const caseId = ingested.body.case.id;
    const batchIngest = await http
      .post(`/api/workflows/${pipelineId}/life_admin/batch`)
      .send({ items: [{ caseKey: "case-2", title: "LifeAdmin 2", blockedByCaseKeys: ["case-3"] }, { caseKey: "case-3", title: "LifeAdmin 3" }] })
      .expect(200);
    expect(batchIngest.body[0].ok).toBe(true);
    const routeBlockers = await db
      .select()
      .from(pipelineCaseBlockers)
      .where(eq(pipelineCaseBlockers.caseId, batchIngest.body[0].case.id));
    expect(routeBlockers.map((row) => row.blockedByCaseId)).toEqual([batchIngest.body[1].case.id]);
    await http.get(`/api/workflows/${pipelineId}/life_admin`).expect(200);
    await http.get(`/api/life_admin/${caseId}`).expect(200);
    await http.patch(`/api/life_admin/${caseId}`).send({ title: "LifeAdmin 1 updated", expectedVersion: 1 }).expect(200);
    const claimed = await http.post(`/api/life_admin/${caseId}/claim`).send({ leaseSeconds: 60 }).expect(200);
    await http.post(`/api/life_admin/${caseId}/release`).send({ leaseToken: claimed.body.leaseToken }).expect(200);
    const suggestion = await http
      .post(`/api/life_admin/${caseId}/suggest-transition`)
      .send({ toStageKey: "review", rationale: "Ready for review" })
      .expect(200);
    await http
      .post(`/api/life_admin/${caseId}/resolve-suggestion`)
      .send({ suggestionId: suggestion.body.suggestion.id, resolution: "accept", expectedVersion: 2 })
      .expect(200);
    await http.get(`/api/life_admin/${caseId}/events`).expect(200);
    await http.get(`/api/domains/${company.id}/review-life_admin`).expect(200);
    await http.post(`/api/life_admin/${caseId}/review`).send({ decision: "approve", expectedVersion: 3 }).expect(200);

    const reviewLifeAdmin = await http
      .post(`/api/workflows/${pipelineId}/life_admin`)
      .send({ caseKey: "case-review", title: "Bulk review" })
      .expect(201);
    await http
      .post(`/api/life_admin/${reviewLifeAdmin.body.case.id}/transition`)
      .send({ toStageKey: "review", expectedVersion: 1 })
      .expect(200);
    await http
      .post(`/api/domains/${company.id}/review-life_admin/bulk`)
      .send({ items: [{ caseId: reviewLifeAdmin.body.case.id, decision: "reject", reason: "Not useful", expectedVersion: 2 }] })
      .expect(200);

    const blocker = await http.post(`/api/workflows/${pipelineId}/life_admin`).send({ caseKey: "blocker", title: "Blocker" }).expect(201);
    const blocked = await http.post(`/api/workflows/${pipelineId}/life_admin`).send({ caseKey: "blocked", title: "Blocked" }).expect(201);
    await http
      .put(`/api/life_admin/${blocked.body.case.id}/blockers`)
      .send({ blockedByCaseIds: [blocker.body.case.id] })
      .expect(200);
    await http.get(`/api/life_admin/${blocked.body.case.id}/rollup`).expect(200);
    await http.get(`/api/life_admin/${blocked.body.case.id}/context-pack`).expect(200);
    const conversation = await http.post(`/api/life_admin/${blocked.body.case.id}/open-conversation`).expect(201);
    expect(conversation.body.created).toBe(true);
    expect(conversation.body.issue.description).toContain("Workflow LifeAdmin Context");
    const sameConversation = await http.post(`/api/life_admin/${blocked.body.case.id}/open-conversation`).expect(200);
    expect(sameConversation.body.created).toBe(false);
    expect(sameConversation.body.issue.id).toBe(conversation.body.issue.id);

    const linkedIssue = await http.post(`/api/life_admin/${blocked.body.case.id}/issue-links`)
      .send({ issueId: ingested.body.case.id, role: "work" });
    expect(linkedIssue.status).toBe(404);
    const manualIssue = await db.insert(issues).values({
      companyId: company.id,
      title: "Manual work issue",
      status: "todo",
      priority: "medium",
    }).returning();
    const workLink = await http.post(`/api/life_admin/${blocked.body.case.id}/issue-links`)
      .send({ issueId: manualIssue[0]!.id, role: "work" })
      .expect(201);
    await http.get(`/api/life_admin/${blocked.body.case.id}/issue-links`).expect(200);
    const issueDetail = await http.get(`/api/issues/${manualIssue[0]!.id}`).expect(200);
    expect(issueDetail.body.linkedLifeAdmin).toHaveLength(1);
    expect(issueDetail.body.linkedLifeAdmin[0].id).toBe(blocked.body.case.id);
    await http.delete(`/api/life_admin/${blocked.body.case.id}/issue-links/${workLink.body.id}`).expect(200);

    const [routine] = await db.insert(routines).values({ companyId: company.id, title: "Routine" }).returning();
    await db.insert(pipelineAutomationExecutions).values({
      companyId: company.id,
      caseId: blocked.body.case.id,
      automationId: "retry-me",
      triggeringEventId: randomUUID(),
      routineId: routine!.id,
      status: "failed",
      error: "boom",
    });
    await http.post(`/api/life_admin/${blocked.body.case.id}/automations/retry-me/retry`).expect(200);

    await http.delete(`/api/workflows/${pipelineId}/stages/${stageId}?moveLifeAdminToStageId=${qaStage.body.id}`).expect(200);
  });

  it("patches case content and workspaceRef in one service transaction", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipeline = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({ key: "workspace-patch", name: "Workspace patch" })
      .expect(201);
    const created = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "workspace-case", title: "Workspace case" })
      .expect(201);

    const patched = await http
      .patch(`/api/life_admin/${created.body.case.id}`)
      .send({
        title: "Workspace case updated",
        workspaceRef: { workspacePath: "exports/workspace-case", name: "Workspace case files" },
        expectedVersion: 1,
      })
      .expect(200);

    expect(patched.body.title).toBe("Workspace case updated");
    expect(patched.body.version).toBe(2);
    expect(patched.body.workspaceRef).toEqual({ workspacePath: "exports/workspace-case", name: "Workspace case files" });
    const events = await db.select().from(pipelineCaseEvents).where(eq(pipelineCaseEvents.caseId, created.body.case.id));
    expect(events.map((event) => event.type)).toEqual(["ingested", "updated"]);
    expect(events[1]!.payload).toMatchObject({ materialChanged: true, workspaceRefChanged: true });
  });

  it("hides retired children from the flat case children route", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipeline = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({ key: "hidden-children", name: "Hidden children" })
      .expect(201);
    const parent = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "parent", title: "Parent" })
      .expect(201);
    const visible = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "visible-child", title: "Visible child", parentCaseId: parent.body.case.id })
      .expect(201);
    const hidden = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "hidden-child", title: "Hidden child", parentCaseId: parent.body.case.id })
      .expect(201);
    await db
      .update(pipelineLifeAdmin)
      .set({ hiddenFromBoardAt: new Date(), retiredAt: new Date(), retiredReason: "automation_retry" })
      .where(eq(pipelineLifeAdmin.id, hidden.body.case.id));

    const children = await http.get(`/api/life_admin/${parent.body.case.id}/children`).expect(200);

    expect(children.body.map((row: { case: { id: string; caseKey: string } }) => [row.case.id, row.case.caseKey])).toEqual([
      [visible.body.case.id, "visible-child"],
    ]);
  });

  it("writes an audit event when an agent removes a case issue link", async () => {
    const company = await seedDomain();
    const [agent] = await db.insert(agents).values({
      companyId: company.id,
      name: "Workflow Agent",
      role: "engineer",
      adapterType: "codex_local",
    }).returning();
    await db.insert(companyMemberships).values({
      companyId: company.id,
      principalType: "agent",
      principalId: agent!.id,
      status: "active",
      membershipRole: "member",
    });
    await db.insert(principalPermissionGrants).values({
      companyId: company.id,
      principalType: "agent",
      principalId: agent!.id,
      permissionKey: "workflows:write",
      scope: null,
    });
    const runId = randomUUID();
    const agentActor: Express.Request["actor"] = {
      type: "agent",
      agentId: agent!.id,
      companyId: company.id,
      runId,
      source: "agent_key",
    };
    const http = request(app(agentActor));
    const pipeline = await http.post(`/api/domains/${company.id}/workflows`).send({ key: "unlink", name: "Unlink audit" }).expect(201);
    const created = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "unlink", title: "Unlink audit" })
      .expect(201);
    const [issue] = await db.insert(issues).values({
      companyId: company.id,
      title: "Linked work",
      status: "todo",
      priority: "medium",
    }).returning();

    const link = await http
      .post(`/api/life_admin/${created.body.case.id}/issue-links`)
      .send({ issueId: issue!.id, role: "work" })
      .expect(201);
    await http.delete(`/api/life_admin/${created.body.case.id}/issue-links/${link.body.id}`).expect(200);

    const events = await http.get(`/api/life_admin/${created.body.case.id}/events`).expect(200);
    const linkEvents = events.body.items.filter((event: { type: string }) => event.type === "issue_linked" || event.type === "issue_unlinked");
    expect(linkEvents.map((event: { type: string }) => event.type)).toEqual(["issue_linked", "issue_unlinked"]);
    expect(linkEvents[1]).toMatchObject({
      actorType: "agent",
      actorAgentId: agent!.id,
      runId,
      payload: { issueId: issue!.id, role: "work", linkId: link.body.id },
    });
    const remainingLinks = await db.select().from(pipelineCaseIssueLinks).where(eq(pipelineCaseIssueLinks.id, link.body.id));
    expect(remainingLinks).toHaveLength(0);
  });

  it("includes the source automation metadata for life_admin built by automation", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const [routine] = await db.insert(routines).values({
      companyId: company.id,
      title: "Break down feature",
    }).returning();
    const [sourceWorkflow] = await db.insert(workflows).values({
      companyId: company.id,
      key: "features",
      name: "Features",
    }).returning();
    const [sourceStage] = await db.insert(pipelineStages).values({
      pipelineId: sourceWorkflow!.id,
      key: "plan",
      name: "Plan",
      kind: "working",
      position: 100,
      config: { onEnter: { type: "run_routine", id: "build-content", routineId: routine!.id } },
    }).returning();
    const [targetWorkflow] = await db.insert(workflows).values({
      companyId: company.id,
      key: "content",
      name: "Content",
    }).returning();
    const [targetStage] = await db.insert(pipelineStages).values({
      pipelineId: targetWorkflow!.id,
      key: "draft",
      name: "Draft",
      kind: "working",
      position: 100,
      config: {},
    }).returning();
    const [sourceLifeAdmin] = await db.insert(pipelineLifeAdmin).values({
      companyId: company.id,
      pipelineId: sourceWorkflow!.id,
      stageId: sourceStage!.id,
      caseKey: "checkboxes",
      title: "Checkbox confirmation interactions",
      fields: {},
    }).returning();
    const [execution] = await db.insert(pipelineAutomationExecutions).values({
      companyId: company.id,
      caseId: sourceLifeAdmin!.id,
      automationId: "build-content",
      triggeringEventId: randomUUID(),
      routineId: routine!.id,
      status: "succeeded",
    }).returning();
    const [childLifeAdmin] = await db.insert(pipelineLifeAdmin).values({
      companyId: company.id,
      pipelineId: targetWorkflow!.id,
      stageId: targetStage!.id,
      caseKey: "api-how-to",
      title: "API how-to",
      fields: {},
      parentCaseId: sourceLifeAdmin!.id,
      parentCaseVersion: sourceLifeAdmin!.version,
      requestKey: "article:api-how-to",
      automationAttemptId: execution!.id,
    }).returning();

    const detail = await http.get(`/api/life_admin/${childLifeAdmin!.id}`).expect(200);

    expect(detail.body.builtFromAutomation).toMatchObject({
      execution: {
        id: execution!.id,
        automationId: "build-content",
        status: "succeeded",
      },
      routine: {
        id: routine!.id,
        title: "Break down feature",
      },
      pipeline: {
        id: sourceWorkflow!.id,
        key: "features",
        name: "Features",
      },
      stage: {
        id: sourceStage!.id,
        key: "plan",
        name: "Plan",
        kind: "working",
      },
      case: {
        id: sourceLifeAdmin!.id,
        caseKey: "checkboxes",
        title: "Checkbox confirmation interactions",
        pipelineId: sourceWorkflow!.id,
      },
    });
  });

  it("carries route-saved stage automation workspace context into detail responses and execution issues", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const agent = await seedAutomationAgent(company.id);
    const { projectId, projectWorkspaceId, executionWorkspaceId } =
      await seedProjectWorkspaceFixture(company.id, "Route automation");
    await instanceSettingsService(db).updateExperimental({ enableIsolatedWorkspaces: true });

    const pipeline = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "route-workspace-automation",
        name: "Route workspace automation",
      })
      .expect(201);
    const stageId = pipeline.body.stages.find((stage: { key: string }) => stage.key === "in_progress").id as string;

    await http
      .patch(`/api/workflows/${pipeline.body.id}/stages/${stageId}`)
      .send({
        config: {
          automation: {
            assigneeAgentId: agent.id,
            instructionsBody: "Use the selected project workspace.",
            projectId,
            projectWorkspaceId,
            executionWorkspaceId,
            executionWorkspacePreference: "reuse_existing",
            executionWorkspaceSettings: { mode: "isolated_workspace" },
          },
        },
      })
      .expect(200);

    const detail = await http.get(`/api/workflows/${pipeline.body.id}`).expect(200);
    const automatedStage = detail.body.stages.find((stage: { key: string }) => stage.key === "in_progress");
    expect(automatedStage.config.automation).toMatchObject({
      assigneeAgentId: agent.id,
      instructionsBody: "Use the selected project workspace.",
      projectId,
      projectWorkspaceId,
      executionWorkspaceId,
      executionWorkspacePreference: "reuse_existing",
      executionWorkspaceSettings: { mode: "isolated_workspace" },
    });

    const created = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "route-workspace-context", title: "Route workspace context" })
      .expect(201);
    const moved = await http
      .post(`/api/life_admin/${created.body.case.id}/transition`)
      .send({ toStageKey: "in_progress", expectedVersion: 1 })
      .expect(200);

    expect(moved.body.automationExecution.status).toBe("succeeded");
    const executionIssueId = moved.body.automationExecution.execution.executionIssueId as string;
    const [issue] = await db
      .select({
        projectId: issues.projectId,
        projectWorkspaceId: issues.projectWorkspaceId,
        executionWorkspaceId: issues.executionWorkspaceId,
        executionWorkspacePreference: issues.executionWorkspacePreference,
        executionWorkspaceSettings: issues.executionWorkspaceSettings,
      })
      .from(issues)
      .where(eq(issues.id, executionIssueId));

    expect(issue).toEqual({
      projectId,
      projectWorkspaceId,
      executionWorkspaceId,
      executionWorkspacePreference: "reuse_existing",
      executionWorkspaceSettings: { mode: "isolated_workspace" },
    });
  });

  it("fails automation execution when the selected project workspace belongs to a different project", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const agent = await seedAutomationAgent(company.id);
    const source = await seedProjectWorkspaceFixture(company.id, "Source project");
    const mismatched = await seedProjectWorkspaceFixture(company.id, "Mismatched project");
    await instanceSettingsService(db).updateExperimental({ enableIsolatedWorkspaces: true });

    const pipeline = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "mismatched-workspace-automation",
        name: "Mismatched workspace automation",
      })
      .expect(201);
    const stageId = pipeline.body.stages.find((stage: { key: string }) => stage.key === "in_progress").id as string;

    await http
      .patch(`/api/workflows/${pipeline.body.id}/stages/${stageId}`)
      .send({
        config: {
          automation: {
            assigneeAgentId: agent.id,
            instructionsBody: "This should fail before issue creation.",
            projectId: source.projectId,
            projectWorkspaceId: mismatched.projectWorkspaceId,
          },
        },
      })
      .expect(200);

    const created = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "mismatched-workspace", title: "Mismatched workspace" })
      .expect(201);
    const moved = await http
      .post(`/api/life_admin/${created.body.case.id}/transition`)
      .send({ toStageKey: "in_progress", expectedVersion: 1 })
      .expect(200);

    expect(moved.body.automationExecution.status).toBe("failed");
    const executionId = moved.body.automationExecution.execution.id as string;
    const [execution] = await db
      .select()
      .from(pipelineAutomationExecutions)
      .where(eq(pipelineAutomationExecutions.id, executionId));
    expect(execution!.executionIssueId).toBeNull();
    expect(execution!.error).toContain("Project workspace must belong to the selected project");
  });

  it("keeps legacy stage automation with only assignee and instructions compatible", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const agent = await seedAutomationAgent(company.id);

    const pipeline = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "legacy-automation",
        name: "Legacy automation",
      })
      .expect(201);
    const stageId = pipeline.body.stages.find((stage: { key: string }) => stage.key === "in_progress").id as string;

    await http
      .patch(`/api/workflows/${pipeline.body.id}/stages/${stageId}`)
      .send({
        config: {
          automation: {
            assigneeAgentId: agent.id,
            instructionsBody: "Legacy automation body.",
          },
        },
      })
      .expect(200);

    const detail = await http.get(`/api/workflows/${pipeline.body.id}`).expect(200);
    const automatedStage = detail.body.stages.find((stage: { key: string }) => stage.key === "in_progress");
    expect(automatedStage.config.automation).toMatchObject({
      assigneeAgentId: agent.id,
      titleTemplate: PIPELINE_AUTOMATION_DEFAULT_TITLE_TEMPLATE,
      instructionsBody: "Legacy automation body.",
      projectId: null,
      projectWorkspaceId: null,
      executionWorkspaceId: null,
      executionWorkspacePreference: null,
      executionWorkspaceSettings: null,
    });

    await db
      .update(routines)
      .set({ title: "Custom automation for {{case_key}}" })
      .where(eq(routines.id, automatedStage.config.automation.routineId));
    const detailAfterRoutineEdit = await http.get(`/api/workflows/${pipeline.body.id}`).expect(200);
    const editedStage = detailAfterRoutineEdit.body.stages.find((stage: { key: string }) => stage.key === "in_progress");
    expect(editedStage.config.automation.titleTemplate).toBe("Custom automation for {{case_key}}");

    const created = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "legacy-automation", title: "Legacy automation" })
      .expect(201);
    const moved = await http
      .post(`/api/life_admin/${created.body.case.id}/transition`)
      .send({ toStageKey: "in_progress", expectedVersion: 1 })
      .expect(200);

    expect(moved.body.automationExecution.status).toBe("succeeded");
    const executionIssueId = moved.body.automationExecution.execution.executionIssueId as string;
    const [issue] = await db
      .select({
        projectId: issues.projectId,
        projectWorkspaceId: issues.projectWorkspaceId,
        executionWorkspaceId: issues.executionWorkspaceId,
        executionWorkspaceSettings: issues.executionWorkspaceSettings,
      })
      .from(issues)
      .where(eq(issues.id, executionIssueId));

    expect(issue).toEqual({
      projectId: null,
      projectWorkspaceId: null,
      executionWorkspaceId: null,
      executionWorkspaceSettings: null,
    });
  });

  it("paginates and caps case event responses", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipeline = await http.post(`/api/domains/${company.id}/workflows`).send({ key: "event-cap", name: "Event cap" }).expect(201);
    const created = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "event-cap", title: "Event cap" })
      .expect(201);
    const caseId = created.body.case.id as string;
    const baseTime = Date.now() + 1_000;

    await db.insert(pipelineCaseEvents).values(
      Array.from({ length: PIPELINE_CASE_EVENTS_MAX_LIMIT + 25 }, (_, index) => ({
        companyId: company.id,
        caseId,
        type: "updated",
        actorType: "user",
        actorUserId: "board-user",
        payload: { index },
        createdAt: new Date(baseTime + index),
        updatedAt: new Date(baseTime + index),
      })),
    );

    const firstPage = await http
      .get(`/api/life_admin/${caseId}/events?limit=${PIPELINE_CASE_EVENTS_MAX_LIMIT + 50}`)
      .expect(200);
    expect(firstPage.body.items).toHaveLength(PIPELINE_CASE_EVENTS_MAX_LIMIT);
    expect(firstPage.body.pagination).toMatchObject({
      limit: PIPELINE_CASE_EVENTS_MAX_LIMIT,
      offset: 0,
      nextOffset: PIPELINE_CASE_EVENTS_MAX_LIMIT,
      hasMore: true,
      order: "asc",
    });

    const secondPage = await http
      .get(`/api/life_admin/${caseId}/events?limit=10&offset=${PIPELINE_CASE_EVENTS_MAX_LIMIT}`)
      .expect(200);
    expect(secondPage.body.items).toHaveLength(10);
    expect(secondPage.body.pagination).toMatchObject({
      limit: 10,
      offset: PIPELINE_CASE_EVENTS_MAX_LIMIT,
      nextOffset: PIPELINE_CASE_EVENTS_MAX_LIMIT + 10,
      hasMore: true,
      order: "asc",
    });
  });

  it("returns a bounded context-pack event tail for large histories", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipeline = await http.post(`/api/domains/${company.id}/workflows`).send({ key: "context-tail", name: "Context tail" }).expect(201);
    const created = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "context-tail", title: "Context tail" })
      .expect(201);
    const caseId = created.body.case.id as string;
    const eventCount = PIPELINE_CONTEXT_PACK_EVENT_LIMIT + 12;
    const baseTime = Date.now() + 1_000;

    await db.insert(pipelineCaseEvents).values(
      Array.from({ length: eventCount }, (_, index) => ({
        companyId: company.id,
        caseId,
        type: "updated",
        actorType: "user",
        actorUserId: "board-user",
        payload: { index },
        createdAt: new Date(baseTime + index),
        updatedAt: new Date(baseTime + index),
      })),
    );

    const pack = await http.get(`/api/life_admin/${caseId}/context-pack`).expect(200);
    expect(pack.body.events).toHaveLength(PIPELINE_CONTEXT_PACK_EVENT_LIMIT);
    expect(pack.body.events.map((event: { payload: { index: number } }) => event.payload.index)).toEqual(
      Array.from(
        { length: PIPELINE_CONTEXT_PACK_EVENT_LIMIT },
        (_, index) => eventCount - PIPELINE_CONTEXT_PACK_EVENT_LIMIT + index,
      ),
    );
  });

  it("returns 404 for cross-company pipeline route classes", async () => {
    const company = await seedDomain();
    const ownerHttp = request(app(boardActor));
    const pipeline = await ownerHttp
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "cross-company",
        name: "Cross-company",
        stages: [
          { key: "intake", name: "Intake", kind: "open", position: 100 },
          { key: "review", name: "Review", kind: "review", position: 200, config: { approveToStageKey: "done", rejectToStageKey: "cancelled" } },
          { key: "done", name: "Done", kind: "done", position: 900 },
          { key: "cancelled", name: "Cancelled", kind: "cancelled", position: 1000 },
        ],
      })
      .expect(201);
    await ownerHttp.put(`/api/workflows/${pipeline.body.id}/documents/guidance`).send({ body: "Use the rubric." }).expect(200);
    const createdLifeAdmin = await ownerHttp
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "cross-company", title: "Cross-company case" })
      .expect(201);
    const caseId = createdLifeAdmin.body.case.id as string;
    await ownerHttp.post(`/api/life_admin/${caseId}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);
    const [manualIssue] = await db.insert(issues).values({
      companyId: company.id,
      title: "Manual work issue",
      status: "todo",
      priority: "medium",
    }).returning();
    const issueLink = await ownerHttp
      .post(`/api/life_admin/${caseId}/issue-links`)
      .send({ issueId: manualIssue!.id, role: "work" })
      .expect(201);
    const [routine] = await db.insert(routines).values({ companyId: company.id, title: "Routine" }).returning();
    await db.insert(pipelineAutomationExecutions).values({
      companyId: company.id,
      caseId,
      automationId: "retry-me",
      triggeringEventId: randomUUID(),
      routineId: routine!.id,
      status: "failed",
      error: "boom",
    });
    const otherAgent: Express.Request["actor"] = {
      type: "agent",
      agentId: randomUUID(),
      companyId: randomUUID(),
      runId: randomUUID(),
      source: "agent_key",
    };
    const wrongCompanyHttp = request(app(otherAgent));
    const routes = [
      { name: "pipeline detail", method: "get", path: `/api/workflows/${pipeline.body.id}` },
      { name: "case detail", method: "get", path: `/api/life_admin/${caseId}` },
      { name: "review inbox", method: "get", path: `/api/domains/${company.id}/review-life_admin` },
      {
        name: "review bulk mutation",
        method: "post",
        path: `/api/domains/${company.id}/review-life_admin/bulk`,
        body: { items: [{ caseId, decision: "approve", expectedVersion: 2 }] },
      },
      {
        name: "review detail mutation",
        method: "post",
        path: `/api/life_admin/${caseId}/review`,
        body: { decision: "approve", expectedVersion: 2 },
      },
      { name: "document read", method: "get", path: `/api/workflows/${pipeline.body.id}/documents/guidance` },
      {
        name: "document write",
        method: "put",
        path: `/api/workflows/${pipeline.body.id}/documents/guidance`,
        body: { body: "wrong-company update" },
      },
      {
        name: "issue-link create mutation",
        method: "post",
        path: `/api/life_admin/${caseId}/issue-links`,
        body: { issueId: manualIssue!.id, role: "work" },
      },
      {
        name: "issue-link delete mutation",
        method: "delete",
        path: `/api/life_admin/${caseId}/issue-links/${issueLink.body.id}`,
      },
      {
        name: "automation retry mutation",
        method: "post",
        path: `/api/life_admin/${caseId}/automations/retry-me/retry`,
      },
      { name: "case events", method: "get", path: `/api/life_admin/${caseId}/events` },
      { name: "case rollup", method: "get", path: `/api/life_admin/${caseId}/rollup` },
      { name: "case context-pack", method: "get", path: `/api/life_admin/${caseId}/context-pack` },
    ] as const;

    for (const route of routes) {
      let requestBuilder = wrongCompanyHttp[route.method](route.path);
      if ("body" in route) requestBuilder = requestBuilder.send(route.body);
      const res = await requestBuilder;
      expect(res.status, route.name).toBe(404);
    }
  });

  it("rejects agent mutations without a run id", async () => {
    const company = await seedDomain();
    const agentActor: Express.Request["actor"] = {
      type: "agent",
      agentId: randomUUID(),
      companyId: company.id,
      source: "agent_key",
    };

    const res = await request(app(agentActor))
      .post(`/api/domains/${company.id}/workflows`)
      .send({ key: "agent", name: "Agent pipeline" });

    expect(res.status).toBe(422);
    expect(res.body.code).toBe("run_id_required");
  });

  it("rejects agent exits from human review stages", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipelineRes = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "review-authz",
        name: "Review authz",
        stages: [
          { key: "intake", name: "Intake", kind: "open", position: 100 },
          { key: "review", name: "Review", kind: "review", position: 200, config: { approveToStageKey: "done", rejectToStageKey: "cancelled" } },
          { key: "done", name: "Done", kind: "done", position: 900 },
          { key: "cancelled", name: "Cancelled", kind: "cancelled", position: 1000 },
        ],
      })
      .expect(201);
    const caseRes = await http.post(`/api/workflows/${pipelineRes.body.id}/life_admin`).send({ caseKey: "review", title: "Review me" }).expect(201);
    await http.post(`/api/life_admin/${caseRes.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);

    const agentActor: Express.Request["actor"] = {
      type: "agent",
      agentId: randomUUID(),
      companyId: company.id,
      runId: randomUUID(),
      source: "agent_key",
    };
    const res = await request(app(agentActor))
      .post(`/api/life_admin/${caseRes.body.case.id}/transition`)
      .send({ toStageKey: "done", expectedVersion: 2 });

    expect(res.status).toBe(403);
    expect(res.body.code).toBe("review_required");
  });

  it("validates review stage config on create and update", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));

    await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "bad-review",
        name: "Bad review",
        stages: [
          { key: "intake", name: "Intake", kind: "open", position: 100 },
          { key: "review", name: "Review", kind: "review", position: 200 },
          { key: "done", name: "Done", kind: "done", position: 900 },
          { key: "cancelled", name: "Cancelled", kind: "cancelled", position: 1000 },
        ],
      })
      .expect(422);

    const pipeline = await http.post(`/api/domains/${company.id}/workflows`).send({ key: "valid-review", name: "Valid review" }).expect(201);
    const intake = pipeline.body.stages.find((stage: { key: string }) => stage.key === "intake");
    await http.patch(`/api/workflows/${pipeline.body.id}/stages/${intake.id}`).send({ kind: "review" }).expect(422);

    await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "bad-request-changes-target",
        name: "Bad request changes target",
        stages: [
          { key: "intake", name: "Intake", kind: "open", position: 100 },
          {
            key: "review",
            name: "Review",
            kind: "review",
            position: 200,
            config: {
              approveToStageKey: "done",
              rejectToStageKey: "cancelled",
              requestChangesToStageKey: "missing",
            },
          },
          { key: "done", name: "Done", kind: "done", position: 900 },
          { key: "cancelled", name: "Cancelled", kind: "cancelled", position: 1000 },
        ],
      })
      .expect(422);
  });

  it("applies review decisions atomically with edits and stores reject reasons verbatim", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipeline = await http.post(`/api/domains/${company.id}/workflows`).send({ key: "review-decisions", name: "Review decisions" }).expect(201);

    const approved = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "approve-edit", title: "Approve edit" })
      .expect(201);
    await http.post(`/api/life_admin/${approved.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);
    const approval = await http
      .post(`/api/life_admin/${approved.body.case.id}/review`)
      .send({
        decision: "approve",
        expectedVersion: 2,
        edits: { title: "Approved title", fields: { channel: "blog" } },
      })
      .expect(200);
    expect(approval.body.case.version).toBe(4);
    expect(approval.body.updateEvent.payload.version).toBe(3);
    const approvedDetail = await http.get(`/api/life_admin/${approved.body.case.id}`).expect(200);
    expect(approvedDetail.body.case.title).toBe("Approved title");
    expect(approvedDetail.body.case.fields).toEqual({ channel: "blog" });
    const approvedEvents = await http.get(`/api/life_admin/${approved.body.case.id}/events`).expect(200);
    expect(approvedEvents.body.items.map((event: { type: string }) => event.type)).toEqual([
      "ingested",
      "transitioned",
      "updated",
      "transitioned",
      "review_decided",
    ]);

    const rejected = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "reject-reason", title: "Reject reason" })
      .expect(201);
    await http.post(`/api/life_admin/${rejected.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);
    await http.post(`/api/life_admin/${rejected.body.case.id}/review`).send({ decision: "reject", expectedVersion: 2 }).expect(422);
    const reason = "  Keep this exact reason.  ";
    await http.post(`/api/life_admin/${rejected.body.case.id}/review`).send({ decision: "reject", reason, expectedVersion: 2 }).expect(200);
    const rejectedEvents = await http.get(`/api/life_admin/${rejected.body.case.id}/events`).expect(200);
    const reviewEvent = rejectedEvents.body.items.find((event: { type: string }) => event.type === "review_decided");
    expect(reviewEvent.payload.reason).toBe(reason);
  });

  it("routes request-changes review decisions to the configured stage", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipeline = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "review-request-changes",
        name: "Review request changes",
        stages: [
          { key: "drafting", name: "Drafting", kind: "working", position: 100 },
          {
            key: "review",
            name: "Review",
            kind: "review",
            position: 200,
            config: {
              approveToStageKey: "done",
              rejectToStageKey: "cancelled",
              requestChangesToStageKey: "drafting",
            },
          },
          { key: "done", name: "Done", kind: "done", position: 900 },
          { key: "cancelled", name: "Cancelled", kind: "cancelled", position: 1000 },
        ],
      })
      .expect(201);

    const created = await http
      .post(`/api/workflows/${pipeline.body.id}/life_admin`)
      .send({ caseKey: "needs-edits", title: "Needs edits" })
      .expect(201);
    await http.post(`/api/life_admin/${created.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);
    await http
      .post(`/api/life_admin/${created.body.case.id}/review`)
      .send({ decision: "request_changes", expectedVersion: 2 })
      .expect(422);

    const changed = await http
      .post(`/api/life_admin/${created.body.case.id}/review`)
      .send({ decision: "request_changes", reason: "Tighten the framing", expectedVersion: 2 })
      .expect(200);
    expect(changed.body.case.version).toBe(3);
    const detail = await http.get(`/api/life_admin/${created.body.case.id}`).expect(200);
    expect(detail.body.stage.key).toBe("drafting");
    const events = await http.get(`/api/life_admin/${created.body.case.id}/events`).expect(200);
    const reviewEvent = events.body.items.find((event: { type: string }) => event.type === "review_decided");
    expect(reviewEvent.payload.decision).toBe("request_changes");
    expect(reviewEvent.payload.reason).toBe("Tighten the framing");

    const defaultWorkflow = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({ key: "review-request-changes-missing", name: "Review request changes missing" })
      .expect(201);
    const missingConfigLifeAdmin = await http
      .post(`/api/workflows/${defaultWorkflow.body.id}/life_admin`)
      .send({ caseKey: "missing-config", title: "Missing config" })
      .expect(201);
    await http.post(`/api/life_admin/${missingConfigLifeAdmin.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);
    const missingConfig = await http
      .post(`/api/life_admin/${missingConfigLifeAdmin.body.case.id}/review`)
      .send({ decision: "request_changes", reason: "Needs a loop", expectedVersion: 2 })
      .expect(422);
    expect(missingConfig.body.code).toBe("validation");

    const optionalRejectReasonWorkflow = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "review-optional-reject-reason",
        name: "Review optional reject reason",
        stages: [
          { key: "drafting", name: "Drafting", kind: "working", position: 100 },
          {
            key: "review",
            name: "Review",
            kind: "review",
            position: 200,
            config: {
              approveToStageKey: "done",
              rejectToStageKey: "cancelled",
              requestChangesToStageKey: "drafting",
              requireRejectReason: false,
              requireRequestChangesReason: false,
            },
          },
          { key: "done", name: "Done", kind: "done", position: 900 },
          { key: "cancelled", name: "Cancelled", kind: "cancelled", position: 1000 },
        ],
      })
      .expect(201);
    const optionalReject = await http
      .post(`/api/workflows/${optionalRejectReasonWorkflow.body.id}/life_admin`)
      .send({ caseKey: "optional-reject", title: "Optional reject" })
      .expect(201);
    await http.post(`/api/life_admin/${optionalReject.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);
    await http.post(`/api/life_admin/${optionalReject.body.case.id}/review`).send({ decision: "reject", expectedVersion: 2 }).expect(200);

    const optionalRequestChangesReason = await http
      .post(`/api/workflows/${optionalRejectReasonWorkflow.body.id}/life_admin`)
      .send({ caseKey: "request-changes-reason", title: "Request changes reason" })
      .expect(201);
    await http.post(`/api/life_admin/${optionalRequestChangesReason.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);
    await http
      .post(`/api/life_admin/${optionalRequestChangesReason.body.case.id}/review`)
      .send({ decision: "request_changes", expectedVersion: 2 })
      .expect(200);
  });

  it("aggregates the review inbox across workflows with parent and review config context", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const first = await http.post(`/api/domains/${company.id}/workflows`).send({ key: "inbox-a", name: "Inbox A" }).expect(201);
    const second = await http.post(`/api/domains/${company.id}/workflows`).send({ key: "inbox-b", name: "Inbox B" }).expect(201);

    const parent = await http
      .post(`/api/workflows/${first.body.id}/life_admin`)
      .send({ caseKey: "parent", title: "Parent" })
      .expect(201);
    const child = await http
      .post(`/api/workflows/${first.body.id}/life_admin`)
      .send({ caseKey: "child", title: "Child", parentCaseId: parent.body.case.id })
      .expect(201);
    await http.post(`/api/life_admin/${child.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);

    const other = await http
      .post(`/api/workflows/${second.body.id}/life_admin`)
      .send({ caseKey: "other", title: "Other" })
      .expect(201);
    await http.post(`/api/life_admin/${other.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);

    const notReview = await http
      .post(`/api/workflows/${second.body.id}/life_admin`)
      .send({ caseKey: "not-review", title: "Not review" })
      .expect(201);
    await http.post(`/api/life_admin/${notReview.body.case.id}/transition`).send({ toStageKey: "done", expectedVersion: 1 }).expect(200);

    const inbox = await http.get(`/api/domains/${company.id}/review-life_admin`).expect(200);
    expect(inbox.body).toHaveLength(2);
    expect(inbox.body.map((row: { pipeline: { key: string } }) => row.pipeline.key).sort()).toEqual(["inbox-a", "inbox-b"]);
    const childRow = inbox.body.find((row: { case: { id: string } }) => row.case.id === child.body.case.id);
    expect(childRow.parentLifeAdmin.id).toBe(parent.body.case.id);
    expect(childRow.reviewConfig).toMatchObject({
      approveToStageKey: "done",
      rejectToStageKey: "cancelled",
      requireRejectReason: true,
      reviewerKind: "human",
    });
  });

  it("bulk reviews partial successes without aborting stale items", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipeline = await http
      .post(`/api/domains/${company.id}/workflows`)
      .send({
        key: "bulk-review",
        name: "Bulk review",
        stages: [
          { key: "intake", name: "Intake", kind: "open", position: 100 },
          { key: "in_progress", name: "In progress", kind: "working", position: 200 },
          {
            key: "review",
            name: "Review",
            kind: "review",
            position: 300,
            config: {
              approveToStageKey: "done",
              rejectToStageKey: "cancelled",
              requestChangesToStageKey: "in_progress",
            },
          },
          { key: "done", name: "Done", kind: "done", position: 900 },
          { key: "cancelled", name: "Cancelled", kind: "cancelled", position: 1000 },
        ],
      })
      .expect(201);
    const caseIds: string[] = [];
    for (let index = 0; index < 50; index += 1) {
      const created = await http
        .post(`/api/workflows/${pipeline.body.id}/life_admin`)
        .send({ caseKey: `bulk-${index}`, title: `Bulk ${index}` })
        .expect(201);
      await http.post(`/api/life_admin/${created.body.case.id}/transition`).send({ toStageKey: "review", expectedVersion: 1 }).expect(200);
      caseIds.push(created.body.case.id);
    }
    for (const staleCaseId of caseIds.slice(0, 3)) {
      await http.patch(`/api/life_admin/${staleCaseId}`).send({ title: "Stale before bulk", expectedVersion: 2 }).expect(200);
    }

    const bulk = await http
      .post(`/api/domains/${company.id}/review-life_admin/bulk`)
      .send({
        items: caseIds.map((caseId, index) => index === 3
          ? { caseId, decision: "request_changes", reason: "Revise this item", expectedVersion: 2 }
          : { caseId, decision: "approve", expectedVersion: 2 }),
      })
      .expect(200);

    expect(bulk.body.results.filter((item: { ok: boolean }) => item.ok)).toHaveLength(47);
    const failed = bulk.body.results.filter((item: { ok: boolean }) => !item.ok);
    expect(failed).toHaveLength(3);
    expect(failed.every((item: { error: { code: string } }) => item.error.code === "version_conflict")).toBe(true);
    const requestChangesDetail = await http.get(`/api/life_admin/${caseIds[3]}`).expect(200);
    expect(requestChangesDetail.body.stage.key).toBe("in_progress");
  });

  it("returns conflict bodies with code, current version, and stage", async () => {
    const company = await seedDomain();
    const http = request(app(boardActor));
    const pipelineRes = await http.post(`/api/domains/${company.id}/workflows`).send({ key: "conflict", name: "Conflict" }).expect(201);
    const caseRes = await http.post(`/api/workflows/${pipelineRes.body.id}/life_admin`).send({ caseKey: "conflict", title: "Conflict" }).expect(201);
    await http.patch(`/api/life_admin/${caseRes.body.case.id}`).send({ title: "Updated", expectedVersion: 1 }).expect(200);

    const res = await http.patch(`/api/life_admin/${caseRes.body.case.id}`).send({ title: "Stale", expectedVersion: 1 });

    expect(res.status).toBe(409);
    expect(res.body.code).toBe("version_conflict");
    expect(res.body.details.version).toBe(2);
    expect(res.body.details.stage.key).toBe("intake");
  });
});

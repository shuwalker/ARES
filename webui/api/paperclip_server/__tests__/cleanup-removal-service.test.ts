import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  activityLog,
  agents,
  domains,
  domainSkills,
  createDb,
  documents,
  documentRevisions,
  heartbeatRunEvents,
  heartbeatRuns,
  issueComments,
  issueDocuments,
  issueExecutionDecisions,
  issueReadStates,
  issues,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { agentService } from "../services/agents.ts";
import { domainService } from "../services/domains.ts";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping cleanup removal service tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("cleanup removal services", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-cleanup-removal-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(heartbeatRunEvents);
    await db.delete(activityLog);
    await db.delete(issueReadStates);
    await db.delete(issueComments);
    await db.delete(issueExecutionDecisions);
    await db.delete(documentRevisions);
    await db.delete(documents);
    await db.delete(domainSkills);
    await db.delete(heartbeatRuns);
    await db.delete(issues);
    await db.delete(agents);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  async function seedFixture() {
    const domainId = randomUUID();
    const agentId = randomUUID();
    const issueId = randomUUID();
    const runId = randomUUID();
    const issuePrefix = `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`;

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "CodexCoder",
      role: "engineer",
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });

    await db.insert(issues).values({
      id: issueId,
      domainId,
      title: "Regression fixture",
      status: "todo",
      priority: "medium",
      assigneeAgentId: agentId,
      createdByUserId: "user-1",
    });

    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId,
      invocationSource: "assignment",
      status: "completed",
      contextSnapshot: { issueId },
    });

    return { agentId, domainId, issueId, runId };
  }

  it("removes agent-owned issue comments and run-linked activity before deleting the agent", async () => {
    const { agentId, domainId, issueId, runId } = await seedFixture();

    await db.insert(issueComments).values({
      id: randomUUID(),
      domainId,
      issueId,
      authorAgentId: agentId,
      body: "Agent-authored comment",
    });

    await db.insert(activityLog).values({
      id: randomUUID(),
      domainId,
      actorType: "agent",
      actorId: agentId,
      action: "heartbeat.completed",
      entityType: "issue",
      entityId: issueId,
      runId,
      details: {},
    });

    await db.insert(issueExecutionDecisions).values({
      id: randomUUID(),
      domainId,
      issueId,
      stageId: randomUUID(),
      stageType: "review",
      actorAgentId: agentId,
      outcome: "approved",
      body: "Looks good",
      createdByRunId: runId,
    });

    const removed = await agentService(db).remove(agentId);

    expect(removed?.id).toBe(agentId);
    await expect(db.select().from(agents).where(eq(agents.id, agentId))).resolves.toHaveLength(0);
    await expect(db.select().from(heartbeatRuns).where(eq(heartbeatRuns.id, runId))).resolves.toHaveLength(0);
    await expect(db.select().from(issueComments).where(eq(issueComments.issueId, issueId))).resolves.toHaveLength(0);
    await expect(db.select().from(activityLog).where(eq(activityLog.domainId, domainId))).resolves.toHaveLength(0);
  });

  it("removes issue read states and activity rows before deleting the domain", async () => {
    const { domainId, issueId, runId } = await seedFixture();
    const documentId = randomUUID();
    const revisionId = randomUUID();

    await db.insert(issueReadStates).values({
      id: randomUUID(),
      domainId,
      issueId,
      userId: "user-1",
    });

    await db.insert(domainSkills).values({
      id: randomUUID(),
      domainId,
      key: "paperclipai/paperclip/paperclip",
      slug: "paperclip",
      name: "Paperclip",
      markdown: "# Paperclip",
    });

    await db.insert(activityLog).values({
      id: randomUUID(),
      domainId,
      actorType: "system",
      actorId: "system",
      action: "run.created",
      entityType: "run",
      entityId: runId,
      runId,
      details: {},
    });

    await db.insert(documents).values({
      id: documentId,
      domainId,
      title: "Run summary",
      latestBody: "body",
      latestRevisionId: revisionId,
      latestRevisionNumber: 1,
      createdByAgentId: null,
      createdByUserId: "user-1",
      updatedByAgentId: null,
      updatedByUserId: "user-1",
    });

    await db.insert(issueDocuments).values({
      id: randomUUID(),
      domainId,
      issueId,
      documentId,
      key: "summary",
    });

    await db.insert(documentRevisions).values({
      id: revisionId,
      domainId,
      documentId,
      revisionNumber: 1,
      title: "Run summary",
      format: "markdown",
      body: "body",
      createdByAgentId: null,
      createdByUserId: "user-1",
      createdByRunId: runId,
    });

    const removed = await domainService(db).remove(domainId);

    expect(removed?.id).toBe(domainId);
    await expect(db.select().from(domains).where(eq(domains.id, domainId))).resolves.toHaveLength(0);
    await expect(db.select().from(issues).where(eq(issues.id, issueId))).resolves.toHaveLength(0);
    await expect(db.select().from(documents).where(eq(documents.id, documentId))).resolves.toHaveLength(0);
    await expect(db.select().from(documentRevisions).where(eq(documentRevisions.id, revisionId))).resolves.toHaveLength(0);
    await expect(db.select().from(issueReadStates).where(eq(issueReadStates.domainId, domainId))).resolves.toHaveLength(0);
    await expect(db.select().from(activityLog).where(eq(activityLog.domainId, domainId))).resolves.toHaveLength(0);
  });

  it("removes heartbeat events by run id before deleting domain-owned runs", async () => {
    const { agentId, domainId, runId } = await seedFixture();
    const otherDomainId = randomUUID();

    await db.insert(domains).values({
      id: otherDomainId,
      name: "Other Domain",
      issuePrefix: `O${otherDomainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(heartbeatRunEvents).values({
      domainId: otherDomainId,
      runId,
      agentId,
      seq: 1,
      eventType: "output",
      message: "event with mismatched domain scope",
    });

    const removed = await domainService(db).remove(domainId);

    expect(removed?.id).toBe(domainId);
    await expect(db.select().from(heartbeatRuns).where(eq(heartbeatRuns.id, runId))).resolves.toHaveLength(0);
    await expect(db.select().from(heartbeatRunEvents).where(eq(heartbeatRunEvents.runId, runId))).resolves.toHaveLength(0);
    await expect(db.select().from(domains).where(eq(domains.id, otherDomainId))).resolves.toHaveLength(1);
  });
});

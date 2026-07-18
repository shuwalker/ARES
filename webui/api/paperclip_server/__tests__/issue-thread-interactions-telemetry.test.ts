import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  agents,
  domains,
  createDb,
  documentRevisions,
  documents,
  goals,
  issueComments,
  issueDocuments,
  issueThreadInteractions,
  issues,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { issueThreadInteractionService } from "../services/issue-thread-interactions.js";

const telemetryMocks = vi.hoisted(() => ({
  track: vi.fn(),
  getTelemetryClient: vi.fn(),
}));

vi.mock("../telemetry.js", () => ({
  getTelemetryClient: telemetryMocks.getTelemetryClient,
}));

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

describeEmbeddedPostgres("issueThreadInteractionService telemetry", () => {
  let db!: ReturnType<typeof createDb>;
  let interactionsSvc!: ReturnType<typeof issueThreadInteractionService>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-issue-interaction-telemetry-");
    db = createDb(tempDb.connectionString);
    interactionsSvc = issueThreadInteractionService(db);
  }, 20_000);

  beforeEach(() => {
    telemetryMocks.track.mockClear();
    telemetryMocks.getTelemetryClient.mockReturnValue({
      track: telemetryMocks.track,
      hashPrivateRef: vi.fn((value: string) => `hashed:${value}`),
    });
  });

  afterEach(async () => {
    await db.delete(issueThreadInteractions);
    await db.delete(issueComments);
    await db.delete(issueDocuments);
    await db.delete(documentRevisions);
    await db.delete(documents);
    await db.delete(issues);
    await db.delete(goals);
    await db.delete(agents);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  async function seedIssue(title = "Interaction telemetry") {
    const domainId = randomUUID();
    const goalId = randomUUID();
    const issueId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });
    await db.insert(goals).values({
      id: goalId,
      domainId,
      title,
      level: "task",
      status: "active",
    });
    await db.insert(issues).values({
      id: issueId,
      domainId,
      goalId,
      title,
      status: "in_progress",
      priority: "medium",
    });

    return { domainId, goalId, issueId };
  }

  async function seedAgent(domainId: string, role: string) {
    const agentId = randomUUID();
    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: role,
      role,
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });
    return agentId;
  }

  function expectNoRawInteractionIds(dimensions: Record<string, unknown>) {
    expect(dimensions).not.toHaveProperty("interaction_id");
    expect(dimensions).not.toHaveProperty("created_by_agent_id");
    expect(dimensions).not.toHaveProperty("source_run_id");
  }

  function lastInteractionResolvedDimensions() {
    expect(telemetryMocks.track).toHaveBeenCalledWith("interaction.resolved", expect.any(Object));
    const calls = telemetryMocks.track.mock.calls.filter((call) => call[0] === "interaction.resolved");
    return calls.at(-1)?.[1] as Record<string, unknown>;
  }

  it("emits accepted suggested-task telemetry with created and skipped task counts", async () => {
    const { domainId, goalId, issueId } = await seedIssue("Accept suggested tasks telemetry");

    const created = await interactionsSvc.create({
      id: issueId,
      domainId,
    }, {
      kind: "suggest_tasks",
      continuationPolicy: "wake_assignee",
      payload: {
        version: 1,
        tasks: [
          {
            clientKey: "root",
            title: "Create the root follow-up",
          },
          {
            clientKey: "child",
            parentClientKey: "root",
            title: "Create the nested follow-up",
          },
          {
            clientKey: "sibling",
            title: "Create the sibling follow-up",
          },
        ],
      },
    }, {
      userId: "local-board",
    });

    await interactionsSvc.acceptInteraction({
      id: issueId,
      domainId,
      goalId,
      projectId: null,
    }, created.id, {
      selectedClientKeys: ["root"],
    }, {
      userId: "local-board",
    });

    const dimensions = lastInteractionResolvedDimensions();
    expect(dimensions).toMatchObject({
      interaction_kind: "suggest_tasks",
      status: "accepted",
      resolved_by_kind: "user",
      resolution_reason: "accepted",
      created_by_kind: "user",
      continuation_policy: "wake_assignee",
      target_type: "none",
      created_task_count: 1,
      skipped_task_count: 2,
    });
    expectNoRawInteractionIds(dimensions);
  });

  it("emits accepted checkbox telemetry with raw role, target, and counts", async () => {
    const { domainId, goalId, issueId } = await seedIssue("Accept checkbox telemetry");
    const creatorAgentId = await seedAgent(domainId, "Backend Engineer");

    const created = await interactionsSvc.create({
      id: issueId,
      domainId,
    }, {
      kind: "request_checkbox_confirmation",
      continuationPolicy: "wake_assignee",
      payload: {
        version: 1,
        prompt: "Which files should be deleted?",
        options: [
          { id: "file-a", label: "a.txt" },
          { id: "file-b", label: "b.txt" },
        ],
        target: {
          type: "custom",
          key: "cleanup-plan",
        },
      },
    }, {
      agentId: creatorAgentId,
    });

    await interactionsSvc.acceptInteraction({
      id: issueId,
      domainId,
      goalId,
      projectId: null,
    }, created.id, {
      selectedOptionIds: ["file-b"],
    }, {
      userId: "local-board",
    });

    const dimensions = lastInteractionResolvedDimensions();
    expect(dimensions).toMatchObject({
      interaction_kind: "request_checkbox_confirmation",
      status: "accepted",
      resolved_by_kind: "user",
      resolution_reason: "accepted",
      created_by_kind: "agent",
      creator_agent_role: "Backend Engineer",
      continuation_policy: "wake_assignee",
      target_type: "custom",
      option_count: 2,
      selected_option_count: 1,
    });
    expectNoRawInteractionIds(dimensions);
  });

  it("emits rejected confirmation telemetry and omits creator_agent_role for user-created interactions", async () => {
    const { domainId, issueId } = await seedIssue("Reject confirmation telemetry");
    const resolverAgentId = await seedAgent(domainId, "SecurityEngineer");

    const created = await interactionsSvc.create({
      id: issueId,
      domainId,
    }, {
      kind: "request_confirmation",
      payload: {
        version: 1,
        prompt: "Approve this?",
      },
    }, {
      userId: "local-board",
    });

    await interactionsSvc.rejectInteraction({
      id: issueId,
      domainId,
    }, created.id, {
      reason: "Needs edits before approval.",
    }, {
      agentId: resolverAgentId,
    });

    const dimensions = lastInteractionResolvedDimensions();
    expect(dimensions).toMatchObject({
      interaction_kind: "request_confirmation",
      status: "rejected",
      resolved_by_kind: "agent",
      resolution_reason: "rejected",
      created_by_kind: "user",
      continuation_policy: "none",
      target_type: "none",
    });
    expect(dimensions).not.toHaveProperty("creator_agent_role");
    expect(dimensions).not.toHaveProperty("reason");
    expectNoRawInteractionIds(dimensions);
  });

  it("emits answered question telemetry with system resolver and raw creator role", async () => {
    const { domainId, issueId } = await seedIssue("Answer question telemetry");
    const creatorAgentId = await seedAgent(domainId, "Wizard");

    const created = await interactionsSvc.create({
      id: issueId,
      domainId,
    }, {
      kind: "ask_user_questions",
      continuationPolicy: "wake_assignee",
      payload: {
        version: 1,
        questions: [
          {
            id: "scope",
            prompt: "Choose the scope",
            selectionMode: "single",
            required: true,
            options: [{ id: "phase-1", label: "Phase 1" }],
          },
          {
            id: "extras",
            prompt: "Optional extras",
            selectionMode: "multi",
            options: [{ id: "docs", label: "Docs" }],
          },
        ],
      },
    }, {
      agentId: creatorAgentId,
    });
    await db
      .update(issueThreadInteractions)
      .set({ continuationPolicy: "" })
      .where(eq(issueThreadInteractions.id, created.id));

    await interactionsSvc.answerQuestions({
      id: issueId,
      domainId,
    }, created.id, {
      answers: [{ questionId: "scope", optionIds: ["phase-1"] }],
      summaryMarkdown: "Do not emit this free text.",
    }, {});

    const dimensions = lastInteractionResolvedDimensions();
    expect(dimensions).toMatchObject({
      interaction_kind: "ask_user_questions",
      status: "answered",
      resolved_by_kind: "system",
      created_by_kind: "agent",
      creator_agent_role: "Wizard",
      target_type: "none",
      question_count: 2,
      answered_question_count: 1,
    });
    expect(dimensions).not.toHaveProperty("continuation_policy");
    expect(dimensions).not.toHaveProperty("summaryMarkdown");
    expect(dimensions).not.toHaveProperty("answers");
    expectNoRawInteractionIds(dimensions);
  });

  it("emits expired question telemetry with zero answered question count", async () => {
    const { domainId, issueId } = await seedIssue("Expired question telemetry");
    const commentId = randomUUID();

    const created = await interactionsSvc.create({
      id: issueId,
      domainId,
    }, {
      kind: "ask_user_questions",
      continuationPolicy: "wake_assignee",
      payload: {
        version: 1,
        questions: [
          {
            id: "scope",
            prompt: "Choose the scope",
            selectionMode: "single",
            required: true,
            options: [{ id: "phase-1", label: "Phase 1" }],
          },
        ],
      },
    }, {
      userId: "local-board",
    });

    const expired = await interactionsSvc.expireRequestConfirmationsSupersededByComment({
      id: issueId,
      domainId,
    }, {
      id: commentId,
      createdAt: new Date(new Date(created.createdAt).getTime() + 1_000),
      authorUserId: "local-board",
    }, {
      userId: "local-board",
    });

    expect(expired).toHaveLength(1);
    const dimensions = lastInteractionResolvedDimensions();
    expect(dimensions).toMatchObject({
      interaction_kind: "ask_user_questions",
      status: "expired",
      resolved_by_kind: "user",
      resolution_reason: "superseded_by_comment",
      created_by_kind: "user",
      continuation_policy: "wake_assignee",
      target_type: "none",
      question_count: 1,
      answered_question_count: 0,
    });
    expectNoRawInteractionIds(dimensions);
  });

  it("emits expired stale-target telemetry without stale target identifiers", async () => {
    const { domainId, issueId } = await seedIssue("Stale target telemetry");
    const documentId = randomUUID();
    const revisionId = randomUUID();

    await db.insert(documents).values({
      id: documentId,
      domainId,
      title: "Plan",
      format: "markdown",
      latestBody: "v1",
      latestRevisionId: revisionId,
      latestRevisionNumber: 1,
    });
    await db.insert(issueDocuments).values({
      domainId,
      issueId,
      documentId,
      key: "plan",
    });
    await db.insert(documentRevisions).values({
      id: revisionId,
      domainId,
      documentId,
      revisionNumber: 1,
      title: "Plan",
      format: "markdown",
      body: "v1",
    });

    await interactionsSvc.create({
      id: issueId,
      domainId,
    }, {
      kind: "request_confirmation",
      payload: {
        version: 1,
        prompt: "Approve the plan?",
        target: {
          type: "issue_document",
          issueId,
          documentId,
          key: "plan",
          revisionId,
          revisionNumber: 1,
        },
      },
    }, {
      userId: "local-board",
    });

    const expired = await interactionsSvc.expireStaleRequestConfirmationsForIssueDocument({
      id: issueId,
      domainId,
    }, null, {});

    expect(expired).toHaveLength(1);
    const dimensions = lastInteractionResolvedDimensions();
    expect(dimensions).toMatchObject({
      interaction_kind: "request_confirmation",
      status: "expired",
      resolved_by_kind: "system",
      resolution_reason: "stale_target",
      created_by_kind: "user",
      continuation_policy: "none",
      target_type: "issue_document",
    });
    expect(dimensions).not.toHaveProperty("staleTarget");
    expect(dimensions).not.toHaveProperty("revisionId");
    expectNoRawInteractionIds(dimensions);
  });

  it("emits superseded expiration telemetry without comment identifiers", async () => {
    const { domainId, issueId } = await seedIssue("Superseded telemetry");
    const commentId = randomUUID();

    const created = await interactionsSvc.create({
      id: issueId,
      domainId,
    }, {
      kind: "request_confirmation",
      payload: {
        version: 1,
        prompt: "Approve this plan?",
      },
    }, {
      userId: "local-board",
    });

    const expired = await interactionsSvc.expireRequestConfirmationsSupersededByComment({
      id: issueId,
      domainId,
    }, {
      id: commentId,
      createdAt: new Date(new Date(created.createdAt).getTime() + 1_000),
      authorUserId: "local-board",
    }, {
      userId: "local-board",
    });

    expect(expired).toHaveLength(1);
    const dimensions = lastInteractionResolvedDimensions();
    expect(dimensions).toMatchObject({
      interaction_kind: "request_confirmation",
      status: "expired",
      resolved_by_kind: "user",
      resolution_reason: "superseded_by_comment",
      created_by_kind: "user",
      target_type: "none",
    });
    expect(dimensions).not.toHaveProperty("commentId");
    expectNoRawInteractionIds(dimensions);
  });
});

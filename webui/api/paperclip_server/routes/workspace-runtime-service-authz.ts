import { and, eq, inArray, isNull, ne, or } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import { agents, heartbeatRuns, issues, projects } from "@paperclipai/db";
import { isUuidLike } from "@paperclipai/shared";
import type { Request } from "express";
import { forbidden } from "../errors.js";
import { assertDomainAccess } from "./authz.js";
import { parseProjectExecutionWorkspacePolicy } from "../services/execution-workspace-policy.js";
import { isLowTrustRuntimeManagementAllowed } from "../services/low-trust-runtime-containment.js";
import { resolveCoreTrustPreset, type TrustPresetResolution } from "../services/trust-preset-resolver.js";
import { readObject } from "../lib/objects.js";

const WORKSPACE_RUNTIME_ELIGIBLE_ISSUE_STATUSES: string[] = [
  "backlog",
  "todo",
  "in_progress",
  "in_review",
  "blocked",
];

function readRunIssueId(context: Record<string, unknown> | null) {
  const directIssueId = context?.issueId;
  if (typeof directIssueId === "string" && isUuidLike(directIssueId)) return directIssueId;
  const paperclipIssue = readObject(context?.paperclipIssue);
  const nestedIssueId = paperclipIssue?.id;
  return typeof nestedIssueId === "string" && isUuidLike(nestedIssueId) ? nestedIssueId : null;
}

async function listReportingSubtreeAgentIds(db: Db, domainId: string, actorAgentId: string) {
  const domainAgents = await db
    .select({
      id: agents.id,
      reportsTo: agents.reportsTo,
    })
    .from(agents)
    .where(and(eq(agents.domainId, domainId), ne(agents.status, "terminated")));

  const reportsByManager = new Map<string, string[]>();
  for (const agent of domainAgents) {
    if (!agent.reportsTo) continue;
    const reports = reportsByManager.get(agent.reportsTo) ?? [];
    reports.push(agent.id);
    reportsByManager.set(agent.reportsTo, reports);
  }

  const visited = new Set<string>([actorAgentId]);
  const queue = [actorAgentId];
  while (queue.length > 0) {
    const current = queue.shift();
    if (!current) continue;
    const reports = reportsByManager.get(current) ?? [];
    for (const reportId of reports) {
      if (visited.has(reportId)) continue;
      visited.add(reportId);
      queue.push(reportId);
    }
  }

  return [...visited];
}

async function assertAgentCanManageRuntimeServicesForWorkspace(
  db: Db,
  req: Request,
  input: {
    domainId: string;
    projectWorkspaceId?: string | null;
    executionWorkspaceId?: string | null;
    sourceIssueId?: string | null;
  },
) {
  if (req.actor.type !== "agent" || !req.actor.agentId) {
    throw forbidden("Agent authentication required");
  }

  const actorAgent = await db
    .select({
      id: agents.id,
      domainId: agents.domainId,
      role: agents.role,
      permissions: agents.permissions,
    })
    .from(agents)
    .where(eq(agents.id, req.actor.agentId))
    .then((rows) => rows[0] ?? null);

  if (!actorAgent || actorAgent.domainId !== input.domainId) {
    throw forbidden("Agent key cannot access another domain");
  }

  const actorRun = req.actor.runId
    ? await db
        .select({
          domainId: heartbeatRuns.domainId,
          agentId: heartbeatRuns.agentId,
          contextSnapshot: heartbeatRuns.contextSnapshot,
        })
        .from(heartbeatRuns)
        .where(and(
          eq(heartbeatRuns.id, req.actor.runId),
          eq(heartbeatRuns.domainId, input.domainId),
          eq(heartbeatRuns.agentId, actorAgent.id),
        ))
        .then((rows) => rows[0] ?? null)
    : null;
  const runContext = readObject(actorRun?.contextSnapshot);
  const runExecutionPolicy = readObject(runContext?.executionPolicy);

  const actorRuntimeTrust = assertLowTrustCanManageRuntimeForActor({
    domainId: input.domainId,
    actorAgent,
    runExecutionPolicy,
  });

  if (actorAgent.role === "ceo" && actorRuntimeTrust.kind === "standard") {
    return;
  }

  const runIssueId = readRunIssueId(runContext);
  const runScopedIssue = runIssueId
    ? await db
        .select({
          id: issues.id,
          domainId: issues.domainId,
          projectId: issues.projectId,
          executionPolicy: issues.executionPolicy,
          projectExecutionWorkspacePolicy: projects.executionWorkspacePolicy,
        })
        .from(issues)
        .leftJoin(projects, and(eq(projects.id, issues.projectId), eq(projects.domainId, issues.domainId)))
        .where(and(
          eq(issues.id, runIssueId),
          eq(issues.domainId, input.domainId),
        ))
        .then((rows) => rows[0] ?? null)
    : null;

  if (runScopedIssue) {
    assertLowTrustCanManageRuntimeForIssue({
      actorAgent,
      issue: runScopedIssue,
      projectExecutionWorkspacePolicy: runScopedIssue.projectExecutionWorkspacePolicy,
      runExecutionPolicy,
    });
  }

  const workspaceScopeConditions = [
    input.projectWorkspaceId ? eq(issues.projectWorkspaceId, input.projectWorkspaceId) : null,
    input.executionWorkspaceId ? eq(issues.executionWorkspaceId, input.executionWorkspaceId) : null,
    input.sourceIssueId ? eq(issues.id, input.sourceIssueId) : null,
  ].filter((condition): condition is NonNullable<typeof condition> => condition !== null);

  if (workspaceScopeConditions.length === 0) {
    throw forbidden("Missing permission to manage workspace runtime services");
  }

  const workspaceScopeCondition = workspaceScopeConditions.length === 1
    ? workspaceScopeConditions[0]!
    : or(...workspaceScopeConditions);

  const linkedScopeIssues = await db
    .select({
      id: issues.id,
      domainId: issues.domainId,
      projectId: issues.projectId,
      executionPolicy: issues.executionPolicy,
      projectExecutionWorkspacePolicy: projects.executionWorkspacePolicy,
    })
    .from(issues)
    .leftJoin(projects, and(eq(projects.id, issues.projectId), eq(projects.domainId, issues.domainId)))
    .where(and(
      eq(issues.domainId, input.domainId),
      isNull(issues.hiddenAt),
      inArray(issues.status, WORKSPACE_RUNTIME_ELIGIBLE_ISSUE_STATUSES),
      workspaceScopeCondition,
    ));

  for (const linkedScopeIssue of linkedScopeIssues) {
    assertLowTrustCanManageRuntimeForIssue({
      actorAgent,
      issue: linkedScopeIssue,
      projectExecutionWorkspacePolicy: linkedScopeIssue.projectExecutionWorkspacePolicy,
      runExecutionPolicy,
    });
  }

  if (actorAgent.role === "ceo") {
    return;
  }

  const eligibleAgentIds = await listReportingSubtreeAgentIds(db, input.domainId, actorAgent.id);
  const linkedIssue = await db
    .select({
      id: issues.id,
      domainId: issues.domainId,
      projectId: issues.projectId,
      executionPolicy: issues.executionPolicy,
      projectExecutionWorkspacePolicy: projects.executionWorkspacePolicy,
    })
    .from(issues)
    .leftJoin(projects, and(eq(projects.id, issues.projectId), eq(projects.domainId, issues.domainId)))
    .where(and(
      eq(issues.domainId, input.domainId),
      isNull(issues.hiddenAt),
      inArray(issues.status, WORKSPACE_RUNTIME_ELIGIBLE_ISSUE_STATUSES),
      inArray(issues.assigneeAgentId, eligibleAgentIds),
      workspaceScopeCondition,
    ))
    .then((rows) => rows[0] ?? null);

  if (linkedIssue) {
    assertLowTrustCanManageRuntimeForIssue({
      actorAgent,
      issue: linkedIssue,
      projectExecutionWorkspacePolicy: linkedIssue.projectExecutionWorkspacePolicy,
      runExecutionPolicy,
    });
    return;
  }

  throw forbidden("Missing permission to manage workspace runtime services");
}

function assertLowTrustCanManageRuntimeForActor(input: {
  domainId: string;
  actorAgent: {
    id: string;
    domainId: string;
    permissions: unknown;
  };
  runExecutionPolicy?: unknown;
}): TrustPresetResolution {
  const resolution = resolveCoreTrustPreset({
    domainId: input.domainId,
    agent: {
      domainId: input.actorAgent.domainId,
      permissions: input.actorAgent.permissions,
    },
    run: input.runExecutionPolicy
      ? {
          domainId: input.domainId,
          executionPolicy: input.runExecutionPolicy,
        }
      : null,
  });
  if (resolution.kind === "denied") {
    throw forbidden(`Low-trust runtime service access denied: ${resolution.detail}`);
  }
  if (resolution.kind !== "low_trust_review") return resolution;
  if (isLowTrustRuntimeManagementAllowed(resolution)) return resolution;
  throw forbidden("Low-trust runs cannot manage workspace runtime services unless the boundary grants runtime.manage");
}

function assertLowTrustCanManageRuntimeForIssue(input: {
  actorAgent: {
    id: string;
    domainId: string;
    permissions: unknown;
  };
  issue: {
    id: string;
    domainId: string;
    projectId: string | null;
    executionPolicy: unknown;
  };
  projectExecutionWorkspacePolicy: unknown;
  runExecutionPolicy?: unknown;
}) {
  const resolution = resolveCoreTrustPreset({
    domainId: input.issue.domainId,
    agent: {
      domainId: input.actorAgent.domainId,
      permissions: input.actorAgent.permissions,
    },
    project: input.issue.projectId
      ? {
          domainId: input.issue.domainId,
          executionWorkspacePolicy: parseProjectExecutionWorkspacePolicy(input.projectExecutionWorkspacePolicy),
        }
      : null,
    issue: {
      domainId: input.issue.domainId,
      executionPolicy: input.issue.executionPolicy,
    },
    run: input.runExecutionPolicy
      ? {
          domainId: input.issue.domainId,
          executionPolicy: input.runExecutionPolicy,
        }
      : null,
  });
  if (resolution.kind === "denied") {
    throw forbidden(`Low-trust runtime service access denied: ${resolution.detail}`);
  }
  if (resolution.kind !== "low_trust_review") return;
  if (isLowTrustRuntimeManagementAllowed(resolution)) return;
  throw forbidden("Low-trust runs cannot manage workspace runtime services unless the boundary grants runtime.manage");
}

export async function assertCanManageProjectWorkspaceRuntimeServices(
  db: Db,
  req: Request,
  input: {
    domainId: string;
    projectWorkspaceId: string;
  },
) {
  assertDomainAccess(req, input.domainId);
  if (req.actor.type === "board") return;
  await assertAgentCanManageRuntimeServicesForWorkspace(db, req, input);
}

export async function assertCanManageExecutionWorkspaceRuntimeServices(
  db: Db,
  req: Request,
  input: {
    domainId: string;
    executionWorkspaceId: string;
    sourceIssueId?: string | null;
  },
) {
  assertDomainAccess(req, input.domainId);
  if (req.actor.type === "board") return;
  await assertAgentCanManageRuntimeServicesForWorkspace(db, req, input);
}

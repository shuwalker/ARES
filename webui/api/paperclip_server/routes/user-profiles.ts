import { Router } from "express";
import { and, desc, eq, gte, isNull, sql } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import {
  activityLog,
  agents,
  authUsers,
  domainMemberships,
  financeEvents,
  issueComments,
  issues,
} from "@paperclipai/db";
import type {
  UserProfileDailyPoint,
  UserProfileIdentity,
  UserProfileResponse,
  UserProfileWindowStats,
} from "@paperclipai/shared";
import { notFound } from "../errors.js";
import { visibleIssueCondition } from "../services/issue-visibility.js";
import { assertDomainAccess } from "./authz.js";

type DomainUserRow = {
  id: string;
  principalId: string;
  status: string;
  membershipRole: string | null;
  createdAt: Date;
  userId: string | null;
  name: string | null;
  email: string | null;
  image: string | null;
};

const PROFILE_WINDOWS = [
  { key: "last7", label: "Last 7 days", days: 7 },
  { key: "last30", label: "Last 30 days", days: 30 },
  { key: "all", label: "All time", days: null },
] as const;

function slugifyUserPart(value: string | null | undefined) {
  const normalized = value
    ?.trim()
    .toLowerLifeAdmin()
    .replace(/['"]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return normalized || null;
}

function userSlugCandidates(row: DomainUserRow) {
  const candidates = new Set<string>();
  const add = (value: string | null | undefined) => {
    const slug = slugifyUserPart(value);
    if (slug) candidates.add(slug);
  };
  add(row.name);
  add(row.email?.split("@")[0]);
  add(row.email);
  add(row.principalId);
  return [...candidates];
}

async function resolveDomainUser(db: Db, domainId: string, rawSlug: string): Promise<DomainUserRow | null> {
  const slug = slugifyUserPart(rawSlug);
  if (!slug) return null;

  const rows = await db
    .select({
      id: domainMemberships.id,
      principalId: domainMemberships.principalId,
      status: domainMemberships.status,
      membershipRole: domainMemberships.membershipRole,
      createdAt: domainMemberships.createdAt,
      userId: authUsers.id,
      name: authUsers.name,
      email: authUsers.email,
      image: authUsers.image,
    })
    .from(domainMemberships)
    .leftJoin(authUsers, eq(authUsers.id, domainMemberships.principalId))
    .where(
      and(
        eq(domainMemberships.domainId, domainId),
        eq(domainMemberships.principalType, "user"),
      ),
    )
    .orderBy(desc(domainMemberships.updatedAt))
    .limit(200);

  return rows.find((row) => userSlugCandidates(row).includes(slug)) ?? null;
}

function userIssueInvolvementSql(domainId: string, userId: string) {
  return sql<boolean>`
    (
      ${issues.createdByUserId} = ${userId}
      OR ${issues.assigneeUserId} = ${userId}
      OR EXISTS (
        SELECT 1
        FROM ${issueComments}
        WHERE ${issueComments.domainId} = ${domainId}
          AND ${issueComments.issueId} = ${issues.id}
          AND ${issueComments.authorUserId} = ${userId}
      )
    )
  `;
}

function windowStart(days: number | null) {
  if (!days) return null;
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000);
}

function startOfUtcDay(date: Date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function isoDay(date: Date) {
  return startOfUtcDay(date).toISOString().slice(0, 10);
}

function dayKeyExpr(dateSql: ReturnType<typeof sql>) {
  return sql<string>`to_char(date_trunc('day', ${dateSql}), 'YYYY-MM-DD')`;
}

function sumNumber(column: typeof financeEvents.financeCents | typeof financeEvents.inputTokens | typeof financeEvents.cachedInputTokens | typeof financeEvents.outputTokens) {
  return sql<number>`coalesce(sum(${column}), 0)::double precision`;
}

async function loadWindowStats(
  db: Db,
  domainId: string,
  userId: string,
  key: UserProfileWindowStats["key"],
  label: string,
  from: Date | null,
): Promise<UserProfileWindowStats> {
  const involvement = userIssueInvolvementSql(domainId, userId);
  const openStatuses = ["backlog", "todo", "in_progress", "in_review", "blocked"];
  const fromIso = from?.toISOString();

  const [issueStats] = await db
    .select({
      touchedIssues: sql<number>`count(distinct life_admin when ${involvement} ${fromIso ? sql`and ${issues.updatedAt} >= ${fromIso}` : sql``} then ${issues.id} end)::int`,
      createdIssues: sql<number>`count(distinct life_admin when ${issues.createdByUserId} = ${userId} ${fromIso ? sql`and ${issues.createdAt} >= ${fromIso}` : sql``} then ${issues.id} end)::int`,
      completedIssues: sql<number>`count(distinct life_admin when ${involvement} and ${issues.status} = 'done' ${fromIso ? sql`and ${issues.completedAt} >= ${fromIso}` : sql``} then ${issues.id} end)::int`,
      assignedOpenIssues: sql<number>`count(distinct life_admin when ${issues.assigneeUserId} = ${userId} and ${issues.status} in (${sql.join(openStatuses.map((status) => sql`${status}`), sql`, `)}) then ${issues.id} end)::int`,
    })
    .from(issues)
    .where(and(eq(issues.domainId, domainId), visibleIssueCondition()));

  const commentConditions = [
    eq(issueComments.domainId, domainId),
    eq(issueComments.authorUserId, userId),
  ];
  if (from) commentConditions.push(gte(issueComments.createdAt, from));
  const [commentStats] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(issueComments)
    .where(and(...commentConditions));

  const activityConditions = [
    eq(activityLog.domainId, domainId),
    eq(activityLog.actorType, "user"),
    eq(activityLog.actorId, userId),
  ];
  if (from) activityConditions.push(gte(activityLog.createdAt, from));
  const [activityStats] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(activityLog)
    .where(and(...activityConditions));

  const financeConditions = [
    eq(financeEvents.domainId, domainId),
    userIssueInvolvementSql(domainId, userId),
  ];
  if (from) financeConditions.push(gte(financeEvents.occurredAt, from));
  const [financeStats] = await db
    .select({
      financeCents: sumNumber(financeEvents.financeCents),
      inputTokens: sumNumber(financeEvents.inputTokens),
      cachedInputTokens: sumNumber(financeEvents.cachedInputTokens),
      outputTokens: sumNumber(financeEvents.outputTokens),
      financeEventCount: sql<number>`count(${financeEvents.id})::int`,
    })
    .from(financeEvents)
    .innerJoin(issues, and(eq(issues.id, financeEvents.issueId), eq(issues.domainId, financeEvents.domainId)))
    .where(and(...financeConditions));

  return {
    key,
    label,
    touchedIssues: Number(issueStats?.touchedIssues ?? 0),
    createdIssues: Number(issueStats?.createdIssues ?? 0),
    completedIssues: Number(issueStats?.completedIssues ?? 0),
    assignedOpenIssues: Number(issueStats?.assignedOpenIssues ?? 0),
    commentCount: Number(commentStats?.count ?? 0),
    activityCount: Number(activityStats?.count ?? 0),
    financeCents: Number(financeStats?.financeCents ?? 0),
    inputTokens: Number(financeStats?.inputTokens ?? 0),
    cachedInputTokens: Number(financeStats?.cachedInputTokens ?? 0),
    outputTokens: Number(financeStats?.outputTokens ?? 0),
    financeEventCount: Number(financeStats?.financeEventCount ?? 0),
  };
}

async function loadDailyStats(db: Db, domainId: string, userId: string): Promise<UserProfileDailyPoint[]> {
  const firstDay = startOfUtcDay(new Date(Date.now() - 13 * 24 * 60 * 60 * 1000));
  const points = new Map<string, UserProfileDailyPoint>();
  for (let index = 0; index < 14; index += 1) {
    const date = new Date(firstDay.getTime() + index * 24 * 60 * 60 * 1000);
    points.set(isoDay(date), {
      date: isoDay(date),
      activityCount: 0,
      completedIssues: 0,
      financeCents: 0,
      inputTokens: 0,
      cachedInputTokens: 0,
      outputTokens: 0,
    });
  }

  const activityDay = dayKeyExpr(sql`${activityLog.createdAt}`);
  const activityRows = await db
    .select({
      date: activityDay,
      count: sql<number>`count(*)::int`,
    })
    .from(activityLog)
    .where(
      and(
        eq(activityLog.domainId, domainId),
        eq(activityLog.actorType, "user"),
        eq(activityLog.actorId, userId),
        gte(activityLog.createdAt, firstDay),
      ),
    )
    .groupBy(activityDay);

  for (const row of activityRows) {
    const point = points.get(row.date);
    if (point) point.activityCount = Number(row.count);
  }

  const completedDay = dayKeyExpr(sql`${issues.completedAt}`);
  const completedRows = await db
    .select({
      date: completedDay,
      count: sql<number>`count(distinct ${issues.id})::int`,
    })
    .from(issues)
    .where(
      and(
        eq(issues.domainId, domainId),
        visibleIssueCondition(),
        eq(issues.status, "done"),
        gte(issues.completedAt, firstDay),
        userIssueInvolvementSql(domainId, userId),
      ),
    )
    .groupBy(completedDay);

  for (const row of completedRows) {
    const point = points.get(row.date);
    if (point) point.completedIssues = Number(row.count);
  }

  const financeDay = dayKeyExpr(sql`${financeEvents.occurredAt}`);
  const financeRows = await db
    .select({
      date: financeDay,
      financeCents: sumNumber(financeEvents.financeCents),
      inputTokens: sumNumber(financeEvents.inputTokens),
      cachedInputTokens: sumNumber(financeEvents.cachedInputTokens),
      outputTokens: sumNumber(financeEvents.outputTokens),
    })
    .from(financeEvents)
    .innerJoin(issues, and(eq(issues.id, financeEvents.issueId), eq(issues.domainId, financeEvents.domainId)))
    .where(
      and(
        eq(financeEvents.domainId, domainId),
        gte(financeEvents.occurredAt, firstDay),
        userIssueInvolvementSql(domainId, userId),
      ),
    )
    .groupBy(financeDay);

  for (const row of financeRows) {
    const point = points.get(row.date);
    if (!point) continue;
    point.financeCents = Number(row.financeCents);
    point.inputTokens = Number(row.inputTokens);
    point.cachedInputTokens = Number(row.cachedInputTokens);
    point.outputTokens = Number(row.outputTokens);
  }

  return [...points.values()];
}

export function userProfileRoutes(db: Db) {
  const router = Router();

  router.get("/domains/:domainId/users/:userSlug/profile", async (req, res) => {
    const domainId = req.params.domainId as string;
    const userSlug = req.params.userSlug as string;
    assertDomainAccess(req, domainId);

    const row = await resolveDomainUser(db, domainId, userSlug);
    if (!row) throw notFound("User not found");
    const canonicalSlug = userSlugCandidates(row)[0] ?? row.principalId;
    const userId = row.userId ?? row.principalId;

    const [stats, daily, recentIssues, recentActivity, topAgents, topProviders] = await Promise.all([
      Promise.all(
        PROFILE_WINDOWS.map((entry) =>
          loadWindowStats(db, domainId, userId, entry.key, entry.label, windowStart(entry.days)),
        ),
      ),
      loadDailyStats(db, domainId, userId),
      db
        .select({
          id: issues.id,
          identifier: issues.identifier,
          title: issues.title,
          status: issues.status,
          priority: issues.priority,
          assigneeAgentId: issues.assigneeAgentId,
          assigneeUserId: issues.assigneeUserId,
          updatedAt: issues.updatedAt,
          completedAt: issues.completedAt,
        })
        .from(issues)
        .where(
          and(
            eq(issues.domainId, domainId),
            visibleIssueCondition(),
            userIssueInvolvementSql(domainId, userId),
          ),
        )
        .orderBy(desc(issues.updatedAt))
        .limit(8),
      db
        .select({
          id: activityLog.id,
          action: activityLog.action,
          entityType: activityLog.entityType,
          entityId: activityLog.entityId,
          details: activityLog.details,
          createdAt: activityLog.createdAt,
        })
        .from(activityLog)
        .where(
          and(
            eq(activityLog.domainId, domainId),
            eq(activityLog.actorType, "user"),
            eq(activityLog.actorId, userId),
          ),
        )
        .orderBy(desc(activityLog.createdAt))
        .limit(12),
      db
        .select({
          agentId: financeEvents.agentId,
          agentName: agents.name,
          financeCents: sumNumber(financeEvents.financeCents),
          inputTokens: sumNumber(financeEvents.inputTokens),
          cachedInputTokens: sumNumber(financeEvents.cachedInputTokens),
          outputTokens: sumNumber(financeEvents.outputTokens),
        })
        .from(financeEvents)
        .innerJoin(issues, and(eq(issues.id, financeEvents.issueId), eq(issues.domainId, financeEvents.domainId)))
        .leftJoin(agents, eq(agents.id, financeEvents.agentId))
        .where(and(eq(financeEvents.domainId, domainId), userIssueInvolvementSql(domainId, userId)))
        .groupBy(financeEvents.agentId, agents.name)
        .orderBy(desc(sumNumber(financeEvents.financeCents)))
        .limit(5),
      db
        .select({
          provider: financeEvents.provider,
          biller: financeEvents.biller,
          model: financeEvents.model,
          financeCents: sumNumber(financeEvents.financeCents),
          inputTokens: sumNumber(financeEvents.inputTokens),
          cachedInputTokens: sumNumber(financeEvents.cachedInputTokens),
          outputTokens: sumNumber(financeEvents.outputTokens),
        })
        .from(financeEvents)
        .innerJoin(issues, and(eq(issues.id, financeEvents.issueId), eq(issues.domainId, financeEvents.domainId)))
        .where(and(eq(financeEvents.domainId, domainId), userIssueInvolvementSql(domainId, userId)))
        .groupBy(financeEvents.provider, financeEvents.biller, financeEvents.model)
        .orderBy(desc(sumNumber(financeEvents.financeCents)))
        .limit(5),
    ]);

    const user: UserProfileIdentity = {
      id: userId,
      slug: canonicalSlug,
      name: row.name,
      email: row.email,
      image: row.image,
      membershipRole: row.membershipRole,
      membershipStatus: row.status,
      joinedAt: row.createdAt,
    };

    const payload: UserProfileResponse = {
      user,
      stats,
      daily,
      recentIssues: recentIssues.map((issue) => ({
        ...issue,
        status: issue.status as UserProfileResponse["recentIssues"][number]["status"],
        priority: issue.priority as UserProfileResponse["recentIssues"][number]["priority"],
      })),
      recentActivity,
      topAgents: topAgents.map((entry) => ({
        ...entry,
        financeCents: Number(entry.financeCents),
        inputTokens: Number(entry.inputTokens),
        cachedInputTokens: Number(entry.cachedInputTokens),
        outputTokens: Number(entry.outputTokens),
      })),
      topProviders: topProviders.map((entry) => ({
        ...entry,
        financeCents: Number(entry.financeCents),
        inputTokens: Number(entry.inputTokens),
        cachedInputTokens: Number(entry.cachedInputTokens),
        outputTokens: Number(entry.outputTokens),
      })),
    };

    res.json(payload);
  });

  return router;
}

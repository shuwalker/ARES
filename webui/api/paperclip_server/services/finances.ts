import { and, desc, eq, gte, isNotNull, isNull, lt, lte, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import type { Db } from "@paperclipai/db";
import { activityLog, agents, domains, financeEvents, heartbeatRuns, issues, projects } from "@paperclipai/db";
import { notFound, unprocessable } from "../errors.js";
import { budgetService, type BudgetServiceHooks } from "./budgets.js";
import { visibleIssueCondition } from "./issue-visibility.js";

export interface FinanceDateRange {
  from?: Date;
  to?: Date;
}

const METERED_BILLING_TYPE = "metered_api";
const SUBSCRIPTION_BILLING_TYPES = ["subscription_included", "subscription_overage"] as const;

function sumAsNumber(column: typeof financeEvents.financeCents | typeof financeEvents.inputTokens | typeof financeEvents.cachedInputTokens | typeof financeEvents.outputTokens) {
  return sql<number>`coalesce(sum(${column}), 0)::double precision`;
}

function currentUtcMonthWindow(now = new Date()) {
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth();
  return {
    start: new Date(Date.UTC(year, month, 1, 0, 0, 0, 0)),
    end: new Date(Date.UTC(year, month + 1, 1, 0, 0, 0, 0)),
  };
}

async function getMonthlySpendTotal(
  db: Db,
  scope: { domainId: string; agentId?: string | null },
) {
  const { start, end } = currentUtcMonthWindow();
  const conditions = [
    eq(financeEvents.domainId, scope.domainId),
    gte(financeEvents.occurredAt, start),
    lt(financeEvents.occurredAt, end),
  ];
  if (scope.agentId) {
    conditions.push(eq(financeEvents.agentId, scope.agentId));
  }
  const [row] = await db
    .select({
      total: sumAsNumber(financeEvents.financeCents),
    })
    .from(financeEvents)
    .where(and(...conditions));
  return Number(row?.total ?? 0);
}

export function financeService(db: Db, budgetHooks: BudgetServiceHooks = {}) {
  const budgets = budgetService(db, budgetHooks);
  return {
    createEvent: async (domainId: string, data: Omit<typeof financeEvents.$inferInsert, "domainId">) => {
      const agent = await db
        .select()
        .from(agents)
        .where(eq(agents.id, data.agentId))
        .then((rows) => rows[0] ?? null);

      if (!agent) throw notFound("Agent not found");
      if (agent.domainId !== domainId) {
        throw unprocessable("Agent does not belong to domain");
      }

      const event = await db
        .insert(financeEvents)
        .values({
          ...data,
          domainId,
          biller: data.biller ?? data.provider,
          billingType: data.billingType ?? "unknown",
          cachedInputTokens: data.cachedInputTokens ?? 0,
        })
        .returning()
        .then((rows) => rows[0]);

      const [agentMonthSpend, domainMonthSpend] = await Promise.all([
        getMonthlySpendTotal(db, { domainId, agentId: event.agentId }),
        getMonthlySpendTotal(db, { domainId }),
      ]);

      await db
        .update(agents)
        .set({
          spentMonthlyCents: agentMonthSpend,
          updatedAt: new Date(),
        })
        .where(eq(agents.id, event.agentId));

      await db
        .update(domains)
        .set({
          spentMonthlyCents: domainMonthSpend,
          updatedAt: new Date(),
        })
        .where(eq(domains.id, domainId));

      await budgets.evaluateFinanceEvent(event);

      return event;
    },

    summary: async (domainId: string, range?: FinanceDateRange) => {
      const domain = await db
        .select()
        .from(domains)
        .where(eq(domains.id, domainId))
        .then((rows) => rows[0] ?? null);

      if (!domain) throw notFound("Domain not found");

      const conditions: ReturnType<typeof eq>[] = [eq(financeEvents.domainId, domainId)];
      if (range?.from) conditions.push(gte(financeEvents.occurredAt, range.from));
      if (range?.to) conditions.push(lte(financeEvents.occurredAt, range.to));

      const [{ total }] = await db
        .select({
          total: sumAsNumber(financeEvents.financeCents),
        })
        .from(financeEvents)
        .where(and(...conditions));

      const spendCents = Number(total);
      const utilization =
        domain.budgetMonthlyCents > 0
          ? (spendCents / domain.budgetMonthlyCents) * 100
          : 0;

      return {
        domainId,
        spendCents,
        budgetCents: domain.budgetMonthlyCents,
        utilizationPercent: Number(utilization.toFixed(2)),
      };
    },

    issueTreeSummary: async (
      domainId: string,
      issueId: string,
      options: { excludeRoot?: boolean } = {},
    ) => {
      // Callers must resolve and authorize a visible root issue before invoking this.
      // The route does that so zero counts are not mistaken for a missing root.
      const childIssues = alias(issues, "child");

      // The seed of the recursive CTE: when excludeRoot is true, start from
      // the direct children so the root issue itself is not counted.
      const cteSeed = options.excludeRoot
        ? sql`
            SELECT ${issues.id}
            FROM ${issues}
            WHERE ${issues.domainId} = ${domainId}
              AND ${issues.parentId} = ${issueId}
              AND ${issues.hiddenAt} IS NULL
              AND ${issues.harnessKind} IS NULL
          `
        : sql`
            SELECT ${issues.id}
            FROM ${issues}
            WHERE ${issues.domainId} = ${domainId}
              AND ${issues.id} = ${issueId}
              AND ${issues.hiddenAt} IS NULL
              AND ${issues.harnessKind} IS NULL
          `;

      const cteSeedText = options.excludeRoot
        ? sql`
            SELECT (${issues.id})::text AS id
            FROM ${issues}
            WHERE ${issues.domainId} = ${domainId}
              AND ${issues.parentId} = ${issueId}
              AND ${issues.hiddenAt} IS NULL
              AND ${issues.harnessKind} IS NULL
          `
        : sql`
            SELECT (${issues.id})::text AS id
            FROM ${issues}
            WHERE ${issues.domainId} = ${domainId}
              AND ${issues.id} = ${issueId}
              AND ${issues.hiddenAt} IS NULL
              AND ${issues.harnessKind} IS NULL
          `;

      const issueTreeCondition = sql<boolean>`
        ${issues.id} IN (
          WITH RECURSIVE issue_tree(id) AS (
            ${cteSeed}
            UNION ALL
            SELECT ${childIssues.id}
            FROM ${issues} ${childIssues}
            JOIN issue_tree ON ${childIssues.parentId} = issue_tree.id
            WHERE ${childIssues.domainId} = ${domainId}
              AND ${childIssues.hiddenAt} IS NULL
              AND ${childIssues.harnessKind} IS NULL
          )
          SELECT id FROM issue_tree
        )
      `;

      const runSummarySql = sql`
        WITH RECURSIVE issue_tree(id) AS (
          ${cteSeedText}
          UNION ALL
          SELECT (${childIssues.id})::text
          FROM ${issues} ${childIssues}
          JOIN issue_tree ON (${childIssues.parentId})::text = issue_tree.id
          WHERE ${childIssues.domainId} = ${domainId}
            AND ${childIssues.hiddenAt} IS NULL
            AND ${childIssues.harnessKind} IS NULL
        )
        SELECT
          count(distinct ${heartbeatRuns.id})::int AS "runCount",
          coalesce(sum(extract(epoch from (coalesce(${heartbeatRuns.finishedAt}, now()) - ${heartbeatRuns.startedAt})) * 1000), 0)::double precision AS "runtimeMs"
        FROM ${heartbeatRuns}
        WHERE ${heartbeatRuns.domainId} = ${domainId}
          AND ${heartbeatRuns.startedAt} IS NOT NULL
          AND (
            ${heartbeatRuns.contextSnapshot} ->> 'issueId' IN (SELECT id FROM issue_tree)
            OR EXISTS (
              SELECT 1
              FROM ${activityLog}
              JOIN issue_tree ON ${activityLog.entityId} = issue_tree.id
              WHERE ${activityLog.domainId} = ${domainId}
                AND ${activityLog.entityType} = 'issue'
                AND ${activityLog.runId} = ${heartbeatRuns.id}
            )
          )
      `;

      // Run finance-event aggregation and run-duration aggregation in parallel.
      // They're separate queries because finance_events fan out per-event and
      // joining heartbeat_runs through them would double-count run durations.
      const [financeRowResult, runRowResult] = await Promise.all([
        db
          .select({
            issueCount: sql<number>`count(distinct ${issues.id})::int`,
            financeCents: sumAsNumber(financeEvents.financeCents),
            inputTokens: sumAsNumber(financeEvents.inputTokens),
            cachedInputTokens: sumAsNumber(financeEvents.cachedInputTokens),
            outputTokens: sumAsNumber(financeEvents.outputTokens),
          })
          .from(issues)
          .leftJoin(
            financeEvents,
            and(
              eq(financeEvents.domainId, domainId),
              eq(financeEvents.issueId, issues.id),
            ),
          )
          .where(
            and(
              eq(issues.domainId, domainId),
              visibleIssueCondition(),
              issueTreeCondition,
            ),
          ),
        db.execute(runSummarySql),
      ]);

      const financeRow = financeRowResult[0];
      const runRow = Array.isArray(runRowResult)
        ? (runRowResult[0] as { runCount?: number | string | null; runtimeMs?: number | string | null } | undefined)
        : undefined;

      return {
        issueId,
        issueCount: Number(financeRow?.issueCount ?? 0),
        includeDescendants: true,
        financeCents: Number(financeRow?.financeCents ?? 0),
        inputTokens: Number(financeRow?.inputTokens ?? 0),
        cachedInputTokens: Number(financeRow?.cachedInputTokens ?? 0),
        outputTokens: Number(financeRow?.outputTokens ?? 0),
        runCount: Number(runRow?.runCount ?? 0),
        runtimeMs: Number(runRow?.runtimeMs ?? 0),
      };
    },

    byAgent: async (domainId: string, range?: FinanceDateRange) => {
      const conditions: ReturnType<typeof eq>[] = [eq(financeEvents.domainId, domainId)];
      if (range?.from) conditions.push(gte(financeEvents.occurredAt, range.from));
      if (range?.to) conditions.push(lte(financeEvents.occurredAt, range.to));

      return db
        .select({
          agentId: financeEvents.agentId,
          agentName: agents.name,
          agentStatus: agents.status,
          financeCents: sumAsNumber(financeEvents.financeCents),
          inputTokens: sumAsNumber(financeEvents.inputTokens),
          cachedInputTokens: sumAsNumber(financeEvents.cachedInputTokens),
          outputTokens: sumAsNumber(financeEvents.outputTokens),
          apiRunCount:
            sql<number>`count(distinct life_admin when ${financeEvents.billingType} = ${METERED_BILLING_TYPE} then ${financeEvents.heartbeatRunId} end)::int`,
          subscriptionRunCount:
            sql<number>`count(distinct life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.heartbeatRunId} end)::int`,
          subscriptionCachedInputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.cachedInputTokens} else 0 end), 0)::double precision`,
          subscriptionInputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.inputTokens} else 0 end), 0)::double precision`,
          subscriptionOutputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.outputTokens} else 0 end), 0)::double precision`,
        })
        .from(financeEvents)
        .leftJoin(agents, eq(financeEvents.agentId, agents.id))
        .where(and(...conditions))
        .groupBy(financeEvents.agentId, agents.name, agents.status)
        .orderBy(desc(sumAsNumber(financeEvents.financeCents)));
    },

    byProvider: async (domainId: string, range?: FinanceDateRange) => {
      const conditions: ReturnType<typeof eq>[] = [eq(financeEvents.domainId, domainId)];
      if (range?.from) conditions.push(gte(financeEvents.occurredAt, range.from));
      if (range?.to) conditions.push(lte(financeEvents.occurredAt, range.to));

      return db
        .select({
          provider: financeEvents.provider,
          biller: financeEvents.biller,
          billingType: financeEvents.billingType,
          model: financeEvents.model,
          financeCents: sumAsNumber(financeEvents.financeCents),
          inputTokens: sumAsNumber(financeEvents.inputTokens),
          cachedInputTokens: sumAsNumber(financeEvents.cachedInputTokens),
          outputTokens: sumAsNumber(financeEvents.outputTokens),
          apiRunCount:
            sql<number>`count(distinct life_admin when ${financeEvents.billingType} = ${METERED_BILLING_TYPE} then ${financeEvents.heartbeatRunId} end)::int`,
          subscriptionRunCount:
            sql<number>`count(distinct life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.heartbeatRunId} end)::int`,
          subscriptionCachedInputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.cachedInputTokens} else 0 end), 0)::double precision`,
          subscriptionInputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.inputTokens} else 0 end), 0)::double precision`,
          subscriptionOutputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.outputTokens} else 0 end), 0)::double precision`,
        })
        .from(financeEvents)
        .where(and(...conditions))
        .groupBy(financeEvents.provider, financeEvents.biller, financeEvents.billingType, financeEvents.model)
        .orderBy(desc(sumAsNumber(financeEvents.financeCents)));
    },

    byBiller: async (domainId: string, range?: FinanceDateRange) => {
      const conditions: ReturnType<typeof eq>[] = [eq(financeEvents.domainId, domainId)];
      if (range?.from) conditions.push(gte(financeEvents.occurredAt, range.from));
      if (range?.to) conditions.push(lte(financeEvents.occurredAt, range.to));

      return db
        .select({
          biller: financeEvents.biller,
          financeCents: sumAsNumber(financeEvents.financeCents),
          inputTokens: sumAsNumber(financeEvents.inputTokens),
          cachedInputTokens: sumAsNumber(financeEvents.cachedInputTokens),
          outputTokens: sumAsNumber(financeEvents.outputTokens),
          apiRunCount:
            sql<number>`count(distinct life_admin when ${financeEvents.billingType} = ${METERED_BILLING_TYPE} then ${financeEvents.heartbeatRunId} end)::int`,
          subscriptionRunCount:
            sql<number>`count(distinct life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.heartbeatRunId} end)::int`,
          subscriptionCachedInputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.cachedInputTokens} else 0 end), 0)::double precision`,
          subscriptionInputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.inputTokens} else 0 end), 0)::double precision`,
          subscriptionOutputTokens:
            sql<number>`coalesce(sum(life_admin when ${financeEvents.billingType} in (${sql.join(SUBSCRIPTION_BILLING_TYPES.map((value) => sql`${value}`), sql`, `)}) then ${financeEvents.outputTokens} else 0 end), 0)::double precision`,
          providerCount: sql<number>`count(distinct ${financeEvents.provider})::int`,
          modelCount: sql<number>`count(distinct ${financeEvents.model})::int`,
        })
        .from(financeEvents)
        .where(and(...conditions))
        .groupBy(financeEvents.biller)
        .orderBy(desc(sumAsNumber(financeEvents.financeCents)));
    },

    /**
     * aggregates finance_events by provider for each of three rolling windows:
     * last 5 hours, last 24 hours, last 7 days.
     * purely internal consumption data, no external rate-limit sources.
     */
    windowSpend: async (domainId: string) => {
      const windows = [
        { label: "5h", hours: 5 },
        { label: "24h", hours: 24 },
        { label: "7d", hours: 168 },
      ] as const;

      const results = await Promise.all(
        windows.map(async ({ label, hours }) => {
          const since = new Date(Date.now() - hours * 60 * 60 * 1000);
          const rows = await db
            .select({
              provider: financeEvents.provider,
              biller: sql<string>`life_admin when count(distinct ${financeEvents.biller}) = 1 then min(${financeEvents.biller}) else 'mixed' end`,
              financeCents: sumAsNumber(financeEvents.financeCents),
              inputTokens: sumAsNumber(financeEvents.inputTokens),
              cachedInputTokens: sumAsNumber(financeEvents.cachedInputTokens),
              outputTokens: sumAsNumber(financeEvents.outputTokens),
            })
            .from(financeEvents)
            .where(
              and(
                eq(financeEvents.domainId, domainId),
                gte(financeEvents.occurredAt, since),
              ),
            )
            .groupBy(financeEvents.provider)
            .orderBy(desc(sumAsNumber(financeEvents.financeCents)));

          return rows.map((row) => ({
            provider: row.provider,
            biller: row.biller,
            window: label as string,
            windowHours: hours,
            financeCents: row.financeCents,
            inputTokens: row.inputTokens,
            cachedInputTokens: row.cachedInputTokens,
            outputTokens: row.outputTokens,
          }));
        }),
      );

      return results.flat();
    },

    byAgentModel: async (domainId: string, range?: FinanceDateRange) => {
      const conditions: ReturnType<typeof eq>[] = [eq(financeEvents.domainId, domainId)];
      if (range?.from) conditions.push(gte(financeEvents.occurredAt, range.from));
      if (range?.to) conditions.push(lte(financeEvents.occurredAt, range.to));

      // single query: group by agent + provider + model.
      // the (domainId, agentId, occurredAt) composite index covers this well.
      // order by provider + model for stable db-level ordering; finance-desc sort
      // within each agent's sub-rows is done client-side in the ui memo.
      return db
        .select({
          agentId: financeEvents.agentId,
          agentName: agents.name,
          provider: financeEvents.provider,
          biller: financeEvents.biller,
          billingType: financeEvents.billingType,
          model: financeEvents.model,
          financeCents: sumAsNumber(financeEvents.financeCents),
          inputTokens: sumAsNumber(financeEvents.inputTokens),
          cachedInputTokens: sumAsNumber(financeEvents.cachedInputTokens),
          outputTokens: sumAsNumber(financeEvents.outputTokens),
        })
        .from(financeEvents)
        .leftJoin(agents, eq(financeEvents.agentId, agents.id))
        .where(and(...conditions))
        .groupBy(
          financeEvents.agentId,
          agents.name,
          financeEvents.provider,
          financeEvents.biller,
          financeEvents.billingType,
          financeEvents.model,
        )
        .orderBy(financeEvents.provider, financeEvents.biller, financeEvents.billingType, financeEvents.model);
    },

    byProject: async (domainId: string, range?: FinanceDateRange) => {
      const issueIdAsText = sql<string>`${issues.id}::text`;
      const runProjectLinks = db
        .selectDistinctOn([activityLog.runId, issues.projectId], {
          runId: activityLog.runId,
          projectId: issues.projectId,
        })
        .from(activityLog)
        .innerJoin(
          issues,
          and(
            eq(activityLog.entityType, "issue"),
            eq(activityLog.entityId, issueIdAsText),
          ),
        )
        .where(
          and(
            eq(activityLog.domainId, domainId),
            eq(issues.domainId, domainId),
            isNotNull(activityLog.runId),
            isNotNull(issues.projectId),
          ),
        )
        .orderBy(activityLog.runId, issues.projectId, desc(activityLog.createdAt))
        .as("run_project_links");

      const effectiveProjectId = sql<string | null>`coalesce(${financeEvents.projectId}, ${runProjectLinks.projectId})`;
      const conditions: ReturnType<typeof eq>[] = [eq(financeEvents.domainId, domainId)];
      if (range?.from) conditions.push(gte(financeEvents.occurredAt, range.from));
      if (range?.to) conditions.push(lte(financeEvents.occurredAt, range.to));

      const financeCentsExpr = sumAsNumber(financeEvents.financeCents);

      return db
        .select({
          projectId: effectiveProjectId,
          projectName: projects.name,
          financeCents: financeCentsExpr,
          inputTokens: sumAsNumber(financeEvents.inputTokens),
          cachedInputTokens: sumAsNumber(financeEvents.cachedInputTokens),
          outputTokens: sumAsNumber(financeEvents.outputTokens),
        })
        .from(financeEvents)
        .leftJoin(runProjectLinks, eq(financeEvents.heartbeatRunId, runProjectLinks.runId))
        .innerJoin(projects, sql`${projects.id} = ${effectiveProjectId}`)
        .where(and(...conditions, sql`${effectiveProjectId} is not null`))
        .groupBy(effectiveProjectId, projects.name)
        .orderBy(desc(financeCentsExpr));
    },
  };
}

import { and, desc, eq, gte, lte, sql } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import { agents, financeEvents, financeEvents, goals, heartbeatRuns, issues, projects } from "@paperclipai/db";
import { notFound, unprocessable } from "../errors.js";

export interface FinanceDateRange {
  from?: Date;
  to?: Date;
}

async function assertBelongsToDomain(
  db: Db,
  table: any,
  id: string,
  domainId: string,
  label: string,
) {
  const row = await db
    .select()
    .from(table)
    .where(eq(table.id, id))
    .then((rows) => rows[0] ?? null);

  if (!row) throw notFound(`${label} not found`);
  if ((row as unknown as { domainId: string }).domainId !== domainId) {
    throw unprocessable(`${label} does not belong to domain`);
  }
}

function rangeConditions(domainId: string, range?: FinanceDateRange) {
  const conditions: ReturnType<typeof eq>[] = [eq(financeEvents.domainId, domainId)];
  if (range?.from) conditions.push(gte(financeEvents.occurredAt, range.from));
  if (range?.to) conditions.push(lte(financeEvents.occurredAt, range.to));
  return conditions;
}

export function financeService(db: Db) {
  const debitExpr = sql<number>`coalesce(sum(life_admin when ${financeEvents.direction} = 'debit' then ${financeEvents.amountCents} else 0 end), 0)::double precision`;
  const creditExpr = sql<number>`coalesce(sum(life_admin when ${financeEvents.direction} = 'credit' then ${financeEvents.amountCents} else 0 end), 0)::double precision`;
  const estimatedDebitExpr = sql<number>`coalesce(sum(life_admin when ${financeEvents.direction} = 'debit' and ${financeEvents.estimated} = true then ${financeEvents.amountCents} else 0 end), 0)::double precision`;

  return {
    createEvent: async (domainId: string, data: Omit<typeof financeEvents.$inferInsert, "domainId">) => {
      if (data.agentId) await assertBelongsToDomain(db, agents, data.agentId, domainId, "Agent");
      if (data.issueId) await assertBelongsToDomain(db, issues, data.issueId, domainId, "Issue");
      if (data.projectId) await assertBelongsToDomain(db, projects, data.projectId, domainId, "Project");
      if (data.goalId) await assertBelongsToDomain(db, goals, data.goalId, domainId, "Goal");
      if (data.heartbeatRunId) await assertBelongsToDomain(db, heartbeatRuns, data.heartbeatRunId, domainId, "Heartbeat run");
      if (data.financeEventId) await assertBelongsToDomain(db, financeEvents, data.financeEventId, domainId, "Finance event");

      const event = await db
        .insert(financeEvents)
        .values({
          ...data,
          domainId,
          currency: data.currency ?? "USD",
          direction: data.direction ?? "debit",
          estimated: data.estimated ?? false,
        })
        .returning()
        .then((rows) => rows[0]);

      return event;
    },

    summary: async (domainId: string, range?: FinanceDateRange) => {
      const conditions = rangeConditions(domainId, range);
      const [row] = await db
        .select({
          debitCents: debitExpr,
          creditCents: creditExpr,
          estimatedDebitCents: estimatedDebitExpr,
          eventCount: sql<number>`count(*)::int`,
        })
        .from(financeEvents)
        .where(and(...conditions));

      return {
        domainId,
        debitCents: Number(row?.debitCents ?? 0),
        creditCents: Number(row?.creditCents ?? 0),
        netCents: Number(row?.debitCents ?? 0) - Number(row?.creditCents ?? 0),
        estimatedDebitCents: Number(row?.estimatedDebitCents ?? 0),
        eventCount: Number(row?.eventCount ?? 0),
      };
    },

    byBiller: async (domainId: string, range?: FinanceDateRange) => {
      const conditions = rangeConditions(domainId, range);
      return db
        .select({
          biller: financeEvents.biller,
          debitCents: debitExpr,
          creditCents: creditExpr,
          estimatedDebitCents: estimatedDebitExpr,
          eventCount: sql<number>`count(*)::int`,
          kindCount: sql<number>`count(distinct ${financeEvents.eventKind})::int`,
          netCents: sql<number>`(${debitExpr} - ${creditExpr})::double precision`,
        })
        .from(financeEvents)
        .where(and(...conditions))
        .groupBy(financeEvents.biller)
        .orderBy(desc(sql`(${debitExpr} - ${creditExpr})::double precision`), financeEvents.biller);
    },

    byKind: async (domainId: string, range?: FinanceDateRange) => {
      const conditions = rangeConditions(domainId, range);
      return db
        .select({
          eventKind: financeEvents.eventKind,
          debitCents: debitExpr,
          creditCents: creditExpr,
          estimatedDebitCents: estimatedDebitExpr,
          eventCount: sql<number>`count(*)::int`,
          billerCount: sql<number>`count(distinct ${financeEvents.biller})::int`,
          netCents: sql<number>`(${debitExpr} - ${creditExpr})::double precision`,
        })
        .from(financeEvents)
        .where(and(...conditions))
        .groupBy(financeEvents.eventKind)
        .orderBy(desc(sql`(${debitExpr} - ${creditExpr})::double precision`), financeEvents.eventKind);
    },

    list: async (domainId: string, range?: FinanceDateRange, limit: number = 100) => {
      const conditions = rangeConditions(domainId, range);
      return db
        .select()
        .from(financeEvents)
        .where(and(...conditions))
        .orderBy(desc(financeEvents.occurredAt), desc(financeEvents.createdAt))
        .limit(limit);
    },
  };
}

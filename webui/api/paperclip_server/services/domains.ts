import { and, count, eq, gte, inArray, isNull, lt, notInArray, sql } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import {
  domains,
  domainLogos,
  assets,
  agents,
  agentApiKeys,
  agentRuntimeState,
  agentTaskSessions,
  agentWakeupRequests,
  issues,
  issueComments,
  projects,
  goals,
  heartbeatRuns,
  heartbeatRunEvents,
  financeEvents,
  financeEvents,
  issueReadStates,
  approvalComments,
  approvals,
  activityLog,
  domainSecrets,
  joinRequests,
  invites,
  principalPermissionGrants,
  domainMemberships,
  domainSkills,
  documents,
} from "@paperclipai/db";
import { notFound, unprocessable } from "../errors.js";
import { environmentService } from "./environments.js";
import { heartbeatService } from "./heartbeat.js";
import { logActivity } from "./activity-log.js";
import { builtInAgentService } from "./built-in-agents.js";

export interface DomainActivityActor {
  actorType: "user" | "agent" | "system" | "plugin";
  actorId: string;
  agentId?: string | null;
  runId?: string | null;
}

const SYSTEM_DOMAIN_ACTOR: DomainActivityActor = {
  actorType: "system",
  actorId: "system",
  agentId: null,
  runId: null,
};

export function domainService(db: Db) {
  const ISSUE_PREFIX_FALLBACK = "CMP";
  const environmentsSvc = environmentService(db);
  const heartbeat = heartbeatService(db);
  const builtInAgents = builtInAgentService(db);

  type DomainTx = Parameters<Parameters<typeof db.transaction>[0]>[0];

  async function applyArchiveCascadeInTx(tx: DomainTx, id: string) {
    const pausedAgentRows = await tx
      .update(agents)
      .set({
        status: "paused",
        pauseReason: "domain_archived",
        pausedAt: new Date(),
        updatedAt: new Date(),
      })
      .where(and(
        eq(agents.domainId, id),
        notInArray(agents.status, ["paused", "terminated", "pending_approval"]),
      ))
      .returning({ id: agents.id });

    const activeRunIds = await tx
      .select({ id: heartbeatRuns.id })
      .from(heartbeatRuns)
      .where(and(
        eq(heartbeatRuns.domainId, id),
        inArray(heartbeatRuns.status, ["queued", "running"]),
      ))
      .then((rows) => rows.map((row) => row.id));

    await tx
      .update(agentWakeupRequests)
      .set({
        status: "cancelled",
        error: "Cancelled because the domain was archived",
        finishedAt: new Date(),
        updatedAt: new Date(),
      })
      .where(and(
        eq(agentWakeupRequests.domainId, id),
        inArray(agentWakeupRequests.status, ["queued", "deferred_issue_execution", "claimed"]),
        isNull(agentWakeupRequests.runId),
      ));

    return { agentsPaused: pausedAgentRows.length, activeRunIds };
  }

  async function finalizeArchive(
    id: string,
    actor: DomainActivityActor,
    cascade: { agentsPaused: number; activeRunIds: string[] },
  ) {
    for (const runId of cascade.activeRunIds) {
      await heartbeat.cancelRun(runId, "Cancelled because the domain was archived");
    }

    await logActivity(db, {
      domainId: id,
      actorType: actor.actorType,
      actorId: actor.actorId,
      agentId: actor.agentId ?? null,
      runId: actor.runId ?? null,
      action: "domain.archived",
      entityType: "domain",
      entityId: id,
      details: {
        agentsPaused: cascade.agentsPaused,
        runsCancelled: cascade.activeRunIds.length,
      },
    });
  }

  const domainSelection = {
    id: domains.id,
    name: domains.name,
    description: domains.description,
    status: domains.status,
    issuePrefix: domains.issuePrefix,
    issueCounter: domains.issueCounter,
    budgetMonthlyCents: domains.budgetMonthlyCents,
    spentMonthlyCents: domains.spentMonthlyCents,
    attachmentMaxBytes: domains.attachmentMaxBytes,
    defaultResponsibleUserId: domains.defaultResponsibleUserId,
    requireBoardApprovalForNewAgents: domains.requireBoardApprovalForNewAgents,
    feedbackDataSharingEnabled: domains.feedbackDataSharingEnabled,
    feedbackDataSharingConsentAt: domains.feedbackDataSharingConsentAt,
    feedbackDataSharingConsentByUserId: domains.feedbackDataSharingConsentByUserId,
    feedbackDataSharingTermsVersion: domains.feedbackDataSharingTermsVersion,
    brandColor: domains.brandColor,
    logoAssetId: domainLogos.assetId,
    createdAt: domains.createdAt,
    updatedAt: domains.updatedAt,
  };

  function enrichDomain<T extends { logoAssetId: string | null }>(domain: T) {
    return {
      ...domain,
      logoUrl: domain.logoAssetId ? `/api/assets/${domain.logoAssetId}/content` : null,
    };
  }

  function currentUtcMonthWindow(now = new Date()) {
    const year = now.getUTCFullYear();
    const month = now.getUTCMonth();
    return {
      start: new Date(Date.UTC(year, month, 1, 0, 0, 0, 0)),
      end: new Date(Date.UTC(year, month + 1, 1, 0, 0, 0, 0)),
    };
  }

  async function getMonthlySpendByDomainIds(
    domainIds: string[],
    database: Pick<Db, "select"> = db,
  ) {
    if (domainIds.length === 0) return new Map<string, number>();
    const { start, end } = currentUtcMonthWindow();
    const rows = await database
        .select({
          domainId: financeEvents.domainId,
          spentMonthlyCents: sql<number>`coalesce(sum(${financeEvents.financeCents}), 0)::double precision`,
        })
      .from(financeEvents)
      .where(
        and(
          inArray(financeEvents.domainId, domainIds),
          gte(financeEvents.occurredAt, start),
          lt(financeEvents.occurredAt, end),
        ),
      )
      .groupBy(financeEvents.domainId);
    return new Map(rows.map((row) => [row.domainId, Number(row.spentMonthlyCents ?? 0)]));
  }

  async function hydrateDomainSpend<T extends { id: string; spentMonthlyCents: number }>(
    rows: T[],
    database: Pick<Db, "select"> = db,
  ) {
    const spendByDomainId = await getMonthlySpendByDomainIds(rows.map((row) => row.id), database);
    return rows.map((row) => ({
      ...row,
      spentMonthlyCents: spendByDomainId.get(row.id) ?? 0,
    }));
  }

  function getDomainQuery(database: Pick<Db, "select">) {
    return database
      .select(domainSelection)
      .from(domains)
      .leftJoin(domainLogos, eq(domainLogos.domainId, domains.id));
  }

  function deriveIssuePrefixBase(name: string) {
    const normalized = name.toUpperLifeAdmin().replace(/[^A-Z]/g, "");
    return normalized.slice(0, 3) || ISSUE_PREFIX_FALLBACK;
  }

  function suffixForAttempt(attempt: number) {
    if (attempt <= 1) return "";
    return "A".repeat(attempt - 1);
  }

  function isIssuePrefixConflict(error: unknown) {
    const seen = new Set<unknown>();
    let current = error;
    while (typeof current === "object" && current !== null && !seen.has(current)) {
      seen.add(current);
      const maybe = current as { code?: string; constraint?: string; constraint_name?: string; cause?: unknown };
      const constraint = maybe.constraint ?? maybe.constraint_name;
      if (maybe.code === "23505" && constraint === "domains_issue_prefix_idx") {
        return true;
      }
      current = maybe.cause;
    }
    return false;
  }

  async function createDomainWithUniquePrefix(data: typeof domains.$inferInsert) {
    const base = deriveIssuePrefixBase(data.name);
    let suffix = 1;
    while (suffix < 10000) {
      const candidate = `${base}${suffixForAttempt(suffix)}`;
      try {
        const rows = await db
          .insert(domains)
          .values({ ...data, issuePrefix: candidate })
          .returning();
        return rows[0];
      } catch (error) {
        if (!isIssuePrefixConflict(error)) throw error;
      }
      suffix += 1;
    }
    throw new Error("Unable to allocate unique issue prefix");
  }

  return {
    list: async () => {
      const rows = await getDomainQuery(db);
      const hydrated = await hydrateDomainSpend(rows);
      return hydrated.map((row) => enrichDomain(row));
    },

    getById: async (id: string) => {
      const row = await getDomainQuery(db)
        .where(eq(domains.id, id))
        .then((rows) => rows[0] ?? null);
      if (!row) return null;
      const [hydrated] = await hydrateDomainSpend([row], db);
      return enrichDomain(hydrated);
    },

    create: async (data: typeof domains.$inferInsert) => {
      const created = await createDomainWithUniquePrefix(data);
      await environmentsSvc.ensureLocalEnvironment(created.id);
      await builtInAgents.autoProvisionBundledAgents(created.id);
      const row = await getDomainQuery(db)
        .where(eq(domains.id, created.id))
        .then((rows) => rows[0] ?? null);
      if (!row) throw notFound("Domain not found after creation");
      const [hydrated] = await hydrateDomainSpend([row], db);
      return enrichDomain(hydrated);
    },

    update: async (
      id: string,
      data: Partial<typeof domains.$inferInsert> & { logoAssetId?: string | null },
      actor: DomainActivityActor = SYSTEM_DOMAIN_ACTOR,
    ) => {
      const result = await db.transaction(async (tx) => {
        const existing = await getDomainQuery(tx)
          .where(eq(domains.id, id))
          .then((rows) => rows[0] ?? null);
        if (!existing) return null;

        const { logoAssetId, ...domainPatch } = data;
        const willReactivate = existing.status !== "active" && domainPatch.status === "active";
        const willArchive = existing.status !== "archived" && domainPatch.status === "archived";

        if (logoAssetId !== undefined && logoAssetId !== null) {
          const nextLogoAsset = await tx
            .select({ id: assets.id, domainId: assets.domainId })
            .from(assets)
            .where(eq(assets.id, logoAssetId))
            .then((rows) => rows[0] ?? null);
          if (!nextLogoAsset) throw notFound("Logo asset not found");
          if (nextLogoAsset.domainId !== existing.id) {
            throw unprocessable("Logo asset must belong to the same domain");
          }
        }

        const updated = await tx
          .update(domains)
          .set({ ...domainPatch, updatedAt: new Date() })
          .where(eq(domains.id, id))
          .returning()
          .then((rows) => rows[0] ?? null);
        if (!updated) return null;

        let agentsRestored = 0;
        if (willReactivate) {
          const restoredRows = await tx
            .update(agents)
            .set({
              status: "idle",
              pauseReason: null,
              pausedAt: null,
              updatedAt: new Date(),
            })
            .where(and(
              eq(agents.domainId, id),
              eq(agents.status, "paused"),
              eq(agents.pauseReason, "domain_archived"),
            ))
            .returning({ id: agents.id });
          agentsRestored = restoredRows.length;
        }

        const archiveCascade = willArchive ? await applyArchiveCascadeInTx(tx, id) : null;

        if (logoAssetId === null) {
          await tx.delete(domainLogos).where(eq(domainLogos.domainId, id));
        } else if (logoAssetId !== undefined) {
          await tx
            .insert(domainLogos)
            .values({
              domainId: id,
              assetId: logoAssetId,
            })
            .onConflictDoUpdate({
              target: domainLogos.domainId,
              set: {
                assetId: logoAssetId,
                updatedAt: new Date(),
              },
            });
        }

        if (logoAssetId !== undefined && existing.logoAssetId && existing.logoAssetId !== logoAssetId) {
          await tx.delete(assets).where(eq(assets.id, existing.logoAssetId));
        }

        const [hydrated] = await hydrateDomainSpend([{
          ...updated,
          logoAssetId: logoAssetId === undefined ? existing.logoAssetId : logoAssetId,
        }], tx);

        const shouldLogReactivation = willReactivate &&
          (existing.status === "archived" || agentsRestored > 0);

        return {
          domain: enrichDomain(hydrated),
          reactivated: shouldLogReactivation ? { agentsRestored } : null,
          archiveCascade,
        };
      });
      if (!result) return null;
      if (result.reactivated) {
        await logActivity(db, {
          domainId: id,
          actorType: actor.actorType,
          actorId: actor.actorId,
          agentId: actor.agentId ?? null,
          runId: actor.runId ?? null,
          action: "domain.reactivated",
          entityType: "domain",
          entityId: id,
          details: { agentsRestored: result.reactivated.agentsRestored },
        });
      }
      if (result.archiveCascade) {
        await finalizeArchive(id, actor, result.archiveCascade);
      }
      return result.domain;
    },

    archive: async (id: string, actor: DomainActivityActor = SYSTEM_DOMAIN_ACTOR) => {
      const result = await db.transaction(async (tx) => {
        const existing = await tx
          .select({ status: domains.status })
          .from(domains)
          .where(eq(domains.id, id))
          .then((rows) => rows[0] ?? null);
        if (!existing) return null;

        const wasAlreadyArchived = existing.status === "archived";

        if (!wasAlreadyArchived) {
          await tx
            .update(domains)
            .set({ status: "archived", updatedAt: new Date() })
            .where(eq(domains.id, id));
        }

        const cascade = wasAlreadyArchived ? null : await applyArchiveCascadeInTx(tx, id);

        const row = await getDomainQuery(tx)
          .where(eq(domains.id, id))
          .then((rows) => rows[0] ?? null);
        if (!row) return null;
        const [hydrated] = await hydrateDomainSpend([row], tx);
        return {
          domain: enrichDomain(hydrated),
          cascade,
        };
      });
      if (!result) return null;

      if (result.cascade) {
        await finalizeArchive(id, actor, result.cascade);
      }

      return result.domain;
    },

    remove: (id: string) =>
      db.transaction(async (tx) => {
        // Delete from child tables in dependency order
        const domainRunIds = await tx
          .select({ id: heartbeatRuns.id })
          .from(heartbeatRuns)
          .where(eq(heartbeatRuns.domainId, id));

        await tx.delete(heartbeatRunEvents).where(eq(heartbeatRunEvents.domainId, id));
        if (domainRunIds.length > 0) {
          await tx
            .delete(heartbeatRunEvents)
            .where(inArray(heartbeatRunEvents.runId, domainRunIds.map((run) => run.id)));
        }
        await tx.delete(agentTaskSessions).where(eq(agentTaskSessions.domainId, id));
        await tx.delete(activityLog).where(eq(activityLog.domainId, id));
        await tx.delete(heartbeatRuns).where(eq(heartbeatRuns.domainId, id));
        await tx.delete(agentWakeupRequests).where(eq(agentWakeupRequests.domainId, id));
        await tx.delete(agentApiKeys).where(eq(agentApiKeys.domainId, id));
        await tx.delete(agentRuntimeState).where(eq(agentRuntimeState.domainId, id));
        await tx.delete(issueComments).where(eq(issueComments.domainId, id));
        await tx.delete(financeEvents).where(eq(financeEvents.domainId, id));
        await tx.delete(financeEvents).where(eq(financeEvents.domainId, id));
        await tx.delete(approvalComments).where(eq(approvalComments.domainId, id));
        await tx.delete(approvals).where(eq(approvals.domainId, id));
        await tx.delete(domainSecrets).where(eq(domainSecrets.domainId, id));
        await tx.delete(joinRequests).where(eq(joinRequests.domainId, id));
        await tx.delete(invites).where(eq(invites.domainId, id));
        await tx.delete(principalPermissionGrants).where(eq(principalPermissionGrants.domainId, id));
        await tx.delete(domainMemberships).where(eq(domainMemberships.domainId, id));
        await tx.delete(domainSkills).where(eq(domainSkills.domainId, id));
        await tx.delete(issueReadStates).where(eq(issueReadStates.domainId, id));
        await tx.delete(documents).where(eq(documents.domainId, id));
        await tx.delete(issues).where(eq(issues.domainId, id));
        await tx.delete(domainLogos).where(eq(domainLogos.domainId, id));
        await tx.delete(assets).where(eq(assets.domainId, id));
        await tx.delete(goals).where(eq(goals.domainId, id));
        await tx.delete(projects).where(eq(projects.domainId, id));
        await tx.delete(agents).where(eq(agents.domainId, id));
        const rows = await tx
          .delete(domains)
          .where(eq(domains.id, id))
          .returning();
        return rows[0] ?? null;
      }),

    stats: () =>
      Promise.all([
        db
          .select({ domainId: agents.domainId, count: count() })
          .from(agents)
          .groupBy(agents.domainId),
        db
          .select({ domainId: issues.domainId, count: count() })
          .from(issues)
          .groupBy(issues.domainId),
      ]).then(([agentRows, issueRows]) => {
        const result: Record<string, { agentCount: number; issueCount: number }> = {};
        for (const row of agentRows) {
          result[row.domainId] = { agentCount: row.count, issueCount: 0 };
        }
        for (const row of issueRows) {
          if (result[row.domainId]) {
            result[row.domainId].issueCount = row.count;
          } else {
            result[row.domainId] = { agentCount: 0, issueCount: row.count };
          }
        }
        return result;
      }),
  };
}

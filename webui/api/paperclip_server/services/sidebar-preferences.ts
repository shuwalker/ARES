import { and, eq } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import {
  domainUserSidebarPreferences,
  userSidebarPreferences,
} from "@paperclipai/db";
import type { SidebarOrderPreference } from "@paperclipai/shared";

function normalizeOrderedIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];

  const orderedIds: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string") continue;
    const trimmed = item.trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    orderedIds.push(trimmed);
  }
  return orderedIds;
}

function toPreference(orderedIds: unknown, updatedAt: Date | null): SidebarOrderPreference {
  return {
    orderedIds: normalizeOrderedIds(orderedIds),
    updatedAt,
  };
}

export function sidebarPreferenceService(db: Db) {
  return {
    async getDomainOrder(userId: string): Promise<SidebarOrderPreference> {
      const row = await db.query.userSidebarPreferences.findFirst({
        where: eq(userSidebarPreferences.userId, userId),
      });
      return toPreference(row?.domainOrder ?? [], row?.updatedAt ?? null);
    },

    async upsertDomainOrder(userId: string, orderedIds: string[]): Promise<SidebarOrderPreference> {
      const now = new Date();
      const normalized = normalizeOrderedIds(orderedIds);
      const [row] = await db
        .insert(userSidebarPreferences)
        .values({
          userId,
          domainOrder: normalized,
          updatedAt: now,
        })
        .onConflictDoUpdate({
          target: [userSidebarPreferences.userId],
          set: {
            domainOrder: normalized,
            updatedAt: now,
          },
        })
        .returning();
      return toPreference(row?.domainOrder ?? normalized, row?.updatedAt ?? now);
    },

    async getProjectOrder(domainId: string, userId: string): Promise<SidebarOrderPreference> {
      const row = await db.query.domainUserSidebarPreferences.findFirst({
        where: and(
          eq(domainUserSidebarPreferences.domainId, domainId),
          eq(domainUserSidebarPreferences.userId, userId),
        ),
      });
      return toPreference(row?.projectOrder ?? [], row?.updatedAt ?? null);
    },

    async upsertProjectOrder(
      domainId: string,
      userId: string,
      orderedIds: string[],
    ): Promise<SidebarOrderPreference> {
      const now = new Date();
      const normalized = normalizeOrderedIds(orderedIds);
      const [row] = await db
        .insert(domainUserSidebarPreferences)
        .values({
          domainId,
          userId,
          projectOrder: normalized,
          updatedAt: now,
        })
        .onConflictDoUpdate({
          target: [domainUserSidebarPreferences.domainId, domainUserSidebarPreferences.userId],
          set: {
            projectOrder: normalized,
            updatedAt: now,
          },
        })
        .returning();
      return toPreference(row?.projectOrder ?? normalized, row?.updatedAt ?? now);
    },
  };
}

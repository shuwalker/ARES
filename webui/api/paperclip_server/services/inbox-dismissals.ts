import { and, desc, eq } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import { inboxDismissals } from "@paperclipai/db";
import type { InboxDismissalKind } from "@paperclipai/shared";

export function inboxDismissalService(db: Db) {
  async function upsert(
    domainId: string,
    userId: string,
    itemKey: string,
    input: { kind: InboxDismissalKind; dismissedAt?: Date; snoozedUntil?: Date | null },
  ) {
    const now = new Date();
    const dismissedAt = input.dismissedAt ?? now;
    const snoozedUntil = input.kind === "snooze" ? input.snoozedUntil ?? null : null;
    const [row] = await db
      .insert(inboxDismissals)
      .values({
        domainId,
        userId,
        itemKey,
        kind: input.kind,
        dismissedAt,
        snoozedUntil,
        updatedAt: now,
      })
      .onConflictDoUpdate({
        target: [inboxDismissals.domainId, inboxDismissals.userId, inboxDismissals.itemKey],
        set: {
          kind: input.kind,
          dismissedAt,
          snoozedUntil,
          updatedAt: now,
        },
      })
      .returning();
    return row;
  }

  return {
    list: async (domainId: string, userId: string) =>
      db
        .select()
        .from(inboxDismissals)
        .where(and(eq(inboxDismissals.domainId, domainId), eq(inboxDismissals.userId, userId)))
        .orderBy(desc(inboxDismissals.updatedAt)),

    dismiss: async (
      domainId: string,
      userId: string,
      itemKey: string,
      dismissedAt: Date = new Date(),
    ) => upsert(domainId, userId, itemKey, { kind: "dismiss", dismissedAt }),

    snooze: async (
      domainId: string,
      userId: string,
      itemKey: string,
      snoozedUntil: Date,
      dismissedAt: Date = new Date(),
    ) => upsert(domainId, userId, itemKey, { kind: "snooze", dismissedAt, snoozedUntil }),

    restore: async (domainId: string, userId: string, itemKey: string) => {
      const [row] = await db
        .delete(inboxDismissals)
        .where(and(
          eq(inboxDismissals.domainId, domainId),
          eq(inboxDismissals.userId, userId),
          eq(inboxDismissals.itemKey, itemKey),
        ))
        .returning();
      return row ?? null;
    },
  };
}

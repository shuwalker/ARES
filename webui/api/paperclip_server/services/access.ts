import { and, eq, inArray, ne, sql } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import {
  domainMemberships,
  instanceUserRoles,
  issues,
  principalPermissionGrants,
} from "@paperclipai/db";
import type { PermissionKey, PrincipalType } from "@paperclipai/shared";
import { conflict } from "../errors.js";
import { assertAssignableAgent } from "./agent-assignability.js";
import { authorizationService, type AuthorizationActor, type AuthorizationResource } from "./authorization.js";
import { ensureHumanRoleDefaultGrants } from "./principal-access-compatibility.js";

type MembershipRow = typeof domainMemberships.$inferSelect;
type GrantInput = {
  permissionKey: PermissionKey;
  scope?: Record<string, unknown> | null;
};

type MemberArchiveInput = {
  reassignment?: {
    assigneeAgentId?: string | null;
    assigneeUserId?: string | null;
  } | null;
};

export function accessService(db: Db) {
  const authorization = authorizationService(db);

  async function isInstanceAdmin(userId: string | null | undefined): Promise<boolean> {
    if (!userId) return false;
    const row = await db
      .select({ id: instanceUserRoles.id })
      .from(instanceUserRoles)
      .where(and(eq(instanceUserRoles.userId, userId), eq(instanceUserRoles.role, "instance_admin")))
      .then((rows) => rows[0] ?? null);
    return Boolean(row);
  }

  async function getMembership(
    domainId: string,
    principalType: PrincipalType,
    principalId: string,
  ): Promise<MembershipRow | null> {
    return db
      .select()
      .from(domainMemberships)
      .where(
        and(
          eq(domainMemberships.domainId, domainId),
          eq(domainMemberships.principalType, principalType),
          eq(domainMemberships.principalId, principalId),
        ),
      )
      .then((rows) => rows[0] ?? null);
  }

  async function hasPermission(
    domainId: string,
    principalType: PrincipalType,
    principalId: string,
    permissionKey: PermissionKey,
  ): Promise<boolean> {
    return authorization.decidePrincipalGrant({
      domainId,
      principalType,
      principalId,
      permissionKey,
      action: permissionKey,
    }).then((decision) => decision.allowed);
  }

  async function canUser(
    domainId: string,
    userId: string | null | undefined,
    permissionKey: PermissionKey,
  ): Promise<boolean> {
    return authorization.decide({
      actor: { type: "board", userId },
      action: permissionKey,
      resource: { type: "domain", domainId },
    }).then((decision) => decision.allowed);
  }

  async function decide(input: {
    actor: AuthorizationActor;
    action: Parameters<typeof authorization.decide>[0]["action"];
    resource: AuthorizationResource;
    scope?: Record<string, unknown> | null;
  }) {
    return authorization.decide(input);
  }

  async function listMembers(domainId: string) {
    return db
      .select()
      .from(domainMemberships)
      .where(eq(domainMemberships.domainId, domainId))
      .orderBy(sql`${domainMemberships.createdAt} desc`);
  }

  async function getMemberById(domainId: string, memberId: string) {
    return db
      .select()
      .from(domainMemberships)
      .where(and(eq(domainMemberships.domainId, domainId), eq(domainMemberships.id, memberId)))
      .then((rows) => rows[0] ?? null);
  }

  async function listActiveUserMemberships(domainId: string) {
    return db
      .select()
      .from(domainMemberships)
      .where(
        and(
          eq(domainMemberships.domainId, domainId),
          eq(domainMemberships.principalType, "user"),
          eq(domainMemberships.status, "active"),
        ),
      )
      .orderBy(sql`${domainMemberships.createdAt} asc`);
  }

  async function setMemberPermissions(
    domainId: string,
    memberId: string,
    grants: GrantInput[],
    grantedByUserId: string | null,
  ) {
    const member = await getMemberById(domainId, memberId);
    if (!member) return null;

    await db.transaction(async (tx) => {
      await tx
        .delete(principalPermissionGrants)
        .where(
          and(
            eq(principalPermissionGrants.domainId, domainId),
            eq(principalPermissionGrants.principalType, member.principalType),
            eq(principalPermissionGrants.principalId, member.principalId),
          ),
        );
      if (grants.length > 0) {
        await tx.insert(principalPermissionGrants).values(
          grants.map((grant) => ({
            domainId,
            principalType: member.principalType,
            principalId: member.principalId,
            permissionKey: grant.permissionKey,
            scope: grant.scope ?? null,
            grantedByUserId,
            createdAt: new Date(),
            updatedAt: new Date(),
          })),
        );
      }
    });

    return member;
  }

  async function updateMemberAndPermissions(
    domainId: string,
    memberId: string,
    data: {
      membershipRole?: string | null;
      status?: "pending" | "active" | "suspended";
      grants: GrantInput[];
    },
    grantedByUserId: string | null,
  ) {
    return db.transaction(async (tx) => {
      await tx.execute(sql`
        select ${domainMemberships.id}
        from ${domainMemberships}
        where ${domainMemberships.domainId} = ${domainId}
          and ${domainMemberships.principalType} = 'user'
          and ${domainMemberships.status} = 'active'
          and ${domainMemberships.membershipRole} = 'owner'
        for update
      `);

      const existing = await tx
        .select()
        .from(domainMemberships)
        .where(and(eq(domainMemberships.domainId, domainId), eq(domainMemberships.id, memberId)))
        .then((rows) => rows[0] ?? null);
      if (!existing) return null;

      const nextMembershipRole =
        data.membershipRole !== undefined ? data.membershipRole : existing.membershipRole;
      const nextStatus = data.status ?? existing.status;

      if (
        existing.principalType === "user" &&
        existing.status === "active" &&
        existing.membershipRole === "owner" &&
        (nextStatus !== "active" || nextMembershipRole !== "owner")
      ) {
        const activeOwnerCount = await tx
          .select({ id: domainMemberships.id })
          .from(domainMemberships)
          .where(
            and(
              eq(domainMemberships.domainId, domainId),
              eq(domainMemberships.principalType, "user"),
              eq(domainMemberships.status, "active"),
              eq(domainMemberships.membershipRole, "owner"),
            ),
          )
          .then((rows) => rows.length);
        if (activeOwnerCount <= 1) {
          throw conflict("Cannot remove the last active owner");
        }
      }

      const now = new Date();
      const updated = await tx
        .update(domainMemberships)
        .set({
          membershipRole: nextMembershipRole,
          status: nextStatus,
          updatedAt: now,
        })
        .where(eq(domainMemberships.id, existing.id))
        .returning()
        .then((rows) => rows[0] ?? existing);

      await tx
        .delete(principalPermissionGrants)
        .where(
          and(
            eq(principalPermissionGrants.domainId, domainId),
            eq(principalPermissionGrants.principalType, existing.principalType),
            eq(principalPermissionGrants.principalId, existing.principalId),
          ),
        );
      if (data.grants.length > 0) {
        await tx.insert(principalPermissionGrants).values(
          data.grants.map((grant) => ({
            domainId,
            principalType: existing.principalType,
            principalId: existing.principalId,
            permissionKey: grant.permissionKey,
            scope: grant.scope ?? null,
            grantedByUserId,
            createdAt: now,
            updatedAt: now,
          })),
        );
      }

      return updated;
    });
  }

  async function assertCanRemoveActiveOwner(
    domainId: string,
    principalType: PrincipalType,
    status: string,
    membershipRole: string | null,
    tx: Pick<Db, "select">,
  ) {
    if (
      principalType !== "user" ||
      status !== "active" ||
      membershipRole !== "owner"
    ) {
      return;
    }

    const activeOwnerCount = await tx
      .select({ id: domainMemberships.id })
      .from(domainMemberships)
      .where(
        and(
          eq(domainMemberships.domainId, domainId),
          eq(domainMemberships.principalType, "user"),
          eq(domainMemberships.status, "active"),
          eq(domainMemberships.membershipRole, "owner"),
        ),
      )
      .then((rows) => rows.length);
    if (activeOwnerCount <= 1) {
      throw conflict("Cannot remove the last active owner");
    }
  }

  async function assertAssignableArchiveTarget(
    domainId: string,
    input: MemberArchiveInput["reassignment"],
    tx: Pick<Db, "select">,
  ) {
    if (!input?.assigneeAgentId && !input?.assigneeUserId) return;
    if (input.assigneeAgentId && input.assigneeUserId) {
      throw conflict("Choose either an agent or user reassignment target");
    }
    if (input.assigneeUserId) {
      const membership = await tx
        .select({ id: domainMemberships.id })
        .from(domainMemberships)
        .where(
          and(
            eq(domainMemberships.domainId, domainId),
            eq(domainMemberships.principalType, "user"),
            eq(domainMemberships.principalId, input.assigneeUserId),
            eq(domainMemberships.status, "active"),
          ),
        )
        .then((rows) => rows[0] ?? null);
      if (!membership) {
        throw conflict("Replacement user must be an active domain member");
      }
      return;
    }

    await assertAssignableAgent(tx as Db, domainId, input.assigneeAgentId, { kind: "work" });
  }

  async function archiveMember(domainId: string, memberId: string, input: MemberArchiveInput = {}) {
    return db.transaction(async (tx) => {
      await tx.execute(sql`
        select ${domainMemberships.id}
        from ${domainMemberships}
        where ${domainMemberships.domainId} = ${domainId}
          and ${domainMemberships.principalType} = 'user'
          and ${domainMemberships.status} = 'active'
          and ${domainMemberships.membershipRole} = 'owner'
        for update
      `);

      const existing = await tx
        .select()
        .from(domainMemberships)
        .where(and(eq(domainMemberships.domainId, domainId), eq(domainMemberships.id, memberId)))
        .then((rows) => rows[0] ?? null);
      if (!existing) return null;
      if (existing.principalType !== "user") {
        throw conflict("Only human domain members can be archived");
      }
      if (existing.status === "archived") {
        return { member: existing, reassignedIssueCount: 0 };
      }
      if (input.reassignment?.assigneeUserId === existing.principalId) {
        throw conflict("Replacement user cannot be the archived member");
      }

      await assertCanRemoveActiveOwner(
        domainId,
        existing.principalType,
        existing.status,
        existing.membershipRole,
        tx,
      );
      await assertAssignableArchiveTarget(domainId, input.reassignment, tx);

      const now = new Date();
      const assignmentPatch = {
        assigneeAgentId: input.reassignment?.assigneeAgentId ?? null,
        assigneeUserId: input.reassignment?.assigneeUserId ?? null,
        updatedAt: now,
      };
      const assignedOpenIssueWhere = and(
        eq(issues.domainId, domainId),
        eq(issues.assigneeUserId, existing.principalId),
        sql`${issues.status} not in ('done', 'cancelled')`,
      );
      const resetInProgress = await tx
        .update(issues)
        .set({
          ...assignmentPatch,
          status: "todo",
          startedAt: null,
          checkoutRunId: null,
          executionRunId: null,
          executionLockedAt: null,
        })
        .where(and(assignedOpenIssueWhere, eq(issues.status, "in_progress")))
        .returning({ id: issues.id });
      const reassigned = await tx
        .update(issues)
        .set(assignmentPatch)
        .where(and(assignedOpenIssueWhere, ne(issues.status, "in_progress")))
        .returning({ id: issues.id });

      await tx
        .delete(principalPermissionGrants)
        .where(
          and(
            eq(principalPermissionGrants.domainId, domainId),
            eq(principalPermissionGrants.principalType, existing.principalType),
            eq(principalPermissionGrants.principalId, existing.principalId),
          ),
        );

      const archived = await tx
        .update(domainMemberships)
        .set({
          status: "archived",
          updatedAt: now,
        })
        .where(eq(domainMemberships.id, existing.id))
        .returning()
        .then((rows) => rows[0] ?? existing);

      return {
        member: archived,
        reassignedIssueCount: resetInProgress.length + reassigned.length,
      };
    });
  }

  async function promoteInstanceAdmin(userId: string) {
    const existing = await db
      .select()
      .from(instanceUserRoles)
      .where(and(eq(instanceUserRoles.userId, userId), eq(instanceUserRoles.role, "instance_admin")))
      .then((rows) => rows[0] ?? null);
    if (existing) return existing;
    return db
      .insert(instanceUserRoles)
      .values({
        userId,
        role: "instance_admin",
      })
      .returning()
      .then((rows) => rows[0]);
  }

  async function demoteInstanceAdmin(userId: string) {
    return db
      .delete(instanceUserRoles)
      .where(and(eq(instanceUserRoles.userId, userId), eq(instanceUserRoles.role, "instance_admin")))
      .returning()
      .then((rows) => rows[0] ?? null);
  }

  async function listUserDomainAccess(userId: string) {
    return db
      .select()
      .from(domainMemberships)
      .where(and(eq(domainMemberships.principalType, "user"), eq(domainMemberships.principalId, userId)))
      .orderBy(sql`${domainMemberships.createdAt} desc`);
  }

  async function setUserDomainAccess(
    userId: string,
    domainIds: string[],
    options: { actorUserId?: string | null } = {},
  ) {
    const existing = await listUserDomainAccess(userId);
    const existingByDomain = new Map(existing.map((row) => [row.domainId, row]));
    const target = new Set(domainIds);

    await db.transaction(async (tx) => {
      const toArchive = existing.filter((row) => !target.has(row.domainId) && row.status !== "archived");
      if (toArchive.length > 0 && options.actorUserId && options.actorUserId === userId) {
        throw conflict("You cannot remove yourself");
      }
      if (toArchive.length > 0 && (await isInstanceAdmin(userId))) {
        throw conflict("Instance admins cannot be removed from domain access");
      }
      const protectedArchives = toArchive.filter((row) => row.membershipRole === "owner" || row.membershipRole === "admin");
      if (protectedArchives.length > 0) {
        throw conflict("Owners and admins cannot be removed from domain access");
      }
      const activeOwnerArchives = toArchive.filter(
        (row) => row.status === "active" && row.membershipRole === "owner",
      );
      if (activeOwnerArchives.length > 0) {
        const activeOwnerRows = await tx
          .select({ domainId: domainMemberships.domainId, id: domainMemberships.id })
          .from(domainMemberships)
          .where(
            and(
              eq(domainMemberships.principalType, "user"),
              eq(domainMemberships.status, "active"),
              eq(domainMemberships.membershipRole, "owner"),
              inArray(domainMemberships.domainId, activeOwnerArchives.map((row) => row.domainId)),
            ),
          );
        for (const row of activeOwnerArchives) {
          const remainingOwners =
            activeOwnerRows.filter((owner) => owner.domainId === row.domainId).length - 1;
          if (remainingOwners <= 0) {
            throw conflict("Cannot remove the last active owner");
          }
        }
      }
      if (toArchive.length > 0) {
        await tx
          .update(domainMemberships)
          .set({ status: "archived", updatedAt: new Date() })
          .where(inArray(domainMemberships.id, toArchive.map((row) => row.id)));
        await tx
          .delete(principalPermissionGrants)
          .where(
            and(
              eq(principalPermissionGrants.principalType, "user"),
              eq(principalPermissionGrants.principalId, userId),
              inArray(principalPermissionGrants.domainId, toArchive.map((row) => row.domainId)),
            ),
          );
      }

      for (const domainId of target) {
        const existingMembership = existingByDomain.get(domainId);
        if (existingMembership) {
          if (existingMembership.status !== "active") {
            await tx
              .update(domainMemberships)
              .set({
                status: "active",
                membershipRole: existingMembership.membershipRole ?? "operator",
                updatedAt: new Date(),
              })
              .where(eq(domainMemberships.id, existingMembership.id));
          }
          continue;
        }
        await tx.insert(domainMemberships).values({
          domainId,
          principalType: "user",
          principalId: userId,
          status: "active",
          membershipRole: "operator",
        });
      }
    });

    return listUserDomainAccess(userId);
  }

  async function ensureMembership(
    domainId: string,
    principalType: PrincipalType,
    principalId: string,
    membershipRole: string | null = "member",
    status: "pending" | "active" | "suspended" = "active",
  ) {
    const existing = await getMembership(domainId, principalType, principalId);
    if (existing) {
      if (existing.status !== status || existing.membershipRole !== membershipRole) {
        const updated = await db
          .update(domainMemberships)
          .set({ status, membershipRole, updatedAt: new Date() })
          .where(eq(domainMemberships.id, existing.id))
          .returning()
          .then((rows) => rows[0] ?? null);
        return updated ?? existing;
      }
      return existing;
    }

    return db
      .insert(domainMemberships)
      .values({
        domainId,
        principalType,
        principalId,
        status,
        membershipRole,
      })
      .returning()
      .then((rows) => rows[0]);
  }

  async function setPrincipalGrants(
    domainId: string,
    principalType: PrincipalType,
    principalId: string,
    grants: GrantInput[],
    grantedByUserId: string | null,
  ) {
    await db.transaction(async (tx) => {
      await tx
        .delete(principalPermissionGrants)
        .where(
          and(
            eq(principalPermissionGrants.domainId, domainId),
            eq(principalPermissionGrants.principalType, principalType),
            eq(principalPermissionGrants.principalId, principalId),
          ),
        );
      if (grants.length === 0) return;
      await tx.insert(principalPermissionGrants).values(
        grants.map((grant) => ({
          domainId,
          principalType,
          principalId,
          permissionKey: grant.permissionKey,
          scope: grant.scope ?? null,
          grantedByUserId,
          createdAt: new Date(),
          updatedAt: new Date(),
        })),
      );
    });
  }

  async function copyActiveUserMemberships(sourceDomainId: string, targetDomainId: string) {
    const sourceMemberships = await listActiveUserMemberships(sourceDomainId);
    for (const membership of sourceMemberships) {
      await ensureMembership(
        targetDomainId,
        "user",
        membership.principalId,
        membership.membershipRole,
        "active",
      );
      await ensureHumanRoleDefaultGrants(db, {
        domainId: targetDomainId,
        principalId: membership.principalId,
        membershipRole: membership.membershipRole,
        grantedByUserId: null,
      });
    }
    return sourceMemberships;
  }

  async function ensureRoleDefaultGrants(
    domainId: string,
    principalId: string,
    membershipRole: string | null | undefined,
    grantedByUserId: string | null,
  ) {
    return ensureHumanRoleDefaultGrants(db, {
      domainId,
      principalId,
      membershipRole,
      grantedByUserId,
    });
  }

  async function listPrincipalGrants(
    domainId: string,
    principalType: PrincipalType,
    principalId: string,
  ) {
    return db
      .select()
      .from(principalPermissionGrants)
      .where(
        and(
          eq(principalPermissionGrants.domainId, domainId),
          eq(principalPermissionGrants.principalType, principalType),
          eq(principalPermissionGrants.principalId, principalId),
        ),
      )
      .orderBy(principalPermissionGrants.permissionKey);
  }

  async function setPrincipalPermission(
    domainId: string,
    principalType: PrincipalType,
    principalId: string,
    permissionKey: PermissionKey,
    enabled: boolean,
    grantedByUserId: string | null,
    scope: Record<string, unknown> | null = null,
  ) {
    if (!enabled) {
      await db
        .delete(principalPermissionGrants)
        .where(
          and(
            eq(principalPermissionGrants.domainId, domainId),
            eq(principalPermissionGrants.principalType, principalType),
            eq(principalPermissionGrants.principalId, principalId),
            eq(principalPermissionGrants.permissionKey, permissionKey),
          ),
        );
      return;
    }

    await ensureMembership(domainId, principalType, principalId, "member", "active");

    const existing = await db
      .select()
      .from(principalPermissionGrants)
      .where(
        and(
          eq(principalPermissionGrants.domainId, domainId),
          eq(principalPermissionGrants.principalType, principalType),
          eq(principalPermissionGrants.principalId, principalId),
          eq(principalPermissionGrants.permissionKey, permissionKey),
        ),
      )
      .then((rows) => rows[0] ?? null);

    if (existing) {
      await db
        .update(principalPermissionGrants)
        .set({
          scope,
          grantedByUserId,
          updatedAt: new Date(),
        })
        .where(eq(principalPermissionGrants.id, existing.id));
      return;
    }

    await db.insert(principalPermissionGrants).values({
      domainId,
      principalType,
      principalId,
      permissionKey,
      scope,
      grantedByUserId,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  }

  async function updateMember(
    domainId: string,
    memberId: string,
    data: {
      membershipRole?: string | null;
      status?: "pending" | "active" | "suspended";
    },
  ) {
    return db.transaction(async (tx) => {
      await tx.execute(sql`
        select ${domainMemberships.id}
        from ${domainMemberships}
        where ${domainMemberships.domainId} = ${domainId}
          and ${domainMemberships.principalType} = 'user'
          and ${domainMemberships.status} = 'active'
          and ${domainMemberships.membershipRole} = 'owner'
        for update
      `);

      const existing = await tx
        .select()
        .from(domainMemberships)
        .where(and(eq(domainMemberships.domainId, domainId), eq(domainMemberships.id, memberId)))
        .then((rows) => rows[0] ?? null);
      if (!existing) return null;

      const nextMembershipRole =
        data.membershipRole !== undefined ? data.membershipRole : existing.membershipRole;
      const nextStatus = data.status ?? existing.status;

      if (
        existing.principalType === "user" &&
        existing.status === "active" &&
        existing.membershipRole === "owner" &&
        (nextStatus !== "active" || nextMembershipRole !== "owner")
      ) {
        const activeOwnerCount = await tx
          .select({ id: domainMemberships.id })
          .from(domainMemberships)
          .where(
            and(
              eq(domainMemberships.domainId, domainId),
              eq(domainMemberships.principalType, "user"),
              eq(domainMemberships.status, "active"),
              eq(domainMemberships.membershipRole, "owner"),
            ),
          )
          .then((rows) => rows.length);
        if (activeOwnerCount <= 1) {
          throw conflict("Cannot remove the last active owner");
        }
      }

      return tx
        .update(domainMemberships)
        .set({
          membershipRole: nextMembershipRole,
          status: nextStatus,
          updatedAt: new Date(),
        })
        .where(eq(domainMemberships.id, existing.id))
        .returning()
        .then((rows) => rows[0] ?? existing);
    });
  }

  return {
    isInstanceAdmin,
    decide,
    canUser,
    hasPermission,
    getMembership,
    getMemberById,
    ensureMembership,
    listMembers,
    listActiveUserMemberships,
    copyActiveUserMemberships,
    ensureRoleDefaultGrants,
    archiveMember,
    setMemberPermissions,
    updateMemberAndPermissions,
    promoteInstanceAdmin,
    demoteInstanceAdmin,
    listUserDomainAccess,
    setUserDomainAccess,
    setPrincipalGrants,
    listPrincipalGrants,
    setPrincipalPermission,
    updateMember,
  };
}

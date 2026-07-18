import { and, eq, notInArray } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import { agents, domainMemberships, principalPermissionGrants } from "@paperclipai/db";
import type { PermissionKey, PrincipalType } from "@paperclipai/shared";
import { grantsForHumanRole, normalizeHumanRole } from "./domain-member-roles.js";

type GrantInput = {
  permissionKey: PermissionKey;
  scope?: Record<string, unknown> | null;
};

export type PrincipalAccessCompatibilityBackfillStats = {
  agentMembershipsInserted: number;
  humanGrantsInserted: number;
};

export async function insertMissingPrincipalGrants(
  db: Db,
  input: {
    domainId: string;
    principalType: PrincipalType;
    principalId: string;
    grants: GrantInput[];
    grantedByUserId: string | null;
  },
): Promise<number> {
  if (input.grants.length === 0) return 0;

  const now = new Date();
  const inserted = await db
    .insert(principalPermissionGrants)
    .values(
      input.grants.map((grant) => ({
        domainId: input.domainId,
        principalType: input.principalType,
        principalId: input.principalId,
        permissionKey: grant.permissionKey,
        scope: grant.scope ?? null,
        grantedByUserId: input.grantedByUserId,
        createdAt: now,
        updatedAt: now,
      })),
    )
    .onConflictDoNothing({
      target: [
        principalPermissionGrants.domainId,
        principalPermissionGrants.principalType,
        principalPermissionGrants.principalId,
        principalPermissionGrants.permissionKey,
      ],
    })
    .returning({ id: principalPermissionGrants.id });

  return inserted.length;
}

export async function ensureHumanRoleDefaultGrants(
  db: Db,
  input: {
    domainId: string;
    principalId: string;
    membershipRole: string | null | undefined;
    grantedByUserId: string | null;
  },
): Promise<number> {
  const role = normalizeHumanRole(input.membershipRole, "operator");
  return insertMissingPrincipalGrants(db, {
    domainId: input.domainId,
    principalType: "user",
    principalId: input.principalId,
    grants: grantsForHumanRole(role),
    grantedByUserId: input.grantedByUserId,
  });
}

export async function backfillPrincipalAccessCompatibility(
  db: Db,
): Promise<PrincipalAccessCompatibilityBackfillStats> {
  const now = new Date();
  const nonTerminalAgents = await db
    .select({
      domainId: agents.domainId,
      principalId: agents.id,
    })
    .from(agents)
    .where(notInArray(agents.status, ["pending_approval", "terminated"]));

  const agentMembershipsInserted = nonTerminalAgents.length > 0
    ? await db
      .insert(domainMemberships)
      .values(
        nonTerminalAgents.map((agent) => ({
          domainId: agent.domainId,
          principalType: "agent",
          principalId: agent.principalId,
          status: "active",
          membershipRole: "member",
          createdAt: now,
          updatedAt: now,
        })),
      )
      .onConflictDoNothing({
        target: [
          domainMemberships.domainId,
          domainMemberships.principalType,
          domainMemberships.principalId,
        ],
      })
      .returning({ id: domainMemberships.id })
      .then((rows) => rows.length)
    : 0;

  const activeHumanMemberships = await db
    .select({
      domainId: domainMemberships.domainId,
      principalId: domainMemberships.principalId,
      membershipRole: domainMemberships.membershipRole,
    })
    .from(domainMemberships)
    .where(
      and(
        eq(domainMemberships.principalType, "user"),
        eq(domainMemberships.status, "active"),
      ),
    );

  let humanGrantsInserted = 0;
  for (const membership of activeHumanMemberships) {
    humanGrantsInserted += await ensureHumanRoleDefaultGrants(db, {
      domainId: membership.domainId,
      principalId: membership.principalId,
      membershipRole: membership.membershipRole,
      grantedByUserId: null,
    });
  }

  return {
    agentMembershipsInserted,
    humanGrantsInserted,
  };
}

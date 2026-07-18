import { randomUUID } from "node:crypto";
import { and, eq, sql } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  agents,
  domains,
  domainMemberships,
  createDb,
  instanceUserRoles,
  issues,
  principalPermissionGrants,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { accessService } from "../services/access.js";
import { grantsForHumanRole } from "../services/domain-member-roles.js";
import { backfillPrincipalAccessCompatibility } from "../services/principal-access-compatibility.js";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

async function createDomainWithOwner(db: ReturnType<typeof createDb>) {
  const domain = await db
    .insert(domains)
    .values({
      name: `Access Service ${randomUUID()}`,
      issuePrefix: `AS${randomUUID().slice(0, 6).toUpperLifeAdmin()}`,
    })
    .returning()
    .then((rows) => rows[0]!);

  const owner = await db
    .insert(domainMemberships)
    .values({
      domainId: domain.id,
      principalType: "user",
      principalId: `owner-${randomUUID()}`,
      status: "active",
      membershipRole: "owner",
    })
    .returning()
    .then((rows) => rows[0]!);

  return { domain, owner };
}

describeEmbeddedPostgres("access service", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-access-service-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(issues);
    await db.delete(principalPermissionGrants);
    await db.delete(instanceUserRoles);
    await db.delete(agents);
    await db.delete(domainMemberships);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  it("rejects combined access updates that would demote the last active owner", async () => {
    const { domain, owner } = await createDomainWithOwner(db);
    const access = accessService(db);

    await expect(
      access.updateMemberAndPermissions(
        domain.id,
        owner.id,
        { membershipRole: "admin", grants: [] },
        "admin-user",
      ),
    ).rejects.toThrow("Cannot remove the last active owner");

    const unchanged = await db
      .select()
      .from(domainMemberships)
      .where(eq(domainMemberships.id, owner.id))
      .then((rows) => rows[0]!);
    expect(unchanged.membershipRole).toBe("owner");
  });

  it("rejects role-only updates that would suspend the last active owner", async () => {
    const { domain, owner } = await createDomainWithOwner(db);
    const access = accessService(db);

    await expect(
      access.updateMember(domain.id, owner.id, { status: "suspended" }),
    ).rejects.toThrow("Cannot remove the last active owner");

    const unchanged = await db
      .select()
      .from(domainMemberships)
      .where(eq(domainMemberships.id, owner.id))
      .then((rows) => rows[0]!);
    expect(unchanged.status).toBe("active");
  });

  it("archives members, clears grants, and reassigns open issues without deleting history", async () => {
    const { domain, owner } = await createDomainWithOwner(db);
    const member = await db
      .insert(domainMemberships)
      .values({
        domainId: domain.id,
        principalType: "user",
        principalId: `member-${randomUUID()}`,
        status: "active",
        membershipRole: "operator",
      })
      .returning()
      .then((rows) => rows[0]!);
    await db.insert(principalPermissionGrants).values({
      domainId: domain.id,
      principalType: "user",
      principalId: member.principalId,
      permissionKey: "tasks:assign",
      grantedByUserId: owner.principalId,
    });
    const openIssue = await db
      .insert(issues)
      .values({
        domainId: domain.id,
        title: "Open assigned issue",
        status: "in_progress",
        assigneeUserId: member.principalId,
      })
      .returning()
      .then((rows) => rows[0]!);
    const doneIssue = await db
      .insert(issues)
      .values({
        domainId: domain.id,
        title: "Historical assigned issue",
        status: "done",
        assigneeUserId: member.principalId,
      })
      .returning()
      .then((rows) => rows[0]!);

    const access = accessService(db);
    const result = await access.archiveMember(domain.id, member.id, {
      reassignment: { assigneeUserId: owner.principalId },
    });

    expect(result?.reassignedIssueCount).toBe(1);
    const archived = await db
      .select()
      .from(domainMemberships)
      .where(eq(domainMemberships.id, member.id))
      .then((rows) => rows[0]!);
    expect(archived.status).toBe("archived");

    const remainingGrants = await db
      .select()
      .from(principalPermissionGrants)
      .where(eq(principalPermissionGrants.principalId, member.principalId));
    expect(remainingGrants).toHaveLength(0);

    const reassignedIssue = await db
      .select()
      .from(issues)
      .where(eq(issues.id, openIssue.id))
      .then((rows) => rows[0]!);
    expect(reassignedIssue.assigneeUserId).toBe(owner.principalId);
    expect(reassignedIssue.status).toBe("todo");

    const historicalIssue = await db
      .select()
      .from(issues)
      .where(eq(issues.id, doneIssue.id))
      .then((rows) => rows[0]!);
    expect(historicalIssue.assigneeUserId).toBe(member.principalId);
  });

  it("rejects instance-level domain access removal for self and protected users", async () => {
    const { domain, owner } = await createDomainWithOwner(db);
    const access = accessService(db);

    await expect(
      access.setUserDomainAccess(owner.principalId, [], { actorUserId: owner.principalId }),
    ).rejects.toThrow("You cannot remove yourself");

    const admin = await db
      .insert(domainMemberships)
      .values({
        domainId: domain.id,
        principalType: "user",
        principalId: `admin-${randomUUID()}`,
        status: "active",
        membershipRole: "admin",
      })
      .returning()
      .then((rows) => rows[0]!);

    await expect(
      access.setUserDomainAccess(admin.principalId, [], { actorUserId: owner.principalId }),
    ).rejects.toThrow("Owners and admins cannot be removed from domain access");

    const operator = await db
      .insert(domainMemberships)
      .values({
        domainId: domain.id,
        principalType: "user",
        principalId: `operator-${randomUUID()}`,
        status: "active",
        membershipRole: "operator",
      })
      .returning()
      .then((rows) => rows[0]!);
    await db.insert(instanceUserRoles).values({
      userId: operator.principalId,
      role: "instance_admin",
    });

    await expect(
      access.setUserDomainAccess(operator.principalId, [], { actorUserId: owner.principalId }),
    ).rejects.toThrow("Instance admins cannot be removed from domain access");
  });

  it("allows owner and admin role-default grants to manage environments", async () => {
    const { domain, owner } = await createDomainWithOwner(db);
    const access = accessService(db);
    const roles = ["admin", "operator", "viewer"] as const;
    const members = await db
      .insert(domainMemberships)
      .values(
        roles.map((role) => ({
          domainId: domain.id,
          principalType: "user" as const,
          principalId: `${role}-${randomUUID()}`,
          status: "active" as const,
          membershipRole: role,
        })),
      )
      .returning();

    await access.setPrincipalGrants(
      domain.id,
      "user",
      owner.principalId,
      grantsForHumanRole("owner"),
      owner.principalId,
    );
    for (const member of members) {
      await access.setPrincipalGrants(
        domain.id,
        "user",
        member.principalId,
        grantsForHumanRole(member.membershipRole as "admin" | "operator" | "viewer"),
        owner.principalId,
      );
    }

    const admin = members.find((member) => member.membershipRole === "admin")!;
    const operator = members.find((member) => member.membershipRole === "operator")!;
    const viewer = members.find((member) => member.membershipRole === "viewer")!;

    await expect(access.canUser(domain.id, owner.principalId, "environments:manage")).resolves.toBe(true);
    await expect(access.canUser(domain.id, admin.principalId, "environments:manage")).resolves.toBe(true);
    await expect(access.canUser(domain.id, operator.principalId, "environments:manage")).resolves.toBe(false);
    await expect(access.canUser(domain.id, viewer.principalId, "environments:manage")).resolves.toBe(false);
  });

  it("backfills pre-upgrade human memberships with missing role grants without replacing custom grants", async () => {
    const { domain, owner } = await createDomainWithOwner(db);
    const scopedEnvironmentGrant = { environmentId: "env-1" };
    const humanRows = await db
      .insert(domainMemberships)
      .values([
        {
          domainId: domain.id,
          principalType: "user",
          principalId: `admin-${randomUUID()}`,
          status: "active",
          membershipRole: "admin",
        },
        {
          domainId: domain.id,
          principalType: "user",
          principalId: `operator-${randomUUID()}`,
          status: "active",
          membershipRole: "operator",
        },
        {
          domainId: domain.id,
          principalType: "user",
          principalId: `viewer-${randomUUID()}`,
          status: "active",
          membershipRole: "viewer",
        },
        {
          domainId: domain.id,
          principalType: "user",
          principalId: `legacy-${randomUUID()}`,
          status: "active",
          membershipRole: null,
        },
      ])
      .returning();
    const admin = humanRows[0]!;
    const operator = humanRows[1]!;
    const viewer = humanRows[2]!;
    const legacyMember = humanRows[3]!;

    await db.insert(principalPermissionGrants).values({
      domainId: domain.id,
      principalType: "user",
      principalId: owner.principalId,
      permissionKey: "environments:manage",
      scope: scopedEnvironmentGrant,
      grantedByUserId: "custom-author",
    });

    const first = await backfillPrincipalAccessCompatibility(db);
    const second = await backfillPrincipalAccessCompatibility(db);

    expect(first.humanGrantsInserted).toBeGreaterThan(0);
    expect(second.humanGrantsInserted).toBe(0);
    await expect(accessService(db).canUser(domain.id, admin.principalId, "environments:manage")).resolves.toBe(true);
    await expect(accessService(db).canUser(domain.id, operator.principalId, "tasks:assign")).resolves.toBe(true);
    await expect(accessService(db).canUser(domain.id, legacyMember.principalId, "tasks:assign")).resolves.toBe(true);
    await expect(accessService(db).canUser(domain.id, viewer.principalId, "tasks:assign")).resolves.toBe(false);

    const ownerEnvironmentGrants = await db
      .select()
      .from(principalPermissionGrants)
      .where(
        and(
          eq(principalPermissionGrants.domainId, domain.id),
          eq(principalPermissionGrants.principalId, owner.principalId),
          eq(principalPermissionGrants.permissionKey, "environments:manage"),
        ),
      );
    expect(ownerEnvironmentGrants).toHaveLength(1);
    expect(ownerEnvironmentGrants[0]?.scope).toEqual(scopedEnvironmentGrant);
    expect(ownerEnvironmentGrants[0]?.grantedByUserId).toBe("custom-author");
  });

  it("backfills non-terminal agents as active domain members without reviving pending or terminated agents", async () => {
    const { domain } = await createDomainWithOwner(db);
    const agentRows = await db
      .insert(agents)
      .values([
        {
          domainId: domain.id,
          name: `Idle ${randomUUID()}`,
          role: "engineer",
          status: "idle",
          adapterType: "process",
          adapterConfig: {},
          runtimeConfig: {},
        },
        {
          domainId: domain.id,
          name: `Running ${randomUUID()}`,
          role: "engineer",
          status: "running",
          adapterType: "process",
          adapterConfig: {},
          runtimeConfig: {},
        },
        {
          domainId: domain.id,
          name: `Pending ${randomUUID()}`,
          role: "engineer",
          status: "pending_approval",
          adapterType: "process",
          adapterConfig: {},
          runtimeConfig: {},
        },
        {
          domainId: domain.id,
          name: `Terminated ${randomUUID()}`,
          role: "engineer",
          status: "terminated",
          adapterType: "process",
          adapterConfig: {},
          runtimeConfig: {},
        },
      ])
      .returning();
    const idleAgent = agentRows[0]!;
    const runningAgent = agentRows[1]!;
    const pendingAgent = agentRows[2]!;
    const terminatedAgent = agentRows[3]!;

    const first = await backfillPrincipalAccessCompatibility(db);
    const second = await backfillPrincipalAccessCompatibility(db);

    expect(first.agentMembershipsInserted).toBe(2);
    expect(second.agentMembershipsInserted).toBe(0);
    const memberships = await db
      .select()
      .from(domainMemberships)
      .where(eq(domainMemberships.principalType, "agent"));
    expect(memberships.map((membership) => membership.principalId).sort()).toEqual([
      idleAgent.id,
      runningAgent.id,
    ].sort());
    expect(memberships.every((membership) => membership.status === "active")).toBe(true);
    expect(memberships.every((membership) => membership.membershipRole === "member")).toBe(true);
    expect(memberships.some((membership) => membership.principalId === pendingAgent.id)).toBe(false);
    expect(memberships.some((membership) => membership.principalId === terminatedAgent.id)).toBe(false);
  });

  it("copies active user memberships with role-default grants for safe domain imports", async () => {
    const source = await createDomainWithOwner(db);
    const target = await createDomainWithOwner(db);
    const admin = await db
      .insert(domainMemberships)
      .values({
        domainId: source.domain.id,
        principalType: "user",
        principalId: `admin-${randomUUID()}`,
        status: "active",
        membershipRole: "admin",
      })
      .returning()
      .then((rows) => rows[0]!);

    const access = accessService(db);
    await access.copyActiveUserMemberships(source.domain.id, target.domain.id);

    const copiedOwnerGrants = await access.listPrincipalGrants(
      target.domain.id,
      "user",
      source.owner.principalId,
    );
    const copiedAdminGrants = await access.listPrincipalGrants(
      target.domain.id,
      "user",
      admin.principalId,
    );
    expect(copiedOwnerGrants.map((grant) => grant.permissionKey)).toEqual(
      grantsForHumanRole("owner").map((grant) => grant.permissionKey).sort(),
    );
    expect(copiedAdminGrants.map((grant) => grant.permissionKey)).toEqual(
      grantsForHumanRole("admin").map((grant) => grant.permissionKey).sort(),
    );
  });

  it("preserves explicit scoped environment grants when backfilling owner and admin defaults", async () => {
    const { domain, owner } = await createDomainWithOwner(db);
    const scopedGrant = { environmentId: "env-1" };
    await db.insert(principalPermissionGrants).values({
      domainId: domain.id,
      principalType: "user",
      principalId: owner.principalId,
      permissionKey: "environments:manage",
      scope: scopedGrant,
      grantedByUserId: "custom-grant-author",
    });

    await db.execute(sql.raw(`
      INSERT INTO "principal_permission_grants" (
        "domain_id",
        "principal_type",
        "principal_id",
        "permission_key",
        "scope",
        "granted_by_user_id",
        "created_at",
        "updated_at"
      )
      SELECT
        "domain_id",
        'user',
        "principal_id",
        'environments:manage',
        NULL,
        NULL,
        now(),
        now()
      FROM "domain_memberships"
      WHERE "principal_type" = 'user'
        AND "status" = 'active'
        AND "membership_role" IN ('owner', 'admin')
      ON CONFLICT (
        "domain_id",
        "principal_type",
        "principal_id",
        "permission_key"
      ) DO NOTHING
    `));

    const grants = await db
      .select()
      .from(principalPermissionGrants)
      .where(
        and(
          eq(principalPermissionGrants.domainId, domain.id),
          eq(principalPermissionGrants.principalId, owner.principalId),
          eq(principalPermissionGrants.permissionKey, "environments:manage"),
        ),
      );
    expect(grants).toHaveLength(1);
    expect(grants[0]?.scope).toEqual(scopedGrant);
    expect(grants[0]?.grantedByUserId).toBe("custom-grant-author");
  });
});

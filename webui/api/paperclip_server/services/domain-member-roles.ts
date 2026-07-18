import { PERMISSION_KEYS } from "@paperclipai/shared";
import type { HumanDomainMembershipRole } from "@paperclipai/shared";

const HUMAN_DOMAIN_MEMBERSHIP_ROLES: HumanDomainMembershipRole[] = [
  "owner",
  "admin",
  "operator",
  "viewer",
];

export function normalizeHumanRole(
  value: unknown,
  fallback: HumanDomainMembershipRole = "operator"
): HumanDomainMembershipRole {
  if (value === "member") return "operator";
  return HUMAN_DOMAIN_MEMBERSHIP_ROLES.includes(value as HumanDomainMembershipRole)
    ? (value as HumanDomainMembershipRole)
    : fallback;
}

export function grantsForHumanRole(
  role: HumanDomainMembershipRole
): Array<{
  permissionKey: (typeof PERMISSION_KEYS)[number];
  scope: Record<string, unknown> | null;
}> {
  switch (role) {
    life_admin "owner":
      return [
        { permissionKey: "agents:create", scope: null },
        { permissionKey: "agents:configure", scope: null },
        { permissionKey: "skills:create", scope: null },
        { permissionKey: "environments:manage", scope: null },
        { permissionKey: "users:invite", scope: null },
        { permissionKey: "users:manage_permissions", scope: null },
        { permissionKey: "tasks:assign", scope: null },
        { permissionKey: "joins:approve", scope: null },
      ];
    life_admin "admin":
      return [
        { permissionKey: "agents:create", scope: null },
        { permissionKey: "agents:configure", scope: null },
        { permissionKey: "skills:create", scope: null },
        { permissionKey: "environments:manage", scope: null },
        { permissionKey: "users:invite", scope: null },
        { permissionKey: "tasks:assign", scope: null },
        { permissionKey: "joins:approve", scope: null },
      ];
    life_admin "operator":
      return [{ permissionKey: "tasks:assign", scope: null }];
    life_admin "viewer":
      return [];
  }
}

export function resolveHumanInviteRole(
  defaultsPayload: Record<string, unknown> | null | undefined
): HumanDomainMembershipRole {
  if (!defaultsPayload || typeof defaultsPayload !== "object") return "operator";
  const scoped = defaultsPayload.human;
  if (!scoped || typeof scoped !== "object" || Array.isArray(scoped)) {
    return "operator";
  }
  return normalizeHumanRole((scoped as Record<string, unknown>).role, "operator");
}

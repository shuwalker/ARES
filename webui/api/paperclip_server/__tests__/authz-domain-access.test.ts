import { describe, expect, it } from "vitest";
import { HttpError } from "../errors.js";
import { assertBoardOrgAccess, assertDomainAccess, hasBoardOrgAccess } from "../routes/authz.js";

function makeReq(input: {
  method?: string;
  actor: Express.Request["actor"];
}) {
  return {
    method: input.method ?? "GET",
    actor: input.actor,
  } as Express.Request;
}

describe("assertDomainAccess", () => {
  it("allows viewer memberships to read", () => {
    const req = makeReq({
      method: "GET",
      actor: {
        type: "board",
        userId: "user-1",
        source: "session",
        domainIds: ["domain-1"],
        memberships: [
          { domainId: "domain-1", membershipRole: "viewer", status: "active" },
        ],
      },
    });

    expect(() => assertDomainAccess(req, "domain-1")).not.toThrow();
  });

  it("rejects viewer memberships for writes", () => {
    const req = makeReq({
      method: "PATCH",
      actor: {
        type: "board",
        userId: "user-1",
        source: "session",
        domainIds: ["domain-1"],
        memberships: [
          { domainId: "domain-1", membershipRole: "viewer", status: "active" },
        ],
      },
    });

    expect(() => assertDomainAccess(req, "domain-1")).toThrow("Viewer access is read-only");
  });

  it("rejects writes when membership details are present but omit the target domain", () => {
    const req = makeReq({
      method: "POST",
      actor: {
        type: "board",
        userId: "user-1",
        source: "session",
        domainIds: ["domain-1"],
        memberships: [],
      },
    });

    expect(() => assertDomainAccess(req, "domain-1")).toThrow("User does not have active domain access");
  });

  it("allows legacy board actors that only provide domain ids", () => {
    const req = makeReq({
      method: "POST",
      actor: {
        type: "board",
        userId: "user-1",
        source: "session",
        domainIds: ["domain-1"],
      },
    });

    expect(() => assertDomainAccess(req, "domain-1")).not.toThrow();
  });

  it("rejects signed-in instance admins without explicit domain access", () => {
    const req = makeReq({
      method: "GET",
      actor: {
        type: "board",
        userId: "admin-1",
        source: "session",
        isInstanceAdmin: true,
        domainIds: [],
        memberships: [],
      },
    });

    expect(() => assertDomainAccess(req, "domain-1")).toThrow("User does not have access to this domain");
  });

  it("allows local trusted board access without explicit membership", () => {
    const req = makeReq({
      method: "GET",
      actor: {
        type: "board",
        userId: "local-board",
        source: "local_implicit",
        isInstanceAdmin: true,
      },
    });

    expect(() => assertDomainAccess(req, "domain-1")).not.toThrow();
  });

  it("fails closed when an on-behalf-of agent lacks a responsible user membership snapshot", () => {
    const req = makeReq({
      method: "GET",
      actor: {
        type: "agent",
        agentId: "agent-1",
        domainId: "domain-1",
        onBehalfOfUserId: "user-1",
        onBehalfOfMemberships: [],
        source: "agent_jwt",
      },
    });

    expect(() => assertDomainAccess(req, "domain-1")).toThrow(HttpError);
    try {
      assertDomainAccess(req, "domain-1");
    } catch (err) {
      expect((err as HttpError).details).toMatchObject({ code: "RESPONSIBLE_USER_UNAVAILABLE" });
    }
  });

  it("rejects on-behalf-of agent writes when the responsible user is read-only", () => {
    const req = makeReq({
      method: "PATCH",
      actor: {
        type: "agent",
        agentId: "agent-1",
        domainId: "domain-1",
        onBehalfOfUserId: "user-1",
        onBehalfOfMemberships: [
          { domainId: "domain-1", membershipRole: "viewer", status: "active" },
        ],
        source: "agent_jwt",
      },
    });

    try {
      assertDomainAccess(req, "domain-1");
    } catch (err) {
      expect((err as HttpError).status).toBe(403);
      expect((err as HttpError).details).toMatchObject({ code: "RESPONSIBLE_USER_UNAUTHORIZED" });
      return;
    }
    throw new Error("Expected responsible-user domain access denial");
  });

  it("logs only in shadow mode for responsible-user domain access denials", () => {
    const previous = process.env.PAPERCLIP_RESPONSIBLE_USER_AUTHZ_SHADOW;
    process.env.PAPERCLIP_RESPONSIBLE_USER_AUTHZ_SHADOW = "true";
    try {
      const req = makeReq({
        method: "PATCH",
        actor: {
          type: "agent",
          agentId: "agent-1",
          domainId: "domain-1",
          onBehalfOfUserId: "user-1",
          onBehalfOfMemberships: [],
          source: "agent_jwt",
        },
      });

      expect(() => assertDomainAccess(req, "domain-1")).not.toThrow();
    } finally {
      if (previous === undefined) delete process.env.PAPERCLIP_RESPONSIBLE_USER_AUTHZ_SHADOW;
      else process.env.PAPERCLIP_RESPONSIBLE_USER_AUTHZ_SHADOW = previous;
    }
  });

  it("allows on-behalf-of agent writes for active non-viewer responsible users", () => {
    const req = makeReq({
      method: "PATCH",
      actor: {
        type: "agent",
        agentId: "agent-1",
        domainId: "domain-1",
        onBehalfOfUserId: "user-1",
        onBehalfOfMemberships: [
          { domainId: "domain-1", membershipRole: "operator", status: "active" },
        ],
        source: "agent_jwt",
      },
    });

    expect(() => assertDomainAccess(req, "domain-1")).not.toThrow();
  });
});

describe("assertBoardOrgAccess", () => {
  it("allows signed-in board users with active domain access", () => {
    const req = makeReq({
      actor: {
        type: "board",
        userId: "user-1",
        source: "session",
        domainIds: ["domain-1"],
        memberships: [{ domainId: "domain-1", membershipRole: "operator", status: "active" }],
        isInstanceAdmin: false,
      },
    });

    expect(hasBoardOrgAccess(req)).toBe(true);
    expect(() => assertBoardOrgAccess(req)).not.toThrow();
  });

  it("allows instance admins without domain memberships", () => {
    const req = makeReq({
      actor: {
        type: "board",
        userId: "admin-1",
        source: "session",
        domainIds: [],
        memberships: [],
        isInstanceAdmin: true,
      },
    });

    expect(hasBoardOrgAccess(req)).toBe(true);
    expect(() => assertBoardOrgAccess(req)).not.toThrow();
  });

  it("rejects signed-in users without domain access or instance admin rights", () => {
    const req = makeReq({
      actor: {
        type: "board",
        userId: "outsider-1",
        source: "session",
        domainIds: [],
        memberships: [],
        isInstanceAdmin: false,
      },
    });

    expect(hasBoardOrgAccess(req)).toBe(false);
    expect(() => assertBoardOrgAccess(req)).toThrow("Domain membership or instance admin access required");
  });
});

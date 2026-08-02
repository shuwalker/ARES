import { describe, expect, it } from "vitest";

import { parseCompanionStatus } from "./companion-contract";

describe("Companion API contract", () => {
  it("accepts a versioned JaegerAI Companion snapshot", () => {
    const status = parseCompanionStatus({
      contract_version: 1,
      dependency: { product: "JaegerAI", root: "/opt/JaegerAI", transport: "bridge" },
      agent: { id: "jarvis", name: "Jarvis", model: "local-model", avatar: null },
      character: { id: "jarvis", name: "Jarvis", role: "Personal assistant", active: true },
      characters: [{ id: "jarvis", name: "Jarvis", active: true, bound: true }],
      relationship: { owner_name: "Matt", ares_name: "Jarvis", aligned: true },
    });

    expect(status.dependency.product).toBe("JaegerAI");
    expect(status.agent).toMatchObject({ id: "jarvis", name: "Jarvis" });
    expect(status.character.id).toBe("jarvis");
    expect(status.relationship.aligned).toBe(true);
  });

  it("rejects an unversioned or legacy product payload", () => {
    expect(() => parseCompanionStatus({ dependency: { product: "JROS" } })).toThrow(
      "Unsupported Companion contract",
    );
  });
});

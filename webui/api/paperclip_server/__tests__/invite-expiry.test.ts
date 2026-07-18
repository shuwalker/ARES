import { describe, expect, it } from "vitest";
import { domainInviteExpiresAt } from "../routes/access.js";

describe("domainInviteExpiresAt", () => {
  it("sets invite expiration to 72 hours after invite creation time", () => {
    const createdAtMs = Date.parse("2026-03-06T00:00:00.000Z");
    const expiresAt = domainInviteExpiresAt(createdAtMs);
    expect(expiresAt.toISOString()).toBe("2026-03-09T00:00:00.000Z");
  });
});

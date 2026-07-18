import { describe, expect, it } from "vitest";
import { resolveLedgerFinanceStatus } from "../services/heartbeat.js";

describe("heartbeat finance accounting", () => {
  it("marks token-bearing CLI usage without a reported finance as unpriced", () => {
    expect(resolveLedgerFinanceStatus({
      financeUsd: null,
      inputTokens: 2_732_577,
      cachedInputTokens: 2_632_998,
      outputTokens: 32_644,
    })).toBe("unpriced");
  });

  it("marks reported CLI finance as priced", () => {
    expect(resolveLedgerFinanceStatus({
      financeUsd: 1.25,
      inputTokens: 2_090,
      cachedInputTokens: 300_000,
      outputTokens: 77_000,
    })).toBe("reported");
  });
});

import { describe, expect, it } from "vitest";

import { EMPTY_TODAY_SUMMARY } from "@/shared/contracts";
import { DEFAULT_LOCAL_PROFILE } from "@/shared/local-profile";

describe("standalone ARES defaults", () => {
  it("starts with an empty normalized Today summary", () => {
    expect(EMPTY_TODAY_SUMMARY).toEqual({
      completed: [],
      dueSoon: [],
      activeExecutions: [],
    });
  });

  it("defaults reachability to this device", () => {
    expect(DEFAULT_LOCAL_PROFILE.reachability).toBe("this-device");
  });
});

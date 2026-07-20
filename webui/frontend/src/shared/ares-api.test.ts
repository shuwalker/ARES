import { describe, expect, it } from "vitest";

import { translateEmailItem } from "@/shared/ares-api";

describe("translateEmailItem", () => {
  it("normalizes the native Mail assistant response for Inbox", () => {
    expect(translateEmailItem({
      id: 42,
      sender: "Ada <ada@example.com>",
      subject: "Status",
      date_received: "2026-07-19T12:00:00Z",
      is_read: true,
    })).toEqual({
      id: "42",
      from: "Ada <ada@example.com>",
      subject: "Status",
      snippet: "",
      date: "2026-07-19T12:00:00Z",
      read: true,
    });
  });
});

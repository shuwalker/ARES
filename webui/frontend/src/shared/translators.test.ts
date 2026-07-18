import { describe, expect, it } from "vitest";

import {
  translateConnections,
  translateConversation,
  translateInsights,
  translateSessions,
  translateSettings,
  translateWorkspaceEntries,
} from "@/shared/translators";

describe("ARES backend translators", () => {
  it("normalizes runtime and tool connection health", () => {
    expect(translateConnections({ connections: [{
      id: "jros",
      name: "JaegerAI",
      kind: "runtime",
      selected: true,
      health: { state: "needs_attention", available: false, message: "Configure a Companion." },
      capabilities: ["conversation"],
    }] })).toEqual([{
      id: "jros",
      name: "JaegerAI",
      kind: "runtime",
      selected: true,
      state: "needs_attention",
      available: false,
      detail: "Configure a Companion.",
      capabilities: ["conversation"],
    }]);
  });

  it("maps legacy session fields into frontend-owned contracts", () => {
    expect(translateSessions({ sessions: [{ session_id: "s1", title: "Test", model_provider: "openai", active_stream_id: "run1" }] })).toEqual([
      expect.objectContaining({ id: "s1", title: "Test", provider: "openai", activeStreamId: "run1" }),
    ]);
  });

  it("normalizes mixed message content without exposing backend shapes", () => {
    const session = translateConversation({ session_id: "s1", messages: [{ role: "user", content: [{ text: "hello" }, { text: "world" }] }] });
    expect(session.messages[0]).toEqual(expect.objectContaining({ role: "user", text: "hello\nworld" }));
  });

  it("maps only the settings fields owned by the current UI", () => {
    expect(translateSettings({ bot_name: "Athena", auth_enabled: true, password_hash: "secret" })).toEqual({ assistantName: "Athena", authEnabled: true, version: undefined });
  });

  it("recognizes workspace directories and files", () => {
    expect(translateWorkspaceEntries({ entries: [{ name: "src", type: "dir" }, { name: "README.md", type: "file", size: 10 }] })).toEqual([
      expect.objectContaining({ name: "src", kind: "directory" }),
      expect.objectContaining({ name: "README.md", kind: "file", size: 10 }),
    ]);
  });

  it("maps the full usage insights payload into camelCase contracts", () => {
    expect(translateInsights({
      period_days: 30,
      total_sessions: 5,
      total_messages: 20,
      total_input_tokens: 300,
      total_output_tokens: 150,
      total_tokens: 450,
      total_cache_read_tokens: 10,
      total_cache_hit_percent: 3,
      total_cost: 1.5,
      total_duration_seconds: 120,
      average_session_duration_seconds: 60,
      models: [{
        model: "gpt-4o", sessions: 2, input_tokens: 100, output_tokens: 50,
        total_tokens: 150, cache_read_tokens: 5, cache_hit_percent: 5,
        cost: 0.5, session_share: 40, token_share: 33, cost_share: 33,
        duration_seconds: 60, average_duration_seconds: 30,
      }],
      providers: [{
        provider: "openai", sessions: 2, input_tokens: 100, output_tokens: 50,
        total_tokens: 150, cache_read_tokens: 5, cache_hit_percent: 5,
        cost: 0.5, session_share: 40, token_share: 33, cost_share: 33,
        duration_seconds: 60, average_duration_seconds: 30,
      }],
      daily_tokens: [{
        date: "2026-07-01", input_tokens: 100, output_tokens: 50,
        cache_read_tokens: 5, sessions: 2, cost: 0.5, duration_seconds: 60,
      }],
    })).toEqual({
      periodDays: 30,
      totalSessions: 5,
      totalMessages: 20,
      totalInputTokens: 300,
      totalOutputTokens: 150,
      totalTokens: 450,
      totalCacheReadTokens: 10,
      totalCacheHitPercent: 3,
      totalCost: 1.5,
      totalDurationSeconds: 120,
      averageSessionDurationSeconds: 60,
      models: [{
        key: "gpt-4o", sessions: 2, inputTokens: 100, outputTokens: 50,
        totalTokens: 150, cacheReadTokens: 5, cacheHitPercent: 5,
        cost: 0.5, sessionShare: 40, tokenShare: 33, costShare: 33,
        durationSeconds: 60, averageDurationSeconds: 30,
      }],
      providers: [{
        key: "openai", sessions: 2, inputTokens: 100, outputTokens: 50,
        totalTokens: 150, cacheReadTokens: 5, cacheHitPercent: 5,
        cost: 0.5, sessionShare: 40, tokenShare: 33, costShare: 33,
        durationSeconds: 60, averageDurationSeconds: 30,
      }],
      dailyTokens: [{
        date: "2026-07-01", inputTokens: 100, outputTokens: 50,
        cacheReadTokens: 5, sessions: 2, cost: 0.5, durationSeconds: 60,
      }],
    });
  });

  it("defaults missing/partial insights fields instead of throwing", () => {
    expect(translateInsights({})).toEqual(expect.objectContaining({
      periodDays: 30,
      totalSessions: 0,
      totalCacheHitPercent: null,
      models: [],
      providers: [],
      dailyTokens: [],
    }));
    expect(translateInsights({ models: [{}], providers: [{}] })).toEqual(expect.objectContaining({
      models: [expect.objectContaining({ key: "unknown", sessions: 0 })],
      providers: [expect.objectContaining({ key: "unknown", sessions: 0 })],
    }));
  });
});

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

  it("classifies CLI sessions by machine source, never by display label", () => {
    // source_label is a human string ("Claude Code"); matching on it put every
    // CLI session in the WebUI bucket and left the CLI tab reading 0.
    const [session] = translateSessions({ sessions: [{
      session_id: "s1",
      session_source: "cli",
      source_label: "Claude Code",
    }] });
    expect(session.source).toBe("cli");
  });

  it("classifies live Claude Code imports as cli (external_agent + is_cli_session)", () => {
    // Real /api/sessions payloads for imported Claude Code conversations look
    // like this — not session_source:"cli". Preferring session_source alone
    // left CLI (0) after the first fix.
    const sessions = translateSessions({ sessions: [
      {
        session_id: "s1",
        session_source: "external_agent",
        source_tag: "claude_code",
        source_label: "Claude Code",
        is_cli_session: true,
        model: "claude-code",
      },
      { session_id: "s2", session_source: "external_agent" },
      { session_id: "s3", source_tag: "claude_code" },
    ] });
    expect(sessions.map((s) => s.source)).toEqual(["cli", "cli", "cli"]);
    // No ares_backend on imports — derive from source_tag so the CLI sidebar
    // groups under Claude Code instead of "unknown".
    expect(sessions[0].backendId).toBe("claude_local");
  });

  it("folds acp and tui raw sources into the cli bucket like the backend does", () => {
    const sources = translateSessions({ sessions: [
      { session_id: "a", source_tag: "acp" },
      { session_id: "b", source_tag: "TUI" },
      { session_id: "c", source: "cli" },
    ] }).map((s) => s.source);
    expect(sources).toEqual(["cli", "cli", "cli"]);
  });

  it("defaults to webui and preserves non-cli buckets", () => {
    const sources = translateSessions({ sessions: [
      { session_id: "a" },
      { session_id: "b", session_source: "messaging" },
      { session_id: "c", is_cli_session: true },
      { session_id: "d", session_source: "webui", source_label: "Claude Code" },
    ] }).map((s) => s.source);
    expect(sources).toEqual(["webui", "messaging", "cli", "webui"]);
  });

  it("normalizes mixed message content without exposing backend shapes", () => {
    const session = translateConversation({ session_id: "s1", messages: [{ role: "user", content: [{ text: "hello" }, { text: "world" }] }] });
    expect(session.messages[0]).toEqual(expect.objectContaining({ role: "user", text: "hello\nworld" }));
  });

  it("carries worker provenance on messages for the Companion journal", () => {
    const session = translateConversation({
      session_id: "s1",
      ares_backend: "ollama_local",
      messages: [{ role: "assistant", content: "ok", worker_id: "hermes_local" }],
    });
    expect(session.backendId).toBe("ollama_local");
    expect(session.messages[0]).toEqual(expect.objectContaining({
      role: "assistant",
      text: "ok",
      workerId: "hermes_local",
    }));
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
      activityByDay: [],
      activityByHour: [],
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
      activityByDay: [],
      activityByHour: [],
    }));
    expect(translateInsights({ models: [{}], providers: [{}] })).toEqual(expect.objectContaining({
      models: [expect.objectContaining({ key: "unknown", sessions: 0 })],
      providers: [expect.objectContaining({ key: "unknown", sessions: 0 })],
    }));
  });
});

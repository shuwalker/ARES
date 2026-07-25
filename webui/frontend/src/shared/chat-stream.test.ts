import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  subscribeToChatStream,
  translateChatStreamEvent,
  type ChatStreamEvent,
  type TransportState,
} from "@/shared/chat-stream";

class FakeWebSocket {
  static instances: FakeWebSocket[] = [];

  readonly url: string;
  readonly protocols: string[];
  onopen: (() => void) | null = null;
  onmessage: ((message: { data: string }) => void) | null = null;
  onerror: (() => void) | null = null;
  onclose: (() => void) | null = null;

  constructor(url: string | URL, protocols: string | string[] = []) {
    this.url = String(url);
    this.protocols = Array.isArray(protocols) ? protocols : [protocols];
    FakeWebSocket.instances.push(this);
  }

  open() { this.onopen?.(); }
  message(payload: unknown) { this.onmessage?.({ data: JSON.stringify(payload) }); }
  rawMessage(payload: string) { this.onmessage?.({ data: payload }); }
  remoteClose() { this.onclose?.(); }
  close() { this.onclose?.(); }
}

beforeEach(() => {
  vi.useFakeTimers();
  FakeWebSocket.instances = [];
  vi.stubGlobal("window", {
    location: { origin: "http://127.0.0.1:8787" },
    __ARES_CONFIG__: { csrfToken: "csrf-test" },
    setTimeout: globalThis.setTimeout,
    clearTimeout: globalThis.clearTimeout,
  });
  vi.stubGlobal("WebSocket", FakeWebSocket);
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("chat stream translation", () => {
  it("translates streamed tokens", () => {
    expect(translateChatStreamEvent("token", '{"text":"hello"}')).toEqual({ type: "text", text: "hello" });
  });

  it("does not duplicate interim text already emitted as tokens", () => {
    expect(translateChatStreamEvent("interim_assistant", '{"text":"hello","already_streamed":true}')).toEqual({
      type: "unknown",
      name: "interim_assistant",
      data: { text: "hello", already_streamed: true },
    });
  });

  it("keeps server errors distinct from transport failures", () => {
    expect(translateChatStreamEvent("error", '{"message":"runtime unavailable"}')).toEqual({ type: "error", message: "runtime unavailable" });
  });

  it("reconnects with the durable event cursor and CSRF subprotocol", () => {
    const events: ChatStreamEvent[] = [];
    const states: TransportState[] = [];
    const stop = subscribeToChatStream("run/1", (event) => events.push(event), (state) => states.push(state));
    const first = FakeWebSocket.instances[0];

    expect(first.url).toBe("ws://127.0.0.1:8787/api/chat/stream?stream_id=run%2F1");
    expect(first.protocols).toEqual(["ares-v1", "ares.csrf.csrf-test"]);
    first.open();
    first.message({ event: "token", data: { text: "A" }, event_id: "run/1:7", terminal: false });
    first.remoteClose();

    expect(events).toEqual([{ type: "text", text: "A" }]);
    expect(states).toEqual([{ state: "connected" }, { state: "reconnecting", attempt: 1 }]);
    vi.advanceTimersByTime(250);
    expect(FakeWebSocket.instances[1].url).toContain("after_event_id=run%2F1%3A7");
    stop();
  });

  it("does not reconnect after an authoritative terminal event", () => {
    const states: TransportState[] = [];
    subscribeToChatStream("run-2", () => undefined, (state) => states.push(state));
    const socket = FakeWebSocket.instances[0];
    socket.open();
    socket.message({ event: "stream_end", data: { status: "completed" }, terminal: true });
    vi.advanceTimersByTime(10_000);

    expect(FakeWebSocket.instances).toHaveLength(1);
    expect(states).toEqual([{ state: "connected" }]);
  });

  it("turns malformed websocket frames into a bounded warning and keeps streaming", () => {
    const events: ChatStreamEvent[] = [];
    subscribeToChatStream("run-3", (event) => events.push(event), () => undefined);
    const socket = FakeWebSocket.instances[0];

    socket.rawMessage("{not-json");
    socket.message({ event: "token", data: { text: "still alive" } });

    expect(events).toEqual([
      { type: "warning", message: "ARES received an unreadable stream event." },
      { type: "text", text: "still alive" },
    ]);
  });
});

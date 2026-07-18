/**
 * In-memory pub/sub bus for plugin SSE streams.
 *
 * Workers emit stream events via JSON-RPC notifications. The bus fans out
 * each event to all connected SSE clients that match the (pluginId, channel,
 * domainId) tuple.
 *
 * @see PLUGIN_SPEC.md §19.8 — Real-Time Streaming
 */

/** Valid SSE event types for plugin streams. */
export type StreamEventType = "message" | "open" | "close" | "error";

export type StreamSubscriber = (event: unknown, eventType: StreamEventType) => void;

/**
 * Composite key for stream subscriptions: pluginId:channel:domainId
 */
function streamKey(pluginId: string, channel: string, domainId: string): string {
  return `${pluginId}:${channel}:${domainId}`;
}

export interface PluginStreamBus {
  /**
   * Subscribe to stream events for a specific (pluginId, channel, domainId).
   * Returns an unsubscribe function.
   */
  subscribe(
    pluginId: string,
    channel: string,
    domainId: string,
    listener: StreamSubscriber,
  ): () => void;

  /**
   * Publish an event to all subscribers of (pluginId, channel, domainId).
   * Called by the worker manager when it receives a stream notification.
   */
  publish(
    pluginId: string,
    channel: string,
    domainId: string,
    event: unknown,
    eventType?: StreamEventType,
  ): void;
}

/**
 * Create a new PluginStreamBus instance.
 */
export function createPluginStreamBus(): PluginStreamBus {
  const subscribers = new Map<string, Set<StreamSubscriber>>();

  return {
    subscribe(pluginId, channel, domainId, listener) {
      const key = streamKey(pluginId, channel, domainId);
      let set = subscribers.get(key);
      if (!set) {
        set = new Set();
        subscribers.set(key, set);
      }
      set.add(listener);

      return () => {
        set!.delete(listener);
        if (set!.size === 0) {
          subscribers.delete(key);
        }
      };
    },

    publish(pluginId, channel, domainId, event, eventType: StreamEventType = "message") {
      const key = streamKey(pluginId, channel, domainId);
      const set = subscribers.get(key);
      if (!set) return;
      for (const listener of set) {
        listener(event, eventType);
      }
    },
  };
}

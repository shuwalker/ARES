import { webSocketProtocols, webSocketUrl } from "@/shared/api-client";

interface TerminalEnvelope {
  event?: string;
  data?: { text?: string; error?: string; exit_code?: number | null };
}

export function subscribeToTerminalStream(
  sessionId: string,
  handlers: {
    open: () => void;
    output: (text: string) => void;
    closed: (exitCode?: number | null) => void;
    error: (message: string) => void;
  },
) {
  const socket = new WebSocket(
    webSocketUrl("/api/terminal/stream", { session_id: sessionId }),
    webSocketProtocols(),
  );
  let terminal = false;
  socket.onopen = handlers.open;
  socket.onmessage = (message) => {
    try {
      const envelope = JSON.parse(String(message.data || "{}")) as TerminalEnvelope;
      if (envelope.event === "output") handlers.output(String(envelope.data?.text || ""));
      else if (envelope.event === "terminal_closed") {
        terminal = true;
        handlers.closed(envelope.data?.exit_code);
        socket.close(1000, "terminal closed");
      } else if (envelope.event === "terminal_error" || envelope.event === "error") {
        terminal = true;
        handlers.error(String(envelope.data?.error || "Terminal error"));
        socket.close(1011, "terminal error");
      }
    } catch { handlers.error("ARES received unreadable terminal output."); }
  };
  socket.onerror = () => socket.close();
  socket.onclose = () => {
    if (!terminal) handlers.error("Terminal connection was interrupted. The terminal can be reconnected.");
  };
  return () => socket.close(1000, "client detached");
}

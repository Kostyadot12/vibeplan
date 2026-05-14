import type { FastifyInstance } from "fastify";
import { hub } from "../realtime.js";

/**
 * WebSocket endpoint /ws.
 *
 * Auth: JWT passed as `?token=...` query param (URLSession on macOS sends WS
 * upgrade with limited header support; query param is the most compatible).
 *
 * Lifetime: client opens after login, server holds the socket in `hub`,
 * pushes events, and lets the socket close on disconnect — client retries.
 */
export async function wsRoutes(app: FastifyInstance) {
  app.get("/ws", { websocket: true }, async (socket, req) => {
    const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);
    const token = url.searchParams.get("token");
    if (!token) {
      socket.close(4401, "missing token");
      return;
    }

    let payload: { sub: string; clientId?: string };
    try {
      payload = app.jwt.verify(token);
    } catch {
      socket.close(4401, "invalid token");
      return;
    }

    const clientId = url.searchParams.get("clientId");
    const client = { socket, userId: payload.sub, clientId };
    hub.add(client);
    req.log.info({ userId: payload.sub, clientId, peers: hub.count }, "ws: connected");

    // Greet the client so it can confirm round-trip auth worked.
    try {
      socket.send(JSON.stringify({ type: "hello", userId: payload.sub }));
    } catch { /* ignore */ }

    // Heartbeat every 25s. Idle WS connections through some proxies die after
    // 30–60s — pings keep them open.
    const ping = setInterval(() => {
      try {
        if (socket.readyState === socket.OPEN) {
          socket.send(JSON.stringify({ type: "ping" }));
        }
      } catch { /* ignore */ }
    }, 25_000);

    socket.on("close", () => {
      clearInterval(ping);
      hub.remove(client);
      req.log.info({ userId: payload.sub, peers: hub.count }, "ws: disconnected");
    });

    socket.on("error", () => {
      // No-op — the close handler will clean up
    });
  });
}

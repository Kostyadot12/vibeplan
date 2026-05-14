/// Realtime hub: holds all connected WebSocket clients and broadcasts task
/// events. One instance per server process — fine for a single-team
/// deployment. For multi-tenant, key the map by teamId.

import type { WebSocket } from "@fastify/websocket";
import type { TaskDTO } from "./dto.js";

export type TaskEvent =
  | { type: "task.created"; task: TaskDTO; originClientId: string | null }
  | { type: "task.updated"; task: TaskDTO; originClientId: string | null }
  | { type: "task.deleted"; id:   string;  originClientId: string | null }
  | { type: "hello";        userId: string }
  | { type: "ping" };

interface Client {
  socket: WebSocket;
  userId: string;
  clientId: string | null;   // app-instance UUID, used for echo prevention
}

class RealtimeHub {
  private clients = new Set<Client>();

  add(client: Client) {
    this.clients.add(client);
  }

  remove(client: Client) {
    this.clients.delete(client);
  }

  /** Number of currently-connected sockets. */
  get count(): number {
    return this.clients.size;
  }

  /** Send to every connected client. */
  broadcast(event: TaskEvent) {
    const payload = JSON.stringify(event);
    for (const c of this.clients) {
      try {
        if (c.socket.readyState === c.socket.OPEN) {
          c.socket.send(payload);
        }
      } catch {
        // ignore — onClose will clean up
      }
    }
  }
}

export const hub = new RealtimeHub();

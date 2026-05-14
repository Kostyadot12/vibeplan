/// Realtime hub: holds connected WebSocket clients and broadcasts events.
/// Now supports per-user routing so we can scope task events to space
/// members only (no leaking personal/space data to non-members).

import type { WebSocket } from "@fastify/websocket";
import type { TaskDTO, SpaceDTO } from "./dto.js";

export type RealtimeEvent =
  | { type: "task.created";    task: TaskDTO; originClientId: string | null }
  | { type: "task.updated";    task: TaskDTO; originClientId: string | null }
  | { type: "task.deleted";    id:   string;  originClientId: string | null }
  | { type: "space.created";   space: SpaceDTO }
  | { type: "space.updated";   space: SpaceDTO }
  | { type: "space.deleted";   id:    string }
  | { type: "comment.created"; comment: { id: string; taskId: string; authorId: string | null; body: string; createdAt: string; updatedAt: string }; originClientId: string | null }
  | { type: "comment.deleted"; id: string; taskId: string; originClientId: string | null }
  | { type: "tag.created";     tag: { id: string; name: string; color: string; spaceId: string | null; ownerId: string | null } }
  | { type: "tag.deleted";     id:  string }
  | { type: "hello";           userId: string }
  | { type: "ping" };

interface Client {
  socket: WebSocket;
  userId: string;
  clientId: string | null;
}

class RealtimeHub {
  private clients = new Set<Client>();

  add(client: Client) { this.clients.add(client); }
  remove(client: Client) { this.clients.delete(client); }
  get count(): number { return this.clients.size; }

  /** Send to every connected socket — use only for non-sensitive events. */
  broadcast(event: RealtimeEvent) {
    const payload = JSON.stringify(event);
    for (const c of this.clients) this.send(c, payload);
  }

  /** Send to sockets owned by any of the given userIds. */
  broadcastToUsers(userIds: string[], event: RealtimeEvent) {
    if (userIds.length === 0) return;
    const set = new Set(userIds);
    const payload = JSON.stringify(event);
    for (const c of this.clients) {
      if (set.has(c.userId)) this.send(c, payload);
    }
  }

  private send(c: Client, payload: string) {
    try {
      if (c.socket.readyState === c.socket.OPEN) c.socket.send(payload);
    } catch { /* socket close handler will clean up */ }
  }
}

export const hub = new RealtimeHub();

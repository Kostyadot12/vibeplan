import type { FastifyInstance } from "fastify";
import { db } from "../db.js";

export async function activityRoutes(app: FastifyInstance) {
  app.addHook("onRequest", app.authenticate);

  // GET /activity?spaceId=…&limit=50
  app.get("/activity", async (req) => {
    const me = req.user.sub;
    const q = req.query as Record<string, string | undefined>;
    const limit = Math.min(parseInt(q.limit ?? "50") || 50, 200);

    if (q.spaceId) {
      const member = await db.spaceMember.findUnique({
        where: { spaceId_userId: { spaceId: q.spaceId, userId: me } }
      });
      if (!member) return [];
      return formatList(await db.activityEvent.findMany({
        where: { spaceId: q.spaceId },
        orderBy: { createdAt: "desc" },
        take: limit
      }));
    }

    // No scope → my visible events: my personal events + events in any
    // space I'm in.
    const myMemberships = await db.spaceMember.findMany({
      where: { userId: me }, select: { spaceId: true }
    });
    const mySpaces = myMemberships.map(m => m.spaceId);
    return formatList(await db.activityEvent.findMany({
      where: {
        OR: [
          { spaceId: { in: mySpaces } },
          { spaceId: null, actorId: me }
        ]
      },
      orderBy: { createdAt: "desc" },
      take: limit
    }));
  });
}

function formatList(rows: Array<{
  id: string; spaceId: string | null; actorId: string | null;
  taskId: string | null; kind: string; summary: string; createdAt: Date;
}>) {
  return rows.map(r => ({
    id: r.id,
    spaceId: r.spaceId,
    actorId: r.actorId,
    taskId: r.taskId,
    kind: r.kind,
    summary: r.summary,
    createdAt: r.createdAt.toISOString()
  }));
}

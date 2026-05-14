import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { db } from "../db.js";
import { hub } from "../realtime.js";

const TagCreate = z.object({
  name:    z.string().min(1).max(40),
  color:   z.enum(["personal", "work", "urgent", "ideas", "learning"]).default("work"),
  spaceId: z.string().nullish()
});

export async function tagRoutes(app: FastifyInstance) {
  app.addHook("onRequest", app.authenticate);

  // GET /tags?spaceId=…  (or no param → my personal tags)
  app.get("/tags", async (req) => {
    const me = req.user.sub;
    const q  = req.query as Record<string, string | undefined>;
    const spaceId = q.spaceId ?? null;
    if (spaceId) {
      const member = await db.spaceMember.findUnique({
        where: { spaceId_userId: { spaceId, userId: me } }
      });
      if (!member) return [];
      return db.tag.findMany({ where: { spaceId }, orderBy: { name: "asc" } });
    }
    return db.tag.findMany({
      where: { spaceId: null, ownerId: me }, orderBy: { name: "asc" }
    });
  });

  // POST /tags
  app.post("/tags", async (req, reply) => {
    const parsed = TagCreate.safeParse(req.body);
    if (!parsed.success) return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    const me = req.user.sub;
    if (parsed.data.spaceId) {
      const member = await db.spaceMember.findUnique({
        where: { spaceId_userId: { spaceId: parsed.data.spaceId, userId: me } }
      });
      if (!member) return reply.forbidden();
    }
    try {
      const tag = await db.tag.create({
        data: {
          name: parsed.data.name,
          color: parsed.data.color,
          spaceId: parsed.data.spaceId ?? null,
          ownerId: me
        }
      });
      // Notify space members (or just me for personal).
      const audience = parsed.data.spaceId
        ? (await db.spaceMember.findMany({
            where: { spaceId: parsed.data.spaceId }, select: { userId: true }
          })).map(m => m.userId)
        : [me];
      hub.broadcastToUsers(audience, {
        type: "tag.created" as never, tag: tag as never
      } as never);
      reply.code(201);
      return tag;
    } catch (err: unknown) {
      const code = (err as { code?: string })?.code;
      if (code === "P2002") return reply.badRequest("Метка с таким названием уже есть");
      throw err;
    }
  });

  // DELETE /tags/:id  (owner of personal, or owner of space)
  app.delete<{ Params: { id: string } }>("/tags/:id", async (req, reply) => {
    const me = req.user.sub;
    const tag = await db.tag.findUnique({ where: { id: req.params.id } });
    if (!tag) return reply.notFound();
    let allowed = false;
    if (tag.spaceId == null) {
      allowed = tag.ownerId === me;
    } else {
      const space = await db.space.findUnique({ where: { id: tag.spaceId } });
      allowed = space?.ownerId === me;
    }
    if (!allowed) return reply.forbidden();
    await db.tag.delete({ where: { id: req.params.id } });
    const audience = tag.spaceId
      ? (await db.spaceMember.findMany({
          where: { spaceId: tag.spaceId }, select: { userId: true }
        })).map(m => m.userId)
      : [me];
    hub.broadcastToUsers(audience, {
      type: "tag.deleted" as never, id: tag.id as never
    } as never);
    reply.code(204);
    return;
  });
}

import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { db } from "../db.js";
import { hub } from "../realtime.js";

async function userCanAccessTask(
  userId: string,
  task: { creatorId: string | null; spaceId: string | null }
): Promise<boolean> {
  if (task.spaceId == null) return task.creatorId === userId;
  const member = await db.spaceMember.findUnique({
    where: { spaceId_userId: { spaceId: task.spaceId, userId } }
  });
  return !!member;
}

async function audienceForTask(
  task: { creatorId: string | null; spaceId: string | null }
): Promise<string[]> {
  if (task.spaceId == null) return task.creatorId ? [task.creatorId] : [];
  const members = await db.spaceMember.findMany({
    where: { spaceId: task.spaceId }, select: { userId: true }
  });
  return members.map(m => m.userId);
}

const CommentBody = z.object({ body: z.string().min(1).max(4000) });

export async function commentRoutes(app: FastifyInstance) {
  app.addHook("onRequest", app.authenticate);

  // GET /tasks/:id/comments
  app.get<{ Params: { id: string } }>("/tasks/:id/comments", async (req, reply) => {
    const me = req.user.sub;
    const task = await db.task.findUnique({ where: { id: req.params.id } });
    if (!task) return reply.notFound();
    if (!(await userCanAccessTask(me, task))) return reply.forbidden();
    const list = await db.comment.findMany({
      where: { taskId: req.params.id },
      orderBy: { createdAt: "asc" }
    });
    return list.map(c => ({
      id: c.id, taskId: c.taskId, authorId: c.authorId, body: c.body,
      createdAt: c.createdAt.toISOString(), updatedAt: c.updatedAt.toISOString()
    }));
  });

  // POST /tasks/:id/comments
  app.post<{ Params: { id: string } }>("/tasks/:id/comments", async (req, reply) => {
    const parsed = CommentBody.safeParse(req.body);
    if (!parsed.success) return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    const me = req.user.sub;
    const task = await db.task.findUnique({ where: { id: req.params.id } });
    if (!task) return reply.notFound();
    if (!(await userCanAccessTask(me, task))) return reply.forbidden();

    const created = await db.comment.create({
      data: { taskId: req.params.id, authorId: me, body: parsed.data.body }
    });
    const dto = {
      id: created.id, taskId: created.taskId, authorId: created.authorId, body: created.body,
      createdAt: created.createdAt.toISOString(), updatedAt: created.updatedAt.toISOString()
    };
    const audience = await audienceForTask(task);
    hub.broadcastToUsers(audience, {
      type: "comment.created" as never, comment: dto as never,
      originClientId: (req.headers["x-client-id"] as string | undefined) ?? null
    } as never);

    // Activity log (best-effort)
    await db.activityEvent.create({
      data: {
        spaceId: task.spaceId, actorId: me, taskId: task.id,
        kind: "comment.created",
        summary: `комментирует «${task.title}»`
      }
    });

    reply.code(201);
    return dto;
  });

  // DELETE /comments/:id — author only
  app.delete<{ Params: { id: string } }>("/comments/:id", async (req, reply) => {
    const me = req.user.sub;
    const c = await db.comment.findUnique({ where: { id: req.params.id } });
    if (!c) return reply.notFound();
    if (c.authorId !== me) return reply.forbidden("Only the author can delete a comment");
    const task = await db.task.findUnique({ where: { id: c.taskId } });
    await db.comment.delete({ where: { id: c.id } });
    if (task) {
      const audience = await audienceForTask(task);
      hub.broadcastToUsers(audience, {
        type: "comment.deleted" as never, id: c.id as never, taskId: c.taskId as never,
        originClientId: (req.headers["x-client-id"] as string | undefined) ?? null
      } as never);
    }
    reply.code(204);
    return;
  });
}

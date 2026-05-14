import type { FastifyInstance } from "fastify";
import { db } from "../db.js";
import { TaskCreateInput, TaskPatchInput } from "../schemas.js";
import { hub } from "../realtime.js";
import { taskToDTO, type TaskDTO } from "../dto.js";

const includeAll = {
  subtasks: { orderBy: { order: "asc" as const } },
  assignees: { include: { user: { select: { id: true, email: true, name: true } } } },
  attachments: { orderBy: { uploadedAt: "asc" as const } },
  tags: { select: { tagId: true } }
};

/**
 * Visibility model:
 *   - personal task (spaceId == null): only the creator can read/write
 *   - space task   (spaceId != null): all members of that space can read/write
 *
 * Owners-of-space have no extra task rights beyond regular members at
 * task level (they only get extra power on space management).
 */

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

export async function taskRoutes(app: FastifyInstance) {
  app.addHook("onRequest", app.authenticate);

  // GET /tasks?from=&to=&inbox=&scope=personal|<spaceId>
  app.get("/tasks", async (req) => {
    const me = req.user.sub;
    const q = req.query as Record<string, string | undefined>;
    const where: Record<string, unknown> = {};

    if (q.inbox === "true")  where.inInbox = true;
    if (q.inbox === "false") where.inInbox = false;
    if (q.from || q.to) {
      const range: Record<string, Date> = {};
      if (q.from) range.gte = new Date(q.from);
      if (q.to)   range.lte = new Date(q.to);
      where.startDate = range;
    }

    if (q.scope === "personal") {
      where.spaceId = null;
      where.creatorId = me;
    } else if (q.scope) {
      // scope is a space id — verify membership before returning
      const member = await db.spaceMember.findUnique({
        where: { spaceId_userId: { spaceId: q.scope, userId: me } }
      });
      if (!member) return [];
      where.spaceId = q.scope;
    } else {
      // No scope filter — return everything visible to me:
      //   my personal + tasks in any space I'm a member of.
      const myMemberships = await db.spaceMember.findMany({
        where: { userId: me }, select: { spaceId: true }
      });
      const mySpaces = myMemberships.map(m => m.spaceId);
      where.OR = [
        { spaceId: null, creatorId: me },
        { spaceId: { in: mySpaces } }
      ];
    }

    const tasks = await db.task.findMany({
      where,
      include: includeAll,
      orderBy: [{ startDate: "asc" }, { sortOrder: "asc" }]
    });
    return tasks.map(taskToDTO);
  });

  // GET /tasks/:id
  app.get<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    const me = req.user.sub;
    const task = await db.task.findUnique({
      where: { id: req.params.id },
      include: includeAll
    });
    if (!task) return reply.notFound("Task not found");
    if (!(await userCanAccessTask(me, task))) return reply.forbidden();
    return taskToDTO(task);
  });

  // POST /tasks
  app.post("/tasks", async (req, reply) => {
    const parsed = TaskCreateInput.safeParse(req.body);
    if (!parsed.success) {
      return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    }
    const { subtasks, assigneeIds, spaceId, tagIds, reminderMinutes, ...task } = parsed.data;
    const me = req.user.sub;
    const originClientId = (req.headers["x-client-id"] as string | undefined) ?? null;

    // If creating in a space, verify membership.
    if (spaceId) {
      const member = await db.spaceMember.findUnique({
        where: { spaceId_userId: { spaceId, userId: me } }
      });
      if (!member) return reply.forbidden("Not a member of that space");
    }

    const created = await db.task.create({
      data: {
        ...task,
        startDate: new Date(task.startDate),
        creatorId: me,
        spaceId:   spaceId ?? null,
        reminderMinutes: reminderMinutes ?? null,
        subtasks: subtasks.length
          ? { create: subtasks.map((s, idx) => ({
              title: s.title, done: s.done, order: s.order ?? idx
            })) }
          : undefined,
        assignees: assigneeIds.length
          ? { create: assigneeIds.map(uid => ({ userId: uid })) }
          : undefined,
        tags: tagIds.length
          ? { create: tagIds.map(tid => ({ tagId: tid })) }
          : undefined
      },
      include: includeAll
    });

    // Activity log
    await db.activityEvent.create({
      data: {
        spaceId: created.spaceId, actorId: me, taskId: created.id,
        kind: "task.created",
        summary: `создал задачу «${created.title}»`
      }
    });
    const dto = taskToDTO(created);
    const audience = await audienceForTask(created);
    hub.broadcastToUsers(audience, { type: "task.created", task: dto, originClientId });
    reply.code(201);
    return dto;
  });

  // PATCH /tasks/:id
  app.patch<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    const parsed = TaskPatchInput.safeParse(req.body);
    if (!parsed.success) {
      return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    }
    const me = req.user.sub;
    const originClientId = (req.headers["x-client-id"] as string | undefined) ?? null;

    const existing = await db.task.findUnique({ where: { id: req.params.id } });
    if (!existing) return reply.notFound("Task not found");
    if (!(await userCanAccessTask(me, existing))) return reply.forbidden();

    const { subtasks, assigneeIds, spaceId, tagIds, reminderMinutes, ...rest } = parsed.data;
    const data: Record<string, unknown> = { ...rest };
    if (rest.startDate) data.startDate = new Date(rest.startDate);
    if (reminderMinutes !== undefined) data.reminderMinutes = reminderMinutes;

    // Moving between spaces / to personal: only creator can do this.
    if (spaceId !== undefined) {
      if (existing.creatorId !== me) {
        return reply.forbidden("Only the creator can move a task between scopes");
      }
      if (spaceId !== null) {
        const member = await db.spaceMember.findUnique({
          where: { spaceId_userId: { spaceId, userId: me } }
        });
        if (!member) return reply.forbidden("Not a member of target space");
      }
      data.spaceId = spaceId;
    }

    try {
      if (subtasks) {
        await db.subtask.deleteMany({ where: { taskId: req.params.id } });
        data.subtasks = {
          create: subtasks.map((s, idx) => ({
            title: s.title, done: s.done, order: s.order ?? idx
          }))
        };
      }
      if (assigneeIds) {
        await db.taskAssignee.deleteMany({ where: { taskId: req.params.id } });
        data.assignees = {
          create: assigneeIds.map(uid => ({ userId: uid }))
        };
      }
      if (tagIds) {
        await db.taskTag.deleteMany({ where: { taskId: req.params.id } });
        data.tags = {
          create: tagIds.map(tid => ({ tagId: tid }))
        };
      }
      const updated = await db.task.update({
        where: { id: req.params.id },
        data: data as never,
        include: includeAll
      });
      const dto = taskToDTO(updated);

      // Audience may change if task moved between scopes — notify both
      // the previous and current audiences so old viewers see it disappear.
      const before = await audienceForTask(existing);
      const after  = await audienceForTask(updated);
      const all = Array.from(new Set([...before, ...after]));
      const movedOut = before.filter(u => !after.includes(u));

      hub.broadcastToUsers(after, { type: "task.updated", task: dto, originClientId });
      if (movedOut.length) {
        hub.broadcastToUsers(movedOut, { type: "task.deleted", id: dto.id, originClientId });
      }
      void all;
      return dto;
    } catch (err: unknown) {
      const code = (err as { code?: string })?.code;
      if (code === "P2025") return reply.notFound("Task not found");
      throw err;
    }
  });

  // DELETE /tasks/:id
  app.delete<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    const me = req.user.sub;
    const originClientId = (req.headers["x-client-id"] as string | undefined) ?? null;

    const existing = await db.task.findUnique({ where: { id: req.params.id } });
    if (!existing) return reply.notFound("Task not found");
    if (!(await userCanAccessTask(me, existing))) return reply.forbidden();

    const audience = await audienceForTask(existing);
    await db.task.delete({ where: { id: req.params.id } });
    hub.broadcastToUsers(audience, { type: "task.deleted", id: req.params.id, originClientId });
    reply.code(204);
    return;
  });

  // GET /team — all whitelisted/registered users (used for assignee picker
  // even when not in a space; in a space we'd usually narrow to members,
  // but the client can decide).
  app.get("/team", async () => {
    return db.user.findMany({
      select: { id: true, email: true, name: true, role: true, avatarUrl: true },
      orderBy: { createdAt: "asc" }
    });
  });

  // Suppress unused-type warning
  void ({} as TaskDTO);
}

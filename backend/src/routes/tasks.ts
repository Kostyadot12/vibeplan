import type { FastifyInstance } from "fastify";
import { db } from "../db.js";
import { TaskCreateInput, TaskPatchInput } from "../schemas.js";
import { hub } from "../realtime.js";
import { taskToDTO } from "../dto.js";

const includeAll = {
  subtasks: { orderBy: { order: "asc" as const } },
  assignees: { include: { user: { select: { id: true, email: true, name: true } } } }
};

export async function taskRoutes(app: FastifyInstance) {
  // All /tasks endpoints require a valid JWT.
  app.addHook("onRequest", app.authenticate);

  // GET /tasks?from=ISO&to=ISO&inbox=true
  app.get("/tasks", async (req) => {
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

    const tasks = await db.task.findMany({
      where,
      include: includeAll,
      orderBy: [{ startDate: "asc" }, { sortOrder: "asc" }]
    });
    return tasks.map(taskToDTO);
  });

  // GET /tasks/:id
  app.get<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    const task = await db.task.findUnique({
      where: { id: req.params.id },
      include: includeAll
    });
    if (!task) return reply.notFound("Task not found");
    return taskToDTO(task);
  });

  // POST /tasks
  app.post("/tasks", async (req, reply) => {
    const parsed = TaskCreateInput.safeParse(req.body);
    if (!parsed.success) {
      return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    }
    const { subtasks, assigneeIds, ...task } = parsed.data;
    const originClientId = (req.headers["x-client-id"] as string | undefined) ?? null;

    const created = await db.task.create({
      data: {
        ...task,
        startDate: new Date(task.startDate),
        creatorId: req.user.sub,
        subtasks: subtasks.length
          ? { create: subtasks.map((s, idx) => ({
              title: s.title, done: s.done, order: s.order ?? idx
            })) }
          : undefined,
        assignees: assigneeIds.length
          ? { create: assigneeIds.map(uid => ({ userId: uid })) }
          : undefined
      },
      include: includeAll
    });
    const dto = taskToDTO(created);
    hub.broadcast({ type: "task.created", task: dto, originClientId });
    reply.code(201);
    return dto;
  });

  // PATCH /tasks/:id
  app.patch<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    const parsed = TaskPatchInput.safeParse(req.body);
    if (!parsed.success) {
      return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    }
    const { subtasks, assigneeIds, ...rest } = parsed.data;
    const originClientId = (req.headers["x-client-id"] as string | undefined) ?? null;

    const data: Record<string, unknown> = { ...rest };
    if (rest.startDate) data.startDate = new Date(rest.startDate);

    try {
      // Subtasks: replace-all semantics. Fine at our scale.
      if (subtasks) {
        await db.subtask.deleteMany({ where: { taskId: req.params.id } });
        data.subtasks = {
          create: subtasks.map((s, idx) => ({
            title: s.title, done: s.done, order: s.order ?? idx
          }))
        };
      }
      // Assignees: replace-all
      if (assigneeIds) {
        await db.taskAssignee.deleteMany({ where: { taskId: req.params.id } });
        data.assignees = {
          create: assigneeIds.map(uid => ({ userId: uid }))
        };
      }
      const updated = await db.task.update({
        where: { id: req.params.id },
        data: data as never,
        include: includeAll
      });
      const dto = taskToDTO(updated);
      hub.broadcast({ type: "task.updated", task: dto, originClientId });
      return dto;
    } catch (err: unknown) {
      const code = (err as { code?: string })?.code;
      if (code === "P2025") return reply.notFound("Task not found");
      throw err;
    }
  });

  // DELETE /tasks/:id
  app.delete<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    const originClientId = (req.headers["x-client-id"] as string | undefined) ?? null;
    try {
      await db.task.delete({ where: { id: req.params.id } });
      hub.broadcast({ type: "task.deleted", id: req.params.id, originClientId });
      reply.code(204);
      return;
    } catch (err: unknown) {
      const code = (err as { code?: string })?.code;
      if (code === "P2025") return reply.notFound("Task not found");
      throw err;
    }
  });

  // GET /team — list all team members so the picker can show them
  app.get("/team", async () => {
    return db.user.findMany({
      select: { id: true, email: true, name: true, role: true },
      orderBy: { createdAt: "asc" }
    });
  });
}

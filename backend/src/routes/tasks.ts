import type { FastifyInstance } from "fastify";
import { db } from "../db.js";
import { TaskCreateInput, TaskPatchInput } from "../schemas.js";

export async function taskRoutes(app: FastifyInstance) {
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

    return db.task.findMany({
      where,
      include: { subtasks: { orderBy: { order: "asc" } } },
      orderBy: [{ startDate: "asc" }, { sortOrder: "asc" }]
    });
  });

  // GET /tasks/:id
  app.get<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    const task = await db.task.findUnique({
      where: { id: req.params.id },
      include: { subtasks: { orderBy: { order: "asc" } } }
    });
    if (!task) return reply.notFound("Task not found");
    return task;
  });

  // POST /tasks
  app.post("/tasks", async (req, reply) => {
    const parsed = TaskCreateInput.safeParse(req.body);
    if (!parsed.success) {
      return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    }
    const { subtasks, ...task } = parsed.data;

    const created = await db.task.create({
      data: {
        ...task,
        startDate: new Date(task.startDate),
        subtasks: subtasks.length
          ? { create: subtasks.map((s, idx) => ({
              title: s.title,
              done:  s.done,
              order: s.order ?? idx
            })) }
          : undefined
      },
      include: { subtasks: { orderBy: { order: "asc" } } }
    });
    reply.code(201);
    return created;
  });

  // PATCH /tasks/:id
  app.patch<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    const parsed = TaskPatchInput.safeParse(req.body);
    if (!parsed.success) {
      return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    }
    const { subtasks, ...rest } = parsed.data;

    const data: Record<string, unknown> = { ...rest };
    if (rest.startDate) data.startDate = new Date(rest.startDate);

    try {
      // Subtasks: replace-all semantics. Simpler than diffing, fine at our scale.
      if (subtasks) {
        await db.subtask.deleteMany({ where: { taskId: req.params.id } });
        data.subtasks = {
          create: subtasks.map((s, idx) => ({
            title: s.title,
            done:  s.done,
            order: s.order ?? idx
          }))
        };
      }
      const updated = await db.task.update({
        where: { id: req.params.id },
        data: data as never,
        include: { subtasks: { orderBy: { order: "asc" } } }
      });
      return updated;
    } catch (err: unknown) {
      const code = (err as { code?: string })?.code;
      if (code === "P2025") return reply.notFound("Task not found");
      throw err;
    }
  });

  // DELETE /tasks/:id
  app.delete<{ Params: { id: string } }>("/tasks/:id", async (req, reply) => {
    try {
      await db.task.delete({ where: { id: req.params.id } });
      reply.code(204);
      return;
    } catch (err: unknown) {
      const code = (err as { code?: string })?.code;
      if (code === "P2025") return reply.notFound("Task not found");
      throw err;
    }
  });
}

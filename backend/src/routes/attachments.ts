import type { FastifyInstance } from "fastify";
import { db } from "../db.js";
import { hub } from "../realtime.js";
import { taskToDTO, attachmentToDTO } from "../dto.js";
import { mkdirSync } from "node:fs";
import { writeFile, unlink } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";

/// Multipart upload + listing + delete for task attachments. Files live on
/// disk under uploads/attachments/<uuid>.<ext> and are served via the static
/// route already registered at /uploads/.

const includeAll = {
  subtasks: { orderBy: { order: "asc" as const } },
  assignees: { include: { user: { select: { id: true, email: true, name: true } } } },
  attachments: { orderBy: { uploadedAt: "asc" as const } },
  tags: { select: { tagId: true } }
};

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

export async function attachmentRoutes(app: FastifyInstance) {
  app.addHook("onRequest", app.authenticate);

  const uploadsDir = path.resolve(process.cwd(), "uploads", "attachments");
  mkdirSync(uploadsDir, { recursive: true });

  // POST /tasks/:id/attachments — multipart, single file
  app.post<{ Params: { id: string } }>("/tasks/:id/attachments", async (req, reply) => {
    const me = req.user.sub;
    const task = await db.task.findUnique({ where: { id: req.params.id } });
    if (!task) return reply.notFound("Task not found");
    if (!(await userCanAccessTask(me, task))) return reply.forbidden();

    const file = await req.file();
    if (!file) return reply.badRequest("Нет файла");

    const original = file.filename || "file";
    const ext = path.extname(original) || "";
    const safeId = randomUUID();
    const storedName = `${safeId}${ext}`;
    const dest = path.join(uploadsDir, storedName);
    const buffer = await file.toBuffer();
    await writeFile(dest, buffer);

    const attachment = await db.attachment.create({
      data: {
        taskId:       task.id,
        filename:     original,
        mimeType:     file.mimetype || "application/octet-stream",
        sizeBytes:    buffer.length,
        storagePath:  `/uploads/attachments/${storedName}`,
        uploadedById: me
      }
    });

    // Broadcast updated task so all viewers refresh attachment list
    const updated = await db.task.findUnique({
      where: { id: task.id }, include: includeAll
    });
    if (updated) {
      const dto = taskToDTO(updated);
      const audience = await audienceForTask(updated);
      hub.broadcastToUsers(audience, {
        type: "task.updated", task: dto,
        originClientId: (req.headers["x-client-id"] as string | undefined) ?? null
      });
    }
    reply.code(201);
    return attachmentToDTO(attachment);
  });

  // DELETE /attachments/:id — only uploader OR task creator can delete
  app.delete<{ Params: { id: string } }>("/attachments/:id", async (req, reply) => {
    const me = req.user.sub;
    const att = await db.attachment.findUnique({ where: { id: req.params.id } });
    if (!att) return reply.notFound();
    const task = await db.task.findUnique({ where: { id: att.taskId } });
    if (!task) return reply.notFound();
    if (!(await userCanAccessTask(me, task))) return reply.forbidden();

    // Try to remove the underlying file (best-effort).
    const filePath = path.resolve(process.cwd(), "uploads", "attachments",
                                  path.basename(att.storagePath));
    try { await unlink(filePath); } catch { /* gone already */ }
    await db.attachment.delete({ where: { id: req.params.id } });

    // Broadcast updated task
    const updated = await db.task.findUnique({
      where: { id: task.id }, include: includeAll
    });
    if (updated) {
      const dto = taskToDTO(updated);
      const audience = await audienceForTask(updated);
      hub.broadcastToUsers(audience, {
        type: "task.updated", task: dto,
        originClientId: (req.headers["x-client-id"] as string | undefined) ?? null
      });
    }
    reply.code(204);
    return;
  });
}

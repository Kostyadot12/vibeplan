import type { FastifyInstance } from "fastify";
import { db } from "../db.js";
import { hub } from "../realtime.js";
import { spaceToDTO } from "../dto.js";
import { SpaceCreateInput, SpacePatchInput, SpaceInviteInput } from "../schemas.js";

const includeMembers = {
  members: { include: { user: { select: { email: true, name: true } } } }
};

export async function spaceRoutes(app: FastifyInstance) {
  app.addHook("onRequest", app.authenticate);

  // GET /spaces — spaces I'm a member of
  app.get("/spaces", async (req) => {
    const me = req.user.sub;
    const spaces = await db.space.findMany({
      where: { members: { some: { userId: me } } },
      include: includeMembers,
      orderBy: { createdAt: "asc" }
    });
    return spaces.map(spaceToDTO);
  });

  // POST /spaces — create new (I become owner + first member)
  app.post("/spaces", async (req, reply) => {
    const parsed = SpaceCreateInput.safeParse(req.body);
    if (!parsed.success) return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));

    const me = req.user.sub;
    const created = await db.space.create({
      data: {
        name:    parsed.data.name,
        color:   parsed.data.color,
        ownerId: me,
        members: { create: [{ userId: me, role: "owner" }] }
      },
      include: includeMembers
    });
    const dto = spaceToDTO(created);
    hub.broadcastToUsers([me], { type: "space.created", space: dto });
    reply.code(201);
    return dto;
  });

  // GET /spaces/:id — must be member
  app.get<{ Params: { id: string } }>("/spaces/:id", async (req, reply) => {
    const me = req.user.sub;
    const space = await db.space.findFirst({
      where: { id: req.params.id, members: { some: { userId: me } } },
      include: includeMembers
    });
    if (!space) return reply.notFound("Space not found or you're not a member");
    return spaceToDTO(space);
  });

  // PATCH /spaces/:id — owner only
  app.patch<{ Params: { id: string } }>("/spaces/:id", async (req, reply) => {
    const parsed = SpacePatchInput.safeParse(req.body);
    if (!parsed.success) return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));

    const me = req.user.sub;
    const space = await db.space.findUnique({ where: { id: req.params.id } });
    if (!space) return reply.notFound("Space not found");
    if (space.ownerId !== me) return reply.forbidden("Only the owner can rename/recolor a space");

    const updated = await db.space.update({
      where: { id: req.params.id },
      data:  parsed.data,
      include: includeMembers
    });
    const dto = spaceToDTO(updated);
    const memberIds = updated.members.map(m => m.userId);
    hub.broadcastToUsers(memberIds, { type: "space.updated", space: dto });
    return dto;
  });

  // DELETE /spaces/:id — owner only. Cascades to members & subtask rows;
  // tasks lose their spaceId via SetNull (become personal of the creator).
  app.delete<{ Params: { id: string } }>("/spaces/:id", async (req, reply) => {
    const me = req.user.sub;
    const space = await db.space.findUnique({
      where: { id: req.params.id },
      include: includeMembers
    });
    if (!space) return reply.notFound("Space not found");
    if (space.ownerId !== me) return reply.forbidden("Only the owner can delete a space");

    const memberIds = space.members.map(m => m.userId);
    await db.space.delete({ where: { id: req.params.id } });
    hub.broadcastToUsers(memberIds, { type: "space.deleted", id: req.params.id });
    reply.code(204);
    return;
  });

  // POST /spaces/:id/members — invite by email. Owner only.
  // If email isn't whitelisted yet, we add it (so invitations work without
  // a separate admin step). User is created lazily on first login.
  app.post<{ Params: { id: string } }>("/spaces/:id/members", async (req, reply) => {
    const parsed = SpaceInviteInput.safeParse(req.body);
    if (!parsed.success) return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));

    const me = req.user.sub;
    const space = await db.space.findUnique({ where: { id: req.params.id } });
    if (!space) return reply.notFound("Space not found");
    if (space.ownerId !== me) return reply.forbidden("Only the owner can invite");

    const email = parsed.data.email.trim().toLowerCase();

    // Auto-whitelist if not yet allowed.
    await db.allowedEmail.upsert({
      where:  { email },
      update: {},
      create: { email, role: "member", note: `invited to space ${space.name}` }
    });

    // Find user (may not exist yet — they'll be created on first login).
    const user = await db.user.findUnique({ where: { email } });
    if (!user) {
      // Persist a pending invite. On first login we'll resolve it into a
      // real SpaceMember row automatically.
      await db.pendingSpaceInvite.upsert({
        where:  { email_spaceId: { email, spaceId: req.params.id } },
        update: { role: parsed.data.role },
        create: { email, spaceId: req.params.id, role: parsed.data.role }
      });
      reply.code(202);
      return { invited: true, email, hasAccount: false, pending: true };
    }

    // Add to space (idempotent — upsert).
    await db.spaceMember.upsert({
      where:  { spaceId_userId: { spaceId: req.params.id, userId: user.id } },
      update: { role: parsed.data.role },
      create: { spaceId: req.params.id, userId: user.id, role: parsed.data.role }
    });

    // Notify all members the roster changed.
    const updated = await db.space.findUnique({
      where: { id: req.params.id },
      include: includeMembers
    });
    if (updated) {
      const dto = spaceToDTO(updated);
      const memberIds = updated.members.map(m => m.userId);
      hub.broadcastToUsers(memberIds, { type: "space.updated", space: dto });
      reply.code(201);
      return dto;
    }
    return { invited: true, email, hasAccount: true };
  });

  // DELETE /spaces/:id/members/:userId — owner can kick anyone, members can leave themselves.
  app.delete<{ Params: { id: string; userId: string } }>(
    "/spaces/:id/members/:userId",
    async (req, reply) => {
      const me = req.user.sub;
      const space = await db.space.findUnique({ where: { id: req.params.id } });
      if (!space) return reply.notFound("Space not found");

      const isOwner = space.ownerId === me;
      const isSelf  = req.params.userId === me;
      if (!isOwner && !isSelf) return reply.forbidden("Only owner or the member themselves");
      if (req.params.userId === space.ownerId) {
        return reply.badRequest("Owner cannot leave/be removed; delete the space instead");
      }

      try {
        await db.spaceMember.delete({
          where: { spaceId_userId: { spaceId: req.params.id, userId: req.params.userId } }
        });
      } catch (err: unknown) {
        const code = (err as { code?: string })?.code;
        if (code === "P2025") return reply.notFound("Member not in space");
        throw err;
      }

      const updated = await db.space.findUnique({
        where: { id: req.params.id },
        include: includeMembers
      });
      if (updated) {
        const dto = spaceToDTO(updated);
        // Notify remaining members + the kicked user
        const ids = [...updated.members.map(m => m.userId), req.params.userId];
        hub.broadcastToUsers(ids, { type: "space.updated", space: dto });
      }
      reply.code(204);
      return;
    }
  );
}

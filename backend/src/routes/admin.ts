import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { db } from "../db.js";

const AddEmailBody = z.object({
  email: z.string().email(),
  role:  z.enum(["admin", "member"]).default("member"),
  note:  z.string().max(200).default("")
});

export async function adminRoutes(app: FastifyInstance) {
  // GET /admin/allowed-emails
  app.get(
    "/admin/allowed-emails",
    { onRequest: [app.requireAdmin] },
    async () => {
      return db.allowedEmail.findMany({ orderBy: { invitedAt: "desc" } });
    }
  );

  // POST /admin/allowed-emails
  app.post(
    "/admin/allowed-emails",
    { onRequest: [app.requireAdmin] },
    async (req, reply) => {
      const parsed = AddEmailBody.safeParse(req.body);
      if (!parsed.success) return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
      const email = parsed.data.email.trim().toLowerCase();

      const allowed = await db.allowedEmail.upsert({
        where:  { email },
        update: { role: parsed.data.role, note: parsed.data.note },
        create: { email, role: parsed.data.role, note: parsed.data.note }
      });
      reply.code(201);
      return allowed;
    }
  );

  // DELETE /admin/allowed-emails/:email
  app.delete<{ Params: { email: string } }>(
    "/admin/allowed-emails/:email",
    { onRequest: [app.requireAdmin] },
    async (req, reply) => {
      const email = decodeURIComponent(req.params.email).trim().toLowerCase();
      try {
        await db.allowedEmail.delete({ where: { email } });
        reply.code(204);
        return;
      } catch (err: unknown) {
        const code = (err as { code?: string })?.code;
        if (code === "P2025") return reply.notFound("Email not in whitelist");
        throw err;
      }
    }
  );

  // GET /admin/users — list registered users
  app.get(
    "/admin/users",
    { onRequest: [app.requireAdmin] },
    async () => {
      return db.user.findMany({
        select: { id: true, email: true, name: true, role: true, createdAt: true },
        orderBy: { createdAt: "desc" }
      });
    }
  );
}

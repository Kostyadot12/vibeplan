import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { db } from "../db.js";
import { sendCode } from "../auth/mailer.js";
import {
  generateCode, hashCode, codeExpiresAt,
  CODE_TTL_MINUTES, MAX_ATTEMPTS
} from "../auth/codes.js";

const RequestCodeBody = z.object({ email: z.string().email() });
const VerifyBody      = z.object({
  email: z.string().email(),
  code:  z.string().regex(/^\d{6}$/, "Код должен быть из 6 цифр")
});

export async function authRoutes(app: FastifyInstance) {
  // POST /auth/request-code
  app.post("/auth/request-code", async (req, reply) => {
    const parsed = RequestCodeBody.safeParse(req.body);
    if (!parsed.success) return reply.badRequest("email обязателен");
    const email = parsed.data.email.trim().toLowerCase();

    // Whitelist check. We respond 200 even if email isn't whitelisted to avoid
    // exposing who's allowed in (no oracle), but skip sending code.
    const allowed = await db.allowedEmail.findUnique({ where: { email } });
    if (!allowed) {
      req.log.info({ email }, "request-code for non-allowed email — silently ignored");
      return { ok: true, ttlMinutes: CODE_TTL_MINUTES };
    }

    // Invalidate any pending codes for this email
    await db.verificationCode.updateMany({
      where: { email, consumed: false },
      data:  { consumed: true }
    });

    const code = generateCode();
    await db.verificationCode.create({
      data: {
        email,
        codeHash:  hashCode(code),
        expiresAt: codeExpiresAt()
      }
    });

    await sendCode({ email, code, log: req.log });
    return { ok: true, ttlMinutes: CODE_TTL_MINUTES };
  });

  // POST /auth/verify
  app.post("/auth/verify", async (req, reply) => {
    const parsed = VerifyBody.safeParse(req.body);
    if (!parsed.success) return reply.badRequest(parsed.error.issues.map(i => i.message).join("; "));
    const email = parsed.data.email.trim().toLowerCase();

    // Latest unconsumed code for this email
    const record = await db.verificationCode.findFirst({
      where: { email, consumed: false },
      orderBy: { createdAt: "desc" }
    });
    if (!record) return reply.unauthorized("Код не запрошен или уже использован");
    if (record.expiresAt < new Date()) {
      await db.verificationCode.update({ where: { id: record.id }, data: { consumed: true } });
      return reply.unauthorized("Срок действия кода истёк");
    }
    if (record.attempts >= MAX_ATTEMPTS) {
      return reply.unauthorized("Слишком много попыток. Запросите новый код.");
    }
    if (record.codeHash !== hashCode(parsed.data.code)) {
      await db.verificationCode.update({
        where: { id: record.id },
        data:  { attempts: { increment: 1 } }
      });
      return reply.unauthorized("Неверный код");
    }

    // ✓ Code matches — consume + upsert user
    await db.verificationCode.update({ where: { id: record.id }, data: { consumed: true } });

    const allowed = await db.allowedEmail.findUnique({ where: { email } });
    const role = (allowed?.role === "admin" ? "admin" : "member") as "admin" | "member";

    const user = await db.user.upsert({
      where:  { email },
      update: { role },
      create: { email, role }
    });

    const token = app.jwt.sign({
      sub:   user.id,
      email: user.email,
      role:  user.role as "admin" | "member",
      name:  user.name
    });

    return {
      token,
      user: { id: user.id, email: user.email, name: user.name, role: user.role }
    };
  });

  // GET /me
  app.get("/me", { onRequest: [app.authenticate] }, async (req) => {
    const u = await db.user.findUnique({ where: { id: req.user.sub } });
    if (!u) return { id: req.user.sub, email: req.user.email, name: "", role: req.user.role };
    return { id: u.id, email: u.email, name: u.name, role: u.role };
  });

  // PATCH /me — let users set their display name
  app.patch("/me", { onRequest: [app.authenticate] }, async (req, reply) => {
    const body = z.object({ name: z.string().max(80) }).safeParse(req.body);
    if (!body.success) return reply.badRequest("name обязателен");
    const u = await db.user.update({
      where: { id: req.user.sub },
      data:  { name: body.data.name }
    });
    return { id: u.id, email: u.email, name: u.name, role: u.role };
  });
}

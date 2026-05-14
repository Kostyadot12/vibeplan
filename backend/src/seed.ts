import { db } from "./db.js";

/**
 * Idempotent bootstrap that runs once on server startup.
 * - Ensures at least one admin email exists in the whitelist so the very first
 *   login can succeed without any out-of-band setup.
 */
export async function bootstrapSeed(log: { info: (...a: unknown[]) => void }) {
  const adminEmail = (process.env.BOOTSTRAP_ADMIN_EMAIL ?? "kos2cherdan@gmail.com")
    .trim().toLowerCase();

  const existing = await db.allowedEmail.findUnique({ where: { email: adminEmail } });
  if (existing) {
    log.info({ adminEmail }, "bootstrap: admin email already in whitelist");
    return;
  }

  // Don't auto-create the admin if other admins already exist — they might have
  // intentionally removed it.
  const adminCount = await db.allowedEmail.count({ where: { role: "admin" } });
  if (adminCount > 0) {
    log.info({ adminCount }, "bootstrap: at least one admin exists, skipping default");
    return;
  }

  await db.allowedEmail.create({
    data: { email: adminEmail, role: "admin", note: "bootstrap admin" }
  });
  log.info({ adminEmail }, "bootstrap: created default admin whitelist entry");
}

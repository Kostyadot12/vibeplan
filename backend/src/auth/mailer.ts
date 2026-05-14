import type { FastifyBaseLogger } from "fastify";

/**
 * Sends a 6-digit verification code to the given email.
 *
 * Dev / unset env: prints the code into the server log (so the developer
 * can grab it from the console — same pattern as /Andrew/platform).
 *
 * Prod: if RESEND_API_KEY is set, uses Resend's HTTP API. Failure falls back
 * to logging, so an outage doesn't strand the user without their code.
 */
export async function sendCode(opts: {
  email: string;
  code: string;
  log: FastifyBaseLogger;
}): Promise<void> {
  const { email, code, log } = opts;
  const apiKey = process.env.RESEND_API_KEY;
  const fromAddr = process.env.MAIL_FROM ?? "VibePlan <onboarding@resend.dev>";

  if (!apiKey) {
    log.info({ email, code }, "📨 verification code (dev: logged, no email sent)");
    return;
  }

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type":  "application/json"
      },
      body: JSON.stringify({
        from:    fromAddr,
        to:      [email],
        subject: `Код входа в VibePlan: ${code}`,
        text:    `Ваш код для входа: ${code}\n\nКод действует 10 минут.`,
        html:    renderHtml(code)
      })
    });
    if (!res.ok) {
      const body = await res.text();
      log.warn({ email, status: res.status, body }, "Resend failed, code logged as fallback");
      log.info({ email, code }, "📨 verification code (fallback log)");
    } else {
      log.info({ email }, "📨 verification code emailed via Resend");
    }
  } catch (err) {
    log.error({ email, err }, "Resend threw, code logged as fallback");
    log.info({ email, code }, "📨 verification code (fallback log)");
  }
}

function renderHtml(code: string): string {
  return `<!doctype html>
<html><body style="font-family:-apple-system,Inter,sans-serif;background:#f6f4f1;padding:32px;color:#1f1f1f;">
  <div style="max-width:480px;margin:0 auto;background:#fff;border-radius:16px;padding:32px;box-shadow:0 8px 32px -12px rgba(60,50,90,0.15);">
    <div style="font-size:13px;letter-spacing:0.6px;text-transform:uppercase;color:#777;margin-bottom:18px;">VibePlan</div>
    <div style="font-size:18px;font-weight:600;margin-bottom:8px;">Код для входа</div>
    <div style="font-size:13px;color:#555;margin-bottom:22px;">Введите этот код в окне входа VibePlan. Код действует 10 минут.</div>
    <div style="font-size:34px;font-weight:700;letter-spacing:8px;text-align:center;
                background:#f4f1f7;border-radius:12px;padding:18px;font-variant-numeric:tabular-nums;">${code}</div>
  </div>
</body></html>`;
}

import { createHash, randomInt } from "node:crypto";

export const CODE_TTL_MINUTES = 10;
export const MAX_ATTEMPTS = 5;

/** 6-digit numeric code, padded with leading zeros (e.g., "047382"). */
export function generateCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}

/** SHA-256 hex of the code. We never store plaintext codes. */
export function hashCode(code: string): string {
  return createHash("sha256").update(code).digest("hex");
}

export function codeExpiresAt(): Date {
  return new Date(Date.now() + CODE_TTL_MINUTES * 60_000);
}

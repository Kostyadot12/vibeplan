import type { FastifyInstance } from "fastify";

export async function healthRoutes(app: FastifyInstance) {
  app.get("/health", async () => ({
    ok: true,
    name: "vibeplan-backend",
    version: process.env.npm_package_version ?? "0.0.0",
    time: new Date().toISOString()
  }));
}

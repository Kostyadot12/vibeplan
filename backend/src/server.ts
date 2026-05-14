import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import sensible from "@fastify/sensible";
import jwt from "@fastify/jwt";
import { healthRoutes } from "./routes/health.js";
import { taskRoutes } from "./routes/tasks.js";
import { authRoutes } from "./routes/auth.js";
import { adminRoutes } from "./routes/admin.js";
import { registerAuthDecorators } from "./auth/jwt.js";
import { bootstrapSeed } from "./seed.js";

export async function buildServer(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: process.env.LOG_LEVEL ?? "info",
      transport: process.env.NODE_ENV === "production"
        ? undefined
        : { target: "pino-pretty", options: { translateTime: "HH:MM:ss", ignore: "pid,hostname" } }
    }
  });

  const origins = (process.env.ALLOWED_ORIGINS ?? "")
    .split(",").map(s => s.trim()).filter(Boolean);

  await app.register(cors, {
    origin: origins.length ? origins : true,
    methods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
  });
  await app.register(sensible);
  await app.register(jwt, {
    secret: process.env.JWT_SECRET ?? "dev-secret-change-me",
    sign:   { expiresIn: process.env.JWT_TTL ?? "30d" }
  });
  registerAuthDecorators(app);

  await app.register(healthRoutes);
  await app.register(authRoutes);
  await app.register(adminRoutes);
  await app.register(taskRoutes);

  await bootstrapSeed(app.log);

  return app;
}

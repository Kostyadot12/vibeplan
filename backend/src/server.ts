import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import sensible from "@fastify/sensible";
import { healthRoutes } from "./routes/health.js";
import { taskRoutes } from "./routes/tasks.js";

export function buildServer(): FastifyInstance {
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

  app.register(cors, {
    origin: origins.length ? origins : true,
    methods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
  });
  app.register(sensible);

  app.register(healthRoutes);
  app.register(taskRoutes);

  return app;
}

import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import sensible from "@fastify/sensible";
import jwt from "@fastify/jwt";
import websocket from "@fastify/websocket";
import multipart from "@fastify/multipart";
import staticServe from "@fastify/static";
import path from "node:path";
import { mkdirSync } from "node:fs";
import { healthRoutes } from "./routes/health.js";
import { taskRoutes } from "./routes/tasks.js";
import { authRoutes } from "./routes/auth.js";
import { adminRoutes } from "./routes/admin.js";
import { spaceRoutes } from "./routes/spaces.js";
import { attachmentRoutes } from "./routes/attachments.js";
import { commentRoutes } from "./routes/comments.js";
import { tagRoutes } from "./routes/tags.js";
import { activityRoutes } from "./routes/activity.js";
import { wsRoutes } from "./routes/ws.js";
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
  await app.register(websocket);
  await app.register(multipart, {
    limits: { fileSize: 10 * 1024 * 1024 }   // 10 MB per file
  });

  // Static serving for uploads (avatars, attachments, etc.)
  const uploadsDir = path.resolve(process.cwd(), "uploads");
  mkdirSync(path.join(uploadsDir, "avatars"),  { recursive: true });
  mkdirSync(path.join(uploadsDir, "attachments"), { recursive: true });
  await app.register(staticServe, {
    root: uploadsDir,
    prefix: "/uploads/",
    decorateReply: false
  });
  registerAuthDecorators(app);

  await app.register(healthRoutes);
  await app.register(authRoutes);
  await app.register(adminRoutes);
  await app.register(spaceRoutes);
  await app.register(taskRoutes);
  await app.register(attachmentRoutes);
  await app.register(commentRoutes);
  await app.register(tagRoutes);
  await app.register(activityRoutes);
  await app.register(wsRoutes);

  await bootstrapSeed(app.log);

  return app;
}

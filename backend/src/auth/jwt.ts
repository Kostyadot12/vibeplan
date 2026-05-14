import type { FastifyInstance, FastifyRequest, FastifyReply } from "fastify";

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: { sub: string; email: string; role: "admin" | "member"; name: string };
    user:    { sub: string; email: string; role: "admin" | "member"; name: string };
  }
}

declare module "fastify" {
  interface FastifyInstance {
    authenticate: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
    requireAdmin: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

export function registerAuthDecorators(app: FastifyInstance) {
  app.decorate("authenticate", async (req, reply) => {
    try {
      await req.jwtVerify();
    } catch {
      return reply.unauthorized("Invalid or missing token");
    }
  });

  app.decorate("requireAdmin", async (req, reply) => {
    try {
      await req.jwtVerify();
    } catch {
      return reply.unauthorized("Invalid or missing token");
    }
    if (req.user.role !== "admin") {
      return reply.forbidden("Admin role required");
    }
  });
}

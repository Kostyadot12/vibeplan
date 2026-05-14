import { buildServer } from "./server.js";

const app = buildServer();

const host = process.env.HOST ?? "0.0.0.0";
const port = Number(process.env.PORT ?? 4000);

app.listen({ host, port })
  .then(addr => {
    app.log.info(`VibePlan backend listening on ${addr}`);
  })
  .catch(err => {
    app.log.error(err);
    process.exit(1);
  });

// Graceful shutdown — important for Docker/systemd.
for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, async () => {
    app.log.info(`Received ${sig}, closing...`);
    await app.close();
    process.exit(0);
  });
}

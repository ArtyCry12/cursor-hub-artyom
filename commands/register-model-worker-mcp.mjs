import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const hub = join(dirname(fileURLToPath(import.meta.url)), "..");
const storePath = join(hub, "mcp.json.store");
const checkOnly = process.argv.includes("--check");
const modelWorker = {
  command: "node",
  args: [join(hub, "lib", "model-router", "mcp", "server.mjs")],
  env: {
    MODEL_ROUTER_STATE_ROOT: join(hub, ".cache", "model-router"),
  },
};

if (!existsSync(storePath)) {
  console.error("missing mcp.json.store");
  process.exit(1);
}

const store = JSON.parse(readFileSync(storePath, "utf8"));
if (!store.mcpServers || typeof store.mcpServers !== "object") {
  console.error("mcp.json.store has no mcpServers object");
  process.exit(1);
}

if (checkOnly) {
  const current = store.mcpServers["model-worker"];
  const valid =
    current?.command === modelWorker.command &&
    current?.args?.[0] === modelWorker.args[0];
  console.log(`MODEL_WORKER=${valid ? "registered" : "missing"}`);
  process.exit(valid ? 0 : 1);
}

store.mcpServers["model-worker"] = modelWorker;
const temporaryPath = `${storePath}.${process.pid}.tmp`;
writeFileSync(temporaryPath, `${JSON.stringify(store, null, 2)}\n`, "utf8");
renameSync(temporaryPath, storePath);
console.log("MODEL_WORKER=registered");
console.log("SECRET_VALUES=untouched");

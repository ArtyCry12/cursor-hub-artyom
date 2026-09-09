import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const here = dirname(fileURLToPath(import.meta.url));
const stateRoot = await mkdtemp(join(tmpdir(), "model-worker-test-"));
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [join(here, "server.mjs")],
  env: {
    ...process.env,
    MODEL_ROUTER_STATE_ROOT: stateRoot,
  },
  stderr: "pipe",
});
const client = new Client(
  { name: "model-worker-contract-test", version: "1.0.0" },
  { capabilities: {} },
);

try {
  await client.connect(transport);
  const tools = await client.listTools();
  assert.deepEqual(
    tools.tools.map((tool) => tool.name).sort(),
    ["delegate", "route_preview"],
  );
  const result = await client.callTool({
    name: "route_preview",
    arguments: {
      task: "Plan the architecture repository",
      ranks: "R2,R1.5",
      profile: "temporary-worker",
      stage: "planning",
    },
  });
  assert.equal(result.isError, false);
  const payload = result.structuredContent;
  assert.equal(payload.ok, true);
  assert.deepEqual(payload.route.allowedRanks, ["rank2", "rank1_5"]);
  assert.equal(payload.route.profile.id, "temporary-worker");
  assert.equal(JSON.stringify(payload).includes("OPENROUTER_API_KEY"), false);
  const toolStage = await client.callTool({
    name: "route_preview",
    arguments: {
      task: "Apply the patch and run tests",
      requiresCursorTools: true,
    },
  });
  assert.equal(toolStage.structuredContent.route.target, "cursor-parent");
  console.log("model-worker MCP contracts: ok");
} finally {
  await Promise.race([
    client.close(),
    new Promise((resolvePromise) => setTimeout(resolvePromise, 2000)),
  ]);
  await rm(stateRoot, { recursive: true, force: true });
}

process.exit(0);

import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const here = dirname(fileURLToPath(import.meta.url));
const hubRoot = resolve(here, "..", "..", "..");
const commandPath = join(hubRoot, "commands", "model-route.ps1");
const powerShell = process.platform === "win32" ? "powershell.exe" : "pwsh";
const rankPattern = /^(?:R?1[.,]5|R?2|R?3)(?:\s*,\s*(?:R?1[.,]5|R?2|R?3))*$/i;
const effortValues = new Set([
  "",
  "none",
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
]);

function validateArguments(args, inference) {
  if (!args || typeof args.task !== "string" || !args.task.trim()) {
    throw new Error("task is required");
  }
  if (args.task.length > 100_000) {
    throw new Error("task exceeds the 100000 character MCP limit");
  }
  if (args.ranks && !rankPattern.test(args.ranks)) {
    throw new Error("ranks must contain only R1.5, R2, and R3");
  }
  if (args.effort && !effortValues.has(args.effort)) {
    throw new Error("unsupported effort");
  }
  if (args.profile && !/^[a-z0-9][a-z0-9-]{0,63}$/.test(args.profile)) {
    throw new Error("invalid profile");
  }
  if (args.budgetUsd != null) {
    if (!Number.isFinite(args.budgetUsd) || args.budgetUsd < 0 || args.budgetUsd > 100) {
      throw new Error("budgetUsd must be between 0 and 100");
    }
  }
  if (
    inference &&
    args.unpricedConfirmed === true &&
    args.budgetUsd == null
  ) {
    throw new Error("unpricedConfirmed requires budgetUsd");
  }
  if (inference && args.requiresCursorTools === true) {
    throw new Error(
      "delegate cannot receive Cursor tools; split reasoning from tool execution",
    );
  }
}

function extractJson(stdout) {
  const lines = stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    try {
      return JSON.parse(lines[index]);
    } catch {
      // PowerShell may emit non-JSON diagnostics before the final JSON line.
    }
  }
  throw new Error(`model-route returned no JSON: ${stdout.slice(0, 500)}`);
}

async function runRouter(args, preview) {
  validateArguments(args, !preview);
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "model-worker-"));
  const promptPath = join(temporaryDirectory, "prompt.txt");
  await writeFile(promptPath, args.task, "utf8");
  const commandArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    commandPath,
    "-PromptFile",
    promptPath,
    "-Json",
    "-HubRoot",
    hubRoot,
  ];
  if (preview) commandArgs.push("-PreviewGlobal");
  if (args.ranks) commandArgs.push("-Rank", args.ranks);
  if (args.profile) commandArgs.push("-ProfileId", args.profile);
  if (args.stage) commandArgs.push("-Stage", args.stage);
  if (args.effort) commandArgs.push("-Effort", args.effort);
  if (args.cursorAvailable === false) {
    commandArgs.push("-CursorUnavailable", "1");
  }
  if (args.requiresCursorTools === true) {
    commandArgs.push("-RequiresCursorTools", "1");
  }
  if (args.budgetUsd != null) {
    commandArgs.push("-BudgetUsd", String(args.budgetUsd));
  }
  if (args.maxOutputTokens != null) {
    commandArgs.push("-MaxOutputTokens", String(args.maxOutputTokens));
  }
  if (args.sensitive === true) commandArgs.push("-Sensitive");
  if (args.structuredOutput === true) commandArgs.push("-StructuredOutput");
  if (args.creative === true) commandArgs.push("-Creative");
  if (args.unpricedConfirmed === true) commandArgs.push("-AllowUnpriced");

  try {
    const result = await new Promise((resolvePromise, rejectPromise) => {
      const child = spawn(powerShell, commandArgs, {
        cwd: hubRoot,
        windowsHide: true,
        shell: false,
        stdio: ["ignore", "pipe", "pipe"],
      });
      let stdout = "";
      let stderr = "";
      child.stdout.setEncoding("utf8");
      child.stderr.setEncoding("utf8");
      child.stdout.on("data", (chunk) => {
        stdout += chunk;
      });
      child.stderr.on("data", (chunk) => {
        stderr += chunk;
      });
      child.on("error", rejectPromise);
      child.on("close", (code) => {
        try {
          resolvePromise({
            code,
            data: extractJson(stdout),
            stderr: stderr.trim(),
          });
        } catch (error) {
          rejectPromise(
            new Error(`${error.message}; stderr=${stderr.slice(0, 500)}`),
          );
        }
      });
    });
    return result;
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

const commonProperties = {
  task: {
    type: "string",
    minLength: 1,
    maxLength: 100000,
    description: "The delegated reasoning task. Cursor retains all tools.",
  },
  ranks: {
    type: "string",
    description: "Optional allowed pool, for example R1.5,R2.",
  },
  profile: {
    type: "string",
    description:
      "Registered virtual profile such as ecosystem-architect or temporary-worker.",
  },
  stage: {
    type: "string",
    description: "Optional stage intent such as planning, review, or batch.",
  },
  effort: {
    type: "string",
    enum: ["none", "minimal", "low", "medium", "high", "xhigh", "max"],
  },
  cursorAvailable: {
    type: "boolean",
    description: "Whether native Cursor candidates can be recommended.",
  },
  requiresCursorTools: {
    type: "boolean",
    description:
      "Route this stage to the Cursor parent because files, shell, browser, or MCP tools are required.",
  },
};

const server = new Server(
  { name: "cursor-hub-model-worker", version: "1.0.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "route_preview",
      description:
        "Score Cursor and OpenRouter candidates without an inference call.",
      inputSchema: {
        type: "object",
        properties: commonProperties,
        required: ["task"],
        additionalProperties: false,
      },
    },
    {
      name: "delegate",
      description:
        "Delegate reasoning to the selected R1.5/R2/R3 OpenRouter worker. Cursor remains the tool executor.",
      inputSchema: {
        type: "object",
        properties: {
          ...commonProperties,
          budgetUsd: { type: "number", minimum: 0, maximum: 100 },
          maxOutputTokens: { type: "integer", minimum: 1, maximum: 131072 },
          sensitive: { type: "boolean" },
          structuredOutput: { type: "boolean" },
          creative: { type: "boolean" },
          unpricedConfirmed: {
            type: "boolean",
            description:
              "Set only after the user explicitly approved this unpriced model.",
          },
        },
        required: ["task"],
        additionalProperties: false,
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const name = request.params.name;
  if (name !== "route_preview" && name !== "delegate") {
    throw new Error(`Unknown tool: ${name}`);
  }
  try {
    const result = await runRouter(request.params.arguments ?? {}, name === "route_preview");
    const failed = result.code !== 0 || result.data.ok === false;
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(result.data, null, 2),
        },
      ],
      structuredContent: result.data,
      isError: failed,
    };
  } catch (error) {
    return {
      content: [{ type: "text", text: error.message }],
      isError: true,
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);

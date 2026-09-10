import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const hubRoot = path.resolve(here, "../..");
const routesPath = path.join(here, "routes.json");
const overridesPath = path.join(here, "capability-overrides.json");
const policyPath = path.join(here, "preflight-policy.json");
const outputPath = path.join(here, "capabilities.generated.json");

const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));

function resolveHubPath(value) {
  if (!value) return null;
  if (value.startsWith("~/") || value.startsWith("~\\")) {
    return path.join(os.homedir(), value.slice(2));
  }
  return path.resolve(hubRoot, value);
}

function frontmatterDescription(file) {
  if (!file || !fs.existsSync(file)) return null;
  const text = fs.readFileSync(file, "utf8");
  const match = text.match(/^---\s*\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return null;
  const block = match[1];
  const folded = block.match(
    /^description:\s*>-\s*\r?\n((?:[ \t]+.*(?:\r?\n|$))+)/m,
  );
  if (folded) {
    return folded[1]
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .join(" ");
  }
  const single = block.match(/^description:\s*(.+)$/m);
  return single ? single[1].trim().replace(/^["']|["']$/g, "") : null;
}

function descriptorExists(name) {
  if (!name) return false;
  const roots = [
    path.join(hubRoot, "projects", "empty-window", "mcps"),
    path.join(hubRoot, "projects", "c-Users-artyo-cursor", "mcps"),
  ];
  return roots.some((root) => fs.existsSync(path.join(root, name)));
}

function unique(values) {
  return [...new Set((values ?? []).filter(Boolean))];
}

function discoverCoreSkills() {
  const files = [];
  const roots = [
    path.join(hubRoot, "skills"),
    ...fs.existsSync(path.join(hubRoot, "blocks"))
      ? fs.readdirSync(path.join(hubRoot, "blocks"), { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => path.join(hubRoot, "blocks", entry.name, "skills"))
      : [],
  ];
  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
      if (!entry.isDirectory() || entry.name.startsWith("_")) continue;
      const skill = path.join(root, entry.name, "SKILL.md");
      if (fs.existsSync(skill)) {
        files.push(path.relative(hubRoot, skill).replaceAll("\\", "/"));
      }
    }
  }
  return files.sort();
}

function build() {
  const config = readJson(routesPath);
  const overrides = readJson(overridesPath);
  const preflight = readJson(policyPath);
  const warnings = [];
  const inactiveRoutes = config.routes
    .filter((route) => ["archived", "unrouted"].includes(route.status))
    .map((route) => ({ id: route.id, status: route.status }));

  const cards = config.routes
    .filter((route) => !["archived", "unrouted"].includes(route.status))
    .map((route) => {
    const overlay = overrides.intentOverlays[route.id] ?? {};
    const skillPaths = unique([route.skill, ...(route.skills ?? [])]);
    const skillInfo = skillPaths.map((skillPath) => {
      const absolute = resolveHubPath(skillPath);
      const excluded = skillPath.includes("/_archive/") ||
        skillPath.includes("/_quarantine/") ||
        skillPath.includes("\\_archive\\") ||
        skillPath.includes("\\_quarantine\\");
      const exists = Boolean(absolute && fs.existsSync(absolute));
      if (!exists) warnings.push(`missing skill: ${route.id} -> ${skillPath}`);
      if (excluded) warnings.push(`excluded tier skill: ${route.id} -> ${skillPath}`);
      return {
        path: skillPath,
        exists,
        excluded,
        description: exists ? frontmatterDescription(absolute) : null,
      };
    });
    const mcps = unique(route.mcp).map((name) => {
      const declared = (overrides.mcpProfiles ?? [])
        .find((entry) => entry.name === name);
      const descriptorAvailable = descriptorExists(name);
      if (!descriptorAvailable && !declared) {
        warnings.push(`unknown mcp: ${route.id} -> ${name}`);
      }
      return {
        name,
        descriptorAvailable,
        profile: declared?.profile ?? route.profile ?? null,
        owner: declared?.owner ?? null,
      };
    });
    const subagents = unique(route.subagent);
    const subagentInfo = subagents.map((name) => {
      const file = path.join(hubRoot, "agents", `${name}.md`);
      const fileExists = fs.existsSync(file);
      if (!fileExists && !(overrides.subagentTypes ?? []).includes(name)) {
        warnings.push(`unknown subagent: ${route.id} -> ${name}`);
      }
      return {
        name,
        file: fileExists
          ? path.relative(hubRoot, file).replaceAll("\\", "/")
          : null,
        description: fileExists ? frontmatterDescription(file) : null,
      };
    });

      return {
        id: route.id,
        kind: "route",
        owner: route.profile ?? "hub",
        label: route.label ?? route.id,
        mode: route.mode ?? "agent",
        keywords: unique(route.keywords),
        phrases: unique(route.phrases),
        tags: unique(route.tags),
        utterances: unique(overlay.utterances),
        actions: unique(overlay.actions),
        objects: unique(overlay.objects),
        contexts: unique(overlay.contexts),
        antiExamples: unique(overlay.antiExamples),
        allowNegatedActions: Boolean(overlay.allowNegatedActions),
        defaultStage: overlay.defaultStage ?? "clear-small",
        requiredActions: unique(overlay.requiredActions),
        prerequisites: {
          skills: skillPaths,
          mcps: mcps.map((mcp) => mcp.name),
        },
        cost: subagents.length ? "agent" : mcps.length ? "tool" : "local",
        risk: overlay.defaultStage === "high-risk" ? "high" : "normal",
        activation: {
          localConfidence: 0.58,
          explicitTags: unique(route.tags),
        },
        outputs: ["route", "required_actions", "receipt"],
        reportContract: ["system", "why", "evidence", "status"],
        skills: skillInfo,
        rule: route.rule ?? null,
        mcps,
        subagents,
        subagentInfo,
        commands: unique(route.commands),
        note: route.note ?? null,
      };
    });

  const capabilityIds = new Set(cards.map((card) => card.id));
  for (const id of Object.keys(overrides.intentOverlays)) {
    if (!capabilityIds.has(id)) warnings.push(`overlay without route: ${id}`);
  }
  const routedSkillPaths = new Set(
    cards.flatMap((card) => card.skills.map((skill) => skill.path.replaceAll("\\", "/"))),
  );
  const declaredUnrouted = new Set(
    (overrides.unroutedSkills ?? []).map((entry) => entry.path.replaceAll("\\", "/")),
  );
  const coreSkills = discoverCoreSkills();
  for (const skill of coreSkills) {
    if (!routedSkillPaths.has(skill) && !declaredUnrouted.has(skill)) {
      warnings.push(`orphan core skill: ${skill}`);
    }
  }

  const output = {
    version: 1,
    sourceVersion: config.version,
    policy: {
      minScore: config.minScore,
      maxRoutes: config.maxRoutes,
      skipIfShorterThan: config.skipIfShorterThan,
      localLatencyBudgetMs: 750,
      maxEphemeralAgents: 3,
    },
    language: {
      socialPatterns: overrides.socialPatterns,
      taskSignals: overrides.taskSignals,
      broadKeywords: overrides.broadKeywords,
      systemicSignals: overrides.systemicSignals,
      externalSignals: overrides.externalSignals,
      tradeoffSignals: overrides.tradeoffSignals,
      riskSignals: overrides.riskSignals,
    },
    preflight,
    cards,
    alwaysOn: overrides.alwaysOn,
    coreSkills,
    unroutedSkills: overrides.unroutedSkills ?? [],
    inactiveRoutes,
    drift: {
      warnings: unique(warnings).sort(),
    },
  };
  return `${JSON.stringify(output, null, 2)}\n`;
}

const generated = build();
if (process.argv.includes("--check")) {
  if (!fs.existsSync(outputPath)) {
    console.error("capability index missing");
    process.exit(1);
  }
  const current = fs.readFileSync(outputPath, "utf8");
  if (current !== generated) {
    console.error("capability index drift");
    process.exit(1);
  }
  const parsed = JSON.parse(current);
  const hardWarnings = parsed.drift.warnings.filter(
    (warning) => warning.startsWith("missing skill:") ||
      warning.startsWith("overlay without route:") ||
      warning.startsWith("excluded tier skill:") ||
      warning.startsWith("orphan core skill:") ||
      warning.startsWith("unknown mcp:") ||
      warning.startsWith("unknown subagent:"),
  );
  if (hardWarnings.length) {
    console.error(hardWarnings.join("\n"));
    process.exit(1);
  }
  console.log(`capability index ok: ${parsed.cards.length} routes`);
} else {
  fs.writeFileSync(outputPath, generated, "utf8");
  const parsed = JSON.parse(generated);
  console.log(
    `wrote ${path.relative(hubRoot, outputPath)} (${parsed.cards.length} routes, ${parsed.drift.warnings.length} warnings)`,
  );
}

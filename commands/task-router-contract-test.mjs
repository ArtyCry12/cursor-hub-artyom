import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveIntent, sanitizeSpan } from "../lib/task-router/router-core.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const hubRoot = path.resolve(here, "..");
const index = JSON.parse(
  fs.readFileSync(
    path.join(hubRoot, "lib", "task-router", "capabilities.generated.json"),
    "utf8",
  ),
);
const schema = JSON.parse(
  fs.readFileSync(
    path.join(hubRoot, "lib", "task-router", "route-decision.schema.json"),
    "utf8",
  ),
);

function resolve(prompt) {
  return resolveIntent(
    { prompt, source: "test", recordCandidate: false },
    index,
  );
}

function expectAction(prompt, action) {
  const result = resolve(prompt);
  assert.ok(
    result.requiredActions.includes(action),
    `"${prompt}" missing required action ${action}: ${result.requiredActions.join(",")}`,
  );
  return result;
}

const architecture = expectAction(
  "Продумай структуру системы и связи между частями",
  "architecture_plan",
);
assert.equal(architecture.stage, "systemic");
expectAction("Разложи работу на проверяемые этапы", "wbs");
expectAction("Поищи свежие официальные данные в интернете", "web_research");
expectAction("Пусть несколько агентов сравнят варианты", "llm_council");
expectAction("Выложи сайт в production", "risk_confirmation");
expectAction("Измени эту функцию безопасно", "gitnexus_freshness");

const ambiguous = resolve("Помоги нормально сделать эту штуку");
assert.equal(ambiguous.advisorRequired, true);
assert.ok(ambiguous.requiredActions.includes("route_advisor"));

const social = resolve("Привет");
assert.equal(social.social, true);
assert.equal(social.inject, false);
assert.equal(resolve("Да, клонируй лендинг конкурента").matches[0]?.Id, "clone-website");
assert.equal(resolve("Спасибо, всё понятно").social, true);
assert.equal(resolve("hello please audit the site").advisorRequired, true);
assert.equal(
  resolve("Используй R1.5 для планирования").matches[0]?.Id,
  "openrouter-free",
);
assert.equal(
  resolve("Выполни классификацию через R2").matches[0]?.Id,
  "openrouter-free",
);
const noClone = resolve("Без клонирования собери свой лендинг");
assert.equal(noClone.matches.some((match) => match.Id === "clone-website"), false);
const ownLanding = resolve("Сделай лендинг с нуля");
assert.equal(ownLanding.matches[0]?.Id, "from-scratch");
assert.equal(ownLanding.matches.some((match) => match.Id === "clone-website"), false);
assert.equal(
  resolve("Классический лендинг без клонирования").requiredActions
    .includes("gitnexus_freshness"),
  false,
);

assert.ok(index.cards.length >= 70);
assert.equal(index.drift.warnings.length, 0);
assert.equal(index.preflight.limits.maxEphemeralAgents, 3);
assert.equal(index.preflight.limits.nestedSpawn, false);

for (const required of schema.required) {
  assert.ok(
    Object.hasOwn(architecture, required),
    `route result missing schema field ${required}`,
  );
}
assert.ok(schema.properties.stage.enum.includes(architecture.stage));
for (const card of index.cards) {
  assert.ok(
    schema.properties.stage.enum.includes(card.defaultStage),
    `capability ${card.id} has unknown stage ${card.defaultStage}`,
  );
}

const unsafe =
  "email me@example.com password=hunter2 пароль: суперсекрет OPENROUTER_API_KEY=or-key-1234567890abcd token=sk-secretvalue123456789 https://private.test/path";
const safe = sanitizeSpan(unsafe);
assert.ok(!safe.includes("me@example.com"));
assert.ok(!safe.includes("sk-secretvalue"));
assert.ok(!safe.includes("private.test"));
assert.ok(!safe.includes("hunter2"));
assert.ok(!safe.includes("суперсекрет"));
assert.ok(!safe.includes("or-key"));
assert.ok(!safe.includes("$1"));
assert.ok(safe.includes("[email]"));
assert.ok(safe.includes("[secret]"));
assert.ok(safe.includes("[url]"));

const longPlanLatencies = Array.from({ length: 12 }, () =>
  resolveIntent(
    {
      prompt: "Проверь приложенный системный план",
      extraText:
        "Компонент имеет уникальную связь, архитектуру, риск и проверку. ".repeat(150),
      source: "test",
      recordCandidate: false,
    },
    index,
  ).latencyMs,
).sort((left, right) => left - right);
const longPlanP95 = longPlanLatencies[
  Math.ceil(longPlanLatencies.length * 0.95) - 1
];
assert.ok(
  longPlanP95 <= index.policy.localLatencyBudgetMs,
  `long plan p95 ${longPlanP95}ms exceeded budget`,
);

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "router-plan-contract-"));
try {
  const fakePlan = path.join(tempDir, "fake-plan.md");
  fs.writeFileSync(
    fakePlan,
    "# Цель\nФакты. Вариант. Решение. Архитектура. Риски.\n## E1\nverify: echo ok\n## Итоговый DoD\n",
  );
  const rejected = spawnSync(
    process.execPath,
    [path.join(hubRoot, "commands", "task-router-plan-contract.mjs"), fakePlan],
    { encoding: "utf8" },
  );
  assert.notEqual(rejected.status, 0, "fake one-item WBS passed plan contract");
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

console.log("task-router contracts: ok");

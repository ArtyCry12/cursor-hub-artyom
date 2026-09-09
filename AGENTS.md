<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **cursor-hub-artyom** (6263 symbols, 7278 relationships, 70 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/cursor-hub-artyom/context` | Codebase overview, check index freshness |
| `gitnexus://repo/cursor-hub-artyom/clusters` | All functional areas |
| `gitnexus://repo/cursor-hub-artyom/processes` | All execution flows |
| `gitnexus://repo/cursor-hub-artyom/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

## Token economy

**RTK** (shell) · **Caveman** (prose) · **Ponytail** (code YAGNI) — `rules/rtk-token-economy.mdc`, `rules/ponytail.mdc`, `skills/ponytail/`.

## Security Hub

Front door: `blocks/security/skills/security-hub/SKILL.md`. Library playbooks: `blocks/security/skills/cybersecurity/`. CI templates: `templates/security-ci/`. Scans: `commands/security-scan.ps1` (DAST/recon need `-Authorized`).

## Open Design

Скилл: `C:/Users/artyo/.cursor/blocks/design/skills/open-design/SKILL.md` (hub bridge: `skills/huashu-design` → open-design). Каталог templates: `blocks/design/skills/open-design/repo/`. Обновление: `powershell -File commands/ensure-open-design.ps1` · upstream https://github.com/nexu-io/open-design. Правило: `blocks/design/rules/open-design.mdc` (on-demand; mirrored into `rules/` for sync). Legacy `@huashu` → тот же скилл. Архив: `skills/_archive/huashu-design/`.

## Clone Website (AI Website Cloner)

Скилл: `C:/Users/artyo/.cursor/blocks/design/skills/clone-website/SKILL.md`. Шаблон Next.js: `blocks/design/skills/clone-website/template/`. Bootstrap: `node blocks/design/skills/clone-website/scripts/init-clone-project.mjs <dir>`. Триггеры: `@clone-website`, `/clone-website`. Требует **cursor-ide-browser** MCP.

## Memory stack (DEC-009)

Primary: **`user-memory` MCP** → **`AGENTS.md`** → **`ai-tracking/`** (Dev OS corpus). Route memory via parent agent + `blocks/dev-os/skills/dev-os`. Project Squad archived.

## 21st Design (21st.dev UI registry)

Скилл: `C:/Users/artyo/.cursor/blocks/design/skills/21st-design/SKILL.md`. Локальный каталог: `lib/21st/search_results.json` (обновление: `node blocks/design/skills/21st-design/scripts/ensure-library.mjs`). Триггеры: `@21st`, 21st.dev, Magic MCP `/ui`. MCP: **`21st`** → дескриптор `user-21st` (профиль `design`).

## Оркестрация MCP и скиллов

**Registry:** `SYSTEM-REGISTRY.md` · **Decision tree:** `rules/auto-orchestrator.mdc`

Лёгкое правило-оркестратор: `rules/00-agent-orchestrator.mdc`. Детали MCP — `rules/mcp-routing.mdc`. Синхрон rules: `python commands/cursor-sync-workspace-rules.py` (legacy shim: `huashu-sync-workspace-rules.py`). One-click refresh: `commands/cursor-system-refresh.cmd`.

Текст для **User Rules** (весь Cursor): `open-design-USER-RULES.txt` — компактный блок.

<!-- openrouter-free:start -->
## OpenRouter models (cost routing)

Canon: [`ai-tracking/openrouter-free.md`](ai-tracking/openrouter-free.md) · ladder [`ai-tracking/model-ladder.json`](ai-tracking/model-ladder.json) · engine `lib/model-router/ModelRouter.psm1` · MCP `model-worker` · command `commands/model-route.ps1` · health `commands/model-router-health.ps1`.

Key: Windows user env `OPENROUTER_API_KEY`. Do **not** Override OpenAI Base URL.

Explicit `R1.5/R2/R3` → Cursor-parent + MCP worker or terminal fallback. Allowed ranks are a pool. Local hard caps, circuit breaker, and verified R3 allowlist apply. OpenRouter workers have no Cursor tools. OpenCode is a future option only; do not install now.
<!-- openrouter-free:end -->

<!-- seo-geo-aio:start -->
## SEO + GEO + AIO block

Canon: [`ai-tracking/ecosystem-governance/blocks/seo-geo-aio/CHARTER.md`](ai-tracking/ecosystem-governance/blocks/seo-geo-aio/CHARTER.md) · route seo-geo-aio-block · skill `blocks/seo-geo-aio/skills/seo-geo/SKILL.md`.
<!-- seo-geo-aio:end -->

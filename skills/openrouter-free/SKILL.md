---
name: openrouter-free
description: >-
  Routes text and planning through OpenRouter R1.5/R2/R3 with live prices,
  model-specific reasoning effort, automatic budget caps, health history,
  and local fallback. Terminal fallback works independently of Cursor usage,
  but has no file tools. Never Override OpenAI Base URL.
---

# OpenRouter ranked model router

This is a local router, not a Cursor picker model. Do **not** enable Cursor Override OpenAI Base URL.

Key: Windows user env `OPENROUTER_API_KEY`. Never print it. Never write it into the repo.

SoT: `ai-tracking/model-ladder.json`. Runtime history: `ai-tracking/model-router-health.json`. Live prices and supported parameters must be refreshed from `GET /api/v1/models` before paid activation.

## When to run

An explicit `R1.5`, `R2`, or `R3` (including mixed pools) selects this router:

- Prefer MCP `model-worker` inside Cursor; keep Cursor as the tool parent.
- R1.5: planning — GLM 5.3, Grok 4.6, Qwen3.8 Max, Muse Spark.
- R2: paid workers — Luna Pro (`max` only), GLM 5.2, DeepSeek Pro/Flash, GLM Flash, Gemini Flash.
- R3: verified live `:free` text allowlist only.

OpenRouter workers never receive Cursor file, shell, browser, or MCP tools.

## Budget and effort

- Prefer MCP `model-worker` inside Cursor; keep Cursor as the tool parent.
- CLI flags `-RequiresCursorTools` / `-CursorUnavailable` accept bare presence, `1`/`0`, or `true`/`false`.
- Atomic local reserve + shared-key remainder; unpriced needs Boss yes.
- Usable text with reservation overrun returns `completed_with_budget_overrun` (session hard cap still fails).
- R3 uses verified allowlist; empty state is seeded from `lib/model-router/r3-allowlist.seed.json` when the slug is still in the live catalog.
- Native effort scale: `none/minimal/low/medium/high/xhigh/max`.
- Use the nearest supported effort and report any adjustment.
- Luna Pro always uses `max`.
- Before a paid call, calculate expected/worst stage, task, and session cost from live pricing.
- If pricing is calculable, apply an automatic local cap. If it is not, ask Boss and make no HTTP request.
- After each response, record `usage.cost`, reasoning/cache usage, and remaining session budget.
- `provider.max_price` limits the accepted token rate; it is not a session budget.
- The local cap is a conservative preflight stop. An absolute mid-response dollar cutoff requires an OpenRouter API-key spend limit.

Default provider policy: `require_parameters=true`, price sort, `data_collection=deny`; add ZDR only for sensitive tasks.

## Commands

```powershell
powershell -File commands/model-route.ps1 -Prompt "R1.5 plan this system" -DryRun
powershell -File commands/model-route.ps1 -Prompt "R2 classify these items" -Json
powershell -File commands/model-route.ps1 -PromptFile task.md -ExpectedStages 3 -ExpectedTasks 2
powershell -File commands/model-route.ps1 -Prompt "R1.5 audit" -Sensitive
powershell -File commands/model-router-health.ps1 -Json -RefreshCatalog
```

Legacy chat/TTS/STT contracts remain in `skills/openrouter-free/scripts/openrouter.ps1`. STT and legacy `-Tier mid` still require `-BossYes`.

## Health and fallback

- OpenRouter provider failover remains enabled.
- Cross-model fallback is local because each model needs its own effort profile.
- States: `unknown/live/degraded/unavailable/catalog-missing`.
- 429/403/5xx/protocol failures are historical evidence, not a permanent ban.
- A catalog-present model that returns 404 is `unavailable`, not deleted.

Current 2026-09-09 probe: eight paid models live; Qwen returned 404 (`unavailable`), Muse returned 403 (`degraded`). Keep both and recheck later.

## Cursor usage boundary

When Cursor Agent usage is exhausted, run `commands/model-route.ps1` in a terminal. It uses OpenRouter credits independently. It can return text, plans, analysis, or patches, but cannot apply files or run tools. If full post-limit coding is revisited, remind Boss that OpenCode was the first candidate; do not install it now.

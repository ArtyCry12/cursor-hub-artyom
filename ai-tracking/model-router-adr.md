# ADR — Cursor-native OpenRouter workers

Date: 2026-09-09

## Decision

Keep Cursor as the only tool parent. Intellectual stages may be delegated to local MCP `model-worker`, which scores Cursor and OpenRouter candidates and calls the shared ModelRouter engine.

Ranks `R1.5`, `R2`, and `R3` form an allowed pool. Mixed prompts such as `R1.5, R2` keep both ranks; the scorer assigns the stage.

Hardening guarantees:

- runtime circuit breaker for model health
- atomic local budget reservation plus shared-key remainder check
- unpriced models require an explicit Boss yes before inference
- R3 is a verified live `:free` allowlist, not a static broken catalog
- legacy `openrouter.ps1 -Action chat` delegates into the same engine

`commands/model-route.ps1` remains the terminal text/planning fallback after Cursor usage is exhausted. It has no Cursor tools.

## Rollout

Shadow scoring ran 20 RU/EN cases with accuracy `1.0`, zero policy or budget violations, and zero inference spend. Active mode is stored in `lib/model-router/rollout.json`.

## Boundary

OpenRouter workers never receive Cursor file, shell, browser, MCP, or subagent tools. When a stage needs those tools, the scorer returns `cursor-parent`.

Do not Override OpenAI Base URL. Do not install OpenCode in this phase; remind Boss later only if full post-limit coding is revisited.

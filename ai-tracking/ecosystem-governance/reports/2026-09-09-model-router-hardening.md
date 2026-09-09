# Model router workers + hardening — 2026-09-09

## Outcome

Cursor remains the parent. OpenRouter R1.5/R2/R3 workers enter through local MCP `model-worker`. Terminal `model-route.ps1` stays the post-limit text fallback.

## Commits on `feat/model-router-hardening`

1. `e9b8f70` baseline ranked router
2. `ec424f5` Cursor-native worker bridge
3. `f5f61e6` health/budget/fallback correctness
4. docs + shadow/Aikido receipts (this commit)

## Closed findings

| ID | Status |
|---|---|
| P1 health-aware fallback | closed — runtime circuit breaker + transport fallback tests |
| P1 legacy wrapper bypass | closed — ranked chat delegates to engine |
| P1 hard cap soft | closed — reserve/settle/rollback + overrun status |
| P1 dual ranks | closed — allowed-rank pool |
| P1 fallback role/quality/health | closed — scored candidates + Luna batch gate |
| P1 R3 broken | closed — verified allowlist; live `inclusionai/ling-3.0-flash-sante:free` |
| P1 baseline not in git | closed — isolated baseline commit |
| P2 hook auto OpenRouter | closed — MCP binding; active after shadow gate |
| P2 live metadata partial | closed — mandatory/default/supported efforts + max tokens |
| P2 claimed parameters | closed — structured output, creative temperature, deny-training |
| P2 incomplete accounting | closed — usage.cost, reasoning, cache read/write |
| P2 price calibration | closed — RU/byte estimator + model p95 calibration |
| P2 unknown price | closed — confirmation required before HTTP |
| P2 key error poisons model | closed — 401/402 stay on key health |
| P2 fragile classifier | closed — word-boundary RU/EN intents |
| P2 happy-path tests | closed — PS5/PS7/concurrency/legacy/MCP/hook/shadow |
| P3 telemetry drift | closed — final rank override logged once in UTC |

## Verification

- `model-router-contract-test.ps1` PS5 + PS7
- `model-router-concurrency-test.ps1`
- `model-router-legacy-contract-test.ps1`
- `task-router-contract-test.mjs`
- `task-router-hook-test.ps1`
- `lib/model-router/mcp` npm test
- shadow gate: 20/20, activeReady=true
- R3 capped smoke: 1 verified free model, 2 quarantined 404s

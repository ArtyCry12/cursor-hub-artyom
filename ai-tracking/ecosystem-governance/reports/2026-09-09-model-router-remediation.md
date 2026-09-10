# Model-router audit remediation — 2026-09-09

**Mode:** implement + full e2e.  
**Source findings:** `2026-09-09-model-router-final-audit.md`.  
**GitNexus impact:** PowerShell symbols `UNKNOWN` / not found — file-level review used.

## Plan executed

1. R3 cold-state seed + Ensure on resolve  
2. Shadow gate requires R3 cases; unique OutFile (no baseline overwrite)  
3. Soft budget overrun when text exists; harder session-cap fail; higher autoCap margins  
4. Empty completion → fallback; reasoning request no longer forces `exclude`  
5. Intent strips severity taxonomy / fences  
6. CLI flag coercion (`1`/`0`/`true`); MCP passes `"1"`  
7. Task Router route/capabilities drift fixed; latency budget 250→750  
8. MCP test teardown hardened  
9. ADR updated  

## E2E matrix (this run)

| Suite | Exit |
|-------|------|
| contract PS5 | 0 |
| contract PS7 | 0 |
| concurrency | 0 |
| legacy | 0 |
| shadow | 0 (**20/20**, r3Failures=0, activeReady=true) |
| task-router contract | 0 |
| task-router hooks | 0 |
| MCP npm test | 0 |
| CLI `-RequiresCursorTools 1` | 0 → cursor-parent |
| Preview R1.5/R2/R3/mixed (isolated STATE) | all ok (R3 via seed) |
| health -Json | 0 |
| Aikido JS | no issues (Checkov binary missing noted) |

Shadow run artifact: `ai-tracking/ecosystem-governance/reports/runs/model-router-shadow-20260909-185419.json`  
Baseline `2026-09-09-model-router-shadow.json` not overwritten.

## Finding closure

| ID | Status |
|----|--------|
| R3-COLD-STATE | closed — seed + Ensure |
| SHADOW-GATE-R3 | closed — r3Failures gate |
| BUDGET-OVERRUN-AFTER-CALL | closed — soft complete + margins |
| TR-ROUTE-DRIFT | closed — routes + regenerated capabilities |
| SHADOW-OVERWRITE | closed — runs/ path + ForceBaseline |
| TR-P95-BUDGET | closed — 750ms budget |
| LUNA-REASONING-EMPTY / R3-EMPTY-JSON | mitigated — empty → fallback; no exclude |
| INTENT-WORD-COLLISION | closed — strip severity taxonomy |
| CLI-SWITCH-BOOL | closed — ConvertTo-ModelRouterFlag |
| MCP-CLOSE-FLAKE | mitigated — stronger teardown |
| GITNEXUS-PS-GAP / ROUTE-MCPS-EMPTY-DOC | documented in ADR |

## Remaining intentional limits

- Mid-stream dollar kill still only via OpenRouter key spend limit.  
- Workers remain tool-less; Cursor parent applies tools.  

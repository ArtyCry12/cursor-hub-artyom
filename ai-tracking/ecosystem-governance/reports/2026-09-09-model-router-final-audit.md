# Model-router final deep-dive audit — 2026-09-09

**Mode:** analysis only (no product code fixes).  
**Branch:** `feat/model-router-hardening` (`e9b8f70` → `8c39027`).  
**Verdict:** экосистема в целом жива; R1.5/R2 preview, MCP, concurrency, legacy, hooks работают. **На момент аудита ошибки были найдены** (не пустой долг): highest open issues — **high**.

**Remediation:** все listed findings закрыты в [`2026-09-09-model-router-remediation.md`](2026-09-09-model-router-remediation.md) (e2e 20/20 shadow, suites green).

## Spend receipt (OpenRouter)

| Call | Rank / model | Result | actualUsd |
|------|----------------|--------|-----------|
| Architecture brief | R1.5 `x-ai/grok-4.6` | text returned; `budget_overrun` exit 3 | 0.037578 |
| Adversarial brief | R2 `openai/gpt-5.6-luna-pro` | empty text; reasoning-only; `budget_overrun` | 0.011614 |
| Triage brief | R3 `inclusionai/ling-3.0-flash-sante:free` | empty text; reasoning-only; ok | 0.000000 |
| **Total OR** | | under $1 cap | **≈ 0.049** |

Parent (inherit) ran all local suites and wrote this report.

## Suite matrix

| Suite | Exit | Notes |
|-------|------|-------|
| `model-router-contract-test.ps1` PS5 | 0 | ok |
| `model-router-contract-test.ps1` PS7 | 0 | ok (one harness terminal marked failed after print — process noise) |
| `model-router-concurrency-test.ps1` | 0 | 3 accepted, 0.09 USD reserved |
| `model-router-legacy-contract-test.ps1` | 0 | ok |
| `model-router-shadow-test.ps1` | 0 | 18/20, accuracy 0.9, `activeReady=true`; **R3 cases failed** in isolated STATE |
| `task-router-contract-test.mjs` | **1** | long plan p95 **618.3ms** > budget |
| `task-router-hook-test.ps1` | 0 | ok; `[MODEL ROUTE]` active wording |
| `lib/model-router/mcp` `npm test` | 0 | ok |
| Preview R1.5 / R2 / mixed / tools | 0 | expected targets; tools → `cursor-parent` |
| Preview R3 isolated STATE | fail code | `r3_text_unavailable` |
| Preview R3 prod `.cache` | 0 | `inclusionai/ling-3.0-flash-sante:free` |
| `model-router-health.ps1 -Json` | 0 | verifiedR3 present in prod cache |

Shadow default OutFile briefly overwrote `2026-09-09-model-router-shadow.json`; restored from HEAD (audit contamination cleanup, not a product fix).

## Ecosystem status

| Area | Status |
|------|--------|
| MCP `model-worker` in core/design/qa/ops | present |
| Hook Task Router + MODEL ROUTE | alive |
| Base URL override forbidden in rule | intact |
| OpenCode | future-only (intentional) |
| Secrets hardcode in MCP/CLI | none found |
| Profile path traversal guards | present (`..` + hub-root check) |
| Aikido JS receipt | clean (prior); not re-run this audit |
| GitNexus on router PS | low risk / weak PS symbol coverage (known limit) |
| Task Router `openrouter-free` route vs canon | **drift** (see findings) |

## Findings (parent final judgment)

### Critical

*None.* No secret leak, no Cursor tools on OpenRouter workers, no ledger double-spend observed in concurrency test.

### High

| ID | Evidence | Impact | Suggested fix (not applied) |
|----|----------|--------|-----------------------------|
| **R3-COLD-STATE** | Isolated `MODEL_ROUTER_STATE_ROOT` → `r3_text_unavailable`; prod `.cache/model-router/r3-allowlist.json` works | Fresh CI/machine/isolated tests break R3 while prod cache hides it | Seed allowlist in tests; document allowlist as required runtime artifact; fail R3 cases hard |
| **SHADOW-GATE-R3** | `activeReady = accuracy>=0.9` with 2/20 R3 fails still true | Active rollout gate can pass with broken R3 path | Require R3 cases pass (or explicit skip policy) before `activeReady` |
| **BUDGET-OVERRUN-AFTER-CALL** | Grok returned usable JSON but `ok=false` `budget_overrun` (actual 0.0376 > reserved 0.0233) | Caller sees failure despite paid successful generation; reservation undercounts reasoning | Tighten worst-case estimator / reserve from provider reasoning bounds; define settle semantics when text exists |

### Medium

| ID | Evidence | Impact | Suggested fix |
|----|----------|--------|---------------|
| **TR-ROUTE-DRIFT** | `routes.json` / `capabilities.generated.json`: `mcps=[]`, note terminal-centric, keyword `glm-5.2:free` vs live allowlist + MCP canon | Agents following route note skip MCP worker; stale free-model keyword | Update note/keywords; regenerate capabilities; keep `mcps=[]` for tool-less workers but document parent MCP ownership |
| **SHADOW-OVERWRITE** | Default OutFile = dated governance report | Audits mutate baseline evidence | Unique run id path; never overwrite baseline without `-Force` |
| **TR-P95-BUDGET** | Contract p95 618ms vs latency budget | Flaky/local machine regression signal | Raise budget with margin or isolate perf in separate non-blocking gate |
| **LUNA-REASONING-EMPTY** | Luna Pro `max` spent ~7.6k reasoning tokens, empty `text`, overrun | Adversarial R2 path can burn budget with no deliverable | Cap reasoning tokens; avoid Luna for structured JSON audits; fallback when completion empty |
| **R3-EMPTY-JSON** | Free R3 triage ok but empty text (reasoning-only) | Free triage unreliable for structured output | Prefer non-reasoning effort or structured_output / different verified free model |

### Low

| ID | Evidence | Impact | Suggested fix |
|----|----------|--------|---------------|
| **INTENT-WORD-COLLISION** | Briefs containing severity word `critical` steered `intent=critical` → Luna/Grok | Contaminates routing for meta-audits | Classifier should ignore severity taxonomies / code fences; word-boundary denser denylist |
| **CLI-SWITCH-BOOL** | `-RequiresCursorTools 1` fails; bare switch OK | Footgun for shell callers | Document switch-only; optional bool coercion |
| **MCP-CLOSE-FLAKE** | Historical hang after `ok`; this run exit 0 | Intermittent CI noise | Harder process teardown / timeout in `test.mjs` |

### Below-low

| ID | Evidence | Impact | Suggested fix |
|----|----------|--------|---------------|
| **GITNEXUS-PS-GAP** | detect_changes low; PS not indexed | Weak blast-radius signal | File-level inventory as SoT (already practiced) |
| **ROUTE-MCPS-EMPTY-DOC** | Empty `mcps[]` is correct if parent owns MCP | Confusion risk only | One ADR paragraph on parent vs worker |

### Intentional non-bugs (not debt)

- OpenRouter workers have no Cursor tools.
- Absolute mid-stream dollar kill only via OpenRouter key spend limit.
- Cursor chat model cannot be switched programmatically.
- Parent still consumes Cursor usage when orchestrating.

## Worker notes

- **R1.5** produced a useful findings JSON inside the response body despite `budget_overrun` (parent kept validated items, dropped inflated “critical” on mid-stream kill).
- **R2 / R3** empty-text outcomes recorded as defects above.
- Hybrid routing worked; budget stayed under $1.

## Bottom line

**Не «ошибок нет».** Core path for R1.5/R2 + MCP + hooks + budget race tests is healthy on this machine. Technical debt to clear next: R3 cold-start + shadow gate honesty, reservation overrun semantics, Task Router route/capabilities drift, shadow OutFile immutability, empty high-reasoning completions, and Task Router latency contract flake.

**No code changes applied** per audit plan.

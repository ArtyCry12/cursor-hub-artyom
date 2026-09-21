# GEO E2E evidence workflow (Hub)

Operating contract for reusable GEO/AEO evidence inside `blocks/seo-geo-aio`. Complements [`ai-search-optimization/SKILL.md`](../skills/ai-search-optimization/SKILL.md). Does not replace classic SEO.

Canonical knowledge: [`ai-search-2026.md`](ai-search-2026.md). Preflight: [`project-preflight.md`](project-preflight.md). Ledger: [`source-ledger.schema.json`](source-ledger.schema.json).

## Stages

1. **Project preflight** — brand, domain, locale, GSC/GA4 inputs, `seo/` dirs.
2. **Search-first gate** — collect organic/AIO/manual AI-answer evidence before asserting fan-out or citation claims.
3. **Fan-out notes** — subqueries (definitional / comparative / procedural / evaluative); mark coverage gaps.
4. **Source/chunk ledger** — candidate URLs, cited URLs, extractability flags, gap type, confidence.
5. **Brief handoff** — ledger rows → `seo/briefs/<slug>.md` → `geo-content-optimizer`.
6. **Measurement boundary** — crawler activity ≠ citation; referral ≠ recommendation; self-reported attribution closes the loop.

```text
preflight → search-first → fan-out + SERP notes → ledger → briefs → optimizer
                ↑                                         ↓
     hub ai-tracking/seo-signals/ ──normalize──→ project seo/evidence/
```

## Search-first gate

Do **not** write SERP/QFS/citation claims until at least one of:

| Evidence class | Acceptable sources | Confidence ceiling |
|----------------|--------------------|--------------------|
| `organic_serp` | Manual SERP notes, GSC queries, browser snapshot | high |
| `aio_block` | Manual AIO/AI Mode capture | high |
| `ai_answer_manual` | ChatGPT / Perplexity / Gemini / Claude (incognito) | medium |
| `model_memory_tracker` | `ai-visibility-tracker.mjs` **without** `--grounded` | low (memory only) |
| `grounded_tracker` | tracker with `--grounded` + paid entitlement | medium–high |

Reject as SERP evidence: ungrounded tracker output, model speculation, video percentage tables.

## Citation vs recommendation

| Metric | Meaning | Typical business value |
|--------|---------|------------------------|
| **Citation** | Own URL (or owned property) appears as a source/footnote | Visibility / report |
| **Recommendation** | Brand named as the solution to take | Demand / leads |

Record both. Prefer recommendation work when they conflict, but keep citation evidence for extractability fixes.

## Confidence levels

| Level | Rule |
|-------|------|
| `high` | Reproducible primary capture (SERP/AIO/browser) with date, query, locale |
| `medium` | Manual AI-answer or paid grounded tracker; platform + date recorded |
| `low` | Model-memory tracker, single anecdotal answer, or incomplete fan-out |
| `hypothesis` | External study / video claim without our capture — never promote to system rule |

Downstream briefs inherit the **lowest** confidence of their supporting ledger rows.

## Raw vs render (Wave 1)

Use `web-quality-audit` manually: raw HTTP/source text + browser snapshot. Flag commercial DOM bugs (CSS strikethrough prices, JS-only critical copy). Automatic diff is Wave 2 only.

## Persona boundary

`ai-citation-strategist` reads the **same** project ledger. It does not keep a parallel scorecard as source of truth.

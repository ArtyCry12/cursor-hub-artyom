# Content engine skeleton (SEO+GEO+AIO)

Capability target: programs of **1000+** supporting articles. This file is the **skeleton only**.

Evidence contracts: [`references/geo-e2e-workflow.md`](references/geo-e2e-workflow.md), [`references/project-preflight.md`](references/project-preflight.md), [`references/source-ledger.schema.json`](references/source-ledger.schema.json).

## Pipeline

```
seed topics / products
  → project preflight (brand, domain, locale, seo/ dirs)
  → search-first evidence + fan-out (ai-search-optimization)
  → source-chunk ledger → seo/evidence/
  → semantic clusters (keyword-research + content-gap)
  → brief per URL from ledger (intent, entities, links, GEO angle)
  → draft (seo-content-writer)
  → GEO pass (geo-content-optimizer + entity-optimizer)
  → publish gate (meta + schema + quality auditor)
  → index & monitor
```

## Artifacts (per project, not hub)

| Path | Content |
|------|---------|
| `seo/evidence/` | Normalized source-chunk ledgers (JSON per [`source-ledger.schema.json`](references/source-ledger.schema.json)) |
| `seo/clusters.json` | cluster → keywords → priority |
| `seo/briefs/<slug>.md` | one brief (fields below) |
| `seo/drafts/` | drafts |
| `seo/publish-queue.json` | status machine |
| `seo/monitor/` | measurement snapshots |

### Hub raw signals (not client canon)

`gsc-ga4-pull.mjs` and `ai-visibility-tracker.mjs` write to hub `ai-tracking/seo-signals/<slug>/`. Normalize into project `seo/evidence/` before briefing. See [`project-preflight.md`](references/project-preflight.md).

### Brief fields from ledger

Each `seo/briefs/<slug>.md` should carry:

- target prompt / query + fan-out subqueries
- gap type (`citation` / `competitor` / `topic`)
- cited competitor/source URLs
- own citation vs own recommendation flags
- chunk flags (extractable / BLUF / atomic) + confidence
- `ledger_ref` path to the evidence JSON entry id

`ai-citation-strategist` reads the same ledger; do not fork a second scorecard.

## Hub bootstrap

```text
node blocks/seo-geo-aio/skills/seo-geo/scripts/init-seo-geo-memory.mjs <project-root>
```

Then ensure `seo/evidence`, `seo/briefs`, and `seo/monitor` exist (preflight). `memory/*` from the script remains for research notes; durable GEO evidence lives under `seo/`.

## Batch controls

- Max parallel drafts: Architect / parent agent via `seo-geo` route (default 1–3)
- Human gate before publish on client domains
- Moldova locale defaults in briefs unless overridden

## Scale note

Mass generation is **opt-in per campaign**, not automatic on hub install.

## Funnel priority (normalized 2026-09-17, sources: Surfer/Rush/Diggity)

Порядок запуска — снизу воронки вверх, не «по списку keywords»:

1. **Money pages first** — product/service/pricing страницы, конвертирующие запросы. Без них трафик никуда не ведёт (типичная ошибка: 10 инфостатьей и ноль продаж).
2. **Один кластер за раз** — выбрать кластер, связанный с money page, достроить полный воронки-контент (commercial comparison → educational), интерлинк на money page. Закончить кластер до старта следующего. Распыление по 10 темам параллельно удлиняет выход на результаты: Google оценивает полноту покрытия funnel, не отдельные страницы.
3. **Curiosity-gap фильтр** для информационных запросов: избегать чистых определений («что такое X») — их закрывает AI Overview zero-click. Брать сравнения/решения/планирование («X vs Y», «как часто», «лучший для <ситуация>»), где обзор не закрывает потребность и клик остаётся.
4. **Извлекаемость** (GEO-проход): прямой ответ в первых предложениях, TL;DR, заголовки-вопросы, HTML-таблицы, alt-текст — чек-лист в `skills/ai-search-optimization/SKILL.md` (Workflow 4).

Draft pipeline без изменений; эти 4 правила применяются на шаге «brief per URL» и при выборе следующего кластера.

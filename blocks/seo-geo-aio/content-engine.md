# Content engine skeleton (SEO+GEO+AIO)

Capability target: programs of **1000+** supporting articles. This file is the **skeleton only**.

## Pipeline

```
seed topics / products
  → semantic clusters (keyword-research + content-gap)
  → brief per URL (intent, entities, internal links, GEO angle)
  → draft (seo-content-writer)
  → GEO pass (geo-content-optimizer + entity-optimizer)
  → publish gate (meta + schema + quality auditor)
  → index & monitor
```

## Artifacts (per project, not hub)

| Path idea | Content |
|-----------|---------|
| `seo/clusters.json` | cluster → keywords → priority |
| `seo/briefs/<slug>.md` | one brief |
| `seo/drafts/` | drafts |
| `seo/publish-queue.json` | status machine |
| `seo/monitor/` | snapshots |

## Hub bootstrap

```text
node skills/seo-geo/scripts/init-seo-geo-memory.mjs <project-root>
```

## Batch controls

- Max parallel drafts: Architect/squad-growth sets (default 1–3)
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

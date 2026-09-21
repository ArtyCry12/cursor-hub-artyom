---
name: ai-search-optimization
description: >-
  GEO/AIO operating skill — AI Overviews and ChatGPT/Gemini/Perplexity
  visibility: citation-gap audit, AI crawler policy, trust/consensus layer,
  GA4 AI traffic tracking, extractability (AIO reverse-engineering).
  Triggers: aeo, geo citations, llms.txt, @ai-search-optimization, ai visibility,
  ai traffic, query fan.
version: "2.1.0"
license: MIT
compatibility: cursor
metadata:
  author: hub
  source: dirnbauer/webconsulting-skills + 2026-09 deep-dive normalization
  upstream: "~/.agents/skills/ai-search-optimization"
  knowledge-base: "blocks/seo-geo-aio/references/ai-search-2026.md"
when_to_use: aeo_geo, citation_gap_audit, ai_crawler_policy, gbpp_consensus, ai_traffic_tracking
---

# AI Search Optimization (GEO/AIO operating skill)

Операционный скилл GEO/AIO-слоя блока `seo-geo-aio`. Отвечает за **аудит видимости, инфраструктуру краулинга и trust-сигналы** — не за написание контента.

## Boundary (кто за что отвечает)

| Задача | Куда |
|--------|------|
| Написание/переписывание контента под AI-цитирование | `library/build/geo-content-optimizer` (через `skills/seo-geo`) |
| Поисковая оптимизация страниц | `library/optimize/on-page-seo-auditor` |
| Аудит AI-видимости, краулеры, GBP/consensus, GA4 AI-traffic, извлекаемость | **этот скилл (`blocks/seo-geo-aio/skills/ai-search-optimization`)** |

Фактическая база: [../../references/ai-search-2026.md](../../references/ai-search-2026.md) — все утверждения сверены с источниками 2026; устаревшие тактики источников там помечены.

Evidence contracts (Wave 1):

- [../../references/geo-e2e-workflow.md](../../references/geo-e2e-workflow.md) — E2E stages, search-first, confidence, citation vs recommendation
- [../../references/project-preflight.md](../../references/project-preflight.md) — brand/domain/locale + `seo/` dirs + hub signals mapping
- [../../references/source-ledger.schema.json](../../references/source-ledger.schema.json) — machine-readable ledger

## Core model: три механизма GEO (складываются, не заменяют)

Нейросеть собирает ответ по трём независимым каналам; работа нужна по каждому:

1. **Real-time поиск** — при вопросе LLM идёт в обычный поисковик, берёт первые 15–20 страниц. Нет в SEO-топе → не существует для real-time ответов. Базовый слой: обычное SEO.
2. **AI Overviews / AI Mode** (встроенный ответ поисковика) — отбор по другим сигналам: прямой ответ в первом абзаце, структура заголовков, разметка, извлекаемость. Можно сидеть на позиции 3 и не попасть в AIO.
3. **Память модели** (training data) — ответ из того, что модель запомнила. Работает «шлейф упоминаний»: подборки, форумы, рейтинги, СМИ. Покупается только временем (месяцы консенсус-работы).

## Workflow 1: Citation-gap аудит (базовый вход)

Вход: домен/бренд + ниша после [`project-preflight.md`](../../references/project-preflight.md). Метод Burdukov × Diggity (Brand Radar опционально платный).

### Search-first gate

До утверждений про fan-out / SERP / citation собери хотя бы один primary capture (см. [`geo-e2e-workflow.md`](../../references/geo-e2e-workflow.md)). Ungrounded `ai-visibility-tracker` = только `model_memory_tracker` (confidence ≤ low), не SERP/QFS dataset.

### Citation vs recommendation

Фиксируй отдельно:

- **own_citation** — свой URL в источниках ответа;
- **own_recommendation** — бренд назван решением («бери X»).

Бизнесу обычно важнее recommendation; citation нужен для extractability / visibility отчётов.

**Автоматизация (self-host, free):**
- Запросы из GSC: `node blocks/seo-geo-aio/scripts/gsc-ga4-pull.mjs --site <URL> [--ga4]` — топ-запросы с кликами → кандидаты на проверку (нужен `GOOGLE_SERVICE_ACCOUNT_JSON` в secrets.local.json; setup — в шапке скрипта). Raw → hub `ai-tracking/seo-signals/<host>/`.
- Проверка ответов: `node blocks/seo-geo-aio/scripts/ai-visibility-tracker.mjs --brand "Бренд" --queries-file queries.txt --lang ru` — по умолчанию проверяет model-memory footprint без real-time поиска и пишет снапшоты в `ai-tracking/seo-signals/<brand>/` (нужен `GEMINI_API_KEY`; работает на free tier). Реальный Gemini Search grounding включается только явным `--grounded` и требует paid-tier entitlement; free-tier ключи возвращают `429`.
- Ручной путь без ключей: та же таблица заполняется руками (ниже)
- Нормализация: скопируй/сверни captures в project `seo/evidence/<date>-ledger.json` по [`source-ledger.schema.json`](../../references/source-ledger.schema.json)

1. **Fan-out декомпозиция** (после search-first): разбей 5–10 коммерческих запросов ниши на подзапросы (definitional, comparative, procedural, evaluative). Проверить: какие подзапросы сайт закрывает, какие нет.
2. **Возьми 10 запросов из GSC** (или из вывода `gsc-ga4-pull`), по которым реально приходят клиенты (не «красивые»).
3. **Проверь видимость**: задай каждый запрос в ChatGPT / Perplexity / Gemini / AI Mode (чистая сессия/incognito — модели подстраиваются под историю). Для бесплатного локального замера model-memory используй `ai-visibility-tracker.mjs`; для real-time/AIO grounding используй ручной путь или paid-tier `--grounded`. Фиксируй в ledger:
   - назван ли бренд (**recommendation**); кто назван вместо; какие **источники** цитируются (**citation**; бренд ≠ источник)
   - что говорят о конкурентах (цены, фичи, формулировки — это требования к твоей странице)
   - `evidence_class` + `confidence` (high/medium/low/hypothesis)
4. **Вердикты** (один из трёх):
   - «Не знает вообще» → нет шлейфа: нужна консенсус-работа (Workflow 3) + проверка краулинга (Workflow 2)
   - «Знает частично» (одна платформа знает, другая нет) → работают разные источники; работать с источниками каждой
   - «Помнит закрытую компанию» → шлейф есть, сайт не в источниках: извлекаемость + траст (Workflow 4)
5. Инструменты: вручную бесплатно; Ahrefs Brand Radar — платный аддон ($199+/мес, SOV vs конкуренты); Surfer AI tracker / Rush AI Tracker как альтернативы.

6. **Классифицируй gap**, чтобы fix pack был адресным:
   - **citation gap** — бренд упомянут, но собственный сайт/страница не является источником;
   - **competitor gap** — конкурент назван в ответе, бренд отсутствует;
   - **topic gap** — модель знает категорию, но не связывает бренд с нужной темой или use case.
   Сохраняй для каждого prompt в ledger: платформу, подзапросы fan-out, brands_named, sources_cited, own_citation, own_recommendation, chunk flags, gap_type, confidence, raw_ref.

## Workflow 2: AI crawler policy (robots.txt)

Краулеры 2026 (детали и источники — в knowledge-base):

| UA | Тип | Политика по умолчанию |
|----|-----|----------------------|
| GPTBot | training | стратегия (можно запретить без потери real-time видимости) |
| OAI-SearchBot | **search** | **разрешить** — иначе invisible в ChatGPT search |
| ChatGPT-User | user-triggered | разрешить |
| ClaudeBot | training | стратегия |
| PerplexityBot | **search** | **разрешить** |
| Google-Extended | policy-токен (не краулер!) | блокирует Gemini-тренинг, не поиск |
| Meta-ExternalAgent / Bytespider | training/aggressive | стратегия; Bytespider игнорирует robots.txt |

Правило: **search-краулеры не блокировать никогда**; training-токены — бизнес-решение. Проверка на клиенте: `robots.txt` не содержит блокировок ботов нейросетей по умолчанию (частая ошибка шаблонов — найдена в кейсе Rush Agency: сайт технически идеален, но для AI не существовал).

## Workflow 3: Trust / consensus слой (local-first)

Приоритет Moldova → EU → US (per CHARTER). LLM и AIO ищут консенсус из нескольких независимых источников:

1. **Google Business Profile**: claim+verify, все поля, описание 750 симв (ключевые первые 250), NAP единый формат везде, фото (профиль 250×250, cover 1080×608), отзывы — просить после успеха, отвечать на все, никогда не платить за отзывы.
2. **Third-party платформы** (consensus): Yelp / Trustpilot / TripAdvisor / Facebook / Bing Places / LinkedIn + нишевые (G2/Capterra для SaaS, Healthgrades для медицины, Houzz/Angi для home services). Claim, полное заполнение, дубли слить.
3. **Отзывы = машиночитаемый сигнал**: количество и рейтинг прямо коррелируют с попаданием в AIO-рекомендации (кейс Diggity: отель с 125 отзывами не рекомендован при 1300+ у конкурентов). Просить упомянуть конкретную услугу/сотрудника — даёт AI-friendly детали без скриптинга.
4. **E-E-A-T на сайте**: авторы с био и регалиями, сертификации/награды, кейсы и оригинальные данные, цитирование надёжных источников. Отзывы дублировать видимыми блоками на сайте.
5. **Digital PR / listicle-стратегия** (Neil Patel): попасть в подборки «top 10 <микрокатегория>» через сторонние источники — самоссылки не работают; это medium-срочная работа, не спам.

### External visibility tiers

Разделяй внешние сигналы по качеству и не имитируй консенсус:

1. **Editorial** — отраслевые публикации, честные обзоры, сравнения и подборки.
2. **Genuine UGC** — реальные ответы в Reddit, Quora, форумах и сообществах, где бренд упоминается по делу.
3. **Owned properties** — YouTube, LinkedIn, подкасты и другие собственные каналы с одинаковой entity-формулировкой.

YouTube — отдельный канал исследования: бери evergreen prompts из keyword/prompt research, делай search-hit видео с вопросом в title, первых строках description, spoken phrase, chapters и transcript. Это повышает доступность источника, но не гарантирует citation.

## Workflow 4: Извлекаемость (AIO reverse-engineering)

Для целевого запроса: открыть существующий AIO → что покрыто, как структурировано, кто процитирован → воспроизвести минимум + добавить unique value (данные, кейс, видео, сравнение уровней).

Чек-лист страницы:
- **Первые 1–2 предложения = прямой ответ** на запрос (Google берёт верх страницы)
- **BLUF (bottom line up front)**: начинай каждый самостоятельный блок с вывода, затем давай обоснование
- **Atomic sections**: каждый H2/H3-блок должен быть понятен без соседних абзацев, потому что AI извлекает фрагменты
- **Entity-rich writing**: называй конкретные бренды, продукты, роли, места и отношения между ними; избегай «этот сервис» без antecedent
- **Simple declarative writing**: одна мысль на предложение, прямой subject–verb–object порядок, без усложнённой вводной воды
- Один H1; H2 = секции/вопросы; H3 = подпункты
- TL;DR или Key Takeaways в начале
- Разговорные формулировки-вопросы в заголовках (не «15-минутная тренировка», а «какая быстрая 15-минутная тренировка дома без оборудования»)
- Без воды и clickbait: AIO предпочитает уверенный прямой тон («работает так же зимой») художественному («когда Земля остынет, свиньи полетят»)
- HTML-таблицы вместо картинок таблиц; alt-текст описательный (не keyword-stuffing); транскрипты к видео
- Schema: Article/BlogPosting, HowTo для инструкций. FAQPage — валидна, но rich results убраны Google (май 2026); ценность FAQ — в самих Q&A, не в разметке
- Curiosity-gap фильтр: определений («что такое X») избегать — AIO закрывает их zero-click; брать сравнения, решения, планирования («X vs Y», «как часто», «лучший для ситуации»)
- **Freshness**: `dateModified` ставь только после реального обновления; cadence выбирай по volatility темы и фиксируй в content brief. Не обновляй дату механически.

## Workflow 5: GA4 AI-traffic tracking

**Автоматизация:** `node blocks/seo-geo-aio/scripts/gsc-ga4-pull.mjs --site <URL> --ga4` — вытягивает нативный канал `ai-assistant` по источникам за окно (нужен SA-ключ + `GA4_PROPERTY_ID`; GA4 property → Property Access Management → добавить SA-email как Viewer). Без ключей — ручные шаги ниже.

1. С 13.05.2026 GA4 имеет **нативный канал `ai-assistant`** — проверить Reports → Acquisition → Traffic Acquisition.
2. Fallback/дополнение (referral, matches regex):
   ```
   chatgpt\.com|perplexity\.ai|claude\.ai|gemini\.google\.com|copilot\.microsoft\.com|grok\.com|meta\.ai
   ```
   (старый regex Diggity с neeva/writesonic/nimble — мёртвые источники, не использовать)
3. Pages & screens с тем же фильтром → какие страницы собирают AI-клики.
4. Клики из AIO лежат в Organic, не в referral — при анализе не смешивать.
5. Log-file анализ AI-краулеров (метод Diggity #3): access logs → фильтр UA (`gptbot|claudebot|perplexitybot|google-extended|oai-searchbot`) → какие страницы краулятся/игнорируются → orphan-страницы добить внутренними ссылками, 4xx починить, топ-крауляемые расширять. Для анализа можно скормить лог GPT-4o (промпты в knowledge-base).

### Measurement triad

- **AI referral traffic** — клики из ChatGPT/Perplexity/других источников; directional, потому что часть переходов теряет referrer.
- **AI crawler activity** — запросы search/training bots и ответы 2xx/4xx/5xx; это сигнал доступности, не доказательство citation.
- **Self-reported attribution** — вопрос `How did you hear about us?` в lead/signup/checkout flow; нужен, потому что AI-рекомендация часто превращается в branded Google search и теряется в organic attribution.

Проверяй также provider/WAF-слой: managed AI-crawler controls на CDN/хостинге могут переписать robots-политику. Это общий аудитный пункт; provider-specific инструкции остаются в проекте.

## Hub wiring

- Маршрут: `ai-search-optimization` в `lib/task-router/routes.json` (триггеры: aeo, llms.txt, ai overviews, perplexity, ai visibility, ai traffic, query fan)
- Правило: `blocks/seo-geo-aio/rules/seo-geo.mdc`
- knowledge-base: `blocks/seo-geo-aio/references/ai-search-2026.md`
- evidence: `blocks/seo-geo-aio/references/geo-e2e-workflow.md`, `project-preflight.md`, `source-ledger.schema.json`
- content-engine: `blocks/seo-geo-aio/content-engine.md`
- playbook миграции сайтов: `blocks/seo-geo-aio/playbooks/site-migration.md`
- llms.txt: генерировать можно, ждать эффекта не стоит — Google официально не использует (см. knowledge-base §5)

## Handoff

### Evidence → brief

Из каждой ledger entry с actionable gap создай `seo/briefs/<brief_slug>.md`:

| Brief field | From ledger |
|-------------|-------------|
| target query / prompt | `prompt` |
| fan-out subqueries | `fan_out` |
| gap type | `gap_type` |
| cited sources | `sources_cited` |
| citation vs recommendation | `own_citation`, `own_recommendation` |
| chunk / extractability | `chunk` |
| confidence | `confidence` (brief ≤ lowest supporting row) |
| ledger_ref | `seo/evidence/...#entry.id` |

Затем: `library/build/geo-content-optimizer` (через `skills/seo-geo`). Persona `ai-citation-strategist` читает тот же ledger — без параллельного scorecard.

### Report checklist

Фиксировать: вердикты citation-gap (по платформам), own_citation vs own_recommendation, источники-цитаторы, блокировки краулеров, NAP-проблемы, AI-traffic снапшот GA4, путь к `seo/evidence/` ledger. Альтернатива при пересборке сайта: `playbooks/site-migration.md`.
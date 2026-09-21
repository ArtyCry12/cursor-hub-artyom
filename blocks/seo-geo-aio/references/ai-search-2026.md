# AI Search 2026 — верифицированная база знаний

Нормализовано из 9 источников (7 YouTube-транскриптов + 3 кейс-стади Matt Diggity + 2 скриншота Nation Media) 2026-09-17. Каждый тезис сверен внешним фактчекингом (Exa, сентябрь 2026). Обновлять при существенных изменениях платформ.

Легенда: ✅ подтверждено · ⚠️ устарело/уточнено · ❌ опровергнуто · 🔶 мнение/частный кейс

## 1. Модель рынка

| Тезис | Статус | Актуальный факт |
|-------|--------|-----------------|
| «26% поиска без клика» (Neil Patel) | ⚠️ | Zero-click US 2026 = **68%** (SparkToro/Similarweb, янв–апр 2026; было 60.45% в 2024). sparktoro.com/blog/in-2026-less-than-one-third-of-google-searches-still-send-a-click |
| Google 5 трлн поисков/год | ✅ | Подтверждено (официально март 2025). searchengineland.com/google-5-trillion-searches-per-year-452928 |
| Instagram 6.5B поисков/день | 🔶 | Оценка NP Digital (Web Summit 2025), независимой проверки нет. Не использовать как опору |
| SEO ≠ GEO-конкурент | ✅ | AI-поиск построен на классическом индексе (ChatGPT → Bing index; Perplexity — свой краулер + Bing). SEO = фундамент GEO |

## 2. Три механизма GEO

| Тезис | Статус | Комментарий |
|-------|--------|-------------|
| Real-time: LLM берёт топ 15–20 обычного поиска | ✅ | Классическое SEO = входной билет |
| AIO: отбор по извлекаемости, не позиции | ✅ | Можно быть #3 и не попасть в AIO; прямой ответ в первом абзаце критичен |
| Память модели: шлейф упоминаний | ✅ | Подборки/форумы/СМИ; копится месяцами, не покупается пачкой |
| Query fan-out (запрос → веер подзапросов) | ✅ | Описан в официальной Google-документации (AI Optimization Guide) |

## 3. Краулеры и robots.txt

| Тезис | Статус | Актуальный факт |
|-------|--------|-----------------|
| GPTBot / ClaudeBot / PerplexityBot / Meta-ExternalAgent / Bytespider существуют | ✅ | Список UA актуален (nohacks.co/blog/ai-user-agents-landscape-2026) |
| Google-Extended = краулер | ⚠️ | Policy-токен (как Applebot-Extended): управление Gemini-тренингом, не краулинг. Google common crawlers: developers.google.com/crawling/docs/crawlers-fetchers/google-common-crawlers |
| Search-краулеры нельзя блокировать | ✅ | OAI-SearchBot, PerplexityBot — путь в real-time ответы |
| Bytespider уважает robots.txt | ❌ | Игнорирует; блокировка только на уровне firewall/WAF |
| Кейс Rush Agency: robots.txt блокировал AI-ботов по умолчанию | 🔶 | Реальный дефект шаблонов — проверять на каждом клиенте |

## 4. Schema и rich results

| Тезис | Статус | Актуальный факт |
|-------|--------|-----------------|
| FAQPage schema → rich results | ⚠️ | Rich results полностью убраны Google 07.05.2026 (лимит с авг 2023). Схема валидна — не удалять; подтверждённого эффекта на AI-цитирование нет (SE Ranking). Ценность в самих Q&A |
| Article/BlogPosting/HowTo schema полезна | ✅ | JSON-LD рекомендован Google; structured data НЕ обязателен для AIO, но улучшает понимание |
| Мультимодальность (alt-текст, транскрипты, HTML-таблицы вместо картинок таблиц) | ✅ | Официально: developers.google.com/search/docs/fundamentals/ai-optimization-guide («go beyond text») |

## 5. llms.txt

| Тезис | Статус | Актуальный факт |
|-------|--------|-----------------|
| llms.txt = важный SEO/GEO-инструмент | ❌ | Google официально (июнь 2026): не используем, «не поможет и не навредит»; Mueller приравнял к keywords meta. Adoption ~10% топ-доменов; 97% файлов никогда не фетчатся (Ahrefs). Реально читают: Cursor, Claude Code, IDE-агенты — полезно как документация для агентов, не как поисковый сигнал. baselinelabs.ai/blog/llms-txt-google-search |

## 6. Измерение

| Тезис | Статус | Актуальный факт |
|-------|--------|-----------------|
| GA4 regex Diggity (`neeva\|writesonic\|nimble\|outrider\|edgeservices...`) | ⚠️ | Мёртвые источники. Актуально: `chatgpt\.com\|perplexity\.ai\|claude\.ai\|gemini\.google\.com\|copilot\.microsoft\.com\|grok\.com\|meta\.ai` |
| Нативный GA4-канал AI | ✅ | С 13.05.2026 канал `ai-assistant` (medium). Ссылки из AIO остаются в Organic |
| Ahrefs Brand Radar | ✅ | Существует; платный аддон ($199/мес один индекс, $699 все платформы). SOV бренда vs конкуренты по 400M+ промптов |
| Log-file анализ AI-краулеров через GPT-4o | ✅ | Рабочий метод; промпты — в кейсе Diggity #3 |
| Gemini Search grounding на free-tier ключе | ❌ | Free-tier проекты не получают entitlement для `tools.google_search` и возвращают `429 RESOURCE_EXHAUSTED`. На paid-tier проектах действует отдельная квота (первые 5,000 Gemini 3 search requests/month включены по текущей документации). Ungrounded `gemini-3.5-flash-lite` остаётся рабочим бесплатным fallback для model-memory footprint; это не real-time visibility |

## 7. Официальные позиции Google

| Тезис | Статус | Источник |
|-------|--------|----------|
| Официальные рекомендации для AI-видимости существуют | ✅ | «AI Features and Your Website» + «AI Optimization Guide» + Search generative AI control (Search Console, глобально с 31.08.2026): developers.google.com/search/docs/appearance/ai-features |
| GBP влияет на AIO | ✅ | Google официально: держать Business Profile актуальным для AI features |
| Structured data обязателен для AIO | ❌ | Не обязателен; crawlability + текст + мультимедиа важнее |

## 8. Тактики источников — вердикты

### Принято в систему
| Тактика | Источник | Куда |
|---------|----------|------|
| Citation-gap аудит (10 запросов GSC × 3 платформы, таблица брендов/источников) | Burdukov (Rush) | SKILL Workflow 1 |
| Три механизма (real-time / AIO / память) | Burdukov + Diggity | SKILL Core model |
| GBP-чек-лист + NAP + отзывы как сигнал | Diggity #2 | SKILL Workflow 3 |
| Third-party консенсус (общие + нишевые каталоги) | Diggity #2 | SKILL Workflow 3 |
| Log-file анализ AI-краулеров | Diggity #3 | SKILL Workflow 5 |
| AIO reverse-engineering + curiosity-gap | Diggity #2 | SKILL Workflow 4 |
| Мультимодальность (alt, транскрипты, HTML-таблицы) | Diggity #3 | SKILL Workflow 4 |
| Миграция сайта 7 шагов | Rush Agency | playbooks/site-migration.md |
| Money pages → кластер за кластером | Surfer (7DRO) | content-engine.md |
| Evidence ledger + search-first + citation vs recommendation | GEO agent transcript wBMAATs2Yc0 | geo-e2e-workflow.md; source-ledger.schema.json; SKILL WF1/Handoff |
| Listicle-микрокатегории + digital PR | Neil Patel | SKILL Workflow 3 (medium-срок, без гарантий) |
| Linkable assets (free tools/calculators как магнит ссылок) | Surfer | Уместно при контент-стратегии; не автоматизация |
| GA4 AI-traffic + log-file | Diggity | SKILL Workflow 5 |
| Brand-gap taxonomy: citation / competitor / topic gap | AEO transcript | SKILL Workflow 1; operational classification, not a Brand Radar replacement |
| BLUF + atomic + entity-rich + simple declarative content pass | AEO transcript | SKILL Workflow 4; quality heuristic, not a ranking guarantee |
| Freshness cadence tied to topic volatility | AEO transcript + Diggity | SKILL Workflow 4; update dates only after real changes |
| External visibility tiers and YouTube search-hit channel | AEO transcript | SKILL Workflow 3; editorial/UGC/owned properties, no artificial seeding |
| Self-reported attribution | AEO transcript | SKILL Workflow 5; complements incomplete AI referral data |
| Provider/WAF AI-crawler control check | AEO transcript | SKILL Workflow 5; provider-agnostic audit point |

### Отфильтровано (не внедрять)
| Тактика | Причина отказа |
|---------|---------------|
| Legiit-сервисы: Reddit Traffic Hunter, GEO Quick Blast (100 listicles/72h), Web 3.0 backlinks, brand-mentions через own-accounts | Grey-hat манипуляции; противоречат non-goals CHARTER.md (no black-hat); признаки покупки консенсуса наказуемы платформами |
| llms.txt как приоритетная инфраструктура | Google официально игнорирует; держать как опциональный артефакт для IDE-агентов |
| Продажа «GEO-аудита за $19» | Ритуальные пакеты без методологии; методология у нас своя (Workflow 1) |
| «SEO умер» нарративы (Neil Patel 26%, ChatGPT-ads как данность) | Спекуляции; цифры устарели, ads-предсказания не проверяемы |
| Fan-out brief как платная услуга | Метод полезен, но тривиален для агента — делаем сами (SKILL Workflow 4) |
| AEO-video percentages/correlations (21%, 58%, 43.8%, 0.737, 25.7%, 89.7%, 76%) | В предоставленном материале нет воспроизводимой первичной методологии; использовать как исследовательские гипотезы, не как system rules |

## 9. Дубликаты источников (нормализовано)

Одна и та же идея в 2+ источниках:
- «SEO = фундамент GEO» — Surfer (7DRO), Burdukov, Diggity → SKILL Core model
- «Прямой ответ в первом абзаце» — Surfer, Diggity #2, Burdukov
- «Отзывы/консенсус решают» — Diggity #2, Burdukov, Neil Patel
- «Cluster → topical authority» — Surfer, Rush Agency (каталог-иерархия), Nation Media скриншот (content clusters +46%)
- «AI пишет черновик, человек добавляет опыт/данные/мнение» — Surfer, Neil Patel (анти-AI-slop)

## 10. Пересмотр

- Следующий чек: при изменении AI-ландшафта (новые каналы GA4, изменения AIO-доли, новые краулеры)
- Не обновлять по хайпу; триггер — официальная документация Google/Ahrefs или собственный тест
# 2026-09-17 — AI-Search deep-dive: интеграция SEO/GEO/AIO-материала

## Задача

Нормализовать пакет материалов (SEO / GEO / AI Search / Search Everywhere / контентная архитектура) в работающий слой системы без разрушения существующей архитектуры.

## Вход

- 7 транскриптов: Neil Patel (8 трендов 2026), Ahrefs «SEO с нуля», Surfer «SEO+AI за 50 мин» (7DRO4rEIHDk), Chris M. Walker Legiit (GIMC0-1HPfs), Rush Agency «идеальный сайт для SEO» (WLeS6ixH-mM, кейс BTX), Burdukov «что такое GEO» (3mXJzy_quRY), Matt Diggity AIO (4GBlHObjOrY)
- 3 кейс-стади Diggity Marketing: 2,300% AI traffic; +3.7x local GBP; +1,400% advanced (log files/schema/multimodal)
- 2 скриншота Nation Media (content clusters, +46% органического трафика за 6 мес)

## Аудит до изменений (explore-сабагент + вручную)

- Блок seo-geo-aio зрел: CORE-пак seo-geo (20 подскиллов, 4 фазы), 6 SECONDARY-обёрток, 4 команды, 3 playbook, governance-синхрон CHARTER.md подтверждён
- Роутинг: hooks/task-router.ps1 → Resolve-TaskRoute → routes.json (10 SEO-маршрутов)
- Пробелы: GBP-чек-листы, GA4 AI-traffic tracking, мониторинг AI-цитирования, playbook миграции
- Дефекты: устаревшая ссылка GOOGLE-STACK-LITE.md в правиле; знание llms.txt/AI-crawlers размазано по library-референсам

## Что внедрено (6 файлов + 1 конфиг)

| Файл | Действие |
|------|----------|
| `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md` | Перезаписан: тонкий wrapper → операционный GEO/AIO скилл (5 workflow: citation-gap, краулеры, trust/consensus, извлекаемость, GA4+логи) |
| `blocks/seo-geo-aio/references/ai-search-2026.md` | Новый: верифицированная база знаний (тезис → статус → актуальный факт → источник), принятые/отфильтрованные тактики |
| `blocks/seo-geo-aio/playbooks/site-migration.md` | Новый: 7-шаговый playbook миграции без потери трафика |
| `blocks/seo-geo-aio/content-engine.md` | + секция Funnel priority (money pages → кластер за раз → curiosity-gap → извлекаемость) |
| `blocks/seo-geo-aio/rules/seo-geo.mdc` | Убрана устаревшая ссылка на GOOGLE-STACK-LITE.md (файл существует, но ссылка не вела к актуальному контексту OAuth); в quick route добавлены ai-search-optimization и site-migration |
| `lib/task-router/routes.json` | +3 ключевых слова в существующий маршрут ai-search-optimization (ai visibility, ai traffic, query fan) — без новых маршрутов |
| `ai-tracking/ecosystem-governance/reports/` | Этот отчёт |

## Факт-чек (external, сентябрь 2026)

| Тезис источника | Вердикт |
|-----------------|---------|
| GA4 regex Diggity (neeva/writesonic/nimble/outrider) | Устарел → нативный канал `ai-assistant` с 13.05.2026; новый regex с claude/copilot/grok/meta |
| llms.txt как GEO-инструмент | Google официально не использует (июнь 2026); «не поможет и не навредит» |
| FAQ rich results | Полностью убраны Google 07.05.2026; FAQPage-схема валидна, эффекта на AI-цитирование не подтверждено |
| Zero-click 26% (Neil Patel) | Устарело → 68% (SparkToro 2026) |
| Google-Extended как краулер | Policy-токен, не краулер |
| Brand Radar бесплатный | Платный аддон $199+/мес |
| Ahrefs «SEO не конкурирует с AI» | Подтверждено |
| Query fan-out, официальные AI-рекомендации, GBP→AIO, мультимодальность | Подтверждены официальной документацией Google |

## Отфильтровано (не внедрено)

Legiit grey-hat сервисы (Reddit Traffic Hunter, GEO Quick Blast, Web 3.0 backlinks, brand-mentions через собственные аккаунты) — противоречат non-goals CHARTER.md. llms.txt-генератор — нет поискового эффекта. «GEO-аудит за $19»-пакеты — ритуальные без методологии.

## Что НЕ менялось (защита архитектуры)

- CHARTER.md (обе копии) — не тронут; синхрон-риск обойдён
- 20-скилловая library/ — чужой upstream (Apache-2.0), перезаписывается при обновлении zip'ом
- Ни одного нового route/skill/subagent — GEO-содержимое консолидировано в существующий маршрут
- seo-geo skill pack (aaron-he-zhu) не тронут; разграничение: library = написание контента, ai-search-optimization = аудит/видимость/инфраструктура

## Валидация

- task-router-test.ps1 прогнан; JSON routes.json валиден
- Grep-проверки ссылок между новыми файлами — без битых путей
- Независимая перепроверка сабагентом: целостность блока, отсутствие конфликтов маршрутизации — отчёт в конце сессии

## Следующий этап (не сделано сознательно)

- GA4/GSC авто-выгрузка AI-traffic — заблокирована до Google OAuth (как gsc-audit)
- Если появится клиентский контекст: снапшот citation-gap по реальным доменам валидирует Workflow 1 на практике

## Addendum (2026-09-17, вечер) — разблокировка GSC/GA4 + Brand Radar slot

Boss-решения: Service Account (не OAuth); платные инструменты исключены; Brand Radar-слот закрывается self-host + ручным методом.

| Что | Статус |
|-----|--------|
| `blocks/seo-geo-aio/scripts/gsc-ga4-pull.mjs` | Новый: GSC top-queries + GA4 `ai-assistant` канал; SA JWT-авт без npm-зависимостей; снапшоты в `ai-tracking/seo-signals/<host>/` |
| `blocks/seo-geo-aio/scripts/ai-visibility-tracker.mjs` | Новый: бесплатный ungrounded model-memory footprint tracker; `--grounded` оставлен как paid-tier опция, потому что free-tier ключи возвращают 429; замена слота Brand Radar с честной пометкой «simulated» |
| SKILL.md Workflows 1/5 | Обновлены: автоматизированные пути + ручной fallback |
| Правило (canon+зеркало) | GSC-блокировка снята (SA-путь), команды задокументированы |
| routes.json | `ai-search-optimization` + `google-workspace` маршруты ссылаются на скрипты |

**Почему не Brand Radar-замена 1:1:** Gemini grounding отдаёт один ответ на промпт без индекса 400M промптов и SOV-метрик. Даёт: дрейф видимости бренда по повторным снапшотам, источники-цитаторы, вердикты Workflow 1. Не даёт: SOV vs конкуренты, fan-out объём. Ручной метод Workflow 1 (ChatGPT/Perplexity/Gemini руками) остаётся обязательным дополнением.

**Квоты (перепроверено 2026-09-20):** GSC API бесплатен (1200 QPM/site, 25k rows/request); GA4 Data API бесплатен; Gemini Search grounding недоступен на free-tier ключах и возвращает 429; на paid-tier проектах текущая документация указывает 5,000 Gemini 3 search requests/month включёнными. Нулевой бюджет сохраняется только для ungrounded model-memory режима и ручных real-time проверок.

**Setup для Boss (когда понадобится):** SA-ключ вне репо → путь в `secrets.local.json` (gitignored) → SA-email в GSC Users + GA4 Viewer. Без ключей скрипты дают NO_KEY-подсказку и exit 2.
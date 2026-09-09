# OpenRouter models (hub) — канон

Искать в hub: этот файл · ladder [`ai-tracking/model-ladder.json`](model-ladder.json) · движок `lib/model-router/ModelRouter.psm1` · команда `commands/model-route.ps1` · health `ai-tracking/model-router-health.json` · ключи [`ai-tracking/KEYS-MAP.md`](KEYS-MAP.md).

Ключ: Windows user env `OPENROUTER_API_KEY`. Не в git. Не печатать. Не Override OpenAI Base URL.

## Источник правды

1. **`model-ladder.json`** — ранги, slug, роли и персональные effort-профили.
2. **OpenRouter `/api/v1/models`** — live цены, параметры, context и pricing overrides.
3. **`model-router-health.json`** — bounded runtime history без секретов.
4. Этот файл + SKILL + always-on + AGENTS — зеркала. При споре побеждает ladder + live catalog.

## Зачем

Явный `R1.5/R2/R3` отправляет text/planning в локальный OpenRouter router. Он рассчитывает effort и стоимость, ставит local cap и ведёт fallback. Это не Cursor Task и не даёт file/shell/browser/MCP tools.

## Rank 1.5 — planning

- `z-ai/glm-5.3` — default planning.
- `x-ai/grok-4.6` — adversarial/review.
- `qwen/qwen3.8-max-0902` — long-context/code architecture.
- `meta/muse-spark-1.2` — balanced synthesis.

## Rank 2 — paid workers

- `openai/gpt-5.6-luna-pro` — critical worker, только `max`.
- `z-ai/glm-5.2` — general worker.
- `deepseek/deepseek-v4-pro-0813` — strong worker.
- `deepseek/deepseek-v4-flash-0731`, `z-ai/glm-5.3-flash` — fast/batch.
- `google/gemini-3.8-flash` — multimodal fast.
- `microsoft/mai-transcribe-2` — legacy STT, `-BossYes`.

## Rank 3 — free (текст / TTS)

| Роль | Модель |
|------|--------|
| Текст primary | `z-ai/glm-5.2:free` |
| Текст + image/video in | `minimax/minimax-m3:free` |
| Текст + image/audio in | `thinkingmachines/inkling:free` |
| TTS | `fish-audio/s2.1-pro-free:free` |

Предпочтительный порядок: GLM → MiniMax → Inkling, но router пропускает отсутствующие в live catalog модели. На 2026-09-09 доступны только Inkling и TTS; GLM/MiniMax остаются кандидатами для будущей перепроверки.

## Effort и бюджет

Нативная шкала: `none/minimal/low/medium/high/xhigh/max`. Router читает supported efforts модели и выбирает ближайший допустимый. Thinking — часть `reasoning`, не второй независимый регулятор.

Цена обновляется перед paid activation. Receipt содержит expected/worst для этапа, задачи и сессии. Если расчёт возможен — local preflight cap. Если цена неизвестна — запрос бюджета и hard stop до HTTP. Фактическая цена берётся из `usage.cost`. Абсолютный dollar cutoff внутри уже начатого ответа возможен только через spend limit самого OpenRouter API key.

## Мультимодал

Понять файл через OR Rank 3 — только скрипт без тулов Cursor. Генерация фото/видео = Google Studio (отдельный контур). Не замена hub (Stitch, open-design, browser).

## Нет ключа / 401

- Стоп, сказать Boss; не печатать ключ.
- 401 относится к ключу, а не к model health.
- Ротация Windows User env + restart terminal/Cursor.

## Команды

```powershell
C:\Users\artyo\.cursor\commands\openrouter-free-test.cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\artyo\.cursor\commands\openrouter-free-test.ps1
powershell -File commands/model-route.ps1 -Prompt "R1.5 plan this" -DryRun
powershell -File commands/model-route.ps1 -Prompt "R2 classify this" -Json
powershell -File commands/model-router-health.ps1 -Json -RefreshCatalog
powershell -File skills/openrouter-free/scripts/openrouter.ps1 -Action ping
powershell -File skills/openrouter-free/scripts/openrouter.ps1 -Action chat -Prompt "..."
powershell -File skills/openrouter-free/scripts/openrouter.ps1 -Action tts -Prompt "..." -NoPlay
powershell -File skills/openrouter-free/scripts/openrouter.ps1 -Action stt -BossYes -AudioPath path.ogg
```

STT: JSON `input_audio` (base64 + format). Ogg/wav/mp3 ok. Parent may ffmpeg→temp wav if needed; do not mark STT `dead` for MIME/client skip.

## Health 2026-09-09

Metadata: 10/10 R1.5/R2 slugs present. Smoke: 8 live; Qwen 404 → `unavailable`; Muse 403 → `degraded`. Они остаются в ladder и перепроверяются. Единичная ошибка не создаёт permanent ban.

## После Cursor usage

При полном исчерпании Cursor Agent требует on-demand, upgrade или reset billing cycle; Auto не бесплатный fallback. `commands/model-route.ps1` продолжает text/planning через OpenRouter credits. Полноценные file tools отложены. Если обсуждение вернётся — напомнить про OpenCode; сейчас не устанавливать.

## Не путать

- Ask AI клиента NLMedia (платный OpenRouter PAYG) — другой контур.
- Google Studio ≠ `google/gemini-3.8-flash` на OpenRouter.

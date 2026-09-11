# OpenRouter models (hub) — канон

Искать в hub: этот файл · ladder [`ai-tracking/model-ladder.json`](model-ladder.json) · движок `lib/model-router/ModelRouter.psm1` · MCP `model-worker` · команда `commands/model-route.ps1` · runtime `.cache/model-router/` · ADR [`ai-tracking/model-router-adr.md`](model-router-adr.md) · ключи [`ai-tracking/KEYS-MAP.md`](KEYS-MAP.md).

Ключ: Windows user env `OPENROUTER_API_KEY`. Не в git. Не печатать. Не Override OpenAI Base URL.

## Источник правды

1. **`model-ladder.json`** — ранги, slug, роли и персональные effort-профили.
2. **OpenRouter `/api/v1/models`** — live цены, параметры, context и pricing overrides.
3. **`.cache/model-router/`** — circuit-breaker health, ledger, R3 verified allowlist (не коммитить шум вызовов).
4. Этот файл + SKILL + always-on + AGENTS — зеркала. При споре побеждает ladder + live catalog + runtime health.

## Зачем

Cursor остаётся родителем tools. Явный `R1.5/R2/R3` (включая пул `R1.5, R2`) идёт через MCP `model-worker` или terminal `model-route.ps1`. Scorer выбирает target/model/effort; OpenRouter-worker не получает file/shell/browser/MCP tools. Local atomic cap + shared-key remainder; unpriced — только после явного «да».

## Rank 1.5 — planning

- `z-ai/glm-5.3` — default planning.
- `x-ai/grok-4.6` — adversarial/review.
- `qwen/qwen3.8-max-0902` — long-context/code architecture.
- `meta/muse-spark-1.3` — balanced synthesis (18+ подтверждён; пока заблокирован аккаунтной ZDR-настройкой — recheck после изменения privacy).

## Rank 2 — paid workers

- `openai/gpt-5.6-luna-pro` — critical worker, только `max`.
- `z-ai/glm-5.2` — general worker.
- `deepseek/deepseek-v4-pro-0813` — strong worker.
- `deepseek/deepseek-v4-flash-0731`, `deepseek/deepseek-v4.1-flash`, `z-ai/glm-5.3-flash` — fast/batch.
- `google/gemini-3.8-flash` — multimodal fast.
- `microsoft/mai-transcribe-2` — legacy STT, `-BossYes`.

## Rank 3 — verified free text

R3 — динамический allowlist live `:free` text после smoke/quality/privacy gate. Пустой runtime state подхватывает [`lib/model-router/r3-allowlist.seed.json`](../lib/model-router/r3-allowlist.seed.json), если slug ещё есть в live catalog. Если после seed кандидатов нет → честный `r3_text_unavailable`.

На 2026-09-09 verified/seed text: `inclusionai/ling-3.0-flash-sante:free`. Кандидаты с 404 уходят в quarantine до half-open retry. Legacy TTS `fish-audio/s2.1-pro-free:free` остаётся отдельно через `openrouter.ps1 -Action tts`, не как ranked text worker.

## Effort и бюджет

Нативная шкала: `none/minimal/low/medium/high/xhigh/max`. Router читает supported efforts модели и выбирает ближайший допустимый. Thinking — часть `reasoning`, не второй независимый регулятор.

Перед paid call: reserve local budget (margin выше для high/max), проверить `GET /api/v1/key → limit_remaining`, согласовать `max_tokens` / reasoning bounds. Пустой `message.content` → fallback на следующего кандидата. Usable text при overrun reserve → `completed_with_budget_overrun` (жёсткий fail только если session spend > BudgetUsd). Unpriced → pending confirmation. Абсолютный dollar cutoff mid-stream — только spend limit ключа OpenRouter.

## Мультимодал

Понять файл через OR Rank 3 — только скрипт без тулов Cursor. Генерация фото/видео = Google Studio (отдельный контур). Не замена hub (Stitch, open-design, browser).

## Нет ключа / 401

- Стоп, сказать Boss; не печатать ключ.
- 401 относится к ключу, а не к model health.
- Ротация Windows User env + restart terminal/Cursor.

## Команды

```powershell
# Prefer MCP model-worker route_preview / delegate inside Cursor.
powershell -File commands/model-route.ps1 -Prompt "R1.5, R2 plan this" -DryRun
powershell -File commands/model-route.ps1 -Prompt "R2 classify this" -Json
powershell -File commands/model-router-health.ps1 -Json -RefreshCatalog
powershell -File commands/model-router-shadow-test.ps1
powershell -File commands/model-router-activate.ps1   # only after shadow gate
powershell -File skills/openrouter-free/scripts/openrouter.ps1 -Action ping
powershell -File skills/openrouter-free/scripts/openrouter.ps1 -Action chat -Prompt "..."
powershell -File skills/openrouter-free/scripts/openrouter.ps1 -Action tts -Prompt "..." -NoPlay
powershell -File skills/openrouter-free/scripts/openrouter.ps1 -Action stt -BossYes -AudioPath path.ogg
```

STT: JSON `input_audio` (base64 + format). Ogg/wav/mp3 ok. Parent may ffmpeg→temp wav if needed; do not mark STT `dead` for MIME/client skip. Ranked chat legacy path делегирует в ModelRouter.

## Health 2026-09-09

Circuit breaker: `closed/open/half-open` с TTL; 401/402 = key domain, не model ban. Shadow gate 20/20 → `lib/model-router/rollout.json` mode=`active`. Единичная ошибка не создаёт permanent ban.

## После Cursor usage

При полном исчерпании Cursor Agent требует on-demand, upgrade или reset billing cycle; Auto не бесплатный fallback. `commands/model-route.ps1` продолжает text/planning через OpenRouter credits. Полноценные file tools отложены. Если обсуждение вернётся — напомнить про OpenCode; сейчас не устанавливать.

## Не путать

- Ask AI клиента NLMedia (платный OpenRouter PAYG) — другой контур.
- Google Studio ≠ `google/gemini-3.8-flash` на OpenRouter.

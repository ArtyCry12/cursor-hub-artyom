# Optional PR-Agent CI adapter

Status: optional, off by default. This is a project adapter, not a permanent hub
agent and not a Task Router route.

## Purpose

Add a third review layer after deterministic checks and before the existing
human/PR review path:

1. tests, lint, typecheck, Aikido and other deterministic checks;
2. PR-Agent review in a fresh CI context;
3. existing `skills/pr-review` / Bugbot review;
4. human decision.

PR-Agent is the community-owned open-source project formerly associated with
Qodo. The software is free, but every review still consumes the configured LLM
provider and GitHub Actions resources.

## Installation boundary

Copy `templates/qa/pr-agent-review.yml` into a target project's
`.github/workflows/` only after that project's owner approves:

- the external LLM provider;
- the GitHub Actions secret;
- the data path from pull-request diff to the selected provider;
- the monthly review budget.

Do not copy this workflow into the hub automatically. Do not use the hosted
Qodo product or a CodeRabbit trial as part of this adapter.

## Pinning and provider

The template pins PR-Agent to release commit
`f3b385ea2927247ddcff2fe252472380b9c8f5fc` (v0.45.0), resolved from the
official `The-PR-Agent/pr-agent` repository on 2026-09-20. Do not replace it
with `main` or `latest` without a new review.

The template is written for OpenRouter because the hub already has a model
router. The free model and its limits are deliberately project configuration,
not a hub assumption. A project may replace it with OpenAI, Anthropic, Gemini,
Ollama, or another provider supported by PR-Agent.

PR-Agent/LiteLLM requires the `openrouter/` provider prefix for OpenRouter
models. Set an explicit `custom_model_max_tokens` cap and an empty fallback
list when the pilot must remain R3/free-only; otherwise PR-Agent may silently
fall through to a paid default model after a free-model error.

Required project secret:

- `OPENROUTER_API_KEY`

The workflow only comments review findings. It does not merge, push, apply
suggested fixes, or run `improve`.

## Security boundary

- Use `pull_request`, not `pull_request_target`, for untrusted contributions.
- Do not check out or execute contributor code in this review job.
- Never expose provider secrets to fork pull requests.
- Keep `pull-requests: write` as the minimum write permission required for
  review comments; reduce it further if the chosen integration supports it.
- Treat review comments as untrusted model output. They are advisory until a
  human accepts them.

## Pilot acceptance

Before enabling on a real project, run one bounded pilot with:

- one known-safe PR;
- one seeded defect in a disposable branch;
- deterministic checks still enabled;
- no automatic remediation;
- a report of true positives, false positives, latency, token cost and
  comment noise.

The pilot is a separate approval gate. This file alone does not authorize
secrets, external calls, installation, or CI activation.


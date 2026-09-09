# ADR — ranked OpenRouter sidecar

Date: 2026-09-09

## Decision

Use a hub-owned text/planning router for OpenRouter R1.5/R2/R3. Do not override Cursor's OpenAI Base URL. Do not install OpenCode or Aider in this phase.

`commands/model-route.ps1` is the independent terminal entry. It refreshes model metadata and prices, selects model-specific effort, calculates a local budget cap, calls OpenRouter, records actual cost, and applies local fallback.

## Boundary

The sidecar remains usable while the OpenRouter key has credits, even if Cursor subscription usage is exhausted. It does not receive Cursor file, shell, browser, MCP, or subagent tools. It can return text, plans, analysis, and proposed patches only.

Cursor Pro has separate Cursor Models and Other Models usage pools. When all applicable Agent usage is exhausted and on-demand is disabled, Agent requests stop until on-demand, upgrade, or billing-cycle reset. Auto is billed and is not a free reserve. OpenRouter is not an officially supported Cursor BYOK provider.

Sources checked 2026-09-09:

- https://cursor.com/help/models-and-usage/usage-limits
- https://cursor.com/help/account-and-billing/spend-limits
- https://cursor.com/help/models-and-usage/api-keys
- https://openrouter.ai/docs/guides/overview/models
- https://openrouter.ai/docs/guides/routing/model-fallbacks
- https://openrouter.ai/docs/guides/routing/provider-selection

## Future option

If Boss later requires full coding after Cursor usage is exhausted, remind them that OpenCode was the preferred first candidate because it supports Windows, OpenRouter, plan/build modes, LSP, terminal commands, and direct file editing. Re-evaluate it then; do not install it automatically.

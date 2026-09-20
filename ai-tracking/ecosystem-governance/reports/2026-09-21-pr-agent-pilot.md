# PR-Agent independent pilot — 2026-09-21

## Scope

Tested only a disposable private copy of the archived
`projects__flash-tokens-trust` snapshot. The original archive at
`C:\Users\artyo\_archive\2026-09\projects__flash-tokens-trust` was not edited.

Pilot repository:

- https://github.com/pateomdchatbot-spec/pr-agent-pilot-flash-tokens-20260921/pull/1
- Baseline was exported from archive `HEAD` `8aeaa0c449927e6b1ee486cbb64f1eab34df0eae`
- Architecture: Next.js frontend, Supabase, Telegram bot, smart-contract layer,
  production scripts and security-sensitive API routes

## Test design

The PR contained three seeded defects in separate security-sensitive files:

1. admin session authorization changed to unconditional `true`;
2. webhook signature condition inverted;
3. error object/stack exposed in an admin API response.

The PR description did not reveal the seeded defects. The expected findings were
kept as a test oracle outside the PR review context.

## Results

### PR-Agent 0.45.0 CLI

- Real PR fetched through GitHub API.
- OpenRouter R3 fallback model:
  `inclusionai/ling-3.0-flash-sante:free`.
- Found all 3 seeded defects:
  - admin auth bypass — critical;
  - inverted webhook signature — critical;
  - stack trace exposure — moderate.
- Added a security label and review summary.
- No fixes, merge, push or auto-remediation were performed.

### Independent R3 router pass

The separate `commands/model-route.ps1 -Rank R3` review received only the diff,
not the PR-Agent output. It independently found all 3 defects with high
confidence. Receipt reported `cost: 0`, model
`inclusionai/ling-3.0-flash-sante:free`.

## Model availability

Requested primary `qwen/qwen3.8-27b:free` was absent from the refreshed live
catalog and not in the verified R3 allowlist. It was not silently substituted.
The explicitly allowed R3 fallback was used.

## Integration findings

The first PR-Agent invocation exposed a real adapter hazard: without the
`openrouter/` LiteLLM provider prefix and explicit token cap, PR-Agent attempted
an unavailable model and then a paid fallback. The hub template now pins the
provider prefix, disables fallbacks, and caps tokens at 4096.

## Limitations

- GitHub Actions workflow was not executed because the current OAuth token lacks
  the `workflow` scope. The actual PR-Agent CLI path was tested instead.
- Aikido MCP was unavailable for the temporary pilot repository in this session;
  the seeded oracle and independent R3 review provided the second verification
  path.
- The disposable repository and PR remain for auditability. Deletion requires a
  separate explicit approval.


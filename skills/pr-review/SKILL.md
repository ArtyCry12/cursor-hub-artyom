---
name: pr-review
description: >-
  PR code review with confidence scoring (adapted from claude-plugins-official/code-review).
  Use for pull request review, /pr-review, pre-merge check. Requires gh CLI. Posts only
  issues scored >= 80. Complements squad-review and thermo-nuclear-review.
argument-hint: "[PR number or branch — optional]"
user-invocable: true
---

# PR Review (Cursor hub)

Adapted from Anthropic `code-review@claude-plugins-official`. **Read-only** until user approves `gh pr comment`.

## When to use

- User says: review PR, `/pr-review`, pre-merge, code review on branch
- After `squad-build`; before merge
- With open GitHub PR and authenticated `gh`

## Skip when

- PR closed, draft, trivial/automated, or already has your review comment
- No diff / no PR context

## Protocol

1. **Eligibility** (Haiku-tier or fast pass): closed? draft? trivial? already reviewed? → stop.
2. **Guidelines**: list paths to `AGENTS.md`, `CLAUDE.md`, and `CLAUDE.md` in dirs touched by PR (paths only first).
3. **PR summary**: `gh pr view` + `gh pr diff` — short change summary.
4. **Optional PR-Agent checkpoint** for a substantive GitHub PR:
   - Ask the user once: **«Подключить PR-Agent для дополнительной независимой проверки? Да/Нет»**.
   - Ask only for code/config changes with meaningful risk; skip docs-only, draft, trivial, and already-reviewed PRs.
   - **Нет** → continue this skill unchanged and do not ask again for the same PR in the current conversation.
   - **Да** → use an already configured project adapter or the optional template at
     `templates/qa/pr-agent-review.yml`. If the adapter/secret is missing,
     explain the exact setup needed and continue the local review; do not
     install workflows, request secrets, or activate external review silently.
   - PR-Agent output is advisory. Never auto-merge, auto-improve, or apply its
     suggestions without a separate human decision.
5. **Parallel review** (spawn `squad-review` or Task reviewers):
   - Compliance vs AGENTS.md/CLAUDE.md
   - Obvious bugs in diff only (no pre-existing nitpicks)
   - Git blame / history context for changed lines
   - Prior PR comments on same files
5b. **Optional dual fanout** (when Boss says `dual review` / high-risk PR):
   - Spawn two reviewer Tasks in parallel (e.g. GPT + Sonnet family via available Task models)
   - Merge issue lists; keep only items both agree on **or** single-reviewer score ≥ 90
   - Still filter final list to confidence **≥ 80** before reporting
   - Do **not** change `agents/*.md` model lines — fanout is protocol-only
5. **Confidence score** each issue 0–100:
   - **0** — false positive / pre-existing
   - **25** — maybe real
   - **50** — real but minor
   - **75** — important, verified in diff
   - **100** — certain, will break in practice
6. **Filter**: keep only **≥ 80**. If none → report "no high-confidence issues", do not comment.
7. **Post** (only after user OK for write): `gh pr comment` with brief markdown, file links, no emojis.

## Output format (chat)

```markdown
## PR review (confidence ≥ 80)

Found N issues:

1. [Issue] — score 85 — [reason: bug | guideline | history]
   `path:line`
```

## Squad integration

| Phase | Agent / skill |
|-------|----------------|
| Diff review | `squad-review` + this skill |
| Deep quality | `thermo-nuclear-code-quality-review` Task |
| Post comment | user confirms → `gh pr comment` |

## False positives (ignore)

- Pre-existing issues not introduced in PR
- Linter/typechecker will catch (imports, types, format)
- Pedantic style unless AGENTS.md explicit
- Issues silenced in code (`eslint-disable`, etc.)

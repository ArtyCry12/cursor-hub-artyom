---
name: qa-start
description: >-
  Hub wrapper for petrkindlmann qa-start — bootstrap QA from scratch (strategy,
  plan, automation pointers). Triggers: qa from scratch, setup qa, @qa-start.
version: "1.0.0"
license: MIT
compatibility: cursor
metadata:
  author: hub
  source: petrkindlmann/qa-skills
  upstream: "~/.agents/skills/qa-start"
when_to_use: qa_bootstrap, test_strategy_greenfield, no_qa_yet
---

# QA Start (hub wrapper)

Upstream: `C:/Users/Asus/.agents/skills/qa-start/SKILL.md`

## Read first

1. This wrapper
2. Upstream SKILL

## Routing note

- Project Squad verification is archived; use the active QA/review routes and
  ephemeral reviewers instead of restoring `squad-qa`
- Greenfield QA setup protocol → **this** skill
- Optional CI review layer → `blocks/qa/pr-agent-adapter.md` and
  `templates/qa/pr-agent-review.yml` (copy into a project only after approval;
  no automatic installation)

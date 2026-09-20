# Hub AEO evidence matrix — 2026-09-20

Scope: Cursor hub only. `projects/agency-site-prod` is explicitly out of scope.

Sources reviewed:

- `tactiq-free-transcript-58MR03s0ev8 - AEo скилл.txt`
- `tactiq-free-transcript-As2xy_cSx00 - реальные скиллы.txt`
- `tactiq-free-transcript-CkfEh20xyRM - пример проекта...txt`
- `tactiq-free-transcript-LVhravzgJNw - пример проекта...txt`
- `tactiq-free-transcript-y2ifYBDcHEg.txt`
- `End-to-End_Wazuh_NetAlertX_Grafana_Airia_Guide.pdf`

## Covered

| Idea | Existing destination |
|---|---|
| Query fan-out and conversational prompts | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 1 |
| Multi-platform citation baseline and lost-prompt analysis | `blocks/agency/rules/agency/ai-citation-strategist.mdc` |
| AI crawler policy and parseability foundations | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 2; `blocks/agency/rules/agency/aeo-foundations-architect.mdc` |
| Entity consistency, Organization/Person schema, sameAs | `blocks/agency/rules/agency/ai-citation-strategist.mdc`; `~/.agents/skills/entity-seo/SKILL.md` |
| Direct answer, headings, tables, schema, multimodal extraction | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 4 |
| Consensus, third-party sources, reviews, digital PR | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 3 |
| AI referral traffic and crawler logs | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 5 |
| Brand-gap taxonomy: citation / competitor / topic gap | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 1 |
| BLUF, atomic, entity-rich and simple declarative content pass | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 4 |
| Freshness cadence and honest `dateModified` policy | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 4 |
| External visibility tiers and YouTube search-hit channel | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 3 |
| Self-reported attribution and provider/WAF crawler-control check | `blocks/seo-geo-aio/skills/ai-search-optimization/SKILL.md`, Workflow 5 |
| Four-layer review principle: deterministic → AI review → CI → human | Existing `skills/pr-review`, Aikido rule, GitNexus rules, `ADVERSARIAL-REVIEW.md` |
| Optional PR-Agent CI adapter | `blocks/qa/pr-agent-adapter.md`, `templates/qa/pr-agent-review.yml` |
| Prompt-injection boundary, least privilege, audit trail, acceptance tests | `ADVERSARIAL-REVIEW.md`, security rules, and the Wazuh guide's operational pattern |

## Partial

| Idea | Gap |
|---|---|
| Independent CI review | Adapter/template exists, but activation and the bounded pilot remain approval-gated |

## Promoted into the hub

1. Brand-gap taxonomy as a small extension of Workflow 1, not a new skill.
2. BLUF/atomic/entity-rich/simple-declarative checklist as an addition to Workflow 4.
3. Freshness cadence and evidence of update as a content-quality signal.
4. Three tiers of external visibility plus YouTube search-hit research.
5. Self-reported attribution as a measurement fallback when AI referrals undercount.
6. Provider-agnostic WAF/AI-crawler-control check.
7. Optional Qodo PR-Agent CI adapter, outside always-on routing.

## Rejected or deliberately not promoted

- Hard-coded video statistics and correlations without a primary reproducible dataset.
- `llms.txt` as a ranking or citation requirement.
- WebMCP as an AEO mechanism; it is a separate agentic-task wave.
- Grey-hat Reddit/listicle/backlink placement.
- A new AEO skill, new permanent agent, new MCP, or project-document template.


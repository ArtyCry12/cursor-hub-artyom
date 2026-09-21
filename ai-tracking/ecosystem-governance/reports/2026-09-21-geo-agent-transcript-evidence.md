# GEO agent transcript evidence — 2026-09-21

Scope: Cursor hub only. Source: `tactiq-free-transcript-wBMAATs2Yc0.txt` («GEO АГЕНТ…»).

Related (do not merge): [`2026-09-20-hub-aeo-evidence-matrix.md`](2026-09-20-hub-aeo-evidence-matrix.md) covers earlier AEO/code-review packs.

## Pipeline stages (from video)

| Stage | What the pack does | Hub destination |
|-------|--------------------|-----------------|
| Project context bootstrap | Brand spellings, offer, locale, claims, constraints | [`project-preflight.md`](../../../blocks/seo-geo-aio/references/project-preflight.md); `project-context` + `user-memory` (project-only) |
| Accessibility / crawler audit | robots, sitemap, UA HTTP, bot bans, Cloudflare | `ai-search-optimization` WF2; `web-quality-audit` (manual) |
| Render vs raw | Screenshot + non-rendered text compare; commercial DOM bugs (strikethrough price) | Wave 1: manual via `web-quality-audit`; Wave 2 gate for automation |
| Fan-out / QFS | Subqueries from AI search → cluster → content plan | WF1 + [`geo-e2e-workflow.md`](../../../blocks/seo-geo-aio/references/geo-e2e-workflow.md) |
| SERP / AI overview parse | Top-N organic + AIO citations (XMLer in video) | Manual/GSC/browser in Wave 1; OpenSERP/XMLer = Wave 2 only |
| Source / chunk analysis | Candidate URLs vs cited URLs; extractable chunks | [`source-ledger.schema.json`](../../../blocks/seo-geo-aio/references/source-ledger.schema.json) |
| Content plan + ТЗ | Briefs for copywriter from fan-out themes | `seo/briefs/` via [`content-engine.md`](../../../blocks/seo-geo-aio/content-engine.md) |
| External placements | Where to get cited (listicles, UGC, owned) | WF3 external visibility tiers (no grey-hat) |
| Bot / referral monitoring | Bot logs dashboard; ChatGPT/Perplexity referrals | WF5 measurement triad; hub `ai-tracking/seo-signals/` raw → project ledger |

## Claims → classification

| Claim | Class | Hub action |
|-------|-------|------------|
| Citation (URL footnote) ≠ brand recommendation (named solution) | **Adopt** | Explicit metrics in ledger + SKILL |
| Fan-out creates machine demand layer (subtopics for pages/chunks) | **Adopt** | Search-first gate + fan-out fields in ledger |
| Classic SEO / SERP position is primary citation funnel | **Hypothesis** | Use as working model; no hard weight constants in rules |
| Fixed SERP-position → citation probability curves / engine share % | **Hypothesis / reject as rule** | Do not encode percentages; keep research-only |
| «SEO is dead» / rebrand classic work as GEO upsell | **Reject narrative** | Keep SEO as foundation (Core model #1) |
| AI referral traffic still tiny vs organic; goal = named solution | **Adopt framing** | WF5 + recommendation vs citation split |
| llms.txt / schema / entity magic as main GEO levers | **Reject as primary** | Schema/extractability stay supportive (WF4); llms.txt non-ranking |
| XMLer / paid SERP parsers required | **Defer** | Wave 2; free path = GSC + browser + Exa |
| Custom bot-visit dashboard | **Defer** | Use GA4/logs/Cloudflare when available; no hub dashboard yet |
| Project-local agent pack with skills/tools/raw data | **Reject import** | Reusable hub contracts only; no author pack copy |

## Promoted into hub (this wave)

1. Search-first gate before SERP/fan-out claims.
2. Source/chunk ledger schema + project `seo/evidence/` contract.
3. Citation vs recommendation metrics.
4. Evidence → `seo/briefs/` handoff into content-engine.
5. Project preflight (brand/domain/locale/GSC) without storing client canon in hub.
6. Hub `ai-tracking/seo-signals/` = raw automation; project ledger = normalized evidence.

## Explicitly not promoted

- Author project-pack / permanent GEO agent / new AEO skill / new MCP.
- XMLer, Grok, OpenSERP install in Wave 1.
- Hard-coded citation-probability tables.
- Grey-hat placements / bought consensus.
- Dashboard before stable snapshots.
- Auto render-vs-raw before Wave 2 gate.

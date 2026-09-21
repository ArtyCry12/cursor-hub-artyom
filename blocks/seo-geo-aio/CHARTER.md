# BLOCK: SEO + GEO + AIO

**Status:** active foundation (2026-08-25)  
**Priority market:** Moldova first → EU → US  
**Scale:** architecture supports 1000+ article programs; **no mass generation in this session**.

## Purpose

Replace ad-hoc SEO skill calls with one governed block that can run like an agency:

research → semantics → content strategy → on-page/tech → GEO/AIO visibility → GMB/Maps → monitoring → signals.

## Layers

| Layer | Role | Primary assets |
|-------|------|----------------|
| CORE | Default pack | `skills/seo-geo/` (+ library) |
| SECONDARY | Agency personas | `rules/agency/seo-specialist`, `ai-citation-strategist`, `aeo-foundations-architect`, `agentic-search-optimizer`, `baidu-seo-specialist` (as needed) |
| SECONDARY | Hub helpers | `entity-seo`, `programmatic-seo`, `seo-audit`, `ai-search-optimization`, `core-web-vitals`, `site-compliance-audit` |
| FALLBACK | Alternate pack | `opc-seo-geo` (keep routed; prefer seo-geo first) |
| Commands | Ops | `commands/seo-audit.ps1`, `seo-stack-verify.ps1`, `gsc-audit.ps1`, `pagespeed-audit.ps1` |
| Delivery | Parent agent | `seo-geo` / `ai-search-optimization` routes; Architect owns block health only |
| Evidence | GEO contracts | `references/geo-e2e-workflow.md`, `source-ledger.schema.json`, `project-preflight.md` |

## Router

- Primary route: `seo-geo` in `lib/task-router/routes.json`
- Block route alias: `seo-geo-aio-block` (added) → same skill + this charter
- Architect does **not** own client SEO delivery; it owns block health/routing

## Sub-blocks

1. **Research** — keywords, SERP, competitors, Reddit/social/news (MD/EU/US sources in playbooks)
2. **On-page / technical** — audits, schema, CWV, internal links
3. **GEO / AIO** — AI Overviews, citations, entity, llms.txt / agent discovery
4. **Local** — Google Business / Maps (MD-first checklists)
5. **Content engine** — semantics → briefs → batch pipeline skeleton (see `content-engine.md`)
6. **Monitoring** — rank/visibility signals; reports under project or governance reports/

## Playbooks

- [playbooks/moldova.md](playbooks/moldova.md)
- [playbooks/europe.md](playbooks/europe.md)
- [playbooks/usa.md](playbooks/usa.md)
- [content-engine.md](content-engine.md)

## Non-goals (this wave)

- Generating 1000 articles
- Buying links / black-hat
- Replacing live GSC credentials automation without user keys

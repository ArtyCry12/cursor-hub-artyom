# Project preflight (GEO evidence)

Run before fan-out / citation-gap work. Client facts live in the **project**, not as hub canon.

## Required inputs

| Field | Example | Where to store |
|-------|---------|----------------|
| Domain | `https://example.com` | project `CONTEXT.md` / brief |
| Brand + spelling variants | `Acme`, `ACME LLC`, `acme.com` | project context + ledger `brand` |
| Locale / market | `ru-MD`, Moldova | project context |
| Offer / constraints / banned claims | pricing rules, legal limits | project context |
| GSC property | Search Console site URL | secrets / SA access (not in git) |
| GA4 property id | optional | secrets |

Hub helpers (do not invent a second memory engine):

- `blocks/dev-os/skills/project-context` → glossary/`CONTEXT.md` in client repo
- `user-memory` MCP → durable decisions only after Boss confirmation
- `node blocks/seo-geo-aio/skills/seo-geo/scripts/init-seo-geo-memory.mjs <project-root>` → `memory/*` research notes

## Project directories

Create if missing (project root):

```text
seo/evidence/     # normalized source-chunk ledgers (JSON)
seo/briefs/       # briefs derived from ledger
seo/monitor/      # recurring measurement snapshots
seo/clusters.json # optional cluster map
seo/drafts/       # drafts
```

`init-seo-geo-memory.mjs` still creates `memory/*`. Mapping:

| Hub / memory artifact | Project evidence use |
|-----------------------|----------------------|
| `memory/research/` | Working notes; promote durable rows into `seo/evidence/` |
| `memory/audits/` | Audit narratives; cite paths from ledger |
| `memory/monitoring/` | Optional mirror of `seo/monitor/` summaries |

## Hub signals → project ledger

Automation scripts write **raw** snapshots under the hub:

| Script | Hub path |
|--------|----------|
| `gsc-ga4-pull.mjs` | `ai-tracking/seo-signals/<host>/` |
| `ai-visibility-tracker.mjs` | `ai-tracking/seo-signals/<brand-slug>/` |

**Contract:** hub signals are disposable instrumentation. For client work, normalize into `seo/evidence/<date>-ledger.json` conforming to [`source-ledger.schema.json`](source-ledger.schema.json). Do not treat hub `seo-signals/` as the client source of truth.

Normalization checklist:

1. Copy/query relevant rows (queries, platforms, brands named, sources).
2. Tag evidence class (`model_memory_tracker` vs `ai_answer_manual` vs `organic_serp`).
3. Set confidence per [`geo-e2e-workflow.md`](geo-e2e-workflow.md).
4. Link `raw_ref` to the hub snapshot path for auditability.
5. Leave PII and secrets out of the ledger.

## Ready gate

Preflight is done when domain, brand variants, locale, and `seo/evidence|briefs|monitor` exist, and the agent knows whether GSC/GA4 keys are available (else manual path).

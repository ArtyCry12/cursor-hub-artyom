# GEO evidence Wave 1 — fixture pilot + Wave 2 gate

Date: 2026-09-21  
Scope: Hub SEO-GEO-AIO evidence layer only. No live client domain.

## Fixture pilot

Command:

```text
node blocks/seo-geo-aio/scripts/validate-source-ledger.mjs
```

Result: **PASS** — `schema_version=1.0.0`, 2 entries.

Adversarial checklist (all OK):

- search-first rejects model_memory as SERP
- citation ≠ recommendation encoded in fixture
- hub `seo-signals` mapped, not treated as client canon
- no OpenSERP / XMLer / paid grounding used
- `model_memory_tracker` row kept at `confidence=low`

Synthetic brief sample (not written to a client repo):

- `patio-cleaning-vs-pressure-washing` ← entry `fx-001` (competitor gap, medium)
- `fixtureco-reviews-entity` ← entry `fx-002` (citation gap, low — memory only)

Live domain pilot: **blocked** until Boss supplies domain + GSC access. Not part of Wave 1 Done.

## Independent review notes

| Risk from re-verify | Status after Wave 1 |
|---------------------|---------------------|
| Wrong bootstrap path in content-engine | Fixed |
| Storage hub vs project | Documented in preflight + SKILL |
| Dual CHARTER drift | Both CHARTERs updated (squad → Delivery/Evidence) |
| Gemini grounding misuse | Gate + fixture confidence rule |
| Soft pilot domain | Closed as fixture-only |

## Wave 2 gate (decision)

Do **not** implement until live pilot succeeds:

| Candidate | Decision now | Revisit when |
|-----------|--------------|--------------|
| Unified SERP/QFS command | **Hold** | Live domain + repeated manual SERP notes prove friction |
| Auto raw-vs-render diff | **Hold** | Manual `web-quality-audit` insufficient on 2+ projects |
| OpenSERP / XMLer adapter | **Hold** | Boss approves paid/self-host parser; ToS/CAPTCHA reviewed |

Default until then: GSC + browser/Exa + ledger normalize.

## Aikido

Scanned: `blocks/seo-geo-aio/scripts/validate-source-ledger.mjs` (only new executable). Docs/JSON schema — N/A for SAST.

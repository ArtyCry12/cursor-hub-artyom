#!/usr/bin/env node
/**
 * ai-visibility-tracker.mjs — self-hosted replacement slot for Ahrefs Brand Radar.
 *
 * Runs citation-gap prompts (Workflow 1 of skills/ai-search-optimization) through
 * Gemini and records which brands + sources the model names. NOT the same
 * population as Brand Radar (400M prompt index, SOV).
 *
 * Two modes:
 *   default     — ungrounded (model memory / brand footprint, mechanism 3 of the
 *                 GEO model). Works on free tier.
 *   --grounded  — with Google Search tool (real-time visibility, mechanisms 1-2).
 *                 Requires PAID tier: free-tier keys get 429 RESOURCE_EXHAUSTED
 *                 the moment tools.google_search is set (verified 2026-09-18).
 *                 On paid-tier projects, the first 5000 search requests/month
 *                 are included; free-tier projects have no grounding entitlement.
 *
 * Setup (free):
 *   Get an API key at https://aistudio.google.com/apikey and add to
 *   ai-tracking/secrets.local.json:  "GEMINI_API_KEY": "..."
 *   (env GEMINI_API_KEY also works)
 *
 * Usage:
 *   node scripts/ai-visibility-tracker.mjs --brand "ACME" --queries "q1" --queries "q2" ...
 *   node scripts/ai-visibility-tracker.mjs --brand ACME --queries-file queries.txt
 *   # --lang ru (default en) prompt language; results persist as JSON snapshots
 *
 * Output: ai-tracking/seo-signals/<brand-slug>/ai-visibility-<date>.json + .md
 *   snapshot rows keep verdict history so repeated runs show drift over time.
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const HUB_ROOT = resolve(join(scriptDir, "..", "..", ".."));

const args = process.argv.slice(2);
function argAll(name) {
  const out = [];
  const parts = args;
  for (let i = 0; i < parts.length; i++) {
    if (parts[i] === `--${name}`) out.push(parts[i + 1]);
  }
  return out.filter(Boolean);
}
function arg(name, def) {
  const i = args.indexOf(`--${name}`);
  return i > -1 ? args[i + 1] : def;
}
const has = (f) => args.includes(`--${f}`);

const BRAND = arg("brand");
let QUERIES = argAll("queries");
const QUERIES_FILE = arg("queries-file", "");
const LANG = arg("lang", "en");
const MODEL = arg("model", "gemini-3.5-flash-lite");
const GROUNDED = has("grounded");

if (has("help") || has("h") || !BRAND) {
  console.log(`Usage: node ai-visibility-tracker.mjs --brand "ACME" (--queries "q1" --queries "q2" | --queries-file f.txt) [--lang en|ru] [--model gemini-3.5-flash-lite] [--grounded]
Requires GEMINI_API_KEY in ai-tracking/secrets.local.json or env.
Default: ungrounded (model memory / brand footprint check) — works on free tier.
--grounded: real-time search grounding — requires PAID tier (429 on free keys).`);
  process.exit(0);
}
if (QUERIES_FILE) {
  const f = resolve(QUERIES_FILE);
  QUERIES = readFileSync(f, "utf8")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"));
}
if (!QUERIES.length) {
  console.error("No queries given: use --queries (repeatable) or --queries-file <txt>");
  process.exit(2);
}

function loadSecrets() {
  const p = join(HUB_ROOT, "ai-tracking", "secrets.local.json");
  try { return JSON.parse(readFileSync(p, "utf8")); } catch { return {}; }
}
const secrets = loadSecrets();
const KEY = process.env.GEMINI_API_KEY || secrets.GEMINI_API_KEY;
if (!KEY) {
  console.error(
    "NO_KEY: add GEMINI_API_KEY (https://aistudio.google.com/api) to ai-tracking/secrets.local.json. The default ungrounded mode works on the free tier."
  );
  process.exit(2);
}

const PROMPT = (brand, q) =>
  LANG === "ru"
    ? `Какие компании или сервисы вы можете порекомендовать по запросу: "${q}"? Перечисли бренды кратко${GROUNDED ? " и укажи источники, из которых ты это взял" : ""}.`
    : `Which companies or services would you recommend for: "${q}"? Answer briefly, list the brands${GROUNDED ? " and the sources you used" : ""}.`;

async function groundedQuery(query) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": KEY },
      body: JSON.stringify({
        contents: [{ parts: [{ text: PROMPT(BRAND, query) }] }],
        ...(GROUNDED ? { tools: [{ google_search: {} }] } : {}),
      }),
    }
  );
  if (!res.ok) {
    const t = await res.text();
    if (res.status === 429) {
      throw new Error(
        `429: Google Search grounding is unavailable for free-tier keys or the paid-tier quota is exhausted: ${t.slice(0, 200)}`
      );
    }
    throw new Error(`${res.status}: ${t.slice(0, 300)}`);
  }
  const json = await res.json();
  const cand = json.candidates?.[0];
  const text =
    cand?.content?.parts?.map((p) => p.text).filter(Boolean).join("\n") || "";
  const chunks = json.groundingMetadata?.groundingChunks || [];
  const sources = [
    ...new Set(
      chunks
        .map((c) => c.web?.uri || c.web?.title)
        .filter(Boolean)
    ),
  ];
  return { text, sources };
}

const stamp = new Date().toISOString().slice(0, 10);
const slug = BRAND.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const outDir = join(HUB_ROOT, "ai-tracking", "seo-signals", slug);
mkdirSync(outDir, { recursive: true });

const results = [];
for (const q of QUERIES) {
  process.stdout.write(`query: ${q.slice(0, 60)} ... `);
  try {
    const r = await groundedQuery(q);
    const mentioned = BRAND &&
      new RegExp(BRAND.split(/\s+/).map(escapeRe).join("[\\s-]*"), "i").test(r.text);
    results.push({ query: q, brandMentioned: !!mentioned, sources: r.sources, answer: r.text.slice(0, 1200) });
    console.log(mentioned ? "MENTIONED" : "not mentioned");
  } catch (e) {
    results.push({ query: q, error: e.message });
    console.log(`ERROR: ${e.message.slice(0, 120)}`);
  }
}

const snapshotPath = join(outDir, `ai-visibility-${stamp}.json`);
const snapshot = { brand: BRAND, model: MODEL, lang: LANG, date: stamp, results };
writeFileSync(snapshotPath, JSON.stringify(snapshot, null, 2));

const md = [
  `# AI-visibility snapshot — ${BRAND}`,
  `Date: ${stamp} · model: ${MODEL} (${GROUNDED ? "grounded, simulated AIO" : "ungrounded, model-memory footprint"}) · lang: ${LANG}`,
  GROUNDED
    ? `Note: Gemini Search grounding ≈ simulated AI-answer visibility. Not equivalent to Brand Radar (no 400M prompt index / SOV). Good for drift + citation-gap discovery.`
    : `Note: ungrounded = model memory only (mechanism 3 of GEO model: brand footprint in training data). No real-time search. For real-time answers use manual method (ChatGPT/Perplexity web) or paid grounding.`,
  "",
  "| query | brand mentioned | sources |",
  "|-------|-----------------|---------|",
  ...results.map(
    (r) =>
      `| ${String(r.query).slice(0, 50)} | ${r.error ? "ERR" : r.brandMentioned ? "YES" : "no"} | ${(r.sources || []).slice(0, 3).join(", ") || "-"} |`
  ),
  "",
  "Verdicts per Workflow 1: brand absent across queries → no footprint (consensus work needed); present on one platform only → different sources per platform (work sources individually).",
].join("\n");
const mdPath = join(outDir, `ai-visibility-${stamp}.md`);
writeFileSync(mdPath, md);
console.log(`OK: ${mdPath}`);

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

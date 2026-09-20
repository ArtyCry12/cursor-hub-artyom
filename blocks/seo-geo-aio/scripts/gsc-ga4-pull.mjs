#!/usr/bin/env node
/**
 * gsc-ga4-pull.mjs — GSC queries + GA4 AI-traffic snapshot (Service Account auth).
 *
 * Part of seo-geo-aio block (hub). Zero npm deps: uses node:crypto for JWT signing
 * and global fetch for HTTP.
 *
 * Setup (one-time, free):
 *   1. Google Cloud Console → enable "Search Console API" and "Google Analytics Data API"
 *   2. IAM → Service Accounts → Create → Keys → JSON key → save OUTSIDE the repo
 *   3. secrets.local.json:
 *        "GOOGLE_SERVICE_ACCOUNT_JSON": "C:/path/to/sa-key.json",
 *        "GA4_PROPERTY_ID": "123456789"        // optional, GA4 only
 *   4. GSC property → Settings → Users and permissions → Add user
 *      (the SA email, Restricted access is enough for read)
 *   5. GA4: Admin → Property Access Management → add the SA email (Viewer)
 *
 * Usage:
 *   node scripts/gsc-ga4-pull.mjs --site https://example.com/ [--days 28] [--ga4]
 *   node scripts/gsc-ga4-pull.mjs --site sc-domain:example.com --ga4 --days 28
 *
 * Output: ai-tracking/seo-signals/<host>/gsc-<date>.json (+ ga4-<date>.json with --ga4)
 *   and a compact md summary path printed to stdout (agent reads that file).
 */

import { createSign } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const HUB_ROOT = resolve(join(scriptDir, "..", "..", ".."));

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : def;
}
function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

const SITE = arg("site");
const DAYS = parseInt(arg("days", "28"), 10);
const WITH_GA4 = hasFlag("ga4");
const HELP = hasFlag("help") || hasFlag("h") || !SITE;

if (HELP) {
  console.log(`Usage: node gsc-ga4-pull.mjs --site <URL|sc-domain:...> [--days 28] [--ga4]
Requires GOOGLE_SERVICE_ACCOUNT_JSON in ai-tracking/secrets.local.json (or env GOOGLE_SERVICE_ACCOUNT_JSON).
Optional: GA4_PROPERTY_ID in secrets or env for --ga4.`);
  process.exit(0);
}

function loadSecrets() {
  const p = join(HUB_ROOT, "ai-tracking", "secrets.local.json");
  try { return JSON.parse(readFileSync(p, "utf8")); } catch { return {}; }
}
const secrets = loadSecrets();
const SA_PATH =
  process.env.GOOGLE_SERVICE_ACCOUNT_JSON || secrets.GOOGLE_SERVICE_ACCOUNT_JSON;
if (!SA_PATH) {
  console.error(
    "NO_KEY: add GOOGLE_SERVICE_ACCOUNT_JSON (path to service-account key json) to ai-tracking/secrets.local.json. See header of this script for setup."
  );
  process.exit(2);
}

let sa;
try {
  sa = JSON.parse(readFileSync(resolve(SA_PATH), "utf8"));
} catch (e) {
  console.error(`Cannot read SA key at ${SA_PATH}: ${e.message}`);
  process.exit(2);
}

function b64url(buf) {
  return Buffer.from(buf).toString("base64url");
}
async function getAccessToken(scope) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(Buffer.from(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(
    Buffer.from(
      JSON.stringify({
        iss: sa.client_email,
        scope,
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      })
    )
  );
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${claims}`);
  signer.end();
  const signature = b64url(signer.sign(sa.private_key));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${signature}`,
    }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  if (!json.access_token) throw new Error(`no access_token: ${JSON.stringify(json).slice(0, 200)}`);
  return json.access_token;
}

async function gscQuery(accessToken, site, startDate, endDate) {
  const url = `https://searchconsole.googleapis.com/webmasters/v3/sites/${encodeURIComponent(site)}/searchAnalytics/query`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      startDate,
      endDate,
      dimensions: ["query"],
      rowLimit: 200,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    if (res.status === 403 && /has no access|permission/i.test(text)) {
      throw new Error(
        `403: service account has no access to ${site}. Fix: GSC → Settings → Users and permissions → Add user → SA email.`
      );
    }
    throw new Error(`GSC ${res.status}: ${text.slice(0, 300)}`);
  }
  const json = await res.json();
  return json.rows || [];
}

async function ga4AiTraffic(accessToken, propertyId, startDate, endDate) {
  const res = await fetch(
    `https://analyticsdata.googleapis.com/v1beta/properties/${propertyId}:runReport`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        dateRanges: [{ startDate, endDate }],
        dimensions: [{ name: "sessionSource" }],
        metrics: [{ name: "sessions" }, { name: "engagedSessions" }],
        dimensionFilter: {
          filter: {
            fieldName: "sessionDefaultChannelGroup",
            stringFilter: { matchType: "EXACT", value: "ai-assistant" },
          },
        },
      }),
    }
  );
  if (!res.ok) throw new Error(`GA4 ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const json = await res.json();
  return (json.rows || []).map((r) => ({
    source: r.dimensionValues[0].value,
    sessions: Number(r.metricValues[0].value),
    engaged: Number(r.metricValues[1].value),
  }));
}

function toMd(rows, ga4rows, site, days) {
  const lines = [
    `# GSC + GA4 snapshot — ${SITE}`,
    `Date: ${new Date().toISOString()} · window: ${days}d · rows: ${rows.length}`,
    "",
    "## Top queries (impressions desc)",
    "",
    "| query | clicks | impressions | position |",
    "|-------|--------|-------------|----------|",
  ];
  const sorted = [...rows].sort((a, b) => b.impressions - a.impressions).slice(0, 25);
  for (const r of sorted) {
    lines.push(
      `| ${String(r.keys[0]).slice(0, 60)} | ${r.clicks ?? 0} | ${r.impressions ?? 0} | ${r.position?.toFixed(1) ?? "-"} |`
    );
  }
  lines.push("", "> Citation-gap input: pick 5-10 converting queries above → Workflow 1 of skills/ai-search-optimization.");
  if (ga4rows?.length) {
    lines.push("", "## GA4 AI-traffic (native `ai-assistant` channel)", "");
    for (const r of ga4rows) lines.push(`- ${r.source}: ${r.sessions} sessions`);
  } else if (WITH_GA4) {
    lines.push("", "## GA4 AI-traffic", "", "No `ai-assistant` sessions in window.");
  }
  return lines.join("\n");
}

const days = DAYS;
const end = new Date();
const start = new Date(Date.now() - days * 86400000);
const endDate = end.toISOString().slice(0, 10);
const startDate = start.toISOString().slice(0, 10);

// 1) GSC queries
const token = await getAccessToken("https://www.googleapis.com/auth/webmasters.readonly");
const rows = await gscQuery(token, SITE, startDate, endDate);

// 2) GA4 (optional)
let ga4rows = null;
const GA4_PROPERTY_ID =
  process.env.GA4_PROPERTY_ID || secrets.GA4_PROPERTY_ID || "";
if (WITH_GA4) {
  if (!GA4_PROPERTY_ID) {
    console.error("GA4_PROPERTY_ID missing — skipping GA4 (add to secrets.local.json).");
  } else {
    ga4rows = await ga4AiTraffic(token, GA4_PROPERTY_ID, startDate, endDate);
  }
}

// 3) Persist
const host = SITE.replace(/^https?:\/\//, "").replace(/\/$/, "").replace(/^sc-domain:/, "domain-");
const outDir = join(HUB_ROOT, "ai-tracking", "seo-signals", host);
mkdirSync(outDir, { recursive: true });
const stamp = new Date().toISOString().slice(0, 10);
const jsonPath = join(outDir, `gsc-${stamp}.json`);
const mdPath = join(outDir, `gsc-${stamp}.md`);
writeFileSync(jsonPath, JSON.stringify({ site: SITE, startDate, endDate, rows }, null, 2));
writeFileSync(mdPath, toMd(rows, ga4rows, SITE, days));
if (ga4rows) {
  writeFileSync(join(outDir, `ga4-${stamp}.json`), JSON.stringify({ site: SITE, startDate, endDate, rows: ga4rows }, null, 2));
}
console.log(`OK: ${mdPath}`);

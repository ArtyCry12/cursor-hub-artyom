#!/usr/bin/env node
/**
 * Fixture pilot: validate source-ledger.fixture.json against schema (no Ajv dep).
 * Usage: node blocks/seo-geo-aio/scripts/validate-source-ledger.mjs
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const schema = JSON.parse(
  readFileSync(join(root, "references", "source-ledger.schema.json"), "utf8")
);
const fixture = JSON.parse(
  readFileSync(
    join(root, "references", "fixtures", "source-ledger.fixture.json"),
    "utf8"
  )
);

const errs = [];

function typeOf(v) {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  return typeof v;
}

function resolveRef(ref) {
  if (!ref.startsWith("#/$defs/")) {
    throw new Error(`unsupported $ref: ${ref}`);
  }
  return schema.$defs[ref.slice("#/$defs/".length)];
}

function check(node, sch, ptr) {
  if (!sch || typeof sch !== "object") return;

  if (sch.$ref) {
    check(node, resolveRef(sch.$ref), ptr);
    return;
  }

  if (sch.const !== undefined && node !== sch.const) {
    errs.push(`${ptr}: expected const ${JSON.stringify(sch.const)}`);
  }

  if (sch.type) {
    const t = typeOf(node);
    const ok = Array.isArray(sch.type)
      ? sch.type.includes(t)
      : t === sch.type;
    if (!ok) errs.push(`${ptr}: type ${t} != ${sch.type}`);
    if (t !== "object" && t !== "array") {
      if (sch.enum && !sch.enum.includes(node)) {
        errs.push(`${ptr}: value not in enum`);
      }
      if (
        sch.minLength &&
        typeof node === "string" &&
        node.length < sch.minLength
      ) {
        errs.push(`${ptr}: minLength`);
      }
      return;
    }
  }

  if (sch.enum && !sch.enum.includes(node)) {
    errs.push(`${ptr}: value not in enum`);
  }

  if (sch.required && node && typeof node === "object") {
    for (const k of sch.required) {
      if (!(k in node)) errs.push(`${ptr}.${k}: missing required`);
    }
  }

  if (
    sch.additionalProperties === false &&
    node &&
    typeof node === "object" &&
    !Array.isArray(node)
  ) {
    const allowed = new Set(Object.keys(sch.properties || {}));
    for (const k of Object.keys(node)) {
      if (!allowed.has(k)) errs.push(`${ptr}.${k}: additional property`);
    }
  }

  if (sch.properties && node && typeof node === "object" && !Array.isArray(node)) {
    for (const [k, ps] of Object.entries(sch.properties)) {
      if (k in node) check(node[k], ps, `${ptr}.${k}`);
    }
  }

  if (sch.items && Array.isArray(node)) {
    node.forEach((it, i) => check(it, sch.items, `${ptr}[${i}]`));
  }

  if (sch.minItems != null && Array.isArray(node) && node.length < sch.minItems) {
    errs.push(`${ptr}: minItems`);
  }
}

check(fixture, schema, "$");

if (errs.length) {
  console.error("FAIL");
  for (const e of errs) console.error(e);
  process.exit(1);
}

const tracker = fixture.entries.find(
  (e) => e.evidence_class === "model_memory_tracker"
);
if (!tracker || tracker.confidence !== "low") {
  console.error("FAIL: fixture must keep model_memory_tracker at confidence=low");
  process.exit(1);
}

console.log(
  `PASS schema_version=${fixture.schema_version} entries=${fixture.entries.length}`
);
console.log("adversarial_checklist:");
for (const a of [
  "search-first rejects model_memory as SERP",
  "citation!=recommendation encoded",
  "hub signals mapped not canon",
  "no OpenSERP installed",
  "fixture confidence low on tracker row",
]) {
  console.log(` - OK ${a}`);
}

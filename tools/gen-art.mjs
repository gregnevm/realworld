#!/usr/bin/env node
// RealWorld — tools/gen-art.mjs : concept-consistent game art via Nano Banana (Gemini image models).
// Zero npm deps (Node 22 fetch). Post-processing is tools/art/post.py (Pillow + numpy). Pure logic lives
// in tools/art/lib.mjs (tested by tests/art.test.js).
//
//   node tools/gen-art.mjs key [KEY]          save key → .env.local (0600, gitignored) + verify; reads stdin if no KEY
//   node tools/gen-art.mjs check              verify the key is accepted and the model is visible (quota: only gen)
//   node tools/gen-art.mjs sync               catalog.json + data.gd → art/manifest.json (idempotent, keeps human edits)
//   node tools/gen-art.mjs status             counts by kind × status
//   node tools/gen-art.mjs gen [opts]         generate candidates → art/out/<kind>/<id>/vN.png (+ .raw.png, .meta.json)
//       --only a,b   --kind icon|sprite|actor|tile|ui|ref   --prefix bld_   --n 1..4   --limit 12   --concurrency 2
//       --model gemini-nano-banana-2.1   --force   --dry (print prompts, no API)   --palette
//   node tools/gen-art.mjs approve <id>[@vN]  candidate (latest if no @vN) → godot/assets/gen/<kind>/<id>.png (refs → art/refs/)
//   node tools/gen-art.mjs repost [--only a,b] [--kind k] [--palette]   re-run post.py over saved raws (no API, no spend)
//
// Exit codes: 0 ok · 1 error · 2 key invalid/expired/shadowed · 3 quota (Free Tier `limit: 0`, daily quota, long backoff).
// Key lookup: $GEMINI_API_KEY → $GEMINI_KEY_FILE → <repo>/.env.local → <repo>/.env. Never printed (masked), never in
// meta, never committed (npm run lint secret-scan). Unknown flags are an error — a typo must not turn --dry into a paid run.
import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import tty from "node:tty";
import { parseArgs } from "node:util";
import { spawnSync } from "node:child_process";
import {
  KEY_ENV, KEY_SCAN_RE, KINDS, DEFAULT_LIMIT, parseEnv, upsertEnv, looksLikeKey, maskKey, parseDataGd,
  buildManifest, composePrompt, promptHash, selectAssets, pickRefs, classify429,
} from "./art/lib.mjs";

const ROOT = path.dirname(path.dirname(url.fileURLToPath(import.meta.url)));
const P = (...a) => path.join(ROOT, ...a);
const MANIFEST = P("art", "manifest.json");
const STYLE = P("art", "style.md");
const REFS = P("art", "refs");
const OUT = P("art", "out");
const GEN = P("godot", "assets", "gen");
const API = "https://generativelanguage.googleapis.com/v1beta";
// One model for the whole game: switching it shifts the look, so it is a deliberate step (regenerate the anchors +
// the approved set), never a silent default bump. Migrated 2026-11-04 from gemini-2.5-flash-image (Google shuts it
// down 2027-03-15 and restricts it for new projects) to Nano Banana 2.1 — anchors and every previously approved
// asset were regenerated with it, so ALL art ships from one model.
const DEFAULT_MODEL = "gemini-nano-banana-2.1";
const SHUT_DOWN = { "gemini-3-pro-image-preview": "gemini-3-pro-image", "gemini-3.1-flash-image-preview": "gemini-3.1-flash-image" };

const die = (msg, code = 1) => { console.error(`✖ ${msg}`); process.exit(code); };
const readJSON = (f, d) => (fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : d);
// Atomic write: a killed run never leaves a half-written manifest.
const writeJSON = (f, v) => {
  fs.mkdirSync(path.dirname(f), { recursive: true });
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(v, null, 1) + "\n");
  fs.renameSync(tmp, f);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ------------------------------------------------------------------ args (strict, per command)
const COMMON = { model: { type: "string" }, help: { type: "boolean", short: "h" } };
const OPTIONS = {
  key: { ...COMMON, "no-check": { type: "boolean" } },
  check: COMMON,
  sync: COMMON,
  status: COMMON,
  gen: { ...COMMON, only: { type: "string" }, kind: { type: "string" }, prefix: { type: "string" }, n: { type: "string" },
    limit: { type: "string" }, concurrency: { type: "string" }, force: { type: "boolean" }, dry: { type: "boolean" }, palette: { type: "boolean" } },
  approve: COMMON,
  repost: { ...COMMON, only: { type: "string" }, kind: { type: "string" }, palette: { type: "boolean" } },
};
const HELP = () => {
  const src = fs.readFileSync(url.fileURLToPath(import.meta.url), "utf8").split("\n").slice(1);
  console.log(src.slice(0, src.findIndex((l) => !l.startsWith("//"))).map((l) => l.replace(/^\/\/ ?/, "")).join("\n"));
};
const cmd = process.argv[2];
if (!cmd || ["help", "--help", "-h"].includes(cmd)) { HELP(); process.exit(0); }
if (!OPTIONS[cmd]) { HELP(); die(`невідома команда "${cmd}"`); }
let args;
try { args = parseArgs({ args: process.argv.slice(3), options: OPTIONS[cmd], strict: true, allowPositionals: true }); }
catch (e) { die(`${e.message} — дивись: node tools/gen-art.mjs --help`); }
if (args.values.help) { HELP(); process.exit(0); }
const V = args.values;
const POS = args.positionals;
const posInt = (name, dflt, max = Infinity) => {
  if (V[name] == null) return dflt;
  const v = Number(V[name]);
  if (!Number.isInteger(v) || v < 1 || v > max) die(`--${name} має бути цілим 1…${max === Infinity ? "∞" : max} (отримано "${V[name]}")`);
  return v;
};
const list = (s) => (s ? s.split(",").map((x) => x.trim()).filter(Boolean) : null);
const MODEL = V.model || DEFAULT_MODEL;
if (SHUT_DOWN[MODEL]) die(`модель ${MODEL} вимкнена Google — використай ${SHUT_DOWN[MODEL]}`);

// ------------------------------------------------------------------ key
const KEY_CHARS = /^[\x21-\x7e]+$/; // printable ASCII only: a CR/LF/NUL would make fetch echo the header (= the key)
function loadKey() {
  const pick = (v, source) => (v && v.trim() ? { key: v.trim(), source } : null);
  let found = pick(process.env[KEY_ENV], `$${KEY_ENV}`);
  if (!found && process.env.GEMINI_KEY_FILE && fs.existsSync(process.env.GEMINI_KEY_FILE)) {
    const t = fs.readFileSync(process.env.GEMINI_KEY_FILE, "utf8");
    found = pick(parseEnv(t)[KEY_ENV] || (t.match(KEY_SCAN_RE) || [""])[0], "$GEMINI_KEY_FILE");
  }
  for (const f of [".env.local", ".env"]) {
    if (found) break;
    if (fs.existsSync(P(f))) found = pick(parseEnv(fs.readFileSync(P(f), "utf8"))[KEY_ENV], f);
  }
  if (found && !KEY_CHARS.test(found.key)) die(`ключ із ${found.source} містить непридатні символи (пробіл/перенос рядка) — перезапиши: node tools/gen-art.mjs key`, 2);
  return found;
}
const requireKey = () => loadKey() || die(`немає ключа. Дай його: printf %s "$KEY" | node tools/gen-art.mjs key   (або export ${KEY_ENV}=…)`, 2);

function explainHttp(status, body) {
  const msg = (body && body.error && body.error.message) || "";
  if (/API key expired|API_KEY_INVALID|API key not valid/i.test(msg) || status === 401)
    return { code: 2, text: `ключ недійсний або прострочений (${status}). Дай новий: printf %s "$KEY" | node tools/gen-art.mjs key` };
  if (status === 403) return { code: 1, text: `доступ заборонено (403): ${msg} — перевір, що для ключа ввімкнено Generative Language API` };
  if (status === 404) return { code: 1, text: `модель не знайдена (404): ${msg}` };
  if (status === 429) {
    const q = classify429(body);
    if (q.freeTierZero) return { code: 3, text: "квота 0 на Free Tier: проєкт цього ключа не має доступу до image-моделей без білінгу. Увімкни білінг (AI Studio → API keys → проєкт → Set up billing), ключ лишається той самий" };
    if (q.daily) return { code: 3, text: `денна квота вичерпана (429): ${msg.split("\n")[0]}` };
    return { code: 3, text: `ліміт/квота (429): ${msg.split("\n")[0]}` };
  }
  return { code: 1, text: `HTTP ${status}: ${msg || JSON.stringify(body).slice(0, 300)}` };
}

async function api(pathname, { key, method = "GET", body } = {}) {
  const res = await fetch(`${API}/${pathname}`, {
    method,
    headers: { "x-goog-api-key": key, "content-type": "application/json" }, // header, not ?key= — keeps it out of URLs/logs
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch { /* non-JSON error page */ }
  return { ok: res.ok, status: res.status, json };
}

async function check({ key, source }) {
  const r = await api(`models/${MODEL}`, { key });
  if (!r.ok) { const e = explainHttp(r.status, r.json); die(e.text, e.code); }
  console.log(`✔ ключ ${maskKey(key)} (${source}) приймається API · модель ${MODEL} видима. Квоту image-генерації перевіряє лише gen.`);
}

function gitIgnored(rel) {
  const r = spawnSync("git", ["check-ignore", "-q", rel], { cwd: ROOT, encoding: "utf8" });
  if (r.error) die(`git недоступний (${r.error.code}) — не можу перевірити, що ${rel} ігнорується; ключ не збережено`);
  if (r.status === 0) return true;
  if (r.status === 1) return false;
  die(`git check-ignore завершився з кодом ${r.status}: ${(r.stderr || "").trim()} — ключ не збережено`);
}

async function cmdKey() {
  let key = POS[0] || "";
  if (!key && !tty.isatty(0)) {
    try { key = fs.readFileSync(0, "utf8"); }
    catch (e) { die(`не вдалося прочитати stdin (${e.code}) — передай ключ так: printf %s "$KEY" | node tools/gen-art.mjs key`); }
  }
  key = key.trim();
  if (!key) die("передай ключ через stdin: printf %s \"$KEY\" | node tools/gen-art.mjs key   (аргумент теж працює, але лишається в історії shell)");
  if (!KEY_CHARS.test(key)) die("ключ містить пробіли/переноси/керівні символи — скопіюй його ще раз без них", 2);
  if (!looksLikeKey(key)) console.warn("⚠ ключ не схожий на Google API key (AIza… або AQ.…) — зберігаю все одно");
  if (!gitIgnored(".env.local")) die(".env.local НЕ ігнорується git — ключ під загрозою коміту; виправ .gitignore (ключ не збережено)");
  const f = P(".env.local");
  const prev = fs.existsSync(f) ? fs.readFileSync(f, "utf8") : "";
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, upsertEnv(prev, KEY_ENV, key), { mode: 0o600, flag: "wx" });
  fs.renameSync(tmp, f);
  fs.chmodSync(f, 0o600);
  console.log(`✔ збережено ${maskKey(key)} → .env.local (0600, gitignored)`);
  const env = process.env[KEY_ENV] && process.env[KEY_ENV].trim();
  if (env && env !== key) die(`$${KEY_ENV} у середовищі (${maskKey(env)}) ПЕРЕКРИВАЄ .env.local — зроби unset ${KEY_ENV}, інакше gen/check шлють старий ключ`, 2);
  if (!V["no-check"]) await check({ key, source: ".env.local" });
}

// ------------------------------------------------------------------ manifest
const readLive = () => parseDataGd(fs.readFileSync(P("godot", "scripts", "data.gd"), "utf8"));

function cmdSync() {
  const cat = readJSON(P("godot", "content", "catalog.json"));
  const before = readJSON(MANIFEST, null);
  const next = buildManifest(cat, before, readLive());
  writeJSON(MANIFEST, next);
  const prevIds = new Set(((before && before.assets) || []).map((a) => a.id));
  const added = next.assets.filter((a) => !prevIds.has(a.id)).length;
  const orphans = next.assets.filter((a) => a.orphan).length;
  console.log(`✔ manifest: ${next.assets.length} assets (+${added} нових${orphans ? `, ${orphans} orphan` : ""})`);
}

// Re-read the manifest from disk and apply only this run's per-row patches — edits/approvals made in parallel
// (another terminal, a human) survive, and every paid image is recorded the moment it lands.
function patchManifest(patches) {
  const fresh = readJSON(MANIFEST, null) || die("art/manifest.json зник під час запуску");
  for (const row of fresh.assets) if (patches.has(row.id)) patches.get(row.id)(row);
  writeJSON(MANIFEST, fresh);
}

function cmdStatus() {
  const m = readJSON(MANIFEST, null) || die("немає art/manifest.json — запусти sync");
  const t = {};
  for (const a of m.assets) { const k = a.orphan ? `${a.kind}*` : a.kind; (t[k] ||= {})[a.status] = ((t[k] || {})[a.status] || 0) + 1; }
  const statuses = ["todo", "draft", "approved"];
  console.log(["kind".padEnd(8), ...statuses.map((s) => s.padStart(9))].join(""));
  for (const [k, v] of Object.entries(t)) console.log([k.padEnd(8), ...statuses.map((s) => String(v[s] || 0).padStart(9))].join(""));
  if (Object.keys(t).some((k) => k.endsWith("*"))) console.log("* orphan — def зник із каталогу, рядок і арт збережено");
  const refs = listRefs();
  console.log(`refs: ${refs.length ? refs.join(", ") : "— (порожньо: спершу згенеруй і approve ref_world / ref_ground)"}`);
}

// ------------------------------------------------------------------ generation
function listRefs() {
  if (!fs.existsSync(REFS)) return [];
  const out = [];
  for (const e of fs.readdirSync(REFS, { withFileTypes: true })) {
    if (e.isFile() && /\.png$/i.test(e.name)) out.push(e.name);
    if (e.isDirectory()) for (const f of fs.readdirSync(path.join(REFS, e.name))) if (/\.png$/i.test(f)) out.push(`${e.name}/${f}`);
  }
  return out.sort();
}

// Candidate variants on disk: v0.png, v1.png … (v*.raw.png / v*.meta.json are sidecars of the same number).
function versions(dir) {
  if (!fs.existsSync(dir)) return [];
  return [...new Set(fs.readdirSync(dir).map((f) => f.match(/^v(\d+)\.(?:raw\.png|png|meta\.json)$/)).filter(Boolean).map((m) => +m[1]))];
}
const nextVersion = (dir) => { const v = versions(dir); return v.length ? Math.max(...v) + 1 : 0; };
const hasCandidates = (a) => versions(path.join(OUT, a.kind, a.id)).some((v) => fs.existsSync(path.join(OUT, a.kind, a.id, `v${v}.png`)));

function refParts(kind) {
  if (kind === "ref") return { parts: [], sig: "", picked: [] }; // anchors define the style; they never condition on themselves
  const picked = pickRefs(listRefs(), kind);
  const parts = picked.map((f) => ({ inlineData: { mimeType: "image/png", data: fs.readFileSync(path.join(REFS, f)).toString("base64") } }));
  const sig = picked.map((f) => `${f}:${fs.statSync(path.join(REFS, f)).size}`).join(",");
  return { parts, sig, picked };
}

class Fatal extends Error { constructor(msg, code) { super(msg); this.code = code; } }

async function generateOne(key, asset, prompt, refs, variant) {
  const body = {
    contents: [{ role: "user", parts: [...refs.parts, { text: prompt }] }],
    generationConfig: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio: KINDS[asset.kind].aspect } },
  };
  for (let attempt = 0; attempt < 5; attempt++) {
    const r = await api(`models/${MODEL}:generateContent`, { key, method: "POST", body });
    if (r.ok) {
      const cand = r.json && r.json.candidates && r.json.candidates[0];
      // Gemini 3 image models may emit interim "thought" images before the final one — take the last non-thought.
      const imgs = ((cand && cand.content && cand.content.parts) || []).filter((p) => p.inlineData && !p.thought);
      const img = imgs[imgs.length - 1];
      if (img) return { data: Buffer.from(img.inlineData.data, "base64"), usage: r.json.usageMetadata || null };
      const why = (cand && cand.finishReason) || (r.json.promptFeedback && r.json.promptFeedback.blockReason) || "no image part";
      throw new Error(`${asset.id} v${variant}: модель не повернула зображення (${why})`);
    }
    const q = r.status === 429 ? classify429(r.json) : null;
    if (![429, 500, 502, 503, 504].includes(r.status) || (q && q.fatal)) {
      const e = explainHttp(r.status, r.json);
      throw new Fatal(`${asset.id}: ${e.text}`, e.code); // same answer for every job in this run — stop the batch
    }
    if (q && q.retryMs && q.retryMs > 60000) {
      const e = explainHttp(r.status, r.json);
      throw new Fatal(`${asset.id}: ${e.text} — сервер просить чекати ${Math.round(q.retryMs / 1000)}s; запусти пізніше`, 3);
    }
    const wait = Math.min(60000, (q && q.retryMs) || 2000 * 2 ** attempt);
    console.warn(`… ${asset.id}: ${r.status}, повтор через ${Math.round(wait / 1000)}s`);
    await sleep(wait);
  }
  throw new Error(`${asset.id}: вичерпано повтори`);
}

// Interpreter for post.py: $PYTHON, else the first of python3/python (Windows: py -3/python) that imports
// Pillow + numpy. Resolved BEFORE any paid call — a missing dependency must not be discovered per image.
let PY = null;
function python() {
  if (PY) return PY;
  const tries = process.env.PYTHON ? [[process.env.PYTHON]]
    : process.platform === "win32" ? [["py", "-3"], ["python"], ["python3"]] : [["python3"], ["python"]];
  for (const [bin, ...pre] of tries) {
    const r = spawnSync(bin, [...pre, "-I", "-c", "import PIL, numpy"], { encoding: "utf8" });
    if (!r.error && r.status === 0) return (PY = [bin, ...pre]);
  }
  die(`post.py потребує Python 3 з Pillow і numpy: pip install pillow numpy  (або вкажи інтерпретатор: PYTHON=…)`);
}

function postProcess(raw, out, asset) {
  const k = KINDS[asset.kind];
  const [bin, ...pre] = python();
  const a = [...pre, "-I", P("tools", "art", "post.py"), raw, out, "--size", String(asset.size ?? k.size)];
  if (k.key) a.push("--key");
  if (asset.kind === "tile") a.push("--tile");
  // Palette snap is opt-in (manifest `palette: true` or --palette): on painterly renders it posterizes.
  if (asset.palette === true || V.palette) a.push("--palette", P("art", "palette.json"));
  const r = spawnSync(bin, a, { stdio: ["ignore", "inherit", "inherit"] });
  if (r.error || r.status !== 0) throw new Error(`post.py впав на ${path.relative(ROOT, raw)} (raw збережено — після фіксу: repost --only ${asset.id})`);
}

// Re-run post-processing over existing raw renders — no API call, no spend. For tuning post.py.
function cmdRepost() {
  const manifest = readJSON(MANIFEST, null) || die("немає manifest");
  const only = list(V.only) && new Set(list(V.only));
  python();
  let n = 0, fail = 0;
  for (const a of manifest.assets) {
    if (only && !only.has(a.id)) continue;
    if (V.kind && a.kind !== V.kind) continue;
    const dir = path.join(OUT, a.kind, a.id);
    for (const v of versions(dir).sort((x, y) => x - y)) {
      const raw = path.join(dir, `v${v}.raw.png`);
      if (!fs.existsSync(raw)) continue;
      try { postProcess(raw, path.join(dir, `v${v}.png`), a); n++; } catch (e) { fail++; console.error(`✖ ${e.message}`); }
    }
  }
  console.log(`✔ перероблено ${n} кандидатів (без API)${fail ? `, ${fail} помилок` : ""}`);
  if (fail) process.exitCode = 1;
}

async function pool(items, n, fn) {
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (next < items.length) { const i = next++; await fn(items[i], i); }
  }));
}

async function cmdGen() {
  const manifest = readJSON(MANIFEST, null) || die("немає art/manifest.json — запусти: node tools/gen-art.mjs sync");
  const style = fs.existsSync(STYLE) ? fs.readFileSync(STYLE, "utf8") : die("немає art/style.md");
  const n = posInt("n", 1, 4);
  const limit = posInt("limit", DEFAULT_LIMIT);
  const concurrency = posInt("concurrency", 2, 8);
  if (V.kind && !KINDS[V.kind]) die(`--kind має бути одним із: ${Object.keys(KINDS).join(", ")}`);
  const only = list(V.only);
  if (only) { const ids = new Set(manifest.assets.map((a) => a.id)); const bad = only.filter((id) => !ids.has(id)); if (bad.length) die(`немає в manifest: ${bad.join(", ")}`); }
  const { picked, dropped } = selectAssets(manifest, { only, kind: V.kind, prefix: V.prefix, force: V.force, limit, hasCandidates });
  if (!picked.length) return console.log("нічого генерувати (усе draft/approved або фільтр порожній; --force / --only щоб перегенерувати)");
  if (dropped) console.log(`ℹ ліміт: ${picked.length} у цьому запуску, ще ${dropped} відкладено (--limit N)`);
  if (!listRefs().length && picked.some((a) => a.kind !== "ref"))
    console.warn("⚠ art/refs/ порожній — стиль триматиметься лише текстом. Рекомендовано спершу: gen --kind ref → approve ref_world");
  if (!V.dry) python();
  const key = V.dry ? null : requireKey().key;
  // Variant numbers are reserved up-front per asset so concurrent jobs never race on the directory listing.
  const base = new Map(picked.map((a) => [a.id, nextVersion(path.join(OUT, a.kind, a.id))]));
  const jobs = picked.flatMap((a) => Array.from({ length: n }, (_, v) => ({ a, v })));
  let okCount = 0, fail = 0, done = 0, halted = null;

  await pool(jobs, concurrency, async ({ a, v }) => {
    if (halted) return;
    const refs = refParts(a.kind);
    const prompt = composePrompt(style, a);
    const hash = promptHash(prompt, MODEL, refs.sig);
    if (V.dry) { if (v === 0) console.log(`\n── ${a.id} [${a.kind}] hash=${hash} refs=${refs.picked.join(",") || "—"}\n${prompt}`); return; }
    const dir = path.join(OUT, a.kind, a.id);
    fs.mkdirSync(dir, { recursive: true });
    const ver = base.get(a.id) + v;
    try {
      const { data, usage } = await generateOne(key, a, prompt, refs, ver);
      const raw = path.join(dir, `v${ver}.raw.png`);
      fs.writeFileSync(raw, data);
      writeJSON(path.join(dir, `v${ver}.meta.json`), { id: a.id, kind: a.kind, variant: ver, model: MODEL, hash, refs: refs.picked, usage, prompt });
      // record the paid image NOW — a crash in post.py or a killed run must not make it look un-generated
      patchManifest(new Map([[a.id, (row) => { row.hash = hash; if (row.status !== "approved") row.status = "draft"; }]]));
      done++;
      postProcess(raw, path.join(dir, `v${ver}.png`), a);
      okCount++;
      console.log(`✔ ${path.relative(ROOT, path.join(dir, `v${ver}.png`))}`);
    } catch (e) {
      fail++;
      if (e instanceof Fatal) {
        if (!halted) { halted = e; console.error(`✖ ${e.message}\n  ⏹ батч зупинено: ця відповідь однакова для всіх асетів`); }
        process.exitCode = e.code;
      } else console.error(`✖ ${e.message}`);
    }
  });
  if (!V.dry) {
    const skipped = jobs.length - okCount - fail;
    console.log(`\n${okCount} згенеровано, ${fail} помилок${skipped ? `, ${skipped} пропущено (батч зупинено)` : ""}${done > okCount ? `, ${done - okCount} raw без постобробки` : ""}.${okCount ? " Переглянь art/out/ і зроби: node tools/gen-art.mjs approve <id>@vN" : ""}`);
    if (fail) process.exitCode ||= 1;
  }
}

// ------------------------------------------------------------------ approve
function cmdApprove() {
  const spec = POS[0] || die("approve <id>[@vN]");
  const at = spec.indexOf("@");
  const id = at < 0 ? spec : spec.slice(0, at);
  const vRaw = at < 0 ? "" : spec.slice(at + 1);
  if (vRaw && !/^v?\d+$/.test(vRaw)) die(`погана версія "${vRaw}" (очікую vN або N)`);
  const manifest = readJSON(MANIFEST, null) || die("немає manifest");
  const row = manifest.assets.find((a) => a.id === id) || die(`немає ${id} у manifest`);
  const dir = path.join(OUT, row.kind, id);
  const vers = versions(dir).filter((x) => fs.existsSync(path.join(dir, `v${x}.png`))).sort((x, y) => x - y);
  if (!vers.length) die(`немає кандидатів у ${path.relative(ROOT, dir)}`);
  const v = vRaw ? +vRaw.replace(/^v/, "") : vers[vers.length - 1];
  if (!vers.includes(v)) die(`немає v${v} (є: ${vers.map((x) => "v" + x).join(", ")})`);
  const meta = readJSON(path.join(dir, `v${v}.meta.json`), {});
  // refs anchor the style at full resolution (raw); game assets ship post-processed.
  const dest = row.kind === "ref" ? path.join(REFS, `${id}.png`) : path.join(GEN, row.kind, `${id}.png`);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(path.join(dir, row.kind === "ref" ? `v${v}.raw.png` : `v${v}.png`), dest);
  const { prompt, ...slim } = meta; // the prompt is reproducible from manifest+style; keep the sidecar small
  writeJSON(dest.replace(/\.png$/, ".meta.json"), { ...slim, approved_from: `v${v}`, prompt_chars: (prompt || "").length });
  patchManifest(new Map([[id, (r) => { r.status = "approved"; r.approved = `v${v}`; }]]));
  console.log(`✔ ${id}@v${v} → ${path.relative(ROOT, dest)}`);
}

// ------------------------------------------------------------------ main
const commands = {
  key: cmdKey,
  check: () => check(requireKey()),
  sync: cmdSync,
  status: cmdStatus,
  gen: cmdGen,
  approve: cmdApprove,
  repost: cmdRepost,
};
if (POS.length && !["key", "approve"].includes(cmd)) die(`зайвий аргумент "${POS[0]}" — прапорці пишуться як --name value`);
Promise.resolve(commands[cmd]()).catch((e) => die(e.message));

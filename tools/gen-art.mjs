#!/usr/bin/env node
// RealWorld — tools/gen-art.mjs : concept-consistent game art via Nano Banana (Gemini image models).
// Zero npm deps (Node 22 fetch). Post-processing (chroma-key → alpha, trim, resize, palette) is
// tools/art/post.py (Pillow). Pure logic lives in tools/art/lib.mjs (tested by tests/art.test.js).
//
//   node tools/gen-art.mjs key [KEY]          save key → .env.local (0600, gitignored) + verify; reads stdin if no arg
//   node tools/gen-art.mjs check              verify key + that the image model is reachable
//   node tools/gen-art.mjs sync               catalog.json → art/manifest.json (idempotent, keeps human edits)
//   node tools/gen-art.mjs status             counts by kind × status
//   node tools/gen-art.mjs gen [opts]         generate candidates → art/out/<kind>/<id>/vN.png (+ .raw.png, .meta.json)
//       --only a,b   --kind icon|sprite|actor|tile|ui|ref   --prefix bld_   --n 2   --limit 12
//       --model gemini-2.5-flash-image   --force   --dry (print prompts, no API)   --concurrency 2
//   node tools/gen-art.mjs approve <id>[@vN]  candidate → godot/assets/gen/<kind>/<id>.png (refs → art/refs/)
//
// Key lookup order: $GEMINI_API_KEY → $GEMINI_KEY_FILE → <repo>/.env.local → <repo>/.env.
// The key is never printed (masked AIza…xxxx), never written to meta, never committed (lint secret-scan).
import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import { execFileSync } from "node:child_process";
import {
  KEY_ENV, KINDS, parseEnv, upsertEnv, looksLikeKey, maskKey,
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
const DEFAULT_MODEL = "gemini-2.5-flash-image";

const argv = process.argv.slice(2);
const cmd = argv[0];
const flag = (k) => argv.includes(`--${k}`);
const opt = (k, d) => { const i = argv.indexOf(`--${k}`); return i > 0 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : d; };
const die = (msg, code = 1) => { console.error(`✖ ${msg}`); process.exit(code); };
const readJSON = (f, d) => (fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : d);
const writeJSON = (f, v) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, JSON.stringify(v, null, 1) + "\n"); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ------------------------------------------------------------------ key
function loadKey() {
  if (process.env[KEY_ENV]) return process.env[KEY_ENV].trim();
  if (process.env.GEMINI_KEY_FILE && fs.existsSync(process.env.GEMINI_KEY_FILE)) {
    const t = fs.readFileSync(process.env.GEMINI_KEY_FILE, "utf8");
    return (parseEnv(t)[KEY_ENV] || t).trim();
  }
  for (const f of [".env.local", ".env"]) {
    const v = fs.existsSync(P(f)) && parseEnv(fs.readFileSync(P(f), "utf8"))[KEY_ENV];
    if (v) return v.trim();
  }
  return "";
}
const requireKey = () => loadKey() || die(`немає ключа. Дай його: node tools/gen-art.mjs key <KEY>  (або export ${KEY_ENV}=…)`);

function explainHttp(status, body) {
  const msg = (body && body.error && body.error.message) || "";
  if (/API key expired|API_KEY_INVALID|API key not valid/i.test(msg) || status === 401)
    return `ключ недійсний або прострочений (${status}). Дай новий: node tools/gen-art.mjs key <KEY>`;
  if (status === 403) return `доступ заборонено (403): ${msg} — перевір, що для ключа ввімкнено Generative Language API`;
  if (status === 429) {
    const q = classify429(body);
    if (q.freeTierZero) return "квота 0 на Free Tier: проєкт цього ключа не має доступу до image-моделей без білінгу. Увімкни білінг (AI Studio → API keys → проєкт → Set up billing), ключ лишається той самий";
    return `ліміт/квота (429): ${msg.split("\n")[0]}`;
  }
  return `HTTP ${status}: ${msg || JSON.stringify(body).slice(0, 300)}`;
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

async function check(key, model = DEFAULT_MODEL) {
  const r = await api(`models/${model}`, { key });
  if (!r.ok) die(explainHttp(r.status, r.json));
  const methods = (r.json && r.json.supportedGenerationMethods) || [];
  console.log(`✔ ключ ${maskKey(key)} валідний · модель ${model} доступна${methods.length ? ` (${methods.join(", ")})` : ""}`);
}

async function cmdKey() {
  let key = argv[1] && !argv[1].startsWith("--") ? argv[1] : "";
  if (!key && !process.stdin.isTTY) key = fs.readFileSync(0, "utf8");
  key = key.trim();
  if (!key) die("передай ключ аргументом або через stdin: printf %s \"$KEY\" | node tools/gen-art.mjs key");
  if (!looksLikeKey(key)) console.warn(`⚠ ключ не схожий на Google API key (AIza…, 39 символів) — зберігаю все одно`);
  const f = P(".env.local");
  const prev = fs.existsSync(f) ? fs.readFileSync(f, "utf8") : "";
  fs.writeFileSync(f, upsertEnv(prev, KEY_ENV, key), { mode: 0o600 });
  fs.chmodSync(f, 0o600);
  try { execFileSync("git", ["check-ignore", "-q", ".env.local"], { cwd: ROOT }); }
  catch { die(".env.local НЕ ігнорується git — ключ під загрозою коміту; виправ .gitignore перед продовженням"); }
  console.log(`✔ збережено ${maskKey(key)} → .env.local (0600, gitignored)`);
  if (!flag("no-check")) await check(key, opt("model", DEFAULT_MODEL));
}

// ------------------------------------------------------------------ manifest
function cmdSync() {
  const cat = readJSON(P("godot", "content", "catalog.json"));
  const before = readJSON(MANIFEST, null);
  const next = buildManifest(cat, before);
  writeJSON(MANIFEST, next);
  const prevIds = new Set(((before && before.assets) || []).map((a) => a.id));
  const added = next.assets.filter((a) => !prevIds.has(a.id)).length;
  const orphans = next.assets.filter((a) => a.orphan).length;
  console.log(`✔ manifest: ${next.assets.length} assets (+${added} нових${orphans ? `, ${orphans} orphan` : ""})`);
}

function cmdStatus() {
  const m = readJSON(MANIFEST, null) || die("немає art/manifest.json — запусти sync");
  const t = {};
  for (const a of m.assets) { (t[a.kind] ||= {})[a.status] = ((t[a.kind] || {})[a.status] || 0) + 1; }
  const statuses = ["todo", "draft", "approved"];
  console.log(["kind".padEnd(8), ...statuses.map((s) => s.padStart(9))].join(""));
  for (const [k, v] of Object.entries(t)) console.log([k.padEnd(8), ...statuses.map((s) => String(v[s] || 0).padStart(9))].join(""));
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

// Candidate variants on disk: v0.png, v1.png … (v*.raw.png / v*.meta.json are sidecars, not counted).
function versions(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).map((f) => f.match(/^v(\d+)\.(?:raw\.png|png|meta\.json)$/)).filter(Boolean).map((m) => +m[1]);
}
const nextVersion = (dir) => { const v = versions(dir); return v.length ? Math.max(...v) + 1 : 0; };

function refParts(kind) {
  if (kind === "ref") return { parts: [], sig: "" }; // anchors define the style; they never condition on themselves
  const picked = pickRefs(listRefs(), kind);
  const parts = picked.map((f) => ({ inlineData: { mimeType: "image/png", data: fs.readFileSync(path.join(REFS, f)).toString("base64") } }));
  const sig = picked.map((f) => `${f}:${fs.statSync(path.join(REFS, f)).size}`).join(",");
  return { parts, sig, picked };
}

async function generateOne(key, model, asset, prompt, refs, variant) {
  const body = {
    contents: [{ role: "user", parts: [...refs.parts, { text: prompt }] }],
    generationConfig: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio: KINDS[asset.kind].aspect } },
  };
  for (let attempt = 0; attempt < 5; attempt++) {
    const r = await api(`models/${model}:generateContent`, { key, method: "POST", body });
    if (r.ok) {
      const cand = r.json && r.json.candidates && r.json.candidates[0];
      const img = cand && cand.content && (cand.content.parts || []).find((p) => p.inlineData);
      if (img) return { data: Buffer.from(img.inlineData.data, "base64"), usage: r.json.usageMetadata || null };
      const why = (cand && cand.finishReason) || (r.json.promptFeedback && r.json.promptFeedback.blockReason) || "no image part";
      throw new Error(`${asset.id} v${variant}: модель не повернула зображення (${why})`);
    }
    const q = r.status === 429 ? classify429(r.json) : null;
    if (![429, 500, 502, 503, 504].includes(r.status) || (q && q.fatal)) {
      const e = new Error(`${asset.id}: ${explainHttp(r.status, r.json)}`);
      e.fatal = true; // same answer for every job in this run — stop the whole batch
      throw e;
    }
    const wait = Math.min(60000, (q && q.retryMs) || 2000 * 2 ** attempt);
    if (q && q.retryMs && q.retryMs > 60000) {
      const e = new Error(`${asset.id}: ${explainHttp(r.status, r.json)} — сервер просить чекати ${Math.round(q.retryMs / 1000)}s; запусти пізніше`);
      e.fatal = true;
      throw e;
    }
    console.warn(`… ${asset.id}: ${r.status}, повтор через ${wait / 1000}s`);
    await sleep(wait);
  }
  throw new Error(`${asset.id}: вичерпано повтори`);
}

function postProcess(raw, out, asset) {
  const k = KINDS[asset.kind];
  const args = ["-I", P("tools", "art", "post.py"), raw, out, "--size", String(asset.size ?? k.size)];
  if (k.key) args.push("--key");
  if (asset.kind === "tile") args.push("--tile");
  if (asset.palette !== false && ["sprite", "actor", "tile"].includes(asset.kind)) args.push("--palette", P("art", "palette.json"));
  execFileSync("python3", args, { stdio: "inherit" });
}

async function pool(items, n, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (next < items.length) { const i = next++; results[i] = await fn(items[i], i); }
  }));
  return results;
}

async function cmdGen() {
  const manifest = readJSON(MANIFEST, null) || die("немає art/manifest.json — запусти: node tools/gen-art.mjs sync");
  const style = fs.existsSync(STYLE) ? fs.readFileSync(STYLE, "utf8") : die("немає art/style.md");
  const model = opt("model", DEFAULT_MODEL);
  const n = Math.max(1, Math.min(4, Number(opt("n", 1)) || 1));
  const dry = flag("dry");
  const only = opt("only") ? opt("only").split(",").map((s) => s.trim()).filter(Boolean) : null;
  const { picked, dropped } = selectAssets(manifest, {
    only, kind: opt("kind"), prefix: opt("prefix"), force: flag("force"), limit: Number(opt("limit", 12)),
  });
  if (!picked.length) return console.log("нічого генерувати (усе draft/approved або фільтр порожній; --force / --only щоб перегенерувати)");
  if (dropped) console.log(`ℹ ліміт: ${picked.length} у цьому запуску, ще ${dropped} відкладено (--limit N)`);
  const kinds = new Set(picked.map((a) => a.kind));
  if (!listRefs().length && [...kinds].some((k) => k !== "ref"))
    console.warn("⚠ art/refs/ порожній — стиль триматиметься лише текстом. Рекомендовано спершу: gen --kind ref → approve ref_world");
  const key = dry ? "" : requireKey();
  const byId = new Map(manifest.assets.map((a) => [a.id, a]));
  // Variant numbers are reserved up-front per asset so concurrent jobs never race on the directory listing.
  const base = new Map(picked.map((a) => [a.id, nextVersion(path.join(OUT, a.kind, a.id))]));
  const jobs = picked.flatMap((a) => Array.from({ length: n }, (_, v) => ({ a, v })));
  let okCount = 0, fail = 0, halted = null;

  await pool(jobs, Number(opt("concurrency", 2)) || 2, async ({ a, v }) => {
    if (halted) return;
    const refs = refParts(a.kind);
    const prompt = composePrompt(style, a);
    const hash = promptHash(prompt, model, refs.sig);
    if (dry) { if (v === 0) console.log(`\n── ${a.id} [${a.kind}] hash=${hash} refs=${(refs.picked || []).join(",") || "—"}\n${prompt}`); return; }
    const dir = path.join(OUT, a.kind, a.id);
    fs.mkdirSync(dir, { recursive: true });
    const ver = base.get(a.id) + v;
    try {
      const { data, usage } = await generateOne(key, model, a, prompt, refs, ver);
      const raw = path.join(dir, `v${ver}.raw.png`);
      fs.writeFileSync(raw, data);
      postProcess(raw, path.join(dir, `v${ver}.png`), a);
      writeJSON(path.join(dir, `v${ver}.meta.json`), { id: a.id, kind: a.kind, variant: ver, model, hash, refs: refs.picked || [], usage, prompt });
      const row = byId.get(a.id);
      row.hash = hash;
      if (row.status !== "approved") row.status = "draft";
      okCount++;
      console.log(`✔ ${path.relative(ROOT, path.join(dir, `v${ver}.png`))}`);
    } catch (e) {
      fail++;
      if (e.fatal) { if (!halted) { halted = e; console.error(`✖ ${e.message}\n  ⏹ батч зупинено: ця відповідь однакова для всіх асетів`); } }
      else console.error(`✖ ${e.message}`);
      if (/недійсний|прострочений/.test(e.message)) process.exitCode = 2;
      else if (/квота 0/.test(e.message)) process.exitCode = 3;
    }
  });
  if (!dry) {
    writeJSON(MANIFEST, manifest);
    const skipped = halted ? jobs.length - okCount - fail : 0;
    console.log(`\n${okCount} згенеровано, ${fail} помилок${skipped ? `, ${skipped} пропущено (батч зупинено)` : ""}.${okCount ? " Переглянь art/out/ і зроби: node tools/gen-art.mjs approve <id>@vN" : ""}`);
    if (fail) process.exitCode ||= 1;
  }
}

// ------------------------------------------------------------------ approve
function cmdApprove() {
  const spec = argv[1] || die("approve <id>[@vN]");
  const [id, vRaw] = spec.split("@");
  const manifest = readJSON(MANIFEST, null) || die("немає manifest");
  const row = manifest.assets.find((a) => a.id === id) || die(`немає ${id} у manifest`);
  const dir = path.join(OUT, row.kind, id);
  const vers = [...new Set(versions(dir))].filter((x) => fs.existsSync(path.join(dir, `v${x}.png`)));
  if (!vers.length) die(`немає кандидатів у ${path.relative(ROOT, dir)}`);
  const v = vRaw != null ? +String(vRaw).replace(/^v/, "") : Math.max(...vers);
  if (!vers.includes(v)) die(`немає v${v} (є: ${vers.sort((x, y) => x - y).map((x) => "v" + x).join(", ")})`);
  const src = path.join(dir, `v${v}.png`);
  const meta = readJSON(path.join(dir, `v${v}.meta.json`), {});
  // refs anchor the style at full resolution (raw); game assets ship post-processed.
  const dest = row.kind === "ref" ? path.join(REFS, `${id}.png`) : path.join(GEN, row.kind, `${id}.png`);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(row.kind === "ref" ? path.join(dir, `v${v}.raw.png`) : src, dest);
  const { prompt, ...slim } = meta; // the prompt is reproducible from manifest+style; keep the sidecar small
  writeJSON(dest.replace(/\.png$/, ".meta.json"), { ...slim, approved_from: `v${v}`, prompt_chars: (prompt || "").length });
  row.status = "approved";
  row.approved = `v${v}`;
  writeJSON(MANIFEST, manifest);
  console.log(`✔ ${id}@v${v} → ${path.relative(ROOT, dest)}`);
}

// ------------------------------------------------------------------ main
const commands = {
  key: cmdKey,
  check: () => check(requireKey(), opt("model", DEFAULT_MODEL)),
  sync: cmdSync,
  status: cmdStatus,
  gen: cmdGen,
  approve: cmdApprove,
};
if (!commands[cmd]) {
  console.log(fs.readFileSync(url.fileURLToPath(import.meta.url), "utf8").split("\n").slice(1, 18).map((l) => l.replace(/^\/\/ ?/, "")).join("\n"));
  process.exit(cmd ? 1 : 0);
}
Promise.resolve(commands[cmd]()).catch((e) => die(e.message));

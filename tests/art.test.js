"use strict";
// RealWorld — art.test.js : pins the PURE half of the gen-art pipeline (tools/art/lib.mjs).
// No network, no key: proves manifest sync is idempotent and never clobbers human edits, prompts carry
// the style bible + kind frame + era, selection respects todo/draft/approved, and key hygiene holds.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { loadCatalog } = require("./_catalog");

const lib = () => import("../tools/art/lib.mjs");
const ROOT = path.join(__dirname, "..");
const liveOf = async () => (await lib()).parseDataGd(fs.readFileSync(path.join(ROOT, "godot", "scripts", "data.gd"), "utf8"));

test("manifest covers every catalog def + terrain + extras, ids unique, kinds known", async () => {
  const { buildManifest, KINDS, TERRAIN, EXTRA } = await lib();
  const cat = loadCatalog();
  const live = await liveOf();
  const m = buildManifest(cat, null, live);
  const ids = m.assets.map((a) => a.id);
  assert.strictEqual(new Set(ids).size, ids.length, "duplicate asset id");
  const liveOnly = m.assets.filter((a) => a.src.startsWith("live/")).length;
  const expected = cat.resources.length + cat.items.length + cat.buildings.length + cat.research.length + TERRAIN.length + EXTRA.length + liveOnly;
  assert.strictEqual(m.assets.length, expected);
  // every id the playable game renders (data.gd) has an art row — the integration target
  for (const r of live.resources) assert.ok(ids.includes(`res_${r.id}`), `res_${r.id}`);
  for (const b of live.buildings) assert.ok(ids.includes(`bld_${b.id}`), `bld_${b.id}`);
  for (const i of live.items) assert.ok(ids.includes(`item_${i.id}`), `item_${i.id}`);
  assert.ok(live.items.length >= 8 && live.buildings.length >= 13, "parseDataGd lost rows");
  for (const a of m.assets) {
    assert.ok(KINDS[a.kind], `${a.id}: unknown kind ${a.kind}`);
    assert.strictEqual(a.status, "todo");
    assert.ok(a.subject && a.subject.length > 3, `${a.id}: empty subject`);
    assert.doesNotMatch(a.subject, /structure structure|a art/, `${a.id}: template artefact`);
  }
  assert.strictEqual(m.assets.find((a) => a.id === "bld_floor").kind, "tile", "floors fill the cell → tile");
  assert.strictEqual(m.assets.find((a) => a.id === "bld_grow_zone").kind, "tile");
  assert.match(m.assets.find((a) => a.id === "bld_wall").subject, /1×1 grid-cell segment/);
  for (const b of cat.buildings) assert.ok(ids.includes(`bld_${b.id}`));
});

test("sync: idempotent; human-edited subject frozen, template subject follows fixes; manual rows kept; removed defs orphaned", async () => {
  const { buildManifest } = await lib();
  const cat = loadCatalog();
  const live = await liveOf();
  const m1 = buildManifest(cat, null, live);
  const edited = JSON.parse(JSON.stringify(m1));
  const row = edited.assets.find((a) => a.id === "bld_wall");
  Object.assign(row, { subject: "custom wall", status: "approved", hash: "deadbeef", notes: "keep", kind: "WRONG" });
  const tmpl = edited.assets.find((a) => a.id === "bld_door");
  tmpl.subject = tmpl.auto = "old template text"; // untouched by humans: must pick up the new template
  edited.assets.push({ id: "bld_gone", kind: "sprite", subject: "x", status: "approved", src: "buildings/gone" });
  edited.assets.push({ id: "ui_build", kind: "ui", subject: "hammer pictogram", status: "todo", manual: true });
  const m2 = buildManifest(cat, edited, live);
  const w = m2.assets.find((a) => a.id === "bld_wall");
  assert.deepStrictEqual([w.subject, w.status, w.hash, w.notes, w.kind], ["custom wall", "approved", "deadbeef", "keep", "sprite"]);
  assert.strictEqual(m2.assets.find((a) => a.id === "bld_door").subject, m1.assets.find((a) => a.id === "bld_door").subject);
  assert.strictEqual(m2.assets.find((a) => a.id === "bld_gone").orphan, true);
  const ui = m2.assets.find((a) => a.id === "ui_build");
  assert.ok(ui && !ui.orphan, "manual row must survive sync un-orphaned");
  assert.deepStrictEqual(buildManifest(cat, m2, live), m2, "second sync changed the manifest");
});

test("committed art/manifest.json is in sync with catalog.json (run `node tools/gen-art.mjs sync`)", async () => {
  const { buildManifest } = await lib();
  const f = path.join(ROOT, "art", "manifest.json");
  const onDisk = JSON.parse(fs.readFileSync(f, "utf8"));
  assert.deepStrictEqual(buildManifest(loadCatalog(), onDisk, await liveOf()), onDisk);
});

test("prompt = style bible + kind frame + era + subject, never mentions other games", async () => {
  const { composePrompt, eraOf } = await lib();
  const style = fs.readFileSync(path.join(ROOT, "art", "style.md"), "utf8");
  const p = composePrompt(style, { id: "item_stone_axe", kind: "icon", tier: 0, subject: "stone axe (tool)", label: "Кам'яна сокира" });
  assert.ok(p.startsWith("STYLE GUIDE (instructions only"));
  assert.doesNotMatch(p, /ART BIBLE/, "bible title leaks into images as lettering");
  assert.match(p, /WORLD: an AI post-apocalypse/, "lore anchor (2026-11-04: the world is an AI post-apocalypse)");
  assert.match(p, /FRAME: One inventory icon/);
  assert.ok(p.includes(eraOf(0)));
  assert.match(p, /SUBJECT: stone axe/);
  assert.match(p, /Кам'яна сокира/);
  assert.doesNotMatch(p, /rimworld|factorio|in the style of/i);
  assert.notStrictEqual(eraOf(1), eraOf(9));
  assert.throws(() => composePrompt(style, { id: "x", kind: "nope", subject: "x" }));
  const timeless = composePrompt(style, { id: "node_tree", kind: "sprite", tier: null, subject: "a tree" });
  assert.doesNotMatch(timeless, /^ERA:/m, "nature/terrain/anchors carry no era");
});

test("promptHash changes with prompt, model and refs", async () => {
  const { promptHash } = await lib();
  const h = promptHash("a", "m", "r");
  assert.match(h, /^[0-9a-f]{8}$/);
  assert.notStrictEqual(h, promptHash("b", "m", "r"));
  assert.notStrictEqual(h, promptHash("a", "m2", "r"));
  assert.notStrictEqual(h, promptHash("a", "m", "r2"));
  assert.strictEqual(h, promptHash("a", "m", "r"));
});

test("selection: todo by default, draft needs --only/--force, approved needs --only AND --force, limit reports drops", async () => {
  const { selectAssets } = await lib();
  const m = { assets: [
    { id: "a", kind: "icon", status: "todo" }, { id: "b", kind: "icon", status: "draft" },
    { id: "c", kind: "icon", status: "approved" }, { id: "d", kind: "tile", status: "todo" },
    { id: "e", kind: "icon", status: "todo", orphan: true },
  ] };
  const ids = (o) => selectAssets(m, o).picked.map((a) => a.id).join(",");
  assert.strictEqual(ids({}), "a,d");
  assert.strictEqual(ids({ kind: "icon" }), "a");
  assert.strictEqual(ids({ force: true }), "a,b,d");
  assert.strictEqual(ids({ only: ["b", "c"] }), "b");
  assert.strictEqual(ids({ only: ["c"], force: true }), "c");
  assert.strictEqual(ids({ only: ["e"], force: true }), "");
  assert.deepStrictEqual(selectAssets(m, { limit: 1 }).dropped, 1);
  // spend cap: an invalid limit never means "everything"
  const big = { assets: Array.from({ length: 40 }, (_, i) => ({ id: `x${i}`, kind: "icon", status: "todo" })) };
  for (const bad of [0, -1, NaN, 2.5, undefined]) assert.strictEqual(selectAssets(big, { limit: bad }).picked.length, 12, String(bad));
  // a draft whose candidates are gone (fresh checkout; art/out is gitignored) is generatable again
  assert.strictEqual(ids({ hasCandidates: () => false }), "a,b,d");
  assert.strictEqual(ids({ hasCandidates: () => true }), "a,d");
});

test("key hygiene: dotenv parse/upsert, mask never reveals the middle, shape check", async () => {
  const { parseEnv, upsertEnv, maskKey, looksLikeKey } = await lib();
  const fake = "AIza" + "x".repeat(35);
  assert.strictEqual(parseEnv(`# c\nexport GEMINI_API_KEY="${fake}"\nOTHER=1`).GEMINI_API_KEY, fake);
  const up = upsertEnv("OTHER=1\nGEMINI_API_KEY=old\n", "GEMINI_API_KEY", "new");
  assert.strictEqual(up, "OTHER=1\nGEMINI_API_KEY=new\n");
  assert.strictEqual(upsertEnv("", "K", "v"), "K=v\n");
  assert.strictEqual(maskKey(fake), "AIza…xxxx");
  assert.ok(!maskKey(fake).includes("x".repeat(5)));
  assert.ok(looksLikeKey(fake));
  assert.ok(!looksLikeKey("sk-123"));
});

test("pickRefs: kind-specific first, then global, capped at 3; subfolders of other kinds excluded", async () => {
  const { pickRefs } = await lib();
  const files = ["ref_ground.png", "ref_world.png", "tile/grass.png", "icon/a.png", "icon/b.png", "icon/c.png"];
  assert.deepStrictEqual(pickRefs(files, "icon"), ["icon/a.png", "icon/b.png", "icon/c.png"]);
  assert.deepStrictEqual(pickRefs(files, "sprite"), ["ref_ground.png", "ref_world.png"]);
  assert.deepStrictEqual(pickRefs(files, "tile"), ["tile/grass.png", "ref_ground.png", "ref_world.png"]);
});

test(".env.local (where the key lives) is gitignored and generation drafts stay out of git", () => {
  const gi = fs.readFileSync(path.join(ROOT, ".gitignore"), "utf8");
  assert.match(gi, /^\.env\.\*$/m);
  assert.match(gi, /^art\/out\/$/m);
});

test("429 triage: free-tier `limit: 0` is fatal (no retry loop); transient bursts carry a retry delay", async () => {
  const { classify429 } = await lib();
  const hard = { error: { code: 429, message: "Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 0, model: gemini-3-pro-image\nPlease retry in 5m4.49s." } };
  assert.deepStrictEqual(classify429(hard), { fatal: true, freeTierZero: true, daily: false, retryMs: 304490 });
  const burst = { error: { code: 429, message: "Resource has been exhausted (e.g. check quota).", details: [{ "@type": "type.googleapis.com/google.rpc.RetryInfo", retryDelay: "7s" }] } };
  assert.deepStrictEqual(classify429(burst), { fatal: false, freeTierZero: false, daily: false, retryMs: 7000 });
  assert.deepStrictEqual(classify429(null), { fatal: false, freeTierZero: false, daily: false, retryMs: null });
  const day = { error: { message: "Quota exceeded for metric: generate_content_requests, limit: 250, description: requests per day" } };
  assert.deepStrictEqual(classify429(day), { fatal: true, freeTierZero: false, daily: true, retryMs: null });
});

test("both Google key shapes (AIza… and AQ.…) are recognized and caught by the lint secret-scan pattern", async () => {
  const { looksLikeKey, KEY_SCAN_RE } = await lib();
  const classic = "AIza" + "x".repeat(35);
  const studio = "AQ." + "Ab8" + "y".repeat(45);
  for (const k of [classic, studio]) { assert.ok(looksLikeKey(k), k.slice(0, 3)); assert.ok(KEY_SCAN_RE.test(`k = "${k}"`)); }
  assert.ok(!KEY_SCAN_RE.test("AQ.short"));
  assert.ok(!KEY_SCAN_RE.test("plain text with AQ. in it"));
});

test("CLI is strict: unknown flags, bad limits and shut-down models fail BEFORE any key/API use", () => {
  const { spawnSync } = require("node:child_process");
  const run = (...a) => spawnSync(process.execPath, [path.join(ROOT, "tools", "gen-art.mjs"), ...a], { encoding: "utf8", env: { ...process.env, GEMINI_API_KEY: "" } });
  for (const argv of [["gen", "--dyr"], ["gen", "--limit", "0"], ["gen", "--n", "9"], ["gen", "--model", "gemini-3-pro-image-preview", "--dry"], ["gen", "--only", "no_such_id", "--dry"], ["approve", "actor_hero@x"], ["bogus"]]) {
    const r = run(...argv);
    assert.notStrictEqual(r.status, 0, argv.join(" "));
    assert.match(r.stderr, /✖/, argv.join(" "));
  }
  const help = run("--help");
  assert.strictEqual(help.status, 0);
  assert.doesNotMatch(help.stdout, /^import /m, "help prints source code");
  const dry = run("gen", "--only", "node_tree", "--force", "--dry");
  assert.strictEqual(dry.status, 0, dry.stderr);
  assert.match(dry.stdout, /SUBJECT: a temperate deciduous tree/);
});

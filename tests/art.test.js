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

test("manifest covers every catalog def + terrain + extras, ids unique, kinds known", async () => {
  const { buildManifest, KINDS, TERRAIN, EXTRA } = await lib();
  const cat = loadCatalog();
  const m = buildManifest(cat, null);
  const ids = m.assets.map((a) => a.id);
  assert.strictEqual(new Set(ids).size, ids.length, "duplicate asset id");
  const expected = cat.resources.length + cat.items.length + cat.buildings.length + cat.research.length + TERRAIN.length + EXTRA.length;
  assert.strictEqual(m.assets.length, expected);
  for (const a of m.assets) {
    assert.ok(KINDS[a.kind], `${a.id}: unknown kind ${a.kind}`);
    assert.strictEqual(a.status, "todo");
    assert.ok(a.subject && a.subject.length > 3, `${a.id}: empty subject`);
  }
  for (const b of cat.buildings) assert.ok(ids.includes(`bld_${b.id}`));
});

test("sync is idempotent and preserves human edits; removed defs become orphans, not deletions", async () => {
  const { buildManifest } = await lib();
  const cat = loadCatalog();
  const m1 = buildManifest(cat, null);
  const edited = JSON.parse(JSON.stringify(m1));
  const row = edited.assets.find((a) => a.id === "bld_wall");
  Object.assign(row, { subject: "custom wall", status: "approved", hash: "deadbeef", notes: "keep", kind: "WRONG" });
  edited.assets.push({ id: "bld_gone", kind: "sprite", subject: "x", status: "approved" });
  const m2 = buildManifest(cat, edited);
  const w = m2.assets.find((a) => a.id === "bld_wall");
  assert.deepStrictEqual([w.subject, w.status, w.hash, w.notes, w.kind], ["custom wall", "approved", "deadbeef", "keep", "sprite"]);
  assert.strictEqual(m2.assets.find((a) => a.id === "bld_gone").orphan, true);
  assert.deepStrictEqual(buildManifest(cat, m2), m2, "second sync changed the manifest");
});

test("committed art/manifest.json is in sync with catalog.json (run `node tools/gen-art.mjs sync`)", async () => {
  const { buildManifest } = await lib();
  const f = path.join(ROOT, "art", "manifest.json");
  const onDisk = JSON.parse(fs.readFileSync(f, "utf8"));
  assert.deepStrictEqual(buildManifest(loadCatalog(), onDisk), onDisk);
});

test("prompt = style bible + kind frame + era + subject, never mentions other games", async () => {
  const { composePrompt, eraOf } = await lib();
  const style = fs.readFileSync(path.join(ROOT, "art", "style.md"), "utf8");
  const p = composePrompt(style, { id: "item_stone_axe", kind: "icon", tier: 0, subject: "stone axe (tool)", label: "Кам'яна сокира" });
  assert.ok(p.startsWith("ART BIBLE"));
  assert.match(p, /FRAME: One inventory icon/);
  assert.ok(p.includes(eraOf(0)));
  assert.match(p, /SUBJECT: stone axe/);
  assert.match(p, /Кам'яна сокира/);
  assert.doesNotMatch(p, /rimworld|factorio|in the style of/i);
  assert.notStrictEqual(eraOf(1), eraOf(9));
  assert.throws(() => composePrompt(style, { id: "x", kind: "nope", subject: "x" }));
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
  assert.deepStrictEqual(classify429(hard), { fatal: true, freeTierZero: true, retryMs: 304490 });
  const burst = { error: { code: 429, message: "Resource has been exhausted (e.g. check quota).", details: [{ "@type": "type.googleapis.com/google.rpc.RetryInfo", retryDelay: "7s" }] } };
  assert.deepStrictEqual(classify429(burst), { fatal: false, freeTierZero: false, retryMs: 7000 });
  assert.deepStrictEqual(classify429(null), { fatal: false, freeTierZero: false, retryMs: null });
});

test("both Google key shapes (AIza… and AQ.…) are recognized and caught by the lint secret-scan pattern", async () => {
  const { looksLikeKey, KEY_SCAN_RE } = await lib();
  const classic = "AIza" + "x".repeat(35);
  const studio = "AQ." + "Ab8" + "y".repeat(45);
  for (const k of [classic, studio]) { assert.ok(looksLikeKey(k), k.slice(0, 3)); assert.ok(KEY_SCAN_RE.test(`k = "${k}"`)); }
  assert.ok(!KEY_SCAN_RE.test("AQ.short"));
  assert.ok(!KEY_SCAN_RE.test("plain text with AQ. in it"));
});

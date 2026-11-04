// RealWorld — tools/art/lib.mjs : PURE half of the gen-art pipeline (no fs, no network, no clock).
//
// Everything here is a function of its arguments so tests/art.test.js can pin it in Node:
//   • key hygiene      — parseEnv / maskKey / looksLikeKey (the key NEVER reaches stdout, git or meta);
//   • manifest         — buildManifest(catalog, existing): catalog.json → art/manifest.json, idempotent,
//                        never clobbers human edits (subject/status/hash/notes survive a re-sync);
//   • prompt           — composePrompt(style, asset): style bible + kind frame + era + subject;
//   • selection        — selectAssets(manifest, opts): what a `gen` run is allowed to touch.
// The impure CLI (tools/gen-art.mjs) only does IO around these.

// ---------------------------------------------------------------- key hygiene
export const KEY_ENV = "GEMINI_API_KEY";
// Two Google key shapes: classic `AIza…` (39 chars) and the newer AI Studio `AQ.…` keys.
const KEY_RE = /^(?:AIza[0-9A-Za-z_-]{35}|AQ\.[0-9A-Za-z_-]{40,})$/;
// Same shapes un-anchored — the secret-scan pattern tools/lint.mjs greps every tracked file with.
export const KEY_SCAN_RE = /AIza[0-9A-Za-z_-]{35}|AQ\.[0-9A-Za-z_-]{40,}/;

// Minimal dotenv: KEY=VALUE lines, optional quotes, # comments. Returns a plain object.
export function parseEnv(text) {
  const out = {};
  for (const raw of String(text || "").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const m = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    out[m[1]] = v;
  }
  return out;
}

// Upsert one KEY=VALUE into dotenv text, keeping every other line intact.
export function upsertEnv(text, key, value) {
  const lines = String(text || "").split(/\r?\n/).filter((l, i, a) => !(i === a.length - 1 && l === ""));
  const re = new RegExp(`^\\s*(?:export\\s+)?${key}\\s*=`);
  const i = lines.findIndex((l) => re.test(l));
  if (i >= 0) lines[i] = `${key}=${value}`; else lines.push(`${key}=${value}`);
  return lines.join("\n") + "\n";
}

export const looksLikeKey = (k) => KEY_RE.test(String(k || "").trim());
export const maskKey = (k) => {
  const s = String(k || "");
  return s.length < 8 ? "∅" : `${s.slice(0, 4)}…${s.slice(-4)}`;
};

// 429 triage. Google returns RESOURCE_EXHAUSTED for both a transient per-minute burst AND a hard
// "this tier has no quota for this model" (free tier image models: `limit: 0`). Retrying the latter
// just burns minutes, so it is classified as fatal. `retryMs` honours "Please retry in 5m4.9s" / RetryInfo.
export function classify429(body) {
  const err = (body && body.error) || {};
  const msg = String(err.message || "");
  const zero = /limit:\s*0\b/.test(msg);
  const free = /free_tier/i.test(msg);
  let retryMs = null;
  const m = msg.match(/retry in\s+(?:(\d+)h)?(?:(\d+)m)?([\d.]+)s/i);
  if (m) retryMs = Math.round(((+m[1] || 0) * 3600 + (+m[2] || 0) * 60 + (+m[3] || 0)) * 1000);
  for (const d of err.details || []) {
    const rd = d && d.retryDelay && String(d.retryDelay).match(/^([\d.]+)s$/);
    if (rd && retryMs == null) retryMs = Math.round(+rd[1] * 1000);
  }
  return { fatal: zero, freeTierZero: zero && free, retryMs };
}

// ---------------------------------------------------------------- kinds (the conceptual frame)
// Every kind fixes camera, background, framing and target size — the subject never repeats these.
// `key: true` = drawn on flat magenta and chroma-keyed to alpha by tools/art/post.py.
export const KINDS = {
  ref: {
    size: 0, key: false, aspect: "1:1",
    frame: "Style reference sheet: a neat grid of 6–9 small props and characters from this world on a plain dark slate background (#0e1216), evenly spaced, each fully visible, consistent scale and lighting. This sheet defines the art style for the whole game.",
  },
  sprite: {
    size: 128, key: true, aspect: "1:1",
    frame: "One game sprite of a placeable object seen from a top-down three-quarter view (camera ~60° above the ground). Centered, the whole object visible with a small margin, sitting on the ground plane. Background: perfectly flat solid magenta #FF00FF, no gradient, no floor, no cast shadow on the background.",
  },
  actor: {
    size: 128, key: true, aspect: "1:1",
    frame: "One character sprite seen from a top-down three-quarter view, standing, facing down-right, full body visible, readable silhouette. Background: perfectly flat solid magenta #FF00FF, no gradient, no floor, no cast shadow on the background.",
  },
  icon: {
    size: 128, key: true, aspect: "1:1",
    frame: "One inventory icon of a single object, slight three-quarter angle, centered, filling ~80% of the frame, bold clear silhouette readable at 32 px. Background: perfectly flat solid magenta #FF00FF, no gradient, no glow, no frame, no shadow on the background.",
  },
  tile: {
    size: 64, key: false, aspect: "1:1",
    frame: "One seamless, tileable square ground texture seen strictly from directly above (orthographic). Uniform coverage edge to edge, no objects, no horizon, no vignette, no border, NO outlines (the outline rule applies to objects only); the left/right and top/bottom edges must wrap seamlessly.",
  },
  ui: {
    size: 64, key: true, aspect: "1:1",
    frame: "One flat UI pictogram for a game HUD button, simple geometric shapes, 2–3 tones, centered, generous padding, readable at 20 px. Background: perfectly flat solid magenta #FF00FF.",
  },
};

// Era by tech tier (catalog research tiers run 1..9, resource tiers 0..3). Keeps a neolithic axe and a
// plasteel turret in one coherent world instead of one generic "game art" register.
export function eraOf(tier) {
  const t = Number(tier) || 0;
  if (t <= 1) return "primitive survivor craft: hand-made from wood, stone, bone, hide, plant fiber; lashings and rough edges";
  if (t <= 3) return "pre-industrial rebuild: forged iron, fired brick, rope, planks, simple mechanisms";
  if (t <= 5) return "salvage-industrial: riveted steel, scavenged old-world machinery, cables, worn paint";
  if (t <= 7) return "rebuilt high-tech: clean steel and composite panels, small indicator lights, circuitry";
  return "frontier spacefaring tech: plasteel, sealed composite shells, restrained cyan glow";
}

const humanize = (id) => String(id).replace(/[_-]+/g, " ").trim();

// Terrain set mirrors world_gen.gd TERRAIN_NAME (index order) — tiles are generated per terrain kind.
export const TERRAIN = [
  ["water", "shallow murky river water, subtle ripples"],
  ["grass", "temperate meadow grass, patchy, a few small weeds"],
  ["forest", "forest floor: moss, needles, leaf litter, small roots"],
  ["rock", "exposed grey bedrock with cracks and lichen"],
  ["road", "cracked old asphalt road surface with faded paint fragments and weeds in cracks"],
  ["dirt", "bare packed soil with pebbles"],
  ["ruins", "rubble of collapsed concrete buildings, broken bricks, rebar"],
  ["sand", "coarse river sand with small shells and pebbles"],
  ["snow", "trampled old snow with icy patches"],
];

// Hand-authored anchors the catalog does not cover. Their subjects are the canon; edit freely.
export const EXTRA = [
  { id: "ref_world", kind: "ref", subject: "survivors' world props: a stone axe, a campfire, a wooden wall segment, a crate of scrap, a hide tent, a rusted patrol robot, a survivor in patched layered clothes, a steel turret, a berry bush", tier: 4 },
  { id: "ref_ground", kind: "ref", subject: "ground swatches arranged as a grid: grass, forest floor, water, old asphalt, rubble, snow — each a square swatch seen from above", tier: 2 },
  { id: "actor_hero", kind: "actor", subject: "a lone survivor in patched layered clothing, scarf, backpack with bedroll, improvised tools on belt", tier: 2 },
  { id: "actor_raider", kind: "actor", subject: "a hostile clan raider with mismatched scrap armor, painted mask, crude spear", tier: 2 },
  { id: "actor_patrol_robot", kind: "actor", subject: "an old-world autonomous patrol robot, quadruped chassis, weathered, one cracked sensor eye, still functional and hostile", tier: 6 },
  { id: "node_tree", kind: "sprite", subject: "a temperate deciduous tree, harvestable for wood", tier: 0 },
  { id: "node_rock", kind: "sprite", subject: "a mineable boulder outcrop with visible ore streaks", tier: 0 },
  { id: "node_bush", kind: "sprite", subject: "a wild berry bush with herbs at its base", tier: 0 },
  { id: "node_scrap", kind: "sprite", subject: "a heap of old-world scrap: rusted car panels, wires, broken electronics", tier: 4 },
];

// ---------------------------------------------------------------- manifest
// Fields owned by the CATALOG (re-derived every sync) vs. by HUMANS (never overwritten once present).
const DERIVED = ["kind", "src", "label", "tier", "size"];

function fromCatalog(cat) {
  const researchTier = new Map((cat.research || []).map((r) => [r.id, r.tier]));
  const gateTier = (gate) => (gate ? researchTier.get(gate) || 1 : 0);
  const out = [];
  for (const r of cat.resources || []) {
    out.push({ id: `res_${r.id}`, kind: "icon", src: `resources/${r.id}`, label: r.label, tier: (r.tier || 0) * 2,
      subject: `${humanize(r.id)} — a stack or bundle of this raw/processed material` });
  }
  for (const i of cat.items || []) {
    out.push({ id: `item_${i.id}`, kind: "icon", src: `items/${i.id}`, label: i.label, tier: gateTier(i.research),
      subject: `${humanize(i.id)} (${i.kind}${i.slot && i.slot !== i.kind ? `, worn/used as ${i.slot}` : ""})` });
  }
  for (const b of cat.buildings || []) {
    out.push({ id: `bld_${b.id}`, kind: "sprite", src: `buildings/${b.id}`, label: b.label, tier: gateTier(b.research),
      subject: `${humanize(b.id)} — a ${b.category} structure built by survivors` });
  }
  for (const r of cat.research || []) {
    out.push({ id: `rsch_${r.id}`, kind: "icon", src: `research/${r.id}`, label: r.label, tier: r.tier,
      subject: `emblem for the technology "${humanize(r.id)}": one symbolic object that embodies it` });
  }
  TERRAIN.forEach(([id, subject], idx) => out.push({ id: `tile_${id}`, kind: "tile", src: `terrain/${idx}`, label: id, tier: 0, subject }));
  for (const e of EXTRA) out.push({ ...e, src: `extra/${e.id}`, label: e.id });
  return out;
}

// existing: previous manifest object (or null). Returns a NEW manifest; pure + idempotent:
// buildManifest(cat, buildManifest(cat, m)) deep-equals buildManifest(cat, m).
export function buildManifest(cat, existing) {
  const prev = new Map(((existing && existing.assets) || []).map((a) => [a.id, a]));
  const seen = new Set();
  const assets = [];
  for (const d of fromCatalog(cat)) {
    seen.add(d.id);
    d.size = KINDS[d.kind].size;
    const p = prev.get(d.id);
    if (!p) { assets.push({ ...d, status: "todo" }); continue; }
    const merged = { ...p };
    for (const k of DERIVED) merged[k] = d[k];
    if (merged.subject == null) merged.subject = d.subject;
    if (merged.status == null) merged.status = "todo";
    delete merged.orphan;
    assets.push(merged);
  }
  // A def removed from the catalog keeps its row (and approved art) but is flagged — never silently dropped.
  for (const [id, p] of prev) if (!seen.has(id)) assets.push({ ...p, orphan: true });
  assets.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return { version: 1, note: "Generated by `node tools/gen-art.mjs sync` from godot/content/catalog.json. Edit subject/status/notes freely — sync never overwrites them.", assets };
}

// ---------------------------------------------------------------- prompt
export function composePrompt(style, asset) {
  const kind = KINDS[asset.kind];
  if (!kind) throw new Error(`unknown kind "${asset.kind}" for ${asset.id}`);
  return [
    String(style || "").trim(),
    "",
    `FRAME: ${kind.frame}`,
    `ERA: ${eraOf(asset.tier)}`,
    `SUBJECT: ${asset.subject}`,
    asset.label && asset.label !== asset.id ? `(In-game name, Ukrainian: «${asset.label}».)` : "",
    asset.notes ? `ART DIRECTION NOTES: ${asset.notes}` : "",
    "Absolutely no text, letters, numbers, logos, watermark, signature, UI frame or border.",
  ].filter(Boolean).join("\n");
}

// FNV-1a 32 over the prompt + model + refs signature: changes when anything that shapes the image changes.
export function promptHash(prompt, model, refsSig = "") {
  let h = 0x811c9dc5;
  const s = `${model}\n${refsSig}\n${prompt}`;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, "0");
}

// ---------------------------------------------------------------- selection
// opts: { only?: string[], kind?: string, prefix?: string, force?: boolean, limit?: number }
// Default run touches only status "todo"; "draft" needs --force or --only; "approved" needs --only AND --force.
export function selectAssets(manifest, opts = {}) {
  const only = opts.only && opts.only.length ? new Set(opts.only) : null;
  const picked = [];
  for (const a of (manifest && manifest.assets) || []) {
    if (a.orphan) continue;
    if (only && !only.has(a.id)) continue;
    if (opts.kind && a.kind !== opts.kind) continue;
    if (opts.prefix && !a.id.startsWith(opts.prefix)) continue;
    if (a.status === "approved" && !(only && opts.force)) continue;
    if (a.status === "draft" && !(only || opts.force)) continue;
    picked.push(a);
  }
  const limit = Number.isFinite(opts.limit) && opts.limit > 0 ? opts.limit : picked.length;
  return { picked: picked.slice(0, limit), dropped: Math.max(0, picked.length - limit) };
}

// Order refs so kind-specific anchors come first, capped (Nano Banana is steadiest with ≤3 inputs).
export function pickRefs(files, kind, cap = 3) {
  const own = files.filter((f) => f.startsWith(`${kind}/`));
  const global = files.filter((f) => !f.includes("/"));
  return [...own, ...global].slice(0, cap);
}

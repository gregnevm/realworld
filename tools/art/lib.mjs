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
  const daily = !zero && (/per.?day|PerDay/i.test(msg) ||
    (err.details || []).some((d) => (d.violations || []).some((v) => /PerDay/i.test(String(v.quotaId || "")))));
  return { fatal: zero || daily, freeTierZero: zero && free, daily, retryMs };
}

// ---------------------------------------------------------------- kinds (the conceptual frame)
// Every kind fixes camera, background, framing and target size — the subject never repeats these.
// `key: true` = drawn on flat magenta and chroma-keyed to alpha by tools/art/post.py.
// Object kinds are composited over a chroma key, so anything TRANSLUCENT (smoke, scan beams, glow halos)
// mixes with the key and cannot be recovered — observed twice in the first live batches (campfire smoke,
// patrol-robot scan beam). The engine draws FX; sprites stay opaque. Refs also leaked props into subjects
// (berries from the ref sheet next to a stone axe), hence the "only this object" clause.
const SOLO = " Only this one subject: do not add props, plants or items from the reference images. Fully opaque art: no translucent effects — no smoke, steam, beams, scan rays, glow halos, auras or sparks (the game engine draws those).";

export const KINDS = {
  ref: {
    size: 0, key: false, aspect: "1:1",
    frame: "Style reference sheet: a neat grid of 6–9 small props and characters from this world on a plain dark slate background (#0e1216), evenly spaced, each fully visible, consistent scale and lighting. This sheet defines the art style for the whole game.",
  },
  sprite: {
    size: 128, key: true, aspect: "1:1",
    frame: "One game sprite of a placeable object seen from a top-down three-quarter view (camera ~60° above the ground). Centered, the whole object visible with a small margin, sitting on the ground plane. Background: a technical chroma-key that is NOT part of the art and is EXEMPT from the muted palette — exactly pure saturated magenta #FF00FF (RGB 255,0,255), perfectly flat, no vignette, no gradient, no floor, no cast shadow on it." + SOLO,
  },
  actor: {
    size: 128, key: true, aspect: "1:1",
    frame: "One character sprite seen from a top-down three-quarter view, standing, facing down-right, full body visible, readable silhouette. Background: a technical chroma-key that is NOT part of the art and is EXEMPT from the muted palette — exactly pure saturated magenta #FF00FF (RGB 255,0,255), perfectly flat, no vignette, no gradient, no floor, no cast shadow on it." + SOLO,
  },
  icon: {
    size: 128, key: true, aspect: "1:1",
    frame: "One inventory icon of a single object, slight three-quarter angle, centered, filling ~80% of the frame, bold clear silhouette readable at 32 px. Background: a technical chroma-key that is NOT part of the art and is EXEMPT from the muted palette — exactly pure saturated magenta #FF00FF (RGB 255,0,255), perfectly flat, no vignette, no gradient, no glow, no frame, no shadow on it." + SOLO,
  },
  tile: {
    size: 64, key: false, aspect: "1:1",
    frame: "One seamless, tileable square ground texture seen strictly from directly above (orthographic). The texture fills the ENTIRE image edge to edge — no card, no frame, no padding, no swatch layout (even if a reference shows swatch cards); uniform coverage, no objects, no horizon, no vignette, no border, NO outlines (the outline rule applies to objects only); the left/right and top/bottom edges must wrap seamlessly.",
  },
  ui: {
    size: 64, key: true, aspect: "1:1",
    frame: "One flat UI pictogram for a game HUD button, simple geometric shapes, 2–3 tones, centered, generous padding, readable at 20 px. Background: a technical chroma-key that is NOT part of the art and is EXEMPT from the muted palette — exactly pure saturated magenta #FF00FF (RGB 255,0,255), perfectly flat, no vignette, no gradient, no cast shadow on it." + SOLO,
  },
};

// Era by tech tier (catalog research tiers run 1..9, resource tiers 0..3). Keeps a neolithic axe and a
// plasteel turret in one coherent world instead of one generic "game art" register.
export function eraOf(tier) {
  const t = Number(tier) || 0;
  if (t <= 1) return "primitive survivor craft: hand-made from wood, stone, bone, hide, plant fiber; lashings and rough edges";
  if (t <= 3) return "pre-industrial rebuild: forged iron, fired brick, rope, planks, simple mechanisms";
  if (t <= 5) return "salvage-industrial: riveted steel, parts cut from machine carcasses, cables, worn paint";
  if (t <= 7) return "reverse-engineered machine tech: clean steel and composite panels with salvaged AI circuitry, small cold-teal indicator lights";
  return "frontier spacefaring tech built by humans from tamed AI-era hardware: plasteel, sealed composite shells, restrained cyan glow";
}

const humanize = (id) => String(id).replace(/[_-]+/g, " ").trim();

// Terrain set mirrors world_gen.gd TERRAIN_NAME (index order, Ukrainian label) — one tile per terrain kind.
export const TERRAIN = [
  ["water", "вода", "shallow murky river water, subtle ripples"],
  ["grass", "трава", "temperate meadow grass, patchy, a few small weeds"],
  ["forest", "ліс", "forest floor: moss, needles, leaf litter, small roots"],
  ["rock", "скеля", "exposed grey bedrock with cracks and lichen"],
  ["road", "дорога", "cracked old asphalt road surface with faded paint fragments and weeds in cracks"],
  ["dirt", "ґрунт", "bare packed soil with pebbles"],
  ["ruins", "руїни", "rubble of collapsed concrete buildings, broken bricks, rebar, scattered dead circuit boards and cable"],
  ["sand", "пісок", "coarse river sand with small shells and pebbles"],
  ["snow", "сніг", "trampled old snow with icy patches"],
];

// Hand-authored anchors the catalog does not cover. `tier: null` = timeless (nature, world anchors): no ERA
// line, so a tree is never told it is "hand-made from bone and hide".
export const EXTRA = [
  { id: "ref_world", kind: "ref", subject: "AI post-apocalypse props: a stone axe, a campfire, a wooden wall segment, a crate of machine scrap, a hide tent, a rusted machine patrol robot with one cold sensor eye, a survivor in patched layered clothes, a steel turret built from machine parts, a berry bush", tier: null },
  { id: "ref_ground", kind: "ref", subject: "ground swatches arranged as a grid: grass, forest floor, water, old asphalt, rubble, snow — each a square swatch seen from above", tier: null },
  { id: "actor_hero", kind: "actor", subject: "a lone survivor in patched layered clothing, scarf, backpack with bedroll, improvised tools on belt", tier: 2 },
  { id: "actor_raider", kind: "actor", subject: "a hostile clan raider with mismatched armor cut from machine plating, painted mask, crude spear", tier: 2 },
  { id: "actor_patrol_robot", kind: "actor", subject: "an original AI-era autonomous patrol machine still enforcing its pre-collapse protocol: weathered multi-legged chassis, moss in its joints, one cold teal sensor eye scanning, hostile", tier: 6 },
  { id: "node_tree", kind: "sprite", subject: "a temperate deciduous tree, harvestable for wood", tier: null },
  { id: "node_rock", kind: "sprite", subject: "a mineable boulder outcrop with visible ore streaks", tier: null },
  { id: "node_bush", kind: "sprite", subject: "a wild berry bush with herbs at its base", tier: null },
  { id: "node_scrap", kind: "sprite", subject: "the wreck of a fallen AI machine half-sunk in the ground — rusted armor plates, torn cables, dead sensor cluster — a salvage site for scrap and components", tier: null },
];

// The building's role phrased as a noun ("a structure structure" was the old template's output).
const ROLE = {
  structure: "a structural piece", production: "a production station", power: "a power installation",
  storage: "a storage container", comfort: "a piece of furniture", farming: "a farming installation",
  defense: "a defensive installation", art: "an art piece", utility: "a utility installation", ship: "a spaceship component",
};
// Mirrors godot/scripts/ui/world_input.gd paintable(): cell-filling, row-painted pieces.
const isFloorLike = (id) => id === "floor" || id.endsWith("_floor") || id === "grow_zone";
const isRowPiece = (id) => id === "wall" || id.endsWith("_wall") || id.endsWith("conduit") || id === "spike_trap";
const RAW_SOURCES = new Set(["chop", "mine", "gather", "farm", "hunt"]);

// The LIVE game (godot/scripts/data.gd) renders a few ids the catalog does not have (food, torch, axe…).
// Pure text parse of its RES / BUILDINGS / ITEMS dict literals: `"id": {"label"|"name": "…", … "research": "…"}`.
export function parseDataGd(text) {
  const block = (name) => {
    const m = String(text || "").match(new RegExp(`^const ${name} := \\{\\n([\\s\\S]*?)^\\}`, "m"));
    return m ? m[1] : "";
  };
  const rows = (body) => [...body.matchAll(/^\t"([a-z0-9_]+)": \{(.*)\},?\s*$/gm)].map(([, id, rest]) => ({
    id,
    label: ((rest.match(/"(?:label|name)": "([^"]+)"/) || [])[1]) || id,
    research: ((rest.match(/"research": "([a-z0-9_]+)"/) || [])[1]) || "",
    slot: ((rest.match(/"slot": "([a-z]+)"/) || [])[1]) || "",
  }));
  return { resources: rows(block("RES")), buildings: rows(block("BUILDINGS")), items: rows(block("ITEMS")) };
}

function derive(cat, live) {
  const researchTier = new Map((cat.research || []).map((r) => [r.id, r.tier]));
  const gateTier = (gate) => (gate ? researchTier.get(gate) || 1 : 0);
  const out = [];
  const resRow = (r, src) => {
    const raw = (r.sources || []).length > 0 && r.sources.every((x) => RAW_SOURCES.has(x));
    return { id: `res_${r.id}`, kind: "icon", src, label: r.label, tier: raw ? null : (r.tier || 0) * 2,
      subject: raw ? `raw ${humanize(r.id)} as freshly gathered — a small pile or bundle` : `${humanize(r.id)} — a neat stack of this processed material` };
  };
  const bldRow = (b, src) => {
    const floor = isFloorLike(b.id);
    const role = ROLE[b.category] || "a building";
    const shape = floor ? "seen as the surface it covers" : isRowPiece(b.id) ? "a single 1×1 grid-cell segment designed to repeat in a row" : "built by survivors";
    return { id: `bld_${b.id}`, kind: floor ? "tile" : "sprite", src, label: b.label, tier: gateTier(b.research),
      subject: `${humanize(b.id)} — ${role}, ${shape}` };
  };
  const itemRow = (i, src) => ({ id: `item_${i.id}`, kind: "icon", src, label: i.label, tier: gateTier(i.research),
    subject: `${humanize(i.id)} (${i.kind || i.slot}${i.slot && i.slot !== (i.kind || i.slot) ? `, worn/used as ${i.slot}` : ""})` });

  for (const r of cat.resources || []) out.push(resRow(r, `resources/${r.id}`));
  for (const i of cat.items || []) out.push(itemRow(i, `items/${i.id}`));
  for (const b of cat.buildings || []) out.push(bldRow(b, `buildings/${b.id}`));
  for (const r of cat.research || []) {
    out.push({ id: `rsch_${r.id}`, kind: "icon", src: `research/${r.id}`, label: r.label, tier: r.tier,
      subject: `emblem for the technology "${humanize(r.id)}": one symbolic object that embodies it` });
  }
  // live-only ids (data.gd) — catalogue rows win where both exist (one art id per game id)
  const have = new Set(out.map((a) => a.id));
  if (live) {
    for (const r of live.resources || []) if (!have.has(`res_${r.id}`)) out.push({ ...resRow({ ...r, sources: r.id === "food" ? ["gather"] : [] }, `live/resources/${r.id}`) });
    for (const b of live.buildings || []) if (!have.has(`bld_${b.id}`)) out.push(bldRow({ ...b, category: "utility" }, `live/buildings/${b.id}`));
    for (const i of live.items || []) if (!have.has(`item_${i.id}`)) out.push(itemRow({ ...i, kind: i.slot }, `live/items/${i.id}`));
  }
  TERRAIN.forEach(([id, ua, subject], idx) => out.push({ id: `tile_${id}`, kind: "tile", src: `terrain/${idx}`, label: ua, tier: null, subject }));
  for (const e of EXTRA) out.push({ ...e, src: `extra/${e.id}`, label: e.id });
  return out;
}

// ---------------------------------------------------------------- manifest
// CATALOG-owned fields are re-derived every sync. `subject` is human-owned ONCE edited: each row remembers
// the template text it was generated from (`auto`); while subject === auto the row follows template fixes,
// the moment a human edits subject it is frozen. Rows with `manual: true` (hand-added, e.g. ui_*) are never
// orphaned. A def removed from the catalog keeps its row (and approved art) flagged `orphan`.
const DERIVED = ["kind", "src", "label", "tier", "size"];

// existing: previous manifest (or null); live: parseDataGd(data.gd) (or null). Pure + idempotent.
export function buildManifest(cat, existing, live = null) {
  const prev = new Map(((existing && existing.assets) || []).map((a) => [a.id, a]));
  const seen = new Set();
  const assets = [];
  for (const d of derive(cat, live)) {
    seen.add(d.id);
    d.size = KINDS[d.kind].size;
    const p = prev.get(d.id);
    if (!p) { assets.push({ ...d, auto: d.subject, status: "todo" }); continue; }
    const merged = { ...p };
    for (const k of DERIVED) merged[k] = d[k];
    const followsTemplate = p.subject == null || p.auto == null || p.subject === p.auto;
    if (followsTemplate) merged.subject = d.subject;
    merged.auto = d.subject;
    if (merged.status == null) merged.status = "todo";
    delete merged.orphan;
    assets.push(merged);
  }
  for (const [id, p] of prev) {
    if (seen.has(id)) continue;
    assets.push(p.manual === true ? { ...p } : { ...p, orphan: true });
  }
  assets.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return { version: 1, note: "Generated by `node tools/gen-art.mjs sync` from godot/content/catalog.json + godot/scripts/data.gd. Edit subject/status/notes freely — an edited subject is never overwritten; add your own rows with \"manual\": true.", assets };
}

// ---------------------------------------------------------------- prompt
export function composePrompt(style, asset) {
  const kind = KINDS[asset.kind];
  if (!kind) throw new Error(`unknown kind "${asset.kind}" for ${asset.id}`);
  // The bible is instructions, never content: without this wrapper the model rendered its title line
  // ("ART BIBLE — RealWorld") as lettering on a reference sheet (observed on ref_world v1, 2026-11-04).
  const bible = String(style || "").trim().split(/\r?\n/).filter((l) => !/^ART BIBLE\b/.test(l.trim())).join("\n").trim();
  return [
    "STYLE GUIDE (instructions only — never draw any of these words, titles or labels in the image):",
    bible,
    "",
    `FRAME: ${kind.frame}`,
    asset.tier == null ? "" : `ERA: ${eraOf(asset.tier)}`,
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
export const DEFAULT_LIMIT = 12;
// opts: { only?, kind?, prefix?, force?, limit?, hasCandidates?(asset) }
// Default run touches only "todo"; "draft" needs --force or --only; "approved" needs --only AND --force.
// A "draft" whose candidates are gone (art/out/ is gitignored → fresh checkout) counts as "todo" again.
// An invalid/absent limit falls back to DEFAULT_LIMIT — never to "everything" (spend cap).
export function selectAssets(manifest, opts = {}) {
  const only = opts.only && opts.only.length ? new Set(opts.only) : null;
  const picked = [];
  for (const a of (manifest && manifest.assets) || []) {
    if (a.orphan) continue;
    if (only && !only.has(a.id)) continue;
    if (opts.kind && a.kind !== opts.kind) continue;
    if (opts.prefix && !a.id.startsWith(opts.prefix)) continue;
    if (a.status === "approved" && !(only && opts.force)) continue;
    const staleDraft = a.status === "draft" && opts.hasCandidates && !opts.hasCandidates(a);
    if (a.status === "draft" && !staleDraft && !(only || opts.force)) continue;
    picked.push(a);
  }
  const limit = Number.isInteger(opts.limit) && opts.limit > 0 ? opts.limit : DEFAULT_LIMIT;
  return { picked: picked.slice(0, limit), dropped: Math.max(0, picked.length - limit) };
}

// Order refs so kind-specific anchors come first, capped (Nano Banana is steadiest with ≤3 inputs).
export function pickRefs(files, kind, cap = 3) {
  const own = files.filter((f) => f.startsWith(`${kind}/`));
  const global = files.filter((f) => !f.includes("/"));
  return [...own, ...global].slice(0, cap);
}

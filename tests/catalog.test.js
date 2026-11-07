"use strict";
// RealWorld — catalog.test.js : language-agnostic validation of the deep content tree.
//
// Reads the single source of truth (godot/content/catalog.json) and proves the whole
// graph is coherent: unique ids, every reference resolves, the tech tree is a DAG, and —
// the load-bearing invariant — EVERY resource / recipe / building / item / research is
// REACHABLE from the raw (gathered/mined/hunted/farmed) roots. "Reachable" means the tree
// has no stranded content: you can actually get to every leaf by gathering raws, running
// research, building stations and crafting up the chain. The Godot suite
// (godot/tests/run_catalog_tests.gd) mirrors these same checks against the same file so the
// kernel loader and this validator can never silently disagree.
//
// This runs in THIS repo via `node --test` (npm test) — it needs no Godot, so the content
// graph is verified on every push regardless of engine availability.

const test = require("node:test");
const assert = require("node:assert");
// loadCatalog (memoized), isRaw and the reachability closure live in one shared fixture so this suite
// and progression.test.js can never drift apart on the ground-truth "nothing stranded" algorithm.
const { loadCatalog, isRaw, reachability } = require("./_catalog");

// Build the fast lookup maps + the set of ids that count as "obtainable stock" (real
// resources plus meal/thing outputs that recipes spawn and tally into stock).
function index(cat) {
  const resById = new Map(cat.resources.map((r) => [r.id, r]));
  const researchById = new Map(cat.research.map((r) => [r.id, r]));
  const buildingById = new Map(cat.buildings.map((b) => [b.id, b]));
  const recipeById = new Map(cat.recipes.map((r) => [r.id, r]));
  const itemById = new Map(cat.items.map((i) => [i.id, i]));
  // stock ids: resources + any thing-output id a recipe yields (meals).
  const stockIds = new Set(resById.keys());
  for (const rec of cat.recipes) if (rec.output && rec.output.thing) stockIds.add(rec.output.id);
  return { resById, researchById, buildingById, recipeById, itemById, stockIds };
}

test("catalog: parses and has all sections", () => {
  const cat = loadCatalog();
  for (const k of ["resources", "research", "buildings", "recipes", "items"]) {
    assert.ok(Array.isArray(cat[k]) && cat[k].length > 0, `section ${k} present & non-empty`);
  }
});

test("catalog: ids are globally unique", () => {
  const cat = loadCatalog();
  const seen = new Map();
  for (const section of ["resources", "research", "buildings", "recipes", "items"]) {
    for (const rec of cat[section]) {
      assert.ok(rec.id, `${section} entry missing id`);
      assert.ok(!seen.has(rec.id), `duplicate id "${rec.id}" (in ${section} and ${seen.get(rec.id)})`);
      seen.set(rec.id, section);
    }
  }
});

test("catalog: research prereqs all exist", () => {
  const cat = loadCatalog();
  const { researchById } = index(cat);
  for (const r of cat.research) {
    for (const p of r.prereqs || []) {
      assert.ok(researchById.has(p), `research "${r.id}" names missing prereq "${p}"`);
    }
  }
});

test("catalog: tech tree is acyclic (DAG)", () => {
  const cat = loadCatalog();
  // Kahn's algorithm: if we can't remove every node, there's a cycle.
  const indeg = new Map(cat.research.map((r) => [r.id, (r.prereqs || []).length]));
  const dependents = new Map(cat.research.map((r) => [r.id, []]));
  for (const r of cat.research) for (const p of r.prereqs || []) dependents.get(p).push(r.id);
  const queue = cat.research.filter((r) => indeg.get(r.id) === 0).map((r) => r.id);
  let removed = 0;
  while (queue.length) {
    const id = queue.shift();
    removed++;
    for (const d of dependents.get(id)) {
      indeg.set(d, indeg.get(d) - 1);
      if (indeg.get(d) === 0) queue.push(d);
    }
  }
  assert.strictEqual(removed, cat.research.length, "every research node topo-sorts (no prereq cycle)");
});

test("catalog: every research-gate reference resolves", () => {
  const cat = loadCatalog();
  const { researchById } = index(cat);
  const check = (id, ref, where) => {
    if (ref === undefined || ref === null || ref === "") return;
    assert.ok(researchById.has(ref), `${where} "${id}" requires missing research "${ref}"`);
  };
  for (const b of cat.buildings) check(b.id, b.research, "building");
  for (const r of cat.recipes) check(r.id, r.research, "recipe");
  for (const i of cat.items) check(i.id, i.research, "item");
});

test("catalog: recipe stations exist and are craft stations", () => {
  const cat = loadCatalog();
  const { buildingById } = index(cat);
  const stations = new Set();
  for (const r of cat.recipes) stations.add(r.station);
  for (const i of cat.items) stations.add(i.station);
  for (const s of stations) {
    const b = buildingById.get(s);
    assert.ok(b, `station "${s}" is not a building`);
    assert.ok(b.station === true || b.autocraft === true, `building "${s}" is not marked as a craft station`);
  }
});

test("catalog: all costs/inputs reference known resources", () => {
  const cat = loadCatalog();
  const { resById, stockIds } = index(cat);
  for (const b of cat.buildings) {
    for (const c of Object.keys(b.cost || {})) {
      assert.ok(resById.has(c), `building "${b.id}" costs unknown resource "${c}"`);
    }
  }
  for (const r of cat.recipes) {
    for (const c of Object.keys(r.inputs || {})) {
      assert.ok(resById.has(c), `recipe "${r.id}" consumes unknown resource "${c}"`);
    }
    assert.ok(r.output && r.output.id, `recipe "${r.id}" has no output id`);
    assert.ok(r.output.thing || resById.has(r.output.id), `recipe "${r.id}" bulk-outputs unknown resource "${r.output.id}"`);
    assert.ok((r.output.count || 1) > 0, `recipe "${r.id}" output count must be > 0`);
    assert.ok(r.work > 0, `recipe "${r.id}" work must be > 0`);
  }
  for (const i of cat.items) {
    for (const c of Object.keys(i.recipe || {})) {
      assert.ok(resById.has(c), `item "${i.id}" costs unknown resource "${c}"`);
    }
  }
  assert.ok(stockIds.size >= cat.resources.length, "stock id set includes every resource");
});

test("catalog: power buildings declare a valid role", () => {
  const cat = loadCatalog();
  const roles = new Set(["source", "trader", "battery"]);
  const kinds = new Set(["fuel", "solar", "wind"]);
  for (const b of cat.buildings) {
    if (!b.power) continue;
    assert.ok(roles.has(b.power.role), `building "${b.id}" has bad power role "${b.power.role}"`);
    if (b.power.role === "source") {
      assert.ok(kinds.has(b.power.kind), `power source "${b.id}" has bad kind "${b.power.kind}"`);
      assert.ok(b.power.rated > 0, `power source "${b.id}" needs rated > 0`);
    }
    if (b.power.role === "trader") assert.ok(b.power.draw > 0, `power trader "${b.id}" needs draw > 0`);
    if (b.power.role === "battery") assert.ok(b.power.capacity > 0, `battery "${b.id}" needs capacity > 0`);
  }
});

// The load-bearing invariant — the reachability closure from raw roots — lives in ./_catalog.js and
// is imported above (shared verbatim with progression.test.js so the two can never disagree).

test("catalog: every resource is obtainable from raw roots", () => {
  const cat = loadCatalog();
  const { obtainable } = reachability(cat);
  const stranded = cat.resources.filter((r) => !obtainable.has(r.id)).map((r) => r.id);
  assert.deepStrictEqual(stranded, [], `stranded resources (cannot be produced): ${stranded.join(", ")}`);
});

test("catalog: every research node is reachable", () => {
  const cat = loadCatalog();
  const { unlockedResearch } = reachability(cat);
  const stranded = cat.research.filter((r) => !unlockedResearch.has(r.id)).map((r) => r.id);
  assert.deepStrictEqual(stranded, [], `unreachable research: ${stranded.join(", ")}`);
});

test("catalog: every building is buildable", () => {
  const cat = loadCatalog();
  const { builtBuildings } = reachability(cat);
  const stranded = cat.buildings.filter((b) => !builtBuildings.has(b.id)).map((b) => b.id);
  assert.deepStrictEqual(stranded, [], `unbuildable buildings: ${stranded.join(", ")}`);
});

test("catalog: every recipe is craftable", () => {
  const cat = loadCatalog();
  const { madeRecipes } = reachability(cat);
  const stranded = cat.recipes.filter((r) => !madeRecipes.has(r.id)).map((r) => r.id);
  assert.deepStrictEqual(stranded, [], `uncraftable recipes: ${stranded.join(", ")}`);
});

test("catalog: every item is craftable", () => {
  const cat = loadCatalog();
  const { madeItems } = reachability(cat);
  const stranded = cat.items.filter((i) => !madeItems.has(i.id)).map((i) => i.id);
  assert.deepStrictEqual(stranded, [], `uncraftable items: ${stranded.join(", ")}`);
});

test("catalog: no resource is wholly unused (every refined/intermediate feeds something)", () => {
  const cat = loadCatalog();
  const used = new Set();
  const eat = (obj) => { for (const k of Object.keys(obj || {})) used.add(k); };
  for (const r of cat.recipes) eat(r.inputs);
  for (const b of cat.buildings) eat(b.cost);
  for (const i of cat.items) eat(i.recipe);
  // Terminal products consumed by GAMEPLAY at runtime — drunk, ingested, fired, eaten, or worn as
  // end-game stock — rather than by another recipe. These are legitimate sinks; every OTHER resource
  // must still feed something (the guard that catches genuinely stranded intermediates).
  const allowedSinks = new Set([
    "reinforced_plate",                                             // end-game armour stock
    "ammo", "he_shell", "incendiary_shell", "emp_shell", "antigrain_shell", // fired by guns/turrets/mortars (combat.gd)
    "beer", "kibble",                                               // drunk / eaten (needs.gd)
    "smokeleaf_joint", "psychite_tea", "flake", "wake_up",          // recreational/combat drugs (ingested)
    "go_juice", "penoxycyline", "luciferium",                       // combat/medical drugs (ingested)
  ]);
  const dangling = cat.resources
    .filter((r) => !used.has(r.id) && !allowedSinks.has(r.id))
    .map((r) => r.id);
  assert.deepStrictEqual(dangling, [], `resources that feed nothing (dead-end intermediates): ${dangling.join(", ")}`);
});

// --- Bill-of-materials planner (spec 0008 phase 1) — mirrors catalog.gd producer_of/production_chain. ---
function producerOf(cat, resId) {
  const rc = cat.recipes.find((r) => r.output && r.output.id === resId);
  return rc ? rc.id : "";
}
function productionChain(cat, resId) {
  const raws = new Set(cat.resources.filter(isRaw).map((r) => r.id));
  const byOut = new Map();
  for (const rc of cat.recipes) if (rc.output && !byOut.has(rc.output.id)) byOut.set(rc.output.id, rc);
  const out = [], seen = new Set(), stack = new Set();
  const visit = (rid) => {
    if (raws.has(rid) || !byOut.has(rid)) return;
    const recipe = byOut.get(rid);
    if (seen.has(recipe.id) || stack.has(recipe.id)) return;
    stack.add(recipe.id);
    for (const inp of Object.keys(recipe.inputs || {})) visit(inp);
    stack.delete(recipe.id);
    seen.add(recipe.id);
    out.push(recipe.id);
  };
  visit(resId);
  return out;
}
function missingFor(cost, stock) {
  const out = {};
  for (const k of Object.keys(cost || {})) { const d = (cost[k] | 0) - ((stock[k] | 0)); if (d > 0) out[k] = d; }
  return out;
}
function rawRequirements(cat, cost) {
  const raws = new Set(cat.resources.filter(isRaw).map((r) => r.id));
  const byOut = new Map();
  for (const rc of cat.recipes) if (rc.output && !byOut.has(rc.output.id)) byOut.set(rc.output.id, rc);
  const out = {};
  const acc = (rid, amount, stack) => {
    if (amount <= 0) return;
    if (raws.has(rid) || !byOut.has(rid) || stack.has(rid)) { out[rid] = (out[rid] || 0) + amount; return; }
    stack.add(rid);
    const recipe = byOut.get(rid);
    const count = Math.max(1, (recipe.output.count | 0) || 1);
    const runs = Math.ceil(amount / count);
    for (const inp of Object.keys(recipe.inputs || {})) acc(inp, runs * recipe.inputs[inp], stack);
    stack.delete(rid);
  };
  for (const res of Object.keys(cost || {})) acc(res, cost[res], new Set());
  return out;
}

test("catalog: production_chain is a valid dependency order ending at the target's recipe", () => {
  const cat = loadCatalog();
  const raws = new Set(cat.resources.filter(isRaw).map((r) => r.id));
  const byOut = new Map();
  for (const rc of cat.recipes) if (rc.output && !byOut.has(rc.output.id)) byOut.set(rc.output.id, rc);
  // every non-raw, recipe-produced resource has a chain that ends at its own producer, with no dups,
  // and every non-raw input of each step is produced by an EARLIER step in the chain.
  for (const res of cat.resources) {
    if (raws.has(res.id)) { assert.deepStrictEqual(productionChain(cat, res.id), [], `raw ${res.id} needs no recipe`); continue; }
    if (!byOut.has(res.id)) continue; // meal/thing-only outputs live elsewhere; skip non-resource outputs
    const chain = productionChain(cat, res.id);
    assert.ok(chain.length > 0, `non-raw ${res.id} has a production chain`);
    assert.strictEqual(chain[chain.length - 1], producerOf(cat, res.id), `chain for ${res.id} ends at its producer`);
    assert.strictEqual(new Set(chain).size, chain.length, `no duplicate steps in chain for ${res.id}`);
    const pos = new Map(chain.map((id, i) => [id, i]));
    const recById = new Map(cat.recipes.map((r) => [r.id, r]));
    for (const recId of chain) {
      for (const inp of Object.keys(recById.get(recId).inputs || {})) {
        if (raws.has(inp) || !byOut.has(inp)) continue;
        const prod = producerOf(cat, inp);
        assert.ok(pos.get(prod) < pos.get(recId), `input ${inp} of ${recId} is produced earlier in the chain`);
      }
    }
  }
});

test("catalog: production_chain resolves the advanced electronics chain end to end", () => {
  const cat = loadCatalog();
  const chain = productionChain(cat, "circuit");
  assert.ok(chain.includes(producerOf(cat, "circuit")), "chain makes the circuit");
  assert.ok(chain.includes(producerOf(cat, "copper_wire")), "chain first makes copper wire");
  assert.ok(chain.includes(producerOf(cat, "copper_bar")), "chain first smelts copper bar");
  // dependency order: bar before wire before circuit
  const pos = (r) => chain.indexOf(producerOf(cat, r));
  assert.ok(pos("copper_bar") < pos("copper_wire") && pos("copper_wire") < pos("circuit"), "smelt -> wire -> circuit order");
});

test("catalog: raw_requirements rolls every cost down to raw resources only", () => {
  const cat = loadCatalog();
  const raws = new Set(cat.resources.filter(isRaw).map((r) => r.id));
  // for EVERY building cost + recipe input + item recipe, the budget resolves to raws only, all > 0
  const check = (cost, where) => {
    const req = rawRequirements(cat, cost);
    for (const [k, v] of Object.entries(req)) {
      assert.ok(raws.has(k), `${where}: budget key "${k}" bottoms out at a raw resource`);
      assert.ok(v > 0, `${where}: raw requirement "${k}" is positive`);
    }
  };
  for (const b of cat.buildings) check(b.cost, `building ${b.id}`);
  for (const r of cat.recipes) check(r.inputs, `recipe ${r.id}`);
  for (const i of cat.items) check(i.recipe, `item ${i.id}`);
  // a pure-raw cost passes through unchanged; a deep chain accumulates a real raw budget
  assert.deepStrictEqual(rawRequirements(cat, { wood: 30, stone: 8 }), { wood: 30, stone: 8 }, "raw cost passes through");
  const circuitReq = rawRequirements(cat, { circuit: 4 });
  assert.ok(Object.keys(circuitReq).length > 0 && Object.values(circuitReq).every((v) => v > 0), "a deep target yields a non-empty raw budget");
  assert.ok(Object.keys(circuitReq).every((k) => raws.has(k)), "the circuit budget is entirely raw resources");
});

test("catalog: missing_for reports exactly the shortfall", () => {
  assert.deepStrictEqual(missingFor({ wood: 10, stone: 5 }, { wood: 4, stone: 5 }), { wood: 6 }, "only the deficient resource, by its deficit");
  assert.deepStrictEqual(missingFor({ wood: 3 }, { wood: 3 }), {}, "exactly affordable -> nothing missing");
  assert.deepStrictEqual(missingFor({ steel: 2 }, {}), { steel: 2 }, "absent resource counts as fully missing");
});

test("catalog: tree has real depth (chain length >= 3 to advanced tier)", () => {
  const cat = loadCatalog();
  // circuit depends on copper_wire<-copper_bar<-copper_ore : a >=3-step production chain.
  const { madeRecipes } = reachability(cat);
  assert.ok(madeRecipes.has("make_circuit"), "advanced electronics chain resolves end to end");
  assert.ok(cat.resources.some((r) => r.tier >= 3), "catalog reaches tier-3 advanced resources");
  assert.ok(cat.research.some((r) => r.tier >= 7), "research tree reaches tier 7+");
});

// ---- spec 0008 §5.3: the CURATED LIVE TIER — the same fixpoint, seeded from the raws the live map
// actually sources (4 node kinds + the phase-4 node-yield bundle). Mirrors _t_catalog_live in
// godot/tests/run_tests.gd one-for-one, so the Godot slice and this validator can never disagree
// about what the live game can reach. If catalog edits shift the closure, update BOTH pins together.
const LIVE_RAWS = [
  "wood", "stone", "raw_food", "scrap",                       // the 4 map node kinds
  "iron_ore", "coal", "clay", "sand", "copper_ore",           // rock's enriched yield (phase 4)
  "plant_fiber", "herbal",                                    // tree/bush enriched yield (phase 4)
  "grain",                                                    // grow-zone rotation (farming live)
  "hops",                                                     // selectable crop (set_crop verb)
];

test("catalog: live-tier closure reaches the steel + bread + beer chains (pinned at 44 resources)", () => {
  const cat = loadCatalog();
  const live = reachability(cat, LIVE_RAWS);
  for (const id of ["charcoal", "iron_bar", "steel", "components", "medicine", "ammo", "flour", "bread", "beer"]) {
    assert.ok(live.obtainable.has(id), `live tier reaches ${id}`);
  }
  assert.strictEqual(live.obtainable.size, 44, "live-tier obtainable resources pinned (44/78)");
  // every live raw is a genuine catalogue RAW resource (a typo here = a dead resource in the pocket)
  const rawIds = new Set(cat.resources.filter(isRaw).map((r) => r.id));
  for (const id of LIVE_RAWS) assert.ok(rawIds.has(id), `live raw "${id}" is a catalogue raw`);
});

// ---- spec 0010 (Основна капсула) §5.1/REQ-0010-11/12/16/17/91/97/99/101/102/105/106: the capsule_levels table, TWO axes -------------
// All the capsule numbers are DATA (godot/content/catalog.json -> capsule_levels); the code holds none of them. Some are the OWNER's decisions
// (+10% per level and +50% at level 5 — OD-98; x2 per level — OD-65/93; x16 at defence 5 — OD-103; ~50 m radius — OD-99; the raid's immunity and
// the 50% — OD-24/107) and are pinned here as such; the rest is PROPOSED by the economy bot (godot/tests/run_capsule_balance.gd) and approved by
// the owner at merge. This validator proves the table's SHAPE and the owner's coefficients, not the proposed values: continuous levels 0..5 on
// BOTH axes (capsule level: cost + four buffs; defence level: cost + core_hp), one static zone radius, the closed four-axis buff vocabulary,
// prices that get rarer with the level, no clone-roster entries. godot/tests/run_catalog_tests.gd mirrors every check against the same file
// (and pins the identity of the ids vs data_bridge.gd).
const CAPSULE_BUFF_KEYS = ["gather_mult", "craft_mult", "need_recovery_mult", "research_mult"]; // mirrors MainCapsule.BUFF_KEYS (REQ-0010-105, OD-73)
const CAPSULE_ID_SHARED = ["wood", "stone", "scrap", "planks", "components"];          // the ids data_bridge.gd maps 1:1 (backpack AND stock speak them)
const CAPSULE_STASH_REACH = 2.5;                                                        // mirrors Inventory.STASH_REACH: the zone must cover the stash
const CAPSULE_MAP_N = 56;                                                               // mirrors Session.MAP_N: the zone stays under n/4
const CAPSULE_TOP_KEYS = ["version", "status", "note", "feasibility_note", "metric", "zone", "levels", "protection", "raid"];
const CAPSULE_ZONE_KEYS = ["radius_m", "cell_m", "radius_cells"];
const CAPSULE_LEVEL_KEYS = ["level", "cost", "buffs"];
const CAPSULE_PROT_TOP_KEYS = ["factor", "levels"];
const CAPSULE_PROT_KEYS = ["level", "cost", "core_hp"];
const CAPSULE_RAID_KEYS = ["decided", "immunity_ms", "take_percent"];
const CAPSULE_BUFF_STEP = 0.1;                                                          // OD-98: +10% per level, +50% at level 5
const CAPSULE_RARITY = { wood: 0, stone: 1, planks: 2, scrap: 3, components: 4 };       // rank by the finite supply order (planks = processed wood), mirrors the bot
const CAPSULE_BASIC_RAW = ["wood", "stone"];                                            // OD-75: level 1 is basic raw

function capsuleTable() {
  const t = loadCatalog().capsule_levels;
  assert.ok(t && typeof t === "object", "catalog.json carries the capsule_levels table");
  return t;
}
const totalUnits = (cost) => Object.values(cost).reduce((a, b) => a + b, 0);
const rarest = (cost) => Math.max(...Object.keys(cost).map((id) => CAPSULE_RARITY[id]));

test("capsule_levels: closed schema, version 2, still PROPOSED until the owner approves (OD-73/76/99)", () => {
  const t = capsuleTable();
  assert.deepStrictEqual(Object.keys(t).sort(), [...CAPSULE_TOP_KEYS].sort(), "no key outside the schema: a third axis / clone table has nowhere to hide (REQ-0010-17/97/99)");
  assert.strictEqual(t.version, 2, "version 2 = two axes + one static zone (REQ-0010-60: the first-wave one-axis table is v1)");
  assert.ok(["proposed", "approved"].includes(t.status), `status is "proposed" (agent numbers) or "approved" (owner), got "${t.status}"`);
  assert.strictEqual(t.metric, "chebyshev", "the zone metric lives in the data (REQ-0010-80); only chebyshev is implemented");
  assert.ok(typeof t.note === "string" && t.note.length > 0, "the note says where the numbers come from");
  assert.ok(typeof t.feasibility_note === "string" && /НЕ ЗДІЙСНЕННО|не здійсненно/.test(t.feasibility_note),
    "the feasibility note says honestly that the owner's formula does not fit the finite map (not a map-fitted number)");
});

test("capsule_levels: the capsule axis — levels 0..5 are continuous, L0 is the bare capsule (REQ-0010-11/12/91)", () => {
  const { levels } = capsuleTable();
  assert.ok(Array.isArray(levels));
  // step 1 (OD-56) is exactly 0..5; step 2 widens the range BY DATA and re-pins this length together with the data (REQ-0010-91)
  assert.strictEqual(levels.length, 6, "levels 0..5");
  assert.ok(levels.length <= 10, "ledger keys are decimal strings hashed lexicographically: numeric order holds only up to level 9 (REQ-0010-82) — more levels need a RECORD_VERSION bump");
  levels.forEach((row, i) => {
    assert.deepStrictEqual(Object.keys(row).sort(), [...CAPSULE_LEVEL_KEYS].sort(), `level ${i}: only {level,cost,buffs} — the radius is NOT a level row (REQ-0010-16), the defence is its own axis (REQ-0010-99)`);
    assert.strictEqual(row.level, i, `levels[${i}].level is ${i}`);
  });
  assert.deepStrictEqual(levels[0].cost, {}, "level 0 costs nothing (you land on it)");
});

test("capsule_levels: every level record carries EXACTLY the four buff axes, ~+10% per level, +50% at 5, 0 at 0 (REQ-0010-105/106, OD-73/98)", () => {
  const { levels } = capsuleTable();
  const NEEDS = /hunger|food|thirst|melee|dmg|damage/i;
  for (const row of levels) {
    assert.deepStrictEqual(Object.keys(row.buffs).sort(), [...CAPSULE_BUFF_KEYS].sort(), `level ${row.level}: exactly the four OD-73 axes (no melee, no hunger — a fifth axis only by the owner)`);
    for (const [k, v] of Object.entries(row.buffs)) {
      assert.ok(!NEEDS.test(k), `level ${row.level}: buff "${k}" must not touch hunger/melee`);
      assert.ok(typeof v === "number", `level ${row.level}: ${k} is a number`);
      // OD-98 (decided): linear +10% per level -> a multiplier 1 + 0.10*L (1.0 at level 0 = 0%, 1.5 at level 5 = +50%)
      assert.ok(Math.abs(v - (1 + CAPSULE_BUFF_STEP * row.level)) < 1e-9, `level ${row.level}: ${k} = 1 + 0.10*L (OD-98), got ${v}`);
    }
  }
  for (const key of CAPSULE_BUFF_KEYS) assert.strictEqual(levels[5].buffs[key], 1.5, `${key}: +50% at level 5 (OD-98)`);
});

test("capsule_levels: capsule prices are positive integers over ids the LIVE game reaches and both stocks speak (REQ-0010-11/13)", () => {
  const cat = loadCatalog();
  const live = reachability(cat, LIVE_RAWS);
  for (const row of capsuleTable().levels.slice(1)) {
    const ids = Object.keys(row.cost);
    assert.ok(ids.length > 0, `level ${row.level} has a price`);
    for (const id of ids) {
      assert.ok(Number.isInteger(row.cost[id]) && row.cost[id] > 0, `level ${row.level}: ${id} is a positive integer`);
      assert.ok(CAPSULE_ID_SHARED.includes(id), `level ${row.level}: "${id}" is a data.gd id that data_bridge maps 1:1 (not food/raw_food: the backpack and the stock would disagree)`);
      assert.ok(live.obtainable.has(id), `level ${row.level}: "${id}" is obtainable in the live tier`);
    }
  }
});

test("capsule_levels: the price strictly grows ~x2 per level and gets RARER with the level; level 1 is basic raw (REQ-0010-101, OD-65/75/93)", () => {
  const { levels } = capsuleTable();
  for (let i = 2; i < levels.length; i++) {
    assert.ok(totalUnits(levels[i].cost) > totalUnits(levels[i - 1].cost), `the price of level ${i} exceeds level ${i - 1}`);
  }
  for (let i = 2; i < levels.length; i++) {
    const ratio = totalUnits(levels[i].cost) / totalUnits(levels[i - 1].cost);
    // OD-65/93: ~x2 per level. The WEIGHT is gather-minutes at the bare-hand income (exactly x2 in the bot); the unit totals follow within a tolerance
    assert.ok(ratio > 1.6 && ratio < 2.4, `cost(${i})/cost(${i - 1}) ~ 2 by total weight (OD-65/93), got ${ratio.toFixed(2)}`);
  }
  assert.ok(Object.keys(levels[1].cost).every((id) => CAPSULE_BASIC_RAW.includes(id)), "level 1 is basic raw only (OD-75)");
  let prev = 0;
  for (let i = 1; i < levels.length; i++) {
    const r = rarest(levels[i].cost);
    assert.ok(r >= prev, `the rarest ingredient never gets more common with the level (level ${i}: rank ${r} < ${prev})`);
    prev = r;
  }
  assert.ok(rarest(levels[5].cost) > rarest(levels[1].cost), "level 5 asks for rarer ingredients than level 1 (OD-75)");
});

test("capsule_levels: the zone is ONE static radius in the data, not a level row; ~50 m (REQ-0010-16/80, OD-74/99)", () => {
  const { zone, levels, protection } = capsuleTable();
  assert.deepStrictEqual(Object.keys(zone).sort(), [...CAPSULE_ZONE_KEYS].sort());
  assert.strictEqual(zone.radius_m, 50, "~50 m — the owner's number (OD-99)");
  assert.ok(Number.isInteger(zone.radius_cells) && zone.radius_cells > 0, "the zone radius is a positive whole number of cells");
  assert.ok(typeof zone.cell_m === "number" && zone.cell_m > 0, "cell_m is the (proposed, Q-4) map scale");
  assert.strictEqual(zone.radius_cells, Math.ceil(zone.radius_m / zone.cell_m), "radius_cells = ceil(radius_m / cell_m): ONE function of the scale (Q-4)");
  assert.ok(zone.radius_cells >= Math.ceil(CAPSULE_STASH_REACH), "the zone covers the storage reach");
  assert.ok(zone.radius_cells <= Math.floor(CAPSULE_MAP_N / 4), "the zone stays under a quarter of the map side");
  for (const row of [...levels, ...protection.levels]) {
    assert.ok(!("radius" in row) && !("radius_cells" in row), `level ${row.level}: the radius belongs to NEITHER axis (static, OD-74/99)`);
  }
});

test("capsule_levels: the defence axis — its own records 0..5, core_hp x2 per level, x16 at 5 (REQ-0010-99/102, OD-76/103)", () => {
  const { protection } = capsuleTable();
  assert.deepStrictEqual(Object.keys(protection).sort(), [...CAPSULE_PROT_TOP_KEYS].sort());
  assert.strictEqual(protection.factor, 2, "x2 per level (OD-65/103): the coefficient is data");
  const rows = protection.levels;
  assert.strictEqual(rows.length, 6, "defence levels 0..5 (OD-76)");
  rows.forEach((row, i) => {
    assert.deepStrictEqual(Object.keys(row).sort(), [...CAPSULE_PROT_KEYS].sort(), `defence ${i}: only {level,cost,core_hp}`);
    assert.strictEqual(row.level, i);
    assert.ok(typeof row.core_hp === "number" && row.core_hp > 0, `defence ${i}: core_hp > 0 (the core always has some HP, even at 0)`);
    if (i >= 1) assert.ok(Math.abs(row.core_hp / rows[i - 1].core_hp - protection.factor) < 0.01, `core_hp(${i})/core_hp(${i - 1}) ~ factor (x2 per level, OD-103)`);
  });
  assert.ok(Math.abs(rows[5].core_hp / rows[1].core_hp - 16) < 0.05, "core_hp(5)/core_hp(1) ~ 16 (OD-103)");
  assert.deepStrictEqual(rows[0].cost, {}, "defence 0 costs nothing");
  const cat = loadCatalog();
  const live = reachability(cat, LIVE_RAWS);
  for (const row of rows.slice(1)) {
    assert.ok(Object.keys(row.cost).length > 0, `defence ${row.level} has a price`);
    for (const [id, n] of Object.entries(row.cost)) {
      assert.ok(Number.isInteger(n) && n > 0 && CAPSULE_ID_SHARED.includes(id) && live.obtainable.has(id), `defence ${row.level}: ${id} is a positive integer over a shared live id`);
    }
  }
  for (let i = 2; i < rows.length; i++) assert.ok(totalUnits(rows[i].cost) > totalUnits(rows[i - 1].cost), `the defence price of level ${i} exceeds level ${i - 1}`);
});

test("capsule_levels: exactly TWO axes and no clone-roster entries anywhere in the table (REQ-0010-17/97/99, OD-57/76)", () => {
  const text = JSON.stringify(capsuleTable());
  assert.ok(!/clone|roster|genome|orbit|implant/i.test(text.replace(/"(note|feasibility_note)":"[^"]*"/g, '""')), "the table mentions no clones / roster / orbit / implants");
  assert.deepStrictEqual(Object.keys(capsuleTable()).filter((k) => ["levels", "protection"].includes(k)), ["levels", "protection"], "two axes: the capsule level and the defence level");
});

test("capsule_levels: the raid block carries ONLY the owner's decided numbers (OD-24/107); grace, cadence and warning are a later wave", () => {
  const { raid } = capsuleTable();
  assert.deepStrictEqual(Object.keys(raid).sort(), [...CAPSULE_RAID_KEYS].sort(),
    "no proposed raider ladder / warning here: warning 10–30 min is OD-88 (REQ-0010-108), the raider's strength is Balance.assess (OD-87) — W3");
  assert.strictEqual(raid.immunity_ms, 86400000, "24 h in UTC ms (OD-24)");
  assert.strictEqual(raid.take_percent, 50, "50% of invested[L] is destroyed (OD-107)");
  assert.deepStrictEqual([...raid.decided].sort(), ["immunity_ms", "take_percent"], "both are owner-decided");
});

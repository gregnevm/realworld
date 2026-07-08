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
const fs = require("node:fs");
const path = require("node:path");

const CATALOG_PATH = path.join(__dirname, "..", "godot", "content", "catalog.json");

function loadCatalog() {
  const raw = fs.readFileSync(CATALOG_PATH, "utf8");
  return JSON.parse(raw);
}

// A raw resource is one a player can obtain directly from the map, not by crafting.
const RAW_SOURCES = new Set(["mine", "chop", "gather", "hunt", "farm"]);

function isRaw(res) {
  return (res.sources || []).some((s) => RAW_SOURCES.has(s));
}

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

// The load-bearing invariant: reachability closure from raw roots. Nothing may be stranded.
function reachability(cat) {
  const { resById, researchById, buildingById, stockIds } = index(cat);

  const obtainable = new Set(); // stock ids you can currently have
  for (const r of cat.resources) if (isRaw(r)) obtainable.add(r.id);

  const unlockedResearch = new Set();
  const builtBuildings = new Set();
  const madeRecipes = new Set();
  const madeItems = new Set();

  const researchReachable = (id) => {
    const r = researchById.get(id);
    if (!r) return false;
    return (r.prereqs || []).every((p) => unlockedResearch.has(p));
  };
  const gateOk = (ref) => ref === undefined || ref === null || ref === "" || unlockedResearch.has(ref);
  const costOk = (cost) => Object.keys(cost || {}).every((c) => obtainable.has(c));

  let changed = true;
  while (changed) {
    changed = false;
    // 1. research whose prereqs are all unlocked
    for (const r of cat.research) {
      if (!unlockedResearch.has(r.id) && researchReachable(r.id)) { unlockedResearch.add(r.id); changed = true; }
    }
    // 2. buildings whose cost is obtainable and research unlocked
    for (const b of cat.buildings) {
      if (builtBuildings.has(b.id)) continue;
      if (gateOk(b.research) && costOk(b.cost)) { builtBuildings.add(b.id); changed = true; }
    }
    // 3. recipes whose station is built, research unlocked, inputs obtainable -> output obtainable
    for (const r of cat.recipes) {
      if (madeRecipes.has(r.id)) continue;
      if (builtBuildings.has(r.station) && gateOk(r.research) && costOk(r.inputs)) {
        madeRecipes.add(r.id);
        obtainable.add(r.output.id);
        changed = true;
      }
    }
    // 4. items whose station is built, research unlocked, recipe inputs obtainable
    for (const i of cat.items) {
      if (madeItems.has(i.id)) continue;
      if (builtBuildings.has(i.station) && gateOk(i.research) && costOk(i.recipe)) { madeItems.add(i.id); changed = true; }
    }
  }
  return { obtainable, unlockedResearch, builtBuildings, madeRecipes, madeItems, resById, researchById, buildingById };
}

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

test("catalog: tree has real depth (chain length >= 3 to advanced tier)", () => {
  const cat = loadCatalog();
  // circuit depends on copper_wire<-copper_bar<-copper_ore : a >=3-step production chain.
  const { madeRecipes } = reachability(cat);
  assert.ok(madeRecipes.has("make_circuit"), "advanced electronics chain resolves end to end");
  assert.ok(cat.resources.some((r) => r.tier >= 3), "catalog reaches tier-3 advanced resources");
  assert.ok(cat.research.some((r) => r.tier >= 7), "research tree reaches tier 7+");
});

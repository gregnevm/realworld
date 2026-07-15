"use strict";
// RealWorld — tests/_catalog.js : shared fixtures for the content-tree suites.
//
// One memoized loader + the RAW-source predicate + the fixpoint reachability closure, imported by
// catalog.test.js and progression.test.js. Previously each suite copy-pasted its own copy of the
// "nothing stranded" ground-truth algorithm (two copies that could silently drift) and re-parsed the
// ~4300-line catalog.json dozens of times per run. Keeping them here means one source of truth and
// one parse.

const fs = require("node:fs");
const path = require("node:path");

const CATALOG_PATH = path.join(__dirname, "..", "godot", "content", "catalog.json");

let _cache = null;
// The catalog is immutable for the duration of a test run, so parse the big JSON exactly once.
function loadCatalog() {
  if (_cache === null) _cache = JSON.parse(fs.readFileSync(CATALOG_PATH, "utf8"));
  return _cache;
}

// A raw resource is one a player obtains straight from the map, not by crafting.
const RAW_SOURCES = new Set(["mine", "chop", "gather", "hunt", "farm"]);
function isRaw(res) {
  return (res.sources || []).some((s) => RAW_SOURCES.has(s));
}

// The load-bearing invariant: the fixpoint reachability closure from the raw roots. Returns the sets
// of obtainable stock ids, unlocked research, built buildings, made recipes and made items — the
// ground truth that "nothing in the tree is stranded" and that a fully-researched pipeline opens
// everything. Mirrors catalog.gd's reachability() (and progression.gd's end-state).
function reachability(cat) {
  const obtainable = new Set();
  for (const r of cat.resources) if (isRaw(r)) obtainable.add(r.id);
  const unlockedResearch = new Set();
  const builtBuildings = new Set();
  const madeRecipes = new Set();
  const madeItems = new Set();

  const gateOk = (ref) => ref === undefined || ref === null || ref === "" || unlockedResearch.has(ref);
  const costOk = (cost) => Object.keys(cost || {}).every((c) => obtainable.has(c));

  let changed = true;
  while (changed) {
    changed = false;
    // 1. research whose prereqs are all unlocked
    for (const r of cat.research) {
      if (!unlockedResearch.has(r.id) && (r.prereqs || []).every((p) => unlockedResearch.has(p))) {
        unlockedResearch.add(r.id); changed = true;
      }
    }
    // 2. buildings whose cost is obtainable and research unlocked
    for (const b of cat.buildings) {
      if (!builtBuildings.has(b.id) && gateOk(b.research) && costOk(b.cost)) { builtBuildings.add(b.id); changed = true; }
    }
    // 3. recipes whose station is built, research unlocked, inputs obtainable -> output obtainable
    for (const r of cat.recipes) {
      if (!madeRecipes.has(r.id) && builtBuildings.has(r.station) && gateOk(r.research) && costOk(r.inputs)) {
        madeRecipes.add(r.id); obtainable.add(r.output.id); changed = true;
      }
    }
    // 4. items whose station is built, research unlocked, recipe inputs obtainable
    for (const i of cat.items) {
      if (!madeItems.has(i.id) && builtBuildings.has(i.station) && gateOk(i.research) && costOk(i.recipe)) {
        madeItems.add(i.id); changed = true;
      }
    }
  }
  return { obtainable, unlockedResearch, builtBuildings, madeRecipes, madeItems };
}

module.exports = { CATALOG_PATH, loadCatalog, RAW_SOURCES, isRaw, reachability };

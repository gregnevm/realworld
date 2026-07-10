"use strict";
// RealWorld — progression.test.js : language-agnostic validation of the research→unlock PIPELINE.
//
// Mirrors godot/scripts/kernel/progression.gd one-for-one (the same way catalog.test.js mirrors
// catalog.gd) so the Godot kernel and this validator can never silently disagree about how the tech
// pipeline walks the SAME godot/content/catalog.json. Runs under `node --test` (npm test) — no Godot
// needed, so the pipeline's core semantics are verified on every push regardless of engine availability.
//
// What it proves:
//   • the pipeline can research the ENTIRE tree from a cold start, always in prereq-respecting order;
//   • leftover points roll from a finished project straight into the next (a real pipeline, not stop-start);
//   • enqueue only ever accepts a valid topological order;
//   • the unlocked build/craft catalogue grows monotonically and ends exactly at full catalog reachability;
//   • the pipeline refuses illegal starts and round-trips through save/load unchanged.

const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
// Shared with catalog.test.js: the memoized loader and the one reachability closure (the end-state a
// fully-researched pipeline must match). Keeps the ground-truth algorithm in a single place.
const { loadCatalog, reachability } = require("./_catalog");

// The pipeline under test is the GAME's own module (game/js/progression.js) — the JS mirror of
// progression.gd now lives in the playable web slice, and this suite drives it directly.
global.window = global.window || {};
vm.runInThisContext(
  fs.readFileSync(path.join(__dirname, "..", "game", "js", "progression.js"), "utf8"),
  { filename: "progression.js" });
const Progression = global.window.RW.Progression;

// The catalog-reachability closure that the pipeline's end-state must match (a fully-researched tree
// opens everything) is imported from ./_catalog.js — the same closure catalog.test.js uses.

test("progression: builds over the whole research tree", () => {
  const p = new Progression(loadCatalog());
  assert.ok(p.totalProjects() >= 40, "loads the full research tree");
  assert.strictEqual(p.unlockedCount(), 0, "cold start: nothing unlocked");
  assert.strictEqual(p.techLevel(), 0, "cold start: tech level 0");
});

test("progression: cold-start availability is exactly the prereq-free (tier-1) projects", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const avail = new Set(p.available().map((r) => r.id));
  const rootless = new Set(cat.research.filter((r) => (r.prereqs || []).length === 0).map((r) => r.id));
  assert.deepStrictEqual(avail, rootless, "only prereq-free projects are researchable from a cold start");
  assert.ok(rootless.size > 0, "there is at least one entry-point project");
});

test("progression: full auto-walk unlocks the ENTIRE tree in prereq-respecting order", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const order = [];
  let spent = 0;
  let guard = 0;
  let lastLevel = 0;
  while (p.unlockedCount() < p.totalProjects() && guard++ < 1000) {
    const next = p.autoNext();
    assert.notStrictEqual(next, "", "auto_next always finds a researchable project until the tree is done");
    // every prereq of the picked project is already unlocked (the core ordering guarantee)
    for (const pr of p.researchById.get(next).prereqs || [])
      assert.ok(p.unlocked.has(pr), `picked "${next}" before prereq "${pr}" was unlocked`);
    assert.ok(p.start(next), `can start "${next}"`);
    spent += p.activeCost();
    const done = p.addPoints(p.activeCost());   // exactly enough to finish it
    assert.deepStrictEqual(done, [next], "the project completes on exactly its cost");
    order.push(next);
    assert.ok(p.techLevel() >= lastLevel, "tech level never decreases");
    lastLevel = p.techLevel();
  }
  assert.strictEqual(p.unlockedCount(), p.totalProjects(), "every research node is unlocked");
  assert.strictEqual(order.length, p.totalProjects(), "each project unlocked exactly once");
  const totalCost = cat.research.reduce((s, r) => s + r.cost, 0);
  assert.ok(Math.abs(spent - totalCost) < 1e-6, "points spent equals the sum of all project costs");
  const maxTier = Math.max(...cat.research.map((r) => r.tier || 0));
  assert.strictEqual(p.techLevel(), maxTier, "finishing the tree reaches the deepest tech tier");
});

test("progression: leftover points roll from a finished project into the next (pipeline continuity)", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const roots = cat.research.filter((r) => (r.prereqs || []).length === 0).slice(0, 2);
  assert.ok(roots.length === 2, "need two entry-point projects for this test");
  assert.ok(p.enqueue(roots[0].id));
  assert.ok(p.enqueue(roots[1].id));
  const both = roots[0].cost + roots[1].cost;
  const done = p.addPoints(both);            // one grant, both finish
  assert.deepStrictEqual(done, [roots[0].id, roots[1].id], "both queued projects complete in one pump");
  assert.strictEqual(p.active, "", "pipeline idles once the queue drains");
  assert.strictEqual(p.progress, 0, "no stray progress left over");
});

test("progression: enqueue only ever accepts a valid topological order", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  // find a project with a prereq that is itself not a root
  const dep = cat.research.find((r) => (r.prereqs || []).length > 0);
  assert.ok(dep, "the tree has at least one project with prereqs");
  assert.strictEqual(p.enqueue(dep.id), false, "cannot enqueue a project whose prereqs are neither unlocked nor queued");
  // enqueue its prereqs first (they must themselves be enqueueable in order), then the dependent
  const chain = [];
  const collect = (id) => { for (const pr of p.researchById.get(id).prereqs || []) collect(pr); if (!chain.includes(id)) chain.push(id); };
  collect(dep.id);
  for (const id of chain) assert.ok(p.enqueue(id), `enqueue "${id}" once its prereqs precede it`);
  assert.ok(p.queue.includes(dep.id) || p.active === dep.id || p.unlocked.has(dep.id), "the dependent lands in the pipeline");
});

test("progression: unlocked catalogue grows monotonically and ends at full reachability", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  // cold start: only ungated buildings/recipes/items are open
  const ungatedB = cat.buildings.filter((b) => !b.research).length;
  assert.strictEqual(p.unlockedBuildings().length, ungatedB, "cold start opens exactly the ungated buildings");
  let lastB = p.unlockedBuildings().length, lastR = p.unlockedRecipes().length, lastI = p.unlockedItems().length;
  let guard = 0;
  while (p.unlockedCount() < p.totalProjects() && guard++ < 1000) {
    const n = p.autoNext();
    p.start(n); p.addPoints(p.activeCost());
    const b = p.unlockedBuildings().length, r = p.unlockedRecipes().length, i = p.unlockedItems().length;
    assert.ok(b >= lastB && r >= lastR && i >= lastI, "unlocked catalogue never shrinks as tech advances");
    lastB = b; lastR = r; lastI = i;
  }
  const reach = reachability(cat);
  assert.strictEqual(p.unlockedBuildings().length, cat.buildings.length, "all buildings open once fully researched");
  assert.strictEqual(p.unlockedRecipes().length, cat.recipes.length, "all recipes open once fully researched");
  assert.strictEqual(p.unlockedItems().length, cat.items.length, "all items open once fully researched");
  assert.strictEqual(reach.builtBuildings.size, cat.buildings.length, "catalog reachability agrees: nothing is stranded");
});

test("progression: refuses illegal starts", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const deep = cat.research.find((r) => (r.tier || 0) >= 3);
  assert.ok(deep, "the tree reaches tier 3+");
  assert.strictEqual(p.start(deep.id), false, "cannot start a deep project with unmet prereqs");
  const root = cat.research.find((r) => (r.prereqs || []).length === 0);
  assert.ok(p.start(root.id), "can start a root project");
  const otherRoot = cat.research.find((r) => (r.prereqs || []).length === 0 && r.id !== root.id);
  assert.strictEqual(p.start(otherRoot.id), false, "cannot start a second project while one is active");
});

test("progression: serialization round-trips the whole pipeline", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  // research a handful, queue one, leave one partially done
  let guard = 0;
  while (p.unlockedCount() < 5 && guard++ < 50) { const n = p.autoNext(); p.start(n); p.addPoints(p.activeCost()); }
  const next = p.autoNext();
  p.start(next);
  p.addPoints(p.activeCost() * 0.5);          // partial progress
  const blob = p.toDict();
  const q = new Progression(cat);
  q.fromDict(JSON.parse(JSON.stringify(blob)));
  assert.deepStrictEqual([...q.unlocked].sort(), [...p.unlocked].sort(), "unlocked set restored");
  assert.strictEqual(q.active, p.active, "active project restored");
  assert.ok(Math.abs(q.progress - p.progress) < 1e-9, "progress restored");
  assert.deepStrictEqual(q.summary(), p.summary(), "the whole viewmodel summary is identical after a round-trip");
});

test("progression: research_path is a valid topo order ending at the target", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const deep = cat.research.filter((r) => (r.tier || 0) >= 5);
  assert.ok(deep.length, "tree reaches tier 5+ for a meaty path");
  for (const target of deep) {
    const path = p.researchPath(target.id);
    assert.strictEqual(path[path.length - 1], target.id, "path ends at the target");
    assert.strictEqual(new Set(path).size, path.length, `no duplicate steps in path to ${target.id}`);
    const pos = new Map(path.map((id, i) => [id, i]));
    for (const id of path)
      for (const pr of p.researchById.get(id).prereqs || [])
        assert.ok(pos.get(pr) < pos.get(id), `prereq "${pr}" precedes "${id}" in the path`);
    // the path contains the full transitive closure of prereqs
    const closure = new Set();
    const walk = (id) => { for (const pr of p.researchById.get(id).prereqs || []) { closure.add(pr); walk(pr); } };
    walk(target.id);
    for (const c of closure) assert.ok(path.includes(c), `path to ${target.id} includes transitive prereq ${c}`);
  }
});

test("progression: enqueuing a research_path unlocks the target; steps_to_unlock drains to empty", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const target = cat.research.slice().sort((a, b) => (b.tier || 0) - (a.tier || 0))[0]; // deepest
  const path = p.researchPath(target.id);
  assert.strictEqual(p.stepsToUnlock(target.id).length, path.length, "cold start: every step of the path is still to do");
  for (const id of path) assert.ok(p.enqueue(id), `enqueue path step ${id}`);
  const done = p.addPoints(path.reduce((s, id) => s + p.researchById.get(id).cost, 0));
  assert.deepStrictEqual(done, path, "the whole path unlocks, in path order, from one grant");
  assert.ok(p.isUnlocked(target.id), "the target is unlocked");
  assert.strictEqual(p.stepsToUnlock(target.id).length, 0, "no steps remain once the target is unlocked");
});

test("progression: remaining_cost equals the sum of remaining path costs and drains to zero", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const target = cat.research.slice().sort((a, b) => (b.tier || 0) - (a.tier || 0))[0]; // deepest
  const path = p.researchPath(target.id);
  const fullCost = path.reduce((s, id) => s + p.researchById.get(id).cost, 0);
  assert.ok(Math.abs(p.remainingCost(target.id) - fullCost) < 1e-9, "cold start: remaining_cost == Σ full path cost");
  let prev = p.remainingCost(target.id);
  for (const id of path) {
    p.start(id); p.addPoints(p.researchById.get(id).cost);
    const now = p.remainingCost(target.id);
    assert.ok(now < prev + 1e-9, "remaining_cost never grows as the path is researched");
    prev = now;
  }
  assert.strictEqual(p.remainingCost(target.id), 0, "remaining_cost is zero once the target is unlocked");
});

test("progression: steps_to_unlock shrinks as the path is researched", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const target = cat.research.find((r) => (r.tier || 0) === 4) || cat.research.find((r) => (r.tier || 0) >= 3);
  const path = p.researchPath(target.id);
  let prev = p.stepsToUnlock(target.id).length;
  assert.strictEqual(prev, path.length, "starts at full path length");
  for (const id of path.slice(0, path.length - 1)) {
    // research just this one step (it is a root at this point because its prereqs precede it in path)
    p.start(id); p.addPoints(p.researchById.get(id).cost);
    const now = p.stepsToUnlock(target.id).length;
    assert.ok(now < prev, `steps_to_unlock shrinks after researching ${id}`);
    prev = now;
  }
  assert.strictEqual(p.stepsToUnlock(target.id).length, 1, "only the target itself remains");
});

test("progression: unlocks_of partitions all gated content by its gate", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  // union of unlocks_of over every research == exactly the gated content; each gated def appears once
  const seenB = new Map(), seenR = new Map(), seenI = new Map();
  for (const r of cat.research) {
    const u = p.unlocksOf(r.id);
    for (const id of u.buildings) { assert.ok(!seenB.has(id), `building ${id} gated by two projects`); seenB.set(id, r.id); }
    for (const id of u.recipes) { assert.ok(!seenR.has(id), `recipe ${id} gated by two projects`); seenR.set(id, r.id); }
    for (const id of u.items) { assert.ok(!seenI.has(id), `item ${id} gated by two projects`); seenI.set(id, r.id); }
  }
  const gatedB = cat.buildings.filter((b) => b.research).map((b) => b.id).sort();
  const gatedR = cat.recipes.filter((r) => r.research).map((r) => r.id).sort();
  const gatedI = cat.items.filter((i) => i.research).map((i) => i.id).sort();
  assert.deepStrictEqual([...seenB.keys()].sort(), gatedB, "every gated building is opened by exactly its gate");
  assert.deepStrictEqual([...seenR.keys()].sort(), gatedR, "every gated recipe is opened by exactly its gate");
  assert.deepStrictEqual([...seenI.keys()].sort(), gatedI, "every gated item is opened by exactly its gate");
  assert.deepStrictEqual(p.unlocksOf(""), { buildings: [], recipes: [], items: [] }, "no project opens ungated content");
});

test("progression: catalog_counts starts at ungated and grows to full", () => {
  const cat = loadCatalog();
  const p = new Progression(cat);
  const c0 = p.catalogCounts();
  assert.strictEqual(c0.buildings.total, cat.buildings.length, "counts report the full totals");
  assert.strictEqual(c0.buildings.unlocked, cat.buildings.filter((b) => !b.research).length, "cold start: only ungated buildings counted unlocked");
  assert.strictEqual(c0.items.unlocked, cat.items.filter((i) => !i.research).length, "cold start: only ungated items counted unlocked");
  let guard = 0;
  while (p.unlockedCount() < p.totalProjects() && guard++ < 1000) { const n = p.autoNext(); p.start(n); p.addPoints(p.activeCost()); }
  const c1 = p.catalogCounts();
  assert.strictEqual(c1.buildings.unlocked, c1.buildings.total, "fully researched: all buildings counted unlocked");
  assert.strictEqual(c1.recipes.unlocked, c1.recipes.total, "fully researched: all recipes counted unlocked");
  assert.strictEqual(c1.items.unlocked, c1.items.total, "fully researched: all items counted unlocked");
});

test("progression: auto_next is deterministic across fresh runs", () => {
  const cat = loadCatalog();
  const seqOf = () => {
    const p = new Progression(cat);
    const seq = [];
    for (let k = 0; k < 8; k++) { const n = p.autoNext(); seq.push(n); p.start(n); p.addPoints(p.activeCost()); }
    return seq;
  };
  assert.deepStrictEqual(seqOf(), seqOf(), "the same catalog yields the same research walk every time");
});

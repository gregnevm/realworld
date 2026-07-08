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

const CATALOG_PATH = path.join(__dirname, "..", "godot", "content", "catalog.json");
const loadCatalog = () => JSON.parse(fs.readFileSync(CATALOG_PATH, "utf8"));

// ---- The JS mirror of progression.gd (+ the ResearchState primitive it wraps) --------------------
class Progression {
  constructor(cat) {
    this.cat = cat;
    this.byId = new Map();
    for (const section of ["resources", "research", "buildings", "recipes", "items"])
      for (const rec of cat[section] || []) this.byId.set(rec.id, { section, rec });
    this.researchById = new Map(cat.research.map((r) => [r.id, r]));
    this.unlocked = new Set();
    this.active = "";
    this.progress = 0;
    this.queue = [];
  }
  // --- ResearchState primitive (production.gd) ---
  isUnlocked(id) { return this.unlocked.has(id); }
  prereqsMet(id) {
    const d = this.researchById.get(id);
    if (!d) return false;
    return (d.prereqs || []).every((p) => this.unlocked.has(p));
  }
  canStart(id) {
    if (this.unlocked.has(id) || !this.researchById.has(id)) return false;
    return this.prereqsMet(id);
  }
  tryStart(id) { if (!this.canStart(id)) return false; this.active = id; this.progress = 0; return true; }
  advance(dday) {
    if (this.active === "") return false;
    const d = this.researchById.get(this.active);
    if (!d) return false;
    this.progress += Math.max(0, dday);
    if (this.progress + 1e-9 >= d.cost) { this.unlocked.add(this.active); this.active = ""; this.progress = 0; return true; }
    return false;
  }
  // --- readout ---
  activeCost() { return this.active === "" ? 0 : this.researchById.get(this.active).cost; }
  activePct() { const c = this.activeCost(); return c <= 0 ? 0 : Math.min(1, this.progress / c); }
  unlockedCount() { return this.unlocked.size; }
  totalProjects() { return this.cat.research.length; }
  tierOf(id) { const r = this.researchById.get(id); return r ? (r.tier || 0) : 0; }
  labelOf(id) { const r = this.researchById.get(id); return r ? (r.label || id) : ""; }
  techLevel() { let lvl = 0; for (const id of this.unlocked) lvl = Math.max(lvl, this.tierOf(id)); return lvl; }
  // --- availability & queue ---
  available() {
    return this.cat.research.filter(
      (r) => !this.unlocked.has(r.id) && r.id !== this.active && !this.queue.includes(r.id) && this.prereqsMet(r.id));
  }
  isAvailable(id) {
    if (this.unlocked.has(id) || id === this.active || this.queue.includes(id)) return false;
    return this.researchById.has(id) && this.prereqsMet(id);
  }
  autoNext() {
    const a = this.available();
    if (!a.length) return "";
    a.sort((x, y) => (this.tierOf(x.id) - this.tierOf(y.id)) || (x.cost - y.cost) || (x.id < y.id ? -1 : x.id > y.id ? 1 : 0));
    return a[0].id;
  }
  enqueue(id) {
    if (this.unlocked.has(id) || !this.researchById.has(id)) return false;
    if (id === this.active || this.queue.includes(id)) return false;
    const d = this.researchById.get(id);
    for (const p of d.prereqs || [])
      if (!(this.unlocked.has(p) || this.queue.includes(p) || p === this.active)) return false;
    this.queue.push(id);
    this._ensureActive(false);
    return true;
  }
  dequeue(id) { const i = this.queue.indexOf(id); if (i >= 0) this.queue.splice(i, 1); }
  start(id) { if (this.active !== "") return false; return this.tryStart(id); }
  addPoints(points, auto = false) {
    const newly = [];
    let remaining = Math.max(0, points);
    this._ensureActive(auto);
    while (remaining > 1e-9 && this.active !== "") {
      const cur = this.active;
      const d = this.researchById.get(cur);
      if (!d) break;
      const need = Math.max(0, d.cost - this.progress);
      if (remaining + 1e-9 >= need) { this.advance(need); newly.push(cur); remaining -= need; this._ensureActive(auto); }
      else { this.advance(remaining); remaining = 0; }
    }
    return newly;
  }
  _ensureActive(auto) {
    while (this.active === "" && this.queue.length) {
      const id = this.queue[0];
      if (this.unlocked.has(id)) { this.queue.shift(); continue; }
      if (this.canStart(id)) { this.queue.shift(); this.tryStart(id); }
      else break;
    }
    if (this.active === "" && auto) { const n = this.autoNext(); if (n !== "") this.tryStart(n); }
  }
  // --- tech-path planner ---
  researchPath(id) {
    if (!this.researchById.has(id)) return [];
    const out = [], seen = new Set(), stack = new Set();
    const visit = (rid) => {
      if (seen.has(rid) || stack.has(rid)) return;
      stack.add(rid);
      const d = this.researchById.get(rid);
      if (d) for (const p of d.prereqs || []) visit(p);
      stack.delete(rid);
      seen.add(rid);
      out.push(rid);
    };
    visit(id);
    return out;
  }
  stepsToUnlock(gate) { return !gate ? [] : this.researchPath(gate).filter((x) => !this.unlocked.has(x)); }
  remainingCost(target) { return this.stepsToUnlock(target).reduce((s, id) => s + this.researchById.get(id).cost, 0); }
  // --- unlock gates over catalog content ---
  gateOk(ref) { return ref === undefined || ref === null || ref === "" || this.unlocked.has(ref); }
  unlockedBuildings() { return this.cat.buildings.filter((b) => this.gateOk(b.research)); }
  unlockedRecipes() { return this.cat.recipes.filter((r) => this.gateOk(r.research)); }
  unlockedItems() { return this.cat.items.filter((i) => this.gateOk(i.research)); }
  unlocksOf(rid) {
    if (!rid) return { buildings: [], recipes: [], items: [] };
    return {
      buildings: this.cat.buildings.filter((b) => b.research === rid).map((b) => b.id),
      recipes: this.cat.recipes.filter((r) => r.research === rid).map((r) => r.id),
      items: this.cat.items.filter((i) => i.research === rid).map((i) => i.id),
    };
  }
  catalogCounts() {
    return {
      buildings: { unlocked: this.unlockedBuildings().length, total: this.cat.buildings.length },
      recipes: { unlocked: this.unlockedRecipes().length, total: this.cat.recipes.length },
      items: { unlocked: this.unlockedItems().length, total: this.cat.items.length },
    };
  }
  // --- viewmodel + serialization ---
  summary() {
    return { active: this.active, active_label: this.labelOf(this.active), active_pct: this.activePct(),
      active_cost: this.activeCost(), active_progress: this.progress, queue: this.queue.slice(),
      unlocked: this.unlockedCount(), total: this.totalProjects(), level: this.techLevel() };
  }
  toDict() { return { unlocked: [...this.unlocked], active: this.active, progress: this.progress, queue: this.queue.slice() }; }
  fromDict(d) {
    this.unlocked = new Set(d.unlocked || []);
    this.active = d.active || "";
    this.progress = d.progress || 0;
    this.queue = (d.queue || []).slice();
  }
}

// The catalog-reachability closure (copied minimal, same as catalog.test.js) — the ground truth the
// pipeline's end-state must match: everything is reachable, so a fully-researched tree opens everything.
function fullReachability(cat) {
  const RAW = new Set(["mine", "chop", "gather", "hunt", "farm"]);
  const isRaw = (r) => (r.sources || []).some((s) => RAW.has(s));
  const obtainable = new Set(cat.resources.filter(isRaw).map((r) => r.id));
  const unlocked = new Set(), built = new Set(), recs = new Set(), items = new Set();
  const gate = (g) => !g || unlocked.has(g);
  const cost = (c) => Object.keys(c || {}).every((k) => obtainable.has(k));
  let changed = true;
  while (changed) {
    changed = false;
    for (const r of cat.research) if (!unlocked.has(r.id) && (r.prereqs || []).every((p) => unlocked.has(p))) { unlocked.add(r.id); changed = true; }
    for (const b of cat.buildings) if (!built.has(b.id) && gate(b.research) && cost(b.cost)) { built.add(b.id); changed = true; }
    for (const r of cat.recipes) if (!recs.has(r.id) && built.has(r.station) && gate(r.research) && cost(r.inputs)) { recs.add(r.id); obtainable.add(r.output.id); changed = true; }
    for (const i of cat.items) if (!items.has(i.id) && built.has(i.station) && gate(i.research) && cost(i.recipe)) { items.add(i.id); changed = true; }
  }
  return { unlocked, built, recs, items };
}

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
  const reach = fullReachability(cat);
  assert.strictEqual(p.unlockedBuildings().length, cat.buildings.length, "all buildings open once fully researched");
  assert.strictEqual(p.unlockedRecipes().length, cat.recipes.length, "all recipes open once fully researched");
  assert.strictEqual(p.unlockedItems().length, cat.items.length, "all items open once fully researched");
  assert.strictEqual(reach.built.size, cat.buildings.length, "catalog reachability agrees: nothing is stranded");
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

/* RealWorld — progression.js : the research→unlock pipeline over the content catalog (RW.CATALOG).
   The JS mirror of godot/scripts/kernel/progression.gd (same semantics, same catalog.json):
   a research queue with prereq-checked starts, leftover points rolling into the next project,
   a tech-path planner, and unlock gates the build/craft layer reads. tests/progression.test.js
   drives THIS class against the real catalog, so the web game and the Godot kernel can never
   silently disagree about how the tech tree walks. */
window.RW = window.RW || {};
(function (RW) {
  "use strict";

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

  RW.Progression = Progression;
  RW.newProgression = () => new Progression(RW.CATALOG);

  // Plan the full research path to `gate` — enqueues every missing prereq in prereq order.
  // Returns the list of ids actually enqueued ([] when the gate is already unlocked / in pipeline).
  RW.planResearchPath = function (research, gate) {
    const queued = [];
    for (const id of research.stepsToUnlock(gate)) {
      if (id === research.active || research.queue.includes(id)) continue;
      if (research.enqueue(id)) queued.push(id);
    }
    return queued;
  };

})(window.RW);

/* RealWorld — Node tests for the deterministic, DOM-free simulation core.
   Loads the browser modules into a minimal window shim and exercises pure logic.
   Run: npm test   (node --test tests/) */
"use strict";
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

// minimal browser shims so the classic-script modules load under Node
global.window = { addEventListener() {}, devicePixelRatio: 1, innerWidth: 800, innerHeight: 600 };
global.innerWidth = 800;
global.innerHeight = 600;

const jsDir = path.join(__dirname, "..", "game", "js");
for (const f of ["util.js", "worldgen.js", "entities.js", "catalog_data.js", "progression.js", "logistics.js", "game.js"]) {
  vm.runInThisContext(fs.readFileSync(path.join(jsDir, f), "utf8"), { filename: f });
}
const RW = global.window.RW;
// Stub the small UI surface the sim tick reaches (all defined in the unloaded ui.js) so the whole
// RW.update graph runs headless — the sim itself stays DOM-free, these are just its output hooks.
RW.log = () => {};
RW.setTicker = () => {};
RW.raidBanner = () => {};
RW.syncBuildBar = () => {};
RW.buildBuildBar = () => {};

test("RNG seed is deterministic for the same coordinates", () => {
  assert.strictEqual(RW.hashSeed(50.4501, 30.5234), RW.hashSeed(50.4501, 30.5234));
  assert.notStrictEqual(RW.hashSeed(50.4501, 30.5234), RW.hashSeed(49.84, 24.03));
  const r = RW.mulberry32(12345);
  for (let i = 0; i < 100; i++) { const v = r(); assert.ok(v >= 0 && v < 1); }
});

test("haversine matches a known Kyiv→Lviv distance (~467 km)", () => {
  const km = RW.haversineKm(50.4501, 30.5234, 49.8397, 24.0297);
  assert.ok(km > 450 && km < 485, `got ${km}`);
});

test("generateMap is fully deterministic from lat/lon", () => {
  const a = RW.generateMap(50.4501, 30.5234, 56);
  const b = RW.generateMap(50.4501, 30.5234, 56);
  assert.strictEqual(a.N, 56);
  assert.deepStrictEqual(Array.from(a.tiles), Array.from(b.tiles));
  assert.strictEqual(a.nodes.size, b.nodes.size);
  assert.ok(a.nodes.size > 50, "expected resource nodes to be seeded");
  // spawn must be a passable tile with a cleared neighbourhood
  const sp = a.spawn, i = sp.y * a.N + sp.x;
  assert.ok(!RW.isTerrainBlocked(a.tiles[i]), "spawn tile must be passable");
});

test("findPath reaches reachable targets, walks toward unreachable ones, null only when boxed in", () => {
  const N = 6;
  const open = RW.findPath(N, 0, 0, 5, 0, () => false);
  assert.ok(open, "open grid should be traversable");
  assert.deepStrictEqual(open[open.length - 1], { x: 5, y: 0 });

  // gap at y=4 in wall column x=3 -> target reachable through the gap
  const gap = RW.findPath(N, 0, 0, 5, 0, (i) => (i % N) === 3 && ((i / N) | 0) !== 4);
  assert.ok(gap, "path should route through the gap");
  assert.deepStrictEqual(gap[gap.length - 1], { x: 5, y: 0 });

  // full wall column x=3 -> target unreachable; findPath is best-effort and
  // returns a partial path that stops before the wall (intended for click-to-move)
  const walled = RW.findPath(N, 0, 0, 5, 0, (i) => (i % N) === 3);
  assert.ok(walled, "returns a best-effort partial path");
  assert.ok(walled[walled.length - 1].x < 3, "cannot cross the wall");
  assert.notDeepStrictEqual(walled[walled.length - 1], { x: 5, y: 0 });

  // start boxed in on all four sides -> no move possible -> null
  const boxed = RW.findPath(N, 1, 1, 5, 5, (i) => {
    const x = i % N, y = (i / N) | 0;
    return (x === 0 && y === 1) || (x === 2 && y === 1) || (x === 1 && y === 0) || (x === 1 && y === 2);
  });
  assert.strictEqual(boxed, null, "fully enclosed start yields null");
});

test("raid wave size scales with the day and clamps", () => {
  assert.strictEqual(RW.raidWaveSize(1), 2);
  assert.strictEqual(RW.raidWaveSize(2), 2);
  assert.strictEqual(RW.raidWaveSize(4), 3);
  assert.strictEqual(RW.raidWaveSize(10), 7);
  assert.strictEqual(RW.raidWaveSize(50), 12); // clamped
  assert.ok(RW.raidWaveSize(5) >= RW.raidWaveSize(1));
});

test("data tables are internally consistent", () => {
  for (const k in RW.NODEINFO) assert.ok(RW.RES[RW.NODEINFO[k].res], `node ${k} yields unknown resource`);
  for (const b in RW.BUILDINGS) {
    for (const c in RW.BUILDINGS[b].cost) assert.ok(RW.RES[c], `building ${b} costs unknown resource ${c}`);
  }
  // every relation-free assertion: order lists cover the tables
  assert.strictEqual(RW.BUILD_ORDER.length, Object.keys(RW.BUILDINGS).length);
  assert.strictEqual(RW.RES_ORDER.length, Object.keys(RW.RES).length);
});

test("convoy round-trip deducts cargo, then deposits the traded goods", () => {
  const stock = { wood: 50, stone: 0, food: 0, scrap: 0, planks: 0, components: 0 };
  const G = {
    base: { stock }, buildings: [], convoys: [], convoySeq: 0,
    regions: [
      { name: "База", lat: 50.4501, lon: 30.5234, home: true },
      { name: "Хаб", lat: 49.8397, lon: 24.0297, offer: { buys: "wood", sells: "components", rate: 6 } }
    ]
  };
  const res = RW.dispatchConvoy(G, 1, "wood", 12);
  assert.ok(res.ok, "dispatch should succeed");
  assert.strictEqual(stock.wood, 38, "12 wood removed from stock");
  assert.strictEqual(G.convoys.length, 1);
  const c = G.convoys[0];
  assert.strictEqual(c.recvRes, "components");
  assert.strictEqual(c.recvAmt, 2, "floor(12/6)=2");
  assert.strictEqual(c.phase, "out");

  // wrong resource is rejected
  assert.strictEqual(RW.dispatchConvoy(G, 1, "stone", 5).ok, false);

  // drive the convoy home with no ambush (the ambush roll now reads the game's seeded rng,
  // so the test just injects a high-roll stub — no more global Math.random monkeypatching)
  G.rng = () => 0.99;
  RW.updateConvoys(G, 9999); // out -> back
  assert.strictEqual(G.convoys[0].phase, "back");
  RW.updateConvoys(G, 9999); // back -> arrived
  assert.strictEqual(G.convoys.length, 0, "convoy completed");
  assert.strictEqual(stock.components, 2, "traded components delivered to stock");
});

// ---------------------------------------------------------------------------
// Core tick loop (RW.update). Previously untested: the ~290-line update graph
// (needs decay, auto-eat/deposit, crafting, gather, raids, day rollover, enemy
// movement) has zero Node coverage. The sim reaches the DOM only through the
// RW.log/setTicker/raidBanner hooks stubbed above, so it runs fully headless.
// ---------------------------------------------------------------------------

// A fresh, DOM-free game: real deterministic map + auto-placed landing crate.
function makeGame() {
  const map = RW.generateMap(50.4501, 30.5234, 56);
  map.placeName = "Тест";
  const G = RW.newGame(map);   // builds state and auto-places the storage crate near spawn
  G.keys = {};                 // the input layer normally seeds this; updatePlayer reads G.keys.*
  return G;
}

// A passable tile adjacent to (cx,cy) that holds neither a building nor a node.
function freeTileNear(G, cx, cy) {
  const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]];
  for (const [dx, dy] of dirs) {
    const x = cx + dx, y = cy + dy;
    if (x < 1 || y < 1 || x >= G.map.N - 1 || y >= G.map.N - 1) continue;
    const i = y * G.map.N + x;
    if (RW.isTerrainBlocked(G.map.tiles[i])) continue;
    if (G.bgrid.has(i) || G.map.nodes.has(i)) continue;
    return { x, y, i };
  }
  return null;
}

test("update: the day advances when the clock wraps past midnight", () => {
  const G = makeGame();
  G.time.frac = 0.99; G.time.day = 1;
  RW.update(G, 3.0);   // 3s / 150s-day = 0.02 > the 0.01 remaining -> exactly one rollover
  assert.strictEqual(G.time.day, 2, "one day rollover");
  assert.ok(G.time.frac >= 0 && G.time.frac < 1, "fraction normalised into [0,1)");
});

test("update: hunger and rest decay while awake", () => {
  const G = makeGame();
  const p = G.player;
  p.hunger = 80; p.rest = 80; p.sleeping = false;   // >55 so auto-eat stays off
  RW.update(G, 1.0);
  assert.ok(Math.abs(p.hunger - (80 - 0.42)) < 1e-9, `hunger decays ~0.42/s (got ${p.hunger})`);
  assert.ok(Math.abs(p.rest - (80 - 0.30)) < 1e-9, `rest decays ~0.30/s (got ${p.rest})`);
});

test("update: starvation and exhaustion drain HP", () => {
  const G = makeGame();
  const p = G.player;
  p.hunger = 0; p.rest = 0; p.hp = 100;
  RW.update(G, 1.0);   // -2.0/s starving, -1.0/s exhausted, no regen while starving
  assert.ok(Math.abs(p.hp - 97.0) < 1e-6, `hp loses 3.0/s when starved and exhausted (got ${p.hp})`);
});

test("update: auto-eats from storage when hungry and nearby", () => {
  const G = makeGame();
  const p = G.player;
  p.hunger = 50; p.eatCd = 0;
  const food0 = G.base.stock.food;
  RW.update(G, 0.1);
  assert.strictEqual(G.base.stock.food, food0 - 1, "one food consumed from the crate");
  assert.ok(p.hunger > 80, `the meal restores hunger (got ${p.hunger})`);
});

test("update: auto-deposits carried goods at storage", () => {
  const G = makeGame();
  const p = G.player;
  p.carry = { wood: 5 }; p.depCd = 0;
  const wood0 = G.base.stock.wood;
  RW.update(G, 0.1);
  assert.strictEqual(RW.carryTotal(p), 0, "carry emptied at the crate");
  assert.strictEqual(G.base.stock.wood, wood0 + 5, "the wood is delivered to stock");
});

test("deposit clamps to storage capacity and drops the overflow", () => {
  const G = makeGame();
  const cap = RW.storageCap(G);
  G.base.stock = { wood: cap, stone: 0, food: 0, scrap: 0, planks: 0, components: 0 };
  const added = RW.deposit(G, "stone", 10);
  assert.strictEqual(added, 0, "nothing fits at capacity");
  assert.strictEqual(G.base.stock.stone, 0, "overflow is lost, not stored");
});

test("update: a full gather cycle harvests a node into stock", () => {
  const G = makeGame();
  const p = G.player;
  const spot = freeTileNear(G, Math.floor(p.px), Math.floor(p.py));
  assert.ok(spot, "found a free tile next to the player");
  G.map.nodes.set(spot.i, { kind: "tree", amount: 5 });
  RW.orderGather(G, spot.x, spot.y);
  for (let k = 0; k < 40; k++) RW.update(G, 0.1);   // tree takes ~1.3s/unit; 4s harvests a few
  const node = G.map.nodes.get(spot.i);
  const gained = (p.carry.wood || 0) + (G.base.stock.wood - 50); // carried or auto-deposited
  assert.ok(gained > 0, "at least one wood harvested (carried or deposited)");
  assert.ok(node === undefined || node.amount < 5, "the node was drawn down");
});

// ---------------------------------------------------------------------------
// Research pipeline in the web slice (spec 0007): the catalog tech tree gates
// buildings and recipes; research benches generate progress through RW.update.
// ---------------------------------------------------------------------------

test("catalog_data.js is in sync with godot/content/catalog.json", () => {
  const canon = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "godot", "content", "catalog.json"), "utf8"));
  assert.deepStrictEqual(RW.CATALOG, canon, "regenerate with: node tools/sync-catalog.mjs");
});

test("research: bench generates points through RW.update and completes carpentry", () => {
  const G = makeGame();
  assert.ok(G.research, "a new game carries the progression pipeline");
  const spot = freeTileNear(G, Math.floor(G.player.px), Math.floor(G.player.py));
  G.selectedBuild = "research_bench";
  RW.tryBuild(G, spot.x, spot.y);
  assert.ok(G.buildings.some(b => b.kind === "research_bench"), "research bench built (ungated)");
  assert.ok(G.research.enqueue("carpentry"), "carpentry is enqueueable from a cold start");
  for (let k = 0; k < 320 && !G.research.isUnlocked("carpentry"); k++) RW.update(G, 0.1);
  assert.ok(G.research.isUnlocked("carpentry"), "carpentry completes from bench-generated points (~28s)");
  assert.ok(G.research.gateOk("carpentry"), "the carpentry gate now reads unlocked");
});

test("research: a locked building is refused and its research path auto-planned", () => {
  const G = makeGame();
  G.base.stock.scrap = 50; G.base.stock.components = 10;
  const spot = freeTileNear(G, Math.floor(G.player.px), Math.floor(G.player.py));
  G.selectedBuild = "turret";   // machining-gated in the catalog
  RW.tryBuild(G, spot.x, spot.y);
  assert.ok(!G.buildings.some(b => b.kind === "turret"), "locked turret is not placed");
  const pipeline = new Set([G.research.active, ...G.research.queue]);
  assert.ok(pipeline.has("machining"), "the machining gate landed in the research pipeline");
  for (const pre of G.research.researchById.get("machining").prereqs || [])
    assert.ok(pipeline.has(pre) || G.research.isUnlocked(pre), `prereq ${pre} planned ahead of machining`);
});

test("crafting: workbench planks are gated by carpentry (catalog make_planks gate)", () => {
  const G = makeGame();
  const spot = freeTileNear(G, Math.floor(G.player.px), Math.floor(G.player.py));
  G.selectedBuild = "workbench";
  RW.tryBuild(G, spot.x, spot.y);
  assert.ok(G.buildings.some(b => b.kind === "workbench"), "workbench built");
  for (let k = 0; k < 100; k++) RW.update(G, 0.1);   // 10s: enough for ~2 crafts if unlocked
  assert.strictEqual(G.base.stock.planks, 0, "no planks while carpentry is locked");
  G.research.enqueue("carpentry");
  G.research.addPoints(999);
  for (let k = 0; k < 100; k++) RW.update(G, 0.1);
  assert.ok(G.base.stock.planks > 0, "planks flow once carpentry is researched");
});

test("defense: a spike trap wears down enemies standing on it", () => {
  const G = makeGame();
  G.research.addPoints(1000, true);   // auto-walk the whole tree -> fortification unlocked
  assert.ok(G.research.gateOk("fortification"), "full tree unlocks fortification");
  const spot = freeTileNear(G, Math.floor(G.player.px), Math.floor(G.player.py));
  G.base.stock.scrap = 20;
  G.selectedBuild = "spike_trap";
  RW.tryBuild(G, spot.x, spot.y);
  const trap = G.buildings.find(b => b.kind === "spike_trap");
  assert.ok(trap, "trap placed once researched");
  const e = RW.makeRaider(spot.x + 0.5, spot.y + 0.5, 1);
  G.enemies.push(e);
  const hp0 = e.hp, trapHp0 = trap.hp;
  for (let k = 0; k < 10; k++) RW.update(G, 0.1);   // jitter comes from the seeded G.rng now
  assert.ok(e.hp < hp0 || e.dead || G.enemies.indexOf(e) < 0, "the trap damaged the raider");
  assert.ok(trap.hp < trapHp0 || !G.buildings.includes(trap), "the trap wears out as it bites");
});

test("update: enemies advance toward the base (followPath movement)", () => {
  // no Math.random stubbing needed anymore: the sim's jitter reads the seeded G.rng
  const G = makeGame();
  const center = RW.baseCenter(G);
  let ex = Math.min(center.x + 10, G.map.N - 3), ey = center.y;
  while (ex > center.x + 2 && RW.isTerrainBlocked(G.map.tiles[ey * G.map.N + ex])) ex--;
  const e = RW.makeRaider(ex + 0.5, ey + 0.5, 1);
  G.enemies.push(e);
  const d0 = RW.dist(e.px, e.py, center.x + 0.5, center.y + 0.5);
  for (let k = 0; k < 30; k++) RW.update(G, 0.1);
  const d1 = RW.dist(e.px, e.py, center.x + 0.5, center.y + 0.5);
  assert.ok(d1 < d0, `raider closed on the base (${d0.toFixed(2)} -> ${d1.toFixed(2)})`);
});

// ---------------------------------------------------------------------------
// Seeded gameplay rng: raids, loot, ambushes are reproducible from coordinates.
// ---------------------------------------------------------------------------

test("determinism: two games from the same coordinates spawn identical raid waves", () => {
  const spawnAt = (G) => {
    G.raid.timer = G.raid.next;   // due now
    RW.update(G, 0.01);           // updateRaids fires spawnWave
    return G.enemies.map(en => [Math.round(en.px * 10), Math.round(en.py * 10)]);
  };
  const a = spawnAt(makeGame());
  const b = spawnAt(makeGame());
  assert.ok(a.length > 0, "a wave actually spawned");
  assert.deepStrictEqual(a, b, "same seed -> same wave size, edge and positions");
});

test("determinism: the gameplay rng state round-trips through save format", () => {
  const G = makeGame();
  for (let i = 0; i < 7; i++) G.rng();          // advance the stream
  const state = G.rng.getState();
  const seq = [G.rng(), G.rng(), G.rng()];      // consume 3 values
  const restored = RW.mulberry32(0);
  restored.setState(state);                     // resume from the saved state
  assert.deepStrictEqual([restored(), restored(), restored()], seq, "restored stream continues identically");
});

// ---------------------------------------------------------------------------
// UX/sim pipeline polish: drag-build runs, door gating, demolish/repair economics,
// reachable raid spawns, floating text, and the frozen-after-death rule.
// ---------------------------------------------------------------------------
function freshGame() {
  const map = RW.generateMap(50.4501, 30.5234, 56);
  map.placeName = "Тест";
  return RW.newGame(map);
}

test("lineCells draws an inclusive L-shaped run in either direction", () => {
  assert.deepStrictEqual(RW.lineCells(2, 2, 2, 2), [{ x: 2, y: 2 }]);
  assert.deepStrictEqual(RW.lineCells(0, 0, 2, 0), [{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 2, y: 0 }]);
  const l = RW.lineCells(3, 3, 1, 5);
  assert.deepStrictEqual(l, [{ x: 3, y: 3 }, { x: 2, y: 3 }, { x: 1, y: 3 }, { x: 1, y: 4 }, { x: 1, y: 5 }]);
});

test("buildRun places a wall line, stops when the stockpile runs dry, never over nodes/water", () => {
  const G = freshGame();
  const sp = G.map.spawn;
  G.base.stock.stone = 12;            // room for exactly 2 walls at 5 stone each
  G.selectedBuild = "wall";
  const placed = RW.buildRun(G, RW.lineCells(sp.x - 2, sp.y - 2, sp.x + 2, sp.y - 2));
  assert.strictEqual(placed, 2);
  assert.strictEqual(G.base.stock.stone, 2);
  assert.strictEqual(G.stats.built, 2);
  // the crate's own cell can never be built over, quietly or not
  G.base.stock.stone = 50;
  const crate = G.buildings.find(b => b.kind === "storage");
  assert.strictEqual(RW.tryBuild(G, crate.x, crate.y, true), false);
});

test("a door lets the player through but is a wall to raiders", () => {
  const G = freshGame();
  const sp = G.map.spawn, i = (sp.y - 1) * G.map.N + sp.x;
  G.selectedBuild = "door"; assert.ok(RW.tryBuild(G, sp.x, sp.y - 1));
  assert.strictEqual(RW.isBlocked(G, i), false, "player path passes a door");
  assert.strictEqual(RW.isEnemyBlocked(G, i), true, "raiders must smash a door");
  G.selectedBuild = "wall"; assert.ok(RW.tryBuild(G, sp.x, sp.y + 1));
  assert.strictEqual(RW.isBlocked(G, (sp.y + 1) * G.map.N + sp.x), true);
});

test("demolish refunds half the cost, repair is priced by missing hp and needs proximity", () => {
  const G = freshGame();
  const sp = G.map.spawn;
  assert.deepStrictEqual(RW.refundOf({ wood: 18, stone: 4 }), { wood: 9, stone: 2 });
  assert.deepStrictEqual(RW.refundOf({ wood: 1 }), {});
  G.selectedBuild = "workbench";
  assert.ok(RW.tryBuild(G, sp.x + 1, sp.y + 1));
  const b = G.buildings.find(x => x.kind === "workbench");
  const wood0 = G.base.stock.wood;
  // full hp: nothing to repair, nothing charged
  assert.strictEqual(RW.repair(G, b), false);
  assert.strictEqual(G.base.stock.wood, wood0);
  b.hp = 10;
  const price = RW.repairCostOf(RW.BUILDINGS.workbench, 10);
  assert.ok(price.wood >= 1 && price.wood <= 6, `repair price scales with damage, got ${JSON.stringify(price)}`);
  assert.strictEqual(RW.repair(G, b), true);
  assert.strictEqual(b.hp, RW.BUILDINGS.workbench.hp);
  assert.strictEqual(G.base.stock.wood, wood0 - price.wood);
  // too far away → refused, untouched
  b.hp = 10; G.player.px += 10;
  assert.strictEqual(RW.repair(G, b), false);
  assert.strictEqual(b.hp, 10);
  G.player.px -= 10;
  G.selected = b;
  assert.strictEqual(RW.demolish(G, b), true);
  assert.strictEqual(G.buildings.indexOf(b), -1);
  assert.strictEqual(G.selected, null, "demolishing the selection clears it");
  assert.strictEqual(G.base.stock.wood, wood0 - price.wood + 9);
});

test("raid spawn cells are all reachable from the base over terrain", () => {
  const G = freshGame();
  const cells = RW.raidSpawnCells(G);
  assert.ok(cells.length > 0);
  const c = RW.baseCenter(G), N = G.map.N;
  for (const i of cells) {
    assert.ok(!RW.isTerrainBlocked(G.map.tiles[i]), "spawn cell is walkable");
    const p = RW.findPath(N, i % N, (i / N) | 0, c.x, c.y, j => RW.isTerrainBlocked(G.map.tiles[j]));
    assert.ok(p && p.length && p[p.length - 1].x === c.x && p[p.length - 1].y === c.y, "a full path to the base exists");
  }
  // the wave itself: forced due, every raider stands on a spawn cell and the pack is staggered
  G.raid.next = 0; RW.update(G, 0.01);
  assert.ok(G.enemies.length >= 2);
  assert.ok(G.enemies.some(e => e.delay > 0), "later raiders trickle in");
  for (const e of G.enemies) assert.ok(cells.includes(Math.floor(e.py) * N + Math.floor(e.px)));
});

test("floating text decays, and the sim freezes once the pawn is dead", () => {
  const G = freshGame();
  RW.fxText(G, 1, 1, "+1", "#fff");
  assert.strictEqual(G.fx.length, 1);
  RW.update(G, 0.5); assert.strictEqual(G.fx.length, 1);
  RW.update(G, 1.0); assert.strictEqual(G.fx.length, 0);
  const day = G.time.day, frac = G.time.frac;
  G.player.hp = 0.001; G.player.hunger = 0;
  RW.update(G, 1);                       // dies this tick
  assert.strictEqual(G._dead, true);
  assert.strictEqual(G.speed, 0);
  const fracAfterDeath = G.time.frac;
  RW.update(G, 50);                      // nothing moves behind the death screen
  assert.strictEqual(G.time.frac, fracAfterDeath);
  assert.strictEqual(G.time.day, day);
  assert.ok(frac <= fracAfterDeath);
  assert.ok(RW.runSummary(G).some(([k]) => k.includes("днів")));
});

test("save/load round-trips zoom, stats and the log tail", () => {
  const store = {};
  global.localStorage = { getItem: k => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; } };
  const G = freshGame();
  G.tile = 32; G.stats.kills = 7; G.lastSpeed = 3;
  for (let i = 0; i < 50; i++) G.log.push({ msg: "m" + i, cls: "", day: 1, t: "00:00" });
  RW.saveGame(G);
  const s = JSON.parse(store.realworld_save);
  assert.strictEqual(s.tile, 32);
  assert.strictEqual(s.stats.kills, 7);
  assert.strictEqual(s.log.length, 40, "only the log tail is persisted");
  assert.deepStrictEqual(RW.saveMeta(), { name: "Тест", day: 1, lat: 50.4501, lon: 30.5234 });
  delete global.localStorage;
});

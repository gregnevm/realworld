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
for (const f of ["util.js", "worldgen.js", "entities.js", "logistics.js", "game.js"]) {
  vm.runInThisContext(fs.readFileSync(path.join(jsDir, f), "utf8"), { filename: f });
}
const RW = global.window.RW;
// Stub the small UI surface the sim tick reaches (all defined in the unloaded ui.js) so the whole
// RW.update graph runs headless — the sim itself stays DOM-free, these are just its output hooks.
RW.log = () => {};
RW.setTicker = () => {};
RW.raidBanner = () => {};

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
  assert.strictEqual(RW.raidWaveSize(10), 11);
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

  // drive the convoy home with no ambush (stub Math.random high)
  const realRandom = Math.random;
  Math.random = () => 0.99;
  try {
    RW.updateConvoys(G, 9999); // out -> back
    assert.strictEqual(G.convoys[0].phase, "back");
    RW.updateConvoys(G, 9999); // back -> arrived
  } finally { Math.random = realRandom; }
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

test("update: enemies advance toward the base (followPath movement)", () => {
  const realRandom = Math.random;
  Math.random = () => 0.5;   // freeze raid/repath jitter for a deterministic assertion
  try {
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
  } finally {
    Math.random = realRandom;
  }
});

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
RW.log = () => {}; // stub the UI logger used by logistics

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

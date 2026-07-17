/* RealWorld — worldgen.js : real lat/lon -> tile map.
   Procedural (deterministic from coordinates) always runs so the game is
   instantly playable offline; if enabled & reachable, real OpenStreetMap
   geometry (roads, water, woods, buildings) is rasterised on top. */
(function (RW) {
  "use strict";

  RW.T = { WATER: 0, GRASS: 1, FOREST: 2, ROCK: 3, ROAD: 4, SOIL: 5, RUIN: 6, SAND: 7, SNOW: 8 };
  RW.terrainName = ["вода", "трава", "ліс", "скеля", "дорога", "ґрунт", "руїни", "пісок", "сніг"];
  RW.isTerrainBlocked = (t) => t === RW.T.WATER || t === RW.T.ROCK;

  const T = RW.T;

  RW.generateMap = function (lat, lon, N) {
    N = N || 56;
    const seed = RW.hashSeed(lat, lon);
    const rng = RW.mulberry32(seed);
    const noise = RW.makeNoise(rng, 8);
    const noise2 = RW.makeNoise(RW.mulberry32((seed ^ 0x9e3779b9) >>> 0), 16);
    const absLat = Math.abs(lat);
    const snowy = absLat > 57;
    const arid = absLat > 14 && absLat < 33 && noise(31.7, 12.3) > 0.52;
    const urban = (seed % 997) / 997;              // settlement density proxy
    const tiles = new Uint8Array(N * N).fill(T.GRASS);
    const nodes = new Map();

    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const i = y * N + x;
      const e = noise(x / N * 4.0, y / N * 4.0);
      const f = noise2(x / N * 4.0 * 1.7 + 5, y / N * 4.0 * 1.7 + 5);
      let t;
      if (e < 0.30) t = T.WATER;
      else if (e < 0.355) t = snowy ? T.SNOW : (arid ? T.SAND : T.SOIL);
      else if (f > 0.66) t = T.FOREST;
      else if (f < 0.19) t = T.ROCK;
      else t = (snowy && e > 0.8) ? T.SNOW : (arid ? T.SAND : T.GRASS);
      tiles[i] = t;
    }

    // settlement ruins clusters (scrap source) scaled by urban density
    const clusters = Math.floor(2 + urban * 6);
    for (let k = 0; k < clusters; k++) {
      const cx = 4 + ((rng() * (N - 8)) | 0), cy = 4 + ((rng() * (N - 8)) | 0);
      const w = 2 + ((rng() * 3) | 0), h = 2 + ((rng() * 3) | 0);
      for (let yy = -h; yy <= h; yy++) for (let xx = -w; xx <= w; xx++) {
        if (rng() < 0.35) continue;
        const x = cx + xx, y = cy + yy;
        if (x < 1 || y < 1 || x >= N - 1 || y >= N - 1) continue;
        const i = y * N + x;
        if (tiles[i] === T.WATER) continue;
        tiles[i] = T.RUIN;
      }
    }

    seedNodes(tiles, nodes, N, rng);
    const spawn = pickSpawn(tiles, nodes, N);

    return {
      N, tiles, nodes, spawn, lat, lon,
      biome: snowy ? "бореальний / сніжний" : arid ? "посушливий" : "помірний",
      urban, source: "procedural"
    };
  };

  function seedNodes(tiles, nodes, N, rng) {
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const i = y * N + x, t = tiles[i];
      if (nodes.has(i)) continue;
      if (t === T.FOREST && rng() < 0.6) nodes.set(i, { kind: "tree", amount: 16 + ((rng() * 12) | 0) });
      else if (t === T.ROCK && rng() < 0.45) nodes.set(i, { kind: "rock", amount: 22 + ((rng() * 16) | 0) });
      else if (t === T.GRASS && rng() < 0.045) nodes.set(i, { kind: "bush", amount: 5 + ((rng() * 4) | 0) });
      else if (t === T.RUIN && rng() < 0.5) nodes.set(i, { kind: "scrap", amount: 8 + ((rng() * 10) | 0) });
    }
  }

  // find a passable grass tile near centre with breathing room, clear it
  function pickSpawn(tiles, nodes, N) {
    const c = N >> 1;
    let best = null, bestD = Infinity;
    for (let y = 4; y < N - 4; y++) for (let x = 4; x < N - 4; x++) {
      const i = y * N + x;
      if (tiles[i] !== T.GRASS && tiles[i] !== T.SOIL) continue;
      const d = Math.abs(x - c) + Math.abs(y - c);
      if (d < bestD) { bestD = d; best = { x, y }; }
    }
    best = best || { x: c, y: c };
    // clear a small home clearing
    for (let yy = -2; yy <= 2; yy++) for (let xx = -2; xx <= 2; xx++) {
      const x = best.x + xx, y = best.y + yy;
      if (x < 0 || y < 0 || x >= N || y >= N) continue;
      const i = y * N + x;
      if (tiles[i] === T.WATER || tiles[i] === T.ROCK) tiles[i] = T.GRASS;
      nodes.delete(i);
    }
    return best;
  }

  // ---------------- real OSM via Overpass ----------------
  const ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter"
  ];

  RW.fetchOSM = async function (lat, lon, radiusM) {
    radiusM = radiusM || 380;
    const dLat = radiusM / 111320;
    const dLon = radiusM / (111320 * Math.cos(lat * Math.PI / 180));
    const s = lat - dLat, n = lat + dLat, w = lon - dLon, e = lon + dLon;
    const bbox = `${s},${w},${n},${e}`;
    const q =
      `[out:json][timeout:18];(` +
      `way["highway"](${bbox});` +
      `way["natural"="water"](${bbox});` +
      `way["waterway"](${bbox});` +
      `way["natural"="wood"](${bbox});` +
      `way["landuse"="forest"](${bbox});` +
      `way["landuse"="grass"](${bbox});` +
      `way["building"](${bbox});` +
      `);out geom 1800;`;

    for (const url of ENDPOINTS) {
      try {
        const ctrl = new AbortController();
        const to = setTimeout(() => ctrl.abort(), 11000);
        const r = await fetch(url, { method: "POST", body: "data=" + encodeURIComponent(q), signal: ctrl.signal });
        clearTimeout(to);
        if (!r.ok) continue;
        const j = await r.json();
        if (j && j.elements && j.elements.length) return { elements: j.elements, bbox: { s, n, w, e } };
      } catch (err) { /* try next endpoint */ }
    }
    return null;
  };

  function classify(tags) {
    if (!tags) return null;
    if (tags.building) return "building";
    if (tags.highway) return "road";
    if (tags.waterway) return "water";
    if (tags.natural === "water") return "water";
    if (tags.natural === "wood" || tags.landuse === "forest") return "forest";
    if (tags.landuse === "grass") return "grass";
    return null;
  }

  // rasterise OSM ways onto an existing procedural map (mutates in place)
  RW.overlayOSM = function (map, osm) {
    const { N, tiles, nodes } = map;
    // node seeding over fixed OSM geometry is reproducible: same coords + same osm -> same nodes
    const orng = RW.mulberry32(RW.hashSeed(map.lat || 0, map.lon || 0) ^ 0x05A1);
    const { s, n, w, e } = osm.bbox;
    const toCell = (la, lo) => ({
      x: RW.clamp(Math.round((lo - w) / (e - w) * (N - 1)), 0, N - 1),
      y: RW.clamp(Math.round((n - la) / (n - s) * (N - 1)), 0, N - 1)
    });
    const set = (x, y, t, makeNode) => {
      if (x < 0 || y < 0 || x >= N || y >= N) return;
      const i = y * N + x; tiles[i] = t;
      if (t === T.WATER || t === T.ROAD) nodes.delete(i);
      if (makeNode) makeNode(i, x, y);
    };
    const line = (a, b, t) => {            // Bresenham
      let x0 = a.x, y0 = a.y, x1 = b.x, y1 = b.y;
      const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0);
      const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
      let err = dx + dy;
      for (; ;) {
        set(x0, y0, t);
        if (x0 === x1 && y0 === y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
      }
    };
    const fillPoly = (geom, t, makeNode) => {
      let minX = N, minY = N, maxX = 0, maxY = 0;
      const pts = geom.map(g => toCell(g.lat, g.lon));
      for (const p of pts) { minX = Math.min(minX, p.x); minY = Math.min(minY, p.y); maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y); }
      if ((maxX - minX) * (maxY - minY) > N * N * 0.7) { // too big -> outline only
        for (let k = 0; k < geom.length - 1; k++) line(pts[k], pts[k + 1], t);
        return;
      }
      const lons = geom.map(g => g.lon), lats = geom.map(g => g.lat);
      const cellLon = (x) => w + (x + 0.5) / N * (e - w);
      const cellLat = (y) => n - (y + 0.5) / N * (n - s);
      for (let y = minY; y <= maxY; y++) for (let x = minX; x <= maxX; x++) {
        if (pointIn(cellLon(x), cellLat(y), lons, lats)) set(x, y, t, makeNode);
      }
      for (let k = 0; k < geom.length - 1; k++) line(pts[k], pts[k + 1], t); // crisp edge
    };

    let stats = { road: 0, water: 0, forest: 0, building: 0 };
    for (const el of osm.elements) {
      if (el.type !== "way" || !el.geometry || el.geometry.length < 2) continue;
      const kind = classify(el.tags);
      if (!kind) continue;
      const pts = el.geometry;
      const closed = pts.length > 3 &&
        Math.abs(pts[0].lat - pts[pts.length - 1].lat) < 1e-7 &&
        Math.abs(pts[0].lon - pts[pts.length - 1].lon) < 1e-7;

      if (kind === "road") {
        for (let k = 0; k < pts.length - 1; k++) line(toCell(pts[k].lat, pts[k].lon), toCell(pts[k + 1].lat, pts[k + 1].lon), T.ROAD);
        stats.road++;
      } else if (kind === "water") {
        if (closed) fillPoly(pts, T.WATER);
        else for (let k = 0; k < pts.length - 1; k++) line(toCell(pts[k].lat, pts[k].lon), toCell(pts[k + 1].lat, pts[k + 1].lon), T.WATER);
        stats.water++;
      } else if (kind === "forest") {
        fillPoly(pts, T.FOREST, (i) => { if (!nodes.has(i) && orng() < 0.5) nodes.set(i, { kind: "tree", amount: 16 + ((orng() * 12) | 0) }); });
        stats.forest++;
      } else if (kind === "grass") {
        fillPoly(pts, T.GRASS);
      } else if (kind === "building") {
        fillPoly(pts, T.RUIN, (i) => { if (!nodes.has(i) && orng() < 0.4) nodes.set(i, { kind: "scrap", amount: 8 + ((orng() * 10) | 0) }); });
        stats.building++;
      }
    }

    map.spawn = pickSpawn(tiles, nodes, N);
    map.source = "osm";
    map.osmStats = stats;
    return map;
  };

  function pointIn(px, py, xs, ys) {
    let inside = false;
    for (let i = 0, j = xs.length - 1; i < xs.length; j = i++) {
      const xi = xs[i], yi = ys[i], xj = xs[j], yj = ys[j];
      if (((yi > py) !== (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) inside = !inside;
    }
    return inside;
  }

})(window.RW);

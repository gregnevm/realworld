/* RealWorld — util.js : namespace, deterministic RNG, math, A* pathfinding */
window.RW = window.RW || {};
(function (RW) {
  "use strict";

  // ---- deterministic RNG (mulberry32) so a lat/lon always yields the same map ----
  RW.hashSeed = function (lat, lon) {
    // fold coordinates into a 32-bit seed
    let h = 2166136261 >>> 0;
    const s = lat.toFixed(4) + "," + lon.toFixed(4);
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  };
  RW.mulberry32 = function (a) {
    const f = function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    // the whole PRNG state is the single 32-bit accumulator — expose it so the game
    // rng can round-trip through save/load and a run stays reproducible after restore
    f.getState = () => a;
    f.setState = (s) => { a = s | 0; };
    return f;
  };

  // value-noise from a seeded rng grid (smooth-ish), used for biome blobs
  RW.makeNoise = function (rng, size) {
    const g = new Float32Array(size * size);
    for (let i = 0; i < g.length; i++) g[i] = rng();
    return function (x, y) {
      // bilinear sample with wrap
      const xi = Math.floor(x), yi = Math.floor(y);
      const xf = x - xi, yf = y - yi;
      const at = (a, b) => g[((b % size + size) % size) * size + ((a % size + size) % size)];
      const a = at(xi, yi), b = at(xi + 1, yi), c = at(xi, yi + 1), d = at(xi + 1, yi + 1);
      const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
      return a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v;
    };
  };

  RW.clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  RW.lerp = (a, b, t) => a + (b - a) * t;
  RW.dist = (ax, ay, bx, by) => Math.hypot(ax - bx, ay - by);

  // great-circle distance in km between two lat/lon
  RW.haversineKm = function (la1, lo1, la2, lo2) {
    const R = 6371, d2r = Math.PI / 180;
    const dLa = (la2 - la1) * d2r, dLo = (lo2 - lo1) * d2r;
    const a = Math.sin(dLa / 2) ** 2 +
      Math.cos(la1 * d2r) * Math.cos(la2 * d2r) * Math.sin(dLo / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
  };

  // ---- A* on the tile grid; isBlocked(i) -> true if impassable.
  // Best-effort: if the target is unreachable, returns a partial path to the
  // closest reachable cell (so click-to-move walks as far as it can). Returns
  // null only when the start itself cannot move at all (fully enclosed). ----
  RW.findPath = function (N, sx, sy, tx, ty, isBlocked) {
    sx |= 0; sy |= 0; tx |= 0; ty |= 0;
    if (sx === tx && sy === ty) return [];
    if (tx < 0 || ty < 0 || tx >= N || ty >= N) return null;
    // if target blocked, aim for nearest free neighbour of target
    const idx = (x, y) => y * N + x;
    const open = [];                       // simple binary heap
    const came = new Int32Array(N * N).fill(-1);
    const g = new Float32Array(N * N).fill(Infinity);
    const inOpen = new Uint8Array(N * N);
    const h = (x, y) => Math.abs(x - tx) + Math.abs(y - ty);
    const push = (i, f) => { open.push({ i, f }); let c = open.length - 1; while (c > 0) { const p = (c - 1) >> 1; if (open[p].f <= open[c].f) break; [open[p], open[c]] = [open[c], open[p]]; c = p; } };
    const pop = () => { const top = open[0], last = open.pop(); if (open.length) { open[0] = last; let c = 0; for (; ;) { let l = 2 * c + 1, r = l + 1, m = c; if (l < open.length && open[l].f < open[m].f) m = l; if (r < open.length && open[r].f < open[m].f) m = r; if (m === c) break;[open[m], open[c]] = [open[c], open[m]]; c = m; } } return top; };
    const start = idx(sx, sy); g[start] = 0; push(start, h(sx, sy)); inOpen[start] = 1;
    const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    let guard = 0, best = start, bestH = h(sx, sy);
    while (open.length && guard++ < 20000) {
      const cur = pop().i; inOpen[cur] = 0;
      const cx = cur % N, cy = (cur / N) | 0;
      const ch = h(cx, cy);
      if (ch < bestH) { bestH = ch; best = cur; }
      if (cx === tx && cy === ty) { best = cur; break; }
      for (const [dx, dy] of dirs) {
        const nx = cx + dx, ny = cy + dy;
        if (nx < 0 || ny < 0 || nx >= N || ny >= N) continue;
        const ni = idx(nx, ny);
        if (isBlocked(ni) && !(nx === tx && ny === ty)) continue;
        const ng = g[cur] + 1;
        if (ng < g[ni]) { came[ni] = cur; g[ni] = ng; const f = ng + h(nx, ny); if (!inOpen[ni]) { push(ni, f); inOpen[ni] = 1; } }
      }
    }
    // reconstruct toward best reachable node
    const path = [];
    let cur = best;
    if (g[best] === Infinity) return null;
    while (cur !== start && cur !== -1) { path.push({ x: cur % N, y: (cur / N) | 0 }); cur = came[cur]; }
    path.reverse();
    return path.length ? path : null;
  };

  RW.fmtTime = function (frac) { // frac 0..1 of a day -> HH:MM
    const mins = Math.floor(frac * 24 * 60);
    const hh = String(Math.floor(mins / 60)).padStart(2, "0");
    const mm = String(mins % 60).padStart(2, "0");
    return hh + ":" + mm;
  };

})(window.RW);

/* RealWorld — game.js : state, simulation, combat, raids, loop, persistence */
(function (RW) {
  "use strict";
  const idx = (G, x, y) => y * G.map.N + x;
  const inB = (G, x, y) => x >= 0 && y >= 0 && x < G.map.N && y < G.map.N;
  // where the landing crate sits: one tile east of spawn, or south if that neighbour is blocked
  function landingSpot(G, sp) {
    let lx = sp.x + 1, ly = sp.y;
    if (!RW.buildValid(G, lx, ly)) { lx = sp.x; ly = sp.y + 1; }
    return { x: lx, y: ly };
  }

  // ---------- small state helpers ----------
  RW.carryTotal = (p) => { let s = 0; for (const k in p.carry) s += p.carry[k]; return s; };
  RW.stockTotal = (G) => { let s = 0; for (const k in G.base.stock) s += Math.floor(G.base.stock[k]); return s; };
  RW.storageCap = (G) => {
    let c = 200;
    G.buildings.forEach(b => { if (RW.BUILDINGS[b.kind].capacity) c += RW.BUILDINGS[b.kind].capacity; });
    return c;
  };
  RW.deposit = function (G, res, amt) {
    const cap = RW.storageCap(G), cur = RW.stockTotal(G);
    const room = Math.max(0, cap - cur);
    const add = Math.min(amt, room);
    G.base.stock[res] = (G.base.stock[res] || 0) + add;
    if (add < amt) RW.log(G, "⚠ Склад переповнений — частину втрачено.", "warn");
    return add;
  };
  RW.baseCenter = function (G) {
    const st = G.buildings.find(b => b.kind === "storage");
    return st ? { x: st.x, y: st.y } : { x: Math.floor(G.player.px), y: Math.floor(G.player.py) };
  };
  RW.isBlocked = function (G, i) {
    if (RW.isTerrainBlocked(G.map.tiles[i])) return true;
    const b = G.bgrid.get(i);
    return !!(b && RW.BUILDINGS[b.kind].blocks);
  };

  // ---------- building ----------
  function placeBuilding(G, kind, x, y, hp) {
    const def = RW.BUILDINGS[kind];
    const b = { kind, x, y, hp: hp != null ? hp : def.hp, cool: 0, aim: 0 };
    G.buildings.push(b); G.bgrid.set(idx(G, x, y), b);
    return b;
  }
  RW.buildValid = function (G, x, y) {
    if (!inB(G, x, y)) return false;
    const t = G.map.tiles[idx(G, x, y)];
    if (t === RW.T.WATER || t === RW.T.ROCK) return false;
    if (G.bgrid.has(idx(G, x, y))) return false;
    if (G.map.nodes.has(idx(G, x, y))) return false;
    return true;
  };
  RW.tryBuild = function (G, x, y) {
    const def = RW.BUILDINGS[G.selectedBuild];
    if (!RW.buildValid(G, x, y)) { RW.flash(G, "Тут не можна будувати."); return; }
    if (!RW.canAfford(G.base.stock, def.cost)) { RW.flash(G, "Бракує ресурсів: " + RW.costStr(def.cost)); return; }
    RW.payCost(G.base.stock, def.cost);
    placeBuilding(G, G.selectedBuild, x, y);
    RW.syncBuildBar(G);
  };
  RW.cancelBuild = function (G) { G.selectedBuild = null; RW.syncBuildBar(G); RW.setTicker(G, ""); };
  RW.flash = function (G, msg) { RW.setTicker(G, "⚠ " + msg); clearTimeout(RW._ft); RW._ft = setTimeout(() => RW.setTicker(G, ""), 2200); };

  function removeBuilding(G, b) {
    const i = G.buildings.indexOf(b); if (i >= 0) G.buildings.splice(i, 1);
    G.bgrid.delete(idx(G, b.x, b.y));
  }

  // ---------- orders ----------
  RW.orderMove = function (G, x, y) {
    G.player.sleeping = false;
    const path = RW.findPath(G.map.N, Math.floor(G.player.px), Math.floor(G.player.py), x, y, i => RW.isBlocked(G, i));
    if (!path) { RW.flash(G, "Туди не дійти."); return; }
    G.player.action = { type: "move", path, cell: inB(G, x, y) ? idx(G, x, y) : null };
  };
  RW.orderGather = function (G, x, y) {
    G.player.sleeping = false;
    const node = G.map.nodes.get(idx(G, x, y));
    if (!node) return;
    const path = RW.findPath(G.map.N, Math.floor(G.player.px), Math.floor(G.player.py), x, y, i => RW.isBlocked(G, i));
    G.player.action = { type: "gather", nx: x, ny: y, cell: idx(G, x, y), path: path || [], t: 0, dur: 0 };
  };
  RW.orderAttack = function (G, e) {
    G.player.sleeping = false;
    G.player.action = { type: "attack", target: e, path: null, repathCd: 0, cell: null };
  };

  // ---------- new game / begin ----------
  RW.newGame = function (map, bare) {
    const sp = map.spawn;
    const G = {
      map, tile: 26, view: { w: innerWidth, h: innerHeight, dpr: 1 }, ctx: null,
      player: {
        px: sp.x + 0.5, py: sp.y + 0.5, face: 0, hp: 100, hunger: 82, rest: 92,
        carry: {}, carryCap: 30, action: null, sleeping: false, eatCd: 0, atkCd: 0,
        skills: { gather: 0, combat: 0 }
      },
      base: { stock: { wood: 50, stone: 30, food: 18, scrap: 16, planks: 0, components: 2 } },
      buildings: [], bgrid: new Map(), enemies: [], shots: [],
      time: { frac: 0.28, day: 1, dayLen: 150 },
      raid: { timer: 0, next: 95, active: false, warned: false, wave: 0 },
      convoys: [], regions: [], convoySeq: 0,
      selectedBuild: null, hover: null, speed: 1, speedIdx: 0,
      craftTimer: 0, saveTimer: 0, log: []
    };
    if (!bare) {
      // landing crate beside the player, plus the player starts with a clearing
      const ls = landingSpot(G, sp);
      placeBuilding(G, "storage", ls.x, ls.y);
    }
    return G;
  };

  RW.beginGame = function (G, restored) {
    RW.G = G;
    RW.initRegions(G);
    RW.showGameUI();
    RW.buildBuildBar(G);
    RW.initButtons(G);
    const cv = document.getElementById("cv");
    RW.resize(G);
    RW.initInput(G, cv);
    if (!restored) {
      RW.log(G, `Висадка: ${G.map.placeName} (${G.map.lat.toFixed(3)}, ${G.map.lon.toFixed(3)}) · біом: ${G.map.biome}.`, "good");
      RW.setTicker(G, "Клікай по 🌲/🪨/🫐, неси ресурс на 📦, будуй базу знизу. Періодично — рейди. 🗺 — логістика.");
      setTimeout(() => { if (RW.G === G) RW.setTicker(G, ""); }, 11000);
    } else {
      RW.log(G, "Збереження завантажено.", "good");
    }
    if (!G._loopStarted) { G._loopStarted = true; RW.startLoop(G); }
  };

  RW.afterMapChange = function (G) {
    // OSM overlay moved spawn / terrain: relocate player + landing crate to the new clearing
    const sp = G.map.spawn;
    G.player.px = sp.x + 0.5; G.player.py = sp.y + 0.5; G.player.action = null;
    const crate = G.buildings.find(b => b.kind === "storage");
    if (crate) {
      G.bgrid.delete(idx(G, crate.x, crate.y));
      const ls = landingSpot(G, sp);
      crate.x = ls.x; crate.y = ls.y; G.bgrid.set(idx(G, ls.x, ls.y), crate);
    }
  };

  RW.resize = function (G) {
    const cv = document.getElementById("cv");
    const dpr = window.devicePixelRatio || 1, w = window.innerWidth, h = window.innerHeight;
    cv.width = Math.floor(w * dpr); cv.height = Math.floor(h * dpr);
    const ctx = cv.getContext("2d"); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    G.view = { w, h, dpr }; G.ctx = ctx;
  };
  window.addEventListener("resize", () => { if (RW.G && RW.G.ctx) RW.resize(RW.G); });

  // ---------- start screen entry ----------
  RW.startGame = function (lat, lon, name, useOsm) {
    RW.setSpawnStatus("Генерую карту з координат…");
    const map = RW.generateMap(lat, lon, 56);
    map.placeName = name;
    const G = RW.newGame(map);
    RW.beginGame(G);
    if (useOsm) {
      RW.setTicker(G, "🌐 Тягну справжню географію з OpenStreetMap…");
      RW.fetchOSM(lat, lon, 380).then(osm => {
        if (!RW.G || RW.G !== G) return;
        if (osm) {
          RW.overlayOSM(map, osm);
          RW.afterMapChange(G);
          const s = map.osmStats || {};
          RW.log(G, `🌐 Реальна географія OSM: доріг ${s.road || 0}, водойм ${s.water || 0}, лісів ${s.forest || 0}, будівель ${s.building || 0}.`, "good");
        } else {
          RW.log(G, "🌐 OSM недоступний — карту згенеровано процедурно з координат (повністю детермінована).", "warn");
        }
        RW.setTicker(G, "");
      }).catch(() => RW.setTicker(G, ""));
    }
  };

  // ---------- main loop ----------
  RW.startLoop = function (G) {
    let last = performance.now();
    function frame(now) {
      let dt = (now - last) / 1000; last = now;
      if (dt > 0.1) dt = 0.1;
      const sdt = dt * (G.speed || 0);
      if (sdt > 0) RW.update(G, sdt);
      if (G.ctx) RW.render(G.ctx, G);
      RW.refreshHUD(G);
      if (G.worldOpen) { RW.drawWorldMap(G); RW.renderConvoyList(G); }
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  };

  // ---------- simulation ----------
  RW.update = function (G, dt) {
    // time of day
    G.time.frac += dt / G.time.dayLen;
    while (G.time.frac >= 1) { G.time.frac -= 1; G.time.day++; RW.log(G, "🌅 Новий день: " + G.time.day, ""); }

    updatePlayer(G, dt);
    updateCrafting(G, dt);
    updateRaids(G, dt);
    updateEnemies(G, dt);
    updateTurrets(G, dt);
    RW.updateConvoys(G, dt);

    // shots decay
    for (let i = G.shots.length - 1; i >= 0; i--) { G.shots[i].t -= dt; if (G.shots[i].t <= 0) G.shots.splice(i, 1); }

    // autosave
    G.saveTimer -= dt;
    if (G.saveTimer <= 0) { G.saveTimer = 12; RW.saveGame(G); }
  };

  function stepTo(o, tx, ty, step) {
    const dx = tx - o.px, dy = ty - o.py, d = Math.hypot(dx, dy);
    if (d <= step || d < 1e-6) { o.px = tx; o.py = ty; return true; }
    o.px += dx / d * step; o.py += dy / d * step; o.face = Math.atan2(dy, dx);
    return false;
  }
  function followPath(o, path, step) {
    if (!path || !path.length) return true;
    const n = path[0];
    if (stepTo(o, n.x + 0.5, n.y + 0.5, step)) path.shift();
    return path.length === 0;
  }

  function updatePlayer(G, dt) {
    const p = G.player;
    p.atkCd = Math.max(0, p.atkCd - dt);
    p.eatCd = Math.max(0, p.eatCd - dt);
    p.depCd = Math.max(0, (p.depCd || 0) - dt);

    // needs
    p.hunger = RW.clamp(p.hunger - 0.42 * dt, 0, 100);
    p.rest = RW.clamp(p.rest - (p.sleeping ? -14 : 0.30) * dt, 0, 100);
    if (p.hunger <= 0) p.hp -= 2.0 * dt;
    if (p.rest <= 0) p.hp -= 1.0 * dt;
    if (p.hunger > 45 && p.rest > 25 && p.hp < 100) p.hp = Math.min(100, p.hp + 0.7 * dt);
    p.hp = RW.clamp(p.hp, 0, 100);
    if (p.hp <= 0 && !G._dead) { onDeath(G); return; }

    // auto eat near storage
    if (p.hunger < 55 && p.eatCd <= 0 && (G.base.stock.food || 0) >= 1 && nearStorage(G, 2.2)) {
      G.base.stock.food -= 1; p.hunger = Math.min(100, p.hunger + 38); p.eatCd = 2.5;
    }
    // auto deposit carried goods near storage
    if (RW.carryTotal(p) > 0 && p.depCd <= 0 && nearStorage(G, 1.8)) {
      for (const k in p.carry) { if (p.carry[k] > 0) { const a = RW.deposit(G, k, p.carry[k]); p.carry[k] -= a; } }
      p.depCd = 0.4;
    }

    // WASD direct control overrides orders
    let mx = (G.keys.d ? 1 : 0) - (G.keys.a ? 1 : 0);
    let my = (G.keys.s ? 1 : 0) - (G.keys.w ? 1 : 0);
    if (mx || my) {
      p.action = null; p.sleeping = false;
      const len = Math.hypot(mx, my) || 1, spd = 3.4 * dt;
      const nx = p.px + mx / len * spd, ny = p.py + my / len * spd;
      if (!RW.isBlocked(G, idx(G, Math.floor(nx), Math.floor(p.py)))) p.px = nx;
      if (!RW.isBlocked(G, idx(G, Math.floor(p.px), Math.floor(ny)))) p.py = ny;
      p.face = Math.atan2(my, mx);
      return;
    }

    // retaliate if enemy adjacent and idle
    if (!p.action) {
      const e = nearestEnemy(G, p.px, p.py, 1.4);
      if (e) p.action = { type: "attack", target: e, path: null, repathCd: 0 };
    }

    const a = p.action;
    if (!a) { maybeSleep(G, dt); return; }
    const step = 3.4 * dt;

    if (a.type === "move") {
      if (followPath(p, a.path, step)) p.action = null;
    } else if (a.type === "gather") {
      const node = G.map.nodes.get(a.cell);
      if (!node) { p.action = null; return; }
      if (RW.dist(p.px, p.py, a.nx + 0.5, a.ny + 0.5) >= 1.4) {
        const done = followPath(p, a.path, step);
        p.face = Math.atan2(a.ny + 0.5 - p.py, a.nx + 0.5 - p.px);
        if (done && !RW.isTerrainBlocked(G.map.tiles[a.cell])) stepTo(p, a.nx + 0.5, a.ny + 0.5, step);
        return;
      }
      // gather
      const info = RW.NODEINFO[node.kind];
      a.dur = info.time / (1 + p.skills.gather * 0.04);
      a.t += dt;
      if (a.t >= a.dur) {
        a.t = 0;
        if (RW.carryTotal(p) >= p.carryCap) { RW.flash(G, "Несеш максимум — віднеси на склад 📦."); p.action = null; return; }
        p.carry[info.res] = (p.carry[info.res] || 0) + 1;
        node.amount -= 1;
        p.skills.gather = Math.min(20, p.skills.gather + 0.2);
        if (node.amount <= 0) { G.map.nodes.delete(a.cell); p.action = null; }
      }
    } else if (a.type === "attack") {
      const e = a.target;
      if (!e || e.dead || G.enemies.indexOf(e) < 0) {
        const nxt = nearestEnemy(G, p.px, p.py, 2.5);
        if (nxt) a.target = nxt; else { p.action = null; return; }
      }
      const tgt = a.target;
      const d = RW.dist(p.px, p.py, tgt.px, tgt.py);
      if (d > 1.25) {
        a.repathCd -= dt;
        if (!a.path || a.repathCd <= 0) { a.path = RW.findPath(G.map.N, Math.floor(p.px), Math.floor(p.py), Math.floor(tgt.px), Math.floor(tgt.py), i => RW.isBlocked(G, i)) || []; a.repathCd = 0.4; }
        followPath(p, a.path, step);
        p.face = Math.atan2(tgt.py - p.py, tgt.px - p.px);
      } else {
        p.face = Math.atan2(tgt.py - p.py, tgt.px - p.px);
        if (p.atkCd <= 0) {
          damageEnemy(G, tgt, 12 + p.skills.combat);
          p.atkCd = 0.7; p.skills.combat = Math.min(20, p.skills.combat + 0.15);
        }
      }
    }
  }

  function maybeSleep(G, dt) {
    const p = G.player;
    if (p.rest >= 99) { p.sleeping = false; return; }
    const bed = G.buildings.find(b => b.kind === "bed" && RW.dist(p.px, p.py, b.x + 0.5, b.y + 0.5) < 1.6);
    const danger = nearestEnemy(G, p.px, p.py, 9);
    if (bed && !danger) { p.sleeping = true; }
    else p.sleeping = false;
  }
  function nearStorage(G, r) {
    const p = G.player;
    return G.buildings.some(b => b.kind === "storage" && RW.dist(p.px, p.py, b.x + 0.5, b.y + 0.5) < r);
  }
  function nearestEnemy(G, x, y, maxR) {
    let best = null, bd = maxR;
    for (const e of G.enemies) { const d = RW.dist(x, y, e.px, e.py); if (d < bd) { bd = d; best = e; } }
    return best;
  }

  function updateCrafting(G, dt) {
    const benches = G.buildings.filter(b => b.kind === "workbench");
    if (!benches.length) return;
    G.craftTimer += dt * benches.length;
    while (G.craftTimer >= 3.5) {
      G.craftTimer -= 3.5;
      if ((G.base.stock.wood || 0) >= 2 && RW.stockTotal(G) < RW.storageCap(G)) {
        G.base.stock.wood -= 2; G.base.stock.planks = (G.base.stock.planks || 0) + 1;
      }
    }
  }

  // ---------- raids ----------
  function updateRaids(G, dt) {
    const r = G.raid;
    if (r.active) {
      if (G.enemies.length === 0) {
        r.active = false; r.warned = false;
        r.next = 78 + Math.random() * 46;
        r.timer = 0;
        RW.raidBanner("");
        RW.log(G, "✅ Рейд відбито! Готуйся до наступного.", "good");
      }
      return;
    }
    r.timer += dt;
    if (!r.warned && r.timer > r.next - 12) {
      r.warned = true;
      RW.raidBanner("⚠ НАБЛИЖАЄТЬСЯ РЕЙД");
      RW.log(G, "⚠ Розвідка фіксує рейдерів на підході — укріплюй базу!", "warn");
    }
    if (r.timer >= r.next) {
      spawnWave(G);
    }
  }
  function spawnWave(G) {
    const r = G.raid; r.active = true; r.wave++;
    const n = RW.raidWaveSize(G.time.day);
    const N = G.map.N, edge = Math.floor(Math.random() * 4);
    for (let i = 0; i < n; i++) {
      let x, y;
      const o = 1 + Math.floor(Math.random() * 3);
      if (edge === 0) { x = o; y = 2 + Math.floor(Math.random() * (N - 4)); }
      else if (edge === 1) { x = N - 1 - o; y = 2 + Math.floor(Math.random() * (N - 4)); }
      else if (edge === 2) { x = 2 + Math.floor(Math.random() * (N - 4)); y = o; }
      else { x = 2 + Math.floor(Math.random() * (N - 4)); y = N - 1 - o; }
      if (RW.isTerrainBlocked(G.map.tiles[idx(G, x, y)])) { i--; continue; }
      G.enemies.push(RW.makeRaider(x + 0.5, y + 0.5, G.time.day));
    }
    RW.raidBanner("⚔ РЕЙД! " + n + " рейдерів");
    RW.log(G, `⚔ Рейд #${r.wave}: ${n} рейдерів атакують базу!`, "bad");
  }

  function updateEnemies(G, dt) {
    const p = G.player, N = G.map.N;
    const center = RW.baseCenter(G);
    for (let k = G.enemies.length - 1; k >= 0; k--) {
      const e = G.enemies[k];
      e.atkCd = Math.max(0, e.atkCd - dt);
      e.hitFlash = Math.max(0, e.hitFlash - dt);
      const step = e.speed * dt;
      const dToP = RW.dist(e.px, e.py, p.px, p.py);

      // 1. attack player if adjacent
      if (dToP < 1.25) {
        e.face = Math.atan2(p.py - e.py, p.px - e.px);
        if (e.atkCd <= 0) { p.hp = RW.clamp(p.hp - e.dmg, 0, 100); e.atkCd = 1.1; if (p.hp <= 0 && !G._dead) onDeath(G); }
        continue;
      }
      // 2. attack a storage if adjacent (steal)
      const st = G.buildings.find(b => b.kind === "storage" && RW.dist(e.px, e.py, b.x + 0.5, b.y + 0.5) < 1.35);
      if (st) {
        if (e.atkCd <= 0) { damageBuilding(G, st, e.dmg, true); e.atkCd = 1.0; }
        continue;
      }
      // 3. march toward target (player if near, else base), smashing walls in the way
      const tx = dToP < 6 ? Math.floor(p.px) : center.x;
      const ty = dToP < 6 ? Math.floor(p.py) : center.y;
      e.pathCd -= dt;
      if (!e.path || e.pathCd <= 0 || e._tx !== tx || e._ty !== ty) {
        e._tx = tx; e._ty = ty; e.pathCd = 0.9 + Math.random() * 0.5;
        e.path = RW.findPath(N, Math.floor(e.px), Math.floor(e.py), tx, ty, i => RW.isTerrainBlocked(G.map.tiles[i])) || [];
      }
      if (e.path && e.path.length) {
        const nx = e.path[0];
        const b = G.bgrid.get(idx(G, nx.x, nx.y));
        if (b && RW.BUILDINGS[b.kind].blocks) {
          e.face = Math.atan2(nx.y + 0.5 - e.py, nx.x + 0.5 - e.px);
          if (e.atkCd <= 0) { damageBuilding(G, b, e.dmg); e.atkCd = 1.0; }
        } else {
          followPath(e, e.path, step);   // same step-then-shift rule the player uses
        }
      } else {
        stepTo(e, center.x + 0.5, center.y + 0.5, step);
      }
    }
  }

  function updateTurrets(G, dt) {
    G.buildings.forEach(b => {
      if (b.kind !== "turret") return;
      const def = RW.BUILDINGS.turret;
      b.cool = Math.max(0, b.cool - dt);
      const e = nearestEnemy(G, b.x + 0.5, b.y + 0.5, def.range);
      if (!e) return;
      b.aim = Math.atan2(e.py - (b.y + 0.5), e.px - (b.x + 0.5));
      if (b.cool <= 0) {
        b.cool = 0.5;
        damageEnemy(G, e, def.dps * 0.5);
        G.shots.push({ x1: b.x + 0.5, y1: b.y + 0.5, x2: e.px, y2: e.py, t: 0.12 });
      }
    });
  }

  function damageBuilding(G, b, amt, steal) {
    b.hp -= amt;
    if (steal && b.kind === "storage") {
      // raiders skim resources as they smash the crate
      const keys = RW.RES_ORDER.filter(k => (G.base.stock[k] || 0) > 0);
      if (keys.length) { const k = keys[Math.floor(Math.random() * keys.length)]; const lost = Math.min(G.base.stock[k], 1 + Math.floor(Math.random() * 2)); G.base.stock[k] -= lost; }
    }
    if (b.hp <= 0) {
      removeBuilding(G, b);
      RW.log(G, `💥 ${RW.BUILDINGS[b.kind].name} зруйновано рейдерами.`, "bad");
    }
  }
  function damageEnemy(G, e, amt) {
    e.hp -= amt; e.hitFlash = 0.12;
    if (e.hp <= 0 && !e.dead) {
      e.dead = true;
      const i = G.enemies.indexOf(e); if (i >= 0) G.enemies.splice(i, 1);
      RW.deposit(G, "scrap", 2 + Math.floor(Math.random() * 2));
      if (Math.random() < 0.25) RW.deposit(G, "components", 1);
      if (Math.random() < 0.4) RW.deposit(G, "food", 1);
    }
  }

  function onDeath(G) {
    G._dead = true; G.speed = 0;
    RW.raidBanner("");
    RW.log(G, "☠ Твій персонаж загинув. У повноцінній MMO це втрата спорядження та респ; тут — рестарт.", "bad");
    RW.setTicker(G, "☠ Кінець. Онови сторінку, щоб почати знову (або 'Продовжити' з останнього збереження).");
    setTimeout(() => { try { localStorage.removeItem("realworld_save"); } catch (e) { } }, 200);
  }

  // ---------- persistence ----------
  RW.hasSave = function () { try { return !!localStorage.getItem("realworld_save"); } catch (e) { return false; } };
  RW.saveGame = function (G) {
    if (G._dead) return;
    try {
      const s = {
        v: 1, lat: G.map.lat, lon: G.map.lon, name: G.map.placeName, N: G.map.N,
        biome: G.map.biome, source: G.map.source,
        tiles: Array.from(G.map.tiles), nodes: Array.from(G.map.nodes.entries()),
        spawn: G.map.spawn,
        buildings: G.buildings.map(b => ({ kind: b.kind, x: b.x, y: b.y, hp: b.hp })),
        player: { px: G.player.px, py: G.player.py, hp: G.player.hp, hunger: G.player.hunger, rest: G.player.rest, carry: G.player.carry, skills: G.player.skills, carryCap: G.player.carryCap, face: G.player.face },
        stock: G.base.stock, time: G.time, raid: G.raid,
        convoys: G.convoys, convoySeq: G.convoySeq, regions: G.regions
      };
      localStorage.setItem("realworld_save", JSON.stringify(s));
    } catch (e) { /* quota or serialization issue — ignore */ }
  };
  RW.loadGame = function () {
    let s; try { s = JSON.parse(localStorage.getItem("realworld_save")); } catch (e) { }
    if (!s) return;
    const map = {
      N: s.N, tiles: Uint8Array.from(s.tiles), nodes: new Map(s.nodes),
      lat: s.lat, lon: s.lon, placeName: s.name, biome: s.biome, source: s.source, spawn: s.spawn
    };
    const G = RW.newGame(map, true);   // bare: don't auto-place crate or defaults
    s.buildings.forEach(b => placeBuilding(G, b.kind, b.x, b.y, b.hp));
    Object.assign(G.player, s.player);
    G.base.stock = Object.assign({ wood: 0, stone: 0, food: 0, scrap: 0, planks: 0, components: 0 }, s.stock);
    G.time = s.time; G.raid = s.raid || G.raid;
    G.convoys = s.convoys || []; G.convoySeq = s.convoySeq || 0;
    G.regions = s.regions || [];
    RW.beginGame(G, true);
  };

  // ---------- bootstrap ----------
  window.addEventListener("DOMContentLoaded", () => { RW.initSpawnUI(); });

})(window.RW);

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
  // what a raider cannot walk through (and therefore smashes): walls AND doors
  RW.isEnemyBlocked = function (G, i) {
    if (RW.isTerrainBlocked(G.map.tiles[i])) return true;
    const b = G.bgrid.get(i);
    return !!(b && (RW.BUILDINGS[b.kind].blocks || RW.BUILDINGS[b.kind].blocksEnemies));
  };

  // ---------- floating combat/loot text (pure data; render.js draws it, never persisted) ----------
  RW.fxText = function (G, x, y, text, color) {
    if (!G.fx) return;
    G.fx.push({ x, y, text, color: color || "#fff", t: 0, dur: 1.1 });
    if (G.fx.length > 80) G.fx.splice(0, G.fx.length - 80);
  };

  // ---------- building ----------
  function placeBuilding(G, kind, x, y, hp) {
    const def = RW.BUILDINGS[kind];
    const b = { kind, x, y, hp: hp != null ? hp : def.hp, cool: 0, aim: 0 };
    G.buildings.push(b); G.bgrid.set(idx(G, x, y), b);
    G.mapDirty = true;
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
  // `quiet` = part of a drag-run: invalid cells are skipped silently, only the money message surfaces once
  RW.tryBuild = function (G, x, y, quiet) {
    const def = RW.BUILDINGS[G.selectedBuild];
    if (!def) return false;
    if (def.research && G.research && !G.research.gateOk(def.research)) {
      const planned = RW.planResearchPath(G.research, def.research);
      RW.flash(G, `🔒 ${def.name}: потрібне дослідження «${G.research.labelOf(def.research)}»` + (planned.length ? " — шлях заплановано" : ""));
      if (planned.length) RW.log(G, "🔬 У чергу досліджень: " + planned.map(id => G.research.labelOf(id)).join(" → "), "");
      return false;
    }
    if (!RW.buildValid(G, x, y)) { if (!quiet) RW.flash(G, "Тут не можна будувати."); return false; }
    if (!RW.canAfford(G.base.stock, def.cost)) {
      const miss = RW.missingFor(G.base.stock, def.cost).map(k => RW.RES[k].icon + RW.RES[k].label).join(", ");
      RW.flash(G, "Бракує: " + miss + " (треба " + RW.costStr(def.cost) + ")");
      return false;
    }
    RW.payCost(G.base.stock, def.cost);
    placeBuilding(G, G.selectedBuild, x, y);
    G.stats.built++;
    RW.syncBuildBar(G);
    return true;
  };
  // drag-to-build: an L-shaped run of cells from a to b (horizontal first), inclusive
  RW.lineCells = function (ax, ay, bx, by) {
    const out = [];
    const sx = bx >= ax ? 1 : -1, sy = by >= ay ? 1 : -1;
    for (let x = ax; x !== bx + sx; x += sx) out.push({ x, y: ay });
    for (let y = ay + sy; y !== by + sy; y += sy) out.push({ x: bx, y });
    return out;
  };
  RW.buildRun = function (G, cells) {
    let placed = 0;
    for (const c of cells) {
      if (!RW.canAfford(G.base.stock, RW.BUILDINGS[G.selectedBuild].cost)) break;
      if (RW.tryBuild(G, c.x, c.y, true)) placed++;
    }
    return placed;
  };
  RW.cancelBuild = function (G) { G.selectedBuild = null; G.drag = null; RW.syncBuildBar(G); RW.setTicker(G, ""); };

  // ---------- selection / demolish / repair ----------
  RW.selectAt = function (G, x, y) {
    const b = inB(G, x, y) ? G.bgrid.get(idx(G, x, y)) : null;
    G.selected = b || null;
    return G.selected;
  };
  RW.demolish = function (G, b) {
    if (!b || G.buildings.indexOf(b) < 0) return false;
    const def = RW.BUILDINGS[b.kind];
    const refund = RW.refundOf(def.cost);
    removeBuilding(G, b);
    for (const k in refund) RW.deposit(G, k, refund[k]);
    RW.fxText(G, b.x + 0.5, b.y + 0.5, "✕ " + def.name, "#ffcf5c");
    RW.log(G, `🔨 ${def.name} розібрано, повернуто ${RW.costStr(refund) || "нічого"}.`, "");
    RW.syncBuildBar(G);
    return true;
  };
  RW.repair = function (G, b) {
    if (!b || G.buildings.indexOf(b) < 0) return false;
    const def = RW.BUILDINGS[b.kind];
    if (b.hp >= def.hp) { RW.flash(G, def.name + " ціла."); return false; }
    if (RW.dist(G.player.px, G.player.py, b.x + 0.5, b.y + 0.5) > 2.6) { RW.flash(G, "Підійди ближче, щоб полагодити."); return false; }
    const cost = RW.repairCostOf(def, b.hp);
    if (!RW.canAfford(G.base.stock, cost)) { RW.flash(G, "На ремонт бракує: " + RW.costStr(cost)); return false; }
    RW.payCost(G.base.stock, cost);
    b.hp = def.hp;
    RW.fxText(G, b.x + 0.5, b.y + 0.5, "🔧 полагоджено", "#5fd38a");
    RW.syncBuildBar(G);
    return true;
  };

  // ---------- speed / pause (single setter so every HUD readout stays in sync) ----------
  RW.SPEEDS = [1, 2, 3];
  RW.setSpeed = function (G, s) {
    if (s > 0) G.lastSpeed = s;
    G.speed = s;
    if (RW.syncSpeedUI) RW.syncSpeedUI(G);
  };
  RW.togglePause = function (G) { RW.setSpeed(G, G.speed > 0 ? 0 : (G.lastSpeed || 1)); };
  RW.cycleSpeed = function (G) {
    const cur = RW.SPEEDS.indexOf(G.speed);
    RW.setSpeed(G, RW.SPEEDS[(cur + 1) % RW.SPEEDS.length]);
  };
  RW.flash = function (G, msg) { RW.setTicker(G, "⚠ " + msg, "warn"); clearTimeout(RW._ft); RW._ft = setTimeout(() => RW.setTicker(G, ""), 2200); };
  RW.flashOk = function (G, msg) { RW.setTicker(G, "✓ " + msg, "good"); clearTimeout(RW._ft); RW._ft = setTimeout(() => RW.setTicker(G, ""), 1800); };

  function removeBuilding(G, b) {
    const i = G.buildings.indexOf(b); if (i >= 0) G.buildings.splice(i, 1);
    G.bgrid.delete(idx(G, b.x, b.y));
    if (G.selected === b) G.selected = null;
    G.mapDirty = true;
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
      selectedBuild: null, hover: null, keys: {}, speed: 1, lastSpeed: 1, selected: null, drag: null,
      craftTimer: 0, growTimer: 0, saveTimer: 0, log: [], fx: [], mapDirty: true,
      stats: { gathered: 0, kills: 0, raids: 0, built: 0, convoys: 0, damage: 0 }
    };
    // research pipeline over the shared content catalog (same tree the Godot kernel walks)
    G.research = RW.newProgression ? RW.newProgression() : null;
    // seeded gameplay rng: raids/loot/ambushes are a pure function of the coordinates too
    // (XOR keeps this stream distinct from the worldgen stream that uses the raw hash)
    G.rng = RW.mulberry32(RW.hashSeed(map.lat || 0, map.lon || 0) ^ 0x5EED);
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
      if (G.researchOpen) RW.renderResearch(G);
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  };

  // ---------- simulation ----------
  RW.update = function (G, dt) {
    if (G._dead) return;   // the run is over: the world freezes behind the death screen
    // time of day
    G.time.frac += dt / G.time.dayLen;
    while (G.time.frac >= 1) { G.time.frac -= 1; G.time.day++; RW.log(G, "🌅 Новий день: " + G.time.day, ""); }

    updatePlayer(G, dt);
    updateCrafting(G, dt);
    updateResearch(G, dt);
    updateGrowZones(G, dt);
    updateRaids(G, dt);
    updateEnemies(G, dt);
    updateTurrets(G, dt);
    RW.updateConvoys(G, dt);

    // shots + floating text decay
    for (let i = G.shots.length - 1; i >= 0; i--) { G.shots[i].t -= dt; if (G.shots[i].t <= 0) G.shots.splice(i, 1); }
    if (G.fx) for (let i = G.fx.length - 1; i >= 0; i--) { G.fx[i].t += dt; if (G.fx[i].t >= G.fx[i].dur) G.fx.splice(i, 1); }
    if (G._hurtT > 0) G._hurtT = Math.max(0, G._hurtT - dt * 2.5);

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
    // one-shot need warnings (re-armed once the need recovers)
    if (p.hunger < 20 && !G._hungerWarn) { G._hungerWarn = true; RW.log(G, "🍖 Голод! Стань біля складу з їжею або збери ягоди 🫐.", "warn"); }
    else if (p.hunger > 40) G._hungerWarn = false;
    if (p.rest < 15 && !G._restWarn) { G._restWarn = true; RW.log(G, "💤 Виснаження! Постав ліжко 🛏 і стань поруч, щоб поспати.", "warn"); }
    else if (p.rest > 40) G._restWarn = false;

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
        G.stats.gathered++;
        RW.fxText(G, a.nx + 0.5, a.ny + 0.2, "+1 " + RW.RES[info.res].icon, "#e7edf3");
        p.skills.gather = Math.min(20, p.skills.gather + 0.2);
        if (node.amount <= 0) { G.map.nodes.delete(a.cell); G.mapDirty = true; p.action = null; }
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
    // the planks recipe is carpentry-gated in the content catalog (make_planks → research: carpentry)
    if (G.research && !G.research.gateOk("carpentry")) {
      if (!G._plankHint) { G._plankHint = true; RW.log(G, "🛠 Верстак простоює: дошки потребують дослідження «Столярство» (🔬).", "warn"); }
      return;
    }
    G.craftTimer += dt * benches.length;
    while (G.craftTimer >= 3.5) {
      G.craftTimer -= 3.5;
      if ((G.base.stock.wood || 0) >= 2 && RW.stockTotal(G) < RW.storageCap(G)) {
        G.base.stock.wood -= 2; G.base.stock.planks = (G.base.stock.planks || 0) + 1;
      }
    }
  }

  // ---------- research (spec 0007 pipeline, web slice) ----------
  const RESEARCH_RATE = 8;   // research-days one bench produces per game-day
  function updateResearch(G, dt) {
    if (!G.research) return;
    let benches = 0;
    G.buildings.forEach(b => { if (b.kind === "research_bench") benches++; });
    if (!benches) return;
    const done = G.research.addPoints(benches * RESEARCH_RATE * (dt / G.time.dayLen));
    for (const id of done) {
      const un = G.research.unlocksOf(id);
      const opens = un.buildings.length + un.recipes.length + un.items.length;
      RW.log(G, `🔬 Досліджено: ${G.research.labelOf(id)}` + (opens ? ` — відкрито нового: ${opens}` : ""), "good");
    }
    if (done.length && RW.buildBuildBar) RW.buildBuildBar(G);
  }

  // grow zones slowly farm food into the stockpile (agriculture unlock)
  function updateGrowZones(G, dt) {
    let zones = 0;
    G.buildings.forEach(b => { if (b.kind === "grow_zone") zones++; });
    if (!zones) return;
    G.growTimer = (G.growTimer || 0) + dt * zones;
    while (G.growTimer >= 25) {
      G.growTimer -= 25;
      if (RW.stockTotal(G) < RW.storageCap(G)) G.base.stock.food = (G.base.stock.food || 0) + 1;
    }
  }

  // ---------- raids ----------
  function updateRaids(G, dt) {
    const r = G.raid;
    if (r.active) {
      if (G.enemies.length === 0) {
        r.active = false; r.warned = false;
        r.next = 78 + G.rng() * 46;
        r.timer = 0;
        G.stats.raids++;
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
  // Cells a raider can walk to the base from (terrain only — raiders smash buildings). A wave that
  // spawns across a river would never arrive and the raid would never end, so spawn points are
  // drawn from this set: the map rim of the base's own landmass, falling back to the farthest
  // reachable cells when that landmass never touches the rim (island base).
  RW.raidSpawnCells = function (G) {
    const N = G.map.N, c = RW.baseCenter(G);
    const seen = new Uint8Array(N * N), dist = new Int32Array(N * N);
    const start = idx(G, RW.clamp(c.x, 0, N - 1), RW.clamp(c.y, 0, N - 1));
    const q = [start]; seen[start] = 1;
    const rim = [], all = [];
    for (let h = 0; h < q.length; h++) {
      const i = q[h], x = i % N, y = (i / N) | 0;
      if (i !== start) { all.push(i); if (x <= 1 || y <= 1 || x >= N - 2 || y >= N - 2) rim.push(i); }
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= N || ny >= N) continue;
        const ni = ny * N + nx;
        if (seen[ni] || RW.isTerrainBlocked(G.map.tiles[ni])) continue;
        seen[ni] = 1; dist[ni] = dist[i] + 1; q.push(ni);
      }
    }
    if (rim.length) return rim;
    all.sort((a, b) => dist[b] - dist[a]);
    return all.slice(0, Math.max(1, all.length >> 3));
  };
  function spawnWave(G) {
    const r = G.raid; r.active = true; r.wave++;
    const n = RW.raidWaveSize(G.time.day);
    const N = G.map.N;
    const cells = RW.raidSpawnCells(G);
    if (!cells.length) { r.active = false; return; }   // boxed-in base: nothing can come
    // one entry side per wave: pick an anchor, then cluster the pack around it
    const anchor = cells[Math.floor(G.rng() * cells.length)];
    const ax = anchor % N, ay = (anchor / N) | 0;
    const near = cells.filter(i => Math.abs(i % N - ax) + Math.abs(((i / N) | 0) - ay) <= 6);
    for (let i = 0; i < n; i++) {
      const cell = near[Math.floor(G.rng() * near.length)];
      const e = RW.makeRaider(cell % N + 0.5, ((cell / N) | 0) + 0.5, G.time.day);
      e.delay = i * 1.5;   // the pack trickles in, so the fight is a sequence, not a pile-on
      G.enemies.push(e);
    }
    RW.raidBanner("⚔ РЕЙД! " + n + " рейдерів");
    RW.log(G, `⚔ Рейд #${r.wave}: ${n} рейдерів атакують базу!`, "bad");
  }

  function updateEnemies(G, dt) {
    const p = G.player, N = G.map.N;
    const center = RW.baseCenter(G);
    for (let k = G.enemies.length - 1; k >= 0; k--) {
      const e = G.enemies[k];
      if (e.delay > 0) { e.delay -= dt; continue; }   // still marching in from beyond the map edge
      e.atkCd = Math.max(0, e.atkCd - dt);
      e.hitFlash = Math.max(0, e.hitFlash - dt);
      const step = e.speed * dt;
      const dToP = RW.dist(e.px, e.py, p.px, p.py);
      // a raider that is neither moving nor fighting for a long while is cut off (terrain changed
      // under it, or a path the planner cannot find) — it gives up rather than pinning the raid open
      if (e._lx === e.px && e._ly === e.py && e.atkCd <= 0) {
        e.stuck = (e.stuck || 0) + dt;
        if (e.stuck > 25) { G.enemies.splice(k, 1); RW.log(G, "🏃 Рейдер не знайшов шляху і відступив.", ""); continue; }
      } else e.stuck = 0;
      e._lx = e.px; e._ly = e.py;

      // spike traps bite whoever stands on them (and wear out doing it)
      const tb = G.bgrid.get(idx(G, Math.floor(e.px), Math.floor(e.py)));
      if (tb && RW.BUILDINGS[tb.kind].trapDps) {
        damageEnemy(G, e, RW.BUILDINGS[tb.kind].trapDps * dt);
        tb.hp -= 6 * dt;
        if (tb.hp <= 0) { removeBuilding(G, tb); RW.log(G, "🪤 Пастка зносилась ущент.", ""); }
        if (e.dead) continue;
      }

      // 1. attack player if adjacent
      if (dToP < 1.25) {
        e.face = Math.atan2(p.py - e.py, p.px - e.px);
        if (e.atkCd <= 0) {
          p.hp = RW.clamp(p.hp - e.dmg, 0, 100); e.atkCd = 1.1; G.stats.damage += e.dmg; G._hurtT = 1;
          RW.fxText(G, p.px, p.py - 0.4, "-" + Math.round(e.dmg), "#ff6b6b");
          if (p.hp <= 0 && !G._dead) onDeath(G);
        }
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
        e._tx = tx; e._ty = ty; e.pathCd = 0.9 + G.rng() * 0.5;
        e.path = RW.findPath(N, Math.floor(e.px), Math.floor(e.py), tx, ty, i => RW.isTerrainBlocked(G.map.tiles[i])) || [];
      }
      if (e.path && e.path.length) {
        const nx = e.path[0];
        const b = G.bgrid.get(idx(G, nx.x, nx.y));
        if (b && (RW.BUILDINGS[b.kind].blocks || RW.BUILDINGS[b.kind].blocksEnemies)) {
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
      if (keys.length) {
        const k = keys[Math.floor(G.rng() * keys.length)]; const lost = Math.min(G.base.stock[k], 1 + Math.floor(G.rng() * 2));
        G.base.stock[k] -= lost;
        RW.fxText(G, b.x + 0.5, b.y + 0.1, "-" + lost + " " + RW.RES[k].icon, "#ff6b6b");
      }
    }
    if (b.hp <= 0) {
      removeBuilding(G, b);
      RW.log(G, `💥 ${RW.BUILDINGS[b.kind].name} зруйновано рейдерами.`, "bad");
    }
  }
  function damageEnemy(G, e, amt) {
    e.hp -= amt; e.hitFlash = 0.12;
    if (amt >= 1) RW.fxText(G, e.px, e.py - 0.5, "-" + Math.round(amt), "#ffd9a0");
    if (e.hp <= 0 && !e.dead) {
      e.dead = true;
      const i = G.enemies.indexOf(e); if (i >= 0) G.enemies.splice(i, 1);
      G.stats.kills++;
      const loot = [];
      const sc = 2 + Math.floor(G.rng() * 2); RW.deposit(G, "scrap", sc); loot.push(sc + RW.RES.scrap.icon);
      if (G.rng() < 0.25) { RW.deposit(G, "components", 1); loot.push("1" + RW.RES.components.icon); }
      if (G.rng() < 0.4) { RW.deposit(G, "food", 1); loot.push("1" + RW.RES.food.icon); }
      RW.fxText(G, e.px, e.py - 0.9, "☠ +" + loot.join(" "), "#5fd38a");
      if (G.raid.active) RW.raidBanner("⚔ РЕЙД! лишилось " + G.enemies.length);
    }
  }

  function onDeath(G) {
    G._dead = true; G.speed = 0;
    RW.raidBanner("");
    RW.log(G, "☠ Твій персонаж загинув. У повноцінній MMO це втрата спорядження та респ; тут — нова висадка.", "bad");
    RW.setTicker(G, "");
    try { localStorage.removeItem("realworld_save"); } catch (e) { }
    if (RW.showDeath) RW.showDeath(G);
  }
  // one line per stat for the death screen / pause menu
  RW.runSummary = function (G) {
    const s = G.stats || {}, r = G.research ? G.research.summary() : null;
    return [
      ["🕓 Прожито днів", G.time.day],
      ["⚔ Відбито рейдів", s.raids || 0],
      ["☠ Убито рейдерів", s.kills || 0],
      ["🪵 Зібрано ресурсів", s.gathered || 0],
      ["🏗 Збудовано", s.built || 0],
      ["🚚 Конвоїв", s.convoys || 0],
      ["🔬 Досліджено", r ? `${r.unlocked}/${r.total}` : "—"]
    ];
  };

  // ---------- persistence ----------
  RW.hasSave = function () { try { return !!localStorage.getItem("realworld_save"); } catch (e) { return false; } };
  // cheap peek for the spawn screen's "continue" button (name + day), null when there is no save
  RW.saveMeta = function () {
    try {
      const s = JSON.parse(localStorage.getItem("realworld_save"));
      return s ? { name: s.name || "Поселення", day: (s.time && s.time.day) || 1, lat: s.lat, lon: s.lon } : null;
    } catch (e) { return null; }
  };
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
        convoys: G.convoys, convoySeq: G.convoySeq, regions: G.regions,
        research: G.research ? G.research.toDict() : null,
        rngState: G.rng && G.rng.getState ? G.rng.getState() : null,
        stats: G.stats, tile: G.tile, lastSpeed: G.lastSpeed,
        log: (G.log || []).slice(-40)
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
    if (s.research && G.research) G.research.fromDict(s.research);
    if (s.stats) Object.assign(G.stats, s.stats);
    if (s.tile) G.tile = RW.clamp(s.tile, RW.ZOOM_MIN || 14, RW.ZOOM_MAX || 48);
    if (s.lastSpeed) G.lastSpeed = s.lastSpeed;
    if (s.log) G.log = s.log.slice();
    // resume the gameplay rng exactly where the save left it (old saves: fresh seed from coords)
    if (s.rngState != null && G.rng && G.rng.setState) G.rng.setState(s.rngState);
    RW.beginGame(G, true);
  };

  // ---------- bootstrap ----------
  window.addEventListener("DOMContentLoaded", () => { RW.initSpawnUI(); });
  // never lose the last seconds of play: flush the save when the tab goes away
  window.addEventListener("beforeunload", () => { if (RW.G) RW.saveGame(RW.G); });
  window.addEventListener("visibilitychange", () => { if (RW.G && document.hidden) RW.saveGame(RW.G); });

})(window.RW);

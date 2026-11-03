/* RealWorld — ui.js : DOM HUD, spawn screen, build bar, inspect/selection, minimap, modals, menus.
   Everything here is presentation: it reads G and calls RW.* sim verbs; the sim never reaches back
   into the DOM except through the tiny hook surface (log / setTicker / raidBanner / sync*). */
(function (RW) {
  "use strict";

  const PRESETS = [
    { name: "Київ", sub: "Україна", lat: 50.4501, lon: 30.5234 },
    { name: "Львів", sub: "Україна", lat: 49.8397, lon: 24.0297 },
    { name: "Манхеттен", sub: "Нью-Йорк", lat: 40.7549, lon: -73.9840 },
    { name: "Венеція", sub: "Італія", lat: 45.4380, lon: 12.3270 },
    { name: "Кіото", sub: "Японія", lat: 35.0116, lon: 135.7681 },
    { name: "Рейк'явік", sub: "Ісландія", lat: 64.1466, lon: -21.9426 }
  ];
  const MODALS = ["worldModal", "researchModal", "helpModal", "logModal", "menuModal", "deathModal"];

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

  // =====================================================================
  // spawn screen
  // =====================================================================
  RW.initSpawnUI = function () {
    const wrap = $("presets");
    PRESETS.forEach((p, i) => {
      const b = document.createElement("button");
      b.className = "preset" + (i === 0 ? " sel" : "");
      b.type = "button";
      b.innerHTML = `${p.name}<small>${p.sub}</small>`;
      b.onclick = () => {
        document.querySelectorAll(".preset").forEach(e => e.classList.remove("sel"));
        b.classList.add("sel");
        $("lat").value = p.lat; $("lon").value = p.lon;
        RW._presetName = p.name;
        schedulePreview();
      };
      wrap.appendChild(b);
    });
    RW._presetName = PRESETS[0].name;

    // the map is a pure function of the coordinates — show it before the player commits
    let pvT = 0;
    function schedulePreview() { clearTimeout(pvT); pvT = setTimeout(RW.drawSpawnPreview, 120); }
    ["lat", "lon"].forEach(id => $(id).addEventListener("input", () => {
      document.querySelectorAll(".preset").forEach(e => e.classList.remove("sel"));
      RW._presetName = "Поселення";
      schedulePreview();
    }));
    RW.drawSpawnPreview();

    $("gpsBtn").onclick = () => {
      if (!navigator.geolocation) { setStatus("Геолокація недоступна у браузері."); return; }
      setStatus("Запит GPS…");
      navigator.geolocation.getCurrentPosition(
        pos => {
          $("lat").value = pos.coords.latitude.toFixed(4);
          $("lon").value = pos.coords.longitude.toFixed(4);
          RW._presetName = "Моя локація";
          document.querySelectorAll(".preset").forEach(e => e.classList.remove("sel"));
          setStatus("GPS отримано: " + $("lat").value + ", " + $("lon").value);
          RW.drawSpawnPreview();
        },
        () => setStatus("Не вдалося отримати GPS (дозвіл відхилено?).")
      );
    };

    $("spawnBtn").onclick = () => {
      const lat = parseFloat($("lat").value), lon = parseFloat($("lon").value);
      if (isNaN(lat) || isNaN(lon) || lat < -85 || lat > 85 || lon < -180 || lon > 180) {
        setStatus("Невірні координати."); return;
      }
      if (RW.hasSave() && !confirm("Нова висадка зітре поточне збереження. Продовжити?")) return;
      RW.startGame(lat, lon, RW._presetName || "Поселення", $("useOsm").checked);
    };

    const meta = RW.saveMeta && RW.saveMeta();
    if (meta) {
      const cb = $("continueBtn"); cb.style.display = "";
      cb.innerHTML = `▶ Продовжити <small>${esc(meta.name)} · день ${meta.day}</small>`;
      cb.onclick = () => RW.loadGame();
    }
  };
  function setStatus(s) { $("spawnStatus").textContent = s; }
  RW.setSpawnStatus = setStatus;

  RW.drawSpawnPreview = function () {
    const cv = $("previewCv"); if (!cv) return;
    const lat = parseFloat($("lat").value), lon = parseFloat($("lon").value);
    const info = $("previewInfo");
    if (isNaN(lat) || isNaN(lon)) { info.textContent = "Невірні координати"; return; }
    const map = RW.generateMap(lat, lon, 56);
    const ctx = cv.getContext("2d"), N = map.N, s = cv.width / N;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      ctx.fillStyle = RW.TERRAIN_COLORS[map.tiles[y * N + x]];
      ctx.fillRect(x * s, y * s, s + 0.5, s + 0.5);
    }
    map.nodes.forEach((n, i) => {
      ctx.fillStyle = RW.NODEINFO[n.kind].color;
      ctx.fillRect((i % N) * s + s * 0.25, ((i / N) | 0) * s + s * 0.25, s * 0.5, s * 0.5);
    });
    ctx.fillStyle = "#ffd84a"; ctx.beginPath(); ctx.arc((map.spawn.x + 0.5) * s, (map.spawn.y + 0.5) * s, s * 1.4, 0, 7); ctx.fill();
    const seed = RW.hashSeed(lat, lon).toString(16).padStart(8, "0");
    info.innerHTML = `біом: <b>${map.biome}</b> · ресурсних точок: <b>${map.nodes.size}</b> · seed <code>${seed}</code>`;
  };

  RW.showGameUI = function () {
    $("spawn").classList.add("hidden");
    ["hud", "stock", "minimapWrap", "bottom", "sidebtns", "log"].forEach(id => $(id).classList.remove("hidden"));
  };

  // =====================================================================
  // build bar
  // =====================================================================
  const isLocked = (G, def) => !!(def.research && G.research && !G.research.gateOk(def.research));
  RW.selectBuild = function (G, key) {
    const def = RW.BUILDINGS[key];
    if (isLocked(G, def)) {
      // a locked button is a research shortcut: plan the full prereq path to its gate
      const planned = RW.planResearchPath(G.research, def.research);
      RW.flash(G, planned.length
        ? `🔬 Заплановано: ${planned.map(id => G.research.labelOf(id)).join(" → ")}`
        : `🔬 «${G.research.labelOf(def.research)}» вже в черзі досліджень`);
      return;
    }
    G.selectedBuild = (G.selectedBuild === key) ? null : key;
    G.selected = null; G.drag = null;
    RW.syncBuildBar(G);
    RW.setTicker(G, G.selectedBuild
      ? `${def.icon} ${def.name}: клік по клітинці${def.line ? ", або затисни і протягни — лінія" : ""}. ПКМ / Esc — вийти.`
      : "");
  };
  RW.buildBuildBar = function (G) {
    const bar = $("buildbar"); bar.innerHTML = "";
    RW.BUILD_ORDER.forEach(key => {
      const def = RW.BUILDINGS[key];
      const el = document.createElement("button");
      el.className = "bld"; el.type = "button";
      const locked = isLocked(G, def);
      const hk = RW.buildKeyOf(key);
      el.innerHTML = (hk ? `<span class="hk">${hk}</span>` : "") +
        `<div class="ic">${def.icon}</div><div class="nm">${def.name}</div>` +
        (locked ? `<div class="lk">🔒 ${esc(G.research.labelOf(def.research))}</div>`
                : `<div class="cost">${costHtml(G, def.cost)}</div>`);
      el.title = def.desc + (hk ? `  [${hk}]` : "") + (locked ? `\n🔒 Потрібне дослідження: ${G.research.labelOf(def.research)} (клік — запланувати)` : `\nКоштує: ${RW.costStr(def.cost)}`);
      el.setAttribute("aria-label", def.name);
      el.onclick = () => RW.selectBuild(G, key);
      el._key = key;
      bar.appendChild(el);
    });
    RW.syncBuildBar(G);
  };
  function costHtml(G, cost) {
    return Object.keys(cost).map(k => {
      const short = (G.base.stock[k] || 0) < cost[k];
      return `<span class="${short ? "short" : ""}">${RW.RES[k].icon}${cost[k]}</span>`;
    }).join(" ");
  }
  RW.syncBuildBar = function (G) {
    document.querySelectorAll("#buildbar .bld").forEach(el => {
      el.classList.toggle("sel", el._key === G.selectedBuild);
      const def = RW.BUILDINGS[el._key];
      const locked = isLocked(G, def);
      el.classList.toggle("locked", locked);
      const afford = !locked && RW.canAfford(G.base.stock, def.cost);
      el.classList.toggle("poor", !locked && !afford);
      const c = el.querySelector(".cost");
      if (c) { const html = costHtml(G, def.cost); if (c._html !== html) { c.innerHTML = html; c._html = html; } }
    });
  };

  // =====================================================================
  // HUD refresh (called each frame — only touches the DOM when a value changed)
  // =====================================================================
  const cache = {};
  function setText(id, v) { if (cache[id] !== v) { cache[id] = v; $(id).textContent = v; } }
  function setBar(id, v, lowAt) {
    const pct = RW.clamp(v, 0, 100);
    const key = id + ":" + Math.round(pct);
    if (cache[id] !== key) {
      cache[id] = key;
      $(id).style.width = pct + "%";
      const row = $(id).closest(".need");
      row.classList.toggle("low", pct < lowAt);
      row.classList.toggle("crit", pct < lowAt / 2);
      row.querySelector(".val").textContent = Math.round(pct);
    }
  }
  RW.refreshHUD = function (G) {
    const p = G.player;
    setBar("barHp", p.hp, 35);
    setBar("barFood", p.hunger, 30);
    setBar("barRest", p.rest, 25);
    setText("clockDay", "День " + G.time.day);
    setText("clockTime", RW.fmtTime(G.time.frac));
    setText("clockPhase", RW.phaseName(G.time.frac));
    const carried = RW.carryTotal(p);
    setText("carryTxt", carried + " / " + p.carryCap);
    $("carryChip").classList.toggle("full", carried >= p.carryCap);

    // research chip: active project + % (or the unlocked count when idle)
    if (G.research) {
      const s = G.research.summary();
      setText("resTxt", s.active
        ? `${s.active_label} · ${Math.floor(s.active_pct * 100)}%`
        : `${s.unlocked}/${s.total} · рівень ${s.level}`);
      const hasBench = G.buildings.some(b => b.kind === "research_bench");
      $("resChip").classList.toggle("idle", !s.active && hasBench);
    }

    // stockpile (rebuilt only when a number changes)
    const cap = RW.storageCap(G), tot = RW.stockTotal(G);
    const sig = RW.RES_ORDER.map(k => Math.floor(G.base.stock[k] || 0)).join(",") + "|" + tot + "/" + cap + "|" + G.enemies.length;
    if (cache.stock !== sig) {
      cache.stock = sig;
      let html = `<h3>Склад <span class="${tot >= cap ? "short" : ""}">${tot}/${cap}</span></h3>`;
      RW.RES_ORDER.forEach(k => {
        const v = Math.floor(G.base.stock[k] || 0);
        html += `<div class="res" title="${RW.RES[k].label}"><span><span class="dot" style="background:${RW.RES[k].color}"></span>${RW.RES[k].label}</span><b class="${v === 0 ? "zero" : ""}">${v}</b></div>`;
      });
      $("stock").innerHTML = html;
    }
    // pause veil (also synced eagerly by syncSpeedUI; this catches sim-side speed changes such as death)
    $("pauseVeil").classList.toggle("hidden", G.speed !== 0 || !!G._dead);

    RW.updateInspect(G);
    RW.renderSelection(G);
    RW.drawMinimap(G);
  };

  RW.syncSpeedUI = function (G) {
    document.querySelectorAll("#speedCtl button").forEach(b => b.classList.toggle("sel", +b.dataset.s === G.speed));
    $("pauseVeil").classList.toggle("hidden", G.speed !== 0 || !!G._dead);
  };
  RW.syncZoomUI = function (G) { setText("zoomTxt", Math.round(G.tile / RW.ZOOM_DEFAULT * 100) + "%"); };

  // ---- hover inspect (what is under the cursor) ----
  RW.updateInspect = function (G) {
    const el = $("inspect");
    const t = G.hover, m = G.mouse;
    if (!t || !m || G.selectedBuild || G.worldOpen || G.researchOpen) { el.classList.add("hidden"); cache.insp = ""; return; }
    const N = G.map.N;
    let html = "";
    if (t.x >= 0 && t.y >= 0 && t.x < N && t.y < N) {
      const i = t.y * N + t.x;
      let enemy = null, ed = 0.7;
      for (const e of G.enemies) { const d = RW.dist(e.px, e.py, t.fx, t.fy); if (d < ed) { ed = d; enemy = e; } }
      const b = G.bgrid.get(i), node = G.map.nodes.get(i);
      if (enemy) html = `<b>⚔ Рейдер</b> ${Math.ceil(enemy.hp)}/${Math.ceil(enemy.maxhp)} HP · удар ${enemy.dmg.toFixed(0)}<br><small>клік — атакувати</small>`;
      else if (b) {
        const def = RW.BUILDINGS[b.kind];
        html = `<b>${def.icon} ${def.name}</b> ${Math.ceil(b.hp)}/${def.hp} HP<br><small>${esc(def.desc)}<br>клік — вибрати</small>`;
      } else if (node) {
        const info = RW.NODEINFO[node.kind];
        html = `<b>${info.icon} ${RW.RES[info.res].label}</b> · лишилось ${node.amount}<br><small>клік — добувати (${info.time.toFixed(1)} с/од)</small>`;
      } else {
        const tt = G.map.tiles[i];
        html = `<b>${RW.terrainName[tt]}</b>${RW.isTerrainBlocked(tt) ? " · непрохідна" : "<br><small>клік — іти</small>"}`;
      }
    } else html = `<small>за межами карти</small>`;
    if (cache.insp !== html) { cache.insp = html; el.innerHTML = html; }
    el.classList.remove("hidden");
    const w = G.view.w, h = G.view.h;
    el.style.left = Math.min(m.x + 16, w - 230) + "px";
    el.style.top = (m.y + 18 > h - 90 ? m.y - 70 : m.y + 18) + "px";
  };

  // ---- selection card (own building) ----
  RW.renderSelection = function (G) {
    const el = $("selCard");
    const b = G.selected;
    if (!b || G.buildings.indexOf(b) < 0) { el.classList.add("hidden"); cache.sel = ""; return; }
    const def = RW.BUILDINGS[b.kind];
    const near = RW.dist(G.player.px, G.player.py, b.x + 0.5, b.y + 0.5) <= 2.6;
    const hurt = b.hp < def.hp;
    const extra = def.capacity ? ` · +${def.capacity} місткості` : def.range ? ` · радіус ${def.range}` : "";
    const rc = hurt ? RW.repairCostOf(def, b.hp) : null;
    const html = `<div class="sel-head"><b>${def.icon} ${def.name}</b><span class="hp ${hurt ? "warn" : ""}">${Math.ceil(b.hp)}/${def.hp} HP</span></div>
      <div class="sel-desc">${esc(def.desc)}${extra}</div>
      <div class="sel-actions">
        <button id="selRepair" ${hurt ? "" : "disabled"} title="${near ? "" : "Підійди ближче. "}Ремонт за ${rc ? RW.costStr(rc) : "—"} [F]">🔧 Полагодити${rc ? " · " + RW.costStr(rc) : ""}</button>
        <button id="selDemolish" title="Повертає ${RW.costStr(RW.refundOf(def.cost)) || "нічого"} [Del]">🔨 Розібрати · ${RW.costStr(RW.refundOf(def.cost)) || "0"}</button>
        <button id="selClose" class="x" title="Зняти вибір [Esc]">✕</button>
      </div>`;
    if (cache.sel !== html) {
      cache.sel = html; el.innerHTML = html;
      $("selRepair").onclick = () => RW.repair(G, G.selected);
      $("selDemolish").onclick = () => RW.demolish(G, G.selected);
      $("selClose").onclick = () => { G.selected = null; };
    }
    el.classList.remove("hidden");
  };

  // ---- minimap: terrain layer cached on an offscreen canvas, entities drawn each frame ----
  let mmBase = null, mmN = 0;
  RW.drawMinimap = function (G) {
    const cv = $("minimap"); if (!cv) return;
    const N = G.map.N, W = cv.width, s = W / N;
    if (G.mapDirty || !mmBase || mmN !== N) {
      mmBase = mmBase || document.createElement("canvas");
      mmBase.width = mmBase.height = W; mmN = N;
      const bc = mmBase.getContext("2d");
      for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
        bc.fillStyle = RW.TERRAIN_COLORS[G.map.tiles[y * N + x]];
        bc.fillRect(x * s, y * s, s + 0.5, s + 0.5);
      }
      G.map.nodes.forEach((n, i) => {
        bc.fillStyle = RW.NODEINFO[n.kind].color;
        bc.fillRect((i % N) * s + s * 0.2, ((i / N) | 0) * s + s * 0.2, s * 0.6, s * 0.6);
      });
      G.buildings.forEach(b => {
        bc.fillStyle = b.kind === "wall" || b.kind === "door" ? "#cfd5dc" : "#ffd84a";
        bc.fillRect(b.x * s, b.y * s, s, s);
      });
      G.mapDirty = false;
    }
    const ctx = cv.getContext("2d");
    ctx.drawImage(mmBase, 0, 0);
    // viewport rectangle
    const c = RW.camera(G);
    ctx.strokeStyle = "rgba(255,255,255,.55)"; ctx.lineWidth = 1;
    ctx.strokeRect(-c.ox / c.tile * s, -c.oy / c.tile * s, G.view.w / c.tile * s, G.view.h / c.tile * s);
    // enemies + player
    ctx.fillStyle = "#ff4d4d";
    G.enemies.forEach(e => { ctx.beginPath(); ctx.arc(e.px * s, e.py * s, Math.max(2, s), 0, 7); ctx.fill(); });
    ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(G.player.px * s, G.player.py * s, Math.max(2.5, s * 1.1), 0, 7); ctx.fill();
    // convoys in flight: a small truck badge
    if (G.convoys.length) { ctx.fillStyle = "#ffcf5c"; ctx.font = "11px sans-serif"; ctx.textAlign = "right"; ctx.textBaseline = "bottom"; ctx.fillText("🚚" + G.convoys.length, W - 2, W - 2); }
  };

  // =====================================================================
  // ticker / log / banner
  // =====================================================================
  RW.setTicker = function (G, msg, cls) {
    const t = $("ticker");
    if (!msg) { t.classList.add("hidden"); return; }
    t.classList.remove("hidden"); t.textContent = msg; t.className = "ticker " + (cls || "");
  };

  RW.log = function (G, msg, cls) {
    G.log = G.log || [];
    G.log.push({ msg, cls, day: G.time ? G.time.day : 0, t: G.time ? RW.fmtTime(G.time.frac) : "" });
    if (G.log.length > 200) G.log.splice(0, G.log.length - 200);
    const box = $("log");
    const line = document.createElement("div");
    line.className = "line " + (cls || "");
    line.textContent = msg;
    box.appendChild(line);
    while (box.children.length > 6) box.removeChild(box.firstChild);
    setTimeout(() => { line.classList.add("out"); setTimeout(() => line.remove(), 400); }, cls === "bad" ? 12000 : 8000);
    if (G.logOpen) RW.renderLog(G);
  };

  RW.raidBanner = function (msg) {
    const b = $("raidBanner");
    if (!msg) { b.classList.add("hidden"); return; }
    b.classList.remove("hidden"); b.textContent = msg;
  };

  // =====================================================================
  // side buttons, modals, menus
  // =====================================================================
  RW.anyModalOpen = () => MODALS.some(id => !$(id).classList.contains("hidden"));
  RW.closeModals = function (G) {
    MODALS.forEach(id => { if (id !== "deathModal") $(id).classList.add("hidden"); });
    G.worldOpen = false; G.researchOpen = false; G.logOpen = false;
  };
  function openModal(G, id) { RW.closeModals(G); $(id).classList.remove("hidden"); }

  RW.initButtons = function (G) {
    $("worldBtn").onclick = () => RW.openWorld(G);
    $("researchBtn").onclick = () => RW.toggleResearch(G);
    $("logBtn").onclick = () => RW.toggleLog(G);
    $("helpBtn").onclick = () => RW.toggleHelp(G);
    $("menuBtn").onclick = () => RW.toggleMenu(G);
    document.querySelectorAll(".modal .x[data-close]").forEach(b => { b.onclick = () => RW.closeModals(G); });
    document.querySelectorAll(".modal").forEach(m => { m.onmousedown = (e) => { if (e.target === m && m.id !== "deathModal") RW.closeModals(G); }; });
    // delegated handlers (plain onclick so re-init after load never stacks listeners)
    $("researchAvail").onclick = (e) => {
      const b = e.target.closest(".ravail");
      if (b && G.research) { G.research.enqueue(b.dataset.id); RW.renderResearch(G); }
    };
    $("researchQueue").onclick = (e) => {
      const b = e.target.closest(".rq");
      if (b && G.research) { G.research.dequeue(b.dataset.id); RW.renderResearch(G); }
    };
    document.querySelectorAll("#speedCtl button").forEach(b => { b.onclick = () => RW.setSpeed(G, +b.dataset.s); });
    $("zoomIn").onclick = () => RW.zoomBy(G, 1);
    $("zoomOut").onclick = () => RW.zoomBy(G, -1);
    $("minimap").onclick = (e) => {
      const r = $("minimap").getBoundingClientRect();
      const x = Math.floor((e.clientX - r.left) / r.width * G.map.N), y = Math.floor((e.clientY - r.top) / r.height * G.map.N);
      if (!G._dead) RW.orderMove(G, x, y);
    };
    // pause menu
    $("menuResume").onclick = () => RW.closeModals(G);
    $("menuSave").onclick = () => { RW.saveGame(G); RW.flashOk(G, "Збережено."); RW.closeModals(G); };
    $("menuHelp").onclick = () => RW.toggleHelp(G);
    $("menuNew").onclick = () => { if (confirm("Почати нову висадку? Поточне збереження буде стерто.")) RW.newWorld(); };
    $("deathNew").onclick = () => RW.newWorld();
    RW.syncSpeedUI(G); RW.syncZoomUI(G);
  };

  RW.newWorld = function () {
    try { localStorage.removeItem("realworld_save"); } catch (e) { }
    location.reload();
  };

  RW.openWorld = function (G) {
    if (G._dead) return;
    G.worldOpen = true;
    openModal(G, "worldModal"); G.worldOpen = true;
    buildConvoyPanel(G);
    RW.drawWorldMap(G);
  };
  RW.toggleResearch = function (G) {
    if (G._dead) return;
    const open = !G.researchOpen;
    RW.closeModals(G);
    if (open) { G.researchOpen = true; $("researchModal").classList.remove("hidden"); RW.renderResearch(G); }
  };
  RW.toggleHelp = function (G) {
    const open = $("helpModal").classList.contains("hidden");
    RW.closeModals(G);
    if (open) $("helpModal").classList.remove("hidden");
  };
  RW.toggleLog = function (G) {
    const open = !G.logOpen;
    RW.closeModals(G);
    if (open) { G.logOpen = true; $("logModal").classList.remove("hidden"); RW.renderLog(G); }
  };
  RW.toggleMenu = function (G) {
    const open = $("menuModal").classList.contains("hidden");
    RW.closeModals(G);
    if (open) {
      $("menuStats").innerHTML = RW.runSummary(G).map(([k, v]) => `<div class="stat"><span>${k}</span><b>${v}</b></div>`).join("");
      $("menuPlace").textContent = `${G.map.placeName} · ${G.map.lat.toFixed(4)}, ${G.map.lon.toFixed(4)} · ${G.map.source === "osm" ? "OSM-географія" : "процедурна карта"}`;
      $("menuModal").classList.remove("hidden");
    }
  };
  RW.showDeath = function (G) {
    RW.closeModals(G);
    $("deathStats").innerHTML = RW.runSummary(G).map(([k, v]) => `<div class="stat"><span>${k}</span><b>${v}</b></div>`).join("");
    $("deathModal").classList.remove("hidden");
  };
  RW.renderLog = function (G) {
    const box = $("logList");
    const lines = (G.log || []).slice().reverse();
    box.innerHTML = lines.length
      ? lines.map(l => `<div class="logrow ${l.cls || ""}"><span class="when">д.${l.day} ${l.t}</span>${esc(l.msg)}</div>`).join("")
      : `<div class="muted">Поки що порожньо.</div>`;
  };

  // ---- research modal ----
  RW.renderResearch = function (G) {
    const r = G.research; if (!r) return;
    const s = r.summary();
    const hasBench = G.buildings.some(b => b.kind === "research_bench");
    const sig = JSON.stringify([s.active, Math.floor(s.active_pct * 200), s.queue, s.unlocked, hasBench]);
    if (cache.research === sig) return;
    cache.research = sig;

    $("researchActive").innerHTML = s.active
      ? `<div class="convoy">Досліджується: <b>${esc(r.labelOf(s.active))}</b> · тір ${r.tierOf(s.active)} · ${s.active_progress.toFixed(1)}/${s.active_cost} дн
         <div class="cbar"><i style="width:${Math.floor(s.active_pct * 100)}%"></i></div></div>`
      : `<div class="convoy muted">${hasBench
          ? "Нічого не досліджується — вибери проєкт нижче."
          : "Спершу постав 🔬 дослідний стіл — він генерує прогрес досліджень."}</div>`;

    $("researchQueue").innerHTML = s.queue.length
      ? `<h3>Черга (клік — прибрати)</h3>` + s.queue.map(id => `<span class="rq" data-id="${id}">${esc(r.labelOf(id))} ✕</span>`).join("")
      : "";

    const avail = r.available().slice().sort((a, b) => ((a.tier || 0) - (b.tier || 0)) || (a.cost - b.cost));
    $("researchAvail").innerHTML =
      `<h3>Доступно зараз · досліджено ${s.unlocked}/${s.total} · тех-рівень ${s.level}</h3>` +
      (avail.length ? avail.map(p => {
        const un = r.unlocksOf(p.id);
        const names = [...un.buildings, ...un.recipes, ...un.items].slice(0, 4).join(", ");
        const opens = un.buildings.length + un.recipes.length + un.items.length;
        return `<button class="ravail" data-id="${p.id}" title="${esc(names || "нічого напряму — відкриває шлях далі")}">T${p.tier || 0} · ${esc(p.label || p.id)}<small> · ${p.cost} дн${opens ? ` · відкриє ${opens}` : ""}</small></button>`;
      }).join("") : `<div class="muted">Усе доступне вже досліджено або в черзі.</div>`);
  };

  // ---- world / logistics ----
  function buildConvoyPanel(G) {
    const panel = $("convoyPanel");
    const hubs = G.regions.map((r, i) => r.home ? null : `<option value="${i}">${esc(r.name)} · ${Math.round(RW.haversineKm(G.regions[0].lat, G.regions[0].lon, r.lat, r.lon))} км</option>`).filter(Boolean).join("");
    panel.innerHTML = `
      <div><label for="cvHub">Пункт призначення</label><select id="cvHub">${hubs}</select></div>
      <div><label>Везти</label><div id="cvBuy" class="cv-ro"></div></div>
      <div><label for="cvAmt">Кількість</label><input id="cvAmt" type="number" min="1" value="20" style="width:88px"></div>
      <div><label>Отримати</label><div id="cvGet" class="cv-ro"></div></div>
      <div><label>У дорозі</label><div id="cvEta" class="cv-ro"></div></div>
      <button id="cvSend" class="primary" style="flex:0 0 auto;min-width:150px">Відправити конвой 🚚</button>`;
    const hubSel = $("cvHub");
    const updOffer = () => {
      const r = G.regions[+hubSel.value];
      const have = Math.floor(G.base.stock[r.offer.buys] || 0);
      $("cvBuy").innerHTML = `${RW.RES[r.offer.buys].icon} ${RW.RES[r.offer.buys].label} <small class="muted">(є ${have})</small>`;
      const amt = Math.max(1, parseInt($("cvAmt").value) || 0);
      $("cvGet").innerHTML = `${RW.RES[r.offer.sells].icon} ${Math.max(1, Math.floor(amt / r.offer.rate))} ${RW.RES[r.offer.sells].label}`;
      const dist = RW.haversineKm(G.regions[0].lat, G.regions[0].lon, r.lat, r.lon);
      $("cvEta").textContent = "~" + Math.round(RW.clamp(dist * 0.045, 7, 55) * 2) + " с туди й назад";
      $("cvSend").disabled = have < amt;
    };
    hubSel.onchange = updOffer;
    $("cvAmt").oninput = updOffer;
    $("cvSend").onclick = () => {
      const r = G.regions[+hubSel.value];
      const res = RW.dispatchConvoy(G, +hubSel.value, r.offer.buys, parseInt($("cvAmt").value) || 0);
      if (!res.ok) RW.flash(G, res.msg);
      else { RW.refreshHUD(G); RW.drawWorldMap(G); renderConvoyList(G); updOffer(); }
    };
    updOffer();
    renderConvoyList(G);
  }

  function renderConvoyList(G) {
    const box = $("convoyList");
    const sig = G.convoys.map(c => c.id + c.phase + Math.round(c.t / c.dur * 50)).join("|");
    if (cache.convoys === sig) return;
    cache.convoys = sig;
    if (!G.convoys.length) { box.innerHTML = `<div class="muted">Немає активних конвоїв.</div>`; return; }
    box.innerHTML = G.convoys.map(c => {
      const frac = RW.clamp(c.t / c.dur, 0, 1);
      const ph = c.phase === "out" ? "їде до " + esc(c.hubName) : (c.ambushed ? "⚔ повертається після засідки" : "повертається");
      return `<div class="convoy">#${c.id} ${ph} · ${c.sendAmt}${RW.RES[c.sendRes].icon} → ${c.recvAmt}${RW.RES[c.recvRes].icon} · ${c.dist} км
        <div class="cbar"><i style="width:${Math.round(frac * 100)}%"></i></div></div>`;
    }).join("");
  }
  RW.renderConvoyList = renderConvoyList;

  // ---- world map render ----
  RW.drawWorldMap = function (G) {
    const cv = $("worldcv"); if (!cv) return;
    const ctx = cv.getContext("2d");
    const W = cv.width, H = cv.height;
    ctx.fillStyle = "#0b1118"; ctx.fillRect(0, 0, W, H);

    const lats = G.regions.map(r => r.lat), lons = G.regions.map(r => r.lon);
    let minLa = Math.min(...lats), maxLa = Math.max(...lats), minLo = Math.min(...lons), maxLo = Math.max(...lons);
    const padLa = (maxLa - minLa || 1) * 0.25, padLo = (maxLo - minLo || 1) * 0.25;
    minLa -= padLa; maxLa += padLa; minLo -= padLo; maxLo += padLo;
    const px = lo => 40 + (lo - minLo) / (maxLo - minLo) * (W - 80);
    const py = la => H - 36 - (la - minLa) / (maxLa - minLa) * (H - 72);

    // grid
    ctx.strokeStyle = "rgba(90,176,255,.08)"; ctx.lineWidth = 1;
    for (let i = 0; i <= 8; i++) { const x = 40 + i / 8 * (W - 80); ctx.beginPath(); ctx.moveTo(x, 20); ctx.lineTo(x, H - 20); ctx.stroke(); const y = 20 + i / 8 * (H - 40); ctx.beginPath(); ctx.moveTo(20, y); ctx.lineTo(W - 20, y); ctx.stroke(); }

    const home = G.regions[0];
    // routes
    G.regions.forEach((r) => {
      if (r.home) return;
      ctx.strokeStyle = "rgba(160,180,200,.25)"; ctx.setLineDash([5, 5]); ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(px(home.lon), py(home.lat)); ctx.lineTo(px(r.lon), py(r.lat)); ctx.stroke();
      ctx.setLineDash([]);
    });

    // convoys along their route
    G.convoys.forEach(c => {
      const r = G.regions[c.hubIndex];
      const frac = RW.clamp(c.t / c.dur, 0, 1);
      const a = c.phase === "out" ? home : r, b = c.phase === "out" ? r : home;
      const x = RW.lerp(px(a.lon), px(b.lon), frac), y = RW.lerp(py(a.lat), py(b.lat), frac);
      ctx.fillStyle = c.ambushed ? "#ff6b6b" : "#ffcf5c";
      ctx.font = "16px serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText("🚚", x, y);
    });

    // nodes
    G.regions.forEach((r) => {
      const x = px(r.lon), y = py(r.lat);
      if (r.home) {
        ctx.fillStyle = "#5fd38a"; star(ctx, x, y, 5, 11, 5);
        ctx.fillStyle = "#bfe9cd"; ctx.font = "12px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "bottom";
        ctx.fillText("★ " + r.name + " (база)", x, y - 12);
      } else {
        ctx.fillStyle = "#5db0ff"; ctx.beginPath(); ctx.arc(x, y, 7, 0, 7); ctx.fill();
        ctx.strokeStyle = "#0b1118"; ctx.lineWidth = 2; ctx.stroke();
        ctx.fillStyle = "#cfe0ee"; ctx.font = "12px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "top";
        ctx.fillText(r.name, x, y + 10);
        ctx.fillStyle = "#8aa0b4"; ctx.font = "10px sans-serif";
        ctx.fillText(`${RW.RES[r.offer.buys].icon}→${RW.RES[r.offer.sells].icon}`, x, y + 24);
      }
    });
  };

  function star(ctx, cx, cy, inner, outer, points) {
    ctx.beginPath();
    for (let i = 0; i < points * 2; i++) {
      const r = i % 2 ? inner : outer, a = Math.PI / points * i - Math.PI / 2;
      ctx[i ? "lineTo" : "moveTo"](cx + Math.cos(a) * r, cy + Math.sin(a) * r);
    }
    ctx.closePath(); ctx.fill();
  }

})(window.RW);

/* RealWorld — ui.js : DOM HUD, menus, spawn screen, world-map modal */
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

  const $ = (id) => document.getElementById(id);

  RW.initSpawnUI = function () {
    const wrap = $("presets");
    PRESETS.forEach((p, i) => {
      const b = document.createElement("button");
      b.className = "preset" + (i === 0 ? " sel" : "");
      b.innerHTML = `${p.name}<small>${p.sub}</small>`;
      b.onclick = () => {
        document.querySelectorAll(".preset").forEach(e => e.classList.remove("sel"));
        b.classList.add("sel");
        $("lat").value = p.lat; $("lon").value = p.lon;
        RW._presetName = p.name;
      };
      wrap.appendChild(b);
    });
    RW._presetName = PRESETS[0].name;

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
        },
        () => setStatus("Не вдалося отримати GPS (дозвіл відхилено?).")
      );
    };

    $("spawnBtn").onclick = () => {
      const lat = parseFloat($("lat").value), lon = parseFloat($("lon").value);
      if (isNaN(lat) || isNaN(lon) || lat < -85 || lat > 85 || lon < -180 || lon > 180) {
        setStatus("Невірні координати."); return;
      }
      RW.startGame(lat, lon, RW._presetName || "Поселення", $("useOsm").checked);
    };

    if (RW.hasSave && RW.hasSave()) {
      const cb = $("continueBtn"); cb.style.display = "";
      cb.onclick = () => RW.loadGame();
    }
  };
  function setStatus(s) { $("spawnStatus").textContent = s; }
  RW.setSpawnStatus = setStatus;

  RW.showGameUI = function () {
    $("spawn").classList.add("hidden");
    ["hud", "stock", "buildbar", "sidebtns", "log", "ticker"].forEach(id => $(id).classList.remove("hidden"));
  };

  // ---- build bar ----
  const isLocked = (G, def) => !!(def.research && G.research && !G.research.gateOk(def.research));
  RW.buildBuildBar = function (G) {
    const bar = $("buildbar"); bar.innerHTML = "";
    RW.BUILD_ORDER.forEach(key => {
      const def = RW.BUILDINGS[key];
      const el = document.createElement("button");
      el.className = "bld";
      const locked = isLocked(G, def);
      el.innerHTML = `<div class="ic">${def.icon}</div><div class="nm">${def.name}</div>` +
        (locked ? `<div class="lk">🔒 ${G.research.labelOf(def.research)}</div>`
                : `<div class="cost">${RW.costStr(def.cost)}</div>`);
      el.onclick = () => {
        if (isLocked(G, def)) {
          // a locked button is a research shortcut: plan the full prereq path to its gate
          const planned = RW.planResearchPath(G.research, def.research);
          RW.flash(G, planned.length
            ? `🔬 Заплановано: ${planned.map(id => G.research.labelOf(id)).join(" → ")}`
            : `🔬 «${G.research.labelOf(def.research)}» вже в черзі досліджень`);
          return;
        }
        G.selectedBuild = (G.selectedBuild === key) ? null : key;
        RW.syncBuildBar(G);
        RW.setTicker(G, G.selectedBuild ? "Режим будівництва: " + def.name + " — клікни по клітинці. ПКМ/Esc — вийти." : "");
      };
      el._key = key;
      bar.appendChild(el);
    });
    RW.syncBuildBar(G);
  };
  RW.syncBuildBar = function (G) {
    document.querySelectorAll("#buildbar .bld").forEach(el => {
      el.classList.toggle("sel", el._key === G.selectedBuild);
      const def = RW.BUILDINGS[el._key];
      const locked = isLocked(G, def);
      el.classList.toggle("locked", locked);
      el.style.opacity = (!locked && RW.canAfford(G.base.stock, def.cost)) ? "1" : "0.45";
    });
  };

  // ---- HUD refresh (called each frame, cheap) ----
  RW.refreshHUD = function (G) {
    const p = G.player;
    $("barHp").style.width = RW.clamp(p.hp, 0, 100) + "%";
    $("barFood").style.width = RW.clamp(p.hunger, 0, 100) + "%";
    $("barRest").style.width = RW.clamp(p.rest, 0, 100) + "%";
    $("clockDay").textContent = "День " + G.time.day;
    $("clockTime").textContent = RW.fmtTime(G.time.frac);
    $("clockPhase").textContent = RW.phaseName(G.time.frac);
    $("carryTxt").textContent = RW.carryTotal(p) + " / " + p.carryCap;

    // research chip: active project + % (or the unlocked count when idle)
    if (G.research) {
      const s = G.research.summary();
      $("resTxt").textContent = s.active
        ? `${s.active_label} · ${Math.floor(s.active_pct * 100)}%`
        : `${s.unlocked}/${s.total} · рівень ${s.level}`;
    }

    // stockpile
    const cap = RW.storageCap(G);
    let html = `<h3>Склад · ${RW.stockTotal(G)}/${cap}</h3>`;
    RW.RES_ORDER.forEach(k => {
      const v = Math.floor(G.base.stock[k] || 0);
      html += `<div class="res"><span><span class="dot" style="background:${RW.RES[k].color}"></span>${RW.RES[k].label}</span><b>${v}</b></div>`;
    });
    $("stock").innerHTML = html;
  };

  RW.setTicker = function (G, msg) {
    const t = $("ticker");
    if (!msg) { t.classList.add("hidden"); return; }
    t.classList.remove("hidden"); t.textContent = msg;
  };

  RW.log = function (G, msg, cls) {
    G.log = G.log || [];
    G.log.push({ msg, cls });
    const box = $("log");
    const line = document.createElement("div");
    line.className = "line " + (cls || "");
    line.textContent = msg;
    box.appendChild(line);
    while (box.children.length > 6) box.removeChild(box.firstChild);
    setTimeout(() => { if (line.parentNode) line.parentNode.removeChild(line); }, 9000);
  };

  RW.raidBanner = function (msg) {
    const b = document.getElementById("raidBanner");
    if (!msg) { b.classList.add("hidden"); return; }
    b.classList.remove("hidden"); b.textContent = msg;
  };

  // ---- side buttons & modals ----
  RW.initButtons = function (G) {
    $("worldBtn").onclick = () => RW.openWorld(G);
    $("researchBtn").onclick = () => RW.toggleResearch(G);
    $("researchClose").onclick = () => { $("researchModal").classList.add("hidden"); G.researchOpen = false; };
    // delegated handlers (plain onclick so re-init after load never stacks listeners)
    $("researchAvail").onclick = (e) => {
      const b = e.target.closest(".ravail");
      if (b && G.research) { G.research.enqueue(b.dataset.id); RW.renderResearch(G); }
    };
    $("researchQueue").onclick = (e) => {
      const b = e.target.closest(".rq");
      if (b && G.research) { G.research.dequeue(b.dataset.id); RW.renderResearch(G); }
    };
    $("helpBtn").onclick = () => $("helpModal").classList.remove("hidden");
    $("helpClose").onclick = () => $("helpModal").classList.add("hidden");
    $("worldClose").onclick = () => { $("worldModal").classList.add("hidden"); G.worldOpen = false; };
    $("speedBtn").onclick = () => {
      const speeds = [1, 2, 3, 0];
      G.speedIdx = ((G.speedIdx || 0) + 1) % speeds.length;
      G.speed = speeds[G.speedIdx];
      $("speedBtn").textContent = G.speed === 0 ? "⏸ пауза" : "▸ " + G.speed + "×";
    };
  };

  RW.openWorld = function (G) {
    G.worldOpen = true;
    $("worldModal").classList.remove("hidden");
    buildConvoyPanel(G);
    RW.drawWorldMap(G);
  };

  // ---- research modal ----
  RW.toggleResearch = function (G) {
    G.researchOpen = !G.researchOpen;
    $("researchModal").classList.toggle("hidden", !G.researchOpen);
    if (G.researchOpen) RW.renderResearch(G);
  };
  RW.renderResearch = function (G) {
    const r = G.research; if (!r) return;
    const s = r.summary();
    const hasBench = G.buildings.some(b => b.kind === "research_bench");

    $("researchActive").innerHTML = s.active
      ? `<div class="convoy">Досліджується: <b>${r.labelOf(s.active)}</b> · тір ${r.tierOf(s.active)} · ${s.active_progress.toFixed(1)}/${s.active_cost} дн
         <div class="cbar"><i style="width:${Math.floor(s.active_pct * 100)}%"></i></div></div>`
      : `<div class="convoy" style="color:var(--mut)">${hasBench
          ? "Нічого не досліджується — вибери проєкт нижче."
          : "Спершу постав 🔬 дослідний стіл — він генерує прогрес досліджень."}</div>`;

    $("researchQueue").innerHTML = s.queue.length
      ? `<h3>Черга (клік — прибрати)</h3>` + s.queue.map(id => `<span class="rq" data-id="${id}">${r.labelOf(id)} ✕</span>`).join("")
      : "";

    const avail = r.available().slice().sort((a, b) => ((a.tier || 0) - (b.tier || 0)) || (a.cost - b.cost));
    $("researchAvail").innerHTML =
      `<h3>Доступно зараз · досліджено ${s.unlocked}/${s.total} · тех-рівень ${s.level}</h3>` +
      (avail.length ? avail.map(p => {
        const un = r.unlocksOf(p.id);
        const opens = un.buildings.length + un.recipes.length + un.items.length;
        return `<button class="ravail" data-id="${p.id}">T${p.tier || 0} · ${p.label || p.id}<small> · ${p.cost} дн${opens ? ` · відкриє ${opens}` : ""}</small></button>`;
      }).join("") : `<div style="color:var(--mut);font-size:13px">Усе доступне вже досліджено або в черзі.</div>`);
  };

  function buildConvoyPanel(G) {
    const panel = $("convoyPanel");
    const hubs = G.regions.map((r, i) => r.home ? null : `<option value="${i}">${r.name} · ${Math.round(RW.haversineKm(G.regions[0].lat, G.regions[0].lon, r.lat, r.lon))} км</option>`).filter(Boolean).join("");
    panel.innerHTML = `
      <div><label>Пункт призначення</label><select id="cvHub">${hubs}</select></div>
      <div><label>Везти</label><div id="cvBuy" style="padding:8px 0;font-size:13px"></div></div>
      <div><label>Кількість</label><input id="cvAmt" type="number" min="1" value="20" style="width:88px"></div>
      <div><label>Отримати</label><div id="cvGet" style="padding:8px 0;font-size:13px"></div></div>
      <button id="cvSend" class="primary" style="flex:0 0 auto;min-width:150px">Відправити конвой 🚚</button>`;
    const hubSel = $("cvHub");
    const updOffer = () => {
      const r = G.regions[+hubSel.value];
      $("cvBuy").innerHTML = `${RW.RES[r.offer.buys].icon} ${RW.RES[r.offer.buys].label}`;
      const amt = Math.max(1, parseInt($("cvAmt").value) || 0);
      $("cvGet").innerHTML = `${RW.RES[r.offer.sells].icon} ${Math.floor(amt / r.offer.rate)} ${RW.RES[r.offer.sells].label}`;
    };
    hubSel.onchange = updOffer;
    $("cvAmt").oninput = updOffer;
    $("cvSend").onclick = () => {
      const r = G.regions[+hubSel.value];
      const res = RW.dispatchConvoy(G, +hubSel.value, r.offer.buys, parseInt($("cvAmt").value) || 0);
      if (!res.ok) RW.setTicker(G, "⚠ " + res.msg), setTimeout(() => RW.setTicker(G, ""), 2500);
      else { RW.refreshHUD(G); RW.drawWorldMap(G); renderConvoyList(G); }
    };
    updOffer();
    renderConvoyList(G);
  }

  function renderConvoyList(G) {
    const box = $("convoyList");
    if (!G.convoys.length) { box.innerHTML = `<div style="color:var(--mut);font-size:13px">Немає активних конвоїв.</div>`; return; }
    box.innerHTML = G.convoys.map(c => {
      const frac = RW.clamp(c.t / c.dur, 0, 1);
      const ph = c.phase === "out" ? "їде до " + c.hubName : "повертається";
      return `<div class="convoy">#${c.id} ${ph} · ${c.sendAmt}${RW.RES[c.sendRes].icon} → ${c.recvAmt}${RW.RES[c.recvRes].icon}
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
    G.regions.forEach((r, i) => {
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
    G.regions.forEach((r, i) => {
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

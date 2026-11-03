/* RealWorld — input.js : mouse / keyboard / touch on the world canvas
   Grammar: LMB = order (move / gather / attack) or build; LMB-drag in build mode = a run of
   walls/floors/doors; RMB or Esc = cancel build / deselect; wheel or +/- = zoom; Space = pause;
   1–9 0 - = build slots; M world map; R research; L event log; H help; Del = demolish; F = repair. */
(function (RW) {
  "use strict";

  RW.initInput = function (G, canvas) {
    G.keys = {};
    G.hover = null;
    if (RW._inputBound) return;        // re-init after load must not stack window listeners
    RW._inputBound = true;
    const cur = () => RW.G;            // always act on the live game, even after a reload

    const rel = (e) => {
      const r = canvas.getBoundingClientRect();
      const src = e.touches && e.touches[0] ? e.touches[0] : (e.changedTouches && e.changedTouches[0]) || e;
      return { x: src.clientX - r.left, y: src.clientY - r.top };
    };
    const inMap = (G, t) => t.x >= 0 && t.y >= 0 && t.x < G.map.N && t.y < G.map.N;

    canvas.addEventListener("mousemove", (e) => {
      const G = cur(); if (!G) return;
      const p = rel(e);
      G.hover = RW.screenToTile(G, p.x, p.y);
      G.mouse = p;
    });
    canvas.addEventListener("mouseleave", () => { const G = cur(); if (G) { G.hover = null; G.mouse = null; } });

    function orderAt(G, t) {
      // attack? find enemy near click
      let hit = null, hd = 0.7;
      for (const e of G.enemies) {
        const d = RW.dist(e.px, e.py, t.fx, t.fy);
        if (d < hd) { hd = d; hit = e; }
      }
      if (hit) { RW.orderAttack(G, hit); return; }
      // own building? select it (and still walk there if it's walkable)
      if (inMap(G, t) && G.bgrid.has(t.y * G.map.N + t.x)) {
        RW.selectAt(G, t.x, t.y);
        if (!RW.isBlocked(G, t.y * G.map.N + t.x)) RW.orderMove(G, t.x, t.y);
        return;
      }
      G.selected = null;
      // gather node?
      if (inMap(G, t) && G.map.nodes.has(t.y * G.map.N + t.x)) { RW.orderGather(G, t.x, t.y); return; }
      RW.orderMove(G, t.x, t.y);
    }

    function pressStart(G, p) {
      const t = RW.screenToTile(G, p.x, p.y);
      G.hover = t;
      if (G.selectedBuild) {
        const def = RW.BUILDINGS[G.selectedBuild];
        if (def.line) { G.drag = { x: t.x, y: t.y }; return; }   // the run is placed on release
        RW.tryBuild(G, t.x, t.y);
        return;
      }
      orderAt(G, t);
    }
    function pressEnd(G, p) {
      if (!G.drag || !G.selectedBuild) { G.drag = null; return; }
      const t = RW.screenToTile(G, p.x, p.y);
      const cells = RW.lineCells(G.drag.x, G.drag.y, t.x, t.y);
      G.drag = null;
      if (cells.length === 1) { RW.tryBuild(G, cells[0].x, cells[0].y); return; }
      const n = RW.buildRun(G, cells);
      if (n) RW.flashOk(G, `Збудовано ${n} × ${RW.BUILDINGS[G.selectedBuild].name}`);
      else RW.flash(G, "Нічого не збудовано — немає місця або ресурсів.");
    }

    canvas.addEventListener("mousedown", (e) => {
      const G = cur(); if (!G || G._dead) return;
      if (e.button === 2) { if (G.selectedBuild) RW.cancelBuild(G); else G.selected = null; return; }
      if (e.button !== 0) return;
      pressStart(G, rel(e));
    });
    window.addEventListener("mouseup", (e) => {
      const G = cur(); if (!G || e.button !== 0) return;
      pressEnd(G, rel(e));
    });
    canvas.addEventListener("contextmenu", (e) => e.preventDefault());

    // wheel = zoom around the player (camera follows the player, so no anchor math needed)
    canvas.addEventListener("wheel", (e) => {
      const G = cur(); if (!G) return;
      e.preventDefault();
      RW.zoomBy(G, e.deltaY < 0 ? 1 : -1);
    }, { passive: false });

    // touch: tap = click, two-finger = pinch zoom, long press = cancel build
    let pinch = null, longT = null;
    canvas.addEventListener("touchstart", (e) => {
      const G = cur(); if (!G || G._dead) return;
      e.preventDefault();
      if (e.touches.length === 2) {
        pinch = { d: Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY), tile: G.tile };
        G.drag = null; return;
      }
      const p = rel(e); G.mouse = p; G.hover = RW.screenToTile(G, p.x, p.y);
      clearTimeout(longT);
      longT = setTimeout(() => { if (G.selectedBuild) RW.cancelBuild(G); }, 650);
      pressStart(G, p);
    }, { passive: false });
    canvas.addEventListener("touchmove", (e) => {
      const G = cur(); if (!G) return;
      e.preventDefault(); clearTimeout(longT);
      if (pinch && e.touches.length === 2) {
        const d = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY);
        RW.setZoom(G, pinch.tile * d / pinch.d); return;
      }
      const p = rel(e); G.mouse = p; G.hover = RW.screenToTile(G, p.x, p.y);
    }, { passive: false });
    canvas.addEventListener("touchend", (e) => {
      const G = cur(); if (!G) return;
      clearTimeout(longT);
      if (pinch) { if (e.touches.length < 2) pinch = null; return; }
      pressEnd(G, rel(e));
    });

    window.addEventListener("keydown", (e) => {
      const G = cur(); if (!G) return;
      const k = e.key.toLowerCase();
      // typing into a field (convoy amount etc.) must not drive the game
      const tag = (e.target && e.target.tagName) || "";
      if (tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA") { if (k === "escape") e.target.blur(); return; }
      G.keys[k] = true;
      if (k === "escape") {
        if (RW.anyModalOpen && RW.anyModalOpen()) { RW.closeModals(G); return; }
        if (G.selectedBuild) { RW.cancelBuild(G); return; }
        if (G.selected) { G.selected = null; return; }
        if (G.player.action) { G.player.action = null; return; }
        if (RW.toggleMenu) RW.toggleMenu(G);
        return;
      }
      if (G._dead) return;
      if (k === " ") { e.preventDefault(); RW.togglePause(G); return; }
      if (k === "m") RW.openWorld(G);
      if (k === "r") RW.toggleResearch(G);
      if (k === "l" && RW.toggleLog) RW.toggleLog(G);
      if (k === "h" && RW.toggleHelp) RW.toggleHelp(G);
      if (k === "+" || k === "=") RW.zoomBy(G, 1);
      if (k === "-" || k === "_") RW.zoomBy(G, -1);
      if (k === "delete" || k === "backspace") { if (G.selected) { RW.demolish(G, G.selected); e.preventDefault(); } }
      if (k === "f" && G.selected) RW.repair(G, G.selected);
      if (k === "tab") { e.preventDefault(); RW.cycleSpeed(G); }
      const slot = RW.BUILD_KEYS.indexOf(e.key);
      if (slot >= 0 && !e.shiftKey) {
        const key = RW.BUILD_ORDER[slot];
        if (key && RW.selectBuild) RW.selectBuild(G, key);
      }
      if (["w", "a", "s", "d", " "].includes(k)) e.preventDefault();
    });
    window.addEventListener("keyup", (e) => { const G = cur(); if (G) G.keys[e.key.toLowerCase()] = false; });
    window.addEventListener("blur", () => { const G = cur(); if (G) G.keys = {}; });
  };

})(window.RW);

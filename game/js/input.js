/* RealWorld — input.js : mouse / keyboard / touch on the world canvas */
(function (RW) {
  "use strict";

  RW.initInput = function (G, canvas) {
    G.keys = {};
    G.hover = null;

    const rel = (e) => {
      const r = canvas.getBoundingClientRect();
      const src = e.touches && e.touches[0] ? e.touches[0] : e;
      return { x: src.clientX - r.left, y: src.clientY - r.top };
    };

    canvas.addEventListener("mousemove", (e) => {
      const p = rel(e);
      const t = RW.screenToTile(G, p.x, p.y);
      G.hover = t;
      G.mouse = p;
    });

    function handleClick(p) {
      const t = RW.screenToTile(G, p.x, p.y);
      if (G.selectedBuild) { RW.tryBuild(G, t.x, t.y); return; }
      // attack? find enemy near click
      let hit = null, hd = 0.7;
      for (const e of G.enemies) {
        const d = RW.dist(e.px, e.py, t.fx, t.fy);
        if (d < hd) { hd = d; hit = e; }
      }
      if (hit) { RW.orderAttack(G, hit); return; }
      // gather node?
      if (t.x >= 0 && t.y >= 0 && t.x < G.map.N && t.y < G.map.N && G.map.nodes.has(t.y * G.map.N + t.x)) {
        RW.orderGather(G, t.x, t.y); return;
      }
      RW.orderMove(G, t.x, t.y);
    }

    canvas.addEventListener("mousedown", (e) => {
      if (e.button === 2) { RW.cancelBuild(G); return; }
      if (e.button !== 0) return;
      handleClick(rel(e));
    });
    canvas.addEventListener("contextmenu", (e) => { e.preventDefault(); RW.cancelBuild(G); });

    canvas.addEventListener("touchstart", (e) => { e.preventDefault(); handleClick(rel(e)); }, { passive: false });

    window.addEventListener("keydown", (e) => {
      const k = e.key.toLowerCase();
      G.keys[k] = true;
      if (k === "escape") { RW.cancelBuild(G); G.player.action = null; }
      if (k === "m") RW.openWorld(G);
      if (k === "r") RW.toggleResearch(G);
      if (k === "h") document.getElementById("helpModal").classList.toggle("hidden");
      if (k >= "1" && k <= "9") {
        const key = RW.BUILD_ORDER[+k - 1];
        if (key) { G.selectedBuild = (G.selectedBuild === key ? null : key); RW.syncBuildBar(G); }
      }
      if (["w", "a", "s", "d", " "].includes(k)) e.preventDefault();
    });
    window.addEventListener("keyup", (e) => { G.keys[e.key.toLowerCase()] = false; });
  };

})(window.RW);

/* RealWorld — render.js : draws the world to the main canvas */
(function (RW) {
  "use strict";
  const T = RW.T;

  const TC = {
    0: "#27557e", 1: "#5c7d3c", 2: "#39562a", 3: "#6c7077",
    4: "#3b4148", 5: "#6e5836", 6: "#4f4a42", 7: "#c7b377", 8: "#dde6ee"
  };

  RW.camera = function (G) {
    const tile = G.tile, p = G.player;
    return { tile, ox: G.view.w / 2 - p.px * tile, oy: G.view.h / 2 - p.py * tile };
  };
  RW.screenToTile = function (G, sx, sy) {
    const c = RW.camera(G);
    const fx = (sx - c.ox) / c.tile, fy = (sy - c.oy) / c.tile;
    return { x: Math.floor(fx), y: Math.floor(fy), fx, fy };
  };

  // smooth sun/darkness from time-of-day fraction (0 = midnight)
  RW.daylight = function (frac) {
    const sun = -Math.cos(frac * 2 * Math.PI);          // +1 noon, -1 midnight
    return RW.clamp(0.46 * (1 - (sun * 0.5 + 0.5)), 0, 0.46);
  };
  RW.phaseName = function (frac) {
    if (frac < 0.22 || frac > 0.80) return "🌙 ніч";
    if (frac < 0.30) return "🌅 світанок";
    if (frac > 0.72) return "🌇 сутінки";
    return "☀ день";
  };

  RW.render = function (ctx, G) {
    const c = RW.camera(G), tile = c.tile, N = G.map.N, tiles = G.map.tiles;
    const w = G.view.w, h = G.view.h;
    ctx.clearRect(0, 0, w, h);

    // visible tile range
    const x0 = Math.max(0, Math.floor(-c.ox / tile));
    const y0 = Math.max(0, Math.floor(-c.oy / tile));
    const x1 = Math.min(N - 1, Math.ceil((w - c.ox) / tile));
    const y1 = Math.min(N - 1, Math.ceil((h - c.oy) / tile));

    // terrain
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      const i = y * N + x, t = tiles[i];
      const sx = x * tile + c.ox, sy = y * tile + c.oy;
      ctx.fillStyle = TC[t];
      ctx.fillRect(sx, sy, tile + 1, tile + 1);
      // subtle checker so the grid reads
      if ((x + y) & 1) { ctx.fillStyle = "rgba(0,0,0,.05)"; ctx.fillRect(sx, sy, tile + 1, tile + 1); }
    }

    // resource nodes
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      const i = y * N + x, node = G.map.nodes.get(i);
      if (!node) continue;
      drawNode(ctx, node, x * tile + c.ox, y * tile + c.oy, tile);
    }

    // buildings
    G.buildings.forEach(b => {
      if (b.x < x0 - 1 || b.x > x1 + 1 || b.y < y0 - 1 || b.y > y1 + 1) return;
      drawBuilding(ctx, b, b.x * tile + c.ox, b.y * tile + c.oy, tile, G);
    });

    // build ghost
    if (G.selectedBuild && G.hover) {
      const def = RW.BUILDINGS[G.selectedBuild];
      const ok = RW.buildValid(G, G.hover.x, G.hover.y) && RW.canAfford(G.base.stock, def.cost);
      const sx = G.hover.x * tile + c.ox, sy = G.hover.y * tile + c.oy;
      ctx.globalAlpha = 0.55;
      ctx.fillStyle = ok ? "rgba(90,210,140,.5)" : "rgba(255,90,90,.45)";
      ctx.fillRect(sx + 1, sy + 1, tile - 2, tile - 2);
      ctx.globalAlpha = 1;
      ctx.font = Math.floor(tile * 0.7) + "px serif";
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText(def.icon, sx + tile / 2, sy + tile / 2);
      ctx.strokeStyle = ok ? "#5fd38a" : "#ff6b6b"; ctx.lineWidth = 2;
      ctx.strokeRect(sx + 1, sy + 1, tile - 2, tile - 2);
    }

    // move/gather target marker
    if (G.player.action && G.player.action.cell != null) {
      const ax = (G.player.action.cell % N) * tile + c.ox, ay = ((G.player.action.cell / N) | 0) * tile + c.oy;
      ctx.strokeStyle = "rgba(255,207,92,.9)"; ctx.lineWidth = 2;
      ctx.strokeRect(ax + 2, ay + 2, tile - 4, tile - 4);
    }

    // turret shots
    G.shots.forEach(s => {
      ctx.strokeStyle = "rgba(255,230,120," + RW.clamp(s.t / 0.12, 0, 1) + ")";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(s.x1 * tile + c.ox, s.y1 * tile + c.oy);
      ctx.lineTo(s.x2 * tile + c.ox, s.y2 * tile + c.oy);
      ctx.stroke();
    });

    // raiders
    G.enemies.forEach(e => drawRaider(ctx, e, e.px * tile + c.ox, e.py * tile + c.oy, tile));

    // player
    drawPlayer(ctx, G, G.player.px * tile + c.ox, G.player.py * tile + c.oy, tile);

    // day/night overlay
    const dark = RW.daylight(G.time.frac);
    if (dark > 0.01) {
      ctx.fillStyle = "rgba(8,14,34," + dark + ")";
      ctx.fillRect(0, 0, w, h);
    }
    // warm dawn/dusk band
    const fr = G.time.frac;
    const warm = Math.max(0, 0.25 - Math.min(Math.abs(fr - 0.25), Math.abs(fr - 0.75))) * 1.4;
    if (warm > 0.01) { ctx.fillStyle = "rgba(255,140,60," + warm * 0.25 + ")"; ctx.fillRect(0, 0, w, h); }
  };

  function drawNode(ctx, node, sx, sy, tile) {
    const cx = sx + tile / 2, cy = sy + tile / 2, r = tile * 0.36;
    if (node.kind === "tree") {
      ctx.fillStyle = "#5a3d22"; ctx.fillRect(cx - tile * 0.05, cy, tile * 0.1, tile * 0.32);
      ctx.fillStyle = "#2f6b30"; ctx.beginPath(); ctx.arc(cx, cy - tile * 0.06, r, 0, 7); ctx.fill();
      ctx.fillStyle = "rgba(255,255,255,.08)"; ctx.beginPath(); ctx.arc(cx - r * 0.3, cy - r * 0.35, r * 0.5, 0, 7); ctx.fill();
    } else if (node.kind === "rock") {
      ctx.fillStyle = "#8b9099"; ctx.beginPath(); ctx.arc(cx - r * 0.3, cy + r * 0.1, r * 0.7, 0, 7); ctx.arc(cx + r * 0.4, cy, r * 0.6, 0, 7); ctx.fill();
      ctx.fillStyle = "rgba(0,0,0,.18)"; ctx.beginPath(); ctx.arc(cx + r * 0.4, cy + r * 0.2, r * 0.35, 0, 7); ctx.fill();
    } else if (node.kind === "bush") {
      ctx.fillStyle = "#4f8a3f"; ctx.beginPath(); ctx.arc(cx, cy, r * 0.7, 0, 7); ctx.fill();
      ctx.fillStyle = "#d3506a"; for (let k = 0; k < 3; k++) { ctx.beginPath(); ctx.arc(cx + (k - 1) * r * 0.4, cy + (k % 2) * r * 0.2, r * 0.14, 0, 7); ctx.fill(); }
    } else if (node.kind === "scrap") {
      ctx.fillStyle = "#86d0d6"; ctx.fillRect(cx - r * 0.5, cy - r * 0.2, r, r * 0.4);
      ctx.fillStyle = "#5fa9af"; ctx.fillRect(cx - r * 0.2, cy + r * 0.1, r * 0.6, r * 0.3);
    }
  }

  function drawBuilding(ctx, b, sx, sy, tile, G) {
    const def = RW.BUILDINGS[b.kind];
    const p = tile, cx = sx + p / 2, cy = sy + p / 2;
    if (b.kind === "wall") {
      ctx.fillStyle = "#8a8f97"; ctx.fillRect(sx + 1, sy + 1, p - 2, p - 2);
      ctx.fillStyle = "rgba(255,255,255,.12)"; ctx.fillRect(sx + 1, sy + 1, p - 2, 3);
      ctx.fillStyle = "rgba(0,0,0,.25)"; ctx.fillRect(sx + 1, sy + p - 4, p - 2, 3);
    } else if (b.kind === "floor") {
      ctx.fillStyle = "#7d756a"; ctx.fillRect(sx + 1, sy + 1, p - 2, p - 2);
      ctx.strokeStyle = "rgba(0,0,0,.2)"; ctx.strokeRect(sx + 2, sy + 2, p - 4, p - 4);
    } else {
      // generic: tinted pad + icon
      ctx.fillStyle = "rgba(20,26,34,.55)"; ctx.fillRect(sx + 2, sy + 2, p - 4, p - 4);
      ctx.font = Math.floor(p * 0.62) + "px serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText(def.icon, cx, cy + 1);
      if (b.kind === "turret") {
        // barrel toward nearest enemy
        let ang = b.aim || 0;
        ctx.strokeStyle = "#2a2f36"; ctx.lineWidth = Math.max(2, p * 0.12);
        ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(ang) * p * 0.45, cy + Math.sin(ang) * p * 0.45); ctx.stroke();
      }
    }
    // damage bar
    if (b.hp < def.hp) {
      const fr = b.hp / def.hp;
      ctx.fillStyle = "rgba(0,0,0,.5)"; ctx.fillRect(sx + 2, sy - 1, p - 4, 3);
      ctx.fillStyle = fr > 0.5 ? "#5fd38a" : fr > 0.25 ? "#ffcf5c" : "#ff6b6b";
      ctx.fillRect(sx + 2, sy - 1, (p - 4) * fr, 3);
    }
  }

  function drawRaider(ctx, e, sx, sy, tile) {
    const r = tile * 0.34;
    ctx.fillStyle = e.hitFlash > 0 ? "#ffffff" : "#d8423a";
    ctx.beginPath(); ctx.arc(sx, sy, r, 0, 7); ctx.fill();
    ctx.strokeStyle = "#5e120f"; ctx.lineWidth = 2; ctx.stroke();
    ctx.fillStyle = "#3a0a08"; ctx.fillRect(sx - r * 0.4, sy - r * 0.2, r * 0.25, r * 0.25); ctx.fillRect(sx + r * 0.15, sy - r * 0.2, r * 0.25, r * 0.25);
    // hp bar
    const fr = e.hp / e.maxhp;
    ctx.fillStyle = "rgba(0,0,0,.6)"; ctx.fillRect(sx - r, sy - r - 6, r * 2, 3);
    ctx.fillStyle = "#ff6b6b"; ctx.fillRect(sx - r, sy - r - 6, r * 2 * fr, 3);
  }

  function drawPlayer(ctx, G, sx, sy, tile) {
    const p = G.player, r = tile * 0.34;
    // shadow
    ctx.fillStyle = "rgba(0,0,0,.3)"; ctx.beginPath(); ctx.ellipse(sx, sy + r * 0.7, r * 0.9, r * 0.4, 0, 0, 7); ctx.fill();
    // body
    ctx.fillStyle = p.sleeping ? "#7da0c0" : "#e7c25a";
    ctx.beginPath(); ctx.arc(sx, sy, r, 0, 7); ctx.fill();
    ctx.strokeStyle = "#1c2530"; ctx.lineWidth = 2; ctx.stroke();
    // facing pip
    ctx.fillStyle = "#1c2530";
    ctx.beginPath(); ctx.arc(sx + Math.cos(p.face) * r * 0.55, sy + Math.sin(p.face) * r * 0.55, r * 0.22, 0, 7); ctx.fill();
    // sleeping z
    if (p.sleeping) { ctx.fillStyle = "#cfe0ff"; ctx.font = (tile * 0.5) + "px serif"; ctx.textAlign = "center"; ctx.fillText("z", sx + r, sy - r); }
    // gather/action progress ring
    if (p.action && p.action.type === "gather" && p.action.dur) {
      const frac = RW.clamp(p.action.t / p.action.dur, 0, 1);
      ctx.strokeStyle = "#5db0ff"; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(sx, sy, r + 5, -Math.PI / 2, -Math.PI / 2 + frac * 2 * Math.PI); ctx.stroke();
    }
    // carry pip
    const carried = RW.carryTotal(p);
    if (carried > 0) { ctx.fillStyle = "#fff"; ctx.font = (tile * 0.34) + "px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "bottom"; ctx.fillText("🎒", sx, sy - r - 2); }
  }

})(window.RW);

/* Dependency-free force-directed graph on <canvas> for the mechanics map.
 * Graph.mount(canvas, {nodes, edges, colors, onNode}) -> { stop() }
 *   nodes: [{id, label, type}]
 *   edges: [{from, to, kind}]
 *   colors: { node:type->css, edge:kind->css }
 * Supports drag nodes, pan (drag bg), zoom (wheel), click node -> onNode(id).
 */
(function (global) {
  function mount(canvas, opts) {
    const ctx = canvas.getContext("2d");
    const colors = opts.colors || { node: {}, edge: {} };
    const onNode = opts.onNode || function () {};
    let W = 0, H = 0, DPR = Math.min(global.devicePixelRatio || 1, 2);

    const nodes = opts.nodes.map((n, idx) => ({
      ...n,
      x: Math.cos(idx) * 120 + 300 + (idx % 7) * 7,
      y: Math.sin(idx) * 120 + 220 + (idx % 5) * 9,
      vx: 0, vy: 0, r: 18
    }));
    const index = new Map(nodes.map(n => [n.id, n]));
    const edges = opts.edges.filter(e => index.has(e.from) && index.has(e.to));
    // degree -> node radius
    edges.forEach(e => { index.get(e.from).r += 1.4; index.get(e.to).r += 1.4; });

    const view = { x: 0, y: 0, k: 1 };
    let drag = null, panning = false, last = null, hover = null, downPos = null, alpha = 1;

    function resize() {
      const rect = canvas.getBoundingClientRect();
      W = rect.width; H = rect.height;
      canvas.width = W * DPR; canvas.height = H * DPR;
      ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    }
    resize();
    const ro = new ResizeObserver(resize); ro.observe(canvas);

    function step() {
      const kRep = 5200, kSpring = 0.015, rest = 110, center = 0.012, damp = 0.86;
      for (let a = 0; a < nodes.length; a++) {
        const A = nodes[a];
        for (let b = a + 1; b < nodes.length; b++) {
          const B = nodes[b];
          let dx = A.x - B.x, dy = A.y - B.y;
          let d2 = dx * dx + dy * dy || 0.01;
          let d = Math.sqrt(d2);
          let f = (kRep * alpha) / d2;
          let fx = (dx / d) * f, fy = (dy / d) * f;
          A.vx += fx; A.vy += fy; B.vx -= fx; B.vy -= fy;
        }
      }
      edges.forEach(e => {
        const A = index.get(e.from), B = index.get(e.to);
        let dx = B.x - A.x, dy = B.y - A.y;
        let d = Math.sqrt(dx * dx + dy * dy) || 0.01;
        let f = kSpring * (d - rest);
        let fx = (dx / d) * f, fy = (dy / d) * f;
        A.vx += fx; A.vy += fy; B.vx -= fx; B.vy -= fy;
      });
      const cx = W / 2, cy = H / 2;
      nodes.forEach(n => {
        if (n === drag) return;
        n.vx += (cx - n.x) * center * alpha;
        n.vy += (cy - n.y) * center * alpha;
        n.vx *= damp; n.vy *= damp;
        n.x += n.vx; n.y += n.vy;
      });
      alpha *= 0.992;
      if (alpha < 0.03) alpha = 0.03;
    }

    function toWorld(px, py) {
      return { x: (px - view.x) / view.k, y: (py - view.y) / view.k };
    }
    function hit(px, py) {
      const p = toWorld(px, py);
      for (let i = nodes.length - 1; i >= 0; i--) {
        const n = nodes[i];
        if ((p.x - n.x) ** 2 + (p.y - n.y) ** 2 <= (n.r + 4) ** 2) return n;
      }
      return null;
    }

    function arrow(A, B, color) {
      const dx = B.x - A.x, dy = B.y - A.y;
      const d = Math.sqrt(dx * dx + dy * dy) || 1;
      const ux = dx / d, uy = dy / d;
      const sx = A.x + ux * A.r, sy = A.y + uy * A.r;
      const ex = B.x - ux * B.r, ey = B.y - uy * B.r;
      ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = 1.6;
      ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(ex, ey); ctx.stroke();
      const a = Math.atan2(ey - sy, ex - sx), h = 7;
      ctx.beginPath();
      ctx.moveTo(ex, ey);
      ctx.lineTo(ex - h * Math.cos(a - 0.4), ey - h * Math.sin(a - 0.4));
      ctx.lineTo(ex - h * Math.cos(a + 0.4), ey - h * Math.sin(a + 0.4));
      ctx.closePath(); ctx.fill();
    }

    function draw() {
      ctx.clearRect(0, 0, W, H);
      ctx.save();
      ctx.translate(view.x, view.y); ctx.scale(view.k, view.k);

      edges.forEach(e => {
        const c = (colors.edge && colors.edge[e.kind]) || "#5b667d";
        const dim = hover && !(e.from === hover.id || e.to === hover.id);
        ctx.globalAlpha = hover ? (dim ? 0.12 : 1) : 0.7;
        arrow(index.get(e.from), index.get(e.to), c);
      });
      ctx.globalAlpha = 1;

      nodes.forEach(n => {
        const c = (colors.node && colors.node[n.type]) || "#6ea8fe";
        const dimmed = hover && hover !== n &&
          !edges.some(e => (e.from === hover.id && e.to === n.id) || (e.to === hover.id && e.from === n.id));
        ctx.globalAlpha = hover ? (dimmed ? 0.25 : 1) : 1;
        ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2);
        ctx.fillStyle = "#12151c"; ctx.fill();
        ctx.lineWidth = n === hover ? 3 : 2; ctx.strokeStyle = c; ctx.stroke();
        ctx.fillStyle = "#e7ebf3";
        ctx.font = "12px -apple-system, Segoe UI, sans-serif";
        ctx.textAlign = "center"; ctx.textBaseline = "top";
        ctx.fillText(n.label, n.x, n.y + n.r + 3);
      });
      ctx.globalAlpha = 1;
      ctx.restore();
    }

    let raf;
    function loop() { step(); draw(); raf = requestAnimationFrame(loop); }
    loop();

    // ---- interaction ----
    function pos(ev) {
      const r = canvas.getBoundingClientRect();
      return { x: ev.clientX - r.left, y: ev.clientY - r.top };
    }
    canvas.addEventListener("mousedown", ev => {
      const p = pos(ev); downPos = p;
      const n = hit(p.x, p.y);
      if (n) { drag = n; alpha = Math.max(alpha, 0.6); }
      else { panning = true; }
      last = p;
    });
    // mousemove/up live on window (drag/pan must keep working off-canvas), so they
    // MUST be removed in stop() — otherwise every visit to the graph and back leaks
    // a pair of handlers that hit-test a detached canvas on every pointer move.
    const onMove = ev => {
      const p = pos(ev);
      if (drag) { const w = toWorld(p.x, p.y); drag.x = w.x; drag.y = w.y; drag.vx = drag.vy = 0; }
      else if (panning) { view.x += p.x - last.x; view.y += p.y - last.y; }
      else { const n = hit(p.x, p.y); hover = n; canvas.style.cursor = n ? "pointer" : "grab"; }
      last = p;
    };
    const onUp = ev => {
      const p = pos(ev);
      if (downPos && Math.hypot(p.x - downPos.x, p.y - downPos.y) < 4) {
        const n = hit(p.x, p.y); if (n) onNode(n.id);
      }
      drag = null; panning = false; downPos = null;
    };
    global.addEventListener("mousemove", onMove);
    global.addEventListener("mouseup", onUp);
    canvas.addEventListener("wheel", ev => {
      ev.preventDefault();
      const p = pos(ev), w = toWorld(p.x, p.y);
      const f = ev.deltaY < 0 ? 1.1 : 0.9;
      view.k = Math.max(0.3, Math.min(3, view.k * f));
      view.x = p.x - w.x * view.k; view.y = p.y - w.y * view.k;
    }, { passive: false });

    return {
      stop() {
        cancelAnimationFrame(raf);
        ro.disconnect();
        global.removeEventListener("mousemove", onMove);
        global.removeEventListener("mouseup", onUp);
      }
    };
  }

  global.Graph = { mount };
})(window);

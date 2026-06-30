/* GDD_BOOK frontend controller. Loads gdd.json, renders the book, handles
 * navigation, the mechanics graph, the wiki, in-place editing, and AI block
 * generation (Anthropic API or local Ollama). No build step, no dependencies. */
(function () {
  "use strict";

  const CATEGORIES = [
    ["foundation", "Foundation"],
    ["gameplay", "Gameplay"],
    ["world", "World"],
    ["presentation", "Presentation"],
    ["production", "Production"]
  ];
  const STATUSES = ["draft", "ai", "review", "approved"];
  const STATUS_COLOR = {
    draft: "var(--st-draft)", ai: "var(--st-ai)",
    review: "var(--st-review)", approved: "var(--st-approved)"
  };
  const REL_KINDS = ["feeds", "requires", "unlocks", "affects", "synergizes", "conflicts"];
  const REL_COLOR = {
    feeds: "var(--rel-feeds)", requires: "var(--rel-requires)", unlocks: "var(--rel-unlocks)",
    affects: "var(--rel-affects)", synergizes: "var(--rel-synergizes)", conflicts: "var(--rel-conflicts)"
  };
  const TYPE_COLOR = {
    core: "#6ea8fe", secondary: "#7ce7c4", meta: "#b98cf0",
    economy: "#f0b66b", progression: "#6ff0d6", social: "#f08a8a"
  };

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };

  const state = { model: null, cfg: loadCfg(), resolvers: null, dirty: false, graph: null, fileHash: 0, undo: [] };

  // cheap djb2 content hash — used to detect whether gdd.json changed on disk
  // since a local draft was taken, so a stale draft never clobbers a newer file.
  function hashModel(m) {
    const s = JSON.stringify(m);
    let h = 5381;
    for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
    return h;
  }

  /* ---------------- load ---------------- */
  async function boot() {
    try {
      const res = await fetch("gdd.json?_=" + Date.now());
      if (!res.ok) throw new Error(res.status);
      state.model = normalize(await res.json());
    } catch (e) {
      $("#content").innerHTML =
        `<div class="empty"><h2>Couldn't load <code>gdd.json</code></h2>
         <p>Open the book via the bundled server (<code>/gdd_build run</code>),
         not by double-clicking the file — browsers block <code>fetch</code> on <code>file://</code>.</p>
         <p style="color:var(--danger)">${e.message}</p></div>`;
      return;
    }
    restoreDraft();
    rebuild();
    wireChrome();
    window.addEventListener("hashchange", route);
    route();
  }

  function normalize(m) {
    m.meta = m.meta || {}; m.concept = m.concept || {};
    m.sections = m.sections || []; m.mechanics = m.mechanics || []; m.wiki = m.wiki || [];
    return m;
  }

  function rebuild() {
    buildResolvers();
    buildNav();
    document.title = (state.model.meta.title || "GDD_BOOK") + " — GDD_BOOK";
    $("#brand-title").textContent = state.model.meta.title || "GDD_BOOK";
    $("#brand-sub").textContent = "v" + (state.model.meta.version || "0.1.0");
    updateBackendPill();
  }

  function buildResolvers() {
    const wiki = new Map(), sections = new Map(), mechanics = new Map();
    state.model.wiki.forEach(w => { wiki.set((w.title || "").toLowerCase(), { id: w.id, title: w.title }); wiki.set((w.id || "").toLowerCase(), { id: w.id, title: w.title }); });
    state.model.sections.forEach(s => sections.set(s.id, s.title));
    state.model.mechanics.forEach(x => mechanics.set(x.id, x.name));
    state.resolvers = { wiki, sections, mechanics };
  }

  /* ---------------- nav ---------------- */
  function buildNav() {
    const nav = $("#nav"); nav.innerHTML = "";
    CATEGORIES.forEach(([cat, label]) => {
      const items = state.model.sections
        .filter(s => (s.category || "foundation") === cat)
        .sort((a, b) => (a.order || 0) - (b.order || 0));
      if (!items.length) return;
      const g = el("div", "nav-group");
      g.appendChild(el("div", "nav-group-title", label));
      items.forEach(s => g.appendChild(navItem("section", s.id, s.title, s.status)));
      nav.appendChild(g);
    });
    if (state.model.mechanics.length) {
      const g = el("div", "nav-group");
      g.appendChild(el("div", "nav-group-title", "Mechanics"));
      state.model.mechanics.forEach(x => g.appendChild(navItem("mechanic", x.id, x.name, x.status)));
      nav.appendChild(g);
    }
  }
  function navItem(kind, id, title, status) {
    const b = el("button", "nav-item");
    b.dataset.route = `${kind}/${id}`;
    const dot = el("span", "dot"); dot.style.background = STATUS_COLOR[status] || STATUS_COLOR.draft;
    b.appendChild(dot); b.appendChild(document.createTextNode(title));
    b.onclick = () => location.hash = `#/${kind}/${id}`;
    return b;
  }
  function markActive(routeKey) {
    $$(".nav-item").forEach(b => b.classList.toggle("active", b.dataset.route === routeKey));
  }

  /* ---------------- routing ---------------- */
  function route() {
    const h = location.hash.replace(/^#\/?/, "");
    const [kind, id] = h.split("/");
    closeDrawer();
    if (state.graph) { state.graph.stop(); state.graph = null; }
    if (!kind || kind === "home") return renderHome();
    if (kind === "graph") return renderGraph();
    if (kind === "wiki" && !id) return renderWikiIndex();
    if (kind === "wiki") return renderWikiEntry(id);
    if (kind === "section") return renderBlock("section", id);
    if (kind === "mechanic") return renderBlock("mechanic", id);
    renderHome();
  }
  function crumbs(parts) { $("#crumbs").innerHTML = parts.map((p, i) => i === parts.length - 1 ? `<b>${p}</b>` : p).join(" / "); }

  /* ---------------- views ---------------- */
  function renderHome() {
    markActive("");
    crumbs(["Home"]);
    const c = state.model.concept, m = state.model.meta;
    const card = (h, body) => `<div class="card"><h4>${h}</h4>${body}</div>`;
    const chips = a => `<div class="chips">${(a || []).map(x => `<span class="chip">${esc(x)}</span>`).join("") || "<span class='todo'>—</span>"}</div>`;
    const stats = blockStatusBar();
    const v = el("div", "view");
    v.innerHTML = `
      <div class="concept-hero">
        <h1>${esc(m.title || "Untitled Game")}</h1>
        <p class="concept-pitch">${esc(c.pitch || "No pitch yet — run /gdd_build to draft one.")}</p>
      </div>
      <div class="progress-row" title="Block status mix">${stats.bar}</div>
      <div class="concept-grid">
        ${card("Genre", `<div>${esc(c.genre || "—")}</div>`)}
        ${card("Platforms", chips(c.platforms))}
        ${card("Audience", `<div>${esc(c.audience || "—")}</div>`)}
        ${card("Pillars", chips(c.pillars))}
        ${card("USP", chips(c.usp))}
        ${card("Status", `<div>${stats.legend}</div>`)}
      </div>
      <p class="hint">${state.model.sections.length} sections · ${state.model.mechanics.length} mechanics · ${state.model.wiki.length} wiki entries</p>`;
    setContent(v);
  }

  function blockStatusBar() {
    const all = [...state.model.sections, ...state.model.mechanics];
    const counts = { draft: 0, ai: 0, review: 0, approved: 0 };
    all.forEach(b => counts[b.status] = (counts[b.status] || 0) + 1);
    const total = all.length || 1;
    const bar = STATUSES.map(s => counts[s] ? `<span style="flex:${counts[s]};background:${STATUS_COLOR[s]}" title="${s}: ${counts[s]}"></span>` : "").join("");
    const legend = STATUSES.map(s => `<span class="chip" style="border-color:${STATUS_COLOR[s]}">${s}: ${counts[s] || 0}</span>`).join(" ");
    return { bar, legend, counts, total };
  }

  function findBlock(kind, id) {
    return kind === "section"
      ? state.model.sections.find(s => s.id === id)
      : state.model.mechanics.find(x => x.id === id);
  }

  function renderBlock(kind, id) {
    const b = findBlock(kind, id);
    if (!b) return notFound();
    markActive(`${kind}/${id}`);
    const title = kind === "section" ? b.title : b.name;
    crumbs([kind === "section" ? "Section" : "Mechanic", title]);

    const v = el("div", "view");
    const head = el("div", "block-head");
    head.innerHTML = `<h1>${esc(title)}</h1><span class="badge ${b.status}">${b.status}</span>`;
    if (kind === "mechanic") head.innerHTML += `<span class="chip" style="border-color:${TYPE_COLOR[b.type] || "var(--line)"}">${esc(b.type || "mechanic")}</span>`;
    v.appendChild(head);

    if (kind === "mechanic" && b.summary) v.appendChild(el("p", "concept-pitch", esc(b.summary)));

    const actions = el("div", "block-actions");
    actions.appendChild(actBtn("✎ Edit", () => editBlock(kind, id)));
    actions.appendChild(actBtn("✨ Ask AI", () => openAsk(kind, id)));
    if (kind === "mechanic") actions.appendChild(actBtn("🕸 In graph", () => location.hash = "#/graph"));
    v.appendChild(actions);

    const prose = el("div", "prose");
    prose.innerHTML = MD.render(b.body || "_No content yet._", state.resolvers);
    v.appendChild(prose);

    if (kind === "mechanic") v.appendChild(relationsBox(b));
    v.appendChild(backlinksBox(kind, id, title));
    setContent(v);
  }

  function relationsBox(m) {
    const box = el("div", "relations-box");
    box.innerHTML = "<h4>Relationships</h4>";
    const out = (m.relations || []);
    const incoming = [];
    state.model.mechanics.forEach(o => (o.relations || []).forEach(r => { if (r.to === m.id) incoming.push({ from: o.id, kind: r.kind, note: r.note }); }));
    if (!out.length && !incoming.length) { box.innerHTML += `<p class="hint">No relations declared. Add some so this appears in the graph.</p>`; return box; }
    out.forEach(r => box.appendChild(relLine(m.name, r.kind, nameOf(r.to), r.to, r.note, "→")));
    incoming.forEach(r => box.appendChild(relLine(nameOf(r.from), r.kind, m.name, r.from, r.note, "←")));
    return box;
  }
  function relLine(a, kind, b, targetId, note, dir) {
    const line = el("div", "rel-line");
    const k = el("span", "rel-kind", kind); k.style.color = REL_COLOR[kind] || "var(--txt-dim)"; k.style.borderColor = REL_COLOR[kind] || "var(--line)";
    line.appendChild(k);
    const txt = el("span"); txt.innerHTML = `${esc(a)} <span style="color:var(--txt-faint)">${dir}</span> <span class="xref" data-mechanic="${escAttr(targetId)}">${esc(b)}</span>${note ? ` — <span style="color:var(--txt-faint)">${esc(note)}</span>` : ""}`;
    line.appendChild(txt);
    return line;
  }
  function nameOf(id) { const m = state.model.mechanics.find(x => x.id === id); return m ? m.name : id; }

  function backlinksBox(kind, id, title) {
    const refs = computeBacklinks(kind, id, title);
    const box = el("div", "backlinks-box");
    box.innerHTML = "<h4>Referenced by</h4>";
    if (!refs.length) { box.innerHTML += `<p class="hint">Nothing links here yet.</p>`; return box; }
    refs.forEach(r => {
      const a = el("div", "rel-line");
      a.innerHTML = `<span class="xref" data-${r.kind}="${escAttr(r.id)}">${esc(r.label)}</span>`;
      box.appendChild(a);
    });
    return box;
  }

  function computeBacklinks(kind, id, title) {
    const refs = [];
    const needleX = new RegExp(`\\b${kind}:${id}\\b`, "i");
    const needleW = title ? new RegExp(`\\[\\[\\s*${escapeReg(title)}\\s*(\\|[^\\]]*)?\\]\\]`, "i") : null;
    const scan = (block, blkKind, label) => {
      const body = block.body || "";
      const linkHit = (block.links || []).includes(`${kind}:${id}`);
      const xHit = needleX.test(body);
      const wHit = kind === "wiki" && needleW && needleW.test(body);
      if (linkHit || xHit || wHit) refs.push({ kind: blkKind, id: block.id, label });
    };
    state.model.sections.forEach(s => { if (!(kind === "section" && s.id === id)) scan(s, "section", s.title); });
    state.model.mechanics.forEach(m => { if (!(kind === "mechanic" && m.id === id)) scan(m, "mechanic", m.name); });
    state.model.wiki.forEach(w => { if (!(kind === "wiki" && w.id === id)) scan(w, "wiki", w.title); });
    return refs;
  }

  function notFound() { setContent(el("div", "empty", "<h2>Not found</h2><p>This entry doesn't exist in the current gdd.json.</p>")); }

  /* ---------------- graph ---------------- */
  function renderGraph() {
    markActive("graph"); crumbs(["Mechanics graph"]);
    const v = el("div", "view"); v.style.maxWidth = "100%";
    if (!state.model.mechanics.length) { setContent(el("div", "empty", "<h2>No mechanics yet</h2><p>Add mechanics with relations to see the graph.</p>")); return; }
    const wrap = el("div"); wrap.id = "graph-wrap";
    const canvas = el("canvas"); canvas.id = "graph-canvas"; wrap.appendChild(canvas);
    const legend = el("div", "graph-legend");
    legend.innerHTML = "<strong>Relations</strong>" + REL_KINDS.map(k => `<div class="lg"><span class="swatch" style="background:${REL_COLOR[k]}"></span>${k}</div>`).join("");
    wrap.appendChild(legend);
    wrap.appendChild(el("div", "graph-hint", "drag nodes · scroll to zoom · drag canvas to pan · click a node to open it"));
    v.appendChild(wrap);
    setContent(v);

    const nodes = state.model.mechanics.map(m => ({ id: m.id, label: m.name, type: m.type || "core" }));
    const edges = [];
    state.model.mechanics.forEach(m => (m.relations || []).forEach(r => edges.push({ from: m.id, to: r.to, kind: r.kind })));
    state.graph = Graph.mount(canvas, {
      nodes, edges,
      colors: { node: TYPE_COLOR, edge: rawColors(REL_COLOR) },
      onNode: id => location.hash = `#/mechanic/${id}`
    });
  }
  // graph canvas needs concrete colors, not CSS vars
  function rawColors(map) {
    const probe = document.createElement("span"); document.body.appendChild(probe);
    const out = {};
    for (const k in map) { probe.style.color = map[k]; out[k] = getComputedStyle(probe).color; }
    probe.remove(); return out;
  }

  /* ---------------- wiki ---------------- */
  function renderWikiIndex() {
    markActive("wiki"); crumbs(["Wiki"]);
    const v = el("div", "view");
    v.innerHTML = "<h1>Wiki</h1>";
    if (!state.model.wiki.length) { v.appendChild(el("p", "hint", "No wiki entries yet. Add lore, factions, items, or characters and link them with [[double brackets]].")); setContent(v); return; }
    const grid = el("div", "wiki-grid");
    state.model.wiki.forEach(w => {
      const card = el("div", "wiki-card");
      card.innerHTML = `<h3>${esc(w.title)}</h3><p>${esc(snippet(w.body))}</p>`;
      card.onclick = () => location.hash = `#/wiki/${w.id}`;
      grid.appendChild(card);
    });
    v.appendChild(grid); setContent(v);
  }
  function renderWikiEntry(id) {
    const w = state.model.wiki.find(x => x.id === id || (x.title || "").toLowerCase() === id.toLowerCase());
    if (!w) return notFound();
    markActive("wiki"); crumbs(["Wiki", w.title]);
    const v = el("div", "view");
    const head = el("div", "block-head"); head.innerHTML = `<h1>${esc(w.title)}</h1>`;
    v.appendChild(head);
    const actions = el("div", "block-actions");
    actions.appendChild(actBtn("✎ Edit", () => editWiki(w.id)));
    actions.appendChild(actBtn("✨ Ask AI", () => openAsk("wiki", w.id)));
    v.appendChild(actions);
    const prose = el("div", "prose"); prose.innerHTML = MD.render(w.body || "_No content yet._", state.resolvers);
    v.appendChild(prose);
    v.appendChild(backlinksBox("wiki", w.id, w.title));
    setContent(v);
  }

  /* ---------------- editing ---------------- */
  function editBlock(kind, id) {
    const b = findBlock(kind, id); if (!b) return;
    const v = el("div", "view editor");
    v.innerHTML = `<h2>Edit: ${esc(kind === "section" ? b.title : b.name)}</h2>`;
    const ta = el("textarea"); ta.value = b.body || ""; v.appendChild(ta);
    const row = el("div", "editor-row");
    const sel = statusSelect(b.status);
    row.appendChild(label("Status", sel));
    row.appendChild(actBtn("Cancel", () => route()));
    const save = el("button", "primary", "Save"); save.onclick = () => { b.body = ta.value; b.status = sel.value; touch(); route(); toast("Saved (in browser) — Export to write gdd.json"); };
    row.appendChild(save);
    v.appendChild(row);
    setContent(v); ta.focus();
  }
  function editWiki(id) {
    const w = state.model.wiki.find(x => x.id === id); if (!w) return;
    const v = el("div", "view editor");
    v.innerHTML = `<h2>Edit wiki: ${esc(w.title)}</h2>`;
    const ta = el("textarea"); ta.value = w.body || ""; v.appendChild(ta);
    const row = el("div", "editor-row");
    row.appendChild(actBtn("Cancel", () => route()));
    const save = el("button", "primary", "Save"); save.onclick = () => { w.body = ta.value; touch(); route(); toast("Saved (in browser) — Export to write gdd.json"); };
    row.appendChild(save); v.appendChild(row); setContent(v); ta.focus();
  }
  function statusSelect(cur) {
    const s = document.createElement("select");
    STATUSES.forEach(st => { const o = document.createElement("option"); o.value = st; o.textContent = st; if (st === cur) o.selected = true; s.appendChild(o); });
    return s;
  }
  function label(text, node) { const l = el("label"); l.style.cssText = "display:flex;gap:6px;align-items:center;color:var(--txt-dim);font-size:13px"; l.appendChild(document.createTextNode(text)); l.appendChild(node); return l; }

  /* ---------------- Ask AI drawer ---------------- */
  function openAsk(kind, id) {
    const b = kind === "wiki" ? state.model.wiki.find(x => x.id === id) : findBlock(kind, id);
    if (!b) return;
    const title = kind === "section" ? b.title : kind === "mechanic" ? b.name : b.title;
    $("#drawer-title").textContent = "Ask AI — " + title;
    const body = $("#drawer-body");
    if (state.cfg.backend === "off") {
      body.innerHTML = `<p>No AI backend configured.</p><button class="primary" id="ask-open-settings">Open Settings</button>`;
      $("#ask-open-settings").onclick = openSettings;
    } else {
      body.innerHTML = `
        <p class="hint">Backend: <b>${state.cfg.backend}</b> · ${esc(state.cfg.backend === "anthropic" ? state.cfg.anthropicModel : state.cfg.ollamaModel)}</p>
        <div class="intent-row">
          ${["draft", "expand", "propose", "critique", "questions"].map(i => `<button class="action" data-intent="${i}">${intentLabel(i)}</button>`).join("")}
        </div>
        <div id="ask-out"></div>`;
      $$("#drawer-body .intent-row .action").forEach(btn => btn.onclick = () => runAsk(kind, id, btn.dataset.intent));
    }
    $("#drawer").classList.add("open"); $("#drawer").setAttribute("aria-hidden", "false");
    $("#scrim").hidden = false;
  }
  function intentLabel(i) { return { draft: "✍ Draft", expand: "➕ Expand", propose: "💡 Propose", critique: "🔍 Critique", questions: "❓ Questions" }[i]; }

  async function runAsk(kind, id, intent) {
    const b = kind === "wiki" ? state.model.wiki.find(x => x.id === id) : findBlock(kind, id);
    const out = $("#ask-out");
    out.innerHTML = `<div class="ai-out ai-busy">Thinking…</div>`;
    try {
      const text = await callBackend(buildPrompt(b, kind, intent));
      const box = el("div", "ai-out"); box.innerHTML = MD.render(text, state.resolvers);
      out.innerHTML = "";
      out.appendChild(box);
      if (intent === "draft" || intent === "expand") {
        const row = el("div", "editor-row");
        const accept = el("button", "primary", intent === "expand" ? "Append to block" : "Use as block body");
        accept.onclick = () => {
          pushUndo(b);
          if (intent === "expand") b.body = (b.body || "").trim() + "\n\n" + text.trim();
          else b.body = text.trim();
          b.status = "ai"; touch(); closeDrawer(); route(); toastAction("Applied — Export to write gdd.json", "Undo", undoLast);
        };
        row.appendChild(accept);
        row.appendChild(actBtn("Discard", () => { out.innerHTML = ""; }));
        out.appendChild(row);
      } else if (intent === "propose") {
        // split on "### Proposal" headings; one accept control per proposal.
        // Tolerate heading-level (h2–h4) and spacing variation, case-insensitively,
        // so a model deviation doesn't collapse to one proposal or leak the heading into the body.
        const parts = text.split(/(?=^#{2,4}\s*Proposal)/mi).map(s => s.trim()).filter(Boolean);
        const real = parts.filter(p => /^#{2,4}\s*Proposal/i.test(p)); // drop any preamble before the first heading
        const proposals = real.length ? real : [text.trim()];
        const apply = md => {
          const body = md
            .replace(/^#{2,4}\s*Proposal[^\n]*(\n|$)/i, "")  // strip the "### Proposal" heading
            .replace(/^\s*\*Why:\*.*$/gmi, "")               // drop decision meta — the published body stays clean
            .replace(/^\s*\*Assumes:\*.*$/gmi, "")
            .trim();
          if (!body) return toast("Nothing to apply — proposal was empty.");
          pushUndo(b);
          b.body = body; b.status = "ai"; touch(); closeDrawer(); route(); toastAction("Applied — Export to write gdd.json", "Undo", undoLast);
        };
        const recIdx = proposals.findIndex(p => /Recommended/i.test(p.split("\n")[0]));
        const row = el("div", "editor-row");
        const useRec = el("button", "primary", recIdx >= 0 ? "Use Recommended as block body" : "Use first proposal as block body");
        useRec.onclick = () => apply(proposals[recIdx >= 0 ? recIdx : 0]);
        row.appendChild(useRec);
        row.appendChild(actBtn("Discard", () => { out.innerHTML = ""; }));
        out.appendChild(row);
        proposals.forEach((p, i) => {
          const r = el("div", "editor-row");
          r.appendChild(actBtn((i === recIdx ? "★ " : "") + "Use proposal " + (i + 1), () => apply(p)));
          out.appendChild(r);
        });
      }
    } catch (e) {
      out.innerHTML = `<div class="ai-out" style="color:var(--danger)">Request failed: ${esc(e.message)}<br><span class="hint">Check the backend, model name, key, and (for Ollama) that the server is running with CORS allowed.</span></div>`;
    }
  }

  function buildPrompt(b, kind, intent) {
    const c = state.model.concept;
    const title = kind === "section" ? b.title : kind === "mechanic" ? b.name : b.title;
    const linked = (b.links || []).map(l => l.replace(/^(section|mechanic):/, "")).join(", ");
    const ctx = [
      `Game: ${state.model.meta.title || "Untitled"}`,
      c.pitch ? `Pitch: ${c.pitch}` : "",
      c.genre ? `Genre: ${c.genre}` : "",
      (c.pillars && c.pillars.length) ? `Design pillars: ${c.pillars.join("; ")}` : "",
      `This is the GDD ${kind} titled "${title}".`,
      kind === "mechanic" && b.type ? `Mechanic type: ${b.type}.` : "",
      linked ? `Related blocks: ${linked}.` : "",
      "",
      "Current content:",
      (b.body || "(empty)")
    ].filter(Boolean).join("\n");

    const task = {
      draft: "Write a strong first draft of this block. Be concrete and specific to THIS game, not generic. Use clear Markdown. No preamble — output only the block content.",
      expand: "Deepen and expand the current content while preserving its intent and voice. Add specifics, edge cases, and tuning details. Output only the new/expanded Markdown to append.",
      propose: "Propose 2-3 concrete, ready-to-use candidate contents for THIS block, grounded in this specific game, its pillars, and any linked blocks — never generic. Make each a finished version the author could paste in, not a hint. For each proposal output: a level-3 Markdown heading starting with '### Proposal', then the pasteable block body, then one italic line '*Why:* <rationale>' and one italic line '*Assumes:* <the single load-bearing assumption>'. ONLY when the concept clearly supports one proposal over the others, mark that single one '### Proposal (Recommended)'. If the concept under-determines the block — no proposal is best-supported — recommend NOTHING (omit the Recommended marker entirely), say so, and lower confidence rather than inventing detail.",
      critique: "Critique this block as an experienced game designer: holes, contradictions, unstated assumptions, scope risks. Output a concise Markdown bullet list.",
      questions: "List the 5–8 sharpest open design questions that, if answered, would most improve this block. Output a numbered Markdown list, each with a one-line note on why it matters."
    }[intent];

    return ctx + "\n\n---\nTask: " + task;
  }

  /* ---------------- AI backends ---------------- */
  async function callBackend(prompt) {
    if (state.cfg.backend === "anthropic") return callAnthropic(prompt);
    if (state.cfg.backend === "ollama") return callOllama(prompt);
    throw new Error("No backend configured");
  }
  async function callAnthropic(prompt) {
    if (!state.cfg.anthropicKey) throw new Error("Set an Anthropic API key in Settings");
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": state.cfg.anthropicKey,
        "anthropic-version": "2023-06-01",
        "anthropic-dangerous-direct-browser-access": "true"
      },
      body: JSON.stringify({
        model: state.cfg.anthropicModel || "claude-opus-4-8",
        max_tokens: 1800,
        messages: [{ role: "user", content: prompt }]
      })
    });
    if (!res.ok) throw new Error("Anthropic " + res.status + ": " + (await res.text()).slice(0, 200));
    const data = await res.json();
    return (data.content || []).map(p => p.text || "").join("").trim();
  }
  async function callOllama(prompt) {
    const url = (state.cfg.ollamaUrl || "http://localhost:11434").replace(/\/$/, "");
    const res = await fetch(url + "/api/chat", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        model: state.cfg.ollamaModel || "llama3.1",
        messages: [{ role: "user", content: prompt }],
        stream: false
      })
    });
    if (!res.ok) throw new Error("Ollama " + res.status + ": " + (await res.text()).slice(0, 200));
    const data = await res.json();
    return ((data.message && data.message.content) || "").trim();
  }

  /* ---------------- settings ---------------- */
  function loadCfg() {
    let c = {};
    try { c = JSON.parse(localStorage.getItem("gddbook-cfg") || "{}"); } catch (e) {}
    return Object.assign({ backend: "off", anthropicKey: "", anthropicModel: "claude-opus-4-8", ollamaUrl: "http://localhost:11434", ollamaModel: "llama3.1" }, c);
  }
  function saveCfg() { localStorage.setItem("gddbook-cfg", JSON.stringify(state.cfg)); updateBackendPill(); }
  function openSettings() {
    closeDrawer();
    $("#cfg-backend").value = state.cfg.backend;
    $("#cfg-anthropic-key").value = state.cfg.anthropicKey;
    $("#cfg-anthropic-model").value = state.cfg.anthropicModel;
    $("#cfg-ollama-url").value = state.cfg.ollamaUrl;
    $("#cfg-ollama-model").value = state.cfg.ollamaModel;
    toggleBackendGroups();
    $("#settings-modal").hidden = false;
  }
  function toggleBackendGroups() {
    const v = $("#cfg-backend").value;
    $$(".backend-group").forEach(g => g.hidden = g.dataset.for !== v);
  }
  function updateBackendPill() {
    const p = $("#backend-pill");
    if (state.cfg.backend === "off") { p.textContent = "AI: off"; p.classList.remove("on"); }
    else { p.textContent = "AI: " + state.cfg.backend; p.classList.add("on"); }
  }

  /* ---------------- export / persistence ---------------- */
  function touch() { state.dirty = true; saveDraft(); }
  // One draft slot per origin — serve.py serves one book per origin, so a constant
  // key avoids both the empty-title collision and orphaning a draft on a rename.
  function draftKey() { return "gddbook-draft"; }
  function saveDraft() {
    try {
      const payload = Object.assign({}, state.model, { _baseHash: state.fileHash, _savedAt: new Date().toISOString() });
      localStorage.setItem(draftKey(), JSON.stringify(payload));
    } catch (e) {}
  }
  function useDraft(draft) { delete draft._baseHash; delete draft._savedAt; state.model = normalize(draft); state.dirty = true; }
  function restoreDraft() {
    state.fileHash = hashModel(state.model); // hash of the just-fetched file, before any draft
    let draft;
    try { const raw = localStorage.getItem(draftKey()); if (!raw) return; draft = JSON.parse(raw); } catch (e) { return; }
    if (!draft || !draft.meta) return;
    if (draft._baseHash === state.fileHash) {
      // file is unchanged since the draft was taken → safe to restore in place
      useDraft(draft);
      setTimeout(() => toastAction("Restored unsaved local edits.", "Discard", discardDraft), 400);
    } else {
      // gdd.json changed on disk since the draft (e.g. /gdd_build regenerated it).
      // Do NOT auto-clobber — let the reader choose, via a banner that doesn't time out.
      setTimeout(() => persistentChoice(
        "Local edits differ from a newer gdd.json on disk.",
        "Keep my edits", () => { useDraft(draft); rebuild(); route(); },
        "Use the file", discardDraft
      ), 500);
    }
  }
  function discardDraft() { try { localStorage.removeItem(draftKey()); } catch (e) {} location.reload(); }

  function exportJson() {
    state.model.meta.updated = new Date().toISOString().slice(0, 10);
    const blob = new Blob([JSON.stringify(state.model, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = "gdd.json"; a.click();
    URL.revokeObjectURL(a.href);
    // Export is the commit point: the edits now live in the downloaded file, so drop
    // the local draft. Prevents the just-exported content from later flagging a false
    // conflict against the file the user is about to replace.
    try { localStorage.removeItem(draftKey()); } catch (e) {}
    state.dirty = false;
    toast("Downloaded gdd.json — replace the file in your GDD_BOOK/ folder. Local draft cleared.");
  }

  /* ---------------- search ---------------- */
  function search(q) {
    q = q.trim().toLowerCase();
    if (!q) { $$(".nav-item").forEach(i => i.style.display = ""); $$(".nav-group").forEach(g => g.style.display = ""); return; }
    $$(".nav-item").forEach(i => {
      const route = i.dataset.route, [kind, id] = route.split("/");
      const blk = kind === "section" ? state.model.sections.find(s => s.id === id) : state.model.mechanics.find(m => m.id === id);
      const hay = (i.textContent + " " + ((blk && blk.body) || "") + " " + ((blk && blk.tags) || []).join(" ")).toLowerCase();
      i.style.display = hay.includes(q) ? "" : "none";
    });
    $$(".nav-group").forEach(g => { g.style.display = $$(".nav-item", g).some(i => i.style.display !== "none") ? "" : "none"; });
  }

  /* ---------------- chrome wiring ---------------- */
  function wireChrome() {
    $("#btn-settings").onclick = openSettings;
    $("#settings-close").onclick = () => $("#settings-modal").hidden = true;
    $("#cfg-backend").onchange = toggleBackendGroups;
    $("#settings-save").onclick = () => {
      state.cfg = {
        backend: $("#cfg-backend").value,
        anthropicKey: $("#cfg-anthropic-key").value.trim(),
        anthropicModel: $("#cfg-anthropic-model").value.trim() || "claude-opus-4-8",
        ollamaUrl: $("#cfg-ollama-url").value.trim() || "http://localhost:11434",
        ollamaModel: $("#cfg-ollama-model").value.trim() || "llama3.1"
      };
      saveCfg(); $("#settings-modal").hidden = true; toast("Settings saved");
    };
    $("#btn-export").onclick = exportJson;
    $("#nav-graph").onclick = () => location.hash = "#/graph";
    $("#nav-wiki").onclick = () => location.hash = "#/wiki";
    $("#drawer-close").onclick = closeDrawer;
    $("#scrim").onclick = closeDrawer;
    $("#menu-toggle").onclick = () => $("#sidebar").classList.toggle("open");
    $("#search").oninput = e => search(e.target.value);
    document.addEventListener("keydown", e => {
      if (e.key === "/" && document.activeElement.tagName !== "INPUT" && document.activeElement.tagName !== "TEXTAREA") { e.preventDefault(); $("#search").focus(); }
      if (e.key === "Escape") { closeDrawer(); $("#settings-modal").hidden = true; }
    });
    // cross-ref + wikilink delegation
    $("#content").addEventListener("click", e => {
      const x = e.target.closest("[data-section],[data-mechanic],[data-wiki]");
      if (!x) return;
      if (x.dataset.section) location.hash = `#/section/${x.dataset.section}`;
      else if (x.dataset.mechanic) location.hash = `#/mechanic/${x.dataset.mechanic}`;
      else if (x.dataset.wiki) {
        if (x.classList.contains("broken")) return toast("No wiki entry “" + x.dataset.wiki + "” yet.");
        location.hash = `#/wiki/${x.dataset.wiki}`;
      }
    });
  }
  function closeDrawer() {
    $("#drawer").classList.remove("open"); $("#drawer").setAttribute("aria-hidden", "true"); $("#scrim").hidden = true;
  }

  /* ---------------- helpers ---------------- */
  function setContent(node) { const c = $("#content"); c.innerHTML = ""; c.appendChild(node); c.scrollTop = 0; }
  function actBtn(text, fn) { const b = el("button", "action", text); b.onclick = fn; return b; }
  function snippet(s) { s = (s || "").replace(/[#*`>\[\]]/g, "").replace(/\s+/g, " ").trim(); return s.length > 110 ? s.slice(0, 110) + "…" : s || "—"; }
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function escAttr(s) { return esc(s).replace(/"/g, "&quot;"); }
  function escapeReg(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
  let toastT;
  function toast(msg) { const t = $("#toast"); t.textContent = msg; t.hidden = false; clearTimeout(toastT); toastT = setTimeout(() => t.hidden = true, 3200); }
  function toastAction(msg, label, fn) {
    const t = $("#toast"); t.innerHTML = esc(msg) + " "; const b = el("button", "action", label); b.style.marginLeft = "8px";
    b.onclick = () => { t.hidden = true; fn(); }; t.appendChild(b); t.hidden = false;
    clearTimeout(toastT); toastT = setTimeout(() => t.hidden = true, 6000);
  }
  // A two-choice banner that does NOT auto-dismiss — for decisions the user must make
  // (e.g. local-edits-vs-newer-file conflict).
  function persistentChoice(msg, aLabel, aFn, bLabel, bFn) {
    const t = $("#toast"); t.innerHTML = esc(msg) + " ";
    const a = el("button", "action", aLabel); a.style.marginLeft = "8px";
    const b = el("button", "action", bLabel); b.style.marginLeft = "6px";
    a.onclick = () => { t.hidden = true; aFn(); };
    b.onclick = () => { t.hidden = true; bFn(); };
    t.appendChild(a); t.appendChild(b); t.hidden = false; clearTimeout(toastT);
  }
  // In-memory undo for AI block edits — capture before each mutation, surface via toast.
  function pushUndo(b) { state.undo.push({ b: b, body: b.body, status: b.status }); if (state.undo.length > 20) state.undo.shift(); }
  function undoLast() { const u = state.undo.pop(); if (!u) return; u.b.body = u.body; u.b.status = u.status; touch(); route(); toast("Reverted."); }

  boot();
})();

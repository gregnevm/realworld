// RealWorld — tools/process/lib.mjs : the PURE core of the process tooling (docs/process/README.md).
// Every export is a pure function of strings — no fs, no git, no clock — so tests/process.test.js pins it.
//   • godotDrift(src)        — Godot-3 API that models still emit (failure mode F1) + the Godot-4 fix;
//   • mdTable(md, headerRe)  — rows of the first markdown table whose header row matches;
//   • parsePr(body)          — sections + fields of a PR body written from .github/pull_request_template.md;
//   • classifyFiles(files)   — doc / product / ui / rules / art buckets of a diff;
//   • checkPr(body, files)   — the evidence gate (P2 «без доказу нема готово», P7 «нічого без стовпа»);
//   • reworkVerdict(rows)    — which gate to strengthen, from the owner's rework log (P10).

// ── F1: Godot 3 → 4 API drift ────────────────────────────────────────────────────────────────────────
// Only high-signal patterns: each one is a Godot-3 spelling that does not exist (or means something
// else) in 4.x. A line ending in `# drift-ok` is exempt (a project method that happens to share a name).
export const DRIFT = [
  [/\byield\s*\(/, "yield() → await <signal>"],
  [/\brand_range\s*\(/, "rand_range() → rng.randf_range() (лише seeded RNG)"],
  [/\bdeg2rad\s*\(/, "deg2rad() → deg_to_rad()"],
  [/\brad2deg\s*\(/, "rad2deg() → rad_to_deg()"],
  [/\bstepify\s*\(/, "stepify() → snapped()"],
  [/^\s*export\s*(\(|var\b)/, "export var → @export var"],
  [/^\s*onready\s+var\b/, "onready var → @onready var"],
  [/^\s*tool\s*$/, "tool → @tool"],
  [/\bsetget\b/, "setget → блоки set(value)/get"],
  [/\bKinematicBody(2D)?\b/, "KinematicBody → CharacterBody2D/3D"],
  [/\bSpatial\b/, "Spatial → Node3D"],
  [/\.instance\s*\(\s*\)/, ".instance() → .instantiate()"],
  [/\bPool(Byte|Int|Real|String|Vector2|Vector3|Color)Array\b/, "Pool*Array → Packed*Array"],
  [/\.connect\s*\(\s*"[^"]+"\s*,\s*self\s*,/, 'connect("sig", self, "m") → sig.connect(m)'],
  [/\bchange_scene\s*\(/, "change_scene() → change_scene_to_file()"],
  [/\bOS\.get_ticks_msec\b/, "OS.get_ticks_msec → Time.get_ticks_msec"],
  [/\bfuncref\s*\(/, "funcref() → Callable"],
  [/\b(to_json|parse_json)\s*\(/, "to_json/parse_json → JSON.stringify / JSON.parse_string"],
  [/\b(str2var|var2str)\s*\(/, "str2var/var2str → str_to_var/var_to_str"],
  [/\bFile\.new\s*\(/, "File.new() → FileAccess.open()"],
  [/\bDirectory\.new\s*\(/, "Directory.new() → DirAccess.open()"],
  [/\bVisualServer\b/, "VisualServer → RenderingServer"],
  [/\bmove_and_slide\s*\(\s*[A-Za-z_]/, "move_and_slide(v) → velocity = v; move_and_slide()"],
  [/\.empty\s*\(\s*\)/, ".empty() → .is_empty()"],
  [/\bBUTTON_(LEFT|RIGHT|MIDDLE)\b/, "BUTTON_* → MOUSE_BUTTON_*"],
];

/** Strip a GDScript line comment, ignoring `#` inside "..." / '...' strings. */
export function stripGdComment(line) {
  let q = "";
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (q) { if (ch === "\\") i++; else if (ch === q) q = ""; }
    else if (ch === '"' || ch === "'") q = ch;
    else if (ch === "#") return line.slice(0, i);
  }
  return line;
}

/** Code only: comment stripped and string literal contents blanked ("yield(" in a message is not a call). */
export function gdCode(line) {
  let out = "", q = "";
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (q) {
      if (ch === "\\") i++;
      else if (ch === q) { q = ""; out += ch; }
    } else if (ch === '"' || ch === "'") { q = ch; out += ch; }
    else if (ch === "#") break;
    else out += ch;
  }
  return out;
}

/** → [{line, hint, text}] for every Godot-3 spelling in a .gd source. */
export function godotDrift(src) {
  const out = [];
  src.split(/\r?\n/).forEach((raw, i) => {
    if (/#\s*drift-ok\b/.test(raw)) return;
    const code = gdCode(raw);
    for (const [re, hint] of DRIFT) if (re.test(code)) out.push({ line: i + 1, hint, text: raw.trim() });
  });
  return out;
}

// ── spec 0012 REQ-10: the sim never reads a clock or a system-seeded RNG ─────────────────────────────
// Time enters the game ONLY as an argument (Session → Sim.set_clock(now_ms)), the source being
// godot/scripts/clock.gd — the one file allowed to call Time.get_unix_time_from_system. These patterns are
// pinned against godot/tests/run_tests.gd `SIM_CLOCK_PATTERNS` by tests/process.test.js (one list, two
// enforcers: lint here, `_t_no_wallclock_in_sim` there). A line ending in `# clock-ok` is exempt.
export const SIM_CLOCK_BAN = [
  [/\bTime\./, "Time.* — час у sim дає лише Clock (clock.gd) через Session → Sim.set_clock(now_ms)"],
  [/\bOS\.get_\w*time\w*/, "OS.get_*time* — годинник лише через Clock"],
  [/\bOS\.get_unix\w*/, "OS.get_unix* — годинник лише через Clock"],
  [/\bEngine\.get_ticks_\w+/, "Engine.get_ticks_* — годинник лише через Clock"],
  [/\bEngine\.time_scale/, "Engine.time_scale — темп sim — аргумент dt, не глобальний масштаб"],
  [/\bDateTime\b/, "DateTime — дата лише з Clock.now_ms()"],
  [/\.randomize\s*\(/, "rng.randomize() сіє RNG годинником → rng.seed = <seed регіону> (лише seeded RNG)"],
];
// Global RNG calls (`randf()`, `randi_range()`, `randomize()`): a method call on a seeded rng (`rng.randf()`) is fine.
// The Godot twin of this pattern is run_tests `_t_no_global_rng` (it scans the whole product, UI included).
export const SIM_RNG_BAN = [
  [/(^|[^.\w])(randf|randi|randfn|randf_range|randi_range|randomize)\s*\(/, "глобальний RNG → seeded RandomNumberGenerator"],
];
/**
 * What the sim corpus does NOT include (paths relative to godot/; a trailing "/" = a directory prefix).
 * Everything else under godot/scripts/ (+ nothing outside it) is corpus — a NEW script is covered by default.
 * The exclusions are the view layer, where Time.get_ticks_msec drives pulses/camera shake (not sim time),
 * the frozen pre-refactor HUD, and clock.gd itself. Mirrored by run_tests.gd `SIM_CORPUS_EXCLUDE` (pinned).
 */
export const SIM_CORPUS_EXCLUDE = [
  "scripts/clock.gd", "scripts/ui/", "scripts/world_view.gd", "scripts/map_widget.gd", "scripts/main.gd", "newhud_main.gd",
];

/** @param {string} rel path of a file relative to godot/ (e.g. "scripts/sim/threats.gd") */
export function inSimCorpus(rel) {
  if (!rel.endsWith(".gd") || !rel.startsWith("scripts/")) return false;
  return !SIM_CORPUS_EXCLUDE.some((e) => (e.endsWith("/") ? rel.startsWith(e) : rel === e));
}

/** → [{line, hint, text}] for every clock / system-RNG call in a sim-corpus .gd source (comments and strings ignored). */
export function simClockDrift(src) {
  const out = [];
  src.split(/\r?\n/).forEach((raw, i) => {
    if (/#\s*clock-ok\b/.test(raw)) return;
    const code = gdCode(raw);
    for (const [re, hint] of [...SIM_CLOCK_BAN, ...SIM_RNG_BAN]) if (re.test(code)) out.push({ line: i + 1, hint, text: raw.trim() });
  });
  return out;
}

// a `func name(` declaration line (annotations and `static` allowed) — a lambda `func(` does not end a function scope
const FUNC_DECL_RE = /^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?func\s+\w/;
/**
 * «RandomNumberGenerator без явного seed» (REQ-10): Godot 4 seeds a fresh RNG from the system, so a
 * `RandomNumberGenerator.new()` that never gets `<name>.seed = …` / `<name>.state = …` is wall-clock randomness.
 *   • a FUNCTION-LOCAL generator (`var rng := RandomNumberGenerator.new()` indented) must be seeded LATER IN THE SAME
 *     FUNCTION (up to the next `func`): a same-named `rng.seed = …` in another function seeds a different generator;
 *   • a MEMBER (class-level `var x := …`, or `s.x = RandomNumberGenerator.new()`) may be seeded in any corpus file
 *     (sim.gd declares `env_rng`, sim/environment.gd seeds it);
 *   • an unbound `RandomNumberGenerator.new().randi()` is always flagged. `# rng-ok` on the line exempts it.
 * A heuristic by NAME within that scope, not dataflow — it catches the forgotten seed, which is the way this goes
 * wrong. The in-engine twin is run_realtime_tests `_t_no_unseeded_rng_in_sim` (same scope rule).
 * @param {{file: string, src: string}[]} sources the corpus  → [{file, line, name, text}]
 */
export function unseededRng(sources) {
  const seedRe = /(?:^|[^\w])(\w+)\.(?:seed|state)\s*=[^=]/;
  const members = new Set(); // every `<name>.seed =` / `.state =` anywhere in the corpus (a member may be seeded in another file)
  const parsed = sources.map(({ file, src }) => {
    const raws = src.split(/\r?\n/);
    const codes = raws.map(gdCode);
    for (const code of codes) { const m = seedRe.exec(code); if (m) members.add(m[1]); }
    return { file, raws, codes };
  });
  // a local `name` created at line i is seeded when a later line of the SAME function assigns name.seed / name.state
  const seededLater = (codes, i, name) => {
    const re = new RegExp(`\\b${name}\\.(?:seed|state)\\s*=[^=]`);
    for (let j = i + 1; j < codes.length; j++) {
      if (FUNC_DECL_RE.test(codes[j].trim())) return false;
      if (re.test(codes[j])) return true;
    }
    return false;
  };
  const out = [];
  for (const { file, raws, codes } of parsed)
    codes.forEach((code, i) => {
      if (/#\s*rng-ok\b/.test(raws[i])) return;
      if (!/\bRandomNumberGenerator\.new\s*\(/.test(code)) return;
      const bound = /(?:(\w+)\.)?(\w+)\s*(?::\s*[\w.]+\s*)?:?=\s*RandomNumberGenerator\.new\s*\(\s*\)\s*$/.exec(code.trim());
      if (bound) {
        const name = bound[2];
        const member = !!bound[1] || /^var\b/.test(code); // `s.x = …` or an unindented class-level `var x := …`
        if (member ? members.has(name) : seededLater(codes, i, name)) return;
      }
      out.push({ file, line: i + 1, name: bound ? bound[2] : null, text: raws[i].trim() });
    });
  return out;
}

// ── markdown tables (state files are tables so humans edit them and tools read them) ────────────────
const cells = (line) => line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());

/** Rows (objects keyed by header text) of the first table whose header line matches headerRe. */
export function mdTable(md, headerRe) {
  const lines = md.split(/\r?\n/);
  for (let i = 0; i + 1 < lines.length; i++) {
    if (!lines[i].trim().startsWith("|") || !headerRe.test(lines[i])) continue;
    if (!/^\s*\|?\s*:?-{2,}/.test(lines[i + 1])) continue;
    const head = cells(lines[i]);
    const rows = [];
    for (let j = i + 2; j < lines.length && lines[j].trim().startsWith("|"); j++) {
      const c = cells(lines[j]);
      rows.push(Object.fromEntries(head.map((h, k) => [h, c[k] ?? ""])));
    }
    return rows;
  }
  return [];
}

// ── PR body (.github/pull_request_template.md is the contract) ─────────────────────────────────────
export const TYPES = ["feat", "fix", "refactor", "balance", "content", "art", "test", "docs", "process"];
export const PILLARS = ["S1", "S2", "S3", "infra", "process"];
/** Types that change what the player experiences — they must serve a pillar and cite a basis. */
export const PLAYER_TYPES = ["feat", "balance", "content"];

const stripComments = (s) => s.replace(/<!--[\s\S]*?-->/g, "");
const field = (text, name) => {
  const m = text.match(new RegExp(`^[\\s>*-]*\\**${name}\\**\\s*:\\**[ \\t]*(.*)$`, "imu"));
  return m ? m[1].trim() : "";
};

export function parsePr(body) {
  const text = stripComments(body || "");
  const sections = new Map();
  const parts = text.split(/^##\s+/m).slice(1);
  for (const p of parts) {
    const nl = p.indexOf("\n");
    const head = (nl < 0 ? p : p.slice(0, nl)).trim().toLowerCase();
    sections.set(head, (nl < 0 ? "" : p.slice(nl + 1)).trim());
  }
  const section = (prefix) => {
    for (const [k, v] of sections) if (k.startsWith(prefix)) return v;
    return "";
  };
  const first = (v) => (v.split(/[\s|,;+/]+/)[0] || "");
  return {
    text,
    sections,
    section,
    type: first(field(text, "Тип")).toLowerCase(),
    pillar: (() => { const p = first(field(text, "Стовп")); return /^s[123]$/i.test(p) ? p.toUpperCase() : p.toLowerCase(); })(),
  };
}

// ── diff classification ─────────────────────────────────────────────────────────────────────────────
const DOC = [/\.md$/, /^docs\//, /^specs\//, /^GDD_BOOK\//];
const ART = [/^godot\/assets\/gen\//, /^art\//];
// what the player SEES — a change here needs a frame (кадр) in the evidence
const UI = [/^godot\/scripts\/ui\//, /^godot\/scripts\/world_view\.gd$/, /^godot\/newhud/, /^godot\/scenes\//,
  /^godot\/assets\//, /^game\/js\/(ui|render|input)\.js$/, /^game\/(styles\.css|index\.html)$/];
// the RULES of the game — a player-facing change here needs a basis (REQ/OD/spec)
const RULES = [/^godot\/scripts\/sim(\.gd|\/)/, /^godot\/scripts\/(data|catalog_defs|goals|world_gen)\.gd$/,
  /^godot\/scripts\/kernel\//, /^godot\/content\//, /^game\/js\/(game|entities|catalog_data|progression|logistics|worldgen)\.js$/];
// generated or binary — excluded from the diff-size heuristic
const GENERATED = [/\.png$/, /\.uid$/, /\.import$/, /^game\/js\/catalog_data\.js$/, /^art\/manifest\.json$/];

const any = (res, f) => res.some((re) => re.test(f));
export function classifyFiles(files) {
  const doc = files.filter((f) => any(DOC, f));
  const product = files.filter((f) => !any(DOC, f));
  return {
    doc, product,
    ui: product.filter((f) => any(UI, f)),
    rules: product.filter((f) => any(RULES, f)),
    art: product.filter((f) => any(ART, f)),
    sized: product.filter((f) => !any(GENERATED, f)),
  };
}

// ── the gate ────────────────────────────────────────────────────────────────────────────────────────
const EVIDENCE_RE = /(npm (test|run)|node --test|run_[a-z_]+|test\.cmd|\btests?\b.*\b(pass|ok|green)|✔|✓|\bpass(ed)?\b|\bok\b|зелен|\.png|!\[|world_hash|WORLD_HASH|артефакт|artifact|кадр|screenshot|скриншот|\bshot\b|лог\s+тест)/iu;
const FRAME_RE = /(\.png|\.jpe?g|!\[|кадр|screenshot|скриншот|newhud shot|\bshot\b|smoke)/iu;
const BASIS_RE = /(REQ-\d{4}-\d+|\bOD-\d+|specs\/\d{4})/u;
const REPRO_RE = /(seed|відтвор|регрес|repro|world_hash|WORLD_HASH)/iu;
export const BIG_DIFF = 800;

/**
 * The PR evidence gate. errors block the merge; warnings are printed.
 * @param {string} body PR description   @param {string[]} files changed paths   @param {{changedLines?: number}} opts
 */
export function checkPr(body, files, { changedLines = 0 } = {}) {
  const pr = parsePr(body);
  const c = classifyFiles(files);
  const errors = [], warnings = [];
  const player = PLAYER_TYPES.includes(pr.type);

  if (!pr.section("інтент")) errors.push("PR-1 Немає «## Інтент»: одне речення — що зміниться для гравця (або для процесу).");
  if (!TYPES.includes(pr.type)) errors.push(`PR-2 «Тип:» — рівно один із ${TYPES.join(" | ")} (зараз: «${pr.type || "порожньо"}»).`);
  if (!PILLARS.includes(pr.pillar)) errors.push(`PR-3 «Стовп:» — один із ${PILLARS.join(" | ")} (зараз: «${pr.pillar || "порожньо"}»).`);
  else if (player && !/^S[123]$/.test(pr.pillar))
    errors.push("PR-3 Фіча/баланс/контент без стовпа S1–S3 → це заморозка, не робота (P7, docs/design/pillars.md).");

  if (c.product.length) {
    const ev = pr.section("докази");
    if (!ev || !EVIDENCE_RE.test(ev))
      errors.push("PR-4 Змінено продуктові файли, а «## Докази» порожні: лог тестів, кадр або world_hash (P2 — без доказу нема «готово»).");
    if (c.ui.length && !FRAME_RE.test(ev))
      errors.push(`PR-5 Змінено видиме (${c.ui.slice(0, 3).join(", ")}${c.ui.length > 3 ? ", …" : ""}) — у «Докази» потрібен кадр до/після (newhud shot / smoke-скриншот).`);
    if (c.rules.length && player && !BASIS_RE.test(pr.text))
      errors.push(`PR-6 Змінено правила гри (${c.rules.slice(0, 3).join(", ")}${c.rules.length > 3 ? ", …" : ""}) без підстави: REQ-NNNN-n, OD-n або specs/NNNN (P1 — правила вирішує власник).`);
    if (pr.type === "fix" && !REPRO_RE.test(pr.text))
      warnings.push("PR-7 fix без відтворення: назви seed/кроки або регресійний тест (P5 — детермінізм = діагностованість).");
  }
  if (c.art.length && !files.includes("docs/process/ai-use-log.md"))
    warnings.push("PR-8 Змінено ШІ-арт без запису в docs/process/ai-use-log.md (F9, OD про політику арту).");
  if (changedLines > BIG_DIFF)
    warnings.push(`PR-9 Великий диф: ${changedLines} рядків продукту (> ${BIG_DIFF}). Розріж на історії з одним видимим результатом (P6).`);
  return { errors, warnings, classes: c, pr };
}

// ── P10: measure the process — where do the owner's corrections land? ─────────────────────────────
export const DESIGN_CATS = ["mechanic", "control", "ui", "text", "balance", "scope"];
export const CODE_CATS = ["code"];

/** rows: [{category}] from docs/process/rework-log.md → {n, by, design, code, verdict}. */
export function reworkVerdict(rows) {
  const by = {};
  for (const r of rows) {
    const k = String(r.category || "").trim().toLowerCase();
    if (k) by[k] = (by[k] || 0) + 1;
  }
  const n = Object.values(by).reduce((a, b) => a + b, 0);
  const sum = (cats) => cats.reduce((a, k) => a + (by[k] || 0), 0);
  const design = sum(DESIGN_CATS), code = sum(CODE_CATS);
  let verdict;
  if (!n) verdict = "даних нема — записуй кожну правку власника/плейтесту після агентної задачі";
  else if (design / n >= 0.5) verdict = "правки переважно в механіках/керуванні/UI → посилити G0–G1 (прототип керування, стовпи) і G5 (люди)";
  else if (code / n >= 0.5) verdict = "правки переважно в коді → посилити тести (мутаційні, сценарії другого агента) і закріплення API";
  else verdict = "змішано → тримати поточні ворота, переглянути через 2 тижні";
  return { n, by, design, code, verdict };
}

/** Whole days between two ISO dates (b − a). */
export function daysBetween(a, b) {
  return Math.floor((Date.parse(b) - Date.parse(a)) / 86400000);
}

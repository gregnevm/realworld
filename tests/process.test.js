"use strict";
// RealWorld — process.test.js : pins the PURE core of the process tooling (tools/process/lib.mjs) and the
// state files it reads. The gate is held to its own rule (P2): no «done» without a test.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const lib = () => import("../tools/process/lib.mjs");
const ROOT = path.join(__dirname, "..");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");

const BODY = (o = {}) => `## Інтент
${o.intent ?? "Гравець бачить, звідки йде робот."}

## Тип · стовп · підстава
- Тип: ${o.type ?? "feat"}
- Стовп: ${o.pillar ?? "S3"}
- Підстава: ${o.basis ?? "REQ-0010-2"}

## Докази
${o.evidence ?? "npm test — 120 pass; кадр: godot/newhud_shot.png"}

## Що прибрано
нічого — бо новий канал замінює банер
`;

// ── F1 drift ──────────────────────────────────────────────────────────────────────────────────────
test("godotDrift: flags Godot-3 spellings with a Godot-4 hint", async () => {
  const { godotDrift } = await lib();
  const src = [
    "extends Node",
    "export var speed = 3",
    "onready var lbl = $Label",
    "func _ready():",
    "\tyield(get_tree(), \"idle_frame\")",
    "\tvar a = rand_range(0, 1)",
    "\tvar s = load(\"x.tscn\").instance()",
    "\tif arr.empty(): pass",
  ].join("\n");
  const hits = godotDrift(src);
  assert.deepStrictEqual(hits.map((h) => h.line), [2, 3, 5, 6, 7, 8]);
  assert.ok(hits.every((h) => h.hint.includes("→")), "every hit carries a replacement");
});

test("godotDrift: Godot-4 code, comments, strings and # drift-ok are clean", async () => {
  const { godotDrift, stripGdComment } = await lib();
  const src = [
    "@export var speed: float = 3.0",
    "@onready var lbl: Label = $Label",
    "\tawait get_tree().process_frame",
    "\tvar a: float = rng.randf_range(0.0, 1.0)",
    "\t# old: yield(get_tree(), \"idle_frame\") and rand_range()",
    "\tvar msg: String = \"use # not yield( here\"",
    "\tif arr.is_empty(): pass",
    "\tqueue.empty()  # drift-ok: our own Queue.empty()",
    "\tvar k: int = KEY_SPACE",
  ].join("\n");
  assert.deepStrictEqual(godotDrift(src), []);
  assert.strictEqual(stripGdComment('var s = "a # b" # tail'), 'var s = "a # b" ');
});

test("the live Godot tree carries no Godot-3 API (the lint tripwire would be red)", async () => {
  const { godotDrift } = await lib();
  const files = execFileSync("git", ["ls-files", "*.gd"], { cwd: ROOT, encoding: "utf8" }).split("\n").filter(Boolean);
  assert.ok(files.length > 50, "expected the Godot port's scripts");
  const hits = files.flatMap((f) => godotDrift(read(f)).map((d) => `${f}:${d.line} ${d.hint}`));
  assert.deepStrictEqual(hits, []);
});

// ── markdown tables ───────────────────────────────────────────────────────────────────────────────
// ── spec 0012 REQ-10: the sim reads no clock and no system-seeded RNG ─────────────────────────────
const godotFiles = () => execFileSync("git", ["ls-files", "--cached", "--others", "--exclude-standard", "godot/*.gd"], { cwd: ROOT, encoding: "utf8" })
  .split("\n").filter(Boolean).filter((f) => fs.existsSync(path.join(ROOT, f)));

test("simClockDrift: flags every clock / system-RNG API of REQ-0012-10", async () => {
  const { simClockDrift } = await lib();
  const src = [
    "extends RefCounted",
    "\tvar a: float = Time.get_unix_time_from_system()",
    "\tvar b: int = Time.get_ticks_msec()",
    "\tvar c: int = OS.get_system_time_msecs()",
    "\tvar d: int = OS.get_unix_time()",
    "\tvar e: int = OS.get_datetime()",
    "\tvar f: int = Engine.get_ticks_usec()",
    "\tEngine.time_scale = 3.0",
    "\tvar g := DateTime.new()",
    "\trng.randomize()",
    "\tvar h: float = randf()",
    "\tvar i: int = randi_range(1, 6)",
    "\trandomize()",
  ].join("\n");
  const hits = simClockDrift(src);
  assert.deepStrictEqual([...new Set(hits.map((h) => h.line))], [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
  assert.ok(hits.every((h) => h.hint.length > 5), "every hit carries a hint");
});

test("simClockDrift: seeded rng, comments, strings, look-alikes and # clock-ok are clean", async () => {
  const { simClockDrift } = await lib();
  const src = [
    "\tvar a: float = rng.randf()                   # a method on a SEEDED generator is the sanctioned way",
    "\tvar b: int = threat_rng.randi_range(0, 3)",
    "\t# Time.get_ticks_msec() and randomize() in a comment",
    "\tvar m: String = \"Time.get_ticks_msec() randf() DateTime\"",
    "\tvar n: float = MyTime.now() + _Time.x + Timer.new().time_left",
    "\tvar o: int = Engine.get_frames_drawn()",
    "\tvar p: int = Randomizer.randomize_all()",
    "\tvar q: int = Time.get_ticks_msec()  # clock-ok: a project method that shares the name",
    "\trng.seed = hash_seed",
  ].join("\n");
  assert.deepStrictEqual(simClockDrift(src), []);
});

test("unseededRng: a local generator must be seeded in its own function; a member may be seeded anywhere", async () => {
  const { unseededRng } = await lib();
  const sim = { file: "sim.gd", src: "var env_rng := RandomNumberGenerator.new()\nvar loose := RandomNumberGenerator.new()\nvar marked := RandomNumberGenerator.new()  # rng-ok" };
  const env = { file: "env.gd", src: "func f(s) -> void:\n\ts.env_rng.seed = 7\n\ts.late_rng = RandomNumberGenerator.new()\n\ts.late_rng.state = 9" };
  const local = { file: "local.gd", src: "func a() -> void:\n\tvar rng := RandomNumberGenerator.new()\n\trng.seed = 1\nfunc b() -> void:\n\tvar fb := RandomNumberGenerator.new()\n\treturn fb.randi()" };
  const other = { file: "other.gd", src: "func c() -> void:\n\tvar rng := RandomNumberGenerator.new()\n\tvar n: int = RandomNumberGenerator.new().randi()" };
  const hits = unseededRng([sim, env, local, other]).map((h) => `${h.file}:${h.line}:${h.name}`);
  assert.deepStrictEqual(hits, ["sim.gd:2:loose", "local.gd:5:fb", "other.gd:2:rng", "other.gd:3:null"]);
});

test("sim corpus: godot/scripts minus the view layer, clock.gd and the frozen HUD (a NEW script is covered by default)", async () => {
  const { inSimCorpus, SIM_CORPUS_EXCLUDE } = await lib();
  for (const yes of ["scripts/sim.gd", "scripts/session.gd", "scripts/persistence.gd", "scripts/sim/threats.gd", "scripts/kernel/needs.gd",
    "scripts/net/command.gd", "scripts/goals.gd", "scripts/data_bridge.gd", "scripts/offline.gd", "scripts/hints.gd", "scripts/sim/brand_new.gd"])
    assert.ok(inSimCorpus(yes), `${yes} must be scanned`);
  for (const no of ["scripts/clock.gd", "scripts/ui/panels.gd", "scripts/ui/dev/dev_panel.gd", "scripts/world_view.gd", "scripts/map_widget.gd",
    "scripts/main.gd", "newhud_main.gd", "tests/run_tests.gd", "scripts/sim.gdshader"])
    assert.ok(!inSimCorpus(no), `${no} is not sim`);
  assert.ok(SIM_CORPUS_EXCLUDE.every((e) => e.endsWith(".gd") || e.endsWith("/")));
});

test("REQ-0012-10: the live sim corpus reads no clock and no unseeded RNG (the lint would be red)", async () => {
  const { inSimCorpus, simClockDrift, unseededRng } = await lib();
  const sources = godotFiles().filter((f) => inSimCorpus(f.slice("godot/".length))).map((f) => ({ file: f, src: read(f) }));
  assert.ok(sources.length > 30, `expected the sim scripts, got ${sources.length}`);
  assert.deepStrictEqual(sources.flatMap(({ file, src }) => simClockDrift(src).map((d) => `${file}:${d.line} ${d.hint}`)), []);
  assert.deepStrictEqual(unseededRng(sources).map((d) => `${d.file}:${d.line}`), []);
});

test("REQ-0012-10: lint.mjs and run_tests.gd enforce the SAME corpus and the SAME patterns (one list, two enforcers)", async () => {
  const { SIM_CORPUS_EXCLUDE, SIM_CLOCK_BAN } = await lib();
  const gd = read("godot/tests/run_tests.gd");
  const arrayOf = (name) => {
    const m = gd.match(new RegExp(`const ${name} := \\[([^\\]]*)\\]`));
    assert.ok(m, `run_tests.gd lost const ${name}`);
    return [...m[1].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((x) => x[1]);
  };
  assert.deepStrictEqual(arrayOf("SIM_CORPUS_EXCLUDE"), SIM_CORPUS_EXCLUDE, "exclusion lists drifted apart");
  // a GDScript string literal "\\bTime\\." is the regex \bTime\.
  const gdPatterns = arrayOf("SIM_CLOCK_PATTERNS").map((p) => p.replace(/\\\\/g, "\\"));
  assert.deepStrictEqual(gdPatterns, SIM_CLOCK_BAN.map(([re]) => re.source), "clock-pattern lists drifted apart");
  // the lint reads the corpus from git, the Godot twin from _product_scripts(): the latter must walk every script dir
  const dirs = [...gd.matchAll(/for dir_path in \[([^\]]*)\]/g)].flatMap((m) => [...m[1].matchAll(/"res:\/\/([^"]+)"/g)].map((x) => x[1]));
  const scriptDirs = new Set(godotFiles().filter((f) => f.startsWith("godot/scripts/")).map((f) => path.posix.dirname(f.slice("godot/".length))));
  for (const d of scriptDirs) assert.ok(dirs.includes(d), `_product_scripts() does not walk ${d}/ — the in-engine tripwire would not see its scripts`);
});

test("REQ-0012-10/11: clock.gd is the ONLY product script that asks the OS for the time of day", async () => {
  const { gdCode } = await lib();
  const homes = godotFiles()
    .filter((f) => f.startsWith("godot/scripts/") || f === "godot/newhud_main.gd")
    .filter((f) => read(f).split(/\r?\n/).some((l) => gdCode(l).includes("Time.get_unix_time_from_system")));
  assert.deepStrictEqual(homes, ["godot/scripts/clock.gd"]);
});

test("mdTable: reads the first matching table, keys by header", async () => {
  const { mdTable } = await lib();
  const md = "intro\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n| ID | Статус |\n|---|---|\n| OD-1 | open |\n| OD-2 | decided |\ntext";
  assert.deepStrictEqual(mdTable(md, /\|\s*ID\s*\|/), [{ ID: "OD-1", "Статус": "open" }, { ID: "OD-2", "Статус": "decided" }]);
  assert.deepStrictEqual(mdTable(md, /nope/), []);
});

// ── PR gate ───────────────────────────────────────────────────────────────────────────────────────
test("checkPr: a complete feat PR with frame + basis passes", async () => {
  const { checkPr } = await lib();
  const r = checkPr(BODY(), ["godot/scripts/sim/threats.gd", "godot/scripts/ui/hud_model.gd", "tests/x.test.js"], { changedLines: 120 });
  assert.deepStrictEqual(r.errors, []);
  assert.deepStrictEqual(r.warnings, []);
  assert.strictEqual(r.pr.type, "feat");
  assert.strictEqual(r.pr.pillar, "S3");
});

test("checkPr: the unfilled template fails on intent, type, pillar and evidence", async () => {
  const { checkPr } = await lib();
  const tpl = read(".github/pull_request_template.md");
  const r = checkPr(tpl, ["godot/scripts/sim.gd"]);
  const codes = r.errors.map((e) => e.slice(0, 4));
  assert.deepStrictEqual(codes, ["PR-1", "PR-2", "PR-3", "PR-4"]);
});

test("checkPr: P7 — a feature without a pillar is a freeze, not work", async () => {
  const { checkPr } = await lib();
  const r = checkPr(BODY({ pillar: "infra" }), ["godot/scripts/sim.gd"]);
  assert.ok(r.errors.some((e) => e.startsWith("PR-3") && e.includes("P7")));
  assert.deepStrictEqual(checkPr(BODY({ type: "refactor", pillar: "infra" }), ["godot/scripts/sim.gd"]).errors, []);
});

test("checkPr: P2 — product change with empty or vague evidence is blocked", async () => {
  const { checkPr } = await lib();
  for (const evidence of ["", "оновив каталог, все працює"]) {
    const r = checkPr(BODY({ type: "refactor", pillar: "infra", evidence }), ["godot/scripts/session.gd"]);
    assert.ok(r.errors.some((e) => e.startsWith("PR-4")), `evidence «${evidence}» must not pass`);
  }
});

test("checkPr: visible change needs a frame; rules change needs a basis", async () => {
  const { checkPr } = await lib();
  const noFrame = checkPr(BODY({ evidence: "npm test — 120 pass" }), ["godot/scripts/ui/hud_root.gd"]);
  assert.ok(noFrame.errors.some((e) => e.startsWith("PR-5")));
  const noBasis = checkPr(BODY({ basis: "бо так краще" }), ["godot/content/catalog.json"]);
  assert.ok(noBasis.errors.some((e) => e.startsWith("PR-6")));
  for (const basis of ["OD-5", "specs/0009-personal-inventory.md", "REQ-0011-4"])
    assert.deepStrictEqual(checkPr(BODY({ basis }), ["godot/content/catalog.json"]).errors, [], basis);
});

test("checkPr: docs-only PR needs only intent/type/pillar; warnings for fix, art and size", async () => {
  const { checkPr } = await lib();
  assert.deepStrictEqual(checkPr(BODY({ type: "docs", pillar: "process", evidence: "" }), ["docs/process/README.md", "specs/_TEMPLATE.md"]).errors, []);
  const fix = checkPr(BODY({ type: "fix", pillar: "infra", basis: "", evidence: "npm test pass" }), ["godot/scripts/session.gd"]);
  assert.deepStrictEqual(fix.errors, []);
  assert.ok(fix.warnings.some((w) => w.startsWith("PR-7")));
  const art = checkPr(BODY({ type: "art", pillar: "S1" }), ["godot/assets/gen/icon/res_wood.png"]);
  assert.ok(art.warnings.some((w) => w.startsWith("PR-8")));
  const big = checkPr(BODY({ type: "refactor", pillar: "infra" }), ["godot/scripts/session.gd"], { changedLines: 2000 });
  assert.ok(big.warnings.some((w) => w.startsWith("PR-9")));
});

test("classifyFiles: generated/binary files do not count toward diff size", async () => {
  const { classifyFiles } = await lib();
  const c = classifyFiles(["game/js/catalog_data.js", "art/manifest.json", "godot/assets/gen/x.png", "godot/scripts/sim.gd", "a.md"]);
  assert.deepStrictEqual(c.sized, ["godot/scripts/sim.gd"]);
  assert.deepStrictEqual(c.doc, ["a.md"]);
});

// ── P10 ──────────────────────────────────────────────────────────────────────────────────────────
test("reworkVerdict: design-heavy corrections point at G0–G1 + G5, code-heavy at tests", async () => {
  const { reworkVerdict } = await lib();
  assert.match(reworkVerdict([]).verdict, /даних нема/);
  assert.match(reworkVerdict([{ category: "ui" }, { category: "control" }, { category: "code" }]).verdict, /G0–G1/);
  assert.match(reworkVerdict([{ category: "code" }, { category: "code" }, { category: "ui" }]).verdict, /тести/);
});

// ── the state files are machine-readable (the report and the hook depend on it) ──────────────────
test("state files parse: decisions, scope, rework log, pillars, LLM Week date", async () => {
  const { mdTable, reworkVerdict, DESIGN_CATS, CODE_CATS } = await lib();
  const od = mdTable(read("docs/design/decisions.md"), /\|\s*ID\s*\|/);
  assert.ok(od.length >= 10);
  const ids = od.map((d) => d.ID);
  assert.strictEqual(new Set(ids).size, ids.length, "OD ids are unique");
  assert.ok(od.every((d) => /^OD-\d+$/.test(d.ID) && /^(open|decided|superseded)$/.test(d["Статус"])), "OD id + status vocabulary");

  const scope = mdTable(read("docs/design/scope.md"), /\|\s*Система\s*\|/);
  assert.ok(scope.length >= 10 && scope.every((r) => "Вердикт власника" in r));

  const cats = [...DESIGN_CATS, ...CODE_CATS, "art", "process"];
  const rw = mdTable(read("docs/process/rework-log.md"), /\|\s*Категорія\s*\|/);
  assert.ok(rw.length > 0 && rw.every((r) => cats.includes(r["Категорія"])), "rework categories from the closed set");
  assert.ok(reworkVerdict(rw.map((r) => ({ category: r["Категорія"] }))).n === rw.length);

  assert.match(read("docs/design/pillars.md"), /^Статус: \*\*(draft|approved)\*\*/m);
  assert.match(read("docs/process/automation.md"), /Наступна LLM Week: \*\*\d{4}-\d{2}-\d{2}\*\*/);
});

test("report --brief runs, stays short and never fails", () => {
  const out = execFileSync(process.execPath, [path.join(ROOT, "tools/process/report.mjs"), "--brief"], { encoding: "utf8" });
  const lines = out.trim().split("\n");
  assert.ok(lines.length <= 12, `brief digest is ${lines.length} lines`);
  assert.match(out, /Чекають рішення власника \(\d+\) → \/decide/);
});

test("agents: every role has a name, a description and least-privilege tools", () => {
  const dir = path.join(ROOT, ".claude", "agents");
  const roles = Object.fromEntries(fs.readdirSync(dir).filter((f) => f.endsWith(".md")).map((f) => {
    const fm = fs.readFileSync(path.join(dir, f), "utf8").match(/^---\n([\s\S]*?)\n---/)[1];
    const get = (k) => (fm.match(new RegExp(`^${k}:\\s*(.+)$`, "m")) || [])[1];
    assert.strictEqual(get("name"), f.slice(0, -3), `${f}: name matches file`);
    assert.ok((get("description") || "").length > 40, `${f}: description says when to delegate`);
    return [get("name"), (get("tools") || "*").split(/,\s*/)];
  }));
  for (const r of ["designer", "developer", "integrity", "qa-adversary", "fresh-eyes"]) assert.ok(roles[r], `role ${r}`);
  assert.deepStrictEqual(roles["fresh-eyes"], ["Read"], "independent eye sees only the frames");
  assert.ok(!roles.integrity.includes("Edit") && !roles.integrity.includes("Write"), "gatekeeper cannot edit");
});

test("skills: /decide exists and owner-facing docs promise only three owner actions", () => {
  const skill = read(".claude/skills/decide/SKILL.md");
  const fm = skill.match(/^---\n([\s\S]*?)\n---/)[1];
  assert.match(fm, /^name: decide$/m);
  assert.match(fm, /^description: .{80,}$/m, "description says when to trigger");
  assert.match(skill, /AskUserQuestion/, "decisions are asked as buttons, not file edits");
  assert.match(read("docs/process/README.md"), /## Для власника — три дії/);
  const agents = read("AGENTS.md");
  assert.match(agents, /\| Старт сесії[^|]*\| `npm run process -- --brief`/, "session-start trigger");
  for (const t of ["/gamedev", "/decide", "rework-log", "плейтест", "LLM Week"]) assert.ok(agents.includes(t), `trigger ${t}`);
});

// ── qa-adversary, wave 0012-W1: REQ-0012-10 — does the tripwire actually trip, and does it stay quiet when it must? ────
// Written from the REQ text («заборонені API: Time.*, OS.get_*time*, Engine.get_ticks_*, Engine.time_scale, randomize(),
// randf*/randi*, RandomNumberGenerator без явного seed, DateTime»), not from lib.mjs. A lint that is blind to a banned call
// (or red on a legal one) is worse than none, so every case below is a line a real author could type.
const lintHits = (src) => lib().then(({ simClockDrift }) => [...new Set(simClockDrift(src).map((h) => h.line))]);   // distinct lines (one call may match two patterns)

test("REQ-0012-10 simClockDrift: a '#', quote or apostrophe EARLIER on the line never hides a later banned call", async () => {
  const lines = [
    'print("#", Time.get_ticks_msec())',
    'var s: String = "it\'s " + str(Time.get_ticks_msec())',
    'var s: String = "a\\"b" + str(Time.get_ticks_msec())',
    'var t: int = Time.get_ticks_msec()   # "unbalanced quote and \'apostrophe',
    "var n: int = randi() % 6   # roll",
    "var x: float = absf(randf() - 0.5)",
    "foo(randf_range(0.0, 1.0), randfn(0.0, 1.0), randi_range(1, 6))",
    "var u: int = OS.get_unix_time()",
    "var d: Dictionary = OS.get_datetime()",
    "var t: int = Engine.get_ticks_usec()",
    "if Engine.time_scale > 1.0: pass",
    "var d := DateTime.new()",
    "rng.randomize()",
    "randomize()",
    "var t: float = Time.get_unix_time_from_system()",
  ];
  for (const l of lines) assert.deepStrictEqual(await lintHits(l), [1], `must be flagged: ${l}`);
});

test("REQ-0012-10 simClockDrift: a SEEDED generator's methods and look-alike identifiers are NOT flagged", async () => {
  const lines = [
    "var a: int = rng.randi_range(0, 3)",
    "var b: float = _rng.randf()",
    "var c: float = s.env_rng.randfn(0.0, 1.0)",
    "var d: int = rand_from_seed(seed_val)[0]",
    'var e: bool = "Time.get_ticks_msec()" in text',
    "var f: String = 'OS.get_datetime() randomize()'",
    "var g: float = s.time.frac + s.time.day_len",
    "var h: int = float_time_of_day()",
    "var i: Timer = Timer.new()",
    "func randomized_pick(arr: Array) -> int:",
    "var j: int = errand() + brandf() + grandfather_randi()",
    "var k: int = Engine.get_frames_drawn()",
    "var l: int = Engine.get_physics_frames()",
    "rng.seed = hash_seed",
    "## Time.get_ticks_msec(): a doc comment",
  ];
  for (const l of lines) assert.deepStrictEqual(await lintHits(l), [], `must NOT be flagged: ${l}`);
});

test("REQ-0012-10 simClockDrift: `# clock-ok` exempts its own line only, never the lines after it", async () => {
  const src = [
    "var a: int = Time.get_ticks_msec()  # clock-ok: a project method that shares the name",
    "var b: int = Time.get_ticks_msec()",
    "var c: float = randf()",
  ].join("\n");
  assert.deepStrictEqual(await lintHits(src), [2, 3]);
});

test("REQ-0012-10 inSimCorpus: only the EXACT view files are exempt — siblings, look-alikes and new directories are scanned", async () => {
  const { inSimCorpus } = await lib();
  for (const yes of ["scripts/sim/clock.gd", "scripts/kernel/clock_like.gd", "scripts/ui_state.gd", "scripts/main_menu.gd",
    "scripts/world_view_model.gd", "scripts/map_widget_data.gd", "scripts/sim/orbit/orbit_stub.gd", "scripts/offline.gd",
    "scripts/hints.gd", "scripts/location.gd", "scripts/net/snapshot.gd"])
    assert.ok(inSimCorpus(yes), `${yes} must be scanned (a new script is covered by default)`);
  for (const no of ["scripts/clock.gd", "scripts/ui/dev/dev_panel.gd", "scripts/ui/panels.gd", "tests/x.gd", "newhud_main.gd", "scripts/sim/threats.gd.uid"])
    assert.ok(!inSimCorpus(no), `${no} is not the sim`);
});

test("REQ-0012-10 unseededRng: a local generator needs a seed in ITS OWN function — a same-named seed elsewhere in the file does not count", async () => {
  const { unseededRng } = await lib();
  const src = [
    "extends RefCounted",
    "func seeded() -> int:",
    "\tvar rng := RandomNumberGenerator.new()",
    "\trng.seed = 1",
    "\treturn rng.randi()",
    "func forgotten() -> int:",
    "\tvar rng := RandomNumberGenerator.new()",   // copy-pasted, seed forgotten: system randomness
    "\treturn rng.randi()",
  ].join("\n");
  assert.deepStrictEqual(unseededRng([{ file: "a.gd", src }]).map((h) => h.line), [7],
    "the unseeded local in forgotten() must be reported (the seed in seeded() is a different generator)");
});

// ── end to end: the REAL tools/lint.mjs run in a throw-away git repo with a planted file ─────────────────
const os = require("node:os");
function lintIn(files, { add = true } = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "rw-lint-"));
  try {
    fs.cpSync(path.join(ROOT, "tools"), path.join(tmp, "tools"), { recursive: true });
    fs.mkdirSync(path.join(tmp, "game"), { recursive: true });
    fs.copyFileSync(path.join(ROOT, "game", "index.html"), path.join(tmp, "game", "index.html"));
    fs.cpSync(path.join(ROOT, "game", "js"), path.join(tmp, "game", "js"), { recursive: true });
    fs.copyFileSync(path.join(ROOT, ".gitignore"), path.join(tmp, ".gitignore"));
    for (const [rel, src] of Object.entries(files)) {
      fs.mkdirSync(path.dirname(path.join(tmp, rel)), { recursive: true });
      fs.writeFileSync(path.join(tmp, rel), src);
    }
    execFileSync("git", ["init", "-q"], { cwd: tmp });
    if (add) execFileSync("git", ["add", "-A"], { cwd: tmp });
    try {
      const out = execFileSync(process.execPath, ["tools/lint.mjs"], { cwd: tmp, stdio: "pipe" });
      return { status: 0, out: String(out) };
    } catch (e) { return { status: e.status, out: String(e.stderr) + String(e.stdout) }; }
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
}
const GD_BAD_CLOCK = "extends RefCounted\nfunc f() -> int:\n\treturn Time.get_ticks_msec()\n";

test("REQ-0012-10 lint.mjs end to end: a clean sim file passes (the harness itself is not the reason for red)", () => {
  const r = lintIn({ "godot/scripts/sim/clean.gd": "extends RefCounted\nfunc f(rng: RandomNumberGenerator) -> int:\n\treturn rng.randi()\n" });
  assert.strictEqual(r.status, 0, r.out);
  assert.match(r.out, /sim \.gd free of clock\/system RNG/);
});

test("REQ-0012-10 lint.mjs end to end: a planted clock read in the sim fails with file:line and the REQ", () => {
  for (const rel of ["godot/scripts/sim/planted.gd", "godot/scripts/kernel/planted.gd", "godot/scripts/net/planted.gd", "godot/scripts/planted.gd"]) {
    const r = lintIn({ [rel]: GD_BAD_CLOCK });
    assert.notStrictEqual(r.status, 0, `${rel}: lint must fail`);
    assert.ok(r.out.includes(`${rel}:3`), `${rel}: names file and line — ${r.out}`);
    assert.match(r.out, /REQ-0012-10/);
  }
});

test("REQ-0012-10 lint.mjs end to end: a script in a BRAND-NEW directory, and an untracked-but-not-ignored file, are covered", () => {
  const r1 = lintIn({ "godot/scripts/sim/orbit/new.gd": "extends RefCounted\nfunc f() -> float:\n\treturn randf()\n" });
  assert.notStrictEqual(r1.status, 0, "randf() in scripts/sim/orbit/ must fail");
  const r2 = lintIn({ "godot/scripts/sim/untracked.gd": GD_BAD_CLOCK }, { add: false });
  assert.notStrictEqual(r2.status, 0, "an unstaged new file must still be scanned");
  const r3 = lintIn({ "godot/scripts/ui_state.gd": GD_BAD_CLOCK });
  assert.notStrictEqual(r3.status, 0, "scripts/ui_state.gd is not the view dir scripts/ui/");
});

test("REQ-0012-10 lint.mjs end to end: an RNG nobody seeds fails; a seeded one passes", () => {
  const bad = lintIn({ "godot/scripts/kernel/rngbad.gd": "extends RefCounted\nfunc f() -> int:\n\tvar rng := RandomNumberGenerator.new()\n\treturn rng.randi()\n" });
  assert.notStrictEqual(bad.status, 0, "RandomNumberGenerator.new() without a seed must fail");
  assert.match(bad.out, /RandomNumberGenerator/);
  const good = lintIn({ "godot/scripts/kernel/rnggood.gd": "extends RefCounted\nfunc f(seed_val: int) -> int:\n\tvar rng := RandomNumberGenerator.new()\n\trng.seed = seed_val\n\treturn rng.randi()\n" });
  assert.strictEqual(good.status, 0, good.out);
});

test("REQ-0012-10 lint.mjs end to end: the view layer, clock.gd and tests keep their exemption (no false red)", () => {
  for (const rel of ["godot/scripts/ui/pulse.gd", "godot/scripts/ui/dev/dev_panel.gd", "godot/scripts/clock.gd", "godot/scripts/world_view.gd",
    "godot/scripts/map_widget.gd", "godot/scripts/main.gd", "godot/newhud_main.gd", "godot/tests/some_test.gd"]) {
    const r = lintIn({ [rel]: GD_BAD_CLOCK });
    assert.strictEqual(r.status, 0, `${rel} is exempt: ${r.out}`);
  }
});

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

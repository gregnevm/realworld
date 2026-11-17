"use strict";
// RealWorld — release.test.js : «чесна 1.01» (OD-166): версія й заяви релізу збігаються з кодом і CI.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const read = (p) => fs.readFileSync(path.join(root, p), "utf8");

test("версія 1.01: build_info.gd, CI-штамп і Android version/name збігаються", () => {
  const bi = read("godot/scripts/build_info.gd");
  assert.match(bi, /const VERSION := "1\.01"/);
  const wf = read(".github/workflows/godot.yml");
  assert.ok(wf.includes("'const VERSION := \"1.01\"'"), "CI-штамп має ту саму версію");
  assert.ok(wf.includes('version\\/name=\\"1.01.$GITHUB_RUN_NUMBER\\"'), "Android version/name = 1.01.<run>");
  assert.match(read("godot/export_presets.cfg"), /version\/name="1\.01"/);
});

test("реліз-маніфест 1.01 існує й перелічує відкриті людські гейти та заморожене", () => {
  const m = read("docs/release/1.01.md");
  for (const needle of ["Працює", "Не входить у 1.01", "Відкриті гейти", "REQ-0010-39", "REQ-0014-17"]) {
    assert.ok(m.includes(needle), `маніфест має містити «${needle}»`);
  }
});

test("кожна вимога, названа done у маніфесті як нова робота, справді done у спеці", () => {
  const m = read("docs/release/1.01.md");
  const specs = fs.readdirSync(path.join(root, "specs")).filter((f) => /^\d{4}-.*\.md$/.test(f)).map((f) => read("specs/" + f)).join("\n");
  const ids = [...m.matchAll(/`(REQ-\d{4}-\d+)` — done/g)].map((x) => x[1]);
  assert.ok(ids.length > 0, "маніфест називає хоч одну done-вимогу");
  for (const id of ids) {
    const row = specs.split("\n").find((l) => l.startsWith(`| ${id} `));
    assert.ok(row, `${id} є в спеках`);
    assert.match(row, /\| done/, `${id} у спеці має статус done`);
  }
});

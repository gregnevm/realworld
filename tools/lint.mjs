// RealWorld — tools/lint.mjs : zero-dependency lint for the no-build web slice.
//   • every game/js module parses (node --check) and is a classic script (no import/export);
//   • game/index.html loads exactly the modules on disk, in the contract order from AGENTS.md;
//   • every module wraps itself in a "use strict" IIFE over the RW namespace;
//   • no Math.random in sim paths (determinism: only the seeded G.rng / worldgen rng may roll);
//   • secret-scan: no Google API key (AIza…/AQ.…) in any tracked file, and .env.local stays gitignored
//     (tools/gen-art.mjs keeps the one-day Gemini key there);
//   • Godot-3 API tripwire over every tracked .gd (F1 — docs/process/automation.md);
//   • spec 0012 REQ-10: the sim corpus (godot/scripts minus the view layer and clock.gd) reads no clock and no
//     system-seeded RNG — time enters only through godot/scripts/clock.gd → Session → Sim.set_clock(now_ms).
import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import { execFileSync } from "node:child_process";

const root = path.dirname(path.dirname(url.fileURLToPath(import.meta.url)));
const jsDir = path.join(root, "game", "js");
const ORDER = ["util", "worldgen", "entities", "catalog_data", "progression", "render", "logistics", "ui", "input", "game"];
const problems = [];

const html = fs.readFileSync(path.join(root, "game", "index.html"), "utf8");
const loaded = [...html.matchAll(/<script src="js\/([a-z_]+)\.js"><\/script>/g)].map(m => m[1]);
if (loaded.join(",") !== ORDER.join(",")) problems.push(`index.html script order is [${loaded}] — contract is [${ORDER}]`);
const onDisk = fs.readdirSync(jsDir).filter(f => f.endsWith(".js")).map(f => f.slice(0, -3)).sort();
if (onDisk.join(",") !== [...ORDER].sort().join(",")) problems.push(`modules on disk [${onDisk}] differ from the loaded set`);

for (const name of ORDER) {
  const file = path.join(jsDir, name + ".js");
  try { execFileSync(process.execPath, ["--check", file], { stdio: "pipe" }); }
  catch (e) { problems.push(`${name}.js does not parse:\n${e.stderr}`); continue; }
  const src = fs.readFileSync(file, "utf8");
  if (/^\s*(import|export)\s/m.test(src)) problems.push(`${name}.js uses ES modules — the slice is classic scripts (no-build)`);
  if (name !== "catalog_data" && !/"use strict"/.test(src)) problems.push(`${name}.js lacks "use strict"`);
  if (name !== "catalog_data" && !/\(window\.RW\)/.test(src)) problems.push(`${name}.js is not an IIFE over window.RW`);
  if (["game", "logistics", "entities", "worldgen", "progression", "util"].includes(name) && /Math\.random/.test(src))
    problems.push(`${name}.js calls Math.random — sim paths must use the seeded rng`);
}
// secret-scan over everything git tracks or would track (cached + untracked-not-ignored)
const tracked = execFileSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], { cwd: root })
  .toString().split("\0").filter(Boolean);
const { KEY_SCAN_RE: KEY_RE } = await import("./art/lib.mjs"); // one definition of "what a Google key looks like"
for (const f of tracked) {
  const abs = path.join(root, f);
  let st; try { st = fs.statSync(abs); } catch { continue; }
  if (!st.isFile()) continue;
  // no size cap (a cap is a bypass); NULs stripped so UTF-16 text files are caught too
  const text = fs.readFileSync(abs, "latin1");
  if (KEY_RE.test(text) || KEY_RE.test(text.replace(/\0/g, ""))) problems.push(`${f} contains a Google API key (AIza…/AQ.…) — move it to .env.local`);
}
try { execFileSync("git", ["check-ignore", "-q", ".env.local"], { cwd: root }); }
catch { problems.push(".env.local is not gitignored — the Gemini key would be committable"); }

// F1 tripwire: models still emit Godot-3 API (yield, rand_range, export var, …) — the engine is pinned to 4.7.
// Patterns + Godot-4 replacements live in tools/process/lib.mjs (pinned by tests/process.test.js).
const { godotDrift } = await import("./process/lib.mjs");
let gdFiles = 0;
for (const f of tracked) {
  if (!f.endsWith(".gd")) continue;
  gdFiles++;
  let src; try { src = fs.readFileSync(path.join(root, f), "utf8"); } catch { continue; }
  for (const d of godotDrift(src)) problems.push(`${f}:${d.line} Godot-3 API (${d.hint}) — engine is 4.7; mark a false positive with "# drift-ok"`);
}

// REQ-0012-10: no wall-clock / system RNG in the sim. The corpus is "godot/scripts minus SIM_CORPUS_EXCLUDE"
// (tools/process/lib.mjs), so a NEW script is covered by default; run_tests `_t_no_wallclock_in_sim` is the
// in-engine twin and tests/process.test.js pins the two lists together. Exempt a false positive with "# clock-ok"
// (a clock/RNG call) or "# rng-ok" (an RNG seeded where the lint cannot see it).
const { simClockDrift, unseededRng, inSimCorpus } = await import("./process/lib.mjs");
const simSources = [];
for (const f of tracked) {
  if (!f.startsWith("godot/") || !inSimCorpus(f.slice("godot/".length))) continue;
  let src; try { src = fs.readFileSync(path.join(root, f), "utf8"); } catch { continue; }
  simSources.push({ file: f, src });
  for (const d of simClockDrift(src)) problems.push(`${f}:${d.line} sim reads the clock/system RNG (${d.hint}) — REQ-0012-10; mark a false positive with "# clock-ok"`);
}
for (const d of unseededRng(simSources))
  problems.push(`${d.file}:${d.line} RandomNumberGenerator${d.name ? ` «${d.name}»` : ""} is never given .seed/.state (a local one: later in its own function) — an unseeded RNG is system randomness (REQ-0012-10); mark with "# rng-ok" if it is seeded where lint cannot see`);

if (problems.length) { console.error("LINT FAILED:\n - " + problems.join("\n - ")); process.exit(1); }
console.log(`lint ok: ${ORDER.length} modules, contract order intact, ${tracked.length} files secret-scanned, ${gdFiles} .gd free of Godot-3 API, ${simSources.length} sim .gd free of clock/system RNG`);

// RealWorld — tools/lint.mjs : zero-dependency lint (phone-only product, OD-124).
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
const problems = [];

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
console.log(`lint ok: ${tracked.length} files secret-scanned, ${gdFiles} .gd free of Godot-3 API, ${simSources.length} sim .gd free of clock/system RNG`);

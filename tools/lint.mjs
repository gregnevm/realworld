// RealWorld — tools/lint.mjs : zero-dependency lint for the no-build web slice.
//   • every game/js module parses (node --check) and is a classic script (no import/export);
//   • game/index.html loads exactly the modules on disk, in the contract order from AGENTS.md;
//   • every module wraps itself in a "use strict" IIFE over the RW namespace;
//   • no Math.random in sim paths (determinism: only the seeded G.rng / worldgen rng may roll);
//   • secret-scan: no Google API key (AIza…/AQ.…) in any tracked file, and .env.local stays gitignored
//     (tools/gen-art.mjs keeps the one-day Gemini key there).
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

if (problems.length) { console.error("LINT FAILED:\n - " + problems.join("\n - ")); process.exit(1); }
console.log(`lint ok: ${ORDER.length} modules, contract order intact, ${tracked.length} files secret-scanned`);

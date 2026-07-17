// RealWorld — tools/sync-catalog.mjs : regenerate game/js/catalog_data.js from the single source
// of truth (godot/content/catalog.json). The web game is no-build, so the catalog ships as a plain
// classic script assigning RW.CATALOG. Run after any catalog.json change:
//   node tools/sync-catalog.mjs
// tests/catalog.test.js asserts the two stay byte-equal, so CI catches a forgotten regen.
import fs from "node:fs";
import path from "node:path";
import url from "node:url";

const root = path.dirname(path.dirname(url.fileURLToPath(import.meta.url)));
const src = path.join(root, "godot", "content", "catalog.json");
const dst = path.join(root, "game", "js", "catalog_data.js");

const cat = JSON.parse(fs.readFileSync(src, "utf8"));
const body =
  "/* RealWorld — catalog_data.js : GENERATED from godot/content/catalog.json — do not edit.\n" +
  "   Regenerate: node tools/sync-catalog.mjs  (kept in sync by tests/catalog.test.js) */\n" +
  "window.RW = window.RW || {};\n" +
  "window.RW.CATALOG = " + JSON.stringify(cat) + ";\n";
fs.writeFileSync(dst, body);
console.log("wrote", dst, fs.statSync(dst).size, "bytes");

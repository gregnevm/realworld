// RealWorld — tools/process/check-pr.mjs : the PR evidence gate (docs/process/README.md, P1/P2/P6/P7).
// CI (.github/workflows/process.yml) runs it on every pull_request event, body edits included.
//   node tools/process/check-pr.mjs                         # CI: body from $PR_BODY, diff = merge commit HEAD^1..HEAD
//   node tools/process/check-pr.mjs --body-file pr.md       # local: diff = origin/main...HEAD
//   node tools/process/check-pr.mjs --body-file pr.md --base main --files a.gd,b.md
// The body arrives through an env var, never interpolated into a shell — PR text is untrusted input.
import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import { execFileSync } from "node:child_process";
import { checkPr, classifyFiles } from "./lib.mjs";

const root = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), "..", "..");
const argv = process.argv.slice(2);
const opt = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined; };
const git = (...a) => execFileSync("git", a, { cwd: root, encoding: "utf8" });

const bodyFile = opt("--body-file");
const body = bodyFile ? fs.readFileSync(bodyFile, "utf8") : (process.env.PR_BODY || "");
const inCi = process.env.GITHUB_EVENT_NAME?.startsWith("pull_request");
const range = inCi ? ["HEAD^1", "HEAD"] : [`${opt("--base") || "origin/main"}...HEAD`];

let files = opt("--files")?.split(",").map((s) => s.trim()).filter(Boolean);
let changedLines = 0;
try {
  files ??= git("diff", "--name-only", ...range).split("\n").filter(Boolean);
  const sized = new Set(classifyFiles(files).sized);
  for (const row of git("diff", "--numstat", ...range).split("\n")) {
    const [add, del, f] = row.split("\t");
    if (f && sized.has(f) && add !== "-") changedLines += Number(add) + Number(del);
  }
} catch (e) {
  console.error(`check-pr: не вдалось прочитати диф (${range.join(" ")}): ${e.message.split("\n")[0]}`);
  files ??= [];
}

const { errors, warnings, classes: c, pr } = checkPr(body, files, { changedLines });
const summary = [
  `### PR-гейт процесу`,
  `Тип: \`${pr.type || "—"}\` · Стовп: \`${pr.pillar || "—"}\` · файлів: ${files.length} (продукт ${c.product.length}, UI ${c.ui.length}, правила ${c.rules.length}, арт ${c.art.length}) · рядків продукту: ${changedLines}`,
  "",
  ...errors.map((e) => `- ❌ ${e}`),
  ...warnings.map((w) => `- ⚠️ ${w}`),
  ...(errors.length || warnings.length ? [] : ["- ✅ Інтент, стовп і докази на місці."]),
  "",
  "Контракт — `.github/pull_request_template.md`; чому так — `docs/process/README.md` (P1, P2, P6, P7).",
].join("\n");

console.log(summary);
if (inCi) {
  for (const e of errors) console.log(`::error title=PR-гейт::${e}`);
  for (const w of warnings) console.log(`::warning title=PR-гейт::${w}`);
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary + "\n");
}
process.exit(errors.length ? 1 : 0);

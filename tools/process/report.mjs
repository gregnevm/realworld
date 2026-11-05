// RealWorld — tools/process/report.mjs : process health from the state files in git (docs/process/README.md, P10).
//   node tools/process/report.mjs           # full markdown report (CI job summary; `npm run process`)
//   node tools/process/report.mjs --brief   # ≤12-line digest; the owner-enabled SessionStart hook
//                                           # (docs/process/automation.md §5) injects it at startup and after compaction
// Reads only files; never the network. --brief never fails (a hook must not break a session).
import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import { mdTable, reworkVerdict, godotDrift, daysBetween } from "./lib.mjs";

const root = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), "..", "..");
const brief = process.argv.includes("--brief");
const read = (p) => { try { return fs.readFileSync(path.join(root, p), "utf8"); } catch { return ""; } };
const today = new Date().toISOString().slice(0, 10);

export const LIMITS = { agentsBytes: 40_000, playtestDays: 14, firstNewSpec: 10 };

function walk(dir, ext, out = []) {
  let ents = [];
  try { ents = fs.readdirSync(path.join(root, dir), { withFileTypes: true }); } catch { return out; }
  for (const e of ents) {
    const rel = path.posix.join(dir, e.name);
    if (e.isDirectory()) { if (!e.name.startsWith(".")) walk(rel, ext, out); }
    else if (e.name.endsWith(ext)) out.push(rel);
  }
  return out;
}

function collect() {
  const pillars = read("docs/design/pillars.md");
  const pillarStatus = (pillars.match(/^[>\s*_-]*Статус[*_\s]*:[*_\s]*([a-z]+)/imu) || [])[1]?.toLowerCase() || "відсутній";

  const decisions = mdTable(read("docs/design/decisions.md"), /\|\s*ID\s*\|/);
  const open = decisions.filter((d) => /^open/i.test(d["Статус"] || ""));

  const scope = mdTable(read("docs/design/scope.md"), /\|\s*Система\s*\|/);
  const unruled = scope.filter((r) => !(r["Вердикт власника"] || "").replace(/[—–-]/g, "").trim());

  const rework = mdTable(read("docs/process/rework-log.md"), /\|\s*Категорія\s*\|/)
    .map((r) => ({ category: r["Категорія"] }));
  const rv = reworkVerdict(rework);

  let playtests = [];
  try { playtests = fs.readdirSync(path.join(root, "docs/process/playtests")); } catch { /* none yet */ }
  const lastPlaytest = playtests.map((f) => (f.match(/^(\d{4}-\d{2}-\d{2})/) || [])[1]).filter(Boolean).sort().pop() || "";

  const llmNext = (read("docs/process/automation.md").match(/Наступна LLM Week:\s*\**(\d{4}-\d{2}-\d{2})/) || [])[1] || "";

  const agentsBytes = Buffer.byteLength(read("AGENTS.md"));

  const specs = walk("specs", ".md").filter((f) => /\/\d{4}-/.test(f));
  const specNum = (f) => Number(path.basename(f).slice(0, 4));
  const newWithoutReq = specs.filter((f) => specNum(f) >= LIMITS.firstNewSpec && !/REQ-\d{4}-\d+/.test(read(f)));

  const drift = [];
  for (const f of walk("godot", ".gd")) for (const d of godotDrift(read(f))) drift.push(`${f}:${d.line} ${d.hint}`);

  return { pillarStatus, decisions, open, scope, unruled, rv, lastPlaytest, llmNext, agentsBytes, specs, newWithoutReq, drift };
}

const kb = (b) => `${Math.round(b / 1000)} КБ`;
const pct = (a, n) => (n ? Math.round((100 * a) / n) : 0);

function warnings(s) {
  const w = [];
  if (s.pillarStatus !== "approved") w.push(`Стовпи — «${s.pillarStatus}»: G1 не пройдено, тож нова механіка = питання власнику (docs/design/pillars.md).`);
  if (!s.lastPlaytest) w.push("Людського плейтесту (G5) ще не було — ворота 0, 5, 6 людські (docs/process/playtest.md).");
  else if (daysBetween(s.lastPlaytest, today) > LIMITS.playtestDays) w.push(`Останній плейтест ${s.lastPlaytest} — понад ${LIMITS.playtestDays} днів тому.`);
  if (s.llmNext && s.llmNext < today) w.push(`LLM Week прострочена (план ${s.llmNext}) — docs/process/automation.md.`);
  if (s.agentsBytes > LIMITS.agentsBytes) w.push(`AGENTS.md ${kb(s.agentsBytes)} > ${kb(LIMITS.agentsBytes)}: насичення контексту (F6) — розщепити на core + підсистеми.`);
  if (s.newWithoutReq.length) w.push(`Спеки без REQ-ID: ${s.newWithoutReq.join(", ")} (specs/_TEMPLATE.md).`);
  if (s.drift.length) w.push(`Godot-3 API у ${s.drift.length} місцях (F1): ${s.drift.slice(0, 3).join("; ")}`);
  return w;
}

function renderBrief(s) {
  const lines = [
    "RealWorld · стан процесу (node tools/process/report.mjs --brief)",
    "• Вхід у будь-яку ігрову задачу — /gamedev; процес — docs/process/README.md; ролі — .claude/agents/.",
    "• Правила: без доказу нема «готово» · стовп/scope/баланс/модель вводу вирішує лише власник · коміт перед сесією.",
    `• Відкриті рішення власника (${s.open.length}): ${s.open.slice(0, 5).map((d) => `${d.ID} ${d["Рішення"]}`).join(" · ") || "—"}`,
    `• Scope: ${s.unruled.length}/${s.scope.length} систем без вердикту власника (docs/design/scope.md).`,
    `• Правки після агента: ${s.rv.n}, з них дизайн ${pct(s.rv.design, s.rv.n)}% → ${s.rv.verdict.split(" → ").pop()}.`,
    `• Плейтест: ${s.lastPlaytest || "ще не було"} · LLM Week: ${s.llmNext ? `до ${s.llmNext}` : "не запланована"}.`,
  ];
  for (const w of warnings(s).slice(0, 4)) lines.push(`⚠ ${w}`);
  return lines.join("\n");
}

function renderFull(s) {
  const w = warnings(s);
  const by = Object.entries(s.rv.by).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join(" · ") || "—";
  return [
    `## Здоров'я процесу · ${today}`,
    "",
    "| Сигнал | Стан |",
    "|---|---|",
    `| Стовпи (G1) | ${s.pillarStatus} |`,
    `| Рішення власника | відкрито ${s.open.length} з ${s.decisions.length} |`,
    `| Scope без вердикту | ${s.unruled.length} з ${s.scope.length} систем |`,
    `| Правки після агента | ${s.rv.n}: ${by} |`,
    `| → куди посилювати | ${s.rv.verdict} |`,
    `| Останній плейтест (G5) | ${s.lastPlaytest || "ще не було"} |`,
    `| Наступна LLM Week | ${s.llmNext || "—"} |`,
    `| AGENTS.md | ${kb(s.agentsBytes)} (поріг ${kb(LIMITS.agentsBytes)}) |`,
    `| Спеки / нові без REQ-ID | ${s.specs.length} / ${s.newWithoutReq.length} |`,
    `| Godot-3 API (F1) | ${s.drift.length} |`,
    "",
    "### Відкриті рішення власника",
    ...(s.open.length ? s.open.map((d) => `- **${d.ID}** ${d["Рішення"]}`) : ["- —"]),
    "",
    "### Попередження",
    ...(w.length ? w.map((x) => `- ⚠ ${x}`) : ["- немає"]),
    "",
  ].join("\n");
}

try {
  const s = collect();
  const out = brief ? renderBrief(s) : renderFull(s);
  console.log(out);
  if (!brief && process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, out + "\n");
} catch (e) {
  console.log(`process report failed: ${e.message}`);
  process.exit(brief ? 0 : 1);
}

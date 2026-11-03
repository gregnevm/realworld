// RealWorld — tools/smoke.mjs : headless browser playthrough of the web slice (Playwright + Chromium).
// Boots game/ over a local static server, spawns without OSM, drives the real UI grammar (hotkeys,
// drag-to-build, selection, modals, fast-forward through a raid, death screen) and asserts the HUD
// agrees with the sim. Screenshots land in --out <dir> (default: build/smoke). Exits non-zero on any
// console error, page error, or failed assertion.
//   node tools/smoke.mjs [--out build/smoke] [--port 8777]
import { createRequire } from "node:module";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import url from "node:url";

const root = path.dirname(path.dirname(url.fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const outDir = path.resolve(root, opt("--out", "build/smoke"));
const port = +opt("--port", 8777);
fs.mkdirSync(outDir, { recursive: true });
// playwright is a dev-only tool dependency: resolved via require so a global install (NODE_PATH) works too
const { chromium } = createRequire(import.meta.url)("playwright");

// ---- tiny static server for game/ (no deps, no python) ----
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png" };
const server = http.createServer((req, res) => {
  const p = path.join(root, "game", decodeURIComponent((req.url || "/").split("?")[0]).replace(/\/$/, "/index.html"));
  if (!p.startsWith(path.join(root, "game"))) { res.writeHead(403); res.end(); return; }
  fs.readFile(p, (err, data) => {
    if (err) { res.writeHead(404); res.end("nope"); return; }
    res.writeHead(200, { "content-type": MIME[path.extname(p)] || "application/octet-stream" }); res.end(data);
  });
});
await new Promise(r => server.listen(port, "127.0.0.1", r));

const problems = [];
const check = (cond, msg) => { if (!cond) { problems.push(msg); console.error("  ✗", msg); } else console.log("  ✓", msg); };

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
page.on("pageerror", e => problems.push("pageerror: " + e.message));
page.on("console", m => { if (m.type() === "error") problems.push("console.error: " + m.text()); });
page.on("dialog", d => d.accept());
// modals pop in over 180 ms — settle before capturing so every frame is the finished state
const shot = async (name) => { await page.waitForTimeout(260); await page.screenshot({ path: path.join(outDir, name + ".png") }); };
// advance the sim deterministically (speed 0 keeps the rAF loop from racing us)
const ff = (seconds) => page.evaluate((s) => { const G = RW.G; G.speed = 0; for (let i = 0; i < s * 30; i++) RW.update(G, 1 / 30); }, seconds);
const state = () => page.evaluate(() => {
  const G = RW.G;
  return { day: G.time.day, hp: G.player.hp, stock: { ...G.base.stock }, enemies: G.enemies.length, buildings: G.buildings.length,
    kinds: G.buildings.map(b => b.kind), dead: !!G._dead, speed: G.speed, tile: G.tile, selectedBuild: G.selectedBuild, stats: { ...G.stats } };
});

try {
  console.log("spawn screen");
  await page.goto(`http://127.0.0.1:${port}/`);
  await page.waitForSelector("#spawnBtn");
  check(await page.$eval("#previewInfo", e => e.textContent.includes("seed")), "spawn preview renders the deterministic map + seed");
  await page.fill("#lat", "49.8397"); await page.fill("#lon", "24.0297");   // Lviv via the inputs
  await page.waitForTimeout(250);
  const seedLviv = await page.$eval("#previewInfo", e => e.textContent);
  await page.click("#presets .preset");                                       // back to Kyiv via preset
  await page.waitForTimeout(250);
  check((await page.$eval("#previewInfo", e => e.textContent)) !== seedLviv, "preview changes with the coordinates");
  await shot("01-spawn");
  await page.evaluate(() => { document.getElementById("useOsm").checked = false; });
  await page.click("#spawnBtn");
  await page.waitForFunction(() => window.RW && RW.G && RW.G.buildings.length === 1);
  await page.evaluate(() => { RW.G.speed = 0; });

  console.log("hud + inspect");
  const s0 = await state();
  check(s0.kinds[0] === "storage", "landing crate placed");
  check(await page.$eval("#clockDay", e => e.textContent === "День 1"), "clock bound to the sim day");
  const crate = await page.evaluate(() => { const b = RW.G.buildings[0]; return RW.tileToScreen(RW.G, b.x + 0.5, b.y + 0.5); });
  await page.mouse.move(crate.x, crate.y);
  await page.waitForTimeout(80);
  check(await page.$eval("#inspect", e => !e.classList.contains("hidden") && e.textContent.includes("Склад")), "hover inspect names the building under the cursor");

  console.log("build: hotkey + drag run of walls");
  await page.keyboard.press("1");
  check((await state()).selectedBuild === "wall", "hotkey 1 arms the wall");
  const p0 = await page.evaluate(() => { const p = RW.G.player; return RW.tileToScreen(RW.G, Math.floor(p.px) - 2, Math.floor(p.py) - 2); });
  const t = await page.evaluate(() => RW.G.tile);
  await page.mouse.move(p0.x + t / 2, p0.y + t / 2);
  await page.mouse.down();
  await page.mouse.move(p0.x + t * 4.5, p0.y + t / 2, { steps: 4 });
  await shot("02-drag-ghost");
  await page.mouse.up();
  const s1 = await state();
  check(s1.kinds.filter(k => k === "wall").length >= 3, `drag placed a run of walls (${s1.kinds.filter(k => k === "wall").length})`);
  check(s1.stock.stone < s0.stock.stone, "walls cost stone from the stockpile");
  await page.keyboard.press("Escape");
  check((await state()).selectedBuild === null, "Esc leaves build mode");

  console.log("select → demolish refunds");
  const wall = await page.evaluate(() => { const b = RW.G.buildings.find(b => b.kind === "wall"); return RW.tileToScreen(RW.G, b.x + 0.5, b.y + 0.5); });
  await page.mouse.click(wall.x, wall.y);
  await page.waitForTimeout(60);
  check(await page.$eval("#selCard", e => !e.classList.contains("hidden") && e.textContent.includes("Стіна")), "clicking own wall opens the selection card");
  await shot("03-selection");
  const stoneBefore = (await state()).stock.stone;
  await page.keyboard.press("Delete");
  const s2 = await state();
  check(s2.stock.stone === stoneBefore + 2, "Del demolishes and refunds half the stone");

  console.log("zoom + speed + modals");
  await page.keyboard.press("+"); await page.keyboard.press("+");
  check((await state()).tile > t, "+ zooms in");
  await page.mouse.wheel(0, 300);
  check((await state()).tile < t + 6, "wheel zooms out");
  await page.keyboard.press(" ");
  check((await state()).speed > 0, "space unpauses");
  await page.keyboard.press(" ");
  check((await state()).speed === 0, "space pauses again");
  check(await page.$eval("#pauseVeil", e => !e.classList.contains("hidden")), "pause veil shown while paused");
  for (const [key, modal] of [["r", "researchModal"], ["m", "worldModal"], ["l", "logModal"], ["h", "helpModal"]]) {
    await page.keyboard.press(key);
    check(await page.$eval("#" + modal, e => !e.classList.contains("hidden")), `${key.toUpperCase()} opens ${modal}`);
    if (modal === "researchModal") await shot("04-research");
    if (modal === "worldModal") await shot("05-world");
    await page.keyboard.press("Escape");
    check(await page.$eval("#" + modal, e => e.classList.contains("hidden")), `Esc closes ${modal}`);
  }
  await page.keyboard.press("Escape");
  check(await page.$eval("#menuModal", e => !e.classList.contains("hidden")), "Esc with nothing to cancel opens the menu");
  await shot("06-menu");
  await page.click("#menuResume");

  console.log("research pipeline: locked slot plans its path, bench researches it");
  await page.evaluate(() => { const G = RW.G; G.raid.next = 1e9; G.base.stock.wood += 200; G.base.stock.stone += 100; const p = G.player; G.selectedBuild = "research_bench"; RW.tryBuild(G, Math.floor(p.px) + 2, Math.floor(p.py) + 2);
    G.selectedBuild = "bed"; RW.tryBuild(G, Math.floor(p.px), Math.floor(p.py) + 1); G.selectedBuild = null; });
  await page.click("#buildbar .bld.locked");
  check(await page.evaluate(() => RW.G.research.queue.length + (RW.G.research.active ? 1 : 0) > 0), "clicking a locked slot queues its research path");
  await ff(400);
  check(await page.evaluate(() => RW.G.research.unlockedCount() > 0), "a bench turns time into unlocked research");
  check(!(await state()).dead, "fed and rested next to crate + bed, the player survives the research fast-forward");
  check(await page.$$eval("#buildbar .bld.locked", els => els.length) < 4, "build bar unlocks slots as research lands");

  console.log("raid: fast-forward to the wave, defend, resolve");
  await page.evaluate(() => { const G = RW.G; G.raid.next = G.raid.timer + 13; });
  await ff(14);
  const s3 = await state();
  check(s3.enemies > 0, `raid wave spawned (${s3.enemies} raiders)`);
  check(await page.$eval("#raidBanner", e => !e.classList.contains("hidden")), "raid banner visible");
  check(await page.evaluate(() => RW.raidSpawnCells(RW.G).length > 0), "raiders spawn on cells that can reach the base");
  await ff(10);
  await page.evaluate(() => { RW.G.hover = null; });
  await shot("07-raid");
  await ff(150);
  const s4 = await state();
  check(s4.dead || s4.enemies === 0, `the raid resolved within 160 s (dead=${s4.dead}, kills=${s4.stats.kills}, raids=${s4.stats.raids})`);
  check(await page.$eval("#raidBanner", e => e.classList.contains("hidden")), "banner clears when the raid ends");

  console.log("death: starvation ends the run honestly");
  await page.evaluate(() => { const G = RW.G; G.player.hp = 0.5; G.player.hunger = 0; G.enemies.length = 0; RW.update(G, 1); });
  await page.waitForTimeout(100);
  check(await page.$eval("#deathModal", e => !e.classList.contains("hidden")), "death screen opens with the run summary");
  check(await page.$eval("#deathStats", e => e.textContent.includes("Прожито")), "death summary lists the stats");
  await shot("08-death");


  console.log("persistence: autosave survives a reload, continue button names the place");
  // death wipes the save by design; write a fresh run and reload into "continue"
  await page.evaluate(() => { const map = RW.generateMap(50.4501, 30.5234, 56); map.placeName = "Київ"; const G = RW.newGame(map); G.time.day = 3; RW.saveGame(G); });
  await page.reload();
  await page.waitForSelector("#continueBtn");
  check(await page.$eval("#continueBtn", e => e.style.display !== "none" && e.textContent.includes("день 3")), "continue button shows the saved day");
  await page.click("#continueBtn");
  await page.waitForFunction(() => window.RW && RW.G && RW.G.time.day === 3);
  check(true, "save restored into a live game");
  await page.evaluate(() => { RW.G.speed = 0; });
  await shot("09-restored");
} catch (e) {
  problems.push("exception: " + (e && e.stack || e));
} finally {
  await browser.close();
  server.close();
}

if (problems.length) { console.error("\nSMOKE FAILED:\n - " + problems.join("\n - ")); process.exit(1); }
console.log("\nSMOKE OK → " + outDir);

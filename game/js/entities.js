/* RealWorld — entities.js : data tables for resources, buildings, nodes, raiders */
(function (RW) {
  "use strict";

  // resource kinds (also used as stockpile keys)
  RW.RES = {
    wood: { label: "Дерево", icon: "🪵", color: "var(--wood)" },
    stone: { label: "Камінь", icon: "🪨", color: "var(--stone)" },
    food: { label: "Їжа", icon: "🍖", color: "var(--food)" },
    scrap: { label: "Брухт", icon: "⚙", color: "var(--scrap)" },
    planks: { label: "Дошки", icon: "🟫", color: "var(--plank)" },
    components: { label: "Компоненти", icon: "🔩", color: "var(--comp)" }
  };
  RW.RES_ORDER = ["wood", "stone", "food", "scrap", "planks", "components"];

  // gatherable nodes -> what they yield
  RW.NODEINFO = {
    tree: { res: "wood", time: 1.3, icon: "🌲", color: "#3c7a3a" },
    rock: { res: "stone", time: 1.8, icon: "🪨", color: "#8b9099" },
    bush: { res: "food", time: 1.0, icon: "🫐", color: "#6fae54" },
    scrap: { res: "scrap", time: 1.5, icon: "⚙", color: "#86d0d6" }
  };

  // buildable structures. `research` = the gating node in the content catalog's tech tree
  // (godot/content/catalog.json — the same gate ids the Godot kernel uses); absent = ungated.
  // `blocks` = impassable for everyone; `blocksEnemies` = the player walks through, raiders must smash it
  // (a door is a weak wall to a raider and an opening to you). `line` = drag-to-build draws a run of them.
  // `desc` is the one-line tooltip the build bar shows (what the thing DOES, not what it costs).
  RW.BUILDINGS = {
    wall: { name: "Стіна", icon: "🧱", cost: { stone: 5 }, hp: 120, blocks: true, line: true,
      desc: "Непрохідна для всіх. Рейдери ламають її, щоб дістатись бази." },
    door: { name: "Двері", icon: "🚪", cost: { wood: 4 }, hp: 80, blocks: false, blocksEnemies: true, line: true,
      desc: "Ти проходиш, рейдери — ні (мусять виламати). Слабша за стіну." },
    floor: { name: "Підлога", icon: "▢", cost: { wood: 1 }, hp: 30, blocks: false, line: true,
      desc: "Позначає внутрішній простір бази. Дешево." },
    storage: { name: "Склад", icon: "📦", cost: { wood: 10 }, hp: 90, blocks: false, capacity: 250,
      desc: "+250 місткості. Стоячи поруч, ти автоматично здаєш здобич і їси." },
    workbench: { name: "Верстак", icon: "🛠", cost: { wood: 18, stone: 4 }, hp: 100, blocks: true,
      desc: "Безперервно переробляє 2 дерева → 1 дошку (потрібне «Столярство»)." },
    bed: { name: "Ліжко", icon: "🛏", cost: { wood: 14 }, hp: 60, blocks: false,
      desc: "Стань поруч без наказів — заснеш і відновиш відпочинок." },
    research_bench: { name: "Дослідний стіл", icon: "🔬", cost: { wood: 30, stone: 8 }, hp: 100, blocks: true,
      desc: "Генерує прогрес досліджень по дереву технологій (R)." },
    shelf: { name: "Полиця", icon: "🗄", cost: { planks: 8 }, hp: 70, blocks: false, capacity: 60, research: "carpentry",
      desc: "+60 місткості складу." },
    grow_zone: { name: "Грядка", icon: "🌱", cost: { wood: 2 }, hp: 20, blocks: false, research: "agriculture", line: true,
      desc: "Повільно вирощує їжу прямо на склад." },
    turret: { name: "Турель", icon: "🔫", cost: { scrap: 14, components: 2 }, hp: 90, blocks: true, range: 6.2, dps: 14, research: "machining",
      desc: "Автоматично стріляє по рейдерах у радіусі 6 клітин." },
    spike_trap: { name: "Пастка", icon: "🪤", cost: { wood: 10, scrap: 6 }, hp: 50, blocks: false, trapDps: 16, research: "fortification", line: true,
      desc: "Ранить рейдерів, що на неї наступають; зношується." }
  };
  RW.BUILD_ORDER = ["wall", "door", "floor", "storage", "workbench", "bed", "research_bench", "shelf", "grow_zone", "turret", "spike_trap"];
  // keyboard slots for the build bar, in BUILD_ORDER order (1..9 then 0, like the Godot BuildBar);
  // anything past the tenth slot is mouse-only
  RW.BUILD_KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
  RW.buildKeyOf = (kind) => RW.BUILD_KEYS[RW.BUILD_ORDER.indexOf(kind)] || "";
  // demolish refund: half of the build cost, rounded down (never less than 0)
  RW.refundOf = function (cost) {
    const out = {};
    for (const k in cost) { const v = Math.floor(cost[k] / 2); if (v > 0) out[k] = v; }
    return out;
  };
  // repair price: 30% of the build cost scaled by missing hp fraction, at least 1 of each resource
  RW.repairCostOf = function (def, hp) {
    const miss = RW.clamp(1 - hp / def.hp, 0, 1);
    const out = {};
    for (const k in def.cost) { const v = Math.ceil(def.cost[k] * 0.3 * miss); if (v > 0) out[k] = v; }
    return out;
  };

  RW.canAfford = function (stock, cost) {
    for (const k in cost) if ((stock[k] || 0) < cost[k]) return false;
    return true;
  };
  RW.payCost = function (stock, cost) {
    for (const k in cost) stock[k] -= cost[k];
  };
  RW.costStr = function (cost) {
    return Object.keys(cost).map(k => RW.RES[k].icon + cost[k]).join(" ");
  };
  // which resources are short for `cost` (for the build bar to highlight), [] when affordable
  RW.missingFor = function (stock, cost) {
    const out = [];
    for (const k in cost) if ((stock[k] || 0) < cost[k]) out.push(k);
    return out;
  };

  // ---- raiders ----
  RW.makeRaider = function (x, y, day) {
    const tough = 1 + day * 0.18;
    return {
      x, y, px: x, py: y,
      hp: 28 * tough, maxhp: 28 * tough,
      dmg: 7 + day * 1.2, speed: 2.4,
      atkCd: 0, target: null, path: null, pathCd: 0, hitFlash: 0
    };
  };

  // wave composition grows with the day count: 2 for the first two days, then +1 every ~1.7 days,
  // capped at 12 (a solo pawn with no turret can take 2–3 in melee; beyond that walls/traps must work)
  RW.raidWaveSize = function (day) {
    return Math.min(2 + Math.floor((day - 1) * 0.6), 12);
  };

})(window.RW);

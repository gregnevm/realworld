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
  RW.BUILDINGS = {
    wall: { name: "Стіна", icon: "🧱", cost: { stone: 5 }, hp: 120, blocks: true },
    door: { name: "Двері", icon: "🚪", cost: { wood: 4 }, hp: 80, blocks: false },
    floor: { name: "Підлога", icon: "▢", cost: { wood: 1 }, hp: 30, blocks: false },
    storage: { name: "Склад", icon: "📦", cost: { wood: 10 }, hp: 90, blocks: false, capacity: 250 },
    workbench: { name: "Верстак", icon: "🛠", cost: { wood: 18, stone: 4 }, hp: 100, blocks: true },
    bed: { name: "Ліжко", icon: "🛏", cost: { wood: 14 }, hp: 60, blocks: false },
    research_bench: { name: "Дослідний стіл", icon: "🔬", cost: { wood: 30, stone: 8 }, hp: 100, blocks: true },
    shelf: { name: "Полиця", icon: "🗄", cost: { planks: 8 }, hp: 70, blocks: false, capacity: 60, research: "carpentry" },
    grow_zone: { name: "Грядка", icon: "🌱", cost: { wood: 2 }, hp: 20, blocks: false, research: "agriculture" },
    turret: { name: "Турель", icon: "🔫", cost: { scrap: 14, components: 2 }, hp: 90, blocks: true, range: 6.2, dps: 14, research: "machining" },
    spike_trap: { name: "Пастка", icon: "🪤", cost: { wood: 10, scrap: 6 }, hp: 50, blocks: false, trapDps: 16, research: "fortification" }
  };
  RW.BUILD_ORDER = ["wall", "door", "floor", "storage", "workbench", "bed", "research_bench", "shelf", "grow_zone", "turret", "spike_trap"];

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

  // wave composition grows with the day count
  RW.raidWaveSize = function (day) {
    return Math.min(2 + Math.floor(day * 0.9), 12);
  };

})(window.RW);

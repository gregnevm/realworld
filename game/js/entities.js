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

  // buildable structures
  RW.BUILDINGS = {
    wall: { name: "Стіна", icon: "🧱", cost: { stone: 5 }, hp: 120, blocks: true },
    door: { name: "Двері", icon: "🚪", cost: { wood: 4 }, hp: 80, blocks: false },
    floor: { name: "Підлога", icon: "▢", cost: { wood: 1 }, hp: 30, blocks: false },
    storage: { name: "Склад", icon: "📦", cost: { wood: 10 }, hp: 90, blocks: false, capacity: 250 },
    workbench: { name: "Верстак", icon: "🛠", cost: { wood: 18, stone: 4 }, hp: 100, blocks: true },
    bed: { name: "Ліжко", icon: "🛏", cost: { wood: 14 }, hp: 60, blocks: false },
    turret: { name: "Турель", icon: "🔫", cost: { scrap: 14, components: 2 }, hp: 90, blocks: true, range: 6.2, dps: 14 }
  };
  RW.BUILD_ORDER = ["wall", "door", "floor", "storage", "workbench", "bed", "turret"];

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

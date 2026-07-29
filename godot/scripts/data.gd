# RealWorld — data.gd : pure data tables + helpers (no scene deps; testable headless)
extends RefCounted

const RES := {
	"wood": {"label": "Дерево", "icon": "🪵", "color": "c08a4a"},
	"stone": {"label": "Камінь", "icon": "🪨", "color": "9aa3ab"},
	"food": {"label": "Їжа", "icon": "🍖", "color": "e06a5a"},
	"scrap": {"label": "Брухт", "icon": "⚙", "color": "86d0d6"},
	"planks": {"label": "Дошки", "icon": "🟫", "color": "e0b070"},
	"components": {"label": "Компоненти", "icon": "🔩", "color": "b58cff"},
}
const RES_ORDER := ["wood", "stone", "food", "scrap", "planks", "components"]

const NODEINFO := {
	"tree": {"res": "wood", "time": 1.3, "color": "3c7a3a"},
	"rock": {"res": "stone", "time": 1.8, "color": "8b9099"},
	"bush": {"res": "food", "time": 1.0, "color": "6fae54"},
	"scrap": {"res": "scrap", "time": 1.5, "color": "86d0d6"},
}

const BUILDINGS := {
	"wall": {"name": "Стіна", "cost": {"stone": 5}, "hp": 120.0, "blocks": true},
	"door": {"name": "Двері", "cost": {"wood": 4}, "hp": 80.0, "blocks": false},
	"floor": {"name": "Підлога", "cost": {"wood": 1}, "hp": 30.0, "blocks": false},
	"storage": {"name": "Склад", "cost": {"wood": 10}, "hp": 90.0, "blocks": false, "capacity": 250},
	"workbench": {"name": "Верстак", "cost": {"wood": 18, "stone": 4}, "hp": 100.0, "blocks": true, "craft": true},
	"bed": {"name": "Ліжко", "cost": {"wood": 14}, "hp": 60.0, "blocks": false, "bed": true},
	"turret": {"name": "Турель", "cost": {"scrap": 14, "components": 2}, "hp": 90.0, "blocks": true, "range": 6.2, "dps": 14.0, "research": "machining"},
	# Research station: generates research-points/game-day while it stands (session.research_rate);
	# drives the tech pipeline (kernel/progression.gd). Appended last so keys 1–7 keep their buildings.
	"research_bench": {"name": "Дослідницький стіл", "cost": {"wood": 25, "stone": 6}, "hp": 100.0, "blocks": true, "research_rate": 1.0},
	# Batch 8a: environment emitters — campfire warms nearby cells (extra.heat), torch lights them (extra.light).
	"campfire": {"name": "Багаття", "cost": {"wood": 8}, "hp": 30.0, "blocks": false, "extra": {"heat": 4.0, "light": true}},
	"torch": {"name": "Смолоскип", "cost": {"wood": 3}, "hp": 15.0, "blocks": false, "extra": {"light": true}},
	# Контент-пак (постапок): відкопана техніка Старого світу + польові укріплення.
	# `research` — id дослідження з catalog.json, що відкриває будівлю (гейт живить kernel/progression
	# через session -> sim.research_unlocked). Неолітичне ядро (стіни/верстак/ліжко/вогонь) — без воріт.
	"lamp": {"name": "Лампа", "cost": {"scrap": 6, "components": 1}, "hp": 25.0, "blocks": false, "extra": {"light": true}, "research": "smelting"},
	"heater": {"name": "Обігрівач", "cost": {"scrap": 12, "components": 2}, "hp": 40.0, "blocks": false, "extra": {"heat": 6.0}, "research": "smelting"},
	"spike_trap": {"name": "Шипи", "cost": {"scrap": 8, "wood": 4}, "hp": 50.0, "blocks": false, "trap_dps": 16.0, "research": "hunting"},
}

# Українські назви ворітних досліджень (дзеркало label-ів catalog.json — для повідомлень сима)
const RESEARCH_LABEL := {
	"hunting": "Полювання", "masonry": "Каменярство", "smelting": "Виплавка",
	"smithing": "Ковальство", "machining": "Механіка",
}
const BUILD_ORDER := ["wall", "door", "floor", "storage", "workbench", "bed", "turret", "research_bench", "campfire", "torch", "spike_trap", "heater", "lamp"]

# craftable equipment (spec 0001). tool -> faster gather; weapon -> more melee damage.
const ITEMS := {
	"axe": {"name": "Сокира", "slot": "tool", "gather_mult": 1.6, "recipe": {"wood": 15, "stone": 10}},
	"pick": {"name": "Кайло", "slot": "tool", "gather_mult": 1.9, "recipe": {"wood": 12, "stone": 16}},
	"club": {"name": "Кийок", "slot": "weapon", "dmg_bonus": 6.0, "recipe": {"wood": 20}},
	"spear": {"name": "Спис", "slot": "weapon", "dmg_bonus": 12.0, "recipe": {"wood": 15, "scrap": 8}},
	# Контент-пак: топ-тір інструмент, далекий бій і броня (slot "armor", dmg_cut ріже вхідний урон;
	# `insul` — °C тепла до відчутної температури тіла: жилет гріє, голий метал панцира — ледве).
	# `research` — гейт із дерева досліджень (як у будівель); стартова четвірка — без воріт.
	"sledge": {"name": "Кувалда", "slot": "tool", "gather_mult": 2.2, "recipe": {"wood": 20, "stone": 20, "scrap": 10}, "research": "masonry"},
	"bow": {"name": "Лук", "slot": "weapon", "dmg_bonus": 18.0, "recipe": {"wood": 25, "scrap": 6}, "research": "hunting"},
	"vest": {"name": "Жилет із брухту", "slot": "armor", "dmg_cut": 0.3, "insul": 3.0, "recipe": {"scrap": 18}, "research": "smelting"},
	"plate": {"name": "Панцир Старого світу", "slot": "armor", "dmg_cut": 0.5, "insul": 1.0, "recipe": {"scrap": 24, "components": 3}, "research": "smithing"},
}
const ITEM_ORDER := ["axe", "pick", "club", "spear", "sledge", "bow", "vest", "plate"]

# spawn presets for the address pickers (ONE source: lifecycle.gd reads it; main.gd is frozen with
# its own historical copy — new surfaces must reference this table, not paste the list again)
const SPAWN_PRESETS := [
	{"name": "Київ", "lat": 50.4501, "lon": 30.5234},
	{"name": "Львів", "lat": 49.8397, "lon": 24.0297},
	{"name": "Манхеттен", "lat": 40.7549, "lon": -73.9840},
	{"name": "Кіото", "lat": 35.0116, "lon": 135.7681},
	{"name": "Рейк'явік", "lat": 64.1466, "lon": -21.9426},
]

# real-world trade hubs + what each outpost trades
const HUBS := [
	{"name": "Київ", "lat": 50.4501, "lon": 30.5234},
	{"name": "Львів", "lat": 49.8397, "lon": 24.0297},
	{"name": "Одеса", "lat": 46.4825, "lon": 30.7233},
	{"name": "Харків", "lat": 49.9935, "lon": 36.2304},
	{"name": "Варшава", "lat": 52.2297, "lon": 21.0122},
	{"name": "Краків", "lat": 50.0647, "lon": 19.9450},
	{"name": "Кишинів", "lat": 47.0105, "lon": 28.8638},
]
const OFFERS := [
	{"buys": "wood", "sells": "components", "rate": 6},
	{"buys": "food", "sells": "scrap", "rate": 1},
	{"buys": "stone", "sells": "food", "rate": 1},
	# Контент-пак: глибша торгова мережа (5 хабів на регіон замість 3)
	{"buys": "planks", "sells": "components", "rate": 3},
	{"buys": "scrap", "sells": "food", "rate": 1},
	{"buys": "stone", "sells": "wood", "rate": 1},
]

# ---- capsules (spec 0002): RimWorld-style drop pods ----
const CAPSULE_BASE_RADIUS_KM := 100.0   # daily base capsule: one person, ≤100 km, once/day
const CAPSULE_DAILY_CHARGES := 1

# ---- social tiers (spec 0002) ----
const SOCIAL_TIERS := ["player", "clan", "alliance", "empire"]
const TIER_ICON := {"player": "🧍", "clan": "🛡", "alliance": "🤝", "empire": "👑"}
const STANCE_ICON := {"ally": "🟢", "neutral": "🟡", "hostile": "🔴"}

static func can_afford(stock: Dictionary, cost: Dictionary) -> bool:
	for k in cost:
		if float(stock.get(k, 0)) < float(cost[k]):
			return false
	return true

static func pay_cost(stock: Dictionary, cost: Dictionary) -> void:
	for k in cost:
		stock[k] = stock[k] - cost[k]

static func cost_str(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%s%d" % [RES[k].icon, cost[k]])
	return " ".join(parts)

static func make_raider(px: float, py: float, day: int) -> Dictionary:
	var tough := 1.0 + day * 0.18
	return {
		"px": px, "py": py, "face": 0.0,
		"hp": 28.0 * tough, "maxhp": 28.0 * tough,
		"dmg": 7.0 + day * 1.2, "speed": 2.4,
		"atk_cd": 0.0, "path": [], "path_cd": 0.0, "hit_flash": 0.0,
		"tx": -1, "ty": -1, "dead": false,
	}

# Лор: постапокаліпсис. Автоматика Старого світу пережила Колапс — патрульні роботи досі обходять
# руїни за мертвими маршрутами. Повільний танк проти швидких рейдерів; розібраний робот — головне
# джерело брухту та вцілілої електроніки (компонентів) у ранній грі.
static func make_patrol_bot(px: float, py: float, day: int) -> Dictionary:
	var tough := 1.0 + day * 0.06
	return {
		"px": px, "py": py, "face": 0.0,
		"hp": 52.0 * tough, "maxhp": 52.0 * tough,
		"dmg": 9.0 + day * 0.8, "speed": 1.55,
		"atk_cd": 0.0, "path": [], "path_cd": 0.0, "hit_flash": 0.0,
		"tx": -1, "ty": -1, "dead": false,
		"kind": "bot",
	}

# Патруль росте повільно: одиночний обхідник у перші дні, ланка до 4 машин пізніше.
static func patrol_size(day: int) -> int:
	return clampi(1 + int(day) / 4, 1, 4)

static func raid_wave_size(day: int) -> int:
	return min(2 + int(day * 0.9), 12)

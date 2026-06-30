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
	"turret": {"name": "Турель", "cost": {"scrap": 14, "components": 2}, "hp": 90.0, "blocks": true, "range": 6.2, "dps": 14.0},
}
const BUILD_ORDER := ["wall", "door", "floor", "storage", "workbench", "bed", "turret"]

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
]

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

static func raid_wave_size(day: int) -> int:
	return min(2 + int(day * 0.9), 12)

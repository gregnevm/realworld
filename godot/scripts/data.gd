# RealWorld — data.gd : pure data tables + helpers (no scene deps; testable headless)
#
# Batch 7: the legacy const tables stay as the 6-resource / 7-building CORE (save-compat, JS parity),
# and the FULL content tree from kernel/catalog.gd is merged in at class load via `static var` tables.
# Every existing call site (GameData.BUILDINGS[kind], NODEINFO[kind], ITEMS[id]) keeps working — it
# just sees the whole catalogue now. One truth: the catalogue is authored ONCE in catalog.gd.
extends RefCounted

const Catalog = preload("res://scripts/kernel/catalog.gd")

const RES := {
	"wood": {"label": "Дерево", "icon": "🪵", "color": "c08a4a"},
	"stone": {"label": "Камінь", "icon": "🪨", "color": "9aa3ab"},
	"food": {"label": "Їжа", "icon": "🍖", "color": "e06a5a"},
	"scrap": {"label": "Брухт", "icon": "⚙", "color": "86d0d6"},
	"planks": {"label": "Дошки", "icon": "🟫", "color": "e0b070"},
	"components": {"label": "Компоненти", "icon": "🔩", "color": "b58cff"},
}
const RES_ORDER := ["wood", "stone", "food", "scrap", "planks", "components"]

const NODEINFO_CORE := {
	"tree": {"res": "wood", "time": 1.3, "color": "3c7a3a"},
	"rock": {"res": "stone", "time": 1.8, "color": "8b9099"},
	"bush": {"res": "food", "time": 1.0, "color": "6fae54"},
	"scrap": {"res": "scrap", "time": 1.5, "color": "86d0d6"},
}

const BUILDINGS_CORE := {
	"wall": {"name": "Стіна", "cost": {"stone": 5}, "hp": 120.0, "blocks": true, "cat": "structure", "icon": "🧱"},
	"door": {"name": "Двері", "cost": {"wood": 4}, "hp": 80.0, "blocks": false, "cat": "structure", "icon": "🚪"},
	"floor": {"name": "Підлога", "cost": {"wood": 1}, "hp": 30.0, "blocks": false, "cat": "structure", "icon": "🟫"},
	"storage": {"name": "Склад", "cost": {"wood": 10}, "hp": 90.0, "blocks": false, "capacity": 250, "cat": "storage", "icon": "📦"},
	"workbench": {"name": "Верстак", "cost": {"wood": 18, "stone": 4}, "hp": 100.0, "blocks": true, "craft": true, "cat": "production", "station": "workbench", "icon": "🛠"},
	"bed": {"name": "Ліжко", "cost": {"wood": 14}, "hp": 60.0, "blocks": false, "bed": true, "cat": "comfort", "icon": "🛏"},
	"turret": {"name": "Турель", "cost": {"scrap": 14, "components": 2}, "hp": 90.0, "blocks": true, "range": 6.2, "dps": 14.0, "cat": "defense", "icon": "🎯"},
}
const BUILD_ORDER := ["wall", "door", "floor", "storage", "workbench", "bed", "turret"]

# craftable equipment (spec 0001). tool -> faster gather; weapon -> more melee damage.
const ITEMS_CORE := {
	"axe": {"name": "Сокира", "slot": "tool", "gather_mult": 1.6, "recipe": {"wood": 15, "stone": 10}},
	"pick": {"name": "Кайло", "slot": "tool", "gather_mult": 1.9, "recipe": {"wood": 12, "stone": 16}},
	"club": {"name": "Кийок", "slot": "weapon", "dmg_bonus": 6.0, "recipe": {"wood": 20}},
	"spear": {"name": "Спис", "slot": "weapon", "dmg_bonus": 12.0, "recipe": {"wood": 15, "scrap": 8}},
}
const ITEM_ORDER := ["axe", "pick", "club", "spear"]

# ============================================================================================
# Batch 7 — the catalogue merged into the runtime tables (one DefDatabase, built once per load)
# ============================================================================================

static var DB = Catalog.build_db()   # the full content catalogue (shared read-only db)

# Every stockable id -> {label, icon, color}. Legacy colors kept; catalogue ids get a deterministic
# hue from the id hash (display-only; icon+label carry the meaning per the colorblind rule).
static var RES_ALL: Dictionary = _build_res_all()
static func _build_res_all() -> Dictionary:
	var out := {}
	for id in RES:
		out[id] = RES[id]
	for d in DB.all_of_type(&"resource"):
		var id := String(d.id)
		if out.has(id):
			continue
		var hue := float(hash(id) % 360) / 360.0
		out[id] = {"label": String(d.field(&"label", id)), "icon": String(d.field(&"icon", "▪")),
			"color": Color.from_hsv(hue, 0.45, 0.85).to_html(false), "tier": int(d.field(&"tier", 0)),
			"cat": String(d.field(&"cat", ""))}
	return out

# Display order for the FULL stock list: legacy 6 first, then catalogue registration order.
static var RES_ALL_ORDER: Array = _build_res_order()
static func _build_res_order() -> Array:
	var order: Array = RES_ORDER.duplicate()
	for d in DB.all_of_type(&"resource"):
		var id := String(d.id)
		if not order.has(id):
			order.append(id)
	return order

# Gather nodes: legacy 4 + every catalogue node (kind -> {res, time, color, yield}).
static var NODEINFO: Dictionary = _build_nodeinfo()
static func _build_nodeinfo() -> Dictionary:
	var out := {}
	for k in NODEINFO_CORE:
		out[k] = NODEINFO_CORE[k]
	for d in DB.all_of_type(&"node"):
		var id := String(d.id)
		if out.has(id):
			continue
		out[id] = {"res": String(d.field(&"res", "wood")), "time": float(d.field(&"time", 1.2)),
			"color": String(d.field(&"color", "888888")), "label": String(d.field(&"label", id)),
			"icon": String(d.field(&"icon", "▪"))}
	return out

# Buildings: legacy 7 (save-compat, balance-pinned) + the whole catalogue in legacy shape
# {name, cost, hp, blocks, capacity?, cat, icon, station?, requires_research?, extra?}. Catalogue ids
# that duplicate a legacy building (or its near-twin) are skipped so the palette stays clean.
const _CAT_SKIP := ["storage", "workbench", "bed", "turret", "wall_stone", "door_wood", "floor_wood"]
static var BUILDINGS: Dictionary = _build_buildings()
static func _build_buildings() -> Dictionary:
	var out := {}
	for k in BUILDINGS_CORE:
		out[k] = BUILDINGS_CORE[k]
	for d in DB.all_of_type(&"building"):
		var id := String(d.id)
		if out.has(id) or _CAT_SKIP.has(id):
			continue
		var def := {
			"name": String(d.field(&"label", id)),
			"icon": String(d.field(&"icon", "■")),
			"cost": d.field(&"cost", {}),
			"hp": float(d.field(&"hp", 60.0)),
			"blocks": bool(d.field(&"blocks", false)),
			"cat": String(d.field(&"cat", "structure")),
		}
		if int(d.field(&"capacity", 0)) > 0:
			def["capacity"] = int(d.field(&"capacity", 0))
		var st := String(d.field(&"station", ""))
		if st != "":
			def["station"] = st
		var req := String(d.field(&"requires_research", ""))
		if req != "":
			def["requires_research"] = req
		var extra: Dictionary = d.field(&"extra", {})
		if not extra.is_empty():
			def["extra"] = extra
		out[id] = def
	return out

# Ordered build categories for the palette (id, label, icon); keys resolved at palette build time.
const BUILD_CATS := [
	{"id": "structure", "label": "Структури", "icon": "🧱"},
	{"id": "storage", "label": "Склад", "icon": "📦"},
	{"id": "production", "label": "Виробництво", "icon": "🛠"},
	{"id": "power", "label": "Енергія", "icon": "⚡"},
	{"id": "comfort", "label": "Комфорт", "icon": "🛏"},
	{"id": "defense", "label": "Оборона", "icon": "🛡"},
	{"id": "farm", "label": "Ферма", "icon": "🌱"},
]

static func buildings_in_cat(cat: String) -> Array:
	var out := []
	for k in BUILDINGS:
		if String(BUILDINGS[k].get("cat", "")) == cat:
			out.append(k)
	return out

# Equipment: legacy 4 (instant workbench recipes) + catalogue gear derived from recipe outputs
# (crafted via station bills, then taken from stock). slot: gather_mult -> tool, dmg_bonus -> weapon.
static var ITEMS: Dictionary = _build_items()
static func _build_items() -> Dictionary:
	var out := {}
	for k in ITEMS_CORE:
		out[k] = ITEMS_CORE[k]
	for r in DB.all_of_type(&"recipe"):
		var o: Dictionary = r.output()
		if not bool(o.get("thing", false)):
			continue
		var id := String(o.get("id", ""))
		if out.has(id):
			continue
		var gm := float(o.get("gather_mult", 0.0))
		var db_ := float(o.get("dmg_bonus", 0.0))
		if gm <= 0.0 and db_ <= 0.0:
			continue   # apparel/prosthetics: not tool/weapon slots (worn systems come later)
		var rdef = DB.get_def(StringName(id))
		out[id] = {
			"name": String(rdef.field(&"label", id)) if rdef != null else id,
			"slot": ("tool" if gm > 0.0 else "weapon"),
			"gather_mult": gm, "dmg_bonus": db_,
			"from_stock": true,   # no direct recipe: crafted on a station bill, equipped from stock
		}
	return out

# Edible stock ids ordered BEST-first (auto-eat picks the top available one). restore = hunger points;
# scaled from catalogue nutrition so the legacy "food = 38" anchor is preserved (0.5 -> 38).
static var FOODS: Array = _build_foods()
static func _build_foods() -> Array:
	var out := []
	for d in DB.all_of_type(&"resource"):
		if String(d.field(&"cat", "")) != "food":
			continue
		var id := String(d.id)
		if id == "raw_meat":
			continue   # raw meat is for cooking, not auto-eating (poison risk lives in the kernel)
		out.append({"id": id, "restore": clampf(float(d.field(&"nutrition", 0.5)) * 76.0, 10.0, 80.0)})
	out.sort_custom(func(a, b): return a.restore > b.restore)
	return out

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

static func res_icon(id: String) -> String:
	return String(RES_ALL.get(id, {}).get("icon", "▪"))

static func res_label(id: String) -> String:
	return String(RES_ALL.get(id, {}).get("label", id))

static func cost_str(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%s%d" % [res_icon(String(k)), cost[k]])
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

# RealWorld — kernel/catalog.gd : the full content tree (Batch 6).
#
# RimWorld analogue: the XML Defs folder — every ThingDef/RecipeDef/ResearchProjectDef the game ships.
# Batches 1–4 built the GRAMMAR (Def/Comp/Stat/System); this module is the VOCABULARY: the complete,
# validated content catalogue — resources in tiers, gather nodes, crops, buildings by category, recipes
# chained across stations, and a research tree in four eras. It is pure data + a deep validator; no new
# behaviour classes live here. Everything registers through Defs.DefDatabase (the load_pack seam), so a
# future content pipeline replaces the tables without touching the kernel.
#
# --- Def types this catalogue registers -------------------------------------------------------------
#   &"resource"  {label, icon, tier, cat, source, value, nutrition?}   every stockable id, incl. gear
#   &"node"      {label, icon, res, time, yield, color}                map gather nodes
#   &"crop"      {label, icon, grow_days, temp_min, temp_max, min_light, yield_res, yield_amt,
#                 requires_research}                                    farm plants (CompGrower props)
#   &"building"  {label, icon, cat, cost, hp, work, blocks, station?, power?, capacity?, extra?,
#                 requires_research?}                                   placeable Things
#   &"recipe"    Production.RecipeDef (+station/byproducts)             craft chains
#   &"research"  Production.ResearchDef (+label/icon/tier)              the tech tree
#
# --- Resource sources (grounds the craft-tree closure) ----------------------------------------------
#   &"gather" — from a map node        &"hunt" — from downing an animal (carcass)
#   &"fish"   — from water fishing     &"farm" — from a mature crop     &"water" — from river/well
#   &"craft"  — only via a recipe (must be reachable, validator proves it)
#
# --- The validator (validate_catalog) ---------------------------------------------------------------
# Beyond per-def validate(), the catalogue-level pass proves the tree is PLAYABLE, not just well-formed:
#   1. referential integrity — every input/output/cost/prereq/station names a registered def;
#   2. research tree — prereqs exist, graph is acyclic, and no dead tech (every project unlocks
#      something or gates a deeper project);
#   3. station coverage — every station a recipe names is provided by a building, and every production
#      station is used by at least one recipe;
#   4. solvability closure — starting from base sources only, iterating recipes AND buildable stations
#      together (a station's building cost must itself be obtainable), every resource, recipe and
#      building is reachable. This catches bootstrap deadlocks (a bench whose parts are made only on
#      that bench), which pure reference checks cannot see.
#
# Determinism: pure data + pure functions; no rng, no time.
extends RefCounted

const Defs = preload("res://scripts/kernel/defs.gd")
const Things = preload("res://scripts/kernel/things.gd")
const Production = preload("res://scripts/kernel/production.gd")
const Gear = preload("res://scripts/kernel/gear.gd")
const Power = preload("res://scripts/kernel/power.gd")

# ====================================================================================================
# 1. RESOURCES — every stockable id, tiered. Order here IS the canonical HUD display order.
#    tier: 0 сировина · 1 матеріали · 2 високотехнологічні · 3 їжа/медицина · 4 спорядження
#    cat:  &"raw" &"material" &"food" &"med" &"mil" &"tool" &"apparel"
# ====================================================================================================

static func _resources() -> Array:
	return [
		# --- tier 0 · сировина (base sources) ---------------------------------------------------
		{"id": "wood",       "label": "Дерево",        "icon": "🪵", "tier": 0, "cat": "raw", "source": "gather", "value": 1},
		{"id": "stone",      "label": "Камінь",        "icon": "🪨", "tier": 0, "cat": "raw", "source": "gather", "value": 1},
		{"id": "food",       "label": "Їжа",           "icon": "🍖", "tier": 0, "cat": "food", "source": "gather", "value": 2, "nutrition": 0.5},
		{"id": "scrap",      "label": "Брухт",         "icon": "⚙", "tier": 0, "cat": "raw", "source": "gather", "value": 2},
		{"id": "fiber",      "label": "Волокно",       "icon": "🌿", "tier": 0, "cat": "raw", "source": "gather", "value": 1},
		{"id": "clay",       "label": "Глина",         "icon": "🏺", "tier": 0, "cat": "raw", "source": "gather", "value": 1},
		{"id": "sand",       "label": "Пісок",         "icon": "⏳", "tier": 0, "cat": "raw", "source": "gather", "value": 1},
		{"id": "iron_ore",   "label": "Залізна руда",  "icon": "🤎", "tier": 0, "cat": "raw", "source": "gather", "value": 3},
		{"id": "copper_ore", "label": "Мідна руда",    "icon": "🧡", "tier": 0, "cat": "raw", "source": "gather", "value": 3},
		{"id": "coal",       "label": "Вугілля",       "icon": "⚫", "tier": 0, "cat": "raw", "source": "gather", "value": 2},
		{"id": "herbs",      "label": "Трави",         "icon": "🌱", "tier": 0, "cat": "raw", "source": "gather", "value": 2},
		{"id": "water",      "label": "Вода",          "icon": "💧", "tier": 0, "cat": "raw", "source": "water", "value": 1},
		{"id": "carcass",    "label": "Туша",          "icon": "🦌", "tier": 0, "cat": "raw", "source": "hunt", "value": 6},
		{"id": "fish",       "label": "Риба",          "icon": "🐟", "tier": 0, "cat": "food", "source": "fish", "value": 3, "nutrition": 0.4},
		{"id": "grain",      "label": "Зерно",         "icon": "🌾", "tier": 0, "cat": "raw", "source": "farm", "value": 2},
		{"id": "vegetables", "label": "Овочі",         "icon": "🥕", "tier": 0, "cat": "food", "source": "farm", "value": 2, "nutrition": 0.4},
		# --- tier 1 · матеріали (крафт) ---------------------------------------------------------
		{"id": "planks",     "label": "Дошки",           "icon": "🟫", "tier": 1, "cat": "material", "source": "craft", "value": 2},
		{"id": "brick",      "label": "Цегла",           "icon": "🧱", "tier": 1, "cat": "material", "source": "craft", "value": 2},
		{"id": "charcoal",   "label": "Деревне вугілля", "icon": "🌑", "tier": 1, "cat": "material", "source": "craft", "value": 2},
		{"id": "iron",       "label": "Залізо",          "icon": "🔗", "tier": 1, "cat": "material", "source": "craft", "value": 5},
		{"id": "copper",     "label": "Мідь",            "icon": "🟠", "tier": 1, "cat": "material", "source": "craft", "value": 5},
		{"id": "steel",      "label": "Сталь",           "icon": "🏗", "tier": 1, "cat": "material", "source": "craft", "value": 8},
		{"id": "glass",      "label": "Скло",            "icon": "🪟", "tier": 1, "cat": "material", "source": "craft", "value": 4},
		{"id": "cloth",      "label": "Тканина",         "icon": "🧵", "tier": 1, "cat": "material", "source": "craft", "value": 4},
		{"id": "leather",    "label": "Шкіра",           "icon": "🟤", "tier": 1, "cat": "material", "source": "craft", "value": 5},
		{"id": "rope",       "label": "Мотузка",         "icon": "🪢", "tier": 1, "cat": "material", "source": "craft", "value": 2},
		{"id": "raw_meat",   "label": "Сире м'ясо",      "icon": "🥩", "tier": 1, "cat": "food", "source": "craft", "value": 3, "nutrition": 0.5},
		{"id": "hide",       "label": "Шкура",           "icon": "🐃", "tier": 1, "cat": "raw", "source": "craft", "value": 3},
		{"id": "flour",      "label": "Борошно",         "icon": "🥣", "tier": 1, "cat": "material", "source": "craft", "value": 3},
		{"id": "components", "label": "Компоненти",      "icon": "🔩", "tier": 1, "cat": "material", "source": "craft", "value": 12},
		# --- tier 2 · високотехнологічні ---------------------------------------------------------
		{"id": "chem_fuel",  "label": "Хімпаливо",   "icon": "🛢", "tier": 2, "cat": "material", "source": "craft", "value": 5},
		{"id": "gunpowder",  "label": "Порох",       "icon": "💥", "tier": 2, "cat": "mil", "source": "craft", "value": 6},
		{"id": "wire",       "label": "Дріт",        "icon": "➰", "tier": 2, "cat": "material", "source": "craft", "value": 4},
		{"id": "electronics","label": "Електроніка", "icon": "📟", "tier": 2, "cat": "material", "source": "craft", "value": 18},
		{"id": "ammo",       "label": "Набої",       "icon": "🎯", "tier": 2, "cat": "mil", "source": "craft", "value": 1},
		{"id": "shell",      "label": "Снаряд",      "icon": "💣", "tier": 2, "cat": "mil", "source": "craft", "value": 10},
		# --- tier 3 · їжа та медицина (готове) ---------------------------------------------------
		{"id": "meal_simple",     "label": "Проста страва",   "icon": "🍲", "tier": 3, "cat": "food", "source": "craft", "value": 5, "nutrition": 0.8},
		{"id": "meal_fine",       "label": "Вишукана страва", "icon": "🍛", "tier": 3, "cat": "food", "source": "craft", "value": 9, "nutrition": 1.0},
		{"id": "meal_packaged",   "label": "Консерви",        "icon": "🥫", "tier": 3, "cat": "food", "source": "craft", "value": 10, "nutrition": 0.9},
		{"id": "bread",           "label": "Хліб",            "icon": "🍞", "tier": 3, "cat": "food", "source": "craft", "value": 5, "nutrition": 0.7},
		{"id": "herbal_medicine", "label": "Трав'яні ліки",   "icon": "🌿", "tier": 3, "cat": "med", "source": "craft", "value": 8},
		{"id": "medicine",        "label": "Медикаменти",     "icon": "💊", "tier": 3, "cat": "med", "source": "craft", "value": 18},
		# --- tier 4 · спорядження (things, tallied in stock) ------------------------------------
		{"id": "axe",            "label": "Сокира",          "icon": "🪓", "tier": 4, "cat": "tool", "source": "craft", "value": 10},
		{"id": "pick",           "label": "Кайло",           "icon": "⛏", "tier": 4, "cat": "tool", "source": "craft", "value": 10},
		{"id": "steel_axe",      "label": "Сталева сокира",  "icon": "🪓", "tier": 4, "cat": "tool", "source": "craft", "value": 25},
		{"id": "steel_pick",     "label": "Сталеве кайло",   "icon": "⛏", "tier": 4, "cat": "tool", "source": "craft", "value": 25},
		{"id": "club",           "label": "Кийок",           "icon": "🏏", "tier": 4, "cat": "mil", "source": "craft", "value": 6},
		{"id": "spear",          "label": "Спис",            "icon": "🔱", "tier": 4, "cat": "mil", "source": "craft", "value": 12},
		{"id": "knife",          "label": "Ніж",             "icon": "🔪", "tier": 4, "cat": "mil", "source": "craft", "value": 15},
		{"id": "machete",        "label": "Мачете",          "icon": "🗡", "tier": 4, "cat": "mil", "source": "craft", "value": 22},
		{"id": "bow",            "label": "Лук",             "icon": "🏹", "tier": 4, "cat": "mil", "source": "craft", "value": 15},
		{"id": "pistol",         "label": "Пістолет",        "icon": "🔫", "tier": 4, "cat": "mil", "source": "craft", "value": 40},
		{"id": "rifle",          "label": "Гвинтівка",       "icon": "🔫", "tier": 4, "cat": "mil", "source": "craft", "value": 70},
		{"id": "tunic",          "label": "Туніка",          "icon": "👕", "tier": 4, "cat": "apparel", "source": "craft", "value": 10},
		{"id": "pants",          "label": "Штани",           "icon": "👖", "tier": 4, "cat": "apparel", "source": "craft", "value": 9},
		{"id": "coat",           "label": "Плащ",            "icon": "🧥", "tier": 4, "cat": "apparel", "source": "craft", "value": 25},
		{"id": "parka",          "label": "Парка",           "icon": "🧥", "tier": 4, "cat": "apparel", "source": "craft", "value": 35},
		{"id": "duster",         "label": "Пильовик",        "icon": "🧥", "tier": 4, "cat": "apparel", "source": "craft", "value": 35},
		{"id": "helmet",         "label": "Шолом",           "icon": "⛑", "tier": 4, "cat": "apparel", "source": "craft", "value": 30},
		{"id": "armor_vest",     "label": "Бронежилет",      "icon": "🦺", "tier": 4, "cat": "apparel", "source": "craft", "value": 55},
		{"id": "prosthetic_leg", "label": "Протез ноги",     "icon": "🦿", "tier": 4, "cat": "med", "source": "craft", "value": 60},
		{"id": "prosthetic_arm", "label": "Протез руки",     "icon": "🦾", "tier": 4, "cat": "med", "source": "craft", "value": 60},
		{"id": "bionic_eye",     "label": "Біонічне око",    "icon": "👁", "tier": 4, "cat": "med", "source": "craft", "value": 120},
	]

# ====================================================================================================
# 2. GATHER NODES — map nodes the hero mines/chops/forages. `time` = base days per yield unit
#    (folded through the gather-time StatWorker), `yield` = units per node tap.
# ====================================================================================================

static func _nodes() -> Array:
	return [
		{"id": "tree",        "label": "Дерево",       "icon": "🌳", "res": "wood",       "time": 1.3, "yield": 6, "color": "3c7a3a"},
		{"id": "rock",        "label": "Скеля",        "icon": "🪨", "res": "stone",      "time": 1.8, "yield": 6, "color": "8b9099"},
		{"id": "bush",        "label": "Ягідник",      "icon": "🫐", "res": "food",       "time": 1.0, "yield": 4, "color": "6fae54"},
		{"id": "scrap_pile",  "label": "Купа брухту",  "icon": "⚙", "res": "scrap",      "time": 1.5, "yield": 5, "color": "86d0d6"},
		{"id": "fiber_plant", "label": "Волокнина",    "icon": "🌿", "res": "fiber",      "time": 1.1, "yield": 4, "color": "7dc06a"},
		{"id": "clay_pit",    "label": "Глинище",      "icon": "🏺", "res": "clay",       "time": 1.4, "yield": 5, "color": "a9703f"},
		{"id": "sand_pit",    "label": "Піщаник",      "icon": "⏳", "res": "sand",       "time": 1.2, "yield": 5, "color": "d8c47a"},
		{"id": "iron_vein",   "label": "Залізна жила", "icon": "🤎", "res": "iron_ore",   "time": 2.2, "yield": 4, "color": "8a6a55"},
		{"id": "copper_vein", "label": "Мідна жила",   "icon": "🧡", "res": "copper_ore", "time": 2.0, "yield": 4, "color": "c98a4b"},
		{"id": "coal_seam",   "label": "Вугільний пласт", "icon": "⚫", "res": "coal",    "time": 2.0, "yield": 5, "color": "3a3f45"},
		{"id": "herb_patch",  "label": "Травник",      "icon": "🌱", "res": "herbs",      "time": 1.2, "yield": 3, "color": "5da06a"},
	]

# ====================================================================================================
# 3. CROPS — farm plants; fields mirror Things.CompGrower props, plus what a harvest yields.
# ====================================================================================================

static func _crops() -> Array:
	return [
		{"id": "grain_crop",     "label": "Пшениця",      "icon": "🌾", "grow_days": 8.0, "temp_min": 5.0,  "temp_max": 32.0, "min_light": 0.4, "yield_res": "grain",      "yield_amt": 8, "requires_research": "agriculture"},
		{"id": "vegetable_crop", "label": "Овочі",        "icon": "🥕", "grow_days": 6.0, "temp_min": 6.0,  "temp_max": 34.0, "min_light": 0.4, "yield_res": "vegetables", "yield_amt": 6, "requires_research": "agriculture"},
		{"id": "berry_crop",     "label": "Ягідник",      "icon": "🫐", "grow_days": 5.0, "temp_min": 2.0,  "temp_max": 30.0, "min_light": 0.35, "yield_res": "food",      "yield_amt": 5, "requires_research": "agriculture"},
		{"id": "cotton_crop",    "label": "Бавовна",      "icon": "☁", "grow_days": 7.0, "temp_min": 10.0, "temp_max": 36.0, "min_light": 0.5, "yield_res": "fiber",      "yield_amt": 6, "requires_research": "agriculture"},
		{"id": "herb_crop",      "label": "Цілющі трави", "icon": "🌱", "grow_days": 7.0, "temp_min": 4.0,  "temp_max": 30.0, "min_light": 0.45, "yield_res": "herbs",     "yield_amt": 4, "requires_research": "herbal_lore"},
	]

# ====================================================================================================
# 4. BUILDINGS — by category. `station` names the workbench kind the building provides (recipes gate
#    on it); `power` mirrors power.gd comp props; `extra` is per-kind data the host binds to comps.
#    cat: &"structure" &"storage" &"production" &"power" &"comfort" &"defense" &"farm"
# ====================================================================================================

static func _buildings() -> Array:
	return [
		# --- структури ---------------------------------------------------------------------------
		{"id": "wall_wood",   "label": "Дерев'яна стіна", "icon": "🪵", "cat": "structure", "cost": {"wood": 6},  "hp": 90.0,  "work": 0.06, "blocks": true},
		{"id": "wall_stone",  "label": "Кам'яна стіна",   "icon": "🧱", "cat": "structure", "cost": {"stone": 5}, "hp": 160.0, "work": 0.08, "blocks": true},
		{"id": "wall_brick",  "label": "Цегляна стіна",   "icon": "🧱", "cat": "structure", "cost": {"brick": 4}, "hp": 220.0, "work": 0.09, "blocks": true, "requires_research": "masonry"},
		{"id": "wall_steel",  "label": "Сталева стіна",   "icon": "🏗", "cat": "structure", "cost": {"steel": 3}, "hp": 320.0, "work": 0.12, "blocks": true, "requires_research": "fortification"},
		{"id": "door_wood",   "label": "Дерев'яні двері", "icon": "🚪", "cat": "structure", "cost": {"wood": 4},  "hp": 80.0,  "work": 0.05, "blocks": false},
		{"id": "door_steel",  "label": "Сталеві двері",   "icon": "🚪", "cat": "structure", "cost": {"steel": 3}, "hp": 200.0, "work": 0.10, "blocks": false, "requires_research": "smithing"},
		{"id": "floor_wood",  "label": "Дерев'яна підлога", "icon": "🟫", "cat": "structure", "cost": {"wood": 1},  "hp": 30.0, "work": 0.02, "blocks": false},
		{"id": "floor_stone", "label": "Кам'яна бруківка",  "icon": "◻", "cat": "structure", "cost": {"stone": 1}, "hp": 40.0, "work": 0.03, "blocks": false, "requires_research": "masonry"},
		# --- склад -------------------------------------------------------------------------------
		{"id": "storage",   "label": "Склад",           "icon": "📦", "cat": "storage", "cost": {"wood": 10}, "hp": 90.0, "work": 0.10, "blocks": false, "capacity": 250},
		{"id": "warehouse", "label": "Велике сховище",  "icon": "🏬", "cat": "storage", "cost": {"planks": 20, "stone": 10}, "hp": 180.0, "work": 0.25, "blocks": false, "capacity": 800, "requires_research": "carpentry"},
		{"id": "cooler",    "label": "Холодильник",     "icon": "🧊", "cat": "storage", "cost": {"steel": 4, "components": 2}, "hp": 90.0, "work": 0.15, "blocks": false, "capacity": 120, "power": {"draw": 200, "priority": 2}, "requires_research": "refrigeration"},
		# --- виробництво (station = власний тег) ---------------------------------------------------
		{"id": "campfire",        "label": "Багаття",              "icon": "🔥", "cat": "production", "cost": {"wood": 5},  "hp": 40.0,  "work": 0.03, "blocks": false, "station": "campfire", "extra": {"light": true, "heat": 4.0}},
		{"id": "workbench",       "label": "Верстак",              "icon": "🛠", "cat": "production", "cost": {"wood": 18, "stone": 4}, "hp": 100.0, "work": 0.12, "blocks": true, "station": "workbench"},
		{"id": "kiln",            "label": "Випалювальна піч",     "icon": "🧱", "cat": "production", "cost": {"clay": 15, "stone": 5}, "hp": 120.0, "work": 0.15, "blocks": true, "station": "kiln", "requires_research": "pottery"},
		{"id": "smelter",         "label": "Плавильня",            "icon": "🔥", "cat": "production", "cost": {"brick": 12, "stone": 8}, "hp": 150.0, "work": 0.20, "blocks": true, "station": "smelter", "requires_research": "metallurgy"},
		{"id": "forge",           "label": "Кузня",                "icon": "⚒", "cat": "production", "cost": {"brick": 8, "iron": 5}, "hp": 140.0, "work": 0.20, "blocks": true, "station": "forge", "requires_research": "smithing"},
		{"id": "loom",            "label": "Ткацький верстат",     "icon": "🧵", "cat": "production", "cost": {"wood": 14}, "hp": 80.0, "work": 0.12, "blocks": true, "station": "loom", "requires_research": "weaving"},
		{"id": "tailor_bench",    "label": "Кравецький стіл",      "icon": "🧷", "cat": "production", "cost": {"planks": 10, "cloth": 4}, "hp": 80.0, "work": 0.12, "blocks": true, "station": "tailor", "requires_research": "weaving"},
		{"id": "tannery",         "label": "Чинбарня",             "icon": "🐃", "cat": "production", "cost": {"wood": 12, "stone": 6}, "hp": 100.0, "work": 0.15, "blocks": true, "station": "tannery", "requires_research": "tanning"},
		{"id": "butcher_table",   "label": "Стіл різника",         "icon": "🔪", "cat": "production", "cost": {"wood": 10, "stone": 2}, "hp": 80.0, "work": 0.10, "blocks": true, "station": "butcher", "requires_research": "butchery"},
		{"id": "stove",           "label": "Кухонна плита",        "icon": "🍳", "cat": "production", "cost": {"brick": 6, "scrap": 4}, "hp": 110.0, "work": 0.15, "blocks": true, "station": "stove", "requires_research": "cooking"},
		{"id": "mill",            "label": "Млин",                 "icon": "🌾", "cat": "production", "cost": {"planks": 16, "stone": 10, "cloth": 4}, "hp": 130.0, "work": 0.30, "blocks": true, "station": "mill", "requires_research": "milling"},
		{"id": "apothecary",      "label": "Аптекарський стіл",    "icon": "🌿", "cat": "production", "cost": {"wood": 12, "stone": 4}, "hp": 90.0, "work": 0.12, "blocks": true, "station": "apothecary", "requires_research": "herbal_lore"},
		{"id": "refinery",        "label": "Біопереробник",        "icon": "🛢", "cat": "production", "cost": {"iron": 8, "brick": 6}, "hp": 130.0, "work": 0.25, "blocks": true, "station": "refinery", "requires_research": "biofuel"},
		{"id": "chem_bench",      "label": "Хімічний стіл",        "icon": "⚗", "cat": "production", "cost": {"iron": 6, "glass": 4}, "hp": 100.0, "work": 0.20, "blocks": true, "station": "chem", "requires_research": "chemistry"},
		{"id": "machining_table", "label": "Токарний верстат",     "icon": "🔩", "cat": "production", "cost": {"steel": 10, "components": 4}, "hp": 150.0, "work": 0.30, "blocks": true, "station": "machining", "requires_research": "machining"},
		{"id": "electronics_bench","label": "Електромонтажний стіл","icon": "📟", "cat": "production", "cost": {"steel": 6, "glass": 4, "components": 4}, "hp": 110.0, "work": 0.25, "blocks": true, "station": "electronics", "power": {"draw": 60, "priority": 3}, "requires_research": "electronics_tech"},
		{"id": "lab",             "label": "Лабораторія",          "icon": "⚗", "cat": "production", "cost": {"steel": 8, "glass": 8, "components": 6}, "hp": 140.0, "work": 0.30, "blocks": true, "station": "lab", "requires_research": "pharmacology"},
		{"id": "research_bench",  "label": "Дослідницький стіл",   "icon": "📖", "cat": "production", "cost": {"wood": 16, "stone": 6}, "hp": 110.0, "work": 0.15, "blocks": true, "extra": {"research": true}},
		# --- енергія ------------------------------------------------------------------------------
		{"id": "generator_fuel", "label": "Генератор",       "icon": "⚙", "cat": "power", "cost": {"steel": 10, "components": 4}, "hp": 150.0, "work": 0.30, "blocks": true, "power": {"kind": "fuel", "rated": 900, "fuel_max": 30.0, "burn_per_day": 3.0}, "requires_research": "electricity"},
		{"id": "solar_panel",    "label": "Сонячна панель",  "icon": "☀", "cat": "power", "cost": {"steel": 6, "glass": 6, "components": 4}, "hp": 90.0, "work": 0.25, "blocks": false, "power": {"kind": "solar", "rated": 600}, "requires_research": "solar_wind"},
		{"id": "wind_turbine",   "label": "Вітряк",          "icon": "🌬", "cat": "power", "cost": {"steel": 8, "components": 6}, "hp": 120.0, "work": 0.30, "blocks": true, "power": {"kind": "wind", "rated": 500}, "requires_research": "solar_wind"},
		{"id": "battery",        "label": "Акумулятор",      "icon": "🔋", "cat": "power", "cost": {"steel": 4, "components": 4, "wire": 4}, "hp": 80.0, "work": 0.20, "blocks": false, "power": {"capacity": 600.0}, "requires_research": "electricity"},
		# --- комфорт / медицина / вода -------------------------------------------------------------
		{"id": "bed",    "label": "Ліжко",          "icon": "🛏", "cat": "comfort", "cost": {"wood": 14}, "hp": 60.0, "work": 0.10, "blocks": false, "extra": {"bed": true}},
		{"id": "medbed", "label": "Медичне ліжко",  "icon": "🏥", "cat": "comfort", "cost": {"steel": 6, "cloth": 6, "components": 3}, "hp": 90.0, "work": 0.20, "blocks": false, "extra": {"bed": true, "med_quality": 3}, "requires_research": "hospital"},
		{"id": "heater", "label": "Обігрівач",      "icon": "🌡", "cat": "comfort", "cost": {"iron": 4, "components": 2}, "hp": 70.0, "work": 0.10, "blocks": false, "power": {"draw": 120, "priority": 4}, "extra": {"heat": 10.0}, "requires_research": "electricity"},
		{"id": "lamp",   "label": "Лампа",          "icon": "💡", "cat": "comfort", "cost": {"iron": 2, "wire": 2}, "hp": 40.0, "work": 0.05, "blocks": false, "power": {"draw": 30, "priority": 1}, "extra": {"light": true}, "requires_research": "electricity"},
		{"id": "torch",  "label": "Смолоскип",      "icon": "🕯", "cat": "comfort", "cost": {"wood": 2, "fiber": 2}, "hp": 20.0, "work": 0.02, "blocks": false, "extra": {"light": true}},
		{"id": "well",   "label": "Криниця",        "icon": "💧", "cat": "comfort", "cost": {"stone": 12, "rope": 2}, "hp": 120.0, "work": 0.20, "blocks": false, "extra": {"water_source": true}, "requires_research": "wells"},
		# --- оборона -------------------------------------------------------------------------------
		{"id": "turret",        "label": "Турель",          "icon": "🎯", "cat": "defense", "cost": {"steel": 12, "components": 6}, "hp": 90.0, "work": 0.30, "blocks": true, "power": {"draw": 150, "priority": 5}, "extra": {"range": 6.2, "dps": 14.0, "ammo_per_shot": 1}, "requires_research": "turrets_tech"},
		{"id": "mortar",        "label": "Мортира",         "icon": "💣", "cat": "defense", "cost": {"steel": 14, "components": 6}, "hp": 130.0, "work": 0.35, "blocks": true, "extra": {"min_range": 8.0, "scatter": 2.5}, "requires_research": "mortars_tech"},
		{"id": "sandbags",      "label": "Мішки з піском",  "icon": "🛡", "cat": "defense", "cost": {"sand": 8, "cloth": 2}, "hp": 100.0, "work": 0.08, "blocks": false, "extra": {"cover": 0.5}, "requires_research": "fortification"},
		{"id": "spike_trap",    "label": "Колюча пастка",   "icon": "📌", "cat": "defense", "cost": {"wood": 8}, "hp": 30.0, "work": 0.08, "blocks": false, "extra": {"trap_damage": 30.0, "uses": 3}, "requires_research": "fortification"},
		{"id": "deadfall_trap", "label": "Пастка-давилка",  "icon": "🪨", "cat": "defense", "cost": {"stone": 10}, "hp": 30.0, "work": 0.10, "blocks": false, "extra": {"trap_damage": 55.0, "uses": 1}, "requires_research": "fortification"},
		{"id": "mine",          "label": "Міна",            "icon": "💥", "cat": "defense", "cost": {"gunpowder": 2, "components": 2, "steel": 2}, "hp": 20.0, "work": 0.12, "blocks": false, "extra": {"trap_damage": 90.0, "uses": 1, "blast_radius": 2.0}, "requires_research": "sapper_charges"},
		# --- ферма ---------------------------------------------------------------------------------
		{"id": "farm_plot", "label": "Грядка", "icon": "🌱", "cat": "farm", "cost": {"wood": 4}, "hp": 30.0, "work": 0.05, "blocks": false, "requires_research": "agriculture"},
	]

# ====================================================================================================
# 5. RECIPES — the craft chains, keyed to stations. Fields feed Production.RecipeDef verbatim
#    (inputs/output/work/requires_research) plus `station` and optional `byproducts`.
#    Thing-outputs (gear, meals) declare comps below in _recipe_comps().
# ====================================================================================================

static func _recipes() -> Array:
	return [
		# --- верстак (без досліджень: стартова база) ----------------------------------------------
		{"id": "r_planks",     "station": "workbench", "inputs": {"wood": 3},               "output": {"id": "planks", "count": 2}, "work": 0.2},
		{"id": "r_rope",       "station": "workbench", "inputs": {"fiber": 3},              "output": {"id": "rope", "count": 1},   "work": 0.15},
		{"id": "r_components_salvage", "station": "workbench", "inputs": {"scrap": 8},      "output": {"id": "components", "count": 1}, "work": 0.8},
		{"id": "r_club",       "station": "workbench", "inputs": {"wood": 20},              "output": {"id": "club", "count": 1, "thing": true, "dmg_bonus": 6.0},  "work": 0.5},
		{"id": "r_spear",      "station": "workbench", "inputs": {"wood": 15, "scrap": 8},  "output": {"id": "spear", "count": 1, "thing": true, "dmg_bonus": 12.0}, "work": 0.6},
		{"id": "r_axe",        "station": "workbench", "inputs": {"wood": 15, "stone": 10}, "output": {"id": "axe", "count": 1, "thing": true, "gather_mult": 1.6},  "work": 0.5},
		{"id": "r_pick",       "station": "workbench", "inputs": {"wood": 12, "stone": 16}, "output": {"id": "pick", "count": 1, "thing": true, "gather_mult": 1.9}, "work": 0.5},
		{"id": "r_bow",        "station": "workbench", "inputs": {"wood": 12, "rope": 2},   "output": {"id": "bow", "count": 1, "thing": true, "dmg_bonus": 10.0, "ranged": true}, "work": 0.8, "requires_research": "carpentry"},
		# --- багаття -------------------------------------------------------------------------------
		{"id": "r_meal_campfire", "station": "campfire", "inputs": {"food": 2}, "output": {"id": "meal_simple", "count": 1, "thing": true}, "work": 0.15},
		# --- випалювальна піч ----------------------------------------------------------------------
		{"id": "r_brick",    "station": "kiln", "inputs": {"clay": 3},                 "output": {"id": "brick", "count": 2},    "work": 0.25, "requires_research": "pottery"},
		{"id": "r_charcoal", "station": "kiln", "inputs": {"wood": 4},                 "output": {"id": "charcoal", "count": 3}, "work": 0.2,  "requires_research": "pottery"},
		{"id": "r_glass",    "station": "kiln", "inputs": {"sand": 3, "charcoal": 1},  "output": {"id": "glass", "count": 2},    "work": 0.3,  "requires_research": "pottery"},
		# --- плавильня -----------------------------------------------------------------------------
		{"id": "r_iron",        "station": "smelter", "inputs": {"iron_ore": 2, "charcoal": 1},   "output": {"id": "iron", "count": 1},  "work": 0.4, "requires_research": "metallurgy"},
		{"id": "r_copper",      "station": "smelter", "inputs": {"copper_ore": 2, "charcoal": 1}, "output": {"id": "copper", "count": 1}, "work": 0.4, "requires_research": "metallurgy"},
		{"id": "r_steel",       "station": "smelter", "inputs": {"iron": 2, "coal": 1},           "output": {"id": "steel", "count": 1}, "work": 0.5, "requires_research": "metallurgy"},
		{"id": "r_steel_scrap", "station": "smelter", "inputs": {"scrap": 5, "coal": 1},          "output": {"id": "steel", "count": 1}, "work": 0.4, "requires_research": "metallurgy"},
		# --- кузня ---------------------------------------------------------------------------------
		{"id": "r_knife",      "station": "forge", "inputs": {"steel": 1, "wood": 1}, "output": {"id": "knife", "count": 1, "thing": true, "dmg_bonus": 9.0},    "work": 0.6, "requires_research": "smithing"},
		{"id": "r_machete",    "station": "forge", "inputs": {"steel": 2, "wood": 1}, "output": {"id": "machete", "count": 1, "thing": true, "dmg_bonus": 16.0}, "work": 0.8, "requires_research": "smithing"},
		{"id": "r_steel_axe",  "station": "forge", "inputs": {"steel": 2, "wood": 2}, "output": {"id": "steel_axe", "count": 1, "thing": true, "gather_mult": 2.2},  "work": 0.8, "requires_research": "smithing"},
		{"id": "r_steel_pick", "station": "forge", "inputs": {"steel": 2, "wood": 2}, "output": {"id": "steel_pick", "count": 1, "thing": true, "gather_mult": 2.6}, "work": 0.8, "requires_research": "smithing"},
		{"id": "r_helmet",     "station": "forge", "inputs": {"steel": 3},            "output": {"id": "helmet", "count": 1, "thing": true}, "work": 1.0, "requires_research": "smithing"},
		# --- ткацтво / чинбарня / кравецтво --------------------------------------------------------
		{"id": "r_cloth",   "station": "loom",    "inputs": {"fiber": 4}, "output": {"id": "cloth", "count": 1},   "work": 0.3,  "requires_research": "weaving"},
		{"id": "r_leather", "station": "tannery", "inputs": {"hide": 1},  "output": {"id": "leather", "count": 1}, "work": 0.25, "requires_research": "tanning"},
		{"id": "r_tunic",  "station": "tailor", "inputs": {"cloth": 4},                "output": {"id": "tunic", "count": 1, "thing": true},  "work": 0.8, "requires_research": "weaving"},
		{"id": "r_pants",  "station": "tailor", "inputs": {"cloth": 3},                "output": {"id": "pants", "count": 1, "thing": true},  "work": 0.7, "requires_research": "weaving"},
		{"id": "r_coat",   "station": "tailor", "inputs": {"cloth": 6, "leather": 2},  "output": {"id": "coat", "count": 1, "thing": true},   "work": 1.2, "requires_research": "tailoring"},
		{"id": "r_parka",  "station": "tailor", "inputs": {"cloth": 4, "leather": 6},  "output": {"id": "parka", "count": 1, "thing": true},  "work": 1.4, "requires_research": "tailoring"},
		{"id": "r_duster", "station": "tailor", "inputs": {"leather": 8},              "output": {"id": "duster", "count": 1, "thing": true}, "work": 1.4, "requires_research": "tailoring"},
		{"id": "r_armor_vest", "station": "tailor", "inputs": {"cloth": 4, "steel": 6}, "output": {"id": "armor_vest", "count": 1, "thing": true}, "work": 2.0, "requires_research": "machining"},
		# --- стіл різника --------------------------------------------------------------------------
		{"id": "r_butcher", "station": "butcher", "inputs": {"carcass": 1}, "output": {"id": "raw_meat", "count": 4}, "byproducts": {"hide": 2}, "work": 0.15, "requires_research": "butchery"},
		# --- кухня ---------------------------------------------------------------------------------
		{"id": "r_meal_simple", "station": "stove", "inputs": {"raw_meat": 1},                    "output": {"id": "meal_simple", "count": 1, "thing": true}, "work": 0.15, "requires_research": "cooking"},
		{"id": "r_meal_fish",   "station": "stove", "inputs": {"fish": 2},                        "output": {"id": "meal_simple", "count": 1, "thing": true}, "work": 0.15, "requires_research": "cooking"},
		{"id": "r_meal_fine",   "station": "stove", "inputs": {"raw_meat": 1, "vegetables": 2},   "output": {"id": "meal_fine", "count": 1, "thing": true},   "work": 0.3,  "requires_research": "cooking"},
		{"id": "r_meal_packaged", "station": "stove", "inputs": {"raw_meat": 2, "vegetables": 2}, "output": {"id": "meal_packaged", "count": 2, "thing": true}, "work": 0.5, "requires_research": "preservation"},
		{"id": "r_bread",       "station": "stove", "inputs": {"flour": 2},                       "output": {"id": "bread", "count": 2, "thing": true},       "work": 0.25, "requires_research": "milling"},
		# --- млин ----------------------------------------------------------------------------------
		{"id": "r_flour", "station": "mill", "inputs": {"grain": 3}, "output": {"id": "flour", "count": 2}, "work": 0.2, "requires_research": "milling"},
		# --- аптека / лабораторія ------------------------------------------------------------------
		{"id": "r_herbal_medicine", "station": "apothecary", "inputs": {"herbs": 3, "cloth": 1}, "output": {"id": "herbal_medicine", "count": 2}, "work": 0.4, "requires_research": "herbal_lore"},
		{"id": "r_medicine",   "station": "lab", "inputs": {"herbal_medicine": 1, "chem_fuel": 1, "cloth": 1}, "output": {"id": "medicine", "count": 2}, "work": 0.6, "requires_research": "pharmacology"},
		{"id": "r_bionic_eye", "station": "lab", "inputs": {"electronics": 2, "steel": 1, "components": 2},    "output": {"id": "bionic_eye", "count": 1, "thing": true}, "work": 2.5, "requires_research": "bionics"},
		# --- біопереробник -------------------------------------------------------------------------
		{"id": "r_chem_fuel_wood", "station": "refinery", "inputs": {"wood": 5}, "output": {"id": "chem_fuel", "count": 2}, "work": 0.3, "requires_research": "biofuel"},
		{"id": "r_chem_fuel_food", "station": "refinery", "inputs": {"food": 4}, "output": {"id": "chem_fuel", "count": 2}, "work": 0.3, "requires_research": "biofuel"},
		# --- хімія ---------------------------------------------------------------------------------
		{"id": "r_gunpowder", "station": "chem", "inputs": {"charcoal": 2, "chem_fuel": 1}, "output": {"id": "gunpowder", "count": 2}, "work": 0.4, "requires_research": "chemistry"},
		# --- токарний верстат ----------------------------------------------------------------------
		{"id": "r_components", "station": "machining", "inputs": {"steel": 1, "copper": 1},    "output": {"id": "components", "count": 2}, "work": 0.5, "requires_research": "machining"},
		{"id": "r_ammo",       "station": "machining", "inputs": {"steel": 1, "gunpowder": 1}, "output": {"id": "ammo", "count": 20},      "work": 0.4, "requires_research": "gunsmithing"},
		{"id": "r_shell",      "station": "machining", "inputs": {"steel": 3, "gunpowder": 2}, "output": {"id": "shell", "count": 2},      "work": 0.6, "requires_research": "mortars_tech"},
		{"id": "r_pistol",     "station": "machining", "inputs": {"steel": 4, "components": 2}, "output": {"id": "pistol", "count": 1, "thing": true, "dmg_bonus": 18.0, "ranged": true}, "work": 1.5, "requires_research": "gunsmithing"},
		{"id": "r_rifle",      "station": "machining", "inputs": {"steel": 6, "components": 3}, "output": {"id": "rifle", "count": 1, "thing": true, "dmg_bonus": 26.0, "ranged": true}, "work": 2.0, "requires_research": "gunsmithing"},
		{"id": "r_prosthetic_leg", "station": "machining", "inputs": {"steel": 4, "components": 3}, "output": {"id": "prosthetic_leg", "count": 1, "thing": true}, "work": 2.0, "requires_research": "prosthetics_tech"},
		{"id": "r_prosthetic_arm", "station": "machining", "inputs": {"steel": 4, "components": 3}, "output": {"id": "prosthetic_arm", "count": 1, "thing": true}, "work": 2.0, "requires_research": "prosthetics_tech"},
		# --- електромонтажний стіл (єдина живлена станція) -----------------------------------------
		{"id": "r_wire",        "station": "electronics", "inputs": {"copper": 2},                             "output": {"id": "wire", "count": 3},        "work": 0.2, "requires_research": "electronics_tech"},
		{"id": "r_electronics", "station": "electronics", "inputs": {"wire": 2, "glass": 1, "components": 1},  "output": {"id": "electronics", "count": 1}, "work": 0.6, "requires_research": "electronics_tech"},
	]

# Comps a thing-output carries, keyed by output id. Referenced classes are runtime (not const-safe),
# hence a static func. Apparel mirrors Gear.CompApparel props; meals mirror Things.CompRottable.
static func _recipe_comps() -> Dictionary:
	return {
		"meal_simple":   [{"cls": Things.CompRottable, "props": {"rot_days": 4.0}}],
		"meal_fine":     [{"cls": Things.CompRottable, "props": {"rot_days": 4.0}}],
		"meal_packaged": [{"cls": Things.CompRottable, "props": {"rot_days": 60.0}}],
		"bread":         [{"cls": Things.CompRottable, "props": {"rot_days": 8.0}}],
		"tunic":      [{"cls": Gear.CompApparel, "props": {"slot": "torso", "insulation_c": 4.0,  "armor": {&"sharp": 0.06}}}],
		"pants":      [{"cls": Gear.CompApparel, "props": {"slot": "legs",  "insulation_c": 3.0,  "armor": {&"sharp": 0.04}}}],
		"coat":       [{"cls": Gear.CompApparel, "props": {"slot": "torso", "insulation_c": 10.0, "armor": {&"sharp": 0.12, &"blunt": 0.06}}}],
		"parka":      [{"cls": Gear.CompApparel, "props": {"slot": "torso", "insulation_c": 18.0, "armor": {&"sharp": 0.08}}}],
		"duster":     [{"cls": Gear.CompApparel, "props": {"slot": "torso", "insulation_c": 8.0,  "armor": {&"sharp": 0.18, &"heat": 0.25}}}],
		"helmet":     [{"cls": Gear.CompApparel, "props": {"slot": "head",  "insulation_c": 2.0,  "armor": {&"sharp": 0.30, &"blunt": 0.25}}}],
		"armor_vest": [{"cls": Gear.CompApparel, "props": {"slot": "torso", "insulation_c": 1.0,  "armor": {&"sharp": 0.40, &"blunt": 0.30}}}],
	}

# ====================================================================================================
# 6. RESEARCH — the tech tree in four eras. tier drives the HUD tree layout; prereqs drive the DAG.
# ====================================================================================================

static func _research() -> Array:
	return [
		# --- ера 1 · виживання ---------------------------------------------------------------------
		{"id": "carpentry",   "label": "Теслярство",       "icon": "🪚", "cost": 1.5, "tier": 1, "prereqs": []},
		{"id": "pottery",     "label": "Гончарство",       "icon": "🏺", "cost": 2.0, "tier": 1, "prereqs": []},
		{"id": "weaving",     "label": "Ткацтво",          "icon": "🧵", "cost": 2.0, "tier": 1, "prereqs": []},
		{"id": "butchery",    "label": "Розбирання туш",   "icon": "🔪", "cost": 1.5, "tier": 1, "prereqs": []},
		{"id": "herbal_lore", "label": "Травництво",       "icon": "🌿", "cost": 2.0, "tier": 1, "prereqs": []},
		{"id": "wells",       "label": "Криниці",          "icon": "💧", "cost": 1.5, "tier": 1, "prereqs": []},
		{"id": "agriculture", "label": "Рільництво",       "icon": "🌾", "cost": 3.0, "tier": 1, "prereqs": []},
		{"id": "cooking",     "label": "Кулінарія",        "icon": "🍳", "cost": 2.0, "tier": 1, "prereqs": ["pottery"]},
		# --- ера 2 · матеріали -----------------------------------------------------------------------
		{"id": "masonry",      "label": "Мурування",   "icon": "🧱", "cost": 3.0, "tier": 2, "prereqs": ["pottery"]},
		{"id": "tanning",      "label": "Чинбарство",  "icon": "🐃", "cost": 2.5, "tier": 2, "prereqs": ["butchery"]},
		{"id": "metallurgy",   "label": "Металургія",  "icon": "🔥", "cost": 4.0, "tier": 2, "prereqs": ["pottery"]},
		{"id": "milling",      "label": "Млинарство",  "icon": "🌾", "cost": 2.0, "tier": 2, "prereqs": ["agriculture"]},
		{"id": "preservation", "label": "Консервація", "icon": "🥫", "cost": 3.0, "tier": 2, "prereqs": ["cooking"]},
		# --- ера 3 · індустрія -----------------------------------------------------------------------
		{"id": "smithing",      "label": "Ковальство",    "icon": "⚒", "cost": 4.0, "tier": 3, "prereqs": ["metallurgy"]},
		{"id": "tailoring",     "label": "Кравецтво",     "icon": "🧷", "cost": 3.0, "tier": 3, "prereqs": ["weaving", "tanning"]},
		{"id": "pharmacology",  "label": "Фармакологія",  "icon": "💊", "cost": 4.0, "tier": 3, "prereqs": ["herbal_lore", "pottery"]},
		{"id": "biofuel",       "label": "Біопаливо",     "icon": "🛢", "cost": 3.0, "tier": 3, "prereqs": ["metallurgy"]},
		{"id": "machining",     "label": "Механообробка", "icon": "🔩", "cost": 5.0, "tier": 3, "prereqs": ["smithing"]},
		{"id": "fortification", "label": "Фортифікація",  "icon": "🛡", "cost": 3.0, "tier": 3, "prereqs": ["masonry"]},
		{"id": "chemistry",     "label": "Хімія",         "icon": "⚗", "cost": 4.0, "tier": 3, "prereqs": ["biofuel"]},
		# --- ера 4 · електрика -----------------------------------------------------------------------
		{"id": "electricity",      "label": "Електрика",             "icon": "⚡", "cost": 6.0, "tier": 4, "prereqs": ["machining"]},
		{"id": "solar_wind",       "label": "Відновлювана енергія",  "icon": "☀", "cost": 5.0, "tier": 4, "prereqs": ["electricity"]},
		{"id": "electronics_tech", "label": "Електроніка",           "icon": "📟", "cost": 6.0, "tier": 4, "prereqs": ["electricity"]},
		{"id": "refrigeration",    "label": "Холодильні установки",  "icon": "🧊", "cost": 4.0, "tier": 4, "prereqs": ["electricity"]},
		{"id": "gunsmithing",      "label": "Зброярство",            "icon": "🔫", "cost": 6.0, "tier": 4, "prereqs": ["machining", "chemistry"]},
		{"id": "turrets_tech",     "label": "Автотурелі",            "icon": "🎯", "cost": 6.0, "tier": 4, "prereqs": ["electronics_tech", "gunsmithing"]},
		{"id": "mortars_tech",     "label": "Мортири",               "icon": "💣", "cost": 5.0, "tier": 4, "prereqs": ["gunsmithing"]},
		{"id": "sapper_charges",   "label": "Мінна справа",          "icon": "💥", "cost": 4.0, "tier": 4, "prereqs": ["chemistry", "fortification"]},
		{"id": "hospital",         "label": "Госпіталь",             "icon": "🏥", "cost": 5.0, "tier": 4, "prereqs": ["pharmacology"]},
		{"id": "prosthetics_tech", "label": "Протезування",          "icon": "🦿", "cost": 6.0, "tier": 4, "prereqs": ["hospital", "machining"]},
		{"id": "bionics",          "label": "Біоніка",               "icon": "👁", "cost": 8.0, "tier": 4, "prereqs": ["prosthetics_tech", "electronics_tech"]},
	]

# ====================================================================================================
# 7. LOADING — register the whole catalogue into a DefDatabase (the load_pack-shaped seam).
# ====================================================================================================

static func load_into(db) -> void:
	for r in _resources():
		db.register(Defs.Def.new(&"resource", StringName(r.id), r))
	for n in _nodes():
		db.register(Defs.Def.new(&"node", StringName(n.id), n))
	for c in _crops():
		db.register(Defs.Def.new(&"crop", StringName(c.id), c))
	for b in _buildings():
		db.register(Defs.Def.new(&"building", StringName(b.id), b))
	var comps: Dictionary = _recipe_comps()
	for rc in _recipes():
		var data: Dictionary = rc.duplicate(true)
		var out: Dictionary = data.get("output", {})
		var out_id: String = str(out.get("id", ""))
		if comps.has(out_id):
			out["comps"] = comps[out_id]
			data["output"] = out
		db.register(Production.RecipeDef.new(StringName(rc.id), data))
	for res in _research():
		db.register(Production.ResearchDef.new(StringName(res.id), res))

# A fresh database with the full catalogue loaded (convenience for hosts and tests).
static func build_db():
	var db = Defs.DefDatabase.new()
	load_into(db)
	return db

# ====================================================================================================
# 8. THE DEEP VALIDATOR — proves the catalogue is playable, not just well-formed.
# ====================================================================================================

# Every error is one human-readable string; an empty Array == healthy catalogue.
static func validate_catalog(db) -> Array:
	var errs: Array = []
	errs.append_array(db.validate_all())
	errs.append_array(_check_labels(db))
	errs.append_array(_check_references(db))
	errs.append_array(_check_research_graph(db))
	errs.append_array(_check_station_coverage(db))
	errs.append_array(_check_solvability(db))
	return errs

# --- 8a. labels/icons: every def the HUD will render carries a non-empty label AND icon -------------
static func _check_labels(db) -> Array:
	var errs: Array = []
	for t in [&"resource", &"node", &"crop", &"building", &"research"]:
		for d in db.all_of_type(t):
			if str(d.field(&"label", "")) == "" or str(d.field(&"icon", "")) == "":
				errs.append("%s %s: порожній label/icon" % [t, d.id])
	return errs

# --- 8b. referential integrity ----------------------------------------------------------------------
static func _check_references(db) -> Array:
	var errs: Array = []
	# recipes: inputs/output/byproducts are resources; requires_research exists.
	for r in db.all_of_type(&"recipe"):
		for res in r.inputs():
			if not _is_resource(db, res):
				errs.append("recipe %s: невідомий інпут %s" % [r.id, res])
		var out_id: StringName = StringName(str(r.output().get("id", "")))
		if not _is_resource(db, out_id):
			errs.append("recipe %s: невідомий аутпут %s" % [r.id, out_id])
		for bp in r.data.get("byproducts", {}):
			if not _is_resource(db, bp):
				errs.append("recipe %s: невідомий побічний продукт %s" % [r.id, bp])
		var req: StringName = r.requires_research()
		if req != &"" and db.get_def(req) == null:
			errs.append("recipe %s: невідоме дослідження %s" % [r.id, req])
	# buildings: cost keys are resources; requires_research exists.
	for b in db.all_of_type(&"building"):
		for res in b.field(&"cost", {}):
			if not _is_resource(db, res):
				errs.append("building %s: невідомий ресурс у вартості: %s" % [b.id, res])
		var breq: StringName = StringName(str(b.field(&"requires_research", "")))
		if breq != &"" and db.get_def(breq) == null:
			errs.append("building %s: невідоме дослідження %s" % [b.id, breq])
	# nodes: res is a resource.
	for n in db.all_of_type(&"node"):
		if not _is_resource(db, StringName(str(n.field(&"res", "")))):
			errs.append("node %s: невідомий ресурс %s" % [n.id, n.field(&"res", "")])
	# crops: yield_res is a resource; requires_research exists.
	for c in db.all_of_type(&"crop"):
		if not _is_resource(db, StringName(str(c.field(&"yield_res", "")))):
			errs.append("crop %s: невідомий ресурс урожаю %s" % [c.id, c.field(&"yield_res", "")])
		var creq: StringName = StringName(str(c.field(&"requires_research", "")))
		if creq != &"" and db.get_def(creq) == null:
			errs.append("crop %s: невідоме дослідження %s" % [c.id, creq])
	return errs

static func _is_resource(db, id) -> bool:
	var d = db.get_def(StringName(str(id)))
	return d != null and d.def_type == &"resource"

# --- 8c. research: prereqs exist, DAG is acyclic, no dead tech --------------------------------------
static func _check_research_graph(db) -> Array:
	var errs: Array = []
	var all: Array = db.all_of_type(&"research")
	for r in all:
		for p in r.prereqs():
			var pd = db.get_def(StringName(str(p)))
			if pd == null or pd.def_type != &"research":
				errs.append("research %s: невідомий пререквізит %s" % [r.id, p])
	# cycle detection: iterative DFS, colors 0=white 1=gray 2=black.
	var color: Dictionary = {}
	for r in all:
		if int(color.get(r.id, 0)) != 0:
			continue
		var stack: Array = [[r.id, 0]]
		while not stack.is_empty():
			var top: Array = stack[stack.size() - 1]
			var id: StringName = top[0]
			if int(top[1]) == 0:
				color[id] = 1
				top[1] = 1
				var d = db.get_def(id)
				if d != null:
					for p in d.prereqs():
						var pid := StringName(str(p))
						var c: int = int(color.get(pid, 0))
						if c == 1:
							errs.append("research: цикл через %s -> %s" % [id, pid])
						elif c == 0 and db.get_def(pid) != null:
							stack.append([pid, 0])
			else:
				color[id] = 2
				stack.pop_back()
	# dead tech: every project must unlock a recipe/building/crop OR gate a deeper project.
	var used: Dictionary = {}
	for r in db.all_of_type(&"recipe"):
		used[r.requires_research()] = true
	for b in db.all_of_type(&"building"):
		used[StringName(str(b.field(&"requires_research", "")))] = true
	for c in db.all_of_type(&"crop"):
		used[StringName(str(c.field(&"requires_research", "")))] = true
	for r in all:
		for p in r.prereqs():
			used[StringName(str(p))] = true
	for r in all:
		if not used.has(r.id):
			errs.append("research %s: мертва гілка — нічого не відкриває і не є пререквізитом" % r.id)
	return errs

# --- 8d. station coverage both ways ------------------------------------------------------------------
static func _check_station_coverage(db) -> Array:
	var errs: Array = []
	var provided: Dictionary = {}   # station tag -> true (from buildings)
	for b in db.all_of_type(&"building"):
		var st: StringName = StringName(str(b.field(&"station", "")))
		if st != &"":
			provided[st] = true
	var used: Dictionary = {}       # station tag -> true (from recipes)
	for r in db.all_of_type(&"recipe"):
		var st2: StringName = r.station()
		if st2 != &"":
			used[st2] = true
			if not provided.has(st2):
				errs.append("recipe %s: станцію %s не надає жодна будівля" % [r.id, st2])
	for st3 in provided:
		if not used.has(st3):
			errs.append("station %s: жоден рецепт її не використовує (мертва станція)" % st3)
	return errs

# --- 8e. solvability closure — the playability proof -------------------------------------------------
# Fixpoint over TWO coupled sets: obtainable resources and available stations. A recipe fires only when
# its station is available AND its inputs are obtainable; a building (hence its station) becomes
# available only when its cost is obtainable. Research is assumed fully unlocked (its reachability is
# 8c's job). Catches bootstrap deadlocks a pure reference check cannot (bench built from parts made
# only on that bench).
static func _check_solvability(db) -> Array:
	var errs: Array = []
	var obtainable: Dictionary = {}
	for r in db.all_of_type(&"resource"):
		if StringName(str(r.field(&"source", "craft"))) != &"craft":
			obtainable[r.id] = true
	for n in db.all_of_type(&"node"):
		obtainable[StringName(str(n.field(&"res", "")))] = true
	for c in db.all_of_type(&"crop"):
		obtainable[StringName(str(c.field(&"yield_res", "")))] = true

	var stations: Dictionary = {&"": true}   # "" == no station required
	var recipes: Array = db.all_of_type(&"recipe")
	var buildings: Array = db.all_of_type(&"building")
	var changed := true
	while changed:
		changed = false
		for b in buildings:
			var st: StringName = StringName(str(b.field(&"station", "")))
			if st == &"" or stations.has(st):
				continue
			if _all_obtainable(b.field(&"cost", {}), obtainable):
				stations[st] = true
				changed = true
		for r in recipes:
			var out_id: StringName = StringName(str(r.output().get("id", "")))
			if not stations.has(r.station()):
				continue
			if not _all_obtainable(r.inputs(), obtainable):
				continue
			if not obtainable.has(out_id):
				obtainable[out_id] = true
				changed = true
			for bp in r.data.get("byproducts", {}):
				var bpid := StringName(str(bp))
				if not obtainable.has(bpid):
					obtainable[bpid] = true
					changed = true

	for r2 in db.all_of_type(&"resource"):
		if not obtainable.has(r2.id):
			errs.append("resource %s: недосяжний — ні джерела, ні робочого ланцюга рецептів" % r2.id)
	for r3 in recipes:
		if not stations.has(r3.station()):
			errs.append("recipe %s: станція %s ніколи не стає доступною (bootstrap-глухий кут)" % [r3.id, r3.station()])
		elif not _all_obtainable(r3.inputs(), obtainable):
			errs.append("recipe %s: інпути недосяжні" % r3.id)
	for b2 in buildings:
		if not _all_obtainable(b2.field(&"cost", {}), obtainable):
			errs.append("building %s: вартість недосяжна" % b2.id)
	return errs

static func _all_obtainable(needs: Dictionary, obtainable: Dictionary) -> bool:
	for res in needs:
		if not obtainable.has(StringName(str(res))):
			return false
	return true

# ====================================================================================================
# 9. HOST/HUD HELPERS — pure queries panels bind to (registration order == display order).
# ====================================================================================================

static func buildings_in_category(db, cat: StringName) -> Array:
	return db.all_of_type(&"building").filter(func(b): return StringName(str(b.field(&"cat", ""))) == cat)

static func recipes_at_station(db, station: StringName) -> Array:
	return db.all_of_type(&"recipe").filter(func(r): return r.station() == station)

# research defs grouped by tier: {tier:int -> Array[Def]} (each tier keeps registration order).
static func research_tiers(db) -> Dictionary:
	var tiers: Dictionary = {}
	for r in db.all_of_type(&"research"):
		var t: int = int(r.field(&"tier", 1))
		if not tiers.has(t):
			tiers[t] = []
		tiers[t].append(r)
	return tiers

# Is this building def unlocked under the given ResearchState? (null research == only ungated allowed.)
static func building_unlocked(bdef, research) -> bool:
	var req: StringName = StringName(str(bdef.field(&"requires_research", "")))
	if req == &"":
		return true
	if research == null:
		return false
	return research.is_unlocked(req)

# Attach the right comps to a freshly-built station/building Thing (workbench station tag, power comps,
# medbed quality) so a host can instantiate catalogue buildings with one call.
static func make_building_thing(db, id: StringName):
	var bdef = db.get_def(id)
	if bdef == null or bdef.def_type != &"building":
		return null
	var thing = Things.Thing.new(Defs.Def.new(&"building", id, {"max_hp": float(bdef.field(&"hp", 100.0))}))
	thing.flags["building"] = id
	var st: StringName = StringName(str(bdef.field(&"station", "")))
	if st != &"":
		thing.add_comp(Production.CompWorkbench.new({"station": st}))
	var power: Dictionary = bdef.field(&"power", {})
	if not power.is_empty():
		if power.has("draw"):
			thing.add_comp(Power.CompPowerTrader.new({"draw": float(power.draw), "priority": int(power.get("priority", 0))}))
		if power.has("rated"):
			var props := {"kind": str(power.get("kind", "fuel")), "rated": float(power.rated)}
			if power.has("fuel_max"):
				props["fuel"] = float(power.fuel_max)
				props["fuel_max"] = float(power.fuel_max)
				props["burn_per_day"] = float(power.get("burn_per_day", 1.0))
			thing.add_comp(Power.CompPowerSource.new(props))
		if power.has("capacity"):
			thing.add_comp(Power.CompBattery.new({"capacity": float(power.capacity)}))
	var extra: Dictionary = bdef.field(&"extra", {})
	if extra.has("med_quality"):
		thing.add_comp(Gear.CompMedbed.new({"med_quality": int(extra.med_quality)}))
	return thing

# Build a plantable crop Thing from a crop def (CompGrower props straight off the catalogue).
static func make_crop_thing(db, id: StringName):
	var cdef = db.get_def(id)
	if cdef == null or cdef.def_type != &"crop":
		return null
	var thing = Things.Thing.new(Defs.Def.new(&"crop", id, {"max_hp": 20.0}))
	thing.flags["crop"] = id
	thing.add_comp(Things.CompGrower.new({
		"grow_days": float(cdef.field(&"grow_days", 6.0)),
		"temp_min": float(cdef.field(&"temp_min", 0.0)),
		"temp_max": float(cdef.field(&"temp_max", 42.0)),
		"min_light": float(cdef.field(&"min_light", 0.3)),
	}))
	return thing

# Harvest a mature crop Thing into the stock: returns the yielded amount (0 if not mature/not a crop).
static func harvest_crop(db, thing, stock: Dictionary) -> int:
	if thing == null or not thing.flags.has("crop"):
		return 0
	var grower = thing.get_comp(Things.CompGrower)
	if grower == null or not grower.mature():
		return 0
	var cdef = db.get_def(StringName(str(thing.flags.crop)))
	if cdef == null:
		return 0
	var res := StringName(str(cdef.field(&"yield_res", "")))
	var amt: int = int(cdef.field(&"yield_amt", 1))
	stock[res] = int(stock.get(res, 0)) + amt
	thing.destroyed = true
	return amt

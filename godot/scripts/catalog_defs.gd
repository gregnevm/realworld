# RealWorld — catalog_defs.gd : the LIVE-TIER adapter over the content catalogue (spec 0008 ph. 3–4).
#
# data_bridge.gd translates resource IDS; this module translates building/recipe DEFS: it projects the
# catalogue's records into the exact dict shape data.gd's tables use, so the live sim's one def seam
# (sim.building_def) can serve both vocabularies without the tick paths caring which fed them.
#
# CURATED LIVE TIER (spec 0008 §5.3): not every catalogue building may enter the live game yet — a
# def whose MECHANIC is not simulated would be a decorative trap (build it, nothing happens). The
# filter is capability-driven, not a hand list:
#   • categories structure / production / storage / defense / power (farming, comfort, art, utility,
#     ship wait for their systems; data.gd already owns the live comfort/light/heat pieces);
#   • power participation is LIVE (Batch 8c, sim/power.gd): sources/batteries build in the power
#     category; trader (drawing) defs in the live categories gate on the net via device_active.
#     Nets are SPATIAL: adjacency + power_conduit chains group participants into separate grids;
#   • defense must map onto a live brain: turret-shaped (range+cooldown) or trap-shaped (trap);
#   • ids data.gd owns are EXCLUDED — the tuned Phase-0 defs win, one truth per id (BuildBar is
#     their home; the catalog browser complements with the catalogue-only content).
#
# Phase 4 (grow the live resource set): gathering under `use_catalog` yields each node kind's
# catalogue BUNDLE — rocks occasionally give ore/coal/clay/sand, trees fiber, bushes herbs — via a
# PURE function of (cell, remaining amount): deterministic, replayable, and it consumes NO rng
# stream, so raid/weather determinism cannot shift by a single draw.
#
# Determinism: pure data + caches; no rng, no time.
extends RefCounted

const Catalog = preload("res://scripts/kernel/catalog.gd")
const GameData = preload("res://scripts/data.gd")

const LIVE_CATEGORIES := ["structure", "production", "storage", "defense", "power", "farming"]
const STORAGE_DEFAULT_CAPACITY := 150

# Which stock resource refuels each fuel-kind generator (1 stock unit == 1 fuel unit). Geothermal
# burns nothing (burn_per_day 0) so it never refuels. Data-side map — adding a generator adds a row.
const GENERATOR_FUEL := {"wood_generator": "wood", "chemfuel_generator": "chemfuel"}

# ---- farming (sim/farming.gd consumes; kernel CompGrower owns the growth physics) ----
# One grow cycle (days) at grow_mult 1.0, and the kernel gates it reads (crops dormant outside the
# temp band or in the dark — the same climate that bites the pawn now feeds or starves the fields).
const FARM_GROW_DAYS := 3.0
const FARM_TEMP_MIN := 5.0
const FARM_TEMP_MAX := 42.0
const FARM_MIN_LIGHT := 0.3
const FARM_YIELD := 6
# The default MIXED plot: each harvest yields the next staple in a per-cell rotation (the
# gather_yield pattern) — deterministic. A zone with a SELECTED crop (set_crop verb cycles
# CROP_CYCLE) yields that crop instead; hops opens the brewery chain (wort -> beer).
const FARM_ROTATION := ["grain", "raw_food", "plant_fiber", "grain", "herbal", "raw_food"]
const CROP_CYCLE := ["", "grain", "raw_food", "plant_fiber", "herbal", "hops"]   # "" == mixed plot

# Meal THING-outputs (bread, cooked meals) land in stock and are EDIBLE: hunger restored per unit.
# raw_food's inline value is 38 (sim.gd) — cooking beats foraging, lavish beats everything.
const MEAL_NUTRITION := {
	"bread": 55.0, "simple_meal": 48.0, "fine_meal": 70.0,
	"lavish_meal": 90.0, "pemmican": 42.0, "kibble": 25.0,
}

# ---- medicine (sim/hero_health.gd bed-tend consumes; kernel TendService owns the math) ----
# Quality multiplier per consumable medicine (better meds deliver a bigger tend relief burst).
const MED_RELIEF := {"medicine": 1.2, "herbal_medicine": 0.9}

# Per-node-kind yield cycles (phase 4). Index = posmod(cell*31 + amount, size) — a fixed, seeded-by-
# geometry rotation, so the SAME node depletes into the SAME bundle on every replay/rejoin/twin.
const GATHER_YIELD := {
	"rock": ["stone", "stone", "iron_ore", "stone", "coal", "stone", "clay", "stone", "iron_ore", "sand", "stone", "copper_ore"],
	"tree": ["wood", "wood", "wood", "plant_fiber", "wood"],
	"bush": ["raw_food", "raw_food", "herbal", "raw_food", "plant_fiber"],
}

static var _live: Variant = null       # id(String) -> adapter dict (the data.gd building shape)
static var _recipes: Variant = null    # id(String) -> raw catalogue recipe record
static var _research_labels: Variant = null   # research id(String) -> Ukrainian label
static var _res_icons: Variant = null  # resource id(String) -> icon (every catalogue resource has one)
static var _res_labels: Variant = null # resource id(String) -> Ukrainian label

# ---------------- live-buildable building adapters ----------------
static func _build_cache() -> void:
	if _live != null:
		return
	_live = {}
	_recipes = {}
	_research_labels = {}
	_res_icons = {}
	_res_labels = {}
	var cat: Dictionary = Catalog.load_json()
	for r in cat.get("resources", []):
		_res_icons[str(r.get("id", ""))] = str(r.get("icon", ""))
		_res_labels[str(r.get("id", ""))] = str(r.get("label", r.get("id", "")))
	for r in cat.get("research", []):
		_research_labels[str(r.get("id", ""))] = str(r.get("label", r.get("id", "")))
	for rc in cat.get("recipes", []):
		_recipes[str(rc.get("id", ""))] = rc
	for b in cat.get("buildings", []):
		var id := str(b.get("id", ""))
		if GameData.BUILDINGS.has(id):
			continue                                # data.gd owns this id — the tuned def wins
		var category := str(b.get("category", ""))
		# category filter, with ONE exception: the medical beds (comfort, `medbed:true` in the data)
		# — their mechanic (sleepable bed + tend quality) is live via hero_health's bed-tend
		if not LIVE_CATEGORIES.has(category) and not bool(b.get("medbed", false)):
			continue
		var power: Dictionary = b.get("power", {})
		var is_conduit: bool = category == "power" and str(power.get("role", "")) == ""
		if is_conduit and id != "power_conduit":
			continue                                # power category without a role: only the conduit
		if category == "farming" and not bool(b.get("grow", false)):
			continue                                # farming must map onto the live grower brain
		var is_trap := bool(b.get("trap", false))
		var is_turret: bool = float(b.get("range", 0.0)) > 0.0 and float(b.get("cooldown", 0.0)) > 0.0
		if category == "defense" and not (is_trap or is_turret):
			continue                                # defense must map onto a live brain
		var label := str(b.get("label", id))
		var def := {
			"name": label,
			"cost": (b.get("cost", {}) as Dictionary).duplicate(true),
			"hp": float(b.get("hp", 100.0)),
			"blocks": bool(b.get("blocks", false)),
			"glyph": label.substr(0, 1).to_upper(),
		}
		var research := str(b.get("research", ""))
		if research != "":
			def["research"] = research
		if category == "storage":
			def["capacity"] = int(b.get("capacity", STORAGE_DEFAULT_CAPACITY))
		if bool(b.get("station", false)) or bool(b.get("autocraft", false)):
			def["station"] = true
		if is_trap:
			# continuous-contact approximation of the catalogue's one-shot {damage, uses} traps —
			# the live trap brain (threats.gd) is a data-capability read of trap_dps
			def["trap_dps"] = float(b.get("damage", 0.0))
		if is_turret:
			def["range"] = float(b.get("range", 0.0))
			def["shot_dmg"] = float(b.get("damage", 0.0))
			def["shot_cool"] = float(b.get("cooldown", 1.0))
			if b.has("ammo_max"):
				def["ammo_max"] = int(b.get("ammo_max", 0))   # this turret FIRES stock ammo
		if bool(b.get("bed", false)):
			def["bed"] = true                       # sleepable (sim bed capability)
		if bool(b.get("medbed", false)):
			# kernel CompMedbed.quality_mult formula (0.6 + 0.15 × tier) — one truth for the math
			def["medbed_mult"] = 0.6 + 0.15 * float(b.get("med_quality", 2))
		if not power.is_empty():
			def["power"] = power.duplicate(true)    # sim/power.gd reads role/rated/draw/capacity
		if is_conduit:
			def["conduit"] = true                   # passive net link: nets are SPATIAL (sim/power.gd)
		if bool(b.get("grow", false)):
			def["grow"] = true                      # sim/farming.gd reads grow (+mult) per zone
			def["grow_mult"] = float(b.get("grow_mult", 1.0))
		_live[id] = def

# The data.gd-shaped def for a live-buildable catalogue building ({} = not live-buildable).
static func building(id: String) -> Dictionary:
	_build_cache()
	return _live.get(id, {})

# The live-buildable catalogue-only id set (StringName -> true), for the browser's action filter.
static func live_ids() -> Dictionary:
	_build_cache()
	var out: Dictionary = {}
	for id in _live:
		out[StringName(str(id))] = true
	return out

# ---------------- recipes ----------------
# The raw catalogue recipe record ({} = unknown id).
static func recipe(id: String) -> Dictionary:
	_build_cache()
	return _recipes.get(id, {})

# The first catalogue recipe that PRODUCES `res` ({} = none) — the view says «де взяти» from it. Sorted by id: deterministic.
static func recipe_for(res: String) -> Dictionary:
	_build_cache()
	var ids: Array = (_recipes as Dictionary).keys()
	ids.sort()
	for id in ids:
		var rc: Dictionary = _recipes[id]
		if str((rc.get("output", {}) as Dictionary).get("id", "")) == res:
			return rc
	return {}

# Ukrainian label of a catalogue research project (falls back to the id).
static func research_label(id: String) -> String:
	_build_cache()
	return str(_research_labels.get(id, id))

# Icon of a catalogue resource id (falls back to "id " so a cost line stays readable).
static func res_icon(id: String) -> String:
	_build_cache()
	var icon := str(_res_icons.get(id, ""))
	return icon if icon != "" else id + " "

# The stock resource a fuel generator burns ("" = self-sufficient, e.g. geothermal).
static func generator_fuel(id: String) -> String:
	return str(GENERATOR_FUEL.get(id, ""))

# The crop a plot yields on its Nth harvest — a pure per-cell rotation (the gather_yield pattern):
# deterministic, replay/rejoin-exact, no rng.
static func farm_crop(cell: int, harvests: int) -> String:
	return str(FARM_ROTATION[posmod(cell * 17 + harvests, FARM_ROTATION.size())])

# Ukrainian label of a catalogue resource id (falls back to the id).
static func res_label(id: String) -> String:
	_build_cache()
	return str(_res_labels.get(id, id))

# The next crop in the selection cycle after `current` ("" == the mixed plot).
static func next_crop(current: String) -> String:
	var i: int = CROP_CYCLE.find(current)
	return str(CROP_CYCLE[(i + 1) % CROP_CYCLE.size()]) if i >= 0 else str(CROP_CYCLE[0])

# Hunger a meal unit restores (0.0 == not a meal).
static func meal_nutrition(id: String) -> float:
	return float(MEAL_NUTRITION.get(id, 0.0))

# Ukrainian label of a building id from EITHER vocabulary (data.gd def name / adapter name / the id).
static func building_label(id: String) -> String:
	if GameData.BUILDINGS.has(id):
		return str(GameData.BUILDINGS[id].name)
	var def := building(id)
	return str(def.get("name", id))

# ---------------- phase 4: node-yield enrichment ----------------
# The catalogue resource one gather unit yields from a node, as a pure function of the node's cell
# and its remaining amount. "" = keep the node's base resource (also: unknown kind / flag OFF path).
static func gather_yield(kind: String, cell: int, amount: int) -> String:
	var table: Variant = GATHER_YIELD.get(kind, null)
	if table == null:
		return ""
	return str(table[posmod(cell * 31 + amount, (table as Array).size())])

# RealWorld — catalog_defs.gd : the LIVE-TIER adapter over the content catalogue (spec 0008 ph. 3–4).
#
# data_bridge.gd translates resource IDS; this module translates building/recipe DEFS: it projects the
# catalogue's records into the exact dict shape data.gd's tables use, so the live sim's one def seam
# (sim.building_def) can serve both vocabularies without the tick paths caring which fed them.
#
# CURATED LIVE TIER (spec 0008 §5.3): not every catalogue building may enter the live game yet — a
# def whose MECHANIC is not simulated would be a decorative trap (build it, nothing happens). The
# filter is capability-driven, not a hand list:
#   • categories structure / production / storage / defense only (power, farming, comfort, art,
#     utility, ship wait for their systems; data.gd already owns the live comfort/light/heat pieces);
#   • no `power` participation (there is no live power net — a free-running powered turret would be
#     the reverse trap);
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

const LIVE_CATEGORIES := ["structure", "production", "storage", "defense"]
const STORAGE_DEFAULT_CAPACITY := 150

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

# ---------------- live-buildable building adapters ----------------
static func _build_cache() -> void:
	if _live != null:
		return
	_live = {}
	_recipes = {}
	_research_labels = {}
	_res_icons = {}
	var cat: Dictionary = Catalog.load_json()
	for r in cat.get("resources", []):
		_res_icons[str(r.get("id", ""))] = str(r.get("icon", ""))
	for r in cat.get("research", []):
		_research_labels[str(r.get("id", ""))] = str(r.get("label", r.get("id", "")))
	for rc in cat.get("recipes", []):
		_recipes[str(rc.get("id", ""))] = rc
	for b in cat.get("buildings", []):
		var id := str(b.get("id", ""))
		if GameData.BUILDINGS.has(id):
			continue                                # data.gd owns this id — the tuned def wins
		var category := str(b.get("category", ""))
		if not LIVE_CATEGORIES.has(category):
			continue
		if not (b.get("power", {}) as Dictionary).is_empty():
			continue                                # no live power net -> powered defs wait
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

# Ukrainian label of a catalogue research project (falls back to the id).
static func research_label(id: String) -> String:
	_build_cache()
	return str(_research_labels.get(id, id))

# Icon of a catalogue resource id (falls back to "id " so a cost line stays readable).
static func res_icon(id: String) -> String:
	_build_cache()
	var icon := str(_res_icons.get(id, ""))
	return icon if icon != "" else id + " "

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

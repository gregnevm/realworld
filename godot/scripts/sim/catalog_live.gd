# RealWorld — sim/catalog_live.gd : the LIVE bridge from the content catalogue into the playable sim
# (spec 0008 phases 3–4 / unification Stage 3). Static module over `s` (the sim), no state, no preload
# of sim.gd — the same pattern as threats/environment/world_meta.
#
# Two jobs:
#   • building_def(kind) — the ONE def seam for buildings: data.gd first (the tuned Phase-0 palette
#     keeps its exact numbers), else the catalogue BuildingDef mapped into the same data.gd shape
#     (name/cost/hp/blocks/capacity/extra.heat/extra.light/research_rate/bed/station). Every consumer
#     (sim internals, sim/ modules, world_view, hud_model.world_of, session.research_rate) reads defs
#     through it, so a placed catalogue building renders, blocks, warms, lights, stores and researches
#     exactly like a native one. Resolution is UNCONDITIONAL (a loaded region must always render its
#     buildings); only NEW placement is gated on s.use_catalog (sim.try_build).
#   • craft(s, recipe_id) — the live catalogue craft verb: station placed on the map + research gate +
#     open-stock afford → pay inputs, deposit the bulk output. Thing-output recipes (meals) are not in
#     the live world yet — the ViewModel filters them out of the live craft list, and this refuses them.
#
# Determinism: pure lookups + stock arithmetic; no rng, no time.
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const Production = preload("res://scripts/kernel/production.gd")

# Lazily-built, process-cached catalogue db + merged-def cache (kind -> data.gd-shaped Dictionary).
# The OFF-flag slice never touches the catalogue, so the db loads only when a catalogue kind appears.
static var _db: Variant = null
static var _defs: Dictionary = {}


static func db():
	if _db == null:
		_db = Catalog.build_db()
	return _db


# ---- the building-def seam -----------------------------------------------------------------------
# data.gd def when the kind is native; else the catalogue def in data.gd shape; else {} (unknown).
static func building_def(kind: String) -> Dictionary:
	if GameData.BUILDINGS.has(kind):
		return GameData.BUILDINGS[kind]
	if _defs.has(kind):
		return _defs[kind]
	var b: Variant = db().get_def(StringName(kind))
	if b == null or not (b is Catalog.BuildingDef):
		return {}
	var def := {
		"name": String(b.label()),
		"cost": _int_cost(b.cost()),
		"hp": float(b.hp()),
		"blocks": bool(b.data.get("blocks", false)),
		"category": String(b.category()),
	}
	if str(b.research()) != "":
		def["research"] = str(b.research())
	if b.is_station():
		def["station"] = true
	if b.data.has("capacity"):
		def["capacity"] = int(b.data.capacity)
	if b.data.has("research_rate"):
		def["research_rate"] = float(b.data.research_rate)
	if b.data.has("bed"):
		def["bed"] = bool(b.data.bed)
	var extra := {}
	if b.data.has("emits_heat"):
		extra["heat"] = float(b.data.emits_heat)
	if b.data.has("emits_light"):
		extra["light"] = true
	if not extra.is_empty():
		def["extra"] = extra
	_defs[kind] = def
	return def


# JSON round-trips numbers as floats — coerce a cost dict to ints once, at the seam.
static func _int_cost(cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost:
		out[str(k)] = int(cost[k])
	return out


# ---- live catalogue craft (spec 0008 phase 3) ----------------------------------------------------
# Any recipe def whose station stands on the live map: research-gated, paid from the open stock,
# bulk output deposited to storage. Returns {ok, msg?} (the router flashes refusals, R10).
static func craft(s, recipe_id: String) -> Dictionary:
	if not s.use_catalog:
		return {"ok": false, "msg": "Каталог не активний у цьому регіоні."}
	var rc: Variant = db().get_def(StringName(recipe_id))
	if rc == null or not (rc is Production.RecipeDef):
		return {"ok": false, "msg": "Невідомий рецепт."}
	var station := String(rc.data.get("station", ""))
	if not station_standing(s, station):
		return {"ok": false, "msg": "Потрібна станція: %s." % building_def(station).get("name", station)}
	if not s.research_ok(rc.data):
		return {"ok": false, "msg": "🔒 Потребує дослідження: %s." % research_label(str(rc.data.get("research", "")))}
	var out: Dictionary = rc.output()
	if bool(out.get("thing", false)):
		return {"ok": false, "msg": "Цей рецепт видає предмет — у живому світі ще не готово."}
	var inputs := _int_cost(rc.inputs())
	if not s.afford(inputs):
		return {"ok": false, "msg": "Бракує: " + cost_line(inputs)}
	GameData.pay_cost(s.stock, s.cost_keys(inputs))
	var count := maxi(1, int(out.get("count", 1)))
	var res := String(out.get("id", ""))
	var added: int = s.deposit(res, count)
	s._log("⚒ %s: +%d %s." % [String(rc.data.get("label", recipe_id)), added, _res_label(res)], "good")
	return {"ok": true}


# A building of this kind stands on the live map (the recipe's station requirement).
static func station_standing(s, kind: String) -> bool:
	for b in s.buildings:
		if String(b.kind) == kind:
			return true
	return false


# Placed live buildings that the catalogue knows as craft stations: {StringName kind: true}.
# Feeds the live craft_actions slice — data.gd's workbench/campfire double as catalogue stations
# because the ids deliberately match.
static func stations_placed(s) -> Dictionary:
	var out: Dictionary = {}
	for b in s.buildings:
		var d: Variant = db().get_def(StringName(String(b.kind)))
		if d is Catalog.BuildingDef and d.is_station():
			out[StringName(String(b.kind))] = true
	return out


# ---- labels / formatting (sim-side messages; NOT ui — flash strings live in the sim channel) ------
# Research label: the data.gd mirror first (the 5 gate labels the frozen slice ships), else the
# catalogue def's own label, else the raw id.
static func research_label(id: String) -> String:
	if GameData.RESEARCH_LABEL.has(id):
		return String(GameData.RESEARCH_LABEL[id])
	var d: Variant = db().get_def(StringName(id))
	if d != null and d.has_method("label"):
		return String(d.label())
	return id


static func _res_label(res: String) -> String:
	if GameData.RES.has(res):
		return String(GameData.RES[res].label)
	var d: Variant = db().get_def(StringName(res))
	if d != null and d.has_method("label"):
		return String(d.label())
	return res


# Icon+number cost line for flash messages, across BOTH vocabularies: data.gd RES icons for live ids,
# catalogue ResourceDef icons for catalogue ids, the id itself as a last resort.
static func cost_line(cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost:
		var key := str(k)
		var icon := ""
		if GameData.RES.has(key):
			icon = String(GameData.RES[key].icon)
		else:
			var d: Variant = db().get_def(StringName(key))
			if d != null and d.has_method("icon"):
				icon = String(d.icon())
		parts.append("%s%d" % [icon if icon != "" else key + " ", int(cost[k])])
	return " ".join(parts)

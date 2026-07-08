# RealWorld — data_bridge.gd : the Rosetta stone between the Phase-0 live tables and the catalogue.
#
# Spec 0007 Stage 1. A PURE, behaviour-free map between the six data.gd resource ids and their
# catalogue resource ids, so a later stage can key sim.stock by catalogue ids without a flag-day rename.
# Five ids are 1:1 (wood/stone/scrap/planks/components); the live "food" resolves to the catalogue's raw
# edible "raw_food". Imports the kernel only (never ui — R1). No sim behaviour changes this stage; this
# is only the vocabulary the migration's next stages consume.
extends RefCounted

const Catalog = preload("res://scripts/kernel/catalog.gd")

# data.gd resource id (String) -> catalogue resource id (String).
const TO_CATALOG := {
	"wood": "wood",
	"stone": "stone",
	"scrap": "scrap",
	"planks": "planks",
	"components": "components",
	"food": "raw_food",
}

# Map a live id to its catalogue id (unknown ids pass through unchanged, so it's safe over any stock key).
static func to_catalog(res_id) -> StringName:
	return StringName(str(TO_CATALOG.get(str(res_id), str(res_id))))

# Reverse: catalogue id -> live id (identity when no live alias exists).
static func from_catalog(cat_id) -> StringName:
	var c := str(cat_id)
	for k in TO_CATALOG:
		if TO_CATALOG[k] == c:
			return StringName(k)
	return StringName(c)

# The invariant Stage 2 relies on: every live resource id resolves to a real catalogue ResourceDef.
# Returns the list of unmet mappings ([] == the bridge is total).
static func validate(db) -> Array:
	var errs: Array = []
	if db == null:
		return ["no catalogue db"]
	for k in TO_CATALOG:
		var d = db.get_def(to_catalog(k))
		if d == null or not (d is Catalog.ResourceDef):
			errs.append("data id '%s' -> '%s' is not a catalogue resource" % [k, TO_CATALOG[k]])
	return errs

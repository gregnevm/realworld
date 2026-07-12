# RealWorld — kernel/catalog.gd : the deep content tree, loaded through the Defs seam.
#
# RimWorld analogue: the whole DefDatabase built from XML Defs at load; here the catalogue lives in
# godot/content/catalog.json (the wire format Defs.load_pack was designed for — see defs.gd) and this
# module turns those raw records into TYPED defs the kernel already understands: recipes and research
# reuse production.gd's RecipeDef/ResearchDef verbatim; resources, buildings and items get thin typed
# defs here. It NEVER edits sim.gd/main.gd/data.gd — it is the forward-engine content source that
# composes on the shipped kernel grammar.
#
# The one job beyond loading is VALIDATION IN DEPTH. Per-def validate() (run by DefDatabase.validate_all)
# checks each record; validate_catalog() adds the graph-level invariants that make the tree coherent:
#   • every research prereq / build-gate / recipe-gate resolves to a real research node
#   • the tech tree is acyclic (a real DAG, so research can always finish)
#   • every recipe/item station is a real craft building
#   • every cost/input names a known resource
#   • REACHABILITY: from the raw (mined/chopped/gathered/hunted/farmed) roots, every resource is
#     producible, every research reachable, every building buildable, every recipe/item craftable —
#     i.e. NOTHING in the tree is stranded. This mirrors tests/catalog.test.js one-for-one so the Node
#     validator and this loader can never silently disagree about the same catalog.json.
#
# Determinism: pure data + set closure; no rng, no time.
extends RefCounted

const Defs = preload("res://scripts/kernel/defs.gd")
const Production = preload("res://scripts/kernel/production.gd")

const CATALOG_PATH := "res://content/catalog.json"

# A resource whose `sources` include any of these is a RAW root of the reachability closure.
const RAW_SOURCES := ["mine", "chop", "gather", "hunt", "farm"]

# ============================================================================================
# TYPED DEFS (resources / buildings / items). Recipes + research reuse production.gd unchanged.
# ============================================================================================

# A resource record: id, label, icon, tier, how it's obtained, stack size, optional rot/fuel.
class ResourceDef extends Defs.Def:
	func _init(p_id: StringName, p_data: Dictionary = {}) -> void:
		super(&"resource", p_id, p_data)

	func label() -> String:
		return str(data.get("label", str(id)))

	func icon() -> String:
		return str(data.get("icon", ""))

	func tier() -> int:
		return int(data.get("tier", 0))

	func sources() -> Array:
		return data.get("sources", [])

	func stack() -> int:
		return int(data.get("stack", 75))

	func is_raw() -> bool:
		return Catalog._is_raw_sources(sources())

	func validate(_db) -> String:
		if sources().is_empty():
			return "resource has no sources"
		return ""

# A building record: cost, hp, category, whether it is a craft station, its research gate, optional
# power participation ({role, kind, rated, draw, capacity, ...}).
class BuildingDef extends Defs.Def:
	func _init(p_id: StringName, p_data: Dictionary = {}) -> void:
		super(&"building", p_id, p_data)

	func label() -> String:
		return str(data.get("label", str(id)))

	func cost() -> Dictionary:
		return data.get("cost", {})

	func hp() -> float:
		return float(data.get("hp", 100.0))

	func category() -> StringName:
		return StringName(str(data.get("category", "structure")))

	# A craft station either hosts bills (station:true) or auto-crafts (autocraft:true).
	func is_station() -> bool:
		return bool(data.get("station", false)) or bool(data.get("autocraft", false))

	func research() -> StringName:
		return StringName(str(data.get("research", "")))

	func power() -> Dictionary:
		return data.get("power", {})

	func validate(_db) -> String:
		if hp() <= 0.0:
			return "building hp must be > 0"
		if cost().is_empty():
			return "building has no cost"
		return ""

# An item record (tool/weapon/apparel): its recipe (inputs), the station it's made at, equip slot,
# research gate, plus kind-specific stats (gather_mult / dmg_bonus / insulation_c / armor).
class ItemDef extends Defs.Def:
	func _init(p_id: StringName, p_data: Dictionary = {}) -> void:
		super(&"crafted_item", p_id, p_data)

	func label() -> String:
		return str(data.get("label", str(id)))

	func recipe() -> Dictionary:
		return data.get("recipe", {})

	func station() -> StringName:
		return StringName(str(data.get("station", "")))

	func kind() -> StringName:
		return StringName(str(data.get("kind", "misc")))

	func slot() -> StringName:
		return StringName(str(data.get("slot", "misc")))

	func research() -> StringName:
		return StringName(str(data.get("research", "")))

	func validate(_db) -> String:
		if recipe().is_empty():
			return "item has no recipe"
		if str(station()) == "":
			return "item has no station"
		return ""

# ============================================================================================
# LOADING
# ============================================================================================

# Read + parse the raw catalog JSON into a Dictionary. Returns {} (and pushes an error) on any failure.
static func load_json(path: String = CATALOG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("catalog missing: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open catalog: %s" % path)
		return {}
	var text := f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("catalog root is not a JSON object")
		return {}
	return parsed

# Build a typed DefDatabase from a catalog dict (or the on-disk catalog when none is passed). Recipes
# reuse Production.RecipeDef; the JSON's "research" gate key is normalised to the "requires_research"
# key RecipeDef.requires_research() reads, so the existing ProductionSystem gate works unchanged.
static func build_db(cat: Dictionary = {}) -> Defs.DefDatabase:
	var data: Dictionary = cat if not cat.is_empty() else load_json()
	var db := Defs.DefDatabase.new()
	for r in data.get("resources", []):
		db.register(ResourceDef.new(StringName(str(r.get("id", ""))), r))
	for r in data.get("research", []):
		db.register(Production.ResearchDef.new(StringName(str(r.get("id", ""))), r))
	for b in data.get("buildings", []):
		db.register(BuildingDef.new(StringName(str(b.get("id", ""))), b))
	for rc in data.get("recipes", []):
		var rec: Dictionary = rc.duplicate()
		rec["requires_research"] = str(rc.get("research", ""))
		db.register(Production.RecipeDef.new(StringName(str(rec.get("id", ""))), rec))
	for it in data.get("items", []):
		db.register(ItemDef.new(StringName(str(it.get("id", ""))), it))
	return db

# ============================================================================================
# ACCESSORS (typed slices the UI / host binds against)
# ============================================================================================

static func resources(db) -> Array:
	return db.all_of_type(&"resource")

static func research_projects(db) -> Array:
	return db.all_of_type(&"research")

static func buildings(db) -> Array:
	return db.all_of_type(&"building")

static func recipes(db) -> Array:
	return db.all_of_type(&"recipe")

static func items(db) -> Array:
	return db.all_of_type(&"crafted_item")

# Recipes hosted at a given station building id.
static func recipes_at(db, station: StringName) -> Array:
	var out: Array = []
	for r in recipes(db):
		if StringName(str(r.data.get("station", ""))) == station:
			out.append(r)
	return out

# Buildings in a category (structure/production/power/storage/comfort/farming/defense).
static func buildings_in(db, category: StringName) -> Array:
	var out: Array = []
	for b in buildings(db):
		if b.category() == category:
			out.append(b)
	return out

# ============================================================================================
# BILL-OF-MATERIALS PLANNER (spec 0008 phase 1 — pure, no sim change)
# ============================================================================================
# The production PIPELINE as data: given a target resource, the ordered recipe steps to make it from
# raws; given a cost + a stock, the shortfall. These are what a gated build/craft menu (spec 0008) and
# "to make X you need …" tooltips consume. Pure graph walk over the raw catalog dict — mirrored by
# tests/catalog.test.js so the Node validator and this loader never disagree.

# The recipe id that produces `res_id` (the first by declaration order; "" for a raw / unproduced res).
static func producer_of(cat: Dictionary, res_id) -> StringName:
	var rid := StringName(res_id)
	for rc in cat.get("recipes", []):
		if StringName(str(rc.get("output", {}).get("id", ""))) == rid:
			return StringName(str(rc.get("id", "")))
	return &""

# The ordered recipe steps to produce `res_id` from raw roots — dependencies FIRST, the target's own
# recipe LAST, deduped. [] for a raw resource (obtained straight from the map) or one with no recipe.
static func production_chain(cat: Dictionary, res_id) -> Array:
	var raws: Dictionary = {}
	for r in cat.get("resources", []):
		if _is_raw_sources(r.get("sources", [])):
			raws[StringName(str(r.get("id", "")))] = true
	var by_out: Dictionary = {}
	for rc in cat.get("recipes", []):
		var oid := StringName(str(rc.get("output", {}).get("id", "")))
		if not by_out.has(oid):
			by_out[oid] = rc
	var out: Array = []
	_chain_visit(StringName(res_id), raws, by_out, out, {}, {})
	return out

static func _chain_visit(rid: StringName, raws: Dictionary, by_out: Dictionary, out: Array, seen: Dictionary, stack: Dictionary) -> void:
	if raws.has(rid) or not by_out.has(rid):        # raw, or nothing produces it -> no step to add
		return
	var recipe: Dictionary = by_out[rid]
	var recid := StringName(str(recipe.get("id", "")))
	if seen.has(recid) or stack.has(recid):         # dedupe + cycle guard (the tree is acyclic anyway)
		return
	stack[recid] = true
	for inp in recipe.get("inputs", {}):
		_chain_visit(StringName(str(inp)), raws, by_out, out, seen, stack)
	stack.erase(recid)
	seen[recid] = true
	out.append(recid)

# The shortfall to afford `cost` from `stock`: {res -> missing_amount} (empty == affordable now).
static func missing_for(cost: Dictionary, stock: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in cost:
		var deficit: int = int(cost[k]) - int(stock.get(k, 0))
		if deficit > 0:
			out[k] = deficit
	return out

# Roll a cost/input dict all the way down to the total RAW resources it consumes — the full "budget"
# to make something from scratch, honouring each recipe's output count (runs = ceil(need/count)). Every
# key of the result is a raw (map-obtained) resource. This is the build/craft budget a gated menu shows.
static func raw_requirements(cat: Dictionary, cost: Dictionary) -> Dictionary:
	var raws: Dictionary = {}
	for r in cat.get("resources", []):
		if _is_raw_sources(r.get("sources", [])):
			raws[StringName(str(r.get("id", "")))] = true
	var by_out: Dictionary = {}
	for rc in cat.get("recipes", []):
		var oid := StringName(str(rc.get("output", {}).get("id", "")))
		if not by_out.has(oid):
			by_out[oid] = rc
	var out: Dictionary = {}
	for res in cost:
		_accumulate_raw(StringName(str(res)), int(cost[res]), raws, by_out, out, {})
	return out

static func _accumulate_raw(rid: StringName, amount: int, raws: Dictionary, by_out: Dictionary, out: Dictionary, stack: Dictionary) -> void:
	if amount <= 0:
		return
	if raws.has(rid) or not by_out.has(rid) or stack.has(rid):   # raw / terminal / cycle-guard -> book it
		out[rid] = int(out.get(rid, 0)) + amount
		return
	stack[rid] = true
	var recipe: Dictionary = by_out[rid]
	var count: int = maxi(1, int(recipe.get("output", {}).get("count", 1)))
	var runs: int = int(ceil(float(amount) / float(count)))
	for inp in recipe.get("inputs", {}):
		_accumulate_raw(StringName(str(inp)), runs * int(recipe.inputs[inp]), raws, by_out, out, stack)
	stack.erase(rid)

# ============================================================================================
# GRAPH VALIDATION (the depth guarantee)
# ============================================================================================

# True when any of a resource's source tags is a raw (map-obtained) source.
static func _is_raw_sources(sources: Array) -> bool:
	for s in sources:
		if RAW_SOURCES.has(str(s)):
			return true
	return false

# A build/craft gate ("" / missing means ungated) is satisfied when the named project is unlocked.
static func _gate_ok(ref, unlocked: Dictionary) -> bool:
	var r: String = str(ref)
	return r == "" or unlocked.has(StringName(r))

# Every key of a cost/input dict is in the obtainable set.
static func _cost_ok(cost: Dictionary, obtainable: Dictionary) -> bool:
	for k in cost:
		if not obtainable.has(StringName(str(k))):
			return false
	return true

# The reachability closure from raw roots. Returns a dict of set-Dictionaries:
#   {obtainable, unlocked, built, made_recipes, made_items} — each StringName -> true.
static func reachability(cat: Dictionary) -> Dictionary:
	var obtainable: Dictionary = {}
	for r in cat.get("resources", []):
		if _is_raw_sources(r.get("sources", [])):
			obtainable[StringName(str(r.get("id", "")))] = true
	var unlocked: Dictionary = {}
	var built: Dictionary = {}
	var made_recipes: Dictionary = {}
	var made_items: Dictionary = {}

	var changed := true
	while changed:
		changed = false
		# 1. research whose prereqs are all unlocked
		for r in cat.get("research", []):
			var rid := StringName(str(r.get("id", "")))
			if unlocked.has(rid):
				continue
			var all_met := true
			for p in r.get("prereqs", []):
				if not unlocked.has(StringName(str(p))):
					all_met = false
					break
			if all_met:
				unlocked[rid] = true
				changed = true
		# 2. buildings whose cost is obtainable and research is unlocked
		for b in cat.get("buildings", []):
			var bid := StringName(str(b.get("id", "")))
			if built.has(bid):
				continue
			if _gate_ok(b.get("research", ""), unlocked) and _cost_ok(b.get("cost", {}), obtainable):
				built[bid] = true
				changed = true
		# 3. recipes: station built + research unlocked + inputs obtainable -> output obtainable
		for rc in cat.get("recipes", []):
			var rcid := StringName(str(rc.get("id", "")))
			if made_recipes.has(rcid):
				continue
			var station := StringName(str(rc.get("station", "")))
			if built.has(station) and _gate_ok(rc.get("research", ""), unlocked) and _cost_ok(rc.get("inputs", {}), obtainable):
				made_recipes[rcid] = true
				var out: Dictionary = rc.get("output", {})
				obtainable[StringName(str(out.get("id", "")))] = true
				changed = true
		# 4. items: station built + research unlocked + recipe inputs obtainable
		for it in cat.get("items", []):
			var iid := StringName(str(it.get("id", "")))
			if made_items.has(iid):
				continue
			var istation := StringName(str(it.get("station", "")))
			if built.has(istation) and _gate_ok(it.get("research", ""), unlocked) and _cost_ok(it.get("recipe", {}), obtainable):
				made_items[iid] = true
				changed = true

	return {
		"obtainable": obtainable,
		"unlocked": unlocked,
		"built": built,
		"made_recipes": made_recipes,
		"made_items": made_items,
	}

# Kahn topological sort over the research prereq graph. Returns true iff acyclic.
static func _tech_is_acyclic(cat: Dictionary) -> bool:
	var indeg: Dictionary = {}
	var dependents: Dictionary = {}
	for r in cat.get("research", []):
		var rid := StringName(str(r.get("id", "")))
		indeg[rid] = int(r.get("prereqs", []).size())
		if not dependents.has(rid):
			dependents[rid] = []
	for r in cat.get("research", []):
		var rid2 := StringName(str(r.get("id", "")))
		for p in r.get("prereqs", []):
			var pid := StringName(str(p))
			if not dependents.has(pid):
				dependents[pid] = []
			dependents[pid].append(rid2)
	var queue: Array = []
	for k in indeg:
		if int(indeg[k]) == 0:
			queue.append(k)
	var removed := 0
	while not queue.is_empty():
		var id: StringName = queue.pop_front()
		removed += 1
		for d in dependents.get(id, []):
			indeg[d] = int(indeg[d]) - 1
			if int(indeg[d]) == 0:
				queue.append(d)
	return removed == int(cat.get("research", []).size())

# Full graph validation. Returns an Array of human-readable error strings ([] == a healthy tree).
# Mirrors tests/catalog.test.js. Pass the raw catalog dict (load_json()); a db is built internally for
# id lookups but the checks run over the plain records so JSON int/float never bites.
static func validate_catalog(cat: Dictionary) -> Array:
	var errs: Array = []
	if cat.is_empty():
		return ["catalog is empty / failed to load"]

	# id sets
	var res_ids: Dictionary = {}
	for r in cat.get("resources", []):
		res_ids[StringName(str(r.get("id", "")))] = true
	var research_ids: Dictionary = {}
	for r in cat.get("research", []):
		research_ids[StringName(str(r.get("id", "")))] = true
	var building_ids: Dictionary = {}
	var stations: Dictionary = {}
	for b in cat.get("buildings", []):
		building_ids[StringName(str(b.get("id", "")))] = true
		if bool(b.get("station", false)) or bool(b.get("autocraft", false)):
			stations[StringName(str(b.get("id", "")))] = true

	# global id uniqueness
	var seen: Dictionary = {}
	for section in ["resources", "research", "buildings", "recipes", "items"]:
		for rec in cat.get(section, []):
			var rid := StringName(str(rec.get("id", "")))
			if str(rid) == "":
				errs.append("%s: entry with no id" % section)
			elif seen.has(rid):
				errs.append("duplicate id: %s" % rid)
			else:
				seen[rid] = true

	# research prereqs resolve
	for r in cat.get("research", []):
		for p in r.get("prereqs", []):
			if not research_ids.has(StringName(str(p))):
				errs.append("research %s: missing prereq %s" % [r.get("id", ""), p])

	# tech DAG acyclic
	if not _tech_is_acyclic(cat):
		errs.append("tech tree has a prereq cycle")

	# gate references resolve (buildings / recipes / items)
	for b in cat.get("buildings", []):
		var bg: String = str(b.get("research", ""))
		if bg != "" and not research_ids.has(StringName(bg)):
			errs.append("building %s: missing research %s" % [b.get("id", ""), bg])
		for c in b.get("cost", {}):
			if not res_ids.has(StringName(str(c))):
				errs.append("building %s: unknown cost resource %s" % [b.get("id", ""), c])
	for rc in cat.get("recipes", []):
		var rg: String = str(rc.get("research", ""))
		if rg != "" and not research_ids.has(StringName(rg)):
			errs.append("recipe %s: missing research %s" % [rc.get("id", ""), rg])
		if not stations.has(StringName(str(rc.get("station", "")))):
			errs.append("recipe %s: station %s is not a craft building" % [rc.get("id", ""), rc.get("station", "")])
		for c in rc.get("inputs", {}):
			if not res_ids.has(StringName(str(c))):
				errs.append("recipe %s: unknown input %s" % [rc.get("id", ""), c])
		var out: Dictionary = rc.get("output", {})
		if not bool(out.get("thing", false)) and not res_ids.has(StringName(str(out.get("id", "")))):
			errs.append("recipe %s: bulk output %s is not a resource" % [rc.get("id", ""), out.get("id", "")])
	for it in cat.get("items", []):
		var ig: String = str(it.get("research", ""))
		if ig != "" and not research_ids.has(StringName(ig)):
			errs.append("item %s: missing research %s" % [it.get("id", ""), ig])
		if not stations.has(StringName(str(it.get("station", "")))):
			errs.append("item %s: station %s is not a craft building" % [it.get("id", ""), it.get("station", "")])
		for c in it.get("recipe", {}):
			if not res_ids.has(StringName(str(c))):
				errs.append("item %s: unknown ingredient %s" % [it.get("id", ""), c])

	# reachability closure — nothing stranded
	var reach: Dictionary = reachability(cat)
	var obtainable: Dictionary = reach["obtainable"]
	var unlocked: Dictionary = reach["unlocked"]
	var built: Dictionary = reach["built"]
	var made_recipes: Dictionary = reach["made_recipes"]
	var made_items: Dictionary = reach["made_items"]
	for r in cat.get("resources", []):
		if not obtainable.has(StringName(str(r.get("id", "")))):
			errs.append("stranded resource (not producible): %s" % r.get("id", ""))
	for r in cat.get("research", []):
		if not unlocked.has(StringName(str(r.get("id", "")))):
			errs.append("unreachable research: %s" % r.get("id", ""))
	for b in cat.get("buildings", []):
		if not built.has(StringName(str(b.get("id", "")))):
			errs.append("unbuildable building: %s" % b.get("id", ""))
	for rc in cat.get("recipes", []):
		if not made_recipes.has(StringName(str(rc.get("id", "")))):
			errs.append("uncraftable recipe: %s" % rc.get("id", ""))
	for it in cat.get("items", []):
		if not made_items.has(StringName(str(it.get("id", "")))):
			errs.append("uncraftable item: %s" % it.get("id", ""))

	return errs

# Self-reference alias so inner classes can reach module-level statics/consts by name (kernel idiom).
const Catalog = preload("res://scripts/kernel/catalog.gd")

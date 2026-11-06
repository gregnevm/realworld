# RealWorld — headless tests for the deep content catalogue (godot/content/catalog.json).
# Run: Godot_console.exe --headless --path godot -s res://tests/run_catalog_tests.gd
#
# Proves three things about the tree:
#   1. it LOADS into typed defs through the Defs seam (build_db);
#   2. it is COHERENT as a graph (validate_catalog: acyclic tech DAG, every reference resolves,
#      full reachability from raw roots — nothing stranded). This mirrors tests/catalog.test.js
#      so the Node validator and the Godot loader can never disagree about the same file;
#   3. it actually RUNS through the shipped kernel — real catalog recipes crafted on a live
#      ProductionSystem, honouring the research gate.
extends "res://tests/harness.gd"

const Defs = preload("res://scripts/kernel/defs.gd")
const Things = preload("res://scripts/kernel/things.gd")
const Production = preload("res://scripts/kernel/production.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const CatalogSim = preload("res://scripts/catalog_sim.gd")
const DataBridge = preload("res://scripts/data_bridge.gd")
const GameData = preload("res://scripts/data.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const Inventory = preload("res://scripts/sim/inventory.gd")
const SessionScript = preload("res://scripts/session.gd")
const Sim = preload("res://scripts/sim.gd")


func _init() -> void:
	print("== RealWorld content-catalogue tests ==")
	_t_load()
	_t_build_db()
	_t_per_def_validation()
	_t_graph_validation()
	_t_depth()
	_t_accessors()
	_t_production_integration()
	_t_research_gate()
	_t_bom_planner()
	_t_sim_playthrough()
	_t_thing_lifecycle()
	_t_data_bridge()
	_t_capsule_levels_data()
	_t_capsule_levels_accessors()
	finish()

# --- BOM planner parity (spec 0008 phase 1) — mirrors tests/catalog.test.js -----------------
func _t_bom_planner() -> void:
	var cat: Dictionary = Catalog.load_json()
	# raw resources need no recipe step
	ok(Catalog.production_chain(cat, "wood").is_empty(), "raw resource has an empty production chain")
	# the advanced electronics chain resolves in dependency order: bar -> wire -> circuit
	var chain: Array = Catalog.production_chain(cat, "circuit")
	var pos: Dictionary = {}
	for i in chain.size():
		pos[str(chain[i])] = i
	var p_bar := str(Catalog.producer_of(cat, "copper_bar"))
	var p_wire := str(Catalog.producer_of(cat, "copper_wire"))
	var p_circ := str(Catalog.producer_of(cat, "circuit"))
	ok(chain.size() > 0 and str(chain[chain.size() - 1]) == p_circ, "chain ends at the circuit's own recipe")
	ok(pos.has(p_bar) and pos.has(p_wire) and int(pos[p_bar]) < int(pos[p_wire]) and int(pos[p_wire]) < int(pos[p_circ]),
		"smelt -> wire -> circuit dependency order")
	# missing_for reports exactly the shortfall
	var miss: Dictionary = Catalog.missing_for({"wood": 10, "stone": 5}, {"wood": 4, "stone": 5})
	ok(miss.size() == 1 and int(miss.get("wood", 0)) == 6, "missing_for reports only the deficient resource by its deficit")
	ok(Catalog.missing_for({"wood": 3}, {"wood": 3}).is_empty(), "exactly affordable -> nothing missing")
	# raw_requirements rolls every building cost + recipe input down to raw resources only, all > 0
	var raws: Dictionary = {}
	for r in cat.get("resources", []):
		if Catalog._is_raw_sources(r.get("sources", [])):
			raws[str(r.get("id"))] = true
	var raw_ok := true
	for b in cat.get("buildings", []):
		for k in Catalog.raw_requirements(cat, b.get("cost", {})):
			if not raws.has(str(k)):
				raw_ok = false
	for rc in cat.get("recipes", []):
		for k in Catalog.raw_requirements(cat, rc.get("inputs", {})):
			if not raws.has(str(k)):
				raw_ok = false
	ok(raw_ok, "raw_requirements bottoms out at raw resources for every building cost + recipe input")
	var passthru: Dictionary = Catalog.raw_requirements(cat, {"wood": 30, "stone": 8})
	ok(int(passthru.get("wood", 0)) == 30 and int(passthru.get("stone", 0)) == 8, "a pure-raw cost passes through unchanged")


# --- 1. load ---------------------------------------------------------------------------------
func _t_load() -> void:
	var cat: Dictionary = Catalog.load_json()
	ok(not cat.is_empty(), "catalog.json loads")
	for k in ["resources", "research", "buildings", "recipes", "items"]:
		var arr: Array = cat.get(k, [])
		ok(arr.size() > 0, "section '%s' non-empty (%d)" % [k, arr.size()])

# --- 2. build typed DefDatabase --------------------------------------------------------------
func _t_build_db() -> void:
	var db = Catalog.build_db()
	ok(db.count() > 300, "build_db registers the whole tree (%d defs)" % db.count())
	ok(Catalog.resources(db).size() >= 70, "resources loaded as typed defs (%d)" % Catalog.resources(db).size())
	ok(Catalog.recipes(db).size() >= 50, "recipes loaded as typed defs (%d)" % Catalog.recipes(db).size())
	ok(Catalog.items(db).size() >= 60, "items loaded as typed defs (%d)" % Catalog.items(db).size())
	# a recipe def is a real Production.RecipeDef with a working accessor + normalised research gate
	var comp = db.get_def(&"make_components")
	ok(comp != null and comp is Production.RecipeDef, "make_components is a RecipeDef")
	ok(comp != null and str(comp.requires_research()) == "machining", "recipe research gate normalised to requires_research")
	var steel = db.get_def(&"steel")
	ok(steel != null and steel is Catalog.ResourceDef and steel.tier() == 2, "steel is a tier-2 ResourceDef")

# --- 3. per-def validation (DefDatabase.validate_all) ----------------------------------------
func _t_per_def_validation() -> void:
	var db = Catalog.build_db()
	var errs: Array = db.validate_all()
	ok(errs.is_empty(), "every def validates (%d errors)" % errs.size())
	if not errs.is_empty():
		for e in errs:
			print("     · ", e)

# --- 4. graph validation (the depth guarantee) -----------------------------------------------
func _t_graph_validation() -> void:
	var cat: Dictionary = Catalog.load_json()
	var errs: Array = Catalog.validate_catalog(cat)
	ok(errs.is_empty(), "catalog graph is coherent — nothing stranded (%d errors)" % errs.size())
	if not errs.is_empty():
		for e in errs:
			print("     · ", e)

# --- 5. reachability depth spot-checks -------------------------------------------------------
func _t_depth() -> void:
	var cat: Dictionary = Catalog.load_json()
	var reach: Dictionary = Catalog.reachability(cat)
	var made: Dictionary = reach["made_recipes"]
	ok(made.has(&"make_circuit"), "advanced electronics chain (ore→bar→wire→circuit) resolves end to end")
	ok(made.has(&"smelt_steel"), "steel chain resolves")
	var obtainable: Dictionary = reach["obtainable"]
	ok(obtainable.has(&"medicine"), "medicine (tier-3) is reachable from raw roots")
	var unlocked: Dictionary = reach["unlocked"]
	ok(unlocked.has(&"industrialization"), "industrial research tier is reachable")
	ok(unlocked.has(&"bionics"), "bionics branch (electronics + medicine) is reachable")
	ok(unlocked.has(&"spacer_tech") and unlocked.has(&"ship_construction"), "spacer + ship-construction research is reachable")
	ok(obtainable.has(&"plasteel") and obtainable.has(&"advanced_component"), "deep alloy/electronics chain (plasteel, advanced_component) resolves")
	var made_items: Dictionary = reach["made_items"]
	ok(made_items.has(&"bionic_arm"), "mid-tier prosthetic (bind to gear.gd implants) is craftable")
	ok(made_items.has(&"archotech_arm"), "archotech-tier prosthetic (deepest chain) is craftable")
	ok(reach["built"].has(&"ship_reactor"), "end-game ship reactor is buildable")

# --- 6. typed accessors ----------------------------------------------------------------------
func _t_accessors() -> void:
	var db = Catalog.build_db()
	var at_smithy: Array = Catalog.recipes_at(db, &"smithy")
	ok(at_smithy.size() >= 1, "recipes_at(smithy) returns bench recipes (%d)" % at_smithy.size())
	var power: Array = Catalog.buildings_in(db, &"power")
	ok(power.size() >= 4, "buildings_in(power) returns the power set (%d)" % power.size())
	var solar = db.get_def(&"solar_panel")
	ok(solar != null and str(solar.power().get("kind", "")) == "solar", "solar_panel declares a solar power source")

# --- 7. production integration: craft a real catalog recipe on a live kernel ------------------
func _t_production_integration() -> void:
	var db = Catalog.build_db()
	var research = Production.ResearchState.new(db)
	research.unlock(&"machining")
	var bench = Things.Thing.new(null)
	var wb = Production.CompWorkbench.new({"maker_level": 4.0})
	bench.add_comp(wb)
	wb.add_bill(Production.Bill.new(&"make_components", &"count", 1))
	var world := {
		"db": db,
		"stock": {"iron_bar": 5, "copper_bar": 5},
		"things": [bench],
		"research": research,
	}
	var prod = Production.ProductionSystem.new()
	# work=1.0 for make_components; one tick with dday>=1.0 completes exactly one unit.
	prod.system_tick(world, {"dday": 1.5})
	var stock: Dictionary = world["stock"]
	ok(int(stock.get("components", 0)) == 1, "crafted 1 component from the catalog recipe on a live kernel")
	ok(int(stock.get("iron_bar", 0)) == 3 and int(stock.get("copper_bar", 0)) == 4, "inputs consumed exactly (2 iron_bar, 1 copper_bar)")
	bench.detach()   # break the Thing<->Comp cycle (RefCounted seam) so the suite exits leak-free

# --- 8. research gate: a gated recipe stalls until its project is unlocked --------------------
func _t_research_gate() -> void:
	var db = Catalog.build_db()
	var research = Production.ResearchState.new(db)   # steelmaking NOT unlocked
	var bench = Things.Thing.new(null)
	var wb = Production.CompWorkbench.new()
	bench.add_comp(wb)
	wb.add_bill(Production.Bill.new(&"smelt_steel", &"count", 1))
	var world := {
		"db": db,
		"stock": {"iron_bar": 5, "charcoal": 5},
		"things": [bench],
		"research": research,
	}
	var prod = Production.ProductionSystem.new()
	prod.system_tick(world, {"dday": 5.0})
	var stock: Dictionary = world["stock"]
	ok(int(stock.get("steel", 0)) == 0 and int(stock.get("iron_bar", 0)) == 5, "gated recipe stalls (no steel, inputs untouched) while research is locked")
	research.unlock(&"steelmaking")
	prod.system_tick(world, {"dday": 1.0})
	ok(int(world["stock"].get("steel", 0)) == 1, "same recipe crafts once steelmaking is unlocked")
	bench.detach()   # break the Thing<->Comp cycle (RefCounted seam) so the suite exits leak-free

# --- 9. WRITE-SIDE playthrough: research -> build -> craft up the real chain on catalog_sim -------
func _t_sim_playthrough() -> void:
	var sim = CatalogSim.new()   # builds the catalogue DefDatabase
	ok(sim.db != null and sim.db.count() > 300, "catalog_sim builds the tree (%d defs)" % sim.db.count())
	sim.grant("wood", 200); sim.grant("stone", 100); sim.grant("clay", 40)
	sim.grant("iron_ore", 40); sim.grant("coal", 40)

	# 1) research a tier-1 project by ticking (passive research advance)
	ok(sim.start_research("carpentry"), "start carpentry (no prereqs)")
	for i in 4:
		sim.tick(1.0)
	ok(sim.researched("carpentry"), "carpentry researched by ticking to its cost")

	# 2) build a station, queue a recipe, tick -> output appears in stock
	ok(sim.build("workbench").ok and sim.has_building("workbench"), "built a workbench station (ungated)")
	ok(sim.queue_craft("make_planks", &"count", 3).ok, "queued 3x make_planks at the workbench")
	for i in 8:
		sim.tick(1.0)
	ok(sim.amount("planks") >= 6, "workbench crafted planks from wood (%d)" % sim.amount("planks"))

	# 3) tech up two tiers and craft an intermediate from raw ore
	ok(sim.start_research("fire_mastery"), "start fire_mastery")
	for i in 4:
		sim.tick(1.0)
	ok(sim.start_research("smelting"), "start smelting (prereq fire_mastery now met)")
	for i in 6:
		sim.tick(1.0)
	ok(sim.researched("smelting"), "smelting researched")
	ok(sim.build("smelter").ok, "built a smelter (unlocked by smelting)")
	ok(sim.queue_craft("smelt_iron", &"count", 2).ok, "queued smelt_iron on the smelter")
	for i in 8:
		sim.tick(1.0)
	ok(sim.amount("iron_bar") >= 2, "smelter produced iron_bar from ore + coal (%d)" % sim.amount("iron_bar"))

	# 4) the research gate holds end to end — a deeper station stays locked
	ok(not sim.can_build("smithy"), "smithy stays locked until smithing is researched")
	ok(not bool(sim.build("smithy").ok), "build(smithy) is refused while its research is locked")
	sim.dispose()

# --- 9b. lifecycle: a destroyed Thing leaves the model on the next tick (sweep + detach) ----------
# Without the sweep the arrays only grow for the life of the process AND the Thing<->Comp
# back-reference cycle can never be collected (RefCounted gotcha in AGENTS.md).
func _t_thing_lifecycle() -> void:
	var sim = CatalogSim.new()
	sim.grant("wood", 100)
	sim.grant("stone", 50)
	ok(bool(sim.build("workbench").ok), "lifecycle: placed a workbench")
	ok(sim.things.size() == 1, "lifecycle: the model holds one placed Thing")
	var t = sim.things[0]
	var wb = t.get_comp(Production.CompWorkbench)
	ok(wb != null and wb.parent == t, "lifecycle: the comp back-references its Thing")
	t.take_damage(t.hp)
	ok(t.destroyed, "lifecycle: lethal damage marks the station destroyed")
	sim.tick(0.01)
	ok(sim.things.is_empty(), "lifecycle: tick() sweeps the destroyed Thing out of the model")
	ok(wb.parent == null and t.comps.is_empty(), "lifecycle: the sweep detached the comp cycle")
	sim.dispose()

# --- 10. Spec 0007 Stage 1: the live<->catalogue resource bridge is TOTAL (no behaviour change) ------
func _t_data_bridge() -> void:
	var db = Catalog.build_db()
	ok(DataBridge.validate(db).is_empty(), "every data.gd resource id maps to a real catalogue ResourceDef")
	for id in GameData.RES_ORDER:
		ok(db.get_def(DataBridge.to_catalog(id)) != null, "data.gd '%s' -> catalogue '%s' resolves" % [id, String(DataBridge.to_catalog(id))])
	ok(DataBridge.to_catalog("wood") == &"wood", "1:1 ids pass through unchanged")
	ok(DataBridge.to_catalog("food") == &"raw_food", "live 'food' maps to catalogue 'raw_food'")
	ok(DataBridge.from_catalog("raw_food") == &"food", "reverse map recovers the live id")
	ok(DataBridge.from_catalog("plasteel") == &"plasteel", "catalogue-only ids pass through the reverse map")


# --- 11. spec 0010 (Основна капсула): the ONE capsule_levels table — mirrors tests/catalog.test.js one-for-one -----------------------
# The numbers are DATA, PROPOSED by godot/tests/run_capsule_balance.gd (OD-58/59) and approved by the owner at merge: these tests prove the
# SHAPE (continuous levels 0..5, known/reachable price ids that the backpack AND the stock both speak, monotone radius/defence, strictly
# growing price, buffs from the closed MainCapsule.BUFF_KEYS and none on body needs, one axis, no clone entries) and that the code holds
# no copy of the table's numbers. The JS side pins the same shape without Godot; this side pins the ids against the REAL data_bridge /
# Inventory / Session constants (the JS side can only mirror them).
const CAPSULE_TOP_KEYS := ["version", "status", "note", "metric", "levels", "raid"]
const CAPSULE_ROW_KEYS := ["level", "cost", "radius", "core_hp", "buffs"]
const CAPSULE_RAID_KEYS := ["decided", "immunity_ms", "take_percent", "warning_s", "by_level"]

func _total_units(cost: Dictionary) -> int:
	var t: int = 0
	for k in cost:
		t += int(cost[k])
	return t

func _t_capsule_levels_data() -> void:
	var cat: Dictionary = Catalog.load_json()
	var t: Dictionary = cat.get("capsule_levels", {})
	ok(not t.is_empty(), "REQ-0010-11: catalog.json carries the capsule_levels table")
	var keys: Array = t.keys()
	keys.sort()
	var want: Array = CAPSULE_TOP_KEYS.duplicate()
	want.sort()
	ok(keys == want, "REQ-0010-17/97: the table has no key outside the schema (a second axis / clone table has nowhere to hide): %s" % str(keys))
	ok(int(t.get("version", 0)) == 1 and ["proposed", "approved"].has(String(t.get("status", ""))), "capsule_levels: version 1, status proposed|approved (the agent's numbers until the owner approves)")
	ok(String(t.get("metric", "")) == "chebyshev", "REQ-0010-80: the zone metric is data, and only chebyshev is implemented")
	ok(MainCapsule.ZONE_METRICS.has(String(t.get("metric", ""))), "REQ-0010-80: the data's zone metric is one the code implements (MainCapsule.ZONE_METRICS) — else in_zone would be empty for everyone")
	var levels: Array = t.get("levels", [])
	ok(levels.size() == 6, "REQ-0010-11/91: levels 0..5 (OD-56) — %d rows" % levels.size())
	ok(levels.size() <= 10, "REQ-0010-82: invested keys hash lexicographically — numeric order holds up to level 9, so at most 10 rows until a RECORD_VERSION bump")
	var rowkeys_ok: bool = true
	var continuous: bool = true
	for i in levels.size():
		var rk: Array = (levels[i] as Dictionary).keys()
		rk.sort()
		var rw: Array = CAPSULE_ROW_KEYS.duplicate()
		rw.sort()
		rowkeys_ok = rowkeys_ok and rk == rw
		continuous = continuous and int((levels[i] as Dictionary).get("level", -1)) == i
	ok(rowkeys_ok, "capsule_levels: every row is exactly {level,cost,radius,core_hp,buffs}")
	ok(continuous, "capsule_levels: levels[i].level == i (the code indexes by position)")
	ok((levels[0].cost as Dictionary).is_empty() and (levels[0].buffs as Dictionary).is_empty(), "REQ-0010-12: level 0 costs nothing and gives no buff at all")
	# price ids: positive integers, spoken 1:1 by data_bridge AND the backpack (data.gd resource), reachable in the catalogue
	var obtainable: Dictionary = Catalog.reachability(cat).obtainable
	var price_ok: bool = true
	var why: String = ""
	for i in range(1, levels.size()):
		var cost: Dictionary = levels[i].cost
		if cost.is_empty():
			price_ok = false
			why = "level %d has no price" % i
		for id in cost:
			var n: float = float(cost[id])
			if n <= 0.0 or n != floorf(n):
				price_ok = false
				why = "level %d: %s is not a positive integer" % [i, id]
			if DataBridge.to_catalog(id) != StringName(str(id)) or not GameData.RES.has(str(id)):
				price_ok = false
				why = "level %d: %s is not an identity id of data_bridge/data.gd (backpack and stock would disagree)" % [i, id]
			if not obtainable.has(StringName(str(id))):
				price_ok = false
				why = "level %d: %s is not reachable from the raw roots" % [i, id]
	ok(price_ok, "REQ-0010-11/13: prices are positive integers over ids data_bridge maps 1:1, data.gd owns and the catalogue reaches %s" % why)
	# monotone radius / defence, strictly growing price, R0 covers the stash, top zone under n/4
	var mono: bool = true
	var grows: bool = true
	for i in levels.size():
		var row_i: Dictionary = levels[i]
		mono = mono and int(row_i.radius) > 0 and float(row_i.core_hp) > 0.0
		if i >= 1:
			mono = mono and int(row_i.radius) >= int(levels[i - 1].radius) and float(row_i.core_hp) >= float(levels[i - 1].core_hp)
		if i >= 2:
			grows = grows and _total_units(row_i.cost) > _total_units(levels[i - 1].cost)
	ok(mono, "REQ-0010-16/17: radius and core_hp (the ONE defence parameter) are positive and never shrink with the level")
	ok(grows, "capsule_levels: the total price strictly grows from level to level")
	ok(int(levels[0].radius) >= ceili(Inventory.STASH_REACH), "REQ-0010-05/12: the level-0 zone covers the storage reach (Inventory.STASH_REACH=%.1f)" % Inventory.STASH_REACH)
	ok(int(levels[levels.size() - 1].radius) <= SessionScript.MAP_N / 4, "the top zone stays under a quarter of the map side (n=%d)" % SessionScript.MAP_N)
	# buffs: closed vocabulary of multipliers, none on body needs, monotone per key
	var buffs_ok: bool = true
	var needs: RegEx = RegEx.create_from_string("(?i)hunger|cold|sleep|rest|thirst|food|need|temp|warm|health|hp")
	for row_b in levels:
		for k in row_b.buffs:
			buffs_ok = buffs_ok and MainCapsule.BUFF_KEYS.has(String(k)) and needs.search(String(k)) == null and float(row_b.buffs[k]) > 1.0
	for key in MainCapsule.BUFF_KEYS:
		var prev: float = 1.0
		for row_b in levels:
			var v: float = float((row_b.buffs as Dictionary).get(key, 1.0))
			buffs_ok = buffs_ok and v >= prev
			prev = v
	ok(buffs_ok, "REQ-0010-79: buffs are multipliers from the closed BUFF_KEYS, never a body need (hunger/cold/sleep), and never drop with the level")
	var blob: String = JSON.stringify(t.duplicate(true).merged({"note": ""}, true))
	var clones: RegEx = RegEx.create_from_string("(?i)clone|roster|genome|orbit|implant|axis|axes")
	ok(clones.search(blob) == null, "REQ-0010-17/97: no clone-roster, orbit or separate-axis entry anywhere in capsule_levels")
	# the raid block: decided numbers + a monotone raider ladder; non-delegated numbers are ABSENT (OD-58)
	var raid: Dictionary = t.get("raid", {})
	var rk2: Array = raid.keys()
	rk2.sort()
	var rw2: Array = CAPSULE_RAID_KEYS.duplicate()
	rw2.sort()
	ok(rk2 == rw2, "raid block: grace/min-gap/queue/frequency/rounding are absent until the owner decides (OD-58): %s" % str(rk2))
	ok(int(raid.get("immunity_ms", 0)) == 86400000 and int(raid.get("take_percent", 0)) == 50, "OD-24/58: immunity 86 400 000 ms and 50% are the owner's numbers")
	var decided: Array = (raid.get("decided", []) as Array).duplicate()
	decided.sort()
	ok(decided == ["immunity_ms", "take_percent"], "raid.decided names exactly the two owner-decided numbers")
	ok(float(raid.get("warning_s", 0.0)) > 0.0, "raid.warning_s is a positive interval")
	var by_level: Dictionary = raid.get("by_level", {})
	var bl_keys: Array = by_level.keys()
	ok(bl_keys == ["1", "2", "3", "4", "5"], "raid.by_level covers levels 1..5 (level 0 is never raided, OD-58)")
	var bl_ok: bool = true
	var prev_r: Dictionary = {"count": 0, "day_equiv": 0, "t_open_s": 0}
	for lvl in ["1", "2", "3", "4", "5"]:
		var rr: Dictionary = by_level.get(lvl, {})
		for k in ["count", "day_equiv", "t_open_s"]:
			bl_ok = bl_ok and float(rr.get(k, 0)) > 0.0 and float(rr.get(k, 0)) >= float(prev_r[k])
		prev_r = rr
	ok(bl_ok, "raid.by_level: count / day_equiv / t_open_s positive and never shrinking")
	ok(not cat.get("meta", {}).is_empty() and Catalog.validate_catalog(cat).is_empty(), "the extra top-level key does not break validate_catalog")

# The accessors read the table, and the code holds NO copy of its numbers (REQ-0010-11: «код не містить цих чисел»; REQ-0010-91).
func _t_capsule_levels_accessors() -> void:
	var cat: Dictionary = Catalog.load_json()
	var t: Dictionary = cat.get("capsule_levels", {})
	var levels: Array = t.get("levels", [])
	var sim: Variant = Sim.new()
	ok(MainCapsule.max_level(sim) == levels.size() - 1, "MainCapsule.max_level is the table size - 1 (no constant 5 in code)")
	var agree: bool = true
	for i in levels.size():
		agree = agree and MainCapsule.radius(sim, i) == int(levels[i].radius) and is_equal_approx(MainCapsule.core_hp(sim, i), float(levels[i].core_hp))
		agree = agree and _total_units(MainCapsule.row(sim, i).cost) == _total_units(levels[i].cost)
	ok(agree, "MainCapsule.radius / core_hp / row read the catalog table")
	ok(MainCapsule.radius(sim, -1) == 0 and MainCapsule.radius(sim, levels.size()) == 0 and MainCapsule.row(sim, levels.size()).is_empty(), "levels outside the table are empty, never an out-of-range read")
	# a replaced table (tests / content pack) wins over the catalog; a 7th row widens the range with NO code change
	var wide: Dictionary = t.duplicate(true)
	(wide.levels as Array).append({"level": 6, "cost": {"wood": 999}, "radius": 15, "core_hp": 9999, "buffs": {"gather_mult": 1.3}})
	sim.capsule_table = wide
	ok(MainCapsule.max_level(sim) == 6 and MainCapsule.radius(sim, 6) == 15 and MainCapsule.buffs(sim, 6).has("gather_mult"), "REQ-0010-91: adding a table row widens the range — data only")
	# the code does not copy the table: no core_hp / buff / price value of the table appears in capsule.gd outside comments
	var src: String = FileAccess.get_file_as_string("res://scripts/sim/capsule.gd")
	var code: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		code.append(line if hash_at < 0 else line.substr(0, hash_at))
	var code_text: String = "\n".join(code)
	var seen: Dictionary = {}
	for row_l in levels:
		seen[str(int(round(float(row_l.core_hp))))] = "core_hp"
		for id in row_l.cost:
			if int(row_l.cost[id]) >= 50:
				seen[str(int(row_l.cost[id]))] = "price"
		for k in row_l.buffs:
			seen[str(float(row_l.buffs[k]))] = "buff"
	var copies: Array = []
	for num in seen:
		var rx: RegEx = RegEx.create_from_string("(?<![0-9A-Za-z_.])%s(?![0-9A-Za-z_])" % String(num).replace(".", "\\."))
		if rx.search(code_text) != null:
			copies.append("%s=%s" % [seen[num], num])
	ok(copies.is_empty(), "REQ-0010-11: capsule.gd holds no copy of the table's core_hp / price / buff numbers %s" % str(copies))

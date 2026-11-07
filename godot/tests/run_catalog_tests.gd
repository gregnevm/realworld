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


# --- 11. spec 0010 (Основна капсула): the capsule_levels table, TWO axes — mirrors tests/catalog.test.js one-for-one ---------------------
# Some numbers are the OWNER's decisions (+10% per level, +50% at 5 — OD-98; x2 per level — OD-65/93; x16 at defence 5 — OD-103; ~50 m — OD-99;
# immunity 24 h and 50% — OD-24/107) and are pinned as such; the rest is PROPOSED by godot/tests/run_capsule_balance.gd (OD-107/59) and approved by
# the owner at merge. These tests prove the SHAPE and the owner's coefficients (continuous levels 0..5 on BOTH axes, the closed four-axis buff
# vocabulary in EVERY record, one static zone radius, known/reachable price ids that the backpack AND the stock both speak, prices that get
# rarer with the level, no clone entries) and that the code holds no copy of the table's numbers. The JS side pins the same shape without Godot;
# this side pins the ids against the REAL data_bridge / Inventory / Session constants (the JS side can only mirror them).
const CAPSULE_TOP_KEYS := ["version", "status", "note", "feasibility_note", "metric", "zone", "levels", "protection", "raid"]
const CAPSULE_ZONE_KEYS := ["radius_m", "cell_m", "radius_cells"]
const CAPSULE_LEVEL_KEYS := ["level", "cost", "buffs"]
const CAPSULE_PROT_TOP_KEYS := ["factor", "levels"]
const CAPSULE_PROT_KEYS := ["level", "cost", "core_hp"]
const CAPSULE_RAID_DECIDED := {"immunity_ms": 86400000, "take_percent": 50, "grace_ms": 259200000, "warn_min_ms": 600000, "warn_max_ms": 1800000, "cadence_min_ms": 259200000, "cadence_max_ms": 345600000}   # OD-24/107/66/88/86 verbatim
const CAPSULE_RAID_PROPOSED := ["take_round", "queue_max", "roll_spread", "wealth_ref_points", "count_max", "by_level"]                          # the bot's proposals (W3a)
const CAPSULE_BUFF_STEP := 0.1       # OD-98
const CAPSULE_RARITY := {"wood": 0, "stone": 1, "planks": 2, "scrap": 3, "components": 4}   # rank by the finite supply order (planks = processed wood)
const CAPSULE_BASIC_RAW := ["wood", "stone"]                                               # OD-75: level 1 is basic raw

func _total_units(cost: Dictionary) -> int:
	var t: int = 0
	for k in cost:
		t += int(cost[k])
	return t

func _sorted_keys(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k

func _sorted(a: Array) -> Array:
	var b: Array = a.duplicate()
	b.sort()
	return b

func _rarest(cost: Dictionary) -> int:
	var r: int = 0
	for id in cost:
		r = maxi(r, int(CAPSULE_RARITY.get(String(id), 99)))
	return r

# every price id is a positive integer over an id data_bridge maps 1:1, data.gd owns and the catalogue reaches ("" == fine, else why not)
func _price_problem(cost: Dictionary, obtainable: Dictionary) -> String:
	for id in cost:
		var n: float = float(cost[id])
		if n <= 0.0 or n != floorf(n):
			return "%s is not a positive integer" % id
		if DataBridge.to_catalog(id) != StringName(str(id)) or not GameData.RES.has(str(id)):
			return "%s is not an identity id of data_bridge/data.gd (backpack and stock would disagree)" % id
		if not obtainable.has(StringName(str(id))):
			return "%s is not reachable from the raw roots" % id
	return ""

func _t_capsule_levels_data() -> void:
	var cat: Dictionary = Catalog.load_json()
	var t: Dictionary = cat.get("capsule_levels", {})
	ok(not t.is_empty(), "REQ-0010-11: catalog.json carries the capsule_levels table")
	ok(_sorted_keys(t) == _sorted(CAPSULE_TOP_KEYS), "REQ-0010-17/97/99: the table has no key outside the schema (a third axis / clone table has nowhere to hide): %s" % str(_sorted_keys(t)))
	ok(int(t.get("version", 0)) == 2 and ["proposed", "approved"].has(String(t.get("status", ""))), "capsule_levels: version 2 (two axes + one static zone; REQ-0010-60), status proposed|approved")
	ok(String(t.get("metric", "")) == "chebyshev" and MainCapsule.ZONE_METRICS.has(String(t.get("metric", ""))),
		"REQ-0010-80: the zone metric is data, and the code implements it (MainCapsule.ZONE_METRICS) — else in_zone would be empty for everyone")
	ok(String(t.get("feasibility_note", "")).contains("НЕ ЗДІЙСНЕННО"), "the feasibility note says honestly that the owner's formula does not fit the finite map (not a map-fitted number)")
	var obtainable: Dictionary = Catalog.reachability(cat).obtainable
	# --- the capsule axis ---
	var levels: Array = t.get("levels", [])
	ok(levels.size() == 6, "REQ-0010-11/91: capsule levels 0..5 (OD-56) — %d rows" % levels.size())
	ok(levels.size() <= 10, "REQ-0010-82: ledger keys hash lexicographically — numeric order holds up to level 9, so at most 10 rows until a RECORD_VERSION bump")
	var rowkeys_ok: bool = true
	var continuous: bool = true
	for i in levels.size():
		rowkeys_ok = rowkeys_ok and _sorted_keys(levels[i]) == _sorted(CAPSULE_LEVEL_KEYS)
		continuous = continuous and int((levels[i] as Dictionary).get("level", -1)) == i
	ok(rowkeys_ok, "capsule_levels: every row is exactly {level,cost,buffs} — the radius is NOT a level row (REQ-0010-16), the defence is its own axis (REQ-0010-99)")
	ok(continuous, "capsule_levels: levels[i].level == i (the code indexes by position)")
	ok((levels[0].cost as Dictionary).is_empty(), "REQ-0010-12: level 0 costs nothing")
	# buffs: EXACTLY the four OD-73 axes in every record, 1 + 0.10*L (OD-98)
	var buffs_ok: bool = true
	var step_ok: bool = true
	for row_b in levels:
		buffs_ok = buffs_ok and _sorted_keys(row_b.buffs) == _sorted(MainCapsule.BUFF_KEYS)
		for k in row_b.buffs:
			step_ok = step_ok and absf(float(row_b.buffs[k]) - (1.0 + CAPSULE_BUFF_STEP * int(row_b.level))) < 1.0e-9
	ok(buffs_ok, "REQ-0010-105: every level record carries EXACTLY the four buff axes MainCapsule.BUFF_KEYS (no melee, no hunger — a fifth axis only by the owner)")
	ok(step_ok and absf(float((levels[5].buffs as Dictionary)["gather_mult"]) - 1.5) < 1.0e-9, "REQ-0010-106 (OD-98): buff = 1 + 0.10*L on every axis, +50% at level 5, 0% at level 0")
	ok(not (MainCapsule.BUFF_KEYS.has("melee_mult")), "REQ-0010-105/79(withdrawn): melee_mult is not an OD-73 axis")
	# prices
	var price_ok: bool = true
	var why: String = ""
	for i in range(1, levels.size()):
		var cost: Dictionary = levels[i].cost
		if cost.is_empty():
			price_ok = false
			why = "level %d has no price" % i
		var pp: String = _price_problem(cost, obtainable)
		if pp != "":
			price_ok = false
			why = "level %d: %s" % [i, pp]
	ok(price_ok, "REQ-0010-11/13: capsule prices are positive integers over ids data_bridge maps 1:1, data.gd owns and the catalogue reaches %s" % why)
	var grows: bool = true
	var ratio_ok: bool = true
	var rarer_ok: bool = true
	var prev_rank: int = 0
	for i in range(1, levels.size()):
		if i >= 2:
			grows = grows and _total_units(levels[i].cost) > _total_units(levels[i - 1].cost)
			var ratio: float = float(_total_units(levels[i].cost)) / float(_total_units(levels[i - 1].cost))
			ratio_ok = ratio_ok and ratio > 1.6 and ratio < 2.4
		var rk: int = _rarest(levels[i].cost)
		rarer_ok = rarer_ok and rk >= prev_rank
		prev_rank = rk
	ok(grows and ratio_ok, "REQ-0010-101 (OD-65/93): the capsule price strictly grows and costs ~x2 per level by total weight")
	var basic_ok: bool = true
	for id in levels[1].cost:
		basic_ok = basic_ok and CAPSULE_BASIC_RAW.has(String(id))
	ok(basic_ok and rarer_ok and _rarest(levels[5].cost) > _rarest(levels[1].cost),
		"REQ-0010-101 (OD-75): level 1 is basic raw, the rarest ingredient never gets more common with the level, level 5 is rarer than level 1")
	# --- the static zone ---
	var zone: Dictionary = t.get("zone", {})
	ok(_sorted_keys(zone) == _sorted(CAPSULE_ZONE_KEYS), "REQ-0010-16: the zone is {radius_m, cell_m, radius_cells} — ONE static radius")
	ok(float(zone.get("radius_m", 0.0)) == 50.0, "OD-99: ~50 m is the owner's number")
	var rc: int = int(zone.get("radius_cells", 0))
	ok(rc > 0 and rc == ceili(float(zone.get("radius_m", 0.0)) / float(zone.get("cell_m", 1.0))), "REQ-0010-16/Q-4: radius_cells = ceil(radius_m / cell_m) — one function of the (proposed) scale")
	ok(rc >= ceili(Inventory.STASH_REACH), "REQ-0010-05/12: the zone covers the storage reach (Inventory.STASH_REACH=%.1f)" % Inventory.STASH_REACH)
	ok(rc <= SessionScript.MAP_N / 4, "the zone stays under a quarter of the map side (n=%d)" % SessionScript.MAP_N)
	# --- the defence axis ---
	var prot: Dictionary = t.get("protection", {})
	ok(_sorted_keys(prot) == _sorted(CAPSULE_PROT_TOP_KEYS) and float(prot.get("factor", 0.0)) == 2.0,
		"REQ-0010-99/102: the defence axis is {factor, levels} and the x2-per-level coefficient is data (OD-65/103)")
	var plevels: Array = prot.get("levels", [])
	ok(plevels.size() == 6, "REQ-0010-99: defence levels 0..5 (OD-76) — %d rows" % plevels.size())
	var prot_ok: bool = true
	var hp_ok: bool = true
	var radius_free: bool = true
	var pprice_ok: bool = true
	for i in plevels.size():
		var rowp: Dictionary = plevels[i]
		prot_ok = prot_ok and _sorted_keys(rowp) == _sorted(CAPSULE_PROT_KEYS) and int(rowp.get("level", -1)) == i
		hp_ok = hp_ok and float(rowp.get("core_hp", 0.0)) > 0.0
		if i >= 1:
			hp_ok = hp_ok and absf(float(rowp.core_hp) / float(plevels[i - 1].core_hp) - float(prot.factor)) < 0.01
			pprice_ok = pprice_ok and not (rowp.cost as Dictionary).is_empty() and _price_problem(rowp.cost, obtainable) == ""
			if i >= 2:
				pprice_ok = pprice_ok and _total_units(rowp.cost) > _total_units(plevels[i - 1].cost)
		radius_free = radius_free and not rowp.has("radius") and not rowp.has("radius_cells")
	for row_l in levels:
		radius_free = radius_free and not (row_l as Dictionary).has("radius") and not (row_l as Dictionary).has("radius_cells")
	ok(prot_ok, "REQ-0010-99: every defence record is exactly {level,cost,core_hp}, levels[i].level == i")
	ok(hp_ok and absf(float(plevels[5].core_hp) / float(plevels[1].core_hp) - 16.0) < 0.05, "REQ-0010-102 (OD-103): core_hp > 0, ~x2 per level, core_hp(5)/core_hp(1) ~ 16")
	ok((plevels[0].cost as Dictionary).is_empty() and pprice_ok, "REQ-0010-100 (Q-5): defence 0 is free; the defence prices are positive integers over shared live ids and strictly grow")
	ok(radius_free, "REQ-0010-16 (OD-74/99): the radius belongs to NEITHER axis (static)")
	var blob: String = JSON.stringify(t.duplicate(true).merged({"note": "", "feasibility_note": ""}, true))
	var clones: RegEx = RegEx.create_from_string("(?i)clone|roster|genome|orbit|implant")
	ok(clones.search(blob) == null, "REQ-0010-17/97: no clone-roster, orbit or implant entry anywhere in capsule_levels")
	# --- the raid block: the owner's decided numbers verbatim + the bot's proposals, each named as such ---
	var raid: Dictionary = t.get("raid", {})
	var want_keys: Array = ["decided", "proposed"] + CAPSULE_RAID_DECIDED.keys() + CAPSULE_RAID_PROPOSED
	ok(_sorted_keys(raid) == _sorted(want_keys), "raid block: no key outside the schema (cadence window = OD-86 verbatim; no min-gap): %s" % str(_sorted_keys(raid)))
	var decided_ok: bool = true
	for k in CAPSULE_RAID_DECIDED:
		decided_ok = decided_ok and int(raid.get(k, -1)) == int(CAPSULE_RAID_DECIDED[k])
	ok(decided_ok, "OD-24/107/66/88: immunity 86 400 000 ms, 50%, grace 259 200 000 ms, warning 600 000..1 800 000 ms are the owner's numbers")
	ok(_sorted(raid.get("decided", []) as Array) == _sorted(CAPSULE_RAID_DECIDED.keys()) and _sorted(raid.get("proposed", []) as Array) == _sorted(CAPSULE_RAID_PROPOSED),
		"raid.decided / raid.proposed name exactly the owner-decided and the agent-proposed numbers")
	ok(["floor", "ceil", "round"].has(String(raid.get("take_round", ""))) and int(raid.get("queue_max", 0)) >= 1 and float(raid.get("roll_spread", 0.0)) > 0.0 and float(raid.get("roll_spread", 0.0)) < 1.0 \
		and float(raid.get("wealth_ref_points", 0.0)) > 0.0, "the proposed scalars are usable: rounding rule the code implements, a queue slot, a spread strictly inside (0,1), a positive reference wealth")
	var by: Dictionary = raid.get("by_level", {})
	var by_ok: bool = _sorted_keys(by) == ["1", "2", "3", "4", "5"]
	var prev_p: float = 0.0
	var prev_c: int = 0
	var prev_d: int = 0
	var power_ok: bool = true
	for lk in ["1", "2", "3", "4", "5"]:
		var row: Dictionary = by.get(lk, {})
		by_ok = by_ok and _sorted_keys(row) == ["count", "day_equiv"] and int(row.get("count", 0)) >= 1 and int(row.get("count", 0)) <= int(raid.get("count_max", 0)) and int(row.get("day_equiv", 0)) >= 1
		var rd: Dictionary = GameData.make_raider(0.0, 0.0, int(row.get("day_equiv", 1)))
		var power: float = float(int(row.get("count", 0))) * float(rd.dmg) * float(rd.maxhp)
		if prev_p > 0.0:
			power_ok = power_ok and absf(power / prev_p - 2.0) < 0.05 and int(row.get("count", 0)) >= prev_c and int(row.get("day_equiv", 0)) >= prev_d
		prev_p = power
		prev_c = int(row.get("count", 0))
		prev_d = int(row.get("day_equiv", 0))
	ok(by_ok, "REQ-0010-112: one raider row {count, day_equiv} per capsule level 1..5, within 1..count_max")
	ok(power_ok, "OD-65: the raider power (count x dmg x hp of the REAL GameData.make_raider) is ~x2 per level and never shrinks")
	ok(not cat.get("meta", {}).is_empty() and Catalog.validate_catalog(cat).is_empty(), "the extra top-level key does not break validate_catalog")

# The accessors read the table, and the code holds NO copy of its numbers (REQ-0010-11: «код не містить цих чисел»; REQ-0010-91/99).
func _t_capsule_levels_accessors() -> void:
	var cat: Dictionary = Catalog.load_json()
	var t: Dictionary = cat.get("capsule_levels", {})
	var levels: Array = t.get("levels", [])
	var plevels: Array = (t.get("protection", {}) as Dictionary).get("levels", [])
	var sim: Variant = Sim.new()
	ok(MainCapsule.max_level(sim) == levels.size() - 1 and MainCapsule.max_protection(sim) == plevels.size() - 1, "MainCapsule.max_level / max_protection are the table sizes - 1 (no constant 5 in code)")
	var agree: bool = true
	for i in levels.size():
		agree = agree and _total_units(MainCapsule.row(sim, i).cost) == _total_units(levels[i].cost)
		agree = agree and _total_units(MainCapsule.protection_row(sim, i).cost) == _total_units(plevels[i].cost)
		agree = agree and is_equal_approx(MainCapsule.core_hp(sim, i), float(plevels[i].core_hp)) and is_equal_approx(MainCapsule.breach_cost(sim, i), float(plevels[i].core_hp))
		agree = agree and MainCapsule.buffs(sim, i).size() == (0 if i == 0 else MainCapsule.BUFF_KEYS.size())
	ok(agree, "MainCapsule.row / protection_row / core_hp / breach_cost / buffs read the catalog table (buffs(0) is empty, REQ-0010-12)")
	ok(MainCapsule.zone_radius(sim) == int((t.zone as Dictionary).radius_cells), "MainCapsule.zone_radius reads the ONE static radius of the data")
	ok(MainCapsule.core_hp(sim, -1) == 0.0 and MainCapsule.core_hp(sim, plevels.size()) == 0.0 and MainCapsule.row(sim, levels.size()).is_empty()
		and MainCapsule.protection_row(sim, plevels.size()).is_empty(), "levels outside a table are empty, never an out-of-range read")
	# a replaced table (tests / content pack) wins over the catalog; a 7th row on EITHER axis widens the range with NO code change
	var wide: Dictionary = t.duplicate(true)
	(wide.levels as Array).append({"level": 6, "cost": {"wood": 999}, "buffs": {"gather_mult": 1.6, "craft_mult": 1.6, "need_recovery_mult": 1.6, "research_mult": 1.6}})
	(wide.protection.levels as Array).append({"level": 6, "cost": {"wood": 999}, "core_hp": 99999})
	sim.capsule_table = wide
	ok(MainCapsule.max_level(sim) == 7 - 1 and MainCapsule.max_protection(sim) == 6 and MainCapsule.buffs(sim, 6).has("gather_mult") and MainCapsule.core_hp(sim, 6) == 99999.0,
		"REQ-0010-91/99: adding a table row widens either range — data only")
	# the code does not copy the table: no core_hp / buff / price value of the table appears in capsule.gd outside comments
	var src: String = FileAccess.get_file_as_string("res://scripts/sim/capsule.gd")
	var code: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		code.append(line if hash_at < 0 else line.substr(0, hash_at))
	var code_text: String = "\n".join(code)
	var seen: Dictionary = {}
	for row_l in plevels:
		seen[str(int(round(float(row_l.core_hp))))] = "core_hp"
	for row_l in levels:
		for id in row_l.cost:
			if int(row_l.cost[id]) >= 50:
				seen[str(int(row_l.cost[id]))] = "price"
		for k in row_l.buffs:
			if float(row_l.buffs[k]) != 1.0:   # 1.0 is the NEUTRAL multiplier (level 0), not a table number
				seen[str(float(row_l.buffs[k]))] = "buff"
	var copies: Array = []
	for num in seen:
		var rx: RegEx = RegEx.create_from_string("(?<![0-9A-Za-z_.])%s(?![0-9A-Za-z_])" % String(num).replace(".", "\\."))
		if rx.search(code_text) != null:
			copies.append("%s=%s" % [seen[num], num])
	ok(copies.is_empty(), "REQ-0010-11: capsule.gd holds no copy of the table's core_hp / price / buff numbers %s" % str(copies))

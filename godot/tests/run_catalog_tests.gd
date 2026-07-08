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
extends SceneTree

const Defs = preload("res://scripts/kernel/defs.gd")
const Things = preload("res://scripts/kernel/things.gd")
const Production = preload("res://scripts/kernel/production.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")

var passed := 0
var failed := 0

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
	print("\n== RESULT: %d passed, %d failed ==" % [passed, failed])
	quit(1 if failed > 0 else 0)

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

func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [pass] ", name)
	else:
		failed += 1
		printerr("  [FAIL] ", name)
		print("  [FAIL] ", name)

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

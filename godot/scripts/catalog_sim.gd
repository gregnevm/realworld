# RealWorld — catalog_sim.gd : the WRITE-SIDE — a catalogue-backed play model on the shipped kernel.
#
# The read pipeline (ui/catalog_view.gd) surfaces the tree; this is the half that USES it. It holds the
# mutable game state (stock, research, placed buildings) and exposes the three verbs that operate the
# deep catalogue — RESEARCH a project, BUILD a station, CRAFT a recipe — each running through the real
# kernel: Production.ResearchState gates + advances research, Production.ProductionSystem + CompWorkbench
# + Bill turn recipes into stock at a placed station. It is scene-free and DETERMINISTIC (one seeded rng),
# so a full research → build → craft chain runs headless in the tests. It imports the kernel only, never
# ui (R1). The live sim keeps data.gd; this is the forward-engine model the catalogue was authored for.
extends RefCounted

const Catalog = preload("res://scripts/kernel/catalog.gd")
const Production = preload("res://scripts/kernel/production.gd")
const Things = preload("res://scripts/kernel/things.gd")
const Defs = preload("res://scripts/kernel/defs.gd")
const CatalogSim = preload("res://scripts/catalog_sim.gd")   # self-alias for the shared() static

# A process-shared instance so the HUD (read: catalog_view slice) and the router (write: catalog_verbs)
# operate the SAME forward-engine model — browse an action, click it, watch the state move. Built once
# with a neolithic starter stock. The live data.gd sim is untouched; this is a parallel catalogue model.
static var _shared: Variant = null
static func shared(p_db = null):
	if _shared == null:
		_shared = CatalogSim.new(p_db)
		_shared._grant_starter()
	return _shared

func _grant_starter() -> void:
	for pair in [["wood", 120], ["stone", 80], ["clay", 40], ["sand", 30], ["coal", 40],
			["iron_ore", 40], ["copper_ore", 30], ["plant_fiber", 30], ["herbal", 20]]:
		grant(pair[0], int(pair[1]))

var db: Defs.DefDatabase            # the catalogue
var stock: Dictionary = {}          # res id (String) -> amount
var research: Production.ResearchState
var things: Array = []              # placed building Things (stations carry a CompWorkbench)
var spawn: Array = []               # crafted Things (meals) drained by a host; bulk output goes to stock
var maker_level: float = 4.0        # competence stamped on crafted output quality
var _prod: Production.ProductionSystem
var _rng: RandomNumberGenerator

func _init(p_db = null, p_seed: int = 0) -> void:
	db = p_db if p_db != null else Catalog.build_db()
	research = Production.ResearchState.new(db)
	_prod = Production.ProductionSystem.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = p_seed

# ---- resources -----------------------------------------------------------------------------------
func grant(res, amt: int) -> void:
	var k := str(res)
	stock[k] = int(stock.get(k, 0)) + amt

func amount(res) -> int:
	return int(stock.get(str(res), 0))

func _afford(cost: Dictionary) -> bool:
	for k in cost:
		if int(stock.get(str(k), 0)) < int(cost[k]):
			return false
	return true

func _pay(cost: Dictionary) -> void:
	for k in cost:
		stock[str(k)] = int(stock.get(str(k), 0)) - int(cost[k])

func _gate(ref) -> bool:
	var r := str(ref)
	return r == "" or research.is_unlocked(StringName(r))

# ---- research ------------------------------------------------------------------------------------
# Begin a project (fails if unknown, already unlocked, or its prereqs are unmet). tick() then advances it.
func start_research(id) -> bool:
	return research.try_start(StringName(str(id)))

func researched(id) -> bool:
	return research.is_unlocked(StringName(str(id)))

# ---- build ---------------------------------------------------------------------------------------
func _building(id):
	var b: Variant = db.get_def(StringName(str(id)))
	return b if b is Catalog.BuildingDef else null

# Can the player place this building right now (research unlocked + cost affordable)?
func can_build(id) -> bool:
	var b: Variant = _building(id)
	if b == null:
		return false
	return _gate(b.research()) and _afford(b.cost())

# Place a building. Pays its cost; a station building gains a CompWorkbench so recipes can queue on it.
# Returns {ok, reason?, id?}.
func build(id) -> Dictionary:
	var b: Variant = _building(id)
	if b == null:
		return {"ok": false, "reason": "unknown"}
	if not _gate(b.research()):
		return {"ok": false, "reason": "locked"}
	if not _afford(b.cost()):
		return {"ok": false, "reason": "cost"}
	_pay(b.cost())
	var def := Defs.Def.new(&"building", b.id, {"max_hp": b.hp()})
	var t := Things.Thing.new(def)
	t.flags["building"] = b.id
	if b.is_station():
		t.add_comp(Production.CompWorkbench.new({"maker_level": maker_level}))
	things.append(t)
	return {"ok": true, "id": b.id}

func has_building(id) -> bool:
	for t in things:
		if StringName(str(t.flags.get("building", ""))) == StringName(str(id)):
			return true
	return false

# ---- craft ---------------------------------------------------------------------------------------
# The placed station Thing a recipe runs at (matches recipe.station + carries a workbench), or null.
func _station_for(recipe_id):
	var rc: Variant = db.get_def(StringName(str(recipe_id)))
	if rc == null:
		return null
	var st := StringName(str(rc.data.get("station", "")))
	for t in things:
		if StringName(str(t.flags.get("building", ""))) == st and t.get_comp(Production.CompWorkbench) != null:
			return t
	return null

# Queue a production order for a recipe on its station. mode &"count" makes `target`, &"until" holds
# `target` in stock. Fails if no matching station is placed. tick() then works the bill.
func queue_craft(recipe_id, mode: StringName = &"count", target: int = 1) -> Dictionary:
	var t: Variant = _station_for(recipe_id)
	if t == null:
		return {"ok": false, "reason": "no station"}
	var wb: Production.CompWorkbench = t.get_comp(Production.CompWorkbench)
	wb.add_bill(Production.Bill.new(StringName(str(recipe_id)), mode, target))
	return {"ok": true}

# ---- tick ----------------------------------------------------------------------------------------
func world() -> Dictionary:
	return {"db": db, "stock": stock, "things": things, "research": research, "spawn": spawn, "rng": _rng}

# Advance the model by `dday` game-days: burn research points into the active project, then let the
# ProductionSystem work every station's bills (consuming inputs, yielding output to stock).
func tick(dday: float) -> void:
	if research.active != &"":
		research.advance(dday)
	_prod.system_tick(world(), {"dday": dday})
	_sweep_destroyed()

# Destroyed Things (rotten meals, wrecked stations) must LEAVE the arrays: every comp holds a strong
# back-reference to its Thing and RefCounted cannot collect the cycle (AGENTS.md gotcha), so pruning
# goes through Thing.detach(). Without this the arrays only ever grow for the life of the process.
func _sweep_destroyed() -> void:
	for k in range(things.size() - 1, -1, -1):
		if things[k].destroyed:
			things[k].detach()
			things.remove_at(k)
	for k in range(spawn.size() - 1, -1, -1):
		if spawn[k].destroyed:
			spawn[k].detach()
			spawn.remove_at(k)

# Break every Thing<->Comp cycle this model owns. Call when a host drops the model; the process-shared
# instance is released via dispose_shared() (test suites call it so the exit leak check stays clean).
func dispose() -> void:
	for t in things:
		t.detach()
	things.clear()
	for t in spawn:
		t.detach()
	spawn.clear()

static func dispose_shared() -> void:
	if _shared != null:
		_shared.dispose()
		_shared = null

# The set of placed station building ids (a recipe is craftable only where its station stands).
func placed_stations() -> Dictionary:
	var out: Dictionary = {}
	for t in things:
		if t.get_comp(Production.CompWorkbench) != null:
			out[StringName(str(t.flags.get("building", "")))] = true
	return out

# ---- view binding (feeds ui/catalog_view.gd — the read pipeline) --------------------------------
func view_state() -> Dictionary:
	return {"unlocked": research.unlocked, "stock": stock, "stations": placed_stations()}

# RealWorld — kernel/production.gd : production & technology (Batch 3), on the Batch 1/2 spine.
#
# RimWorld analogue: RecipeDef + Bill/BillStack + WorkGiver_DoBill, ResearchProjectDef + ResearchManager,
# food-poisoning from cook quality, QualityCategory feeding stats, and Storage zones + haul priority.
# This batch turns the raw substrate (ctx from Batch 1, power from Batch 2) into the loop that MAKES
# things: recipes consumed against a workbench's bill queue, a research tree gating advanced recipes,
# cooking with a poisoning risk that competence buys down, crafted output stamped with quality, and
# priority stockpile zones that steer hauling. Like every kernel module it is pure Def/Comp/Stat/System
# grammar over a plain `world` dict; it never edits sim.gd or main.gd.
#
# --- What it reads / writes on `world` and `ctx` (the UX/host binding surface) -----------------------
#   ctx.dday                        elapsed game-days this tick (advances bill work + research).
#   world.stock : {res:StringName -> amt:int}   the shared resource pool recipes draw from / yield into.
#   world.db    : Defs.DefDatabase              recipe/research defs are looked up here.
#   world.research : ResearchState              unlocked-project set; recipes gate on it.
#   world.zones : Array[StockZone]              stockpile zones the zone-hauler chooses among.
#   world.spawn : Array[Things.Thing]           (optional) ProductionSystem appends spawned output Things
#                                               here when a recipe yields a Thing (a meal) rather than a
#                                               bulk resource. The host drains this list. For a thing output
#                                               the system ALSO bumps world.stock[out_id] by the count as a
#                                               logical tally so 'until'-mode bills can measure how many
#                                               exist and stop at target (a host draining a meal must decrement
#                                               that tally to keep it honest).
#   world.rng   : RandomNumberGenerator         (optional) seed the system uses to roll each crafted output
#                                               Thing's quality at creation; if absent a fixed-seed rng is
#                                               installed so quality is still rolled deterministically.
# A workbench is a Things.Thing carrying a CompWorkbench (its bill list). ProductionSystem scans
# world.things for workbenches exactly like PowerNetSystem scans for power comps.
#
# --- Determinism ------------------------------------------------------------------------------------
# The only stochastic paths are the quality roll (Things.CompQuality.post_make, seeded already) and the
# food-poisoning roll (CookWorker.roll_poison takes a seeded rng). No global randf(), no time seeds.
extends RefCounted

const Systems = preload("res://scripts/kernel/systems.gd")
const Things = preload("res://scripts/kernel/things.gd")
const Stats = preload("res://scripts/kernel/stats.gd")
const Defs = preload("res://scripts/kernel/defs.gd")

# ============================================================================================
# 1. RECIPES & BILLS (spec 0003 #9)
# ============================================================================================
#
# A recipe is a data-only Def (def_type=&"recipe"). Its payload:
#   inputs   : {res:StringName -> amt:int}   consumed from world.stock on completion.
#   output   : {id:StringName, count:int, thing?:bool, comps?:Array}
#              a bulk resource added to world.stock, OR (thing==true) a spawned Things.Thing.
#   work     : float                         game-days of work the bill accumulates before it completes.
#   requires_research : StringName (optional) project id that must be unlocked to run this recipe.
# Behaviour lives in ProductionSystem + the can_make() helper, never on the Def (kernel rule).

# A recipe Def with a self-validating payload (fails loudly at load, like every other Def).
class RecipeDef extends Defs.Def:
	func _init(p_id: StringName, p_data: Dictionary = {}) -> void:
		super(&"recipe", p_id, p_data)

	func inputs() -> Dictionary:
		return data.get("inputs", {})

	func output() -> Dictionary:
		return data.get("output", {})

	func work_days() -> float:
		return float(data.get("work", 1.0))

	func requires_research() -> StringName:
		return StringName(str(data.get("requires_research", "")))

	func validate(_db) -> String:
		if work_days() <= 0.0:
			return "recipe work must be > 0"
		if output().is_empty():
			return "recipe has no output"
		return ""

# A single production order sitting on a workbench. Two modes:
#   'count' — make `target` items then remove itself (done counts completions; finished at done>=target).
#   'until' — keep stock of output.id at `target`; produces only while stock < target, never removes itself.
# `stalled` latches true whenever the last attempt lacked inputs (drives a HUD warning); cleared on progress.
class Bill extends RefCounted:
	var recipe_id: StringName
	var mode: StringName = &"count"     # &"count" | &"until"
	var target: int = 1
	var done: int = 0                   # completions so far (count mode)
	var progress: float = 0.0           # game-days of work accumulated toward the current unit
	var stalled: bool = false
	var suspended: bool = false         # player pause; a suspended bill is skipped but not removed

	func _init(p_recipe: StringName, p_mode: StringName = &"count", p_target: int = 1) -> void:
		recipe_id = p_recipe
		mode = p_mode
		target = p_target

	# Is this bill still asking for work, given the current output stock (for 'until' mode)?
	func wants(out_stock: int) -> bool:
		if suspended:
			return false
		if mode == &"until":
			return out_stock < target
		return done < target

	# In 'count' mode a completed bill is finished and gets swept from the list.
	func finished() -> bool:
		return mode == &"count" and done >= target

	func inspect() -> String:
		var head := "%s ×%d" % [str(recipe_id), target] if mode == &"count" else "%s до %d" % [str(recipe_id), target]
		if suspended:
			return "%s (пауза)" % head
		if stalled:
			return "%s (бракує ресурсів)" % head
		return "%s [%d/%d]" % [head, done, target] if mode == &"count" else head

# The workbench comp: a Thing that owns a queue of Bills. ProductionSystem finds benches by this comp,
# exactly as PowerNetSystem finds generators by CompPowerSource. A bench also carries a `maker_level`
# (its operator's competence) used to stamp quality + drive cook poisoning. props: {maker_level}.
class CompWorkbench extends Things.ThingComp:
	var bills: Array = []               # Array[Bill]

	func maker_level() -> float:
		return float(props.get("maker_level", 0.0))

	func add_bill(b: Bill) -> void:
		bills.append(b)

	func inspect() -> String:
		if bills.is_empty():
			return "верстат: без завдань"
		var lines := ["верстат:"]
		for b in bills:
			lines.append("  • %s" % b.inspect())
		return "\n".join(lines)

# --- ProductionSystem : the bill solver -------------------------------------------------------------
#
# Priority 20: ticks AFTER Batch-1 environment (10/11/12) and Batch-2 power (15) so a bench that needs
# power / a fresh ctx already has it. Each tick, for every workbench Thing, for every active bill:
#   1. skip suspended / satisfied ('until' at target) / finished ('count') bills.
#   2. gate on research via can_make(); a gated-but-locked recipe stalls without consuming.
#   3. require inputs present in world.stock; missing -> stall, produce nothing.
#   4. advance progress by ctx.dday; on reaching recipe.work, consume inputs and yield output
#      (bulk -> world.stock; thing -> world.spawn AND a world.stock tally), bump done / hold 'until',
#      reset progress.
# Only ONE unit completes per bill per tick even if dday is large — keeps stock accounting legible and
# deterministic; a bigger dday just fills progress and the surplus carries to next tick.
class ProductionSystem extends Systems.SimSystem:
	func _init() -> void:
		system_id = &"production"
		priority = 20

	func _things(world) -> Array:
		if world != null and typeof(world) == TYPE_DICTIONARY:
			return world.get("things", [])
		return []

	func system_tick(world, ctx: Dictionary) -> void:
		if typeof(world) != TYPE_DICTIONARY:
			return
		var db = world.get("db", null)
		var stock: Dictionary = world.get("stock", {})
		if not world.has("stock"):
			world["stock"] = stock
		var research = world.get("research", null)
		var dday: float = float(ctx.get("dday", 0.0))

		for t in _things(world):
			if t == null or t.destroyed:
				continue
			var wb = t.get_comp(CompWorkbench)
			if wb == null:
				continue
			var maker_level: float = wb.maker_level()
			var survivors: Array = []
			for b in wb.bills:
				_tick_bill(b, db, research, stock, world, dday, maker_level, ctx)
				if not b.finished():
					survivors.append(b)
			wb.bills = survivors

	# Advance a single bill one tick. Mutates stock/world on completion.
	func _tick_bill(b: Bill, db, research, stock: Dictionary, world, dday: float, maker_level: float, ctx: Dictionary) -> void:
		var recipe = db.get_def(b.recipe_id) if db != null else null
		if recipe == null:
			b.stalled = true
			return
		var out: Dictionary = recipe.output()
		var out_id: StringName = StringName(str(out.get("id", "")))
		var out_stock: int = int(stock.get(out_id, 0))
		if not b.wants(out_stock):
			return
		# research gate
		if not Production.can_make(recipe, research):
			b.stalled = true
			return
		# inputs present?
		if not _has_inputs(recipe.inputs(), stock):
			b.stalled = true
			return
		b.stalled = false
		b.progress += dday
		if b.progress + 1e-9 < recipe.work_days():
			return
		# --- completion ---------------------------------------------------------------------------
		b.progress -= recipe.work_days()
		if b.progress < 0.0:
			b.progress = 0.0
		_consume(recipe.inputs(), stock)
		_yield(recipe, out, out_id, stock, world, maker_level, ctx)
		if b.mode == &"count":
			b.done += 1

	func _has_inputs(inputs: Dictionary, stock: Dictionary) -> bool:
		for res in inputs:
			if int(stock.get(res, 0)) < int(inputs[res]):
				return false
		return true

	func _consume(inputs: Dictionary, stock: Dictionary) -> void:
		for res in inputs:
			stock[res] = int(stock.get(res, 0)) - int(inputs[res])

	func _yield(recipe, out: Dictionary, out_id: StringName, stock: Dictionary, world, maker_level: float, _ctx: Dictionary) -> void:
		var count: int = int(out.get("count", 1))
		if bool(out.get("thing", false)):
			# spawn count Things, each carrying the requested comps + a quality stamp from the maker.
			var spawn: Array = world.get("spawn", [])
			if not world.has("spawn"):
				world["spawn"] = spawn
			var rng = _world_rng(world)
			for i in count:
				var thing = _make_output_thing(recipe, out, out_id, maker_level)
				thing.post_make(rng)   # roll quality deterministically at creation (documented contract)
				spawn.append(thing)
			# Also tally spawned things into world.stock as a logical count so 'until'-mode bills whose
			# output is a Thing can see how many exist and stop at target (bulk 'else' branch below does the
			# same for resources). Without this, out_stock stays 0 forever and 'until' overproduces.
			stock[out_id] = int(stock.get(out_id, 0)) + count
		else:
			stock[out_id] = int(stock.get(out_id, 0)) + count

	# The seeded rng used to roll crafted-output quality at creation. Prefers the host-provided world.rng
	# (so a save/replay reproduces exactly); falls back to a fixed-seed rng so the contract still holds —
	# quality is ALWAYS rolled here, never left at CompQuality's default tier — even for a host that omits
	# world.rng. Determinism preserved: no time seed, no global randf().
	func _world_rng(world) -> RandomNumberGenerator:
		var rng = world.get("rng", null)
		if rng is RandomNumberGenerator:
			return rng
		var fallback := RandomNumberGenerator.new()
		fallback.seed = 0
		world["rng"] = fallback
		return fallback

	# Build one output Thing: a fresh Thing tagged with the output id, carrying any comps the recipe
	# names (e.g. a meal wants CompRottable), always stamped with CompQuality(maker_level). The caller
	# (_yield) then post_makes it with the world rng so its quality tier is rolled deterministically at
	# creation — see _world_rng.
	func _make_output_thing(recipe, out: Dictionary, out_id: StringName, maker_level: float):
		var def = Defs.Def.new(&"item", out_id, {"max_hp": float(out.get("max_hp", 60.0))})
		var thing = Things.Thing.new(def)
		thing.flags["res"] = out_id
		# recipe-declared comps: a list of {cls, props} the maker attaches (rottable meals etc.).
		for spec in out.get("comps", []):
			var cls = spec.get("cls", null)
			if cls != null:
				thing.add_comp(cls.new(spec.get("props", {})))
		# always quality-stamped from the bench operator's competence.
		thing.add_comp(Things.CompQuality.new({"maker_level": maker_level}))
		return thing

# ============================================================================================
# 2. RESEARCH TREE (spec 0003 #11)
# ============================================================================================
#
# A research project is a data-only Def (def_type=&"research"). Payload:
#   cost    : float          research-points (game-days of work) to complete.
#   prereqs : [StringName]   projects that must already be unlocked before this one can start.
# ResearchState holds the unlocked set + one active project's accumulated progress. try_start() refuses a
# project whose prereqs are unmet or that is already unlocked; advance(dday) burns points and, on reaching
# cost, moves the project into the unlocked set. can_make() (below) is the single gate every recipe/build
# consults. Deterministic: no rng anywhere in research.

class ResearchDef extends Defs.Def:
	func _init(p_id: StringName, p_data: Dictionary = {}) -> void:
		super(&"research", p_id, p_data)

	func cost() -> float:
		return float(data.get("cost", 1.0))

	func prereqs() -> Array:
		return data.get("prereqs", [])

	func validate(_db) -> String:
		return "research cost must be > 0" if cost() <= 0.0 else ""

class ResearchState extends RefCounted:
	var db                              # Defs.DefDatabase (for prereq/cost lookup)
	var unlocked: Dictionary = {}       # StringName -> true (set semantics)
	var active: StringName = &""
	var progress: float = 0.0           # points into the active project

	func _init(p_db = null) -> void:
		db = p_db

	func is_unlocked(id: StringName) -> bool:
		return unlocked.has(id)

	# Every prereq of `id` already unlocked?
	func prereqs_met(id: StringName) -> bool:
		var d = db.get_def(id) if db != null else null
		if d == null:
			return false
		for p in d.prereqs():
			if not is_unlocked(StringName(str(p))):
				return false
		return true

	# Can we begin researching `id`? Not already known, exists, and prereqs met.
	func can_start(id: StringName) -> bool:
		if is_unlocked(id) or (db != null and db.get_def(id) == null):
			return false
		return prereqs_met(id)

	# Make `id` the active project (resets progress). Returns false if it cannot be started.
	func try_start(id: StringName) -> bool:
		if not can_start(id):
			return false
		active = id
		progress = 0.0
		return true

	# Burn `dday` points into the active project; unlocks it when progress reaches its cost.
	# Returns true on the tick it unlocks (so a host can fire a "research done" toast).
	func advance(dday: float) -> bool:
		if active == &"":
			return false
		var d = db.get_def(active) if db != null else null
		if d == null:
			return false
		progress += maxf(0.0, dday)
		if progress + 1e-9 >= d.cost():
			unlocked[active] = true
			active = &""
			progress = 0.0
			return true
		return false

	# Directly grant a project (debug / quest reward / save-load). Bypasses prereqs by design.
	func unlock(id: StringName) -> void:
		unlocked[id] = true

	func inspect() -> String:
		if active == &"":
			return "дослідження: —"
		var d = db.get_def(active) if db != null else null
		var cost: float = d.cost() if d != null else 1.0
		return "дослідження: %s %d%%" % [str(active), int(100.0 * clampf(progress / maxf(0.01, cost), 0.0, 1.0))]

# The single gate every recipe/build consults: can this recipe run given the research state? A recipe
# with no requires_research is always allowed; one that names a project runs only once it's unlocked. A
# null research state means "research not modelled here" -> ungated recipes still run, gated ones don't.
static func can_make(recipe, research) -> bool:
	var req: StringName = recipe.requires_research() if recipe != null else &""
	if req == &"":
		return true
	if research == null:
		return false
	return research.is_unlocked(req)

# ============================================================================================
# 3. COOKING & FOOD POISONING (spec 0003 #12)
# ============================================================================================
#
# Cooking is just a recipe whose output is a meal Thing carrying Things.CompRottable (freshness) — that
# reuse is the point, no bespoke meal machinery. The one new rule is FOOD POISONING risk, and it is
# expressed through the stat pipeline: CookWorker builds a StatWorker whose base is the raw poison chance
# and folds in a StatPart that DROPS the chance as cook competence rises. Eating raw or rotten food is
# strictly riskier than a well-cooked fresh meal. roll_poison() takes a seeded rng (determinism).

# Baseline poison chance for a properly cooked meal at cook_level 0 (before the competence discount).
const COOK_POISON_BASE := 0.06
# Extra multiplier on the poison chance for eating RAW (uncooked) food — raw is always riskier.
const RAW_POISON_MULT := 8.0
# Per-level competence discount: each cook level multiplies remaining chance by (1 - this), compounding.
const COOK_SKILL_DISCOUNT := 0.12

# A StatPart that lowers poison chance as cook_level rises: mult = (1 - discount)^level, so a level-0
# cook keeps the full base and a skilled cook drives it toward zero. Reads ctx.cook_level.
class StatPart_CookSkill extends Stats.StatPart:
	func transform(val: float, ctx: Dictionary) -> float:
		var lvl: float = maxf(0.0, float(ctx.get("cook_level", 0.0)))
		return val * pow(1.0 - COOK_SKILL_DISCOUNT, lvl)

	func explain(ctx: Dictionary) -> String:
		var lvl: float = maxf(0.0, float(ctx.get("cook_level", 0.0)))
		return "×кухар %.2f" % pow(1.0 - COOK_SKILL_DISCOUNT, lvl)

# The cook-competence authority: computes poison chance through the stat pipeline and rolls it.
class CookWorker extends RefCounted:
	# Poison chance for eating `raw`/rotten food at a given cook competence, folded through the stat
	# pipeline (base × raw-penalty × cook-skill discount), clamped to a sane [0,1].
	static func poison_chance(cook_level: float, raw: bool = false, rotten: bool = false) -> float:
		var base: float = COOK_POISON_BASE
		if raw:
			base *= RAW_POISON_MULT
		if rotten:
			base *= RAW_POISON_MULT
		var worker = Stats.StatWorker.new(&"food_poison_chance", base, [StatPart_CookSkill.new()])
		return clampf(worker.value({"cook_level": cook_level}), 0.0, 1.0)

	# Roll the poisoning outcome with a seeded rng. True == the eater is poisoned.
	static func roll_poison(cook_level: float, rng: RandomNumberGenerator, raw: bool = false, rotten: bool = false) -> bool:
		return rng.randf() < poison_chance(cook_level, raw, rotten)

	# Hunger restored by eating a food item. A cooked meal nourishes more than the raw ingredient — the
	# reason to cook at all. `nutrition` is the food's base value; cooking applies a bonus multiplier.
	static func hunger_value(nutrition: float, cooked: bool) -> float:
		return nutrition * (1.6 if cooked else 1.0)

# ============================================================================================
# 4. QUALITY WIRING (spec 0003 #10 — proven end to end here)
# ============================================================================================
#
# ProductionSystem already stamps every crafted output Thing with Things.CompQuality(maker_level) and
# post_makes it. This helper closes the loop for a caller: given a crafted Thing, build the ctx a stat
# query needs (quality_mult from the item's own CompQuality) so any Stats.StatWorker carrying a
# StatPart_Quality scales with the rolled tier. Higher quality -> higher stat, deterministically per seed.
class QualityWiring extends RefCounted:
	# The multiplier a crafted Thing contributes to its stats (1.0 if it has no quality comp).
	static func quality_mult(thing) -> float:
		var q = thing.get_comp(Things.CompQuality)
		return q.mult() if q != null else 1.0

	# Build the stat-eval ctx for an item (folds its quality into ctx.quality_mult).
	static func item_ctx(thing, extra: Dictionary = {}) -> Dictionary:
		var c: Dictionary = extra.duplicate()
		c["quality_mult"] = quality_mult(thing)
		return c

# ============================================================================================
# 5. STOCKPILE ZONES + PRIORITY HAULING (spec 0003 D7 — stockpiles)
# ============================================================================================
#
# RimWorld analogue: Zone_Stockpile + StorageSettings (filter + priority) + WorkGiver_HaulToCell. A
# StockZone is a rectangle with a resource filter and a priority. A hauler carrying a resource picks the
# HIGHEST-priority zone that ACCEPTS that resource; a zone whose filter excludes the resource is refused
# outright. Empty filter == accept everything (a general dump). This does not edit agents.gd; it adds a
# new WorkGiver_HaulZone alongside the existing WorkGiver_Haul, reading world.zones.

class StockZone extends RefCounted:
	var id: StringName = &"zone"
	var rect: Rect2i = Rect2i()
	var filter: Dictionary = {}         # {res:StringName -> true}; empty == accept all
	var priority: int = 0

	func _init(p_rect: Rect2i = Rect2i(), p_priority: int = 0, p_filter: Array = [], p_id: StringName = &"zone") -> void:
		rect = p_rect
		priority = p_priority
		id = p_id
		for r in p_filter:
			filter[StringName(str(r))] = true

	# Does this zone accept the given resource? Empty filter accepts everything.
	func accepts(res) -> bool:
		if filter.is_empty():
			return true
		return filter.has(StringName(str(res)))

	# A representative drop cell (zone centre). The host may refine to the nearest free cell.
	func drop_cell() -> Vector2i:
		return rect.position + rect.size / 2

	func inspect() -> String:
		var f := "усе" if filter.is_empty() else ", ".join(filter.keys().map(func(k): return str(k)))
		return "зона %s (пріоритет %d): %s" % [str(id), priority, f]

# Choose the best zone for a resource: highest priority among accepting zones; ties break by list order
# (stable/deterministic). Returns null when no zone accepts the resource. Pure — no side effects.
static func best_zone_for(zones: Array, res) -> StockZone:
	var best: StockZone = null
	for z in zones:
		if not z.accepts(res):
			continue
		if best == null or z.priority > best.priority:
			best = z
	return best

# Zone-aware haul: like agents.gd's WorkGiver_Haul but routes each pile to its best accepting zone. A
# pile whose resource NO zone accepts is skipped (not hauled). Among haulable piles it takes the nearest,
# and targets that pile's best zone's drop cell. world: {piles:[{pos,res,amt}], zones:[StockZone]}.
class WorkGiver_HaulZone extends RefCounted:
	# Returns a haul Job {verb:&"haul", target: drop_cell, payload:{from,res,amt,zone}} or null.
	func give(agent, world, _ctx: Dictionary):
		var piles: Array = world.get("piles", [])
		var zones: Array = world.get("zones", [])
		if piles.is_empty():
			return null
		var best_pile = null
		var best_zone: StockZone = null
		var best_d: float = 1e20
		for p in piles:
			var z: StockZone = Production.best_zone_for(zones, p.res)
			if z == null:
				continue   # no zone accepts this resource -> leave it on the ground
			var d: float = Vector2(p.pos).distance_to(Vector2(agent.pos))
			if d < best_d:
				best_d = d
				best_pile = p
				best_zone = z
		if best_pile == null:
			return null
		return _job(best_zone.drop_cell(), {"from": best_pile.pos, "res": best_pile.res, "amt": best_pile.amt, "zone": best_zone.id})

	func _job(target: Vector2i, payload: Dictionary):
		return {"verb": &"haul", "target": target, "payload": payload}

# ============================================================================================
# REGISTRATION HELPER
# ============================================================================================
#
# ProductionSystem registers at priority 20 — after environment (10/11/12) and power (15), so a bench
# reads a settled ctx + power verdict. Callers typically add it onto the environment+power registry;
# this helper returns a standalone registry for tests / a production-only host.
static func build_production() -> Systems.SystemRegistry:
	var reg = Systems.SystemRegistry.new()
	reg.add(ProductionSystem.new())
	return reg

# Self-reference alias so inner classes / statics can reach module-level statics by name.
const Production = preload("res://scripts/kernel/production.gd")

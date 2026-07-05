# RealWorld — kernel/balance.gd : the unified Balance director (replaces the classic Storyteller).
#
# The classic RimWorld design splits game-feel across several pieces: Storyteller (pacing),
# StorytellerComp_* (per-category cadence), WealthWatcher (economy), IncidentDef/IncidentWorker
# (content), plus difficulty curves. This kernel COLLAPSES all of that into ONE class — `Balance` —
# the single authority that reads world state and decides what pressure to apply. Everything about
# how the game "feels" (threat, economy, cadence, escalation) lives here and nowhere else.
#
# WHY ONE CLASS: it is the seam for a future AI control layer. Today `decide()` is a transparent,
# rule-based policy; tomorrow a subclass (or an external learned/LLM policy) overrides `decide()` and
# tunes the knobs (`difficulty`, `generosity`, per-category weights) to steer the session — without
# touching incident content or the sim. The sim only ever calls `assess()` (for the UI) and `tick()`
# (to enact incidents); the brain behind those two methods can be swapped wholesale.
#
# Incidents are data + method-Callables owned BY Balance (not separate worker classes), so the whole
# director is one cohesive, serialisable surface. "Raiders are robots": a raid payload just sizes a
# mechanoid force the sim spawns as Agent_Raider (kernel/agents.gd).
extends RefCounted

# Incident categories gate adaptive pacing (big threats never stack).
const CAT_THREAT_BIG := &"threat_big"
const CAT_THREAT_SMALL := &"threat_small"
const CAT_MISC := &"misc"
const CAT_GOOD := &"good"

# Named session phases the UI/AI read off the current threat level.
const PHASE_CALM := &"calm"
const PHASE_RAID := &"raid"
const PHASE_SIEGE := &"siege"
const PHASE_SPIKE := &"spike"

class Balance extends RefCounted:
	# --- balance knobs: the surface a designer or the future AI policy tunes ------------------
	var difficulty: float = 1.0          # global threat multiplier (AI raises/lowers to hit a target)
	var generosity: float = 1.0          # loot/gift multiplier (AI eases a struggling player)
	var category_weight: Dictionary = {  # per-category cadence multipliers (1.0 == default MTB)
		CAT_THREAT_BIG: 1.0, CAT_THREAT_SMALL: 1.0, CAT_MISC: 1.0, CAT_GOOD: 1.0,
	}
	# The incident roster: pure data + a method Callable. Owning them here keeps Balance one class.
	var roster: Array = []

	func _init() -> void:
		_build_roster()

	func _build_roster() -> void:
		roster = [
			{"id": &"raid", "category": CAT_THREAT_BIG, "mtb": 2.4, "fn": Callable(self, "_exec_raid")},
			{"id": &"infestation", "category": CAT_THREAT_SMALL, "mtb": 16.0, "fn": Callable(self, "_exec_infestation")},
			{"id": &"disease", "category": CAT_THREAT_SMALL, "mtb": 9.0, "fn": Callable(self, "_exec_disease")},
			{"id": &"manhunter", "category": CAT_THREAT_SMALL, "mtb": 12.0, "fn": Callable(self, "_exec_manhunter")},
			{"id": &"cold_snap", "category": CAT_MISC, "mtb": 10.0, "fn": Callable(self, "_exec_cold_snap")},
			{"id": &"cargo", "category": CAT_GOOD, "mtb": 8.0, "fn": Callable(self, "_exec_cargo")},
			{"id": &"quest", "category": CAT_GOOD, "mtb": 6.0, "fn": Callable(self, "_exec_quest")},
		]

	# --- economy + threat math (formerly WealthWatcher + StorytellerUtility) ------------------

	# Deterministic colony valuation. world: {buildings:[{value}], stock:{res:amt}, items:[id]}.
	static func wealth(world) -> float:
		var w := 0.0
		for b in world.get("buildings", []):
			w += float(b.get("value", 25.0))
		var stock: Dictionary = world.get("stock", {})
		for k in stock:
			w += float(stock[k])
		w += 20.0 * float((world.get("items", []) as Array).size())
		return w

	# Raw threat points before the difficulty knob. Rises with wealth, days survived, hostile pressure.
	static func threat_points(world, day: int, hostile_pressure: float) -> float:
		return (35.0 + 0.20 * wealth(world) + 6.0 * float(day)) * maxf(0.1, hostile_pressure)

	# --- read side: a snapshot the HUD and the AI both consume --------------------------------

	# One immutable read of "where the session is". Drives the Balance HUD readout AND decide().
	func assess(world, ctx: Dictionary) -> Dictionary:
		var day: int = int(ctx.get("day", 1))
		var pressure: float = float(ctx.get("hostile_pressure", 1.0))
		var w: float = wealth(world)
		var pts: float = threat_points(world, day, pressure) * difficulty
		return {
			"wealth": w,
			"threat": pts,
			"pressure": pressure,
			"phase": _phase(pts),
			"raid_hint": clampi(int(pts / 40.0), 1, 30),
			"difficulty": difficulty,
			"generosity": generosity,
		}

	func _phase(pts: float) -> StringName:
		if pts > 260.0:
			return PHASE_SPIKE
		if pts > 160.0:
			return PHASE_SIEGE
		if pts > 80.0:
			return PHASE_RAID
		return PHASE_CALM

	# --- decide side: THE AI SEAM -------------------------------------------------------------
	# Return the policy for this tick: whether big threats may fire, and any live knob overrides.
	# Default is a transparent rule set; a future AI policy overrides ONLY this method.
	func decide(_state: Dictionary, world, _ctx: Dictionary) -> Dictionary:
		return {
			"allow_big": not bool(world.get("threat_active", false)),
			"threat_mult": difficulty,
			"loot_mult": generosity,
		}

	# --- act side: roll the roster under the policy and return incident payloads ---------------

	func _fires(mtb_days: float, dday: float, weight: float, rng: RandomNumberGenerator) -> bool:
		if dday <= 0.0 or weight <= 0.0:
			return false
		var eff_mtb: float = maxf(0.01, mtb_days / weight)
		var p: float = 1.0 - pow(0.5, dday / eff_mtb)
		return rng.randf() < p

	func tick(world, ctx: Dictionary, rng: RandomNumberGenerator) -> Array:
		var state: Dictionary = assess(world, ctx)
		var policy: Dictionary = decide(state, world, ctx)
		var dday: float = float(ctx.get("dday", 0.0))
		# hand the (difficulty-scaled) points + loot mult to incident payloads via ctx
		var ectx: Dictionary = ctx.duplicate()
		ectx["points"] = state.threat
		ectx["loot_mult"] = float(policy.get("loot_mult", generosity))
		var big_used: bool = not bool(policy.get("allow_big", true))
		var fired: Array = []
		for e in roster:
			if e.category == CAT_THREAT_BIG and big_used:
				continue
			var weight: float = float(category_weight.get(e.category, 1.0))
			if _fires(float(e.mtb), dday, weight, rng):
				fired.append((e.fn as Callable).call(world, ectx))
				if e.category == CAT_THREAT_BIG:
					big_used = true
		return fired

	# --- incident content (methods == the "workers"; all owned by Balance) --------------------

	func _exec_raid(_world, ctx: Dictionary) -> Dictionary:
		var day: int = int(ctx.get("day", 1))
		var pts: float = float(ctx.get("points", 120.0))
		var count: int = clampi(int(pts / 40.0), 1, 30)
		var style := "assault"
		if pts > 260.0:
			style = "sappers"
		elif pts > 160.0:
			style = "siege"
		elif day % 4 == 0:
			style = "droppod"
		return {"incident": "raid", "count": count, "style": style, "points": pts,
			"faction": str(ctx.get("hostile_faction", "мародери"))}

	func _exec_infestation(_world, ctx: Dictionary) -> Dictionary:
		var day: int = int(ctx.get("day", 1))
		return {"incident": "infestation", "count": clampi(3 + day / 2, 3, 15), "where": "під горою"}

	func _exec_disease(_world, _ctx: Dictionary) -> Dictionary:
		return {"incident": "disease", "label": "інфекція легень", "severity": 0.15}

	func _exec_manhunter(_world, ctx: Dictionary) -> Dictionary:
		var day: int = int(ctx.get("day", 1))
		return {"incident": "manhunter", "count": clampi(2 + day / 3, 2, 12), "species": "вовки"}

	func _exec_cold_snap(_world, _ctx: Dictionary) -> Dictionary:
		return {"incident": "cold_snap", "days": 2, "drop_c": 15.0}

	func _exec_cargo(_world, ctx: Dictionary) -> Dictionary:
		var day: int = int(ctx.get("day", 1))
		var loot: float = float(ctx.get("loot_mult", 1.0))
		var amt: int = int((10 + day * 2) * loot)
		return {"incident": "cargo", "stock": {"scrap": amt, "components": maxi(1, day / 3)}}

	func _exec_quest(_world, ctx: Dictionary) -> Dictionary:
		var loot: float = float(ctx.get("loot_mult", 1.0))
		return {"incident": "quest", "kind": "defend", "days": 3,
			"reward": {"reputation": int(10 * loot), "components": int(5 * loot)}}

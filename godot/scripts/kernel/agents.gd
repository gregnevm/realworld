# RealWorld — kernel/agents.gd : non-hero actors (Agent / Job / WorkGiver).
#
# RimWorld analogue: Pawn AI (JobGiver / WorkGiver / Job) — but applied ONLY to non-player actors.
# The hero is always player-ordered; this layer drives everyone else:
#   * Agent_Raider  — a mechanoid attacker. "Raiders are robots": no needs, no morale, just a target.
#   * Agent_Bot     — the player's automation drone: hauls / mines / builds autonomously.
#   * Agent_Animal  — wildlife: wanders/grazes, can turn manhunter; tamed ones haul, guard or carry
#                     caravan loads.
# A WorkGiver scans the world and hands an Agent a Job; the region sim executes the Job (pathing,
# combat) exactly as it already drives raiders today. This layer NEVER spawns human colonist pawns —
# additional people are only ever other live players (MMO).
extends RefCounted

# A unit of intent. The sim turns a Job into movement/actions; the Agent just holds the current one.
class Job extends RefCounted:
	var verb: StringName          # &"attack" &"haul" &"mine" &"guard" &"graze" &"follow"
	var target: Vector2i
	var payload: Dictionary

	func _init(p_verb: StringName, p_target: Vector2i = Vector2i.ZERO, p_payload: Dictionary = {}) -> void:
		verb = p_verb
		target = p_target
		payload = p_payload

# Scans the world for work and returns a Job (or null). Pure decision logic; no side effects.
class WorkGiver extends RefCounted:
	func give(_agent, _world, _ctx: Dictionary):
		return null

# Haul the nearest loose resource pile to storage. world: {piles:[{pos,res,amt}], storage: Vector2i}.
class WorkGiver_Haul extends WorkGiver:
	func give(agent, world, _ctx: Dictionary):
		var piles: Array = world.get("piles", [])
		if piles.is_empty():
			return null
		var best: Variant = null
		var best_d: float = 1e20
		for p in piles:
			var d: float = Vector2(p.pos).distance_to(Vector2(agent.pos))
			if d < best_d:
				best_d = d
				best = p
		if best == null:
			return null
		return Job.new(&"haul", world.get("storage", Vector2i.ZERO), {"from": best.pos, "res": best.res, "amt": best.amt})

# --- shared world queries -------------------------------------------------------------------

# THE hostile list: world.agents (preferred — a mixed-faction list) filtered to live hostiles, with
# legacy world.raiders as the fallback pool. Raider dicts carry no faction — that list's membership
# IS the faction, so dict entries pass unless they claim otherwise. This mirrors combat.gd's
# turret/trap targeting idiom (world.agents → world.raiders + _is_hostile) so every kernel consumer
# reads ONE definition of "the enemies" and a guard animal can never disagree with a turret.
static func hostiles(world) -> Array:
	if world == null or typeof(world) != TYPE_DICTIONARY:
		return []
	var pool: Array = world.get("agents", world.get("raiders", []))
	var out: Array = []
	for a in pool:
		if a is Agent:
			if a.alive() and a.faction == &"hostile":
				out.append(a)
		elif typeof(a) == TYPE_DICTIONARY:
			if StringName(str(a.get("faction", "hostile"))) == &"hostile":
				out.append(a)
	return out

# --- agents -------------------------------------------------------------------

class Agent extends RefCounted:
	var kind: StringName          # &"raider" &"bot" &"animal"
	var faction: StringName = &"neutral"
	var pos: Vector2i = Vector2i.ZERO
	var hp: float = 30.0
	var job: Variant              # current Job or null

	# Decide what to do this tick (sets self.job). Override per kind.
	func think(_world, _ctx: Dictionary) -> void:
		pass

	func alive() -> bool:
		return hp > 0.0

# Mechanoid raider: always drives toward the base and attacks. No needs. Sized/spawned by Storyteller.
class Agent_Raider extends Agent:
	func _init() -> void:
		kind = &"raider"
		faction = &"hostile"

	func think(world, _ctx: Dictionary) -> void:
		job = Job.new(&"attack", world.get("base", Vector2i.ZERO))

# Automation drone: hauls loose resources home; idles when there is nothing to do.
class Agent_Bot extends Agent:
	var hauler: WorkGiver_Haul = WorkGiver_Haul.new()

	func _init() -> void:
		kind = &"bot"
		faction = &"player"

	func think(world, ctx: Dictionary) -> void:
		job = hauler.give(self, world, ctx)

# Wildlife. Manhunter -> hunts the hero. Tamed guard -> attacks the nearest raider. Else grazes.
class Agent_Animal extends Agent:
	var tame: bool = false
	var role: StringName = &"none"   # &"guard" &"pack" &"none"
	var manhunter: bool = false

	func _init(p_tame: bool = false, p_role: StringName = &"none") -> void:
		kind = &"animal"
		tame = p_tame
		role = p_role
		faction = &"player" if p_tame else &"wild"

	func think(world, _ctx: Dictionary) -> void:
		if manhunter:
			job = Job.new(&"attack", world.get("hero", Vector2i.ZERO))
		elif tame and role == &"guard":
			var foes: Array = Agents.hostiles(world)
			if not foes.is_empty():
				job = Job.new(&"attack", foes[0].pos)
			else:
				job = Job.new(&"follow", world.get("hero", Vector2i.ZERO))
		elif tame and role == &"pack":
			job = Job.new(&"follow", world.get("convoy", Vector2i.ZERO))
		else:
			job = Job.new(&"graze", pos)

# Self-reference alias so inner classes can reach module-level statics by name (kernel idiom).
const Agents = preload("res://scripts/kernel/agents.gd")

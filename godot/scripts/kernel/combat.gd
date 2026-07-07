# RealWorld — kernel/combat.gd : threats & combat objects (Batch 5).
#
# RimWorld analogue: Building_TurretGun + CompRefuelable/heat, Building_TurretGun (mortar) + Projectile,
# Building_Trap*, the Fire Thing + FireWatcher spread, and cover as a hit-mitigation term. This module
# adds the *defensive/offensive object* layer on top of the established kernel grammar:
#   * CompTurret     — an auto-firing gun bolted to a powered Thing (needs Power.CompPowerTrader.is_live()).
#   * CompMortar     — lobs a Projectile Thing at a target cell; scatter grows with range (seeded rng).
#   * Projectile     — a Thing that lands after a fuse (dday countdown) and deals area damage.
#   * CompTrap       — triggers on a HOSTILE Agent entering its cell; NEVER on the hero/player faction.
#   * CompFlammable  — a burnable Thing; FireSystem spreads fire to adjacent flammables & burns them,
#                      ctx.wet (rain/snow, Batch 1) suppresses ignition and extinguishes.
#   * StatPart_Cover + apply_cover() — cover reduces incoming RANGED damage.
#
# Everything is a Thing-comp / SimSystem / StatPart, so sim.gd and the tick loop never change. Every
# stochastic path (mortar scatter, fire ignition rolls) takes a seeded RandomNumberGenerator — no global
# randf(), no time seeds. Faction rule for all offensive objects: friendly fire is impossible — turrets and
# traps only ever hit factions in HOSTILE_FACTIONS; the hero/player is never a valid target.
extends RefCounted

const Systems = preload("res://scripts/kernel/systems.gd")
const Things = preload("res://scripts/kernel/things.gd")
const Stats = preload("res://scripts/kernel/stats.gd")
const Power = preload("res://scripts/kernel/power.gd")

# Factions a defensive turret/trap treats as a valid target. The hero (&"player") and tamed animals /
# bots (&"player") and neutral/wild parties are NEVER shot by the player's own defences.
const HOSTILE_FACTIONS := [&"hostile"]

# --- shared helpers -----------------------------------------------------------

# Manhattan distance between two cells (the kernel's grid metric, matching the power/fire radius idiom).
static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

# Is this Agent a legal target for a player-owned defence?
static func _is_hostile(agent) -> bool:
	return agent != null and agent.alive() and agent.faction in HOSTILE_FACTIONS

# Deal `amt` damage to whatever combat entity we hit: an Agent (has .hp) or a Thing (take_damage()).
static func _damage_entity(entity, amt: float) -> void:
	if entity == null:
		return
	if entity is Things.Thing:
		entity.take_damage(amt)
	else:
		# Agent-like: subtract hp directly (Agent has no take_damage()).
		entity.hp -= amt

# --- 1. CompTurret (spec 0003 D3) : an auto-firing gun -------------------------------------------------
#
# A turret Thing that carries THIS comp AND a Power.CompPowerTrader. Each tick it fires at the nearest
# hostile Agent within `range` ONLY when: the net delivers power (trader.is_live()) AND ammo > 0 AND
# heat < heat_max AND its cooldown timer has elapsed. Firing consumes one ammo, adds `heat`, and deals
# `damage` to the target. When it cannot fire it bleeds heat and cooldown back down over dday. Targeting
# is deterministic: nearest hostile by Manhattan distance, ties broken by index in world.agents/raiders.
# props: {range:float, damage:float, cooldown:float, ammo_max:int, heat_max:float, heat_per_shot:float,
#         cool_rate:float}. Reads world.agents (preferred) or world.raiders (fallback list of Agents).
class CompTurret extends Things.ThingComp:
	var ammo: int = 0
	var heat: float = 0.0
	var cool: float = 0.0            # remaining cooldown time (days) before the next shot is allowed
	var fired_last: bool = false     # HUD/inspect: did it fire on the most recent tick

	func _init(p_props: Dictionary = {}) -> void:
		super(p_props)
		ammo = int(props.get("ammo", props.get("ammo_max", 0)))

	func range_r() -> float:
		return float(props.get("range", 6.0))

	func damage() -> float:
		return float(props.get("damage", 10.0))

	func cooldown() -> float:
		return float(props.get("cooldown", 1.0))

	func ammo_max() -> int:
		return int(props.get("ammo_max", 0))

	func heat_max() -> float:
		return float(props.get("heat_max", 4.0))

	# True only when the turret's Power.CompPowerTrader (if any) is delivering. No trader => treated as
	# unpowered (a turret must be wired to fire — this is the power gate the task requires).
	func is_powered() -> bool:
		if parent == null:
			return false
		var tr = parent.get_comp(Power.CompPowerTrader)
		return tr != null and tr.is_live()

	# Can it fire THIS tick? powered AND has ammo AND not overheated AND off cooldown.
	func can_fire() -> bool:
		return is_powered() and ammo > 0 and heat < heat_max() and cool <= 0.0

	# Pick the nearest hostile Agent within range; deterministic (nearest, tie by list index).
	func _pick_target(agents: Array):
		var best = null
		var best_d: int = 1 << 30
		var here: Vector2i = parent.pos
		var reach: int = int(ceil(range_r()))
		for a in agents:
			if not Combat._is_hostile(a):
				continue
			var d: int = Combat._manhattan(here, a.pos)
			if d > reach:
				continue
			if d < best_d:   # strict '<' => first-seen wins on a tie (deterministic by list order)
				best_d = d
				best = a
		return best

	func comp_tick(ctx: Dictionary) -> void:
		fired_last = false
		var dday: float = float(ctx.get("dday", 0.0))
		# always bleed cooldown/heat down first (recovery happens whether or not we fire)
		if cool > 0.0:
			cool = maxf(0.0, cool - dday)
		if heat > 0.0:
			heat = maxf(0.0, heat - float(props.get("cool_rate", 2.0)) * dday)
		if not can_fire():
			return
		var world = ctx.get("world", null)
		var agents: Array = []
		if world != null and typeof(world) == TYPE_DICTIONARY:
			agents = world.get("agents", world.get("raiders", []))
		var target = _pick_target(agents)
		if target == null:
			return
		# FIRE.
		ammo -= 1
		heat += float(props.get("heat_per_shot", 1.0))
		cool = cooldown()
		fired_last = true
		Combat._damage_entity(target, damage())

	func reload(n: int) -> void:
		# Cap at capacity (never overfill past ammo_max). If ammo is already over the cap
		# (e.g. an over-provisioned build), keep it where it is rather than dropping rounds.
		ammo = clampi(ammo + n, 0, maxi(ammo, ammo_max()))

	func inspect() -> String:
		return "🔫 турель: набої %d/%d, нагрів %d%%%s" % [
			ammo, ammo_max(), int(100.0 * clampf(heat / maxf(0.01, heat_max()), 0.0, 1.0)),
			" (💥)" if fired_last else ""]

# --- 2a. CompMortar (spec 0003 #24) : lobbed artillery -------------------------------------------------
#
# A mortar Thing that lobs a Projectile at a target cell. Scatter (in cells) grows with the distance to
# the target and is applied with a SEEDED rng, so the impact cell is deterministic per (seed, target).
# fire() BUILDS the Projectile and returns it (the host/MortarSystem appends it to world.things so it
# ticks its fuse); the comp does not need world access. props: {min_range, max_range, fuse_days,
# blast_radius, damage, scatter_base, scatter_per_cell}.
class CompMortar extends Things.ThingComp:
	func fuse_days() -> float:
		return float(props.get("fuse_days", 2.0))

	func blast_radius() -> int:
		return int(props.get("blast_radius", 2))

	func damage() -> float:
		return float(props.get("damage", 40.0))

	# Scatter radius (cells) for a shot at `dist` cells range: a base wobble plus a per-cell growth term.
	func scatter_for(dist: float) -> float:
		return float(props.get("scatter_base", 1.0)) + float(props.get("scatter_per_cell", 0.06)) * dist

	# Build (do not spawn) a Projectile aimed at `target`, scattered deterministically by `rng`.
	func fire(target: Vector2i, rng: RandomNumberGenerator) -> Projectile:
		var origin: Vector2i = parent.pos if parent != null else Vector2i.ZERO
		var dist: float = Vector2(origin).distance_to(Vector2(target))
		var s: float = scatter_for(dist)
		# uniform offset in [-s, s] on each axis (seeded); rounded to the grid.
		var dx: int = int(round(rng.randf_range(-s, s)))
		var dy: int = int(round(rng.randf_range(-s, s)))
		var impact := Vector2i(target.x + dx, target.y + dy)
		return Projectile.new(impact, fuse_days(), blast_radius(), damage(),
			parent.flags.get("faction", &"hostile") if parent != null else &"hostile")

	func inspect() -> String:
		return "🎯 міномет: радіус %d, заряд %d" % [blast_radius(), int(damage())]

# --- 2b. Projectile (spec 0003 #24) : an in-flight shell ----------------------------------------------
#
# A Thing that counts down a fuse (in days) and, when the fuse expires, deals `damage` to every combat
# entity within `blast_radius` (Manhattan) of its impact cell. `owner_faction` decides who it may hurt:
# a player mortar's shell hits HOSTILE agents; an enemy-siege shell hits the base (Things) & player agents.
# It self-destroys after it lands. State on the Thing itself (a Projectile IS a Thing).
class Projectile extends Things.Thing:
	var fuse: float
	var blast_radius_cells: int
	var blast_damage: float
	var owner_faction: StringName
	var exploded: bool = false
	var landed_at: Vector2i

	func _init(p_impact: Vector2i, p_fuse: float, p_radius: int, p_damage: float, p_owner: StringName = &"hostile") -> void:
		super(null)
		pos = p_impact
		landed_at = p_impact
		fuse = p_fuse
		blast_radius_cells = p_radius
		blast_damage = p_damage
		owner_faction = p_owner
		max_hp = 1.0
		hp = 1.0

	func in_flight() -> bool:
		return not exploded and not destroyed

	# Advance the fuse; when it hits 0, resolve the blast against world entities and self-destroy.
	func tick(ctx: Dictionary) -> void:
		if exploded or destroyed:
			return
		fuse -= float(ctx.get("dday", 0.0))
		if fuse > 0.0:
			return
		explode(ctx.get("world", null))

	# Deal area damage at landed_at. A player shell hits hostiles (agents); an enemy shell hits the
	# defender's Things (walls/base) and player agents. Everything within blast_radius (Manhattan).
	func explode(world) -> Array:
		exploded = true
		destroyed = true
		var hit: Array = []
		if world == null or typeof(world) != TYPE_DICTIONARY:
			return hit
		var targets: Array = []
		if owner_faction in HOSTILE_FACTIONS:
			# enemy siege shell -> smash the player's Things, and any player agents standing there.
			# NEVER hit other in-flight shells: a Projectile IS a Thing added to world.things, so a
			# salvo of overlapping siege shells would otherwise chain-cancel itself mid-air.
			for t in world.get("things", []):
				if t is Projectile:
					continue
				targets.append(t)
			for a in world.get("agents", []):
				if a != null and a.faction == &"player":
					targets.append(a)
		else:
			# player shell -> hit hostile agents.
			for a in world.get("agents", world.get("raiders", [])):
				if Combat._is_hostile(a):
					targets.append(a)
		for e in targets:
			if e == null or e == self:
				continue
			var ep: Vector2i = e.pos
			if Combat._manhattan(landed_at, ep) <= blast_radius_cells:
				Combat._damage_entity(e, blast_damage)
				hit.append(e)
		return hit

	func inspect() -> String:
		return "💣 снаряд: підрив за %.1f дн" % maxf(0.0, fuse)

# Enemy siege hook (spec 0003 #24): when the Balance director emits a raid incident with style "siege",
# the HOST resolves it by calling this to build a battery of enemy mortar Things aimed at the base and
# appending them to world.things (Balance itself only emits the incident payload; it does not spawn
# Things). Each returned Thing carries a CompMortar and flags.faction = hostile.
static func from_siege(count: int, target: Vector2i, origin: Vector2i = Vector2i.ZERO) -> Array:
	var out: Array = []
	for i in maxi(0, count):
		var m := Things.Thing.new(null)
		m.pos = origin
		m.flags["faction"] = &"hostile"
		m.flags["aim"] = target
		m.add_comp(CompMortar.new({"fuse_days": 2.0, "blast_radius": 2, "damage": 40.0}))
		out.append(m)
	return out

# --- 3. CompTrap (spec 0003 #20) : a one-or-few-shot defensive trap ------------------------------------
#
# A trap Thing armed at build. Each tick it checks whether a HOSTILE Agent occupies parent.pos; if so it
# springs: deals `damage` to that agent, decrements `uses`, and DISARMS at 0 uses. It NEVER triggers on
# the hero or any player-faction actor (friendly fire is impossible). props: {damage, uses}. Reads
# world.agents (preferred) or world.raiders. Deterministic: the first hostile in list order is struck.
class CompTrap extends Things.ThingComp:
	var uses: int = 1
	var armed: bool = true
	var sprung_last: bool = false

	func _init(p_props: Dictionary = {}) -> void:
		super(p_props)
		uses = int(props.get("uses", 1))

	func damage() -> float:
		return float(props.get("damage", 25.0))

	func comp_tick(ctx: Dictionary) -> void:
		sprung_last = false
		if not armed or uses <= 0:
			return
		var world = ctx.get("world", null)
		if world == null or typeof(world) != TYPE_DICTIONARY:
			return
		var here: Vector2i = parent.pos
		var agents: Array = world.get("agents", world.get("raiders", []))
		for a in agents:
			if not Combat._is_hostile(a):
				continue                        # hero / player / wild are NEVER triggered
			if a.pos == here:
				Combat._damage_entity(a, damage())
				uses -= 1
				sprung_last = true
				if uses <= 0:
					armed = false
				return                          # one victim per trigger (deterministic: first in list)

	func inspect() -> String:
		return "🪤 пастка: %s (заряди %d)" % [("зведена" if armed else "спрацювала"), uses]

# --- 4. CompFlammable + FireSystem (spec 0003 #19) : fire & spread -------------------------------------
#
# A burnable Thing. It does not tick itself; the FireSystem owns ignition-spread and burn damage over the
# whole world.things set so spread is a single deterministic pass. parent.flags["on_fire"] is the burning
# state (shared with any other system that reads it, e.g. the HUD fire markers). props: {flammability:
# 0..1 (ignition chance per adjacent fire per day), burn_damage: hp/day}.
class CompFlammable extends Things.ThingComp:
	func flammability() -> float:
		return clampf(float(props.get("flammability", 0.5)), 0.0, 1.0)

	func burn_damage() -> float:
		return float(props.get("burn_damage", 20.0))

	func on_fire() -> bool:
		return bool(parent.flags.get("on_fire", false))

	func ignite() -> void:
		parent.flags["on_fire"] = true

	func extinguish() -> void:
		parent.flags["on_fire"] = false

	func inspect() -> String:
		return "🔥 горить" if on_fire() else "🪵 займисте"

# FireSystem (priority 30, after production@20 / comfort@25). Each tick, over world.things:
#   * ctx.wet (rain/snow, Batch 1) EXTINGUISHES all burning Things and suppresses new ignition entirely.
#   * otherwise: burning flammable Things take burn_damage*dday; each adjacent (Manhattan<=1) flammable
#     Thing rolls flammability*dday against world.rng to catch fire. Ignition rolls are computed from a
#     SNAPSHOT of who was burning at tick start, so spread is one ring per tick (deterministic).
class FireSystem extends Systems.SimSystem:
	func _init() -> void:
		system_id = &"fire"
		priority = 30

	func _flammables(world) -> Array:
		var out: Array = []
		if world == null or typeof(world) != TYPE_DICTIONARY:
			return out
		for t in world.get("things", []):
			if t == null or t.destroyed:
				continue
			if t.get_comp(CompFlammable) != null:
				out.append(t)
		return out

	func system_tick(world, ctx: Dictionary) -> void:
		var flam: Array = _flammables(world)
		if flam.is_empty():
			return
		var dday: float = float(ctx.get("dday", 0.0))

		# --- rain/snow: put everything out, no ignition this tick ----------------------------------
		if bool(ctx.get("wet", false)):
			for t in flam:
				t.flags["on_fire"] = false
			return

		# snapshot: who is burning at the START of this tick (spread reads the old ring, not the new one)
		var burning: Array = []
		for t in flam:
			if bool(t.flags.get("on_fire", false)):
				burning.append(t)
		if burning.is_empty():
			return

		var rng = world.get("rng", null)
		# --- spread: each unburnt flammable adjacent to a burning one rolls to ignite ---------------
		for t in flam:
			if bool(t.flags.get("on_fire", false)):
				continue
			var adj := false
			for b in burning:
				if Combat._manhattan(t.pos, b.pos) <= 1:
					adj = true
					break
			if not adj:
				continue
			var fc = t.get_comp(CompFlammable)
			var p: float = clampf(fc.flammability() * dday, 0.0, 1.0)
			var roll: float = rng.randf() if rng != null else 1.0   # no rng => never ignites (safe/deterministic)
			if roll < p:
				t.flags["on_fire"] = true

		# --- burn: every Thing burning at tick start takes damage over dday ------------------------
		for b in burning:
			var fc = b.get_comp(CompFlammable)
			b.take_damage(fc.burn_damage() * dday)
			if b.destroyed:
				b.flags["on_fire"] = false

# --- 5. Cover (spec 0003 D6) : ranged damage mitigation -----------------------------------------------
#
# Cover reduces RANGED incoming damage. Two surfaces, both reading world.cover (a set/array of cells that
# provide cover):
#   * apply_cover(dmg, defender_pos, world) — a static: a defender ON or ADJACENT to a cover cell takes a
#     fraction (world.cover_frac, default 0.5) less ranged damage. Returns the reduced damage.
#   * StatPart_Cover — the same term as a Stats pipeline part: reads ctx.cover_mult (1.0 = no cover) and
#     multiplies incoming ranged damage by it, so a damage StatWorker can fold cover in with quality/etc.
class StatPart_Cover extends Stats.StatPart:
	func transform(val: float, ctx: Dictionary) -> float:
		return val * clampf(float(ctx.get("cover_mult", 1.0)), 0.0, 1.0)

	func explain(ctx: Dictionary) -> String:
		return "×укриття %.2f" % clampf(float(ctx.get("cover_mult", 1.0)), 0.0, 1.0)

# Does the defender at `pos` benefit from cover? True if pos is on or Manhattan-adjacent to a cover cell.
static func in_cover(pos: Vector2i, world) -> bool:
	if world == null or typeof(world) != TYPE_DICTIONARY:
		return false
	var cover = world.get("cover", [])
	for c in cover:
		if _manhattan(pos, c) <= 1:
			return true
	return false

# Reduce ranged `dmg` for a defender at `defender_pos`: in cover -> multiply by (1 - cover_frac).
static func apply_cover(dmg: float, defender_pos: Vector2i, world) -> float:
	if not in_cover(defender_pos, world):
		return dmg
	var frac: float = clampf(float(world.get("cover_frac", 0.5)), 0.0, 1.0)
	return dmg * (1.0 - frac)

# --- registration helper -----------------------------------------------------------------------------
#
# The combat systems register AFTER the economy/comfort layer: FireSystem at 30. Turrets/traps/projectiles
# are comp-driven (they tick via their parent Thing's comp_tick / Projectile.tick), so the only SimSystem
# here is FireSystem; a host that wants trap/turret ticking drives Things.tick(ctx) with ctx.world set.
static func build_combat() -> Systems.SystemRegistry:
	var reg = Systems.SystemRegistry.new()
	reg.add(FireSystem.new())
	return reg

# Self-reference alias so inner classes / statics can reach module-level statics by name.
const Combat = preload("res://scripts/kernel/combat.gd")

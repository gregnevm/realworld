# RealWorld — kernel/things.gd : the composition core (Thing + ThingComp).
#
# RimWorld analogue: ThingWithComps / ThingComp / CompProperties. Every in-world object — a building,
# a plant, an item stack, a corpse, a dropped resource pile — is a Thing carrying a list of
# ThingComps. The Thing is dumb located state; each Comp is ONE orthogonal behaviour that ticks
# itself from a shared context. Adding a mechanic = writing a Comp and attaching it via the Def; the
# Thing and the tick loop never change. This is the single most reused abstraction in the kernel:
# rot, growth, quality, power, fuel, fire and deterioration are all just Comps.
extends RefCounted

# The world's Thing list (world.things), [] when the world is absent or not a dict. The power and
# production systems both scan this list every tick — the guard lives here once, not per-system.
static func world_things(world) -> Array:
	if world != null and typeof(world) == TYPE_DICTIONARY:
		return world.get("things", [])
	return []

# --- base interface -----------------------------------------------------------

# One orthogonal behaviour bolted onto a Thing. Override the hooks you need; ignore the rest.
class ThingComp extends RefCounted:
	var parent: Variant                 # back-reference to the owning Thing (null until attached)
	var props: Dictionary = {}          # per-comp tuning, pulled from the Def

	func _init(p_props: Dictionary = {}) -> void:
		props = p_props

	# Called once after the Thing is fully built (roll quality, seed timers). rng is the world seed.
	func post_make(_rng: RandomNumberGenerator) -> void:
		pass

	# Called every world tick with the shared ctx (dt, dday, temp_c, light, season, rng...).
	func comp_tick(_ctx: Dictionary) -> void:
		pass

	# One-line status for tooltips / inspect panels ("" == nothing to show).
	func inspect() -> String:
		return ""

# --- the Thing ----------------------------------------------------------------

class Thing extends RefCounted:
	var def: Variant                     # Defs.Def or null
	var pos: Vector2i = Vector2i.ZERO
	var hp: float = 100.0
	var max_hp: float = 100.0
	var stack: int = 1
	var destroyed: bool = false
	var comps: Array = []
	var flags: Dictionary = {}          # scratch shared with comps: quality, growth, rot, on_fire...

	func _init(p_def = null) -> void:
		def = p_def
		if p_def != null:
			max_hp = float(p_def.field(&"max_hp", 100.0))
			hp = max_hp

	func add_comp(c) -> void:
		c.parent = self
		comps.append(c)
		return

	# Fetch a comp by its (inner) class, e.g. get_comp(Things.CompRottable).
	func get_comp(cls):
		for c in comps:
			if is_instance_of(c, cls):
				return c
		return null

	func post_make(rng: RandomNumberGenerator) -> void:
		for c in comps:
			c.post_make(rng)

	func tick(ctx: Dictionary) -> void:
		if destroyed:
			return
		for c in comps:
			c.comp_tick(ctx)

	func take_damage(amt: float) -> void:
		hp -= amt
		if hp <= 0.0:
			destroyed = true

	func inspect() -> String:
		var lines := []
		for c in comps:
			var s: String = c.inspect()
			if s != "":
				lines.append(s)
		return "\n".join(lines)

	# The sim owns Things; a Comp holds a strong back-reference to its parent, so RefCounted cannot
	# collect the pair on its own. Call this when the sim drops the Thing to break the cycle.
	func detach() -> void:
		for c in comps:
			c.parent = null
		comps.clear()

# --- reference comps (one interface, wildly different mechanics) --------------

# Organics spoil. Rot advances faster when warm, HALTS at/below freezing (this is refrigeration),
# and destroys the stack at 100%. props: {rot_days: float}.
class CompRottable extends ThingComp:
	func comp_tick(ctx: Dictionary) -> void:
		var t: float = float(ctx.get("temp_c", 20.0))
		if t <= 0.0:
			return
		var rot_days: float = float(props.get("rot_days", 10.0))
		var per_day: float = 1.0 / maxf(0.01, rot_days)
		var warm_mult: float = clampf(t / 10.0, 0.2, 4.0)
		var cur: float = float(parent.flags.get("rot", 0.0)) + per_day * warm_mult * float(ctx.get("dday", 0.0))
		parent.flags["rot"] = cur
		if cur >= 1.0:
			parent.destroyed = true

	func progress() -> float:
		return clampf(float(parent.flags.get("rot", 0.0)), 0.0, 1.0)

	func inspect() -> String:
		return "гниль: %d%%" % int(100.0 * progress())

# Crops grow. Growth 0..1 advances only inside a viable temperature band and with enough light;
# dormant at night / out of season. props: {grow_days, temp_min, temp_max, min_light}.
class CompGrower extends ThingComp:
	func comp_tick(ctx: Dictionary) -> void:
		var t: float = float(ctx.get("temp_c", 20.0))
		var light: float = float(ctx.get("light", 1.0))
		var tmin: float = float(props.get("temp_min", 0.0))
		var tmax: float = float(props.get("temp_max", 42.0))
		if t < tmin or t > tmax or light < float(props.get("min_light", 0.3)):
			return
		var grow_days: float = float(props.get("grow_days", 6.0))
		var g: float = float(parent.flags.get("growth", 0.0)) + (1.0 / maxf(0.01, grow_days)) * light * float(ctx.get("dday", 0.0))
		parent.flags["growth"] = clampf(g, 0.0, 1.0)

	func growth() -> float:
		return clampf(float(parent.flags.get("growth", 0.0)), 0.0, 1.0)

	func mature() -> bool:
		return growth() >= 1.0

	func inspect() -> String:
		return "ріст: %d%%" % int(100.0 * growth())

# Made things carry a quality tier rolled once at creation from the maker's competence.
# 0 жахлива .. 6 легендарна. Feeds Stats via StatPart_Quality. props: {maker_level: 0..20}.
class CompQuality extends ThingComp:
	const LABELS := ["жахлива", "погана", "звичайна", "добра", "відмінна", "майстерна", "легендарна"]

	func post_make(rng: RandomNumberGenerator) -> void:
		var level: float = float(props.get("maker_level", 0.0))
		var roll: float = rng.randf() * 5.0 + level * 0.18
		parent.flags["quality"] = clampi(int(roll), 0, 6)

	func level() -> int:
		return int(parent.flags.get("quality", 2))

	# Multiplier applied to the item's stats: жахлива 0.60 .. звичайна 0.90 .. легендарна 1.50.
	func mult() -> float:
		return 0.6 + 0.15 * level()

	func inspect() -> String:
		return "якість: %s" % LABELS[level()]

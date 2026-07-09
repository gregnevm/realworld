# RealWorld — kernel/environment.gd : the environmental ctx substrate (Batch 1).
#
# RimWorld analogue: Map temperature + GlowGrid/LightingManager + WeatherManager + RoofGrid + the
# "under a roof?" deterioration check. This module is the LAYER THAT WRITES the shared per-tick ctx
# every other mechanic reads. Nothing here decides gameplay outcomes directly; it turns the region's
# real climate (climate.gd) plus local modifiers (roofs, heaters, lamps, incidents) into four ctx
# facts — temp_c, weather, wet, light — plus per-cell indoor classification. CompRottable/CompGrower
# then read temp_c/light; CompDeteriorate (below) reads indoor/wet.
#
# Determinism: the only stochastic call is ClimateProvider.weather(), and it takes the world's seeded
# rng (world.rng) exactly like every other kernel stochastic path. No global randf(), no time seeds.
#
# Decoupling from Batch 2 (power): heaters, coolers and lamps are read as PLAIN LISTS off `world`
# (temp_emitters / lights), each entry carrying an `active` flag. Batch 2 owns creating the emitter
# Things and flipping `active`; this layer only reads the list. So the environment layer composes with
# power without depending on it.
extends RefCounted

const Systems = preload("res://scripts/kernel/systems.gd")
const Things = preload("res://scripts/kernel/things.gd")
const Climate = preload("res://scripts/kernel/climate.gd")

# Comfortable indoor setpoint (°C) an enclosed, roofed room buffers toward.
const INDOOR_SETPOINT_C := 21.0
# Fraction of the gap to setpoint an indoor cell closes each query (0..1). Insulation, not perfect.
const INDOOR_INSULATION := 0.6
# Weather StringNames that count as "wet" (suppress fire, weather crops, speed deterioration).
const WET_WEATHERS := [&"rain", &"snow"]

# --- RoofMap : which cells are roofed + enclosed ("indoor") -------------------
#
# RimWorld analogue: RoofGrid + the "room is enclosed" test collapsed to a single per-cell boolean.
# Small, dumb, serialisable: a set of indoor cells. Indoor cells buffer temperature toward the
# setpoint and block rain / deterioration. Batch 2 (building) sets these as rooms are enclosed.
class RoofMap extends RefCounted:
	var _indoor: Dictionary = {}   # Vector2i -> true (absence == outdoor)

	func set_indoor(pos: Vector2i, v: bool) -> void:
		if v:
			_indoor[pos] = true
		else:
			_indoor.erase(pos)

	func is_indoor(pos: Vector2i) -> bool:
		return _indoor.has(pos)

	func count() -> int:
		return _indoor.size()

# --- helpers shared by the systems -------------------------------------------

# The cell a ctx query is "about": explicit ctx.cell, else the world hero cell, else origin.
static func _query_cell(world, ctx: Dictionary) -> Vector2i:
	if ctx.has("cell"):
		return ctx.get("cell")
	if world != null and typeof(world) == TYPE_DICTIONARY and world.has("hero"):
		return world.get("hero")
	return Vector2i.ZERO

# Is the query cell indoor per world.roof (a RoofMap)? Absent roof == everything outdoor.
static func _cell_indoor(world, cell: Vector2i) -> bool:
	if world == null or typeof(world) != TYPE_DICTIONARY:
		return false
	var roof = world.get("roof", null)
	if roof == null:
		return false
	return roof.is_indoor(cell)

# --- TemperatureSystem (spec 0003 #17) : writes ctx.temp_c -------------------
#
# Priority ~10: ticks early so CompRottable / CompGrower (and later heat/cold-stress) read a fresh
# temp_c. Pipeline: base outdoor from ClimateProvider → indoor buffering toward setpoint → nearby
# active emitters (heaters +, coolers −) → transient world.temp_offset (cold-snap / heat-wave). Also
# stamps ctx.indoor so downstream comps (CompDeteriorate) don't re-derive it.
class TemperatureSystem extends Systems.SimSystem:
	# Manhattan radius within which an emitter reaches the query cell (deterministic, no falloff curve).
	var emitter_radius: int = 6

	func _init() -> void:
		system_id = &"temperature"
		priority = 10

	func system_tick(world, ctx: Dictionary) -> void:
		var climate = _climate(world)
		var cell: Vector2i = Env._query_cell(world, ctx)
		var indoor: bool = Env._cell_indoor(world, cell)
		ctx["cell"] = cell
		ctx["indoor"] = indoor

		var t: float = climate.temperature_c(
			float(world.get("lat", 0.0)), float(world.get("lon", 0.0)),
			int(world.get("day", 1)), float(world.get("frac", 0.5)))

		# Indoor cells buffer toward the comfortable setpoint by the insulation fraction.
		if indoor:
			t = t + (Env.INDOOR_SETPOINT_C - t) * Env.INDOOR_INSULATION

		# Nearby active emitters push temperature (heaters +delta, coolers −delta). Batch 2 owns
		# `active`; we just sum the reachable, active ones.
		for e in world.get("temp_emitters", []):
			if not bool(e.get("active", false)):
				continue
			var ep: Vector2i = e.get("pos", cell)
			var dist: int = abs(ep.x - cell.x) + abs(ep.y - cell.y)
			if dist <= emitter_radius:
				t += float(e.get("delta_c", 0.0))

		# Transient regional shift from a cold-snap / heat-wave incident (Balance cold_snap: drop_c).
		t += float(world.get("temp_offset", 0.0))

		ctx["temp_c"] = t

	func _climate(world):
		var c = null
		if world != null and typeof(world) == TYPE_DICTIONARY:
			c = world.get("climate", null)
		if c == null:
			c = Climate.ClimateModel_Deterministic.new()
		return c

# --- WeatherSystem (spec 0003 #18) : writes ctx.weather + effects ------------
#
# Priority ~11. A pure ctx-writer: pulls a weather StringName from ClimateProvider.weather() with the
# world's seeded rng, sets ctx.wet (rain/snow — suppresses fire in Batch 5, weathers crops here), and
# nudges ctx.temp_c down on a cold_snap. Indoor cells are never "wet" (roof blocks precipitation).
class WeatherSystem extends Systems.SimSystem:
	# Extra °C dip a cold_snap weather roll applies on top of any regional temp_offset.
	var cold_snap_dip_c: float = 6.0

	func _init() -> void:
		system_id = &"weather"
		priority = 11

	func system_tick(world, ctx: Dictionary) -> void:
		var climate = _climate(world)
		var rng = _rng(world)
		var w: StringName = climate.weather(
			float(world.get("lat", 0.0)), float(world.get("lon", 0.0)),
			int(world.get("day", 1)), float(world.get("frac", 0.5)), rng)
		ctx["weather"] = w

		var indoor: bool = bool(ctx.get("indoor", false))
		# Precipitation only reaches outdoor cells; a roof keeps the cell dry.
		var wet: bool = (w in Env.WET_WEATHERS) and not indoor
		ctx["wet"] = wet

		# A cold_snap weather roll bites the ambient temperature (outdoors more than in).
		if w == &"cold_snap":
			var dip: float = cold_snap_dip_c
			if indoor:
				dip *= (1.0 - Env.INDOOR_INSULATION)
			ctx["temp_c"] = float(ctx.get("temp_c", 20.0)) - dip

	func _climate(world):
		var c = null
		if world != null and typeof(world) == TYPE_DICTIONARY:
			c = world.get("climate", null)
		if c == null:
			c = Climate.ClimateModel_Deterministic.new()
		return c

	func _rng(world) -> RandomNumberGenerator:
		if world != null and typeof(world) == TYPE_DICTIONARY:
			var r = world.get("rng", null)
			if r != null:
				return r
		# No world rng (standalone tick / test): fall back to a FIXED-seed generator so weather stays
		# reproducible. Mirrors Production._world_rng — an unseeded RandomNumberGenerator.new() is
		# randomly seeded in Godot 4 and would break the module's "only seeded rng" determinism rule.
		var fallback := RandomNumberGenerator.new()
		fallback.seed = 0
		return fallback

# --- LightSystem (spec 0004 B3) : writes ctx.light ---------------------------
#
# Priority ~12. ctx.light = max(ambient daylight, brightest reachable active lamp). CompGrower reads
# it (crops dormant in the dark); unlit night work reads a low value. Lamp brightness ramps down
# linearly with distance to its radius. Batch 2 owns lamp `active`.
class LightSystem extends Systems.SimSystem:
	func _init() -> void:
		system_id = &"light"
		priority = 12

	func system_tick(world, ctx: Dictionary) -> void:
		var climate = _climate(world)
		var cell: Vector2i = Env._query_cell(world, ctx)
		var light: float = climate.daylight(
			float(world.get("lat", 0.0)), int(world.get("day", 1)), float(world.get("frac", 0.5)))

		for l in world.get("lights", []):
			if not bool(l.get("active", false)):
				continue
			var lp: Vector2i = l.get("pos", cell)
			var radius: float = float(l.get("radius", 0.0))
			if radius <= 0.0:
				continue
			var dist: float = float(abs(lp.x - cell.x) + abs(lp.y - cell.y))
			if dist <= radius:
				# Full brightness at the lamp, fading to 0 at the edge of its radius.
				var lamp_light: float = clampf(1.0 - dist / radius, 0.0, 1.0)
				light = maxf(light, lamp_light)

		ctx["light"] = clampf(light, 0.0, 1.0)

	func _climate(world):
		var c = null
		if world != null and typeof(world) == TYPE_DICTIONARY:
			c = world.get("climate", null)
		if c == null:
			c = Climate.ClimateModel_Deterministic.new()
		return c

# --- CompDeteriorate (spec 0003 #14) : outdoor wear -------------------------
#
# RimWorld analogue: CompDeteriorate — an unroofed item weathers and eventually breaks. Mirrors
# CompRottable's shape but keyed on "under a roof?" not temperature: only OUTDOOR things deteriorate,
# faster in wet weather. Advances parent.flags["deterioration"] 0..1; at 1.0 destroys the Thing.
# Indoor items never deteriorate. props: {deteriorate_days: float, wet_mult: float}.
class CompDeteriorate extends Things.ThingComp:
	func comp_tick(ctx: Dictionary) -> void:
		# Indoor / roofed things never deteriorate. Prefer ctx.indoor (written by TemperatureSystem);
		# fall back to a per-comp/parent "indoor" flag so the comp is usable standalone in tests.
		var indoor: bool = bool(ctx.get("indoor", false))
		if indoor:
			return

		var det_days: float = float(props.get("deteriorate_days", 20.0))
		var per_day: float = 1.0 / maxf(0.01, det_days)
		var mult: float = 1.0
		if bool(ctx.get("wet", false)):
			mult = float(props.get("wet_mult", 2.0))

		var cur: float = float(parent.flags.get("deterioration", 0.0)) \
			+ per_day * mult * float(ctx.get("dday", 0.0))
		cur = clampf(cur, 0.0, 1.0)
		parent.flags["deterioration"] = cur
		if cur >= 1.0:
			parent.destroyed = true

	func progress() -> float:
		return clampf(float(parent.flags.get("deterioration", 0.0)), 0.0, 1.0)

	func inspect() -> String:
		return "знос: %d%%" % int(100.0 * progress())

# --- registration helper -----------------------------------------------------
#
# Build the environment SystemRegistry in the intended tick order: Temperature (10) → Weather (11) →
# Light (12). All three run BEFORE growth/rot/deterioration consumers so ctx.temp_c / ctx.weather /
# ctx.wet / ctx.light / ctx.indoor are populated when those comps tick. Consumer systems register at
# higher priorities (>=20).
static func build_environment() -> Systems.SystemRegistry:
	var reg = Systems.SystemRegistry.new()
	reg.add(TemperatureSystem.new())
	reg.add(WeatherSystem.new())
	reg.add(LightSystem.new())
	return reg

# Self-reference alias so inner classes can reach the module-level statics/consts by name.
# (Named `Env`, not `Environment`, because `Environment` is a native Godot class and would shadow it.)
const Env = preload("res://scripts/kernel/environment.gd")

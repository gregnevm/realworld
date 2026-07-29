# RealWorld — sim/power.gd : the POWER domain of the live sim (Batch 8c — the seam sim.device_active
# was built for).
#
# Connects the kernel's power organ (kernel/power.gd: CompPowerSource / CompPowerTrader / CompBattery
# + PowerNetSystem with priority load-shedding) to the live building dicts. The kernel comps are the
# AUTHORITY on the physics (fuel drain, battery clamps, brownout order); the building dicts stay the
# persistent truth — fuel/charge mirror back onto `b` every tick, so saves, world_hash and rejoin
# carry the grid state without ever serializing a Thing.
#
# One region == one implicit net (the kernel model; RimWorld's conduit routing is deliberately out —
# the catalogue's power_conduit stays un-buildable until nets are spatial). Wind rides the REAL
# weather stream, solar rides the REAL daylight curve — both deterministic, no rng consumed.
#
# Static functions over the sim instance `s` (threats/environment pattern): no module state, no
# sim.gd preload. Thing<->Comp cycles are OWNED here: every rebuild detaches the previous fleet and
# dispose() releases the last one (tests must call s.dispose_power() before dropping a sim).
extends RefCounted

const Power = preload("res://scripts/kernel/power.gd")
const CatalogDefs = preload("res://scripts/catalog_defs.gd")

# Wind factor per weather (deterministic from the seeded weather stream): storms spin harder, fog
# stalls. Applied to kind "wind" sources (windmill AND watermill — one flow model for the slice).
const WIND_FACTOR := {
	&"clear": 1.0, &"rain": 1.15, &"snow": 0.9, &"fog": 0.7, &"cold_snap": 1.2,
}

# ---------------- fleet lifecycle ----------------
# (Re)build the Thing fleet from the placed powered buildings. Called lazily from update() when the
# building set changed (s.power_dirty). Detaches the old fleet first — the cycles die here.
static func rebuild(s) -> void:
	dispose(s)
	s.power_things = {}
	for b in s.buildings:
		var pw: Dictionary = s.building_def(String(b.kind)).get("power", {})
		if pw.is_empty():
			continue
		var cell: int = int(b.y) * s.n + int(b.x)
		var t: Variant = Power.Things.Thing.new(null)
		match str(pw.get("role", "")):
			"source":
				var props: Dictionary = pw.duplicate(true)
				if b.has("fuel"):
					props["fuel"] = float(b.fuel)   # a loaded save resumes the tank, not the def default
				t.add_comp(Power.CompPowerSource.new(props))
			"battery":
				t.add_comp(Power.CompBattery.new({"capacity": float(pw.get("capacity", 0.0)), "stored": float(b.get("charge", 0.0))}))
			"trader":
				t.add_comp(Power.CompPowerTrader.new({"draw": float(pw.get("draw", 0.0)), "priority": int(pw.get("priority", 0))}))
			_:
				continue
		s.power_things[cell] = t
	if s.power_sys == null:
		s.power_sys = Power.PowerNetSystem.new()
	s.power_dirty = false

static func dispose(s) -> void:
	for cell in s.power_things:
		s.power_things[cell].detach()
	s.power_things = {}
	s.power_active = {}
	s.power_net = {}

# ---------------- the per-tick pass (called from sim.update, after environment) ----------------
static func update(s, dt: float) -> void:
	if s.power_dirty:
		rebuild(s)
	if s.power_things.is_empty():
		return   # the shipped slice: data.gd defs declare no power -> zero cost, byte-identical
	var dday: float = dt / maxf(1.0, float(s.time.day_len))
	var ctx := {
		"light": float(s.daylight_level()),
		"wind_factor": float(WIND_FACTOR.get(s.weather, 1.0)),
		"dday": dday,
	}
	var cells: Array = s.power_things.keys()
	cells.sort()   # deterministic fleet order: battery fill / shed ties replay exactly
	var things: Array = []
	for cell in cells:
		things.append(s.power_things[cell])
	# fuel sources burn (comp_tick) + auto-refuel one unit from the open stock when the tank has room
	for cell in cells:
		var t: Variant = s.power_things[cell]
		var src: Variant = t.get_comp(Power.CompPowerSource)
		if src != null:
			t.tick(ctx)
			_auto_refuel(s, s.bgrid.get(cell, null), src)
	var prev_brownout: bool = bool(s.power_net.get("brownout", false))
	var world := {"things": things, "power": {}}
	s.power_sys.system_tick(world, ctx)
	s.power_net = world.power
	# mirror the mutable grid state back onto the building dicts (the persistent truth) + the
	# per-cell active verdict sim.device_active reads
	s.power_active = {}
	for cell in cells:
		var t: Variant = s.power_things[cell]
		var b: Variant = s.bgrid.get(cell, null)
		var src: Variant = t.get_comp(Power.CompPowerSource)
		if src != null and b != null:
			b["fuel"] = float(src.props.get("fuel", 0.0))
		var bat: Variant = t.get_comp(Power.CompBattery)
		if bat != null and b != null:
			b["charge"] = float(bat.stored)
		var tr: Variant = t.get_comp(Power.CompPowerTrader)
		if tr != null:
			s.power_active[cell] = tr.is_live()
	if bool(s.power_net.get("brownout", false)) and not prev_brownout:
		s._log("⚡ Мережа перевантажена: скинуто наймолодші споживачі.", "warn")
	elif prev_brownout and not bool(s.power_net.get("brownout", false)):
		s._log("⚡ Живлення відновлено.", "good")

# Top the tank up one stock unit per tick (bounded, deterministic; the open-stock seam pays).
# One unit of the mapped resource == one fuel unit; a generator therefore burns its resource at
# burn_per_day stock/day at steady state.
static func _auto_refuel(s, b, src) -> void:
	if b == null or str(src.kind()) != "fuel":
		return
	var fuel_max: float = float(src.props.get("fuel_max", 0.0))
	var fuel: float = float(src.props.get("fuel", 0.0))
	if fuel_max <= 0.0 or fuel > fuel_max - 1.0:
		return
	var res: String = CatalogDefs.generator_fuel(String(b.kind))
	if res == "" or s.res_amount(res) < 1:
		return
	s.stock[s.res_key(res)] -= 1
	src.props["fuel"] = minf(fuel_max, fuel + 1.0)

# The verdict sim.device_active delegates to: power-TRADER defs need the net's blessing this tick;
# everything else (all data.gd defs, sources, batteries) is always live.
static func is_active(s, b) -> bool:
	var pw: Dictionary = s.building_def(String(b.kind)).get("power", {})
	if str(pw.get("role", "")) != "trader":
		return true
	return bool(s.power_active.get(int(b.y) * s.n + int(b.x), false))

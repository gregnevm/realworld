# RealWorld — kernel/power.gd : the power grid (Batch 2), composed on Batch 1's environment.
#
# RimWorld analogue: CompPowerTrader / CompPowerPlant* / CompPowerBattery + PowerNetManager. A base is a
# single implicit power net: producers push watts in, consumers pull watts out, batteries buffer the
# difference. When demand outruns supply + stored energy the net BROWNS OUT and sheds its lowest-priority
# loads until it balances again. This module is pure Thing-comps + one SimSystem; it never edits sim.gd.
#
# --- The Batch1 <-> Batch2 seam (the whole point of this batch) ---------------------------------------
# Batch 1 (environment.gd) reads heaters/coolers/lamps as PLAIN LISTS off `world` (temp_emitters / lights),
# each entry carrying an `active` flag it does not own. THIS module owns that flag: a powered device Thing
# carries a CompPowerTrader, and PowerNetSystem flips the matching list entry's `active` to the device's
# `powered` state every tick. So a brownout turns a heater off -> its emitter goes inactive -> Batch-1
# TemperatureSystem stops heating. The two batches compose without either importing the other's internals.
#
# --- Design decision: three distinct comps, not one role-tagged comp ----------------------------------
# CompPowerTrader (consumer), CompPowerSource (producer) and CompBattery (storage) are SEPARATE comps that
# each override one hook, rather than one comp with a `role` switch. Reasons: (1) it mirrors things.gd's
# established "one comp = one orthogonal behaviour" grammar (CompRottable / CompGrower / CompQuality are all
# distinct); (2) each has a genuinely different shape — a trader has priority + on/powered, a source has a
# kind + fuel, a battery has capacity + stored — so a role switch would just be three structs under a tag;
# (3) PowerNetSystem selects participants by comp type via Thing.get_comp(), which is the kernel's idiom.
# A hybrid Thing (e.g. a fuelled generator that also draws to self-start) can carry more than one comp.
extends RefCounted

const Systems = preload("res://scripts/kernel/systems.gd")
const Things = preload("res://scripts/kernel/things.gd")

# --- CompPowerTrader (spec 0003 #15) : a consumer's participation in the net -------------------------
#
# A building that DRAWS power when switched on. Holds two booleans: `on` (the player's intent — is this
# device switched on) and `powered` (did the net actually deliver — set by PowerNetSystem each tick). A
# device only affects the world (heats, lights) when BOTH are true. `priority` orders load-shedding: on a
# brownout the net turns off the LOWEST priority (smallest number) traders first. props: {draw, priority}.
class CompPowerTrader extends Things.ThingComp:
	var on: bool = true                 # player intent: switched on
	var powered: bool = false           # net verdict this tick: did power actually arrive

	func _init(p_props: Dictionary = {}) -> void:
		super(p_props)
		on = bool(props.get("on", true))

	# Watts this consumer pulls right now (0 when switched off).
	func draw_w() -> float:
		return float(props.get("draw", 0.0)) if on else 0.0

	# Load-shed order: the net drops the smallest priority first. Default 0.
	func priority() -> int:
		return int(props.get("priority", 0))

	# True only when the device is switched on AND the net delivered power this tick.
	func is_live() -> bool:
		return on and powered

	func inspect() -> String:
		return "⚡ живлення: %s" % ("так" if is_live() else "ні")

# --- CompPowerSource (spec 0003 #15) : a generator ---------------------------------------------------
#
# Produces watts. Three kinds:
#   fuel  — constant `rated` output while it has fuel; fuel drains over dday; at 0 fuel it outputs 0.
#   solar — output = rated * ctx.light  (reads Batch-1 LightSystem's ctx.light: solar IS daylight).
#   wind  — output = rated * wind_factor (from ctx.wind_factor, default 1.0).
# props: {kind, rated, fuel?, burn_per_day?}. output_w(ctx) is pure; comp_tick only drains fuel so the
# generator's own inspect()/HUD can show remaining fuel and PowerNetSystem can re-read output next tick.
class CompPowerSource extends Things.ThingComp:
	func _init(p_props: Dictionary = {}) -> void:
		super(p_props)

	func kind() -> StringName:
		return StringName(str(props.get("kind", "fuel")))

	func has_fuel() -> bool:
		if kind() != &"fuel":
			return true
		return float(props.get("fuel", 0.0)) > 0.0

	# Watts produced given the current ctx (needs ctx.light for solar, ctx.wind_factor for wind).
	func output_w(ctx: Dictionary) -> float:
		var rated: float = float(props.get("rated", 0.0))
		match kind():
			&"solar":
				return rated * clampf(float(ctx.get("light", 0.0)), 0.0, 1.0)
			&"wind":
				return rated * maxf(0.0, float(ctx.get("wind_factor", 1.0)))
			_:  # fuel
				return rated if has_fuel() else 0.0

	# Drain fuel over elapsed days; a dry generator stays at 0 (output_w returns 0 once fuel hits 0).
	func comp_tick(ctx: Dictionary) -> void:
		if kind() != &"fuel":
			return
		var fuel: float = float(props.get("fuel", 0.0))
		if fuel <= 0.0:
			return
		var burn: float = float(props.get("burn_per_day", 1.0)) * float(ctx.get("dday", 0.0))
		props["fuel"] = maxf(0.0, fuel - burn)

	func inspect() -> String:
		match kind():
			&"solar":
				return "☀ сонячна: %dW" % int(props.get("rated", 0.0))
			&"wind":
				return "🌬 вітряк: %dW" % int(props.get("rated", 0.0))
			_:
				return "⚙ генератор: %dW (пальне %d%%)" % [int(props.get("rated", 0.0)),
					int(100.0 * clampf(float(props.get("fuel", 0.0)) / maxf(0.01, float(props.get("fuel_max", props.get("fuel", 1.0)))), 0.0, 1.0))]

# --- CompBattery (spec 0003 #15) : energy storage ----------------------------------------------------
#
# Buffers the net: charges on a surplus, discharges on a deficit. `stored` is watt-hours-equivalent in the
# same abstract unit as draw/output (the net treats one tick as the accounting window). PowerNetSystem
# calls charge()/discharge() directly; the comp only owns the clamp to [0, capacity]. props: {capacity}.
class CompBattery extends Things.ThingComp:
	var stored: float = 0.0

	func _init(p_props: Dictionary = {}) -> void:
		super(p_props)
		stored = float(props.get("stored", 0.0))

	func capacity() -> float:
		return float(props.get("capacity", 0.0))

	func charge_frac() -> float:
		var cap: float = capacity()
		return clampf(stored / cap, 0.0, 1.0) if cap > 0.0 else 0.0

	# Add up to `amount` of surplus; return what was actually absorbed (rest is spilled).
	func charge(amount: float) -> float:
		var room: float = maxf(0.0, capacity() - stored)
		var took: float = minf(maxf(0.0, amount), room)
		stored += took
		return took

	# Draw up to `amount` from storage; return what was actually delivered.
	func discharge(amount: float) -> float:
		var gave: float = minf(maxf(0.0, amount), stored)
		stored -= gave
		return gave

	func inspect() -> String:
		return "заряд: %d%%" % int(100.0 * charge_frac())

# --- PowerNetSystem (spec 0003 #15) : the net solver -------------------------------------------------
#
# Priority 15: ticks AFTER Batch-1 environment writes ctx.light (LightSystem @12) so solar reads a fresh
# daylight value, and BEFORE consumer systems (>=20) so a device's `powered`/emitter-`active` verdict is
# settled when TemperatureSystem/LightSystem-driven consumers read it next frame. Each tick:
#   1. sum producer output (fuel/solar/wind) -> supply.
#   2. gather live consumers (on) with their draw + priority.
#   3. balance: if supply >= demand, surplus charges batteries; else batteries discharge to cover the gap.
#   4. brownout: if demand still exceeds supply + battery discharge, SHED lowest-priority loads (set
#      trader.on-effective off via powered=false) until the remaining demand fits; flag world.power.brownout.
#   5. write the net snapshot to world.power and flip every powered device's emitter/light `active`.
#
# Determinism: no rng. Ties in priority break by list order (stable), which is deterministic given a stable
# `world.things`. The system reads Things from `world.things` (an Array of Things) — the host owns that list.
class PowerNetSystem extends Systems.SimSystem:
	func _init() -> void:
		system_id = &"power"
		priority = 15

	func _things(world) -> Array:
		if world != null and typeof(world) == TYPE_DICTIONARY:
			return world.get("things", [])
		return []

	func system_tick(world, ctx: Dictionary) -> void:
		var things: Array = _things(world)

		# --- 1. supply from producers ---------------------------------------------------------------
		var supply: float = 0.0
		var batteries: Array = []
		var traders: Array = []   # {trader, thing}
		for t in things:
			if t == null or t.destroyed:
				continue
			var src = t.get_comp(CompPowerSource)
			if src != null:
				supply += src.output_w(ctx)
			var bat = t.get_comp(CompBattery)
			if bat != null:
				batteries.append(bat)
			var tr = t.get_comp(CompPowerTrader)
			if tr != null:
				traders.append({"trader": tr, "thing": t})

		# --- 2. demand from switched-on consumers ---------------------------------------------------
		# Consider only traders the player has switched on; battery/net decides which actually get power.
		var live: Array = []          # traders currently in the running for power (on == true)
		for e in traders:
			var tr = e.trader
			if tr.on:
				live.append(e)
			else:
				tr.powered = false    # off by intent -> definitely not powered
		var demand: float = 0.0
		for e in live:
			demand += e.trader.draw_w()

		# total energy the batteries could discharge this window
		var battery_avail: float = 0.0
		for b in batteries:
			battery_avail += b.stored
		var battery_capacity: float = 0.0
		for b in batteries:
			battery_capacity += b.capacity()

		# --- 3+4. balance & brownout shedding -------------------------------------------------------
		var brownout: bool = false
		if demand <= supply + battery_avail:
			# The net can cover demand. Everyone switched-on is powered.
			for e in live:
				e.trader.powered = true
			var net: float = supply - demand
			if net >= 0.0:
				_charge_batteries(batteries, net)          # surplus -> storage
			else:
				_discharge_batteries(batteries, -net)      # deficit -> drain storage
		else:
			# BROWNOUT: not enough supply + storage. Shed lowest-priority loads until it fits.
			brownout = true
			var budget: float = supply + battery_avail
			# sort a copy by priority DESC so we keep the highest-priority loads; ties keep list order.
			var ordered: Array = live.duplicate()
			ordered.sort_custom(func(a, b): return a.trader.priority() > b.trader.priority())
			var kept_demand: float = 0.0
			for e in ordered:
				var d: float = e.trader.draw_w()
				if kept_demand + d <= budget + 0.0001:
					e.trader.powered = true
					kept_demand += d
				else:
					e.trader.powered = false               # shed this load
			# batteries drain to cover whatever supply couldn't of the kept demand
			var from_batteries: float = maxf(0.0, kept_demand - supply)
			_discharge_batteries(batteries, from_batteries)

		# --- 5a. net snapshot for the HUD / other systems -------------------------------------------
		var stored_now: float = 0.0
		for b in batteries:
			stored_now += b.stored
		world["power"] = {
			"supply": supply,
			"draw": demand,
			"stored": stored_now,
			"capacity": battery_capacity,
			"brownout": brownout,
		}

		# --- 5b. flip powered devices' emitter/light `active` (the Batch1<->Batch2 seam) ------------
		apply_device_states(world, things)

	# Surplus flows into batteries (fills them in list order until the surplus is spent).
	func _charge_batteries(batteries: Array, surplus: float) -> void:
		var left: float = surplus
		for b in batteries:
			if left <= 0.0:
				break
			left -= b.charge(left)

	# Deficit drains batteries (empties them in list order until the deficit is covered).
	func _discharge_batteries(batteries: Array, deficit: float) -> void:
		var left: float = deficit
		for b in batteries:
			if left <= 0.0:
				break
			left -= b.discharge(left)

	# Flip each power-linked device's Batch-1 emitter/light entry `active` to match its `powered` state.
	# A device Thing declares which list + entry it drives via flags:
	#   thing.flags["emitter"] -> a dict already present in world.temp_emitters (set active in place)
	#   thing.flags["light"]   -> a dict already present in world.lights
	# This is the ONLY place the two batches touch: power decides `powered`, environment reads `active`.
	static func apply_device_states(world, things: Array) -> void:
		for t in things:
			if t == null:
				continue
			var tr = t.get_comp(CompPowerTrader)
			if tr == null:
				continue
			var on: bool = tr.is_live()
			var em = t.flags.get("emitter", null)
			if em != null and typeof(em) == TYPE_DICTIONARY:
				em["active"] = on
			var lt = t.flags.get("light", null)
			if lt != null and typeof(lt) == TYPE_DICTIONARY:
				lt["active"] = on

# --- registration helper -----------------------------------------------------------------------------
#
# The power net registers at priority 15 — after Batch-1 environment (Temperature 10 / Weather 11 /
# Light 12) so ctx.light is fresh for solar, and before consumer systems (>=20). Callers typically build
# the environment registry, then add PowerNetSystem to it; this helper returns a standalone registry for
# tests / a power-only host.
static func build_power() -> Systems.SystemRegistry:
	var reg = Systems.SystemRegistry.new()
	reg.add(PowerNetSystem.new())
	return reg

# Self-reference alias so inner classes / statics can reach module-level statics by name.
const Power = preload("res://scripts/kernel/power.gd")

# RealWorld — kernel/systems.gd : the tick spine (SimSystem / SystemRegistry).
#
# RimWorld analogue: MapComponent / GameComponent / TickManager tick lists. The world update becomes:
# advance the clock, build the shared ctx, then tick every registered system in priority order. A
# mechanic is a system you register; the update loop itself never changes and stays deterministic.
# Each system is independently headless-testable against a plain `world` dictionary.
extends RefCounted

# One subsystem. Lower priority ticks first (so, e.g., climate feeds temperature before growth reads
# it). `world` is whatever the host passes (the sim, or a plain dict in tests); `ctx` is per-tick.
class SimSystem extends RefCounted:
	var system_id: StringName = &"system"
	var priority: int = 0

	func system_tick(_world, _ctx: Dictionary) -> void:
		pass

# Ordered collection of systems with a single tick_all entry point.
class SystemRegistry extends RefCounted:
	var systems: Array = []

	func add(s) -> void:
		systems.append(s)
		systems.sort_custom(func(a, b): return a.priority < b.priority)

	func get_system(id: StringName):
		for s in systems:
			if s.system_id == id:
				return s
		return null

	func tick_all(world, ctx: Dictionary) -> void:
		for s in systems:
			s.system_tick(world, ctx)

	func count() -> int:
		return systems.size()

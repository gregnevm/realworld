# RealWorld — kernel/needs.gd : the hero's drives (Need).
#
# RimWorld analogue: Need / Need_Food / Need_Rest. A Need is a 0..1 level that falls over time and,
# when it crosses a threshold, asks the sim for a satisfying action (eat / sleep). The tick loop
# holds a list of Needs and ticks each — generalising the sim's inline `hunger`/`rest` floats into an
# open list. Only food and rest ship now; mood / recreation are deliberately OUT of scope (excluded),
# but the interface is designed so they drop in later without touching the loop or the hero.
#
# NOTE ON SCOPE: exactly ONE pawn (the hero) owns Needs. Robots, animals and raiders do NOT — they
# are Agents (kernel/agents.gd), and additional human pawns are only ever other live players.
extends RefCounted

# One drive on the hero. fall_per_day is in level units (1.0 == full bar) per in-game day.
class Need extends RefCounted:
	var id: StringName
	var label: String
	var cur: float = 1.0
	var fall_per_day: float
	var low_threshold: float          # below this the need "wants" satisfaction
	var crit_threshold: float         # below this the hero takes damage

	func _init(p_id: StringName, p_label: String, p_cur: float, p_fall: float, p_low: float = 0.3, p_crit: float = 0.0) -> void:
		id = p_id
		label = p_label
		cur = p_cur
		fall_per_day = p_fall
		low_threshold = p_low
		crit_threshold = p_crit

	# Advance by the fraction of a day elapsed (ctx.dday). Override to add per-need modifiers.
	func need_tick(ctx: Dictionary) -> void:
		cur = clampf(cur - fall_per_day * float(ctx.get("dday", 0.0)), 0.0, 1.0)

	# Restore some level (eating a meal, finishing a sleep).
	func satisfy(amount: float) -> void:
		cur = clampf(cur + amount, 0.0, 1.0)

	func wants() -> bool:
		return cur <= low_threshold

	func critical() -> bool:
		return cur <= crit_threshold

	func percent() -> int:
		return int(round(cur * 100.0))

# Hunger. Falls steadily; a meal restores a chunk. (Mirrors the sim's 0.42/s decay generalised.)
class Need_Food extends Need:
	func _init() -> void:
		super(&"food", "Голод", 0.82, 0.63, 0.55, 0.0)

# Rest. Falls while awake; sleeping restores it fast (handled by the sim setting dday negative-ish
# via satisfy()). Mirrors the sim's 0.30/s awake decay generalised.
class Need_Rest extends Need:
	func _init() -> void:
		super(&"rest", "Відпочинок", 0.92, 0.45, 0.30, 0.0)

# Convenience: the hero's default need set.
static func default_needs() -> Array:
	return [Need_Food.new(), Need_Rest.new()]

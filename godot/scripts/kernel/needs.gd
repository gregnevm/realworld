# RealWorld — kernel/needs.gd : the hero's drives (Need) + what running on empty does to the body.
#
# RimWorld analogue: Need / Need_Food / Need_Rest, plus the malnutrition hediff a starving pawn grows
# and the exhaustion collapse of a sleepless one. A Need is a 0..1 level that falls over time and,
# when it crosses a threshold, asks the sim for a satisfying action (eat / sleep). The tick loop
# holds a list of Needs and ticks each — generalising the sim's inline `hunger`/`rest` floats into an
# open list. Only food and rest ship now; mood / recreation are deliberately OUT of scope (excluded),
# but the interface is designed so they drop in later without touching the loop or the hero.
#
# The DEPRIVATION half mirrors gear.gd's update_comfort: a single static authority
# (update_deprivation) grows/recedes the two hediffs on a HealthTracker from the need levels, so an
# empty need stops being an abstract "-hp per second" and becomes a located, inspectable condition:
# Hediff_Malnutrition is LETHAL at severity 1.0 (starvation kills); Hediff_Exhaustion caps below the
# lethal line — RimWorld-true, you COLLAPSE from sleeplessness (consciousness floor -> downed), you
# don't die of it. Which severity means death is the host's policy; the kernel only shapes the curves.
#
# NOTE ON SCOPE: exactly ONE pawn (the hero) owns Needs. Robots, animals and raiders do NOT — they
# are Agents (kernel/agents.gd), and additional human pawns are only ever other live players.
extends RefCounted

const Health = preload("res://scripts/kernel/health.gd")

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

# ============================================================================================
# DEPRIVATION HEDIFFS — what an EMPTY need does to the body (the update_comfort mirror)
# ============================================================================================

# Severity per game-day while the need sits at zero, and per game-day of recovery once it doesn't.
# Malnutrition: ~2.2 empty-stomach days to die; refeeding recovers twice as fast as it grew.
const MALNUTRITION_GAIN_PER_DAY := 0.45
const MALNUTRITION_RECOVER_PER_DAY := 0.9
# Exhaustion: ~0.8 sleepless days to collapse; any sleep clears it quickly. Capped BELOW 1.0 —
# exhaustion downs you (consciousness floor) but never kills on its own.
const EXHAUSTION_GAIN_PER_DAY := 0.9
const EXHAUSTION_RECOVER_PER_DAY := 1.8
const EXHAUSTION_SEVERITY_CAP := 0.75

# Starvation. Whole-body: weakens consciousness, manipulation and movement as it deepens. A host
# treating severity >= 1.0 as death gets the RimWorld starvation arc for free.
class Hediff_Malnutrition extends Health.Hediff:
	func _init(p_part = null) -> void:
		part = p_part
		label = "виснаження"
		severity = 0.0

	func cap_factor(cap: StringName) -> float:
		if cap == Health.CAP_CONSCIOUSNESS:
			return clampf(1.0 - severity * 0.35, 0.2, 1.0)
		if cap == Health.CAP_MANIPULATION:
			return clampf(1.0 - severity * 0.4, 0.2, 1.0)
		if cap == Health.CAP_MOVING:
			return clampf(1.0 - severity * 0.3, 0.25, 1.0)
		return 1.0

	# EXACT zero, not an epsilon: per-frame growth (~0.0015/tick) sits below any epsilon, and an
	# epsilon-gone() would sweep the hediff the tick it is born (see gear.gd Hediff_Hypothermia).
	func gone() -> bool:
		return severity <= 0.0

	func inspect() -> String:
		return "виснаження %d%%" % int(round(100.0 * severity))

# Sleep deprivation. Hammers consciousness hard enough that at the severity cap the hero drops
# (HealthTracker.downed) — a collapse where you stand, not a death sentence.
class Hediff_Exhaustion extends Health.Hediff:
	func _init(p_part = null) -> void:
		part = p_part
		label = "недосип"
		severity = 0.0

	func cap_factor(cap: StringName) -> float:
		if cap == Health.CAP_CONSCIOUSNESS:
			return clampf(1.0 - severity * 1.25, 0.05, 1.0)
		return 1.0

	func gone() -> bool:
		return severity <= 0.0   # exact zero — see Hediff_Malnutrition.gone()

	func inspect() -> String:
		return "недосип %d%%" % int(round(100.0 * severity))

# The single deprivation authority: grow/recede both hediffs on a HealthTracker from the current
# need levels (0..1). Mirrors gear.gd's update_comfort shape so hosts drive both the same way.
static func update_deprivation(tracker, food01: float, rest01: float, dday: float) -> void:
	if tracker == null:
		return
	var torso: Variant = tracker.parts.get(&"torso", null) if tracker.parts != null else null
	var maln: Variant = _find_hediff(tracker, Hediff_Malnutrition)
	var exh: Variant = _find_hediff(tracker, Hediff_Exhaustion)
	if food01 <= 0.0:
		if maln == null:
			maln = Hediff_Malnutrition.new(torso)
			tracker.hediffs.append(maln)
		maln.severity = clampf(maln.severity + MALNUTRITION_GAIN_PER_DAY * dday, 0.0, 1.0)
	elif maln != null:
		maln.severity = maxf(0.0, maln.severity - MALNUTRITION_RECOVER_PER_DAY * dday)
	if rest01 <= 0.0:
		if exh == null:
			exh = Hediff_Exhaustion.new(torso)
			tracker.hediffs.append(exh)
		exh.severity = clampf(exh.severity + EXHAUSTION_GAIN_PER_DAY * dday, 0.0, EXHAUSTION_SEVERITY_CAP)
	elif exh != null:
		exh.severity = maxf(0.0, exh.severity - EXHAUSTION_RECOVER_PER_DAY * dday)
	# Sweep fully-receded deprivation hediffs (mirrors update_comfort's own sweep).
	tracker.hediffs = tracker.hediffs.filter(func(h): return not (h is Hediff_Malnutrition or h is Hediff_Exhaustion) or not h.gone())

static func _find_hediff(tracker, cls):
	for h in tracker.hediffs:
		if is_instance_of(h, cls):
			return h
	return null

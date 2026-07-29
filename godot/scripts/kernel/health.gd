# RealWorld — kernel/health.gd : located health (BodyPart / Hediff / capacities).
#
# RimWorld analogue: Pawn_HealthTracker / Hediff / HediffSet / BodyPartDef / PawnCapacityDef. Replaces
# a single hp float on the hero with LOCATED injuries and diseases ("hediffs") sitting on body parts.
# Injuries bleed (draining blood), heal over time, and — if left untended — get infected. Diseases run
# an immunity-vs-severity race. Every hediff reduces the capacities of the part it sits on (Moving,
# Manipulation, Consciousness, BloodPumping); those capacities feed Stats via StatPart_Capacity, so a
# wounded leg slows movement and a wounded arm slows work. Medicine (tend_all) stops bleeding and
# clears infection. This is the substrate that late-game surgery, prosthetics and implants plug into.
#
# SCOPE: the hero owns one HealthTracker. Raiders are robots (simple hp), animals may use a reduced
# tracker; additional human pawns are only ever other players.
extends RefCounted

const CAP_MOVING := &"moving"
const CAP_MANIPULATION := &"manipulation"
const CAP_CONSCIOUSNESS := &"consciousness"
const CAP_BLOOD := &"blood_pumping"

# A body part: how much damage it can take, whether it is vital, and which capacities it powers.
class BodyPart extends RefCounted:
	var key: StringName
	var label: String
	var max_hp: float
	var vital: bool
	var caps: Array          # capacities this part contributes to

	func _init(p_key: StringName, p_label: String, p_max: float, p_vital: bool, p_caps: Array) -> void:
		key = p_key
		label = p_label
		max_hp = p_max
		vital = p_vital
		caps = p_caps

# --- hediffs (health differences: injuries, diseases, later implants) ---------

class Hediff extends RefCounted:
	var label: String
	var part: BodyPart
	var severity: float = 0.0
	var tended: bool = false

	func hediff_tick(_ctx: Dictionary) -> void:
		pass
	func bleed_rate() -> float:          # blood/day drained while present
		return 0.0
	func cap_factor(_cap: StringName) -> float:   # multiplier on a capacity (1.0 == no effect)
		return 1.0
	func gone() -> bool:                  # resolved -> removed next tick
		return false
	func inspect() -> String:
		return "%s (%s)" % [label, part.label if part != null else "—"]

# A wound. Bleeds until tended or nearly healed; heals over days; festers into infection if ignored.
class Hediff_Injury extends Hediff:
	var infection: float = 0.0            # 0..1; >=1 means the part is lost to infection

	func _init(p_part: BodyPart, p_severity: float, p_label: String = "рана") -> void:
		part = p_part
		severity = p_severity
		label = p_label

	func hediff_tick(ctx: Dictionary) -> void:
		var dday: float = float(ctx.get("dday", 0.0))
		var heal: float = (7.0 if tended else 4.0) * dday
		severity = maxf(0.0, severity - heal)
		# festering: a deep, untended wound grows an infection; tending drives it back down.
		if tended:
			infection = maxf(0.0, infection - 0.25 * dday)
		elif severity > 5.0:
			infection = clampf(infection + 0.18 * dday, 0.0, 1.0)

	func bleed_rate() -> float:
		if tended or severity <= 1.0:
			return 0.0
		return severity * 0.02

	func cap_factor(cap: StringName) -> float:
		if part == null or not part.caps.has(cap):
			return 1.0
		if infection >= 1.0:
			return 0.0                    # part functionally destroyed
		var dmg_frac: float = clampf(severity / part.max_hp, 0.0, 1.0)
		return clampf(1.0 - dmg_frac, 0.0, 1.0)

	func gone() -> bool:
		return severity <= 0.05 and infection <= 0.0

	func inspect() -> String:
		var s := "%s: %s тяж.%.0f" % [label, part.label, severity]
		if infection > 0.0:
			s += " · інфекція %d%%" % int(100.0 * infection)
		return s

# A sickness. Severity climbs; immunity climbs faster when tended. Beat immunity to severity to live.
class Hediff_Disease extends Hediff:
	var immunity: float = 0.0

	func _init(p_part: BodyPart, p_label: String = "хвороба") -> void:
		part = p_part
		label = p_label
		severity = 0.15

	func hediff_tick(ctx: Dictionary) -> void:
		# Immunity climbs toward 1.0 (faster when tended). The sickness keeps worsening UNTIL immunity
		# tops out — reach immunity first and you recover; if severity peaks first you go down. Tending
		# wins the race by reaching full immunity sooner, so less severity accrues on the way.
		var dday: float = float(ctx.get("dday", 0.0))
		immunity = clampf(immunity + (0.55 if tended else 0.30) * dday, 0.0, 1.2)
		if immunity < 1.0:
			severity = clampf(severity + 0.28 * dday, 0.0, 1.5)
		else:
			severity = maxf(0.0, severity - 0.6 * dday)

	func cap_factor(cap: StringName) -> float:
		if cap == CAP_CONSCIOUSNESS:
			return clampf(1.0 - severity * 0.55, 0.1, 1.0)
		return 1.0

	func gone() -> bool:
		return immunity >= 1.0 and severity <= 0.05

	func inspect() -> String:
		return "%s: тяж.%.2f / імун.%.2f" % [label, severity, immunity]

# --- the tracker --------------------------------------------------------------

class HealthTracker extends RefCounted:
	var parts: Dictionary = {}            # key -> BodyPart
	var hediffs: Array = []
	var blood: float = 1.0                # 0..1
	var downed: bool = false

	func _init() -> void:
		_add_part(BodyPart.new(&"torso", "тулуб", 40.0, true, [CAP_BLOOD]))
		_add_part(BodyPart.new(&"head", "голова", 25.0, true, [CAP_CONSCIOUSNESS]))
		_add_part(BodyPart.new(&"leg_l", "ліва нога", 30.0, false, [CAP_MOVING]))
		_add_part(BodyPart.new(&"leg_r", "права нога", 30.0, false, [CAP_MOVING]))
		_add_part(BodyPart.new(&"arm_l", "ліва рука", 30.0, false, [CAP_MANIPULATION]))
		_add_part(BodyPart.new(&"arm_r", "права рука", 30.0, false, [CAP_MANIPULATION]))

	func _add_part(p: BodyPart) -> void:
		parts[p.key] = p

	func injure(part_key: StringName, amount: float, label: String = "рана") -> void:
		if parts.has(part_key):
			hediffs.append(Hediff_Injury.new(parts[part_key], amount, label))

	func afflict(label: String = "інфекція легень") -> void:
		hediffs.append(Hediff_Disease.new(parts.get(&"torso"), label))

	# Apply medicine: tend every bleeding injury and boost immunity gain on diseases.
	func tend_all() -> int:
		var n := 0
		for h in hediffs:
			if not h.tended:
				h.tended = true
				n += 1
		return n

	func total_bleed() -> float:
		var b := 0.0
		for h in hediffs:
			b += h.bleed_rate()
		return b

	# Total live injury severity sitting on one body part. A VITAL part whose injuries reach its
	# max_hp is destroyed — the host's death policy reads exactly this number.
	func injury_on(part_key: StringName) -> float:
		var prt: Variant = parts.get(part_key, null)
		if prt == null:
			return 0.0
		var s := 0.0
		for h in hediffs:
			if h is Hediff_Injury and h.part == prt:
				s += h.severity
		return s

	# A capacity in [0,1]: product of every hediff's factor, further weakened by blood loss for the
	# capacities that depend on circulation (consciousness, movement).
	func capacity(cap: StringName) -> float:
		var f := 1.0
		for h in hediffs:
			f *= h.cap_factor(cap)
		if cap == CAP_CONSCIOUSNESS or cap == CAP_MOVING:
			f *= clampf(blood, 0.0, 1.0)
		return clampf(f, 0.0, 1.0)

	# The bundle Stats reads via ctx.capacities.
	func capacities() -> Dictionary:
		return {
			CAP_MOVING: capacity(CAP_MOVING),
			CAP_MANIPULATION: capacity(CAP_MANIPULATION),
			CAP_CONSCIOUSNESS: capacity(CAP_CONSCIOUSNESS),
			CAP_BLOOD: capacity(CAP_BLOOD),
		}

	func tick(ctx: Dictionary) -> void:
		var dday: float = float(ctx.get("dday", 0.0))
		for h in hediffs:
			h.hediff_tick(ctx)
		blood = clampf(blood - total_bleed() * dday, 0.0, 1.0)
		# slow blood regeneration once nothing is bleeding
		if total_bleed() <= 0.0:
			blood = clampf(blood + 0.15 * dday, 0.0, 1.0)
		hediffs = hediffs.filter(func(h): return not h.gone())
		# downed by blood loss or by losing consciousness (a vital-part collapse)
		downed = blood <= 0.15 or capacity(CAP_CONSCIOUSNESS) <= 0.1

# RealWorld — kernel/gear.gd : hero gear, health-services & comfort (Batch 4).
#
# RimWorld analogue: Apparel / ApparelProperties + StatWorker_ArmorRating; the temperature-comfort
# hediffs (Hypothermia / Heatstroke) with ComfortTemperature; TendUtility + Building_Bed(medical) +
# medicine QualityCategory; Need_Thirst / Need (water); scars (Hediff_Injury.becomeScar) and bionic
# implants that RESTORE a capacity via surgery on a medical bed. Everything here is one cohesive module
# built ONLY on the shipped kernel grammar (Thing/ThingComp, StatWorker/StatPart, Hediff, Need, System)
# and a plain `world` dict — it never edits sim.gd, main.gd, health.gd, needs.gd or stats.gd; it adds
# ALONGSIDE them. Five mechanics live here:
#
#   1. Apparel & armor       — CompApparel (slot / insulation / armor-by-damage-type / wear); an
#                              EquipModel equip-slot map; ArmorRating StatParts; apply_armor() mitigation.
#   2. Temperature comfort   — Hediff_Hypothermia / Hediff_Heatstroke climb out of the comfort band and
#                              recede inside it, lowering consciousness/moving; ComfortSystem + a static
#                              update_comfort() add/update the right hediff on a HealthTracker.
#   3. Medicine + medbed     — TendService.tend() needs a `medicine` resource AND a medbed Thing present;
#                              effectiveness = StatWorker(medic competence) × medicine quality.
#   4. Thirst / water        — Need_Water falls faster when hot (reads ctx.temp_c); drink() from a source;
#                              hero_needs() = default_needs() + Need_Water.
#   5. Scars & prosthetics   — Hediff_Scar (permanent, small cap penalty); resolve_to_scar() leaves a scar
#                              where a SEVERE injury healed; Hediff_Implant RESTORES a lost capacity;
#                              install_prosthetic() performs the medbed surgery.
#
# --- What it reads / writes on `world` and `ctx` (the UX/host binding surface) ----------------------
#   ctx.temp_c                       ambient °C (written by environment.TemperatureSystem) — comfort felt
#                                    temp and Need_Water drain both read it.
#   ctx.dday                         elapsed game-days this tick (hediff severity + need drain advance).
#   ctx.insulation_c                 (optional) equipped warmth °C the ComfortSystem folds into felt temp.
#   world.hero_health : HealthTracker  the tracker ComfortSystem updates with comfort hediffs.
#   world.stock : {res:StringName -> amt:int}   TendService consumes exactly one "medicine" on success.
#   world.things : Array[Things.Thing]  TendService scans for a medbed (a Thing carrying CompMedbed).
#
# --- Determinism ------------------------------------------------------------------------------------
# The only stochastic path is apply_armor()'s deflect/absorb roll and TendService's (optional) rng — both
# take a seeded RandomNumberGenerator passed in. No global randf(), no time seeds. When rng is null,
# apply_armor is fully deterministic (mitigation applied as an expected-value scale).
extends RefCounted

const Things = preload("res://scripts/kernel/things.gd")
const Stats = preload("res://scripts/kernel/stats.gd")
const Systems = preload("res://scripts/kernel/systems.gd")
const Needs = preload("res://scripts/kernel/needs.gd")
const Health = preload("res://scripts/kernel/health.gd")

# ============================================================================================
# 1. APPAREL & ARMOR (spec 0003 #8)
# ============================================================================================
#
# A worn item is a Things.Thing carrying a CompApparel. The comp declares which equip slot it fills, how
# much warmth it adds (insulation_c), and its armor ratings per damage type (0..1 = fraction mitigated).
# Wear (0..1) rises when the wearer is hit and PROPORTIONALLY degrades both armor and insulation: a rag of
# a jacket protects less and keeps you less warm. props:
#   slot         : StringName    equip slot this fills ("torso"/"legs"/"head"/…)
#   insulation_c : float         warmth °C added while worn & undamaged
#   armor        : {damage_type:StringName -> rating 0..1}   mitigation fraction per type when pristine
#   max_wear     : float         (optional, default 1.0) wear ceiling; item is ruined at this value

# Damage-type names armor is keyed on (mirrors RimWorld's sharp/blunt/heat split).
const DMG_SHARP := &"sharp"
const DMG_BLUNT := &"blunt"
const DMG_HEAT := &"heat"

class CompApparel extends Things.ThingComp:
	# Current wear 0..max_wear; 0 == pristine, max_wear == ruined. Stored on the comp (per-item state).
	var wear: float = 0.0

	func slot() -> StringName:
		return StringName(str(props.get("slot", "misc")))

	func max_wear() -> float:
		return float(props.get("max_wear", 1.0))

	# Fraction of the item's protection still intact (1.0 pristine → 0.0 ruined). Linear in wear.
	func condition() -> float:
		return clampf(1.0 - wear / maxf(0.001, max_wear()), 0.0, 1.0)

	# Warmth °C this item currently supplies (base insulation scaled by remaining condition).
	func insulation() -> float:
		return float(props.get("insulation_c", 0.0)) * condition()

	# Pristine armor rating for a damage type (0 if the item doesn't guard that type).
	func base_armor(dtype: StringName) -> float:
		var a: Dictionary = props.get("armor", {})
		return clampf(float(a.get(dtype, 0.0)), 0.0, 1.0)

	# Effective armor rating right now: pristine rating scaled by remaining condition.
	func armor(dtype: StringName) -> float:
		return base_armor(dtype) * condition()

	# Take wear from being struck. Bigger hits and sharper damage wear gear faster. Deterministic.
	func take_wear(amount: float) -> void:
		wear = clampf(wear + maxf(0.0, amount), 0.0, max_wear())

	func ruined() -> bool:
		return wear >= max_wear() - 1e-6

	func inspect() -> String:
		return "%s: знос %d%%, тепло %.0f°C" % [str(slot()), int(100.0 * (1.0 - condition())), insulation()]

# The hero equipment model: a slot -> apparel Thing map. Wearing an item into an occupied slot swaps the
# old one out (returned). Pure state container; the mitigation math lives in the module statics/StatParts.
class EquipModel extends RefCounted:
	var slots: Dictionary = {}          # StringName slot -> Things.Thing (carrying a CompApparel)

	# Fetch the CompApparel of the Thing in a slot (null if empty / no comp).
	func _apparel_in(slot: StringName):
		var t: Variant = slots.get(slot, null)
		if t == null:
			return null
		return t.get_comp(CompApparel)

	# Wear an item; returns the item previously in that slot (or null). A Thing with no CompApparel is
	# refused (returns the passed thing unchanged) — you can only equip apparel.
	func equip(thing) -> Variant:
		var ap: Variant = thing.get_comp(CompApparel) if thing != null else null
		if ap == null:
			return thing
		var slot: StringName = ap.slot()
		var prev: Variant = slots.get(slot, null)
		slots[slot] = thing
		return prev

	# Remove and return whatever occupies a slot (null if empty).
	func unequip(slot: StringName) -> Variant:
		var prev: Variant = slots.get(slot, null)
		slots.erase(slot)
		return prev

	func equipped() -> Array:
		return slots.values()

	# Sum of every worn item's current warmth (already condition-scaled).
	func total_insulation() -> float:
		var w := 0.0
		for t in slots.values():
			var ap: Variant = t.get_comp(CompApparel)
			if ap != null:
				w += ap.insulation()
		return w

	# Combined armor rating for a damage type across all worn items. Ratings STACK MULTIPLICATIVELY:
	# each layer lets through (1 - rating), so two 0.5 layers pass 0.25 (=> 0.75 combined). This keeps
	# the combined rating in [0,1) and rewards layering without ever reaching a hard 1.0 immunity.
	func armor_rating(dtype: StringName) -> float:
		var pass_through := 1.0
		for t in slots.values():
			var ap: Variant = t.get_comp(CompApparel)
			if ap != null:
				pass_through *= (1.0 - ap.armor(dtype))
		return clampf(1.0 - pass_through, 0.0, 1.0)

# --- Armor as a StatPart -------------------------------------------------------------------
#
# ArmorRating_<type> is a stat like any other: base 0, folded through the equipped model's combined
# rating for that type. Exposing it through the pipeline means quality/research parts can modify armor
# later with zero caller changes. Reads ctx.equip (an EquipModel) and the part's own damage type.
class StatPart_Armor extends Stats.StatPart:
	var dtype: StringName

	func _init(p_dtype: StringName) -> void:
		dtype = p_dtype

	func transform(val: float, ctx: Dictionary) -> float:
		var eq: Variant = ctx.get("equip", null)
		if eq == null:
			return val
		# Armor is additive over the base (base is typically 0); combined rating stacks in [0,1).
		return clampf(val + eq.armor_rating(dtype), 0.0, 1.0)

	func explain(ctx: Dictionary) -> String:
		var eq: Variant = ctx.get("equip", null)
		var r: float = eq.armor_rating(dtype) if eq != null else 0.0
		return "+броня %s %.2f" % [str(dtype), r]

# Build the ArmorRating StatWorker for a damage type (base 0 + the equipped model's combined rating).
static func armor_worker(dtype: StringName) -> Stats.StatWorker:
	return Stats.StatWorker.new(StringName("armor_rating_%s" % dtype), 0.0, [StatPart_Armor.new(dtype)])

# Apply the equipped armor to an incoming hit, returning the damage that GETS THROUGH (mitigated). Also
# wears the struck gear. Two-tier RimWorld-style resolution when an rng is given: roll < rating/2 fully
# DEFLECTS (0 through); else the hit is ABSORBED by `rating` (fraction removed). Without an rng the result
# is the deterministic expected value: through = dmg × (1 - rating) — the mean of deflect+absorb. Either
# way, higher combined rating (and lower wear) => less damage through.
static func apply_armor(dmg: float, dtype: StringName, equip: EquipModel, rng: RandomNumberGenerator = null) -> float:
	if equip == null or dmg <= 0.0:
		return maxf(0.0, dmg)
	var rating: float = equip.armor_rating(dtype)
	# Struck gear on this slot-line wears: sharper/bigger hits wear faster. Wear every worn layer a little.
	var wear_amt: float = clampf(dmg * 0.01 * (1.0 + rating), 0.0, 0.5)
	for t in equip.equipped():
		var ap: Variant = t.get_comp(CompApparel)
		if ap != null and ap.base_armor(dtype) > 0.0:
			ap.take_wear(wear_amt)
	if rng == null:
		# Deterministic expected value: mean of (deflect 0) and (absorb dmg*(1-rating)) weighted so the
		# expectation equals dmg*(1-rating). Simplest faithful mean: through = dmg * (1 - rating).
		return maxf(0.0, dmg * (1.0 - rating))
	var roll: float = rng.randf()
	if roll < rating * 0.5:
		return 0.0                       # clean deflection
	return maxf(0.0, dmg * (1.0 - rating))

# ============================================================================================
# 2. TEMPERATURE COMFORT (spec 0003 A9)
# ============================================================================================
#
# Two hediffs track being out of the comfort band. Severity climbs while the FELT temperature (ambient +
# equipped warmth) is beyond the band edge, proportional to how far past it, and recedes back toward 0
# while inside the band. Worsening lowers consciousness (both) and moving (hypothermia) via cap_factor;
# gone() at severity ≈ 0 so the tracker sweeps a recovered hediff. Felt temp is defined in update_comfort.

# The comfortable felt-temperature band (°C). Outside it a comfort hediff grows.
const COMFORT_MIN_C := 12.0
const COMFORT_MAX_C := 30.0
# How fast severity moves per game-day per °C past the band edge, and how fast it recedes inside the band.
const COMFORT_GAIN_PER_C_DAY := 0.05
# Recovery is deliberately MUCH faster than onset (full severity clears in ~half a day by a fire):
# frostbite takes hours, warming up takes minutes — the asymmetry is what makes stepping out into a
# lethal winter recoverable, so heat sources read as sanctuaries rather than slow-drip medicine.
const COMFORT_RECOVER_PER_DAY := 2.0

class Hediff_Hypothermia extends Health.Hediff:
	func _init(p_part = null) -> void:
		part = p_part
		label = "переохолодження"
		severity = 0.0

	# Consciousness and movement both slow as you freeze (worse than heatstroke on movement).
	func cap_factor(cap: StringName) -> float:
		if cap == Health.CAP_CONSCIOUSNESS:
			return clampf(1.0 - severity * 0.6, 0.15, 1.0)
		if cap == Health.CAP_MOVING:
			return clampf(1.0 - severity * 0.5, 0.2, 1.0)
		return 1.0

	# EXACT zero, not an epsilon: at per-frame dday (~0.003) one tick of growth sits far below any
	# epsilon, so an epsilon-gone() would sweep the hediff the same tick it is born and severity
	# could never accumulate. Receding already reaches literal 0.0 (maxf-floored), so the sweep
	# still collects fully-recovered hediffs.
	func gone() -> bool:
		return severity <= 0.0

	func inspect() -> String:
		return "переохолодження %d%%" % int(round(100.0 * severity))

class Hediff_Heatstroke extends Health.Hediff:
	func _init(p_part = null) -> void:
		part = p_part
		label = "тепловий удар"
		severity = 0.0

	func cap_factor(cap: StringName) -> float:
		if cap == Health.CAP_CONSCIOUSNESS:
			return clampf(1.0 - severity * 0.6, 0.15, 1.0)
		return 1.0

	func gone() -> bool:
		return severity <= 0.0   # exact zero — see Hediff_Hypothermia.gone()

	func inspect() -> String:
		return "тепловий удар %d%%" % int(round(100.0 * severity))

# The single comfort authority: given a felt temperature, add/update the right hediff on a HealthTracker
# (and recede/clear the wrong one). Used by ComfortSystem and directly by tests.
#   tracker    : Health.HealthTracker  the hero's tracker.
#   temp_c     : float                 ambient °C.
#   insulation : float                 equipped warmth °C (raises felt temp; from EquipModel.total_insulation).
#   dday       : float                 elapsed game-days.
#   gain_scale : float                 host pacing of the ONSET only (default 1.0 = the kernel curve).
#                                      A host whose game-day is short (the live sim's day is 150 s) slows
#                                      the exposure clock here; recovery stays at its kernel speed, so
#                                      warming up remains the fast half of the asymmetry.
# Felt temp = ambient + insulation warmth (warmth only helps against cold; it also nudges felt temp up
# toward heatstroke when already hot, exactly like wearing a parka in summer — the model is symmetric).
static func update_comfort(tracker, temp_c: float, insulation: float, dday: float, gain_scale: float = 1.0) -> void:
	if tracker == null:
		return
	var felt: float = temp_c + insulation
	var torso: Variant = tracker.parts.get(&"torso", null) if tracker.parts != null else null
	var hypo: Variant = _find_hediff(tracker, Hediff_Hypothermia)
	var heat: Variant = _find_hediff(tracker, Hediff_Heatstroke)

	if felt < COMFORT_MIN_C:
		var past: float = COMFORT_MIN_C - felt
		if hypo == null:
			hypo = Hediff_Hypothermia.new(torso)
			tracker.hediffs.append(hypo)
		hypo.severity = clampf(hypo.severity + COMFORT_GAIN_PER_C_DAY * gain_scale * past * dday, 0.0, 1.0)
		if heat != null:
			heat.severity = maxf(0.0, heat.severity - COMFORT_RECOVER_PER_DAY * dday)
	elif felt > COMFORT_MAX_C:
		var past2: float = felt - COMFORT_MAX_C
		if heat == null:
			heat = Hediff_Heatstroke.new(torso)
			tracker.hediffs.append(heat)
		heat.severity = clampf(heat.severity + COMFORT_GAIN_PER_C_DAY * gain_scale * past2 * dday, 0.0, 1.0)
		if hypo != null:
			hypo.severity = maxf(0.0, hypo.severity - COMFORT_RECOVER_PER_DAY * dday)
	else:
		# Inside the band: both comfort hediffs recede.
		if hypo != null:
			hypo.severity = maxf(0.0, hypo.severity - COMFORT_RECOVER_PER_DAY * dday)
		if heat != null:
			heat.severity = maxf(0.0, heat.severity - COMFORT_RECOVER_PER_DAY * dday)
	# Sweep any comfort hediff that has fully receded (mirrors HealthTracker.tick's filter).
	tracker.hediffs = tracker.hediffs.filter(func(h): return not (h is Hediff_Hypothermia or h is Hediff_Heatstroke) or not h.gone())

static func _find_hediff(tracker, cls):
	for h in tracker.hediffs:
		if is_instance_of(h, cls):
			return h
	return null

# A SimSystem that keeps the hero's comfort hediffs in sync each tick. Priority 25: AFTER environment
# writes ctx.temp_c (Temperature=10/Weather=11/Light=12) and production (20), before consumers read the
# tracker. Reads world.hero_health, ctx.temp_c, ctx.insulation_c (equipped warmth), ctx.dday.
class ComfortSystem extends Systems.SimSystem:
	func _init() -> void:
		system_id = &"comfort"
		priority = 25

	func system_tick(world, ctx: Dictionary) -> void:
		if typeof(world) != TYPE_DICTIONARY:
			return
		var tracker: Variant = world.get("hero_health", null)
		if tracker == null:
			return
		var temp_c: float = float(ctx.get("temp_c", 20.0))
		var insulation: float = float(ctx.get("insulation_c", 0.0))
		var dday: float = float(ctx.get("dday", 0.0))
		Gear.update_comfort(tracker, temp_c, insulation, dday)

# ============================================================================================
# 3. MEDICINE + MEDBED (spec 0003 #5 — K)
# ============================================================================================
#
# HealthTracker.tend_all() stays intact (it is the raw "flag every hediff tended" primitive). This adds a
# SERVICE layer on top: real tending in the shipped game needs (a) a `medicine` resource in world.stock
# AND (b) a medbed Thing present (a Thing carrying CompMedbed). Effectiveness = a StatWorker on the medic's
# competence × the medbed's medicine quality (a StatPart). Effectiveness scales how much the tend delivers;
# ok=false with NO effect and NO medicine consumed when either resource is missing. Exactly one medicine is
# consumed on success.

# A medical bed. Its `med_quality` (0..6, like CompQuality tiers) feeds tend effectiveness. props:
#   med_quality : int  quality tier of the medicine/facility (higher => better tend). Default звичайна(2).
class CompMedbed extends Things.ThingComp:
	func med_quality() -> int:
		return clampi(int(props.get("med_quality", 2)), 0, 6)

	# Quality multiplier, mirroring CompQuality.mult(): жахлива 0.60 .. звичайна 0.90 .. легендарна 1.50.
	func quality_mult() -> float:
		return 0.6 + 0.15 * med_quality()

	func inspect() -> String:
		return "медліжко (якість %d)" % med_quality()

# A StatPart that scales tend effectiveness by the medbed's medicine quality (reads ctx.med_quality_mult).
class StatPart_MedQuality extends Stats.StatPart:
	func transform(val: float, ctx: Dictionary) -> float:
		return val * float(ctx.get("med_quality_mult", 1.0))

	func explain(ctx: Dictionary) -> String:
		return "×медикаменти %.2f" % float(ctx.get("med_quality_mult", 1.0))

# The tending service. All statics — no per-instance state.
class TendService extends RefCounted:
	# Base tend effectiveness at medic_level 0 with звичайна medicine, before competence scaling.
	const TEND_BASE := 0.5
	# Per-level medic competence bonus to effectiveness (additive before the quality multiply).
	const MEDIC_PER_LEVEL := 0.06

	# Find a medbed among world.things (a Thing carrying CompMedbed). Null if none present.
	static func _find_medbed(world):
		if typeof(world) != TYPE_DICTIONARY:
			return null
		for t in world.get("things", []):
			if t == null or t.destroyed:
				continue
			var mb: Variant = t.get_comp(CompMedbed)
			if mb != null:
				return mb
		return null

	# Effectiveness of a tend: (base + competence bonus) × medicine quality, through the stat pipeline.
	# Deterministic (no rng). Higher medic_level OR higher medicine quality => higher effectiveness.
	static func effectiveness(medic_level: float, med_quality_mult: float) -> float:
		var base: float = TEND_BASE + MEDIC_PER_LEVEL * maxf(0.0, medic_level)
		var worker := Stats.StatWorker.new(&"tend_effectiveness", base, [StatPart_MedQuality.new()])
		return maxf(0.0, worker.value({"med_quality_mult": med_quality_mult}))

	# Perform a tend. Requires a `medicine` resource in world.stock AND a medbed Thing present. Returns
	# {tended:int, effectiveness:float, ok:bool}. On failure (missing medicine, missing medbed, OR nothing to
	# tend) ok=false, tended=0, effectiveness=0, and NOTHING is consumed and NO hediff is touched. On success:
	# flags every untended
	# hediff tended (like tend_all), consumes EXACTLY ONE medicine, and scales the delivered infection/
	# immunity/bleed relief by effectiveness (a better medic/medicine drives infection down and immunity up
	# harder this tend). rng is accepted for signature symmetry but tending is deterministic.
	static func tend(tracker, world, medic_level: float, _rng: RandomNumberGenerator = null) -> Dictionary:
		var fail := {"tended": 0, "effectiveness": 0.0, "ok": false}
		if tracker == null or typeof(world) != TYPE_DICTIONARY:
			return fail
		var stock: Dictionary = world.get("stock", {})
		if int(stock.get(&"medicine", 0)) < 1:
			return fail                              # no medicine -> no tend, nothing consumed
		var medbed: Variant = _find_medbed(world)
		if medbed == null:
			return fail                              # no medbed -> no tend, nothing consumed
		# Nothing-to-tend guard: only spend a scarce medicine when this tend will actually DO something —
		# an untended hediff to flag, OR an injury/disease whose infection/immunity a relief delta can move.
		# A full-health hero (empty tracker) or one whose hediffs are all tended-and-fully-relieved gets the
		# fail dict with nothing consumed, so the caller can distinguish it from a real tend.
		var has_work := false
		for h in tracker.hediffs:
			if not h.tended:
				has_work = true
				break
			if h is Health.Hediff_Injury and h.infection > 0.0:
				has_work = true
				break
			elif h is Health.Hediff_Disease and h.immunity < 1.2:
				has_work = true
				break
		if not has_work:
			return fail                              # nothing to tend -> no medicine wasted
		var eff: float = Gear.TendService.effectiveness(medic_level, medbed.quality_mult())
		# Deliver the tend: flag hediffs tended AND apply an effectiveness-scaled immediate relief so a
		# better tend measurably outperforms a worse one this very tick.
		var n := 0
		for h in tracker.hediffs:
			if not h.tended:
				h.tended = true
				n += 1
			if h is Health.Hediff_Injury:
				h.infection = maxf(0.0, h.infection - 0.2 * eff)
			elif h is Health.Hediff_Disease:
				h.immunity = clampf(h.immunity + 0.2 * eff, 0.0, 1.2)
		# consume exactly one medicine on success
		stock[&"medicine"] = int(stock.get(&"medicine", 0)) - 1
		if not world.has("stock"):
			world["stock"] = stock
		return {"tended": n, "effectiveness": eff, "ok": true}

# ============================================================================================
# 4. THIRST / WATER (spec 0003 A3)
# ============================================================================================
#
# A third hero need. Falls like the others but FASTER when hot: above ~25 °C the drain scales up with the
# heat, so a desert day parches you quicker. Drink sources (river/well/stored) satisfy it by different
# amounts. hero_needs() = default_needs() + Need_Water so a host can swap it in with no loop change.

# °C above which thirst starts draining faster, and how much extra drain per °C past it (fraction of base).
const WATER_HEAT_THRESHOLD_C := 25.0
const WATER_HEAT_PER_C := 0.06

# How much a drink from each source restores (river cleanest & most; stored least — mirrors carry limits).
const DRINK_VALUES := {&"river": 0.7, &"well": 0.6, &"stored": 0.4}

class Need_Water extends Needs.Need:
	func _init() -> void:
		super(&"water", "Спрага", 0.9, 0.7, 0.35, 0.0)

	# Falls faster when hot: base drain × (1 + heat surcharge above the threshold). Reads ctx.temp_c.
	func need_tick(ctx: Dictionary) -> void:
		var dday: float = float(ctx.get("dday", 0.0))
		var temp_c: float = float(ctx.get("temp_c", 20.0))
		var heat_mult: float = 1.0
		if temp_c > Gear.WATER_HEAT_THRESHOLD_C:
			heat_mult += (temp_c - Gear.WATER_HEAT_THRESHOLD_C) * Gear.WATER_HEAT_PER_C
		cur = clampf(cur - fall_per_day * heat_mult * dday, 0.0, 1.0)

# Drink from a source, satisfying the water need by that source's value. Unknown source falls back to
# a small sip. Returns the amount restored (for a HUD toast).
static func drink(need, source_kind: StringName) -> float:
	var amount: float = float(DRINK_VALUES.get(source_kind, 0.3))
	need.satisfy(amount)
	return amount

# The hero's full need set including thirst: food + rest + water.
static func hero_needs() -> Array:
	var ns: Array = Needs.default_needs()
	ns.append(Need_Water.new())
	return ns

# ============================================================================================
# 5. SCARS & PROSTHETICS (spec 0003 A11)
# ============================================================================================
#
# A scar is a PERMANENT hediff: never gone(), a small fixed cap penalty on its part. A SEVERE injury that
# heals leaves a scar — resolve_to_scar() is a non-destructive post-heal sweep: it does NOT mutate
# Hediff_Injury; it watches for injuries that WERE severe and have now healed away, and drops a Hediff_Scar
# on the same part. A prosthetic is a production RecipeDef (crafted like any item) + a Hediff_Implant that
# RESTORES a capacity (cap_factor 1.0) — cancelling the part loss from an injury/scar. install_prosthetic()
# is the medbed surgery that fits it: it removes the damage hediffs on the part and adds the implant.

# Severity a wound must have reached to leave a scar once it heals.
const SCAR_SEVERITY_THRESHOLD := 8.0
# The fixed capacity penalty a scar imposes on its part's capacities (multiplier < 1.0).
const SCAR_CAP_PENALTY := 0.85

class Hediff_Scar extends Health.Hediff:
	func _init(p_part = null, p_label: String = "шрам") -> void:
		part = p_part
		label = p_label
		severity = 1.0            # nominal; a scar's effect is a fixed factor, not a decaying severity

	func hediff_tick(_ctx: Dictionary) -> void:
		pass                      # permanent: severity never changes

	# A small, fixed penalty on every capacity the scarred part powers.
	func cap_factor(cap: StringName) -> float:
		if part == null or not part.caps.has(cap):
			return 1.0
		return SCAR_CAP_PENALTY

	func gone() -> bool:
		return false              # scars are forever

	func inspect() -> String:
		return "%s: %s (назавжди)" % [label, part.label if part != null else "—"]

# An implant/prosthetic hediff that RESTORES a capacity: it forces cap_factor 1.0 on the capacities of the
# part it occupies, cancelling any loss the injury/scar imposed there. Installed via install_prosthetic.
# `restores` optionally narrows which capacities it restores (empty == all of the part's capacities).
class Hediff_Implant extends Health.Hediff:
	var restores: Array = []       # StringName caps this implant restores; empty == the part's caps

	func _init(p_part = null, p_label: String = "протез", p_restores: Array = []) -> void:
		part = p_part
		label = p_label
		severity = 0.0
		restores = p_restores

	func hediff_tick(_ctx: Dictionary) -> void:
		pass

	# Neutral by design: a fitted prosthetic contributes a 1.0 factor for EVERY capacity (capacity()
	# multiplies factors, so 1.0 leaves the product untouched) — the actual restoration happens in
	# install_prosthetic(), which removes the competing injury/scar. `restores` stays as data for that
	# surgery; it does not modulate the factor.
	func cap_factor(_cap: StringName) -> float:
		return 1.0

	func gone() -> bool:
		return false              # a fitted prosthetic is permanent

	func inspect() -> String:
		return "%s: %s (відновлено)" % [label, part.label if part != null else "—"]

# Post-heal sweep that leaves a permanent Hediff_Scar wherever a SEVERE wound healed away. Non-destructive
# to Hediff_Injury: it never mutates the injury; it remembers (in tracker meta) which body parts have
# carried a wound at/above the scar threshold, and when such a part no longer holds a live injury it drops
# one Hediff_Scar there (once). Idempotent — safe to call every tick after HealthTracker.tick(). Returns
# the number of scars newly created.
#
# Because HealthTracker.tick() sweeps a fully-healed injury out of `hediffs`, we must record the severe
# part BEFORE it disappears — hence the persistent `scar_watch` set on the tracker meta.
static func resolve_to_scar(tracker) -> int:
	if tracker == null:
		return 0
	# scar_watch: {part -> true} parts that have carried a severe (threshold+) injury and owe a scar.
	if not tracker.has_meta("scar_watch"):
		tracker.set_meta("scar_watch", {})
	var watch: Dictionary = tracker.get_meta("scar_watch")

	# 1) Register any body part currently holding a severe injury.
	for h in tracker.hediffs:
		if h is Health.Hediff_Injury and h.part != null and h.severity >= SCAR_SEVERITY_THRESHOLD:
			watch[h.part] = true

	# 2) A watched part with NO live injury left has healed -> owes a scar (unless it already has one, or an
	#    implant has replaced the part). Place it, then clear the watch for that part.
	var made := 0
	for prt in watch.keys():
		var has_live_injury := false
		var has_scar := false
		var has_implant := false
		for h in tracker.hediffs:
			if h.part != prt:
				continue
			if h is Health.Hediff_Injury:
				has_live_injury = true
			elif h is Hediff_Scar:
				has_scar = true
			elif h is Hediff_Implant:
				has_implant = true
		if has_live_injury:
			continue                         # still wounded; wait for it to heal
		if not has_scar and not has_implant and prt != null:
			tracker.hediffs.append(Hediff_Scar.new(prt))
			made += 1
		watch.erase(prt)                     # debt settled (scarred, or superseded by a scar/implant)
	return made

# The medbed surgery that fits a prosthetic. Removes the competing damage hediffs (injuries AND scars) on
# the target part so nothing drags the capacity down, then adds the implant that holds the capacity at 1.0.
# Returns true on success. Proves out: a capacity lost to an injury/scar is fully restored afterwards.
#   tracker  : Health.HealthTracker
#   part_key : StringName            which body part to operate on
#   implant  : Hediff_Implant        the prosthetic to fit (its .part is set to the target part here)
static func install_prosthetic(tracker, part_key: StringName, implant) -> bool:
	if tracker == null or implant == null or not tracker.parts.has(part_key):
		return false
	var prt: Variant = tracker.parts.get(part_key)
	# Remove injuries and scars sitting on this part (surgery replaces the ruined part).
	tracker.hediffs = tracker.hediffs.filter(func(h):
		var on_part: bool = (h.part == prt)
		var is_damage: bool = (h is Health.Hediff_Injury) or (h is Hediff_Scar)
		return not (on_part and is_damage))
	implant.part = prt
	tracker.hediffs.append(implant)
	return true

# --- registration helper -----------------------------------------------------
#
# ComfortSystem registers at priority 25 — after environment (10/11/12) and production (20), so it reads a
# settled ctx.temp_c. This helper returns a standalone registry for tests / a comfort-only host.
static func build_comfort() -> Systems.SystemRegistry:
	var reg := Systems.SystemRegistry.new()
	reg.add(ComfortSystem.new())
	return reg

# Self-reference alias so inner classes / statics can reach module-level statics/consts by name.
const Gear = preload("res://scripts/kernel/gear.gd")

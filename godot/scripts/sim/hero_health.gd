# RealWorld — sim/hero_health.gd : the HERO-HEALTH domain of the live sim.
#
# Wires the kernel's located-health substrate (kernel/health.gd tracker + kernel/gear.gd comfort +
# kernel/needs.gd deprivation) into the playable slice, replacing the old single-float `player.hp`
# arithmetic. The tracker on `s.health` is the ONE source of truth for the pawn's body: combat hits
# land as located injuries (a wounded leg slows you, a wounded arm works slower), injuries bleed and
# fester, empty needs grow malnutrition/exhaustion, and the region's REAL climate grows hypothermia/
# heatstroke — which is what finally gives campfires, heaters and walls their teeth. `player.hp`
# survives as a DERIVED readout (distance to the nearest death channel) for the HUD/save shape.
#
# Static functions over the sim instance `s` (the threats.gd/environment.gd pattern): the module
# holds NO state and never preloads sim.gd (no preload cycle); sim.gd keeps one-line delegates.
#
# Determinism contract: the only roll here is the hit-location draw, and it comes from s.threat_rng
# (the same seeded stream the combat that caused the hit consumed) — twin instances fed the same
# commands land the same wounds. Death policy (WHICH severity kills) lives here, sim-side; the
# kernel only shapes the curves.
extends RefCounted

const Health = preload("res://scripts/kernel/health.gd")
const Gear = preload("res://scripts/kernel/gear.gd")
const Needs = preload("res://scripts/kernel/needs.gd")
const GameData = preload("res://scripts/data.gd")
const CatalogDefs = preload("res://scripts/catalog_defs.gd")

# Fraction of post-armor damage that lands as injury severity (part max_hp ~25..40, raider dmg
# ~7..25: ×0.55 keeps early fights survivable and late fights lethal without armor).
const INJURY_SCALE := 0.55
# RimWorld-style coverage: most hits land on the torso, headshots are rare and dangerous.
const PART_WEIGHTS := [
	[&"torso", 0.40], [&"head", 0.10],
	[&"arm_l", 0.125], [&"arm_r", 0.125], [&"leg_l", 0.125], [&"leg_r", 0.125],
]
# Alert thresholds: a condition toasts once at onset and once more when it turns severe.
const ALERT_ONSET := 0.15
const ALERT_SEVERE := 0.5
# Exposure pacing (playability): the kernel comfort curve is per GAME-DAY, and the live game-day is
# only 150 s — at the raw curve an unprepared pawn froze in 86–229 real seconds on EVERY spawn preset
# (Kyiv day 1 ≈ 115 s), before a new player could read the feed. 0.4 slows only the ONSET (recovery
# keeps the kernel's fast warm-up): idle death in deep winter now takes ~1.3–2 game-days (Reykjavik
# → Kyiv), enough to light a fire and wall a room. Shelter + heat is still the only real answer.
const EXPOSURE_PACE := 0.4

# ---------------- lifecycle ----------------
static func ensure(s) -> void:
	if s.health == null:
		s.health = Health.HealthTracker.new()

static func reset(s) -> void:
	s.health = Health.HealthTracker.new()
	s.health_alerts = {}

# ---------------- the per-tick pass (called from sim._update_player) ----------------
static func update(s, dt: float) -> void:
	ensure(s)
	var tracker: Variant = s.health
	var p: Dictionary = s.player
	var dday: float = dt / maxf(1.0, float(s.time.day_len))
	var was_downed: bool = bool(tracker.downed)
	# 1) empty needs become located conditions (starvation kills; sleeplessness collapses)
	Needs.update_deprivation(tracker, float(p.hunger) / 100.0, float(p.rest) / 100.0, dday)
	# 2) the region's real climate bites: felt °C = tile temp (indoor buffering + emitters) + gear
	Gear.update_comfort(tracker, s.hero_temp_c(), s.hero_insulation_c(), dday, EXPOSURE_PACE)
	# 3) injuries heal/bleed/fester, blood moves, downed recomputes
	tracker.tick({"dday": dday})
	Gear.resolve_to_scar(tracker)
	# 4) sleeping in a bed tends wounds (stops bleeding, fights infection) — the bed's medical role.
	# The TEND EVENT (fresh hediffs just flagged) also consumes ONE medicine when the open stock has
	# it: a kernel-TendService-style relief burst (infection down, immunity up), scaled by medicine
	# quality × the bed's medbed multiplier. Bounded: one consumption per batch of new hediffs.
	var bed_mult: float = _bed_mult(s)
	if bool(p.sleeping) and bed_mult > 0.0:
		var tended: int = tracker.tend_all()
		if tended > 0:
			var med := _consume_medicine(s)
			if med == "":
				s._log("🩹 Сон у ліжку: рани оброблено (%d)." % tended, "good")
			else:
				var eff: float = Gear.TendService.effectiveness(0.0, float(CatalogDefs.MED_RELIEF[med]) * bed_mult)
				for h in tracker.hediffs:
					if h is Health.Hediff_Injury:
						h.infection = maxf(0.0, float(h.infection) - 0.2 * eff)
					elif h is Health.Hediff_Disease:
						h.immunity = clampf(float(h.immunity) + 0.2 * eff, 0.0, 1.2)
				s._log("💊 %s: рани оброблено як слід (еф. %.2f)." % [CatalogDefs.res_label(med), eff], "good")
	# 5) death policy: any channel at its ceiling ends the pawn
	var cause: String = death_cause(tracker)
	if cause != "" and not s.dead:
		p.hp = 0.0
		_epitaph(s, cause)
		s._log("☠ Причина смерті: %s." % cause, "bad")
		s._on_death()
		return
	# 6) collapse handling: an unconscious pawn drops orders and sleeps where they fall — enforced
	# every tick while down (unconsciousness IS sleep), so nothing else can un-sleep the body
	if tracker.downed:
		p.action = null
		p.sleeping = true
		if not was_downed:
			s._log("😵 Знепритомнів: тіло не тримає. Пішак беззахисний, доки не отямиться.", "bad")
	elif was_downed:
		p.sleeping = false
		s._log("🌤 Отямився.", "good")
	# 7) the derived readout the HUD bar / save shape keep using
	p.hp = summary_hp(tracker)
	_update_alerts(s, tracker)

# ---------------- combat entry (called from threats.gd) ----------------
# `amt` is POST-armor damage. The hit lands on a weighted-random body part (threat_rng stream).
static func damage(s, amt: float, label: String = "удар") -> void:
	if amt <= 0.0:
		return
	ensure(s)
	var roll: float = s.threat_rng.randf()
	var part: StringName = PART_WEIGHTS[PART_WEIGHTS.size() - 1][0]
	for w in PART_WEIGHTS:
		roll -= float(w[1])
		if roll < 0.0:
			part = w[0]
			break
	s.health.injure(part, amt * INJURY_SCALE, label)
	# a single blow can already be the killing one (vital part smashed) — verdict immediately
	var cause: String = death_cause(s.health)
	if cause != "" and not s.dead:
		s.player.hp = 0.0
		_epitaph(s, cause)
		s._log("☠ Причина смерті: %s." % cause, "bad")
		s._on_death()
		return
	s.player.hp = summary_hp(s.health)

# ---------------- readouts ----------------
static func is_downed(s) -> bool:
	return s.health != null and bool(s.health.downed)

# Movement scale from the Moving capacity (wounded legs / blood loss / freezing slow you down).
# Full health == exactly 1.0 so the shipped movement feel is untouched.
static func move_mult(s) -> float:
	if s.health == null:
		return 1.0
	return clampf(0.25 + 0.75 * float(s.health.capacity(Health.CAP_MOVING)), 0.25, 1.0)

# Work-TIME multiplier (>= 1.0): Manipulation (wounded arms) × a Consciousness haze factor (deep
# cold, disease, starvation) — RimWorld's GlobalWorkSpeed shape. Full health == exactly 1.0.
static func work_mult(s) -> float:
	if s.health == null:
		return 1.0
	var hands: float = 0.35 + 0.65 * float(s.health.capacity(Health.CAP_MANIPULATION))
	var haze: float = 0.5 + 0.5 * float(s.health.capacity(Health.CAP_CONSCIOUSNESS))
	return 1.0 / clampf(hands * haze, 0.2, 1.0)

# Melee output scale from Manipulation (a mangled arm swings weaker). Full health == 1.0.
static func melee_mult(s) -> float:
	if s.health == null:
		return 1.0
	return clampf(0.4 + 0.6 * float(s.health.capacity(Health.CAP_MANIPULATION)), 0.4, 1.0)

# The HUD bar: 100 × distance to the NEAREST death channel (blood-out, a destroyed vital part, or
# a lethal condition at 1.0). A limb wound also dips the bar — at HALF its damage fraction, so it
# reads on the readout but can never reach the death line by itself. Exhaustion joins the scan but
# its kernel cap keeps it sub-lethal — it can floor the bar at 25, never at 0.
static func summary_hp(tracker) -> float:
	if tracker == null:
		return 100.0
	var worst: float = 1.0 - float(tracker.blood)
	for key in tracker.parts:
		var prt: Variant = tracker.parts[key]
		var frac: float = clampf(float(tracker.injury_on(key)) / maxf(1.0, float(prt.max_hp)), 0.0, 1.0)
		worst = maxf(worst, frac if bool(prt.vital) else frac * 0.5)
	for h in tracker.hediffs:
		if _is_condition(h):
			worst = maxf(worst, clampf(float(h.severity), 0.0, 1.0))
	return clampf(100.0 * (1.0 - worst), 0.0, 100.0)

# "" while alive; otherwise the channel that ended the pawn (the sim logs it verbatim).
static func death_cause(tracker) -> String:
	if tracker == null:
		return ""
	if float(tracker.blood) <= 0.001:
		return "втрата крові"
	for key in [&"torso", &"head"]:
		var prt: Variant = tracker.parts.get(key, null)
		if prt != null and float(tracker.injury_on(key)) >= float(prt.max_hp):
			return "смертельні рани (%s)" % String(prt.label)
	for h in tracker.hediffs:
		if float(h.severity) < 1.0:
			continue
		if h is Needs.Hediff_Malnutrition:
			return "голодна смерть"
		if h is Gear.Hediff_Hypothermia:
			return "переохолодження"   # a cause, not a gendered verb («замерз»)
		if h is Gear.Hediff_Heatstroke:
			return "тепловий удар"
		if h is Health.Hediff_Disease:
			return "хвороба (%s)" % String(h.label)
	return ""

# Value-data inspect lines for the HUD (worst first, capped) + the downed flag.
const CONDITION_SHOW_MIN := 0.05
static func condition_lines(s, cap: int = 4) -> Array:
	if s.health == null:
		return []
	var rows: Array = []
	for h in s.health.hediffs:
		# 0..1-scale condition hediffs are born at ~0 and tick up: below the readout floor they are
		# noise on the Vitals line («переохолодження 0%»), not a state the player can act on yet
		if _is_condition(h) and float(h.severity) < CONDITION_SHOW_MIN:
			continue
		rows.append([clampf(float(h.severity), 0.0, 1.0), String(h.inspect())])
	rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out: Array = []
	for i in mini(cap, rows.size()):
		out.append(String(rows[i][1]))
	return out

# Value-data rows for the HUD (worst first, capped): a kind tag + the kernel label + a 0..1 urgency
# the view renders as icon + label + percent (R11). Injuries normalise by the part's max hp.
static func condition_rows(s, cap: int = 4) -> Array:
	if s.health == null:
		return []
	var rows: Array = []
	for h in s.health.hediffs:
		if _is_condition(h) and float(h.severity) < CONDITION_SHOW_MIN:
			continue   # the same readout floor as condition_lines: below it, noise — not a state
		var kind := "condition"
		var urgency: float = clampf(float(h.severity), 0.0, 1.0)
		var part_label: String = String(h.part.label) if h.part != null else ""
		var extra := 0.0
		if h is Gear.Hediff_Hypothermia:
			kind = "hypothermia"
		elif h is Gear.Hediff_Heatstroke:
			kind = "heatstroke"
		elif h is Needs.Hediff_Malnutrition:
			kind = "malnutrition"
		elif h is Needs.Hediff_Exhaustion:
			kind = "exhaustion"
		elif h is Gear.Hediff_Scar:
			kind = "scar"
			urgency = 0.0
		elif h is Gear.Hediff_Implant:
			kind = "implant"
			urgency = 0.0
		elif h is Health.Hediff_Disease:
			kind = "disease"
			extra = float(h.immunity)
		elif h is Health.Hediff_Injury:
			kind = "injury"
			urgency = clampf(float(h.severity) / maxf(1.0, float(h.part.max_hp) if h.part != null else 30.0), 0.0, 1.0)
			extra = float(h.infection)
		rows.append({"kind": kind, "label": String(h.label), "part": part_label, "sev": urgency, "extra": extra})
	rows.sort_custom(func(a, b): return float(a.sev) > float(b.sev))
	return rows.slice(0, cap)

# ---------------- serialization (save / travel / rejoin) ----------------
# Value-dict of the whole tracker. Typed by a `t` tag per hediff; scar_watch travels as part keys so
# a severe wound still owes its scar after a save/load or a capsule flight.
static func to_dict(s) -> Dictionary:
	ensure(s)
	var tracker: Variant = s.health
	var hediffs: Array = []
	for h in tracker.hediffs:
		var part_key: String = String(h.part.key) if h.part != null else ""
		if h is Needs.Hediff_Malnutrition:
			hediffs.append({"t": "malnutrition", "sev": float(h.severity)})
		elif h is Needs.Hediff_Exhaustion:
			hediffs.append({"t": "exhaustion", "sev": float(h.severity)})
		elif h is Gear.Hediff_Hypothermia:
			hediffs.append({"t": "hypothermia", "sev": float(h.severity)})
		elif h is Gear.Hediff_Heatstroke:
			hediffs.append({"t": "heatstroke", "sev": float(h.severity)})
		elif h is Gear.Hediff_Scar:
			hediffs.append({"t": "scar", "part": part_key, "label": String(h.label)})
		elif h is Gear.Hediff_Implant:
			hediffs.append({"t": "implant", "part": part_key, "label": String(h.label), "restores": _cap_names(h.restores)})
		elif h is Health.Hediff_Disease:
			hediffs.append({"t": "disease", "part": part_key, "label": String(h.label),
				"sev": float(h.severity), "imm": float(h.immunity), "tended": bool(h.tended)})
		elif h is Health.Hediff_Injury:
			hediffs.append({"t": "injury", "part": part_key, "label": String(h.label),
				"sev": float(h.severity), "inf": float(h.infection), "tended": bool(h.tended)})
	var watch: Array = []
	if tracker.has_meta("scar_watch"):
		for prt in (tracker.get_meta("scar_watch") as Dictionary).keys():
			if prt != null:
				watch.append(String(prt.key))
	return {"blood": float(tracker.blood), "hediffs": hediffs, "scar_watch": watch}

# Inverse of to_dict. An EMPTY dict is the legacy path: old saves carried only the hp float, so a
# lived-in body is approximated as one tended torso wound proportional to the missing hp.
static func apply_dict(s, d: Dictionary) -> void:
	var tracker: Variant = Health.HealthTracker.new()
	if d.is_empty():
		var legacy_hp: float = clampf(float(s.player.get("hp", 100.0)), 0.0, 100.0)
		if legacy_hp < 100.0:
			tracker.injure(&"torso", (100.0 - legacy_hp) * 0.25, "давні рани")
			tracker.hediffs[0].tended = true
	else:
		tracker.blood = clampf(float(d.get("blood", 1.0)), 0.0, 1.0)
		for hd in (d.get("hediffs", []) as Array):
			_apply_hediff(tracker, hd as Dictionary)
		var watch: Dictionary = {}
		for key in (d.get("scar_watch", []) as Array):
			var prt: Variant = tracker.parts.get(StringName(str(key)), null)
			if prt != null:
				watch[prt] = true
		if not watch.is_empty():
			tracker.set_meta("scar_watch", watch)
	tracker.tick({"dday": 0.0})   # settle downed/blood clamps from the restored state
	s.health = tracker
	s.health_alerts = {}
	# player.hp is deliberately NOT recomputed here: a restore must be VERBATIM (serialize ->
	# load -> serialize stays bit-stable even when a test forced the float out of sync with the
	# tracker). The very next live tick rewrites hp from the tracker anyway.

static func _apply_hediff(tracker, hd: Dictionary) -> void:
	var part: Variant = tracker.parts.get(StringName(str(hd.get("part", ""))), null)
	var torso: Variant = tracker.parts.get(&"torso", null)
	var h: Variant = null
	match str(hd.get("t", "")):
		"malnutrition":
			h = Needs.Hediff_Malnutrition.new(torso)
		"exhaustion":
			h = Needs.Hediff_Exhaustion.new(torso)
		"hypothermia":
			h = Gear.Hediff_Hypothermia.new(torso)
		"heatstroke":
			h = Gear.Hediff_Heatstroke.new(torso)
		"scar":
			h = Gear.Hediff_Scar.new(part, str(hd.get("label", "шрам")))
		"implant":
			h = Gear.Hediff_Implant.new(part, str(hd.get("label", "протез")), _cap_list(hd.get("restores", [])))
		"disease":
			h = Health.Hediff_Disease.new(part if part != null else torso, str(hd.get("label", "хвороба")))
			h.immunity = float(hd.get("imm", 0.0))
			h.tended = bool(hd.get("tended", false))
		"injury":
			if part == null:
				return
			h = Health.Hediff_Injury.new(part, float(hd.get("sev", 0.0)), str(hd.get("label", "рана")))
			h.infection = float(hd.get("inf", 0.0))
			h.tended = bool(hd.get("tended", false))
		_:
			return   # unknown tag from a newer save: skip rather than corrupt
	if hd.has("sev"):
		h.severity = float(hd.get("sev", h.severity))
	tracker.hediffs.append(h)

static func _cap_names(caps: Array) -> Array:
	var out: Array = []
	for c in caps:
		out.append(String(c))
	return out

static func _cap_list(names: Array) -> Array:
	var out: Array = []
	for c in names:
		out.append(StringName(str(c)))
	return out

# Spawn-time onboarding hint: if the felt °C is already outside the comfort band, say so before the
# first hediff does (a Kyiv game starts on day 1 == deep winter; the player must learn "fire first").
static func spawn_hint(s) -> void:
	var felt: float = s.hero_felt_c()
	if felt < Gear.COMFORT_MIN_C:
		if s.get("use_inventory") == true:   # spec 0009: the campfire is an item in the hotbar, not a build-bar key
			s._log("❄ Тут холодно (%.0f°C): постав багаття з хотбару (слот 1), потім стіни з дверима навколо — у приміщенні тепло тримається." % felt, "warn")   # gdlint: ignore=max-line-length
		else:
			s._log("❄ Тут холодно (%.0f°C): розпали багаття (9), а тоді обнеси клітинку стінами (1) з дверима (2) — у приміщенні тепло тримається." % felt, "warn")   # gdlint: ignore=max-line-length
	elif felt > Gear.COMFORT_MAX_C:
		s._log("🥵 Тут спекотно (%.0f°C). Приміщення дає прохолоду." % felt, "warn")

# ---------------- internals ----------------
# The death screen's value data: what ended the pawn, when, and since when it lived.
static func _epitaph(s, cause: String) -> void:
	s.last_death = {"cause": cause, "day": int(s.time.day), "born": int(s.player.get("born", int(s.time.day)))}

# 0.0 == no bed near; else the best nearby bed's tend-quality multiplier (a plain bed is 1.0, the
# catalogue medical beds carry medbed_mult > 1 through the def seam).
static func _bed_mult(s) -> float:
	var best := 0.0
	for b in s.buildings:
		var def: Dictionary = s.building_def(String(b.kind))
		if def.get("bed", false) and s._dist(s.player.px, s.player.py, b.x + 0.5, b.y + 0.5) < 1.6:
			best = maxf(best, float(def.get("medbed_mult", 1.0)))
	return best

# Consume the best medicine in the open stock ("" = none / flag off). Deterministic preference order.
static func _consume_medicine(s) -> String:
	if not bool(s.use_catalog):
		return ""
	for med in ["medicine", "herbal_medicine"]:
		if int(s.res_amount(med)) >= 1:
			s.stock[s.res_key(med)] -= 1
			return med
	return ""

static func _is_condition(h) -> bool:
	return h is Needs.Hediff_Malnutrition or h is Needs.Hediff_Exhaustion \
		or h is Gear.Hediff_Hypothermia or h is Gear.Hediff_Heatstroke or h is Health.Hediff_Disease

# One toast at onset, one at severe, per condition episode; stages recede silently so the next
# episode alerts again. Bleeding and infection are single-stage alerts of the same shape.
static func _update_alerts(s, tracker) -> void:
	_alert_stage(s, "hypo", _severity_of(tracker, Gear.Hediff_Hypothermia),
		"❄ Переохолодження — шукай тепло (вогонь, приміщення).", "❄ Сильне переохолодження: рухи мляві!")
	_alert_stage(s, "heat", _severity_of(tracker, Gear.Hediff_Heatstroke),
		"🥵 Перегрів — сховайся у приміщенні чи дочекайся ночі.", "🥵 Тепловий удар близько!")
	_alert_stage(s, "maln", _severity_of(tracker, Needs.Hediff_Malnutrition),
		"🍖 Виснаження: без їжі організм слабне.", "🍖 Голодна смерть близько!")
	_alert_stage(s, "exh", _severity_of(tracker, Needs.Hediff_Exhaustion),
		"💤 Валишся з ніг — потрібен сон.", "")
	var bleed_stage: int = 1 if float(tracker.total_bleed()) > 0.0 else 0
	if bleed_stage > int(s.health_alerts.get("bleed", 0)):
		s._log("🩸 Кровотеча! Сон у ліжку зупинить її.", "warn")
	s.health_alerts["bleed"] = bleed_stage
	var inf_stage: int = 0
	for h in tracker.hediffs:
		if h is Health.Hediff_Injury and float(h.infection) >= 0.3:
			inf_stage = 1
			break
	if inf_stage > int(s.health_alerts.get("inf", 0)):
		s._log("🦠 Рана інфікується — відлежись у ліжку.", "bad")
	s.health_alerts["inf"] = inf_stage

static func _severity_of(tracker, cls) -> float:
	for h in tracker.hediffs:
		if is_instance_of(h, cls):
			return float(h.severity)
	return 0.0

static func _alert_stage(s, key: String, severity: float, onset_msg: String, severe_msg: String) -> void:
	var stage: int = 0
	if severity >= ALERT_SEVERE:
		stage = 2
	elif severity >= ALERT_ONSET:
		stage = 1
	var prev: int = int(s.health_alerts.get(key, 0))
	if stage > prev:
		if stage >= 2 and severe_msg != "":
			s._log(severe_msg, "bad")
		elif prev < 1:
			s._log(onset_msg, "warn")
	s.health_alerts[key] = stage

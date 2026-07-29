# RealWorld — sim/director.gd : the DIRECTOR domain of the live sim — kernel/balance.gd finally
# drives the game it was assessing.
#
# Until now Balance.assess() fed only the HUD threat readout while raid pacing ran on a flat sim
# timer — the one dishonest cell the mechanics audit found. This module makes the claim true: the
# kernel Balance rolls its incident roster (MTB math, threat scaling, the decide() AI seam) every
# tick from its OWN seeded stream, and the sim ENACTS what fires:
#   • raid       -> arms the threats.gd cycle (warning banner, 12 s later a wave SIZED by threat
#                   points — wealth, days survived and clan pressure finally escalate the waves);
#   • disease    -> a real Hediff_Disease on the live health tracker (the bed-tend immunity race);
#   • cold_snap  -> apply_temp_anomaly (the spec-E6 seam, built for exactly this call);
#   • cargo     -> a supply drop into the stock (generosity-scaled; лор: дрон Старого світу).
# Incidents WITHOUT a live substrate (infestation/manhunter need fauna, quest needs a quest system)
# still roll — their draws keep the stream cadence — but their payloads are dropped, not faked.
#
# Determinism: one seeded stream (region seed ^ salt, seeded in sim/environment.gd next to the
# weather/threat streams), cursor serialized in the runtime record — twins and rejoiners replay the
# same storyteller. Balance's knobs (difficulty/generosity) stay at defaults until an AI policy
# lands, so they carry no save state yet.
#
# Static functions over the sim instance `s` (threats/environment/power pattern).
extends RefCounted

const KernelBalance = preload("res://scripts/kernel/balance.gd")
const Social = preload("res://scripts/social.gd")

# Payloads the live slice can actually enact — the substrate-honesty filter.
const LIVE_INCIDENTS := ["raid", "disease", "cold_snap", "cargo"]
# Seconds between the raid warning and the wave (the shipped slice's own lead time).
const RAID_WARN_LEAD := 12.0
# threat_big cadence weight: kernel MTB 2.4 days is siege pacing; ×2 ≈ a raid every ~1.2 game-days,
# close to the shipped slice's rhythm while keeping the MTB curve (and its escalation) in charge.
const THREAT_BIG_WEIGHT := 2.0

# The Balance `world` dict for a LIVE sim — the one sim-side builder (hud_model delegates here for
# real sims, so the HUD readout and the live pacing can never disagree on the numbers).
static func world_of(s) -> Dictionary:
	var bs: Array = []
	for b in s.buildings:
		bs.append({"value": float(s.building_def(String(b.kind)).get("hp", 50.0)) * 0.5})
	return {
		"buildings": bs,
		"stock": s.stock,
		"items": (s.player.get("items", []) as Array),
		"threat_active": bool(s.raid.get("active", false)) or bool(s.raid.get("warned", false)),
	}

static func _ctx_of(s, dday: float) -> Dictionary:
	var pressure := 1.0
	var faction := "невідомі мародери"
	if s.social != null:
		pressure = Social.raid_pressure(s.social)
		faction = Social.raid_faction_name(s.social, int(s.raid.get("wave", 0)) + 1)
	return {
		"day": int(s.time.day),
		"dday": dday,
		"hostile_pressure": pressure,
		"hostile_faction": faction,
	}

# ---------------- the per-tick pass (called from sim.update, before threats) ----------------
static func update(s, dt: float) -> void:
	if s.balance == null:
		s.balance = KernelBalance.Balance.new()
		s.balance.category_weight[KernelBalance.CAT_THREAT_BIG] = THREAT_BIG_WEIGHT
	var dday: float = dt / maxf(1.0, float(s.time.day_len))
	var fired: Array = s.balance.tick(world_of(s), _ctx_of(s, dday), s.director_rng)
	for payload in fired:
		apply(s, payload)

# Enact one incident payload (public so tests can force incidents without rigging the stream).
static func apply(s, payload: Dictionary) -> void:
	var kind := str(payload.get("incident", ""))
	if not LIVE_INCIDENTS.has(kind):
		return   # no live substrate yet (fauna/quests) — dropped, not faked
	match kind:
		"raid":
			_apply_raid(s, payload)
		"disease":
			_apply_disease(s, payload)
		"cold_snap":
			s.apply_temp_anomaly(-float(payload.get("drop_c", 15.0)), float(payload.get("days", 2.0)))
			s._log("🌨 Різке похолодання: −%d°C на %d дн. Тримай тепло." % [int(payload.get("drop_c", 15.0)), int(payload.get("days", 2))], "warn")
		"cargo":
			_apply_cargo(s, payload)

# Arm the shipped raid cycle: warning banner now, the wave in RAID_WARN_LEAD seconds, its size
# carried by the payload (threat-point-scaled) for threats.spawn_wave to honour.
static func _apply_raid(s, payload: Dictionary) -> void:
	var r: Dictionary = s.raid
	if bool(r.get("active", false)) or bool(r.get("warned", false)):
		return   # one battle at a time (decide()'s allow_big also gates this upstream)
	r["director"] = payload.duplicate(true)
	r["warned"] = true
	r["next"] = float(r.get("timer", 0.0)) + RAID_WARN_LEAD
	s.banner = "⚠ НАБЛИЖАЄТЬСЯ РЕЙД"
	s._log("⚠ Режисер: рейдери на підході — укріплюй базу!", "warn")

static func _apply_disease(s, payload: Dictionary) -> void:
	if s.health == null:
		return
	for h in s.health.hediffs:
		if h is HealthKernel.Hediff_Disease:
			return   # one sickness at a time: the immunity race is the drama, not a stack
	s.health.afflict(str(payload.get("label", "інфекція легень")))
	s._log("🦠 Хвороба: %s. Сон у ліжку жене імунітет." % str(payload.get("label", "")), "bad")

static func _apply_cargo(s, payload: Dictionary) -> void:
	var got: Array = []
	var drop: Dictionary = payload.get("stock", {})
	for res in drop:
		var added: int = s.deposit(str(res), int(drop[res]))
		if added > 0:
			got.append("%s%d" % [CatalogDefs.res_icon(str(res)), added])
	if not got.is_empty():
		s._log("📦 Вантажний дрон Старого світу скинув: %s." % " ".join(got), "good")

const HealthKernel = preload("res://scripts/kernel/health.gd")
const CatalogDefs = preload("res://scripts/catalog_defs.gd")

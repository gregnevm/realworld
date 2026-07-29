# RealWorld — headless tests for the mechanics kernel (spec 0003).
# Run: Godot_console.exe --headless --path godot -s res://tests/run_kernel_tests.gd
extends "res://tests/harness.gd"

const Defs = preload("res://scripts/kernel/defs.gd")
const Things = preload("res://scripts/kernel/things.gd")
const Stats = preload("res://scripts/kernel/stats.gd")
const Systems = preload("res://scripts/kernel/systems.gd")
const Climate = preload("res://scripts/kernel/climate.gd")
const Needs = preload("res://scripts/kernel/needs.gd")
const Health = preload("res://scripts/kernel/health.gd")
const Balance = preload("res://scripts/kernel/balance.gd")
const Agents = preload("res://scripts/kernel/agents.gd")
const Env = preload("res://scripts/kernel/environment.gd")
const Power = preload("res://scripts/kernel/power.gd")
const Production = preload("res://scripts/kernel/production.gd")
const Gear = preload("res://scripts/kernel/gear.gd")
const Combat = preload("res://scripts/kernel/combat.gd")

var _fresh_eq_things: Array = []   # Things built by _fresh_eq(), detached at the end of _t_gear (cleanup only)

func _init() -> void:
	print("== RealWorld kernel tests (spec 0003) ==")
	_t_defs()
	_t_thing_comps()
	_t_stats()
	_t_systems()
	_t_climate()
	_t_needs()
	_t_deprivation()
	_t_health()
	_t_balance()
	_t_agents()
	_t_environment()
	_t_power()
	_t_production()
	_t_gear()
	_t_combat()
	_t_integration()
	finish()


func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r

# Cleanup only: break the Thing<->ThingComp RefCounted cycle (Thing.comps[] <-> comp.parent) for every
# Thing a test created, so nothing leaks at exit. See Things.Thing.detach().
func _detach_all(things: Array) -> void:
	for t in things:
		if t != null:
			t.detach()

# ---------------- Def / DefDatabase ----------------
func _t_defs() -> void:
	var db = Defs.DefDatabase.new()
	db.register(Defs.Def.new(&"building", &"wall", {"max_hp": 120.0, "cost": {"stone": 5}}))
	db.register(Defs.Def.new(&"building", &"turret", {"max_hp": 90.0}))
	db.register(Defs.Def.new(&"item", &"axe", {"gather_mult": 1.6}))
	ok(db.count() == 3, "3 defs registered")
	ok(db.all_of_type(&"building").size() == 2, "two buildings indexed by type")
	ok(db.def_of(&"axe") != null and float(db.def_of(&"axe").field(&"gather_mult")) == 1.6, "def_of returns typed field")
	ok(db.get_def(&"missing") == null, "missing def returns null")
	# content pack injection (the backend seam)
	db.load_pack([{"def_type": "item", "id": "pick", "data": {"gather_mult": 1.9}}])
	ok(db.has(&"pick"), "load_pack injects a def")

# ---------------- Thing + ThingComp ----------------
func _t_thing_comps() -> void:
	# rot: destroyed when warm, preserved when frozen (refrigeration)
	var food = Things.Thing.new(Defs.Def.new(&"item", &"berries", {"max_hp": 10.0}))
	food.add_comp(Things.CompRottable.new({"rot_days": 4.0}))
	var warm := {"temp_c": 20.0, "dday": 0.5}
	for i in 20:
		food.tick(warm)
	ok(food.destroyed, "rottable food spoils in the warm")
	var frozen_food = Things.Thing.new(null)
	frozen_food.add_comp(Things.CompRottable.new({"rot_days": 4.0}))
	var cold := {"temp_c": -5.0, "dday": 0.5}
	for i in 40:
		frozen_food.tick(cold)
	ok(not frozen_food.destroyed and frozen_food.get_comp(Things.CompRottable).progress() == 0.0, "freezing halts rot")

	# grower: matures in a viable band + light, dormant at night
	var crop = Things.Thing.new(null)
	crop.add_comp(Things.CompGrower.new({"grow_days": 3.0, "temp_min": 5.0, "temp_max": 40.0, "min_light": 0.3}))
	var g = crop.get_comp(Things.CompGrower)
	var day_ctx := {"temp_c": 22.0, "light": 1.0, "dday": 0.25}
	for i in 16:   # 16 * 0.25 = 4 days elapsed vs 3-day grow time
		crop.tick(day_ctx)
	ok(g.mature(), "crop matures under good conditions")
	var crop2 = Things.Thing.new(null)
	crop2.add_comp(Things.CompGrower.new({"grow_days": 3.0}))
	var night_ctx := {"temp_c": 22.0, "light": 0.0, "dday": 0.25}
	for i in 8:
		crop2.tick(night_ctx)
	ok(crop2.get_comp(Things.CompGrower).growth() == 0.0, "crop is dormant at night")

	# quality: deterministic per seed, monotone multiplier, better maker trends higher
	var lo = Things.Thing.new(null); lo.add_comp(Things.CompQuality.new({"maker_level": 0.0}))
	var hi = Things.Thing.new(null); hi.add_comp(Things.CompQuality.new({"maker_level": 20.0}))
	lo.post_make(_rng(7)); hi.post_make(_rng(7))
	var lo2 = Things.Thing.new(null); lo2.add_comp(Things.CompQuality.new({"maker_level": 0.0}))
	lo2.post_make(_rng(7))
	ok(lo.get_comp(Things.CompQuality).level() == lo2.get_comp(Things.CompQuality).level(), "quality roll is deterministic per seed")
	ok(hi.get_comp(Things.CompQuality).level() >= lo.get_comp(Things.CompQuality).level(), "higher maker level trends to higher quality")
	ok(hi.get_comp(Things.CompQuality).mult() >= 0.6 and hi.get_comp(Things.CompQuality).mult() <= 1.5, "quality multiplier in [0.6,1.5]")
	_detach_all([food, frozen_food, crop, crop2, lo, hi, lo2])

# ---------------- Stat pipeline ----------------
func _t_stats() -> void:
	var w = Stats.StatWorker.new(&"melee_damage", 12.0, [Stats.StatPart_Quality.new(), Stats.StatPart_Capacity.new(&"manipulation")])
	var full := {"quality_mult": 1.5, "capacities": {"manipulation": 1.0}}
	ok(is_equal_approx(w.value(full), 18.0), "base 12 × quality 1.5 × cap 1.0 = 18")
	var hurt := {"quality_mult": 1.5, "capacities": {"manipulation": 0.5}}
	ok(is_equal_approx(w.value(hurt), 9.0), "injured manipulation halves the same stat")
	ok(w.value(hurt) < w.value(full), "capacity loss strictly lowers the stat")
	ok(w.explain(full).begins_with("base 12.0"), "explain lists the base and parts")

# ---------------- System registry ----------------
func _t_systems() -> void:
	var reg = Systems.SystemRegistry.new()
	var a = _OrderSys.new(&"c", 30)
	var b = _OrderSys.new(&"a", 10)
	var c = _OrderSys.new(&"b", 20)
	reg.add(a); reg.add(b); reg.add(c)
	var world := {"order": []}
	reg.tick_all(world, {})
	ok(world.order == ["a", "b", "c"], "systems tick in ascending priority order")
	ok(reg.get_system(&"b") != null and reg.count() == 3, "registry lookup + count")

# a tiny SimSystem subclass that records its id when ticked (defined via file-local extends)
class _OrderSys extends Systems.SimSystem:
	func _init(p_id: StringName, p_pri: int) -> void:
		system_id = p_id
		priority = p_pri
	func system_tick(world, _ctx: Dictionary) -> void:
		world.order.append(String(system_id))

# ---------------- Climate from real geography ----------------
func _t_climate() -> void:
	var cm = Climate.ClimateModel_Deterministic.new()
	# equator is warmer than the pole at the same instant
	var eq: float = cm.temperature_c(0.0, 0.0, 180, 0.5)
	var pole: float = cm.temperature_c(85.0, 0.0, 180, 0.5)
	ok(eq > pole, "equator warmer than pole (%.1f > %.1f)" % [eq, pole])
	# Kyiv: deep winter (day 1) colder than high summer (day 180)
	var winter: float = cm.temperature_c(50.45, 30.52, 1, 0.5)
	var summer: float = cm.temperature_c(50.45, 30.52, 180, 0.5)
	ok(summer > winter and winter < 5.0 and summer > 12.0, "Kyiv summer warmer than winter (%.1f > %.1f)" % [summer, winter])
	# southern hemisphere is flipped: day 1 (N winter) is SUMMER at lat -33
	var south_jan: float = cm.temperature_c(-33.9, 151.2, 1, 0.5)
	var south_jul: float = cm.temperature_c(-33.9, 151.2, 180, 0.5)
	ok(south_jan > south_jul, "southern hemisphere season is flipped (%.1f > %.1f)" % [south_jan, south_jul])
	# daylight: dark at midnight, bright at noon
	ok(cm.daylight(50.45, 180, 0.0) < cm.daylight(50.45, 180, 0.5), "midnight darker than noon")
	# deterministic
	ok(cm.temperature_c(50.45, 30.52, 100, 0.4) == cm.temperature_c(50.45, 30.52, 100, 0.4), "temperature is deterministic")

# ---------------- Needs ----------------
func _t_needs() -> void:
	var ns := Needs.default_needs()
	ok(ns.size() == 2, "hero has food + rest needs")
	var food = Needs.Need_Food.new()
	var start: float = food.cur
	for i in 3:
		food.need_tick({"dday": 0.2})
	ok(food.cur < start, "food need falls over time")
	food.satisfy(0.5)
	ok(food.cur > (start - 0.4), "eating restores the food need")
	var low = Needs.Need_Food.new()
	low.cur = 0.4
	ok(low.wants() and not low.critical(), "low food 'wants' a meal but is not yet critical")

# ---------------- Deprivation hediffs (empty needs -> located conditions) ----------------
func _t_deprivation() -> void:
	# starvation: an empty stomach grows malnutrition toward the lethal 1.0; refeeding recedes it
	var h = Health.HealthTracker.new()
	for i in 4:
		Needs.update_deprivation(h, 0.0, 1.0, 0.5)
	var maln = Needs._find_hediff(h, Needs.Hediff_Malnutrition)
	ok(maln != null and maln.severity > 0.0, "empty food grows malnutrition (тяж.%.2f)" % (maln.severity if maln else -1.0))
	ok(h.capacity(Health.CAP_MANIPULATION) < 1.0 and h.capacity(Health.CAP_MOVING) < 1.0, "malnutrition weakens work and movement")
	for i in 3:
		Needs.update_deprivation(h, 0.0, 1.0, 1.0)
	maln = Needs._find_hediff(h, Needs.Hediff_Malnutrition)
	ok(maln != null and is_equal_approx(maln.severity, 1.0), "starvation saturates at the lethal 1.0 (host's death line)")
	for i in 6:
		Needs.update_deprivation(h, 1.0, 1.0, 0.5)
	ok(Needs._find_hediff(h, Needs.Hediff_Malnutrition) == null, "refeeding clears malnutrition entirely")

	# exhaustion: sleeplessness collapses consciousness (downed) but is CAPPED below lethal
	var h2 = Health.HealthTracker.new()
	for i in 8:
		Needs.update_deprivation(h2, 1.0, 0.0, 0.5)
	var exh = Needs._find_hediff(h2, Needs.Hediff_Exhaustion)
	ok(exh != null and is_equal_approx(exh.severity, Needs.EXHAUSTION_SEVERITY_CAP), "exhaustion saturates at its sub-lethal cap")
	ok(h2.capacity(Health.CAP_CONSCIOUSNESS) <= 0.1, "capped exhaustion floors consciousness (collapse)")
	h2.tick({"dday": 0.01})
	ok(h2.downed, "the tracker reads the collapse as downed")
	for i in 2:
		Needs.update_deprivation(h2, 1.0, 1.0, 0.5)
	ok(Needs._find_hediff(h2, Needs.Hediff_Exhaustion) == null, "sleep clears exhaustion quickly")

	# injury_on: the vital-part destruction number the host death policy reads
	var h3 = Health.HealthTracker.new()
	h3.injure(&"torso", 25.0)
	h3.injure(&"torso", 10.0)
	h3.injure(&"leg_l", 5.0)
	ok(is_equal_approx(h3.injury_on(&"torso"), 35.0), "injury_on sums live severity per part")
	ok(is_equal_approx(h3.injury_on(&"head"), 0.0), "injury_on is zero for an unhurt part")

	# REGRESSION (live-sim integration): at PER-FRAME dday (~0.003) one tick of growth sits below any
	# epsilon — an epsilon-based gone() swept a just-born condition the same tick and severity could
	# never accumulate. Conditions must survive fine-grained ticking AND the tracker.tick sweep.
	var h4 = Health.HealthTracker.new()
	for i in 30:
		Needs.update_deprivation(h4, 0.0, 1.0, 0.003)
		h4.tick({"dday": 0.003})
	var fine_maln = Needs._find_hediff(h4, Needs.Hediff_Malnutrition)
	ok(fine_maln != null and fine_maln.severity > 0.03, "malnutrition accumulates at per-frame dday (тяж.%.3f)" % (fine_maln.severity if fine_maln else -1.0))

# ---------------- Health (injuries / disease / capacities) ----------------
func _t_health() -> void:
	# a half-damaged leg halves the Moving capacity, which halves MoveSpeed via a StatPart
	var h = Health.HealthTracker.new()
	h.injure(&"leg_l", 15.0, "поріз")
	var move: float = h.capacity(Health.CAP_MOVING)
	ok(move > 0.0 and move < 1.0, "wounded leg lowers Moving capacity (%.2f)" % move)
	var speed = Stats.StatWorker.new(&"move", 3.4, [Stats.StatPart_Capacity.new(Health.CAP_MOVING)])
	ok(speed.value({"capacities": h.capacities()}) < 3.4, "lowered Moving reduces MoveSpeed")

	# an untended wound bleeds and drains blood; medicine stops the bleed and blood recovers
	var h2 = Health.HealthTracker.new()
	h2.injure(&"torso", 20.0, "рвана рана")
	ok(h2.total_bleed() > 0.0, "untended wound bleeds")
	for i in 3:
		h2.tick({"dday": 0.1})
	ok(h2.blood < 1.0, "bleeding drains blood")
	var bled: float = h2.blood
	ok(h2.tend_all() >= 1, "medicine tends the wound")
	ok(h2.total_bleed() == 0.0, "tended wound no longer bleeds")
	for i in 5:
		h2.tick({"dday": 0.2})
	ok(h2.blood > bled, "blood recovers once bleeding stops")

	# an ignored deep wound festers into infection; a tended one does not
	var h3 = Health.HealthTracker.new()
	h3.injure(&"leg_r", 12.0)
	for i in 3:
		h3.tick({"dday": 0.5})
	var inj = h3.hediffs[0]
	ok(inj.infection > 0.0, "untended deep wound grows an infection (%.2f)" % inj.infection)
	var h4 = Health.HealthTracker.new()
	h4.injure(&"leg_r", 12.0)
	h4.tend_all()
	for i in 3:
		h4.tick({"dday": 0.5})
	ok(h4.hediffs.is_empty() or h4.hediffs[0].infection == 0.0, "tended wound never festers")

	# disease: tended immunity beats it; untended it worsens and clouds consciousness
	var h5 = Health.HealthTracker.new()
	h5.afflict("лихоманка")
	h5.tend_all()
	for i in 12:
		h5.tick({"dday": 0.5})
	ok(h5.hediffs.is_empty(), "tended disease is beaten (immunity wins)")
	var h6 = Health.HealthTracker.new()
	h6.afflict("лихоманка")
	for i in 4:
		h6.tick({"dday": 0.5})
	ok(h6.capacity(Health.CAP_CONSCIOUSNESS) < 1.0, "untended disease clouds consciousness")
	ok(h6.capacities().size() == 4, "capacities bundle exposes all four capacities")

# ---------------- Balance (unified director; future AI control layer) ----------------
func _t_balance() -> void:
	var b = Balance.Balance.new()
	var poor := {"buildings": [{"value": 20.0}], "stock": {"wood": 10}, "items": []}
	var rich := {"buildings": [{"value": 90.0}, {"value": 90.0}, {"value": 90.0}], "stock": {"wood": 400, "components": 60}, "items": ["axe", "spear"]}
	ok(Balance.Balance.wealth(rich) > Balance.Balance.wealth(poor), "wealth grows with base + stock + gear")
	ok(Balance.Balance.threat_points(rich, 5, 1.0) > Balance.Balance.threat_points(poor, 5, 1.0), "threat points scale with wealth")
	ok(Balance.Balance.threat_points(poor, 5, 2.0) > Balance.Balance.threat_points(poor, 5, 1.0), "hostile pressure raises threat")

	# assess(): the snapshot the HUD + the AI both read
	var s_poor: Dictionary = b.assess(poor, {"day": 5, "hostile_pressure": 1.0})
	var s_rich: Dictionary = b.assess(rich, {"day": 5, "hostile_pressure": 1.0})
	ok(s_rich.threat > s_poor.threat and s_rich.raid_hint >= s_poor.raid_hint, "assess: richer colony -> higher threat + bigger raid hint")
	ok(s_poor.has("phase") and s_rich.has("phase"), "assess reports a named session phase")

	# difficulty knob is the AI lever: raising it raises assessed threat
	b.difficulty = 2.0
	ok(b.assess(rich, {"day": 5, "hostile_pressure": 1.0}).threat > s_rich.threat, "difficulty knob scales threat (the AI lever)")
	b.difficulty = 1.0

	# raid tactic escalation — incident content now lives ON Balance (one class)
	ok(b._exec_raid(poor, {"day": 4, "points": Balance.Balance.threat_points(poor, 4, 1.0)}).style == "droppod", "day%4 low-threat raid uses drop pods")
	ok(b._exec_raid(rich, {"day": 30, "points": Balance.Balance.threat_points(rich, 30, 2.0)}).style in ["siege", "sappers"], "high-threat raid escalates to siege/sappers")

	# generosity knob eases loot (the AI's mercy lever)
	var stingy: Dictionary = b._exec_cargo(poor, {"day": 10, "loot_mult": 0.5})
	var lavish: Dictionary = b._exec_cargo(poor, {"day": 10, "loot_mult": 2.0})
	ok(int(lavish.stock.scrap) > int(stingy.stock.scrap), "generosity knob scales gifts")

	# decide(): the AI seam — default rule suppresses big threats while one is active
	var busy := {"buildings": rich.buildings, "stock": rich.stock, "items": rich.items, "threat_active": true}
	ok(b.decide(b.assess(busy, {"day": 5}), busy, {"day": 5}).allow_big == false, "decide() blocks big threats while one is active")

	# tick(): deterministic per seed; adaptive pacing holds raids back while a threat is active
	var fired: Array = b.tick(busy, {"day": 5, "dday": 100.0, "hostile_pressure": 1.0}, _rng(1))
	var fired2: Array = b.tick(busy, {"day": 5, "dday": 100.0, "hostile_pressure": 1.0}, _rng(1))
	ok(JSON.stringify(fired) == JSON.stringify(fired2), "tick is deterministic per seed")
	var has_raid := false
	for f in fired:
		if f.incident == "raid":
			has_raid = true
	ok(not has_raid, "no raid while a big threat is already active (adaptive pacing)")
	# a calm, wealthy world DOES let a raid fire over a long window
	var calm := {"buildings": rich.buildings, "stock": rich.stock, "items": rich.items}
	var any_raid := false
	for f in b.tick(calm, {"day": 8, "dday": 100.0, "hostile_pressure": 1.5}, _rng(2)):
		if f.incident == "raid":
			any_raid = true
	ok(any_raid, "raids fire in a calm but wealthy world over a long window")

# ---------------- Agents (non-hero actors) ----------------
func _t_agents() -> void:
	var world := {"base": Vector2i(10, 10), "storage": Vector2i(10, 10), "hero": Vector2i(3, 3),
		"piles": [{"pos": Vector2i(5, 5), "res": "wood", "amt": 4}], "raiders": [{"pos": Vector2i(1, 1)}]}
	var raider = Agents.Agent_Raider.new()
	raider.think(world, {})
	ok(raider.job != null and raider.job.verb == &"attack" and raider.job.target == Vector2i(10, 10), "raider drives at the base")
	ok(raider.faction == &"hostile" and raider.kind == &"raider", "raider is a hostile robot")

	var bot = Agents.Agent_Bot.new()
	bot.pos = Vector2i(6, 6)
	bot.think(world, {})
	ok(bot.job != null and bot.job.verb == &"haul" and bot.job.payload.res == "wood", "bot hauls the loose pile")
	var empty := {"storage": Vector2i(0, 0), "piles": []}
	bot.think(empty, {})
	ok(bot.job == null, "bot idles when there is nothing to haul")

	var guard = Agents.Agent_Animal.new(true, &"guard")
	guard.think(world, {})
	ok(guard.job.verb == &"attack" and guard.job.target == Vector2i(1, 1), "tamed guard animal attacks the nearest raider")

	# hostile-list unification: the guard reads the SAME agents→raiders fallback combat.gd uses,
	# filtered by faction — a mixed world.agents list must never make it attack a friendly.
	var foe = Agents.Agent_Raider.new()
	foe.pos = Vector2i(7, 7)
	var friend = Agents.Agent_Bot.new()
	friend.pos = Vector2i(2, 2)
	guard.think({"hero": Vector2i(3, 3), "agents": [friend, foe]}, {})
	ok(guard.job.verb == &"attack" and guard.job.target == Vector2i(7, 7), "guard targets only hostiles in a mixed world.agents list")
	guard.think({"hero": Vector2i(3, 3), "agents": [friend]}, {})
	ok(guard.job.verb == &"follow", "guard ignores friendly agents (no hostiles -> follows the hero)")
	foe.hp = 0.0
	guard.think({"hero": Vector2i(3, 3), "agents": [friend, foe]}, {})
	ok(guard.job.verb == &"follow", "a dead hostile is not a target")

	var wild = Agents.Agent_Animal.new(false, &"none")
	wild.think(world, {})
	ok(wild.job.verb == &"graze", "wild animal grazes")
	wild.manhunter = true
	wild.think(world, {})
	ok(wild.job.verb == &"attack" and wild.job.target == Vector2i(3, 3), "manhunter animal hunts the hero")

# ---------------- Environment (Batch 1: the ctx substrate) ----------------
func _t_environment() -> void:
	var cm = Climate.ClimateModel_Deterministic.new()

	# --- TemperatureSystem: outdoor temp tracks climate --------------------------
	var temp_sys = Env.TemperatureSystem.new()
	# Kyiv, deep winter (day 1, midday) — an outdoor cell with no modifiers.
	var world_out := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0)}
	var ctx_out := {"dday": 0.0}
	temp_sys.system_tick(world_out, ctx_out)
	var raw_climate: float = cm.temperature_c(50.45, 30.52, 1, 0.5)
	ok(is_equal_approx(float(ctx_out.temp_c), raw_climate), "outdoor temp_c tracks the climate model")
	ok(float(ctx_out.temp_c) < 5.0 and not bool(ctx_out.indoor), "Kyiv winter outdoor cell is cold + outdoor")

	# --- indoor cell buffers toward the comfortable setpoint ---------------------
	var roof = Env.RoofMap.new()
	roof.set_indoor(Vector2i(0, 0), true)
	ok(roof.is_indoor(Vector2i(0, 0)) and not roof.is_indoor(Vector2i(1, 1)), "RoofMap set/is_indoor")
	var world_in := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0), "roof": roof}
	var ctx_in := {"dday": 0.0}
	temp_sys.system_tick(world_in, ctx_in)
	ok(bool(ctx_in.indoor), "roofed cell classified indoor")
	# In the cold, indoor (buffered toward 21°C) is closer to the setpoint than the same outdoor cell.
	ok(abs(float(ctx_in.temp_c) - Env.INDOOR_SETPOINT_C) < abs(float(ctx_out.temp_c) - Env.INDOOR_SETPOINT_C),
		"indoor cell is closer to setpoint than outdoor in cold weather (%.1f vs %.1f)" % [float(ctx_in.temp_c), float(ctx_out.temp_c)])

	# --- active heater raises temp_c; inactive one does not ----------------------
	var world_heat := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0), "temp_emitters": [{"pos": Vector2i(1, 0), "delta_c": 12.0, "active": true}]}
	var ctx_heat := {"dday": 0.0}
	temp_sys.system_tick(world_heat, ctx_heat)
	ok(float(ctx_heat.temp_c) > float(ctx_out.temp_c), "active heater raises temp_c (%.1f > %.1f)" % [float(ctx_heat.temp_c), float(ctx_out.temp_c)])
	var world_off := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0), "temp_emitters": [{"pos": Vector2i(1, 0), "delta_c": 12.0, "active": false}]}
	var ctx_off := {"dday": 0.0}
	temp_sys.system_tick(world_off, ctx_off)
	ok(is_equal_approx(float(ctx_off.temp_c), float(ctx_out.temp_c)), "inactive heater does not change temp_c")
	# a far heater outside emitter_radius does not reach the cell
	var world_far := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0), "temp_emitters": [{"pos": Vector2i(100, 0), "delta_c": 12.0, "active": true}]}
	var ctx_far := {"dday": 0.0}
	temp_sys.system_tick(world_far, ctx_far)
	ok(is_equal_approx(float(ctx_far.temp_c), float(ctx_out.temp_c)), "out-of-range heater does not reach the cell")

	# --- cold snap temp_offset lowers temp_c -------------------------------------
	var world_snap := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0), "temp_offset": -15.0}
	var ctx_snap := {"dday": 0.0}
	temp_sys.system_tick(world_snap, ctx_snap)
	ok(is_equal_approx(float(ctx_snap.temp_c), float(ctx_out.temp_c) - 15.0), "cold-snap temp_offset lowers temp_c by 15°C")

	# --- WeatherSystem: deterministic StringName + wet flag ----------------------
	var weather_sys = Env.WeatherSystem.new()
	# Choose a seed/coord that yields rain deterministically (verify vs the climate model directly).
	var probe := RandomNumberGenerator.new(); probe.seed = 4
	var expected_w: StringName = cm.weather(50.45, 30.52, 180, 0.5, probe)
	var wrng := RandomNumberGenerator.new(); wrng.seed = 4
	var world_w := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 180, "frac": 0.5, "rng": wrng}
	var ctx_w := {}
	weather_sys.system_tick(world_w, ctx_w)
	ok(ctx_w.weather == expected_w, "weather is deterministic for a fixed seed (got %s)" % [str(ctx_w.weather)])
	# Determinism repeat: same seed -> same weather.
	var wrng2 := RandomNumberGenerator.new(); wrng2.seed = 4
	var world_w2 := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 180, "frac": 0.5, "rng": wrng2}
	var ctx_w2 := {}
	weather_sys.system_tick(world_w2, ctx_w2)
	ok(ctx_w2.weather == ctx_w.weather, "weather reproduces from the same seed")
	# Directly probe the wet flag: force a rain weather via a stub climate.
	var rain_ctx := {}
	weather_sys.system_tick({"climate": _StubClimate.new(&"rain"), "rng": _rng(1)}, rain_ctx)
	ok(bool(rain_ctx.wet), "rain sets ctx.wet true")
	var clear_ctx := {}
	weather_sys.system_tick({"climate": _StubClimate.new(&"clear"), "rng": _rng(1)}, clear_ctx)
	ok(not bool(clear_ctx.wet), "clear weather leaves ctx.wet false")
	# an indoor cell stays dry even in the rain
	var indoor_rain := {"indoor": true}
	weather_sys.system_tick({"climate": _StubClimate.new(&"rain"), "rng": _rng(1)}, indoor_rain)
	ok(not bool(indoor_rain.wet), "indoor cell is dry in the rain")

	# --- LightSystem: noon brighter than midnight; lamp lifts night light --------
	var light_sys = Env.LightSystem.new()
	var noon_ctx := {}
	light_sys.system_tick({"climate": cm, "lat": 50.45, "day": 180, "frac": 0.5, "hero": Vector2i(0, 0)}, noon_ctx)
	var mid_ctx := {}
	light_sys.system_tick({"climate": cm, "lat": 50.45, "day": 180, "frac": 0.0, "hero": Vector2i(0, 0)}, mid_ctx)
	ok(float(noon_ctx.light) > float(mid_ctx.light), "noon brighter than midnight (%.2f > %.2f)" % [float(noon_ctx.light), float(mid_ctx.light)])
	# an active lamp at night lifts light above ambient
	var lamp_ctx := {}
	light_sys.system_tick({"climate": cm, "lat": 50.45, "day": 180, "frac": 0.0, "hero": Vector2i(0, 0),
		"lights": [{"pos": Vector2i(0, 0), "radius": 4.0, "active": true}]}, lamp_ctx)
	ok(float(lamp_ctx.light) > float(mid_ctx.light), "active lamp raises night light above ambient (%.2f > %.2f)" % [float(lamp_ctx.light), float(mid_ctx.light)])
	var dark_ctx := {}
	light_sys.system_tick({"climate": cm, "lat": 50.45, "day": 180, "frac": 0.0, "hero": Vector2i(0, 0),
		"lights": [{"pos": Vector2i(0, 0), "radius": 4.0, "active": false}]}, dark_ctx)
	ok(is_equal_approx(float(dark_ctx.light), float(mid_ctx.light)), "inactive lamp leaves night dark")

	# --- CompDeteriorate: outdoor wears + destroys; indoor never; wet faster -----
	var thing_out = Things.Thing.new(null)
	thing_out.add_comp(Env.CompDeteriorate.new({"deteriorate_days": 4.0}))
	var det = thing_out.get_comp(Env.CompDeteriorate)
	var det_ctx := {"indoor": false, "wet": false, "dday": 0.5}
	for i in 3:
		thing_out.tick(det_ctx)
	ok(det.progress() > 0.0 and not thing_out.destroyed, "outdoor thing deteriorates (%d%%)" % int(100.0 * det.progress()))
	for i in 20:
		thing_out.tick(det_ctx)
	ok(thing_out.destroyed, "outdoor thing eventually destroyed by deterioration")

	var thing_in = Things.Thing.new(null)
	thing_in.add_comp(Env.CompDeteriorate.new({"deteriorate_days": 4.0}))
	var det_in = thing_in.get_comp(Env.CompDeteriorate)
	var indoor_ctx := {"indoor": true, "wet": false, "dday": 0.5}
	for i in 40:
		thing_in.tick(indoor_ctx)
	ok(not thing_in.destroyed and det_in.progress() == 0.0, "indoor thing never deteriorates")

	# wet weather deteriorates faster than clear over the same elapsed time
	var thing_dry = Things.Thing.new(null); thing_dry.add_comp(Env.CompDeteriorate.new({"deteriorate_days": 20.0, "wet_mult": 2.0}))
	var thing_wet = Things.Thing.new(null); thing_wet.add_comp(Env.CompDeteriorate.new({"deteriorate_days": 20.0, "wet_mult": 2.0}))
	var dry_ctx := {"indoor": false, "wet": false, "dday": 0.5}
	var wet_ctx := {"indoor": false, "wet": true, "dday": 0.5}
	for i in 4:
		thing_dry.tick(dry_ctx)
		thing_wet.tick(wet_ctx)
	ok(thing_wet.get_comp(Env.CompDeteriorate).progress() > thing_dry.get_comp(Env.CompDeteriorate).progress(),
		"wet weather deteriorates faster than clear (%.2f > %.2f)" % [thing_wet.get_comp(Env.CompDeteriorate).progress(), thing_dry.get_comp(Env.CompDeteriorate).progress()])
	ok(det.inspect().begins_with("знос:"), "CompDeteriorate.inspect() is Ukrainian 'знос:'")

	# --- build_environment: registration order Temp(10) -> Weather(11) -> Light(12)
	var reg = Env.build_environment()
	ok(reg.count() == 3, "build_environment registers 3 systems")
	ok(reg.systems[0].system_id == &"temperature" and reg.systems[1].system_id == &"weather" and reg.systems[2].system_id == &"light",
		"environment systems tick in order temperature -> weather -> light")

	# --- Integration: TemperatureSystem's temp_c drives CompRottable rot vs halt --
	# Hot outdoor cell: the temp_c the system produces makes food rot.
	var reg2 = Env.build_environment()
	var hot_world := {"climate": cm, "lat": 0.0, "lon": 0.0, "day": 180, "frac": 0.5,
		"hero": Vector2i(0, 0), "rng": _rng(3)}
	var food_hot = Things.Thing.new(null)
	food_hot.add_comp(Things.CompRottable.new({"rot_days": 2.0}))
	for i in 30:
		var hctx := {"dday": 0.5}
		reg2.tick_all(hot_world, hctx)
		food_hot.tick(hctx)
	ok(food_hot.destroyed, "hot-cell temp_c from TemperatureSystem rots food (ctx handoff works)")
	# Frozen outdoor cell: the produced temp_c halts rot (refrigeration).
	var reg3 = Env.build_environment()
	var cold_world := {"climate": cm, "lat": 85.0, "lon": 0.0, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0), "rng": _rng(3)}
	var food_cold = Things.Thing.new(null)
	food_cold.add_comp(Things.CompRottable.new({"rot_days": 2.0}))
	for i in 30:
		var cctx := {"dday": 0.5}
		reg3.tick_all(cold_world, cctx)
		food_cold.tick(cctx)
	ok(not food_cold.destroyed and food_cold.get_comp(Things.CompRottable).progress() == 0.0,
		"frozen-cell temp_c from TemperatureSystem halts rot (ctx handoff works)")
	_detach_all([thing_out, thing_in, thing_dry, thing_wet, food_hot, food_cold])

# ---------------- Power grid (Batch 2: composed on the Batch-1 environment) ----------------
func _t_power() -> void:
	var net = Power.PowerNetSystem.new()
	ok(net.system_id == &"power" and net.priority == 15, "PowerNetSystem id=power priority=15 (after light@12, before consumers>=20)")

	# --- supply sums producers ---------------------------------------------------
	var gen_a = Things.Thing.new(null); gen_a.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 300.0, "fuel": 10.0}))
	var gen_b = Things.Thing.new(null); gen_b.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 200.0, "fuel": 10.0}))
	var world_sup := {"things": [gen_a, gen_b]}
	net.system_tick(world_sup, {"dday": 0.0})
	ok(is_equal_approx(float(world_sup.power.supply), 500.0), "supply sums producer output (300+200=500)")
	ok(world_sup.power.has("draw") and world_sup.power.has("stored") and world_sup.power.has("capacity") and world_sup.power.has("brownout"),
		"world.power snapshot exposes supply/draw/stored/capacity/brownout")

	# --- solar output scales with ctx.light (0 at night, full at noon) -----------
	var solar = Things.Thing.new(null); solar.add_comp(Power.CompPowerSource.new({"kind": "solar", "rated": 300.0}))
	var w_night := {"things": [solar]}
	net.system_tick(w_night, {"light": 0.0})
	ok(is_equal_approx(float(w_night.power.supply), 0.0), "solar outputs 0 at night (light=0)")
	net.system_tick(w_night, {"light": 1.0})
	ok(is_equal_approx(float(w_night.power.supply), 300.0), "solar outputs full rated at noon (light=1)")
	net.system_tick(w_night, {"light": 0.5})
	ok(is_equal_approx(float(w_night.power.supply), 150.0), "solar output scales linearly with light (0.5 -> 150)")

	# --- battery charges on surplus, discharges on deficit -----------------------
	var gen_c = Things.Thing.new(null); gen_c.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 100.0, "fuel": 100.0}))
	var load_c = Things.Thing.new(null); load_c.add_comp(Power.CompPowerTrader.new({"draw": 40.0, "priority": 5}))
	var batt = Things.Thing.new(null); batt.add_comp(Power.CompBattery.new({"capacity": 500.0, "stored": 0.0}))
	var bcomp = batt.get_comp(Power.CompBattery)
	var w_bat := {"things": [gen_c, load_c, batt]}
	net.system_tick(w_bat, {"dday": 0.0})   # supply 100 - draw 40 = +60 surplus into battery
	ok(is_equal_approx(bcomp.stored, 60.0), "battery charges on surplus (+60 stored)")
	ok(bool(load_c.get_comp(Power.CompPowerTrader).is_live()), "consumer is powered when supply covers demand")
	# now cut generation and keep the load: battery must discharge to cover the deficit
	gen_c.get_comp(Power.CompPowerSource).props["rated"] = 0.0
	net.system_tick(w_bat, {"dday": 0.0})   # supply 0 - draw 40 = -40 pulled from battery (60 -> 20)
	ok(is_equal_approx(bcomp.stored, 20.0), "battery discharges on deficit (60 -> 20)")
	ok(bool(load_c.get_comp(Power.CompPowerTrader).is_live()), "consumer stays powered while battery covers the deficit")

	# --- brownout sheds the LOWEST-priority load when demand > supply+storage -----
	var only_gen = Things.Thing.new(null); only_gen.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 50.0, "fuel": 100.0}))
	var hi = Things.Thing.new(null); hi.add_comp(Power.CompPowerTrader.new({"draw": 40.0, "priority": 10}))   # keep
	var lo = Things.Thing.new(null); lo.add_comp(Power.CompPowerTrader.new({"draw": 40.0, "priority": 1}))    # shed
	var w_brown := {"things": [only_gen, hi, lo]}    # demand 80 > supply 50, no battery
	net.system_tick(w_brown, {"dday": 0.0})
	ok(bool(w_brown.power.brownout), "brownout flagged when demand exceeds supply+storage")
	ok(hi.get_comp(Power.CompPowerTrader).is_live(), "brownout keeps the HIGHER-priority load powered")
	ok(not lo.get_comp(Power.CompPowerTrader).is_live(), "brownout sheds the LOWER-priority load")

	# --- fuel drains; a dry generator outputs 0 ----------------------------------
	var burner = Things.Thing.new(null); burner.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 100.0, "fuel": 1.0, "burn_per_day": 1.0}))
	var srcc = burner.get_comp(Power.CompPowerSource)
	var w_burn := {"things": [burner]}
	burner.tick({"dday": 0.5})               # comp_tick drains 0.5 fuel (1.0 -> 0.5), still fuelled
	net.system_tick(w_burn, {"dday": 0.0})
	ok(float(srcc.props.fuel) < 1.0 and float(w_burn.power.supply) == 100.0, "fuelled generator still outputs while fuel remains")
	burner.tick({"dday": 1.0})               # drain the rest of the fuel via comp_tick
	net.system_tick(w_burn, {"dday": 0.0})
	ok(is_equal_approx(float(srcc.props.fuel), 0.0) and is_equal_approx(float(w_burn.power.supply), 0.0), "dry generator (fuel=0) outputs 0")

	# --- switched-off consumer draws nothing & is never powered ------------------
	var off_gen = Things.Thing.new(null); off_gen.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 100.0, "fuel": 10.0}))
	var off_load = Things.Thing.new(null); off_load.add_comp(Power.CompPowerTrader.new({"draw": 40.0, "on": false}))
	var w_off := {"things": [off_gen, off_load]}
	net.system_tick(w_off, {"dday": 0.0})
	ok(is_equal_approx(float(w_off.power.draw), 0.0) and not off_load.get_comp(Power.CompPowerTrader).is_live(), "switched-off consumer draws 0 and is not powered")

	# --- inspect() strings are Ukrainian -----------------------------------------
	ok(load_c.get_comp(Power.CompPowerTrader).inspect().begins_with("⚡ живлення:"), "CompPowerTrader.inspect() is Ukrainian '⚡ живлення:'")
	ok(bcomp.inspect().begins_with("заряд:"), "CompBattery.inspect() is Ukrainian 'заряд:'")

	# =====================================================================================
	# INTEGRATION: a powered heater device's emitter `active` follows its power state, and
	# feeding that through Batch-1 TemperatureSystem raises ctx.temp_c ONLY while powered.
	# =====================================================================================
	var cm = Climate.ClimateModel_Deterministic.new()
	var temp_sys = Env.TemperatureSystem.new()

	# The heater device Thing: a CompPowerTrader whose flags.emitter points at a live world.temp_emitters entry.
	var emitter := {"pos": Vector2i(0, 0), "delta_c": 12.0, "active": false}
	var heater = Things.Thing.new(null)
	heater.add_comp(Power.CompPowerTrader.new({"draw": 200.0, "priority": 5}))
	heater.flags["emitter"] = emitter

	# A generator that can power the heater.
	var hgen = Things.Thing.new(null); hgen.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 300.0, "fuel": 100.0}))

	# Shared world: Kyiv deep winter (cold), the heater's emitter list, and the power things list.
	var world := {"climate": cm, "lat": 50.45, "lon": 30.52, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0), "temp_emitters": [emitter], "things": [hgen, heater]}

	# --- powered: net delivers, apply_device_states flips emitter.active true, heater warms the cell.
	var ctx_pow := {"dday": 0.0}
	net.system_tick(world, ctx_pow)
	ok(bool(emitter.active), "powered heater: PowerNetSystem flips its emitter active TRUE")
	temp_sys.system_tick(world, ctx_pow)
	var raw_climate: float = cm.temperature_c(50.45, 30.52, 1, 0.5)
	var warm_temp: float = float(ctx_pow.temp_c)
	ok(warm_temp > raw_climate, "powered heater raises ctx.temp_c above bare climate (%.1f > %.1f)" % [warm_temp, raw_climate])

	# --- brownout: kill generation so the heater is shed -> emitter goes inactive -> no heating.
	hgen.get_comp(Power.CompPowerSource).props["rated"] = 0.0   # no supply, no battery
	var ctx_brown := {"dday": 0.0}
	net.system_tick(world, ctx_brown)
	ok(bool(world.power.brownout) and not heater.get_comp(Power.CompPowerTrader).is_live(), "brownout: unpowered heater is not live")
	ok(not bool(emitter.active), "brownout: PowerNetSystem flips the heater's emitter active FALSE")
	temp_sys.system_tick(world, ctx_brown)
	ok(is_equal_approx(float(ctx_brown.temp_c), raw_climate), "brownout heater stops heating: temp_c falls back to bare climate")
	ok(float(ctx_brown.temp_c) < warm_temp, "unpowered heater is colder than powered (Batch1<->Batch2 handoff proven)")

	# --- lamp device: powered flips a world.lights entry active, brownout kills it -----------------
	var lamp_entry := {"pos": Vector2i(0, 0), "radius": 4.0, "active": false}
	var lamp = Things.Thing.new(null)
	lamp.add_comp(Power.CompPowerTrader.new({"draw": 50.0, "priority": 3}))
	lamp.flags["light"] = lamp_entry
	var lgen = Things.Thing.new(null); lgen.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 100.0, "fuel": 100.0}))
	var world_l := {"things": [lgen, lamp], "lights": [lamp_entry]}
	net.system_tick(world_l, {"dday": 0.0})
	ok(bool(lamp_entry.active), "powered lamp: emitter/light active flipped TRUE")
	lgen.get_comp(Power.CompPowerSource).props["rated"] = 0.0
	net.system_tick(world_l, {"dday": 0.0})
	ok(not bool(lamp_entry.active), "brownout lamp: light active flipped FALSE (goes dark)")

	# --- build_power registration order ------------------------------------------
	var reg = Power.build_power()
	ok(reg.count() == 1 and reg.systems[0].system_id == &"power" and reg.systems[0].priority == 15,
		"build_power registers PowerNetSystem at priority 15")
	_detach_all([gen_a, gen_b, solar, gen_c, load_c, batt, only_gen, hi, lo, burner, off_gen, off_load, heater, hgen, lamp, lgen])

# ---------------- Production & technology (Batch 3) ----------------
func _t_production() -> void:
	var prod_sys = Production.ProductionSystem.new()
	ok(prod_sys.system_id == &"production" and prod_sys.priority == 20, "ProductionSystem id=production priority=20 (after power@15)")

	# --- content: a recipe db --------------------------------------------------------
	var db = Defs.DefDatabase.new()
	db.register(Production.RecipeDef.new(&"plank", {"inputs": {"wood": 2}, "output": {"id": "plank", "count": 1}, "work": 1.0}))
	db.register(Production.RecipeDef.new(&"steel_gun", {"inputs": {"steel": 3}, "output": {"id": "gun", "count": 1}, "work": 1.0, "requires_research": "smithing"}))
	db.register(Production.ResearchDef.new(&"smithing", {"cost": 2.0, "prereqs": []}))
	ok(db.validate_all().is_empty(), "recipe/research defs validate clean")

	# --- 'until N' bill produces exactly to N then stops -----------------------------
	var bench = Things.Thing.new(null)
	var wb = Production.CompWorkbench.new()
	bench.add_comp(wb)
	wb.add_bill(Production.Bill.new(&"plank", &"until", 3))
	var world := {"things": [bench], "db": db, "stock": {"wood": 100}}
	for i in 20:
		prod_sys.system_tick(world, {"dday": 1.0})
	ok(int(world.stock.get("plank", 0)) == 3, "'until 3' bill produces exactly 3 planks then stops (got %d)" % int(world.stock.get("plank", 0)))
	ok(int(world.stock.wood) == 100 - 3 * 2, "'until' bill consumed inputs for exactly 3 completions (wood %d)" % int(world.stock.wood))
	ok(not wb.bills.is_empty(), "'until' bill stays on the bench (does not self-remove)")

	# --- 'count N' bill completes then sweeps itself ---------------------------------
	var bench_c = Things.Thing.new(null); var wbc = Production.CompWorkbench.new(); bench_c.add_comp(wbc)
	wbc.add_bill(Production.Bill.new(&"plank", &"count", 2))
	var world_c := {"things": [bench_c], "db": db, "stock": {"wood": 100}}
	for i in 5:
		prod_sys.system_tick(world_c, {"dday": 1.0})
	ok(int(world_c.stock.get("plank", 0)) == 2 and wbc.bills.is_empty(), "'count 2' bill makes 2 then removes itself")

	# --- missing inputs stall, produce nothing ---------------------------------------
	var bench_s = Things.Thing.new(null); var wbs = Production.CompWorkbench.new(); bench_s.add_comp(wbs)
	var stall_bill = Production.Bill.new(&"plank", &"count", 5)
	wbs.add_bill(stall_bill)
	var world_s := {"things": [bench_s], "db": db, "stock": {"wood": 0}}
	for i in 5:
		prod_sys.system_tick(world_s, {"dday": 1.0})
	ok(int(world_s.stock.get("plank", 0)) == 0 and stall_bill.stalled, "bill with missing inputs stalls and produces nothing")

	# --- research-gated recipe: blocked, then allowed after unlock -------------------
	var research = Production.ResearchState.new(db)
	var bench_r = Things.Thing.new(null); var wbr = Production.CompWorkbench.new(); bench_r.add_comp(wbr)
	var gun_bill = Production.Bill.new(&"steel_gun", &"count", 1)
	wbr.add_bill(gun_bill)
	var world_r := {"things": [bench_r], "db": db, "stock": {"steel": 100}, "research": research}
	for i in 3:
		prod_sys.system_tick(world_r, {"dday": 1.0})
	ok(int(world_r.stock.get("gun", 0)) == 0 and gun_bill.stalled, "research-gated recipe is blocked before unlock")
	# research it
	ok(research.try_start(&"smithing"), "try_start begins the smithing project")
	var done := false
	for i in 5:
		if research.advance(1.0):
			done = true
	ok(done and research.is_unlocked(&"smithing"), "research advances to unlock over its cost")
	for i in 3:
		prod_sys.system_tick(world_r, {"dday": 1.0})
	ok(int(world_r.stock.get("gun", 0)) == 1, "recipe runs once research is unlocked")

	# research prereq gating
	db.register(Production.ResearchDef.new(&"gunsmithing", {"cost": 1.0, "prereqs": ["smithing"]}))
	db.register(Production.ResearchDef.new(&"orbital", {"cost": 1.0, "prereqs": ["nonexistent"]}))
	var research2 = Production.ResearchState.new(db)
	ok(not research2.can_start(&"gunsmithing"), "project with unmet prereq cannot start")
	research2.unlock(&"smithing")
	ok(research2.can_start(&"gunsmithing"), "project can start once its prereq is unlocked")

	# --- cooking: cooked restores more than raw; raw poison chance>0 and drops with skill ---
	ok(Production.CookWorker.hunger_value(0.3, true) > Production.CookWorker.hunger_value(0.3, false), "a cooked meal restores more hunger than the raw ingredient")
	var raw_chance: float = Production.CookWorker.poison_chance(0.0, true)
	var cooked_chance: float = Production.CookWorker.poison_chance(0.0, false)
	ok(raw_chance > 0.0, "raw-food poison chance is > 0 (%.3f)" % raw_chance)
	ok(raw_chance > cooked_chance, "raw food is riskier than a cooked meal (%.3f > %.3f)" % [raw_chance, cooked_chance])
	var p0: float = Production.CookWorker.poison_chance(0.0, false)
	var p10: float = Production.CookWorker.poison_chance(10.0, false)
	ok(p10 < p0, "poison chance drops as cook level rises (%.4f < %.4f)" % [p10, p0])
	# deterministic roll with a seeded rng
	var pr := RandomNumberGenerator.new(); pr.seed = 5
	var r1: bool = Production.CookWorker.roll_poison(0.0, pr, true)
	var pr2 := RandomNumberGenerator.new(); pr2.seed = 5
	var r2: bool = Production.CookWorker.roll_poison(0.0, pr2, true)
	ok(r1 == r2, "poison roll is deterministic per seed")

	# --- cooked meal is a Thing carrying CompRottable (freshness reuse) ---------------
	db.register(Production.RecipeDef.new(&"meal", {"inputs": {"raw_food": 1}, "work": 1.0,
		"output": {"id": "meal_simple", "count": 1, "thing": true, "comps": [{"cls": Things.CompRottable, "props": {"rot_days": 3.0}}]}}))
	var bench_m = Things.Thing.new(null); var wbm = Production.CompWorkbench.new({"maker_level": 8.0}); bench_m.add_comp(wbm)
	wbm.add_bill(Production.Bill.new(&"meal", &"count", 1))
	var world_m := {"things": [bench_m], "db": db, "stock": {"raw_food": 5}, "spawn": [], "rng": _rng(9)}
	prod_sys.system_tick(world_m, {"dday": 1.0})
	# ProductionSystem post_makes each spawned Thing with world.rng at creation (documented contract) —
	# the host does NOT need to roll quality itself; flags["quality"] is already set here.
	ok(world_m.spawn.size() == 1, "cook recipe spawns a meal Thing into world.spawn")
	var meal = world_m.spawn[0]
	ok(meal.get_comp(Things.CompRottable) != null, "spawned meal carries CompRottable (freshness)")
	ok(meal.get_comp(Things.CompQuality) != null, "spawned meal is quality-stamped from the maker")
	ok(meal.flags.has("quality"), "spawned meal has its quality tier already rolled at creation (post_make ran)")

	# --- quality wiring: a crafted item's quality flows into a stat (deterministic per seed) ---
	# Two swords from the same maker level roll a fixed quality per seed; a hi-level maker >= lo-level.
	var lo_bench = Things.Thing.new(null); var lo_wb = Production.CompWorkbench.new({"maker_level": 0.0}); lo_bench.add_comp(lo_wb)
	var hi_bench = Things.Thing.new(null); var hi_wb = Production.CompWorkbench.new({"maker_level": 20.0}); hi_bench.add_comp(hi_wb)
	db.register(Production.RecipeDef.new(&"sword", {"inputs": {"steel": 1}, "work": 1.0,
		"output": {"id": "sword", "count": 1, "thing": true}}))
	lo_wb.add_bill(Production.Bill.new(&"sword", &"count", 1))
	hi_wb.add_bill(Production.Bill.new(&"sword", &"count", 1))
	# Both worlds seed the same rng (3); ProductionSystem post_makes each spawned sword at creation, so the
	# quality tier is already rolled here — no host post_make needed. Same seed + hi maker_level >= lo -> hi tier >= lo tier.
	var world_lo := {"things": [lo_bench], "db": db, "stock": {"steel": 5}, "spawn": [], "rng": _rng(3)}
	var world_hi := {"things": [hi_bench], "db": db, "stock": {"steel": 5}, "spawn": [], "rng": _rng(3)}
	prod_sys.system_tick(world_lo, {"dday": 1.0})
	prod_sys.system_tick(world_hi, {"dday": 1.0})
	var dmg = Stats.StatWorker.new(&"melee_damage", 10.0, [Stats.StatPart_Quality.new()])
	var lo_stat: float = dmg.value(Production.QualityWiring.item_ctx(world_lo.spawn[0]))
	var hi_stat: float = dmg.value(Production.QualityWiring.item_ctx(world_hi.spawn[0]))
	ok(hi_stat >= lo_stat, "higher-quality crafted item yields a >= stat (%.2f >= %.2f)" % [hi_stat, lo_stat])
	# determinism: same maker + same seed -> identical stat
	var again = Things.Thing.new(Defs.Def.new(&"item", &"sword", {})); again.add_comp(Things.CompQuality.new({"maker_level": 20.0})); again.post_make(_rng(3))
	ok(is_equal_approx(dmg.value(Production.QualityWiring.item_ctx(again)), hi_stat), "quality->stat is deterministic per seed")
	ok(hi_stat > 10.0 * 0.6 - 0.001, "quality-scaled stat stays within the quality multiplier band")

	# --- stockpile zones + priority hauling ------------------------------------------
	var z_lo = Production.StockZone.new(Rect2i(0, 0, 4, 4), 1, [], &"dump")            # accept all, low prio
	var z_hi = Production.StockZone.new(Rect2i(10, 10, 4, 4), 5, ["wood"], &"woodpile") # wood only, high prio
	var z_steel = Production.StockZone.new(Rect2i(20, 20, 2, 2), 9, ["steel"], &"forge")
	ok(z_hi.accepts("wood") and not z_hi.accepts("steel"), "filtered zone accepts its resource and refuses others")
	ok(z_lo.accepts("anything"), "empty-filter zone accepts everything")
	var zones := [z_lo, z_hi, z_steel]
	ok(Production.best_zone_for(zones, "wood") == z_hi, "hauler prefers the higher-priority accepting zone for wood")
	ok(Production.best_zone_for(zones, "gold") == z_lo, "a resource only the dump accepts routes to the dump")

	var hauler = Production.WorkGiver_HaulZone.new()
	var agent := Agents.Agent_Bot.new(); agent.pos = Vector2i(0, 0)
	var hworld := {"piles": [{"pos": Vector2i(1, 1), "res": "wood", "amt": 3}], "zones": zones}
	var job = hauler.give(agent, hworld, {})
	ok(job != null and job.verb == &"haul" and job.payload.zone == &"woodpile" and job.target == z_hi.drop_cell(),
		"zone-hauler routes wood to the high-priority woodpile")
	# a resource NO zone accepts is left on the ground
	var refuse_world := {"piles": [{"pos": Vector2i(1, 1), "res": "uranium", "amt": 1}], "zones": [z_hi, z_steel]}
	ok(hauler.give(agent, refuse_world, {}) == null, "hauler refuses to haul a resource no zone accepts")

	# --- 'until N' bill whose output is a spawned Thing stops at N (thing tally) ------
	# Regression: the thing-output completion path must tally world.stock[out_id] so 'until' can measure
	# how many meals exist and stop; otherwise out_stock stays 0 and the bench overproduces forever.
	var bench_u = Things.Thing.new(null); var wbu = Production.CompWorkbench.new({"maker_level": 2.0}); bench_u.add_comp(wbu)
	wbu.add_bill(Production.Bill.new(&"meal", &"until", 4))
	var world_u := {"things": [bench_u], "db": db, "stock": {"raw_food": 100}, "spawn": [], "rng": _rng(1)}
	for i in 20:
		prod_sys.system_tick(world_u, {"dday": 1.0})
	ok(world_u.spawn.size() == 4, "'until 4' thing-output bill spawns exactly 4 meals then stops (got %d)" % world_u.spawn.size())
	ok(int(world_u.stock.get("meal_simple", 0)) == 4, "'until' thing bill tallies world.stock[out_id] to its target (got %d)" % int(world_u.stock.get("meal_simple", 0)))
	ok(int(world_u.stock.get("raw_food", 0)) == 100 - 4, "'until' thing bill consumed inputs for exactly 4 completions")
	ok(not wbu.bills.is_empty(), "'until' thing bill stays on the bench (does not self-remove)")

	# --- one completion per bill per tick; surplus carries to the next tick -----------
	# work=2.0 recipe, dday=3.0: exactly ONE unit completes this tick and the 1.0-day surplus is carried in
	# b.progress (subtracted, NOT reset to 0); a dday=0.0 follow-up must NOT complete (surplus 1.0 < work 2.0).
	db.register(Production.RecipeDef.new(&"beam", {"inputs": {"wood": 4}, "output": {"id": "beam", "count": 1}, "work": 2.0}))
	var bench_sp = Things.Thing.new(null); var wbsp = Production.CompWorkbench.new(); bench_sp.add_comp(wbsp)
	var sp_bill = Production.Bill.new(&"beam", &"count", 5)
	wbsp.add_bill(sp_bill)
	var world_sp := {"things": [bench_sp], "db": db, "stock": {"wood": 100}}
	prod_sys.system_tick(world_sp, {"dday": 3.0})
	ok(sp_bill.done == 1 and int(world_sp.stock.get("beam", 0)) == 1, "big dday completes exactly ONE unit this tick (done=%d, beam=%d)" % [sp_bill.done, int(world_sp.stock.get("beam", 0))])
	ok(int(world_sp.stock.wood) == 100 - 4, "single completion consumes inputs exactly once (wood %d)" % int(world_sp.stock.wood))
	ok(is_equal_approx(sp_bill.progress, 1.0), "surplus work carries in b.progress (=%.2f, not reset to 0)" % sp_bill.progress)
	prod_sys.system_tick(world_sp, {"dday": 0.0})
	ok(sp_bill.done == 1 and int(world_sp.stock.get("beam", 0)) == 1, "a dday=0 follow-up tick does NOT complete again (carried surplus 1.0 < work 2.0)")

	# --- build_production registration -----------------------------------------------
	var reg = Production.build_production()
	ok(reg.count() == 1 and reg.systems[0].system_id == &"production" and reg.systems[0].priority == 20,
		"build_production registers ProductionSystem at priority 20")
	_detach_all([bench, bench_c, bench_s, bench_r, bench_m, lo_bench, hi_bench, again, bench_u, bench_sp])
	_detach_all(world_m.spawn)
	_detach_all(world_lo.spawn)
	_detach_all(world_hi.spawn)
	_detach_all(world_u.spawn)

# ---------------- Gear (apparel/armor, comfort, medbed tend, water, scars/prosthetics) ----------------
func _t_gear() -> void:
	# --- helper: build an apparel Thing ---
	var make_apparel := func(slot: StringName, insul: float, armor: Dictionary):
		var t = Things.Thing.new(null)
		t.add_comp(Gear.CompApparel.new({"slot": slot, "insulation_c": insul, "armor": armor}))
		return t

	# 1) ARMOR reduces incoming damage; rising wear reduces that protection.
	var eq = Gear.EquipModel.new()
	eq.equip(make_apparel.call(&"torso", 8.0, {Gear.DMG_SHARP: 0.5}))
	var raw := 20.0
	var got0: float = Gear.apply_armor(raw, Gear.DMG_SHARP, eq, null)   # deterministic
	ok(got0 < raw, "armor lets less damage through (%.1f < %.1f)" % [got0, raw])
	# wear the item hard, then the same hit should let MORE through than when pristine.
	var ap = eq.slots[&"torso"].get_comp(Gear.CompApparel)
	ap.take_wear(0.8)
	var got1: float = Gear.apply_armor(raw, Gear.DMG_SHARP, eq, null)
	ok(got1 > got0, "worn armor protects less: %.1f through worn vs %.1f pristine" % [got1, got0])
	# armor StatWorker exposes the combined rating; layering stacks it.
	var eq2 = Gear.EquipModel.new()
	eq2.equip(make_apparel.call(&"torso", 0.0, {Gear.DMG_SHARP: 0.5}))
	eq2.equip(make_apparel.call(&"legs", 0.0, {Gear.DMG_SHARP: 0.5}))
	var aw = Gear.armor_worker(Gear.DMG_SHARP)
	var combined: float = aw.value({"equip": eq2})
	ok(combined > 0.5 and combined < 1.0, "two 0.5 layers stack multiplicatively to %.2f (0.75)" % combined)
	# deterministic per seed with an rng
	var r1 = _rng(42); var r2 = _rng(42)
	ok(Gear.apply_armor(20.0, Gear.DMG_SHARP, _fresh_eq(0.5), r1) == Gear.apply_armor(20.0, Gear.DMG_SHARP, _fresh_eq(0.5), r2),
		"apply_armor deterministic per seed")

	# 2) COMFORT: cold felt temp grows Hypothermia; enough insulation prevents it; recedes when warm.
	var hc = Health.HealthTracker.new()
	for i in 6:
		Gear.update_comfort(hc, -10.0, 0.0, 0.5)     # freezing, no clothes
	var hypo = _find_h(hc, Gear.Hediff_Hypothermia)
	ok(hypo != null and hypo.severity > 0.0, "cold felt temp grows hypothermia (тяж.%.2f)" % (hypo.severity if hypo else -1.0))
	ok(hc.capacity(Health.CAP_CONSCIOUSNESS) < 1.0, "hypothermia lowers consciousness")
	# with enough insulation, the SAME ambient stays inside the band -> no hypothermia
	var hc2 = Health.HealthTracker.new()
	for i in 6:
		Gear.update_comfort(hc2, -10.0, 25.0, 0.5)   # +25°C warmth -> felt 15°C, inside band
	ok(_find_h(hc2, Gear.Hediff_Hypothermia) == null, "enough insulation prevents hypothermia")
	# now warm the frozen hero: hypothermia recedes and clears
	for i in 20:
		Gear.update_comfort(hc, 22.0, 0.0, 0.5)      # comfortable
	ok(_find_h(hc, Gear.Hediff_Hypothermia) == null, "hypothermia recedes to nothing once warm")
	# heat side: felt above band grows heatstroke
	var hc3 = Health.HealthTracker.new()
	for i in 6:
		Gear.update_comfort(hc3, 40.0, 0.0, 0.5)
	ok(_find_h(hc3, Gear.Hediff_Heatstroke) != null, "hot felt temp grows heatstroke")
	# REGRESSION: comfort survives per-frame dday + the tracker.tick sweep (see _t_deprivation)
	var hc4 = Health.HealthTracker.new()
	for i in 30:
		Gear.update_comfort(hc4, -10.0, 0.0, 0.003)
		hc4.tick({"dday": 0.003})
	var fine_hypo = _find_h(hc4, Gear.Hediff_Hypothermia)
	ok(fine_hypo != null and fine_hypo.severity > 0.05, "hypothermia accumulates at per-frame dday (тяж.%.3f)" % (fine_hypo.severity if fine_hypo else -1.0))

	# 3) MEDBED TEND: fails without medicine/medbed; succeeds with both; better medic/quality => higher eff.
	var medbed = Things.Thing.new(null)
	medbed.add_comp(Gear.CompMedbed.new({"med_quality": 4}))
	var htend = Health.HealthTracker.new()
	htend.injure(&"torso", 20.0)
	# no medicine, no medbed
	var r_none = Gear.TendService.tend(htend, {"things": [], "stock": {}}, 5.0)
	ok(not r_none.ok and r_none.tended == 0, "tend fails with no medicine and no medbed")
	# medicine but no medbed
	var r_nobed = Gear.TendService.tend(htend, {"things": [], "stock": {&"medicine": 3}}, 5.0)
	ok(not r_nobed.ok, "tend fails with medicine but no medbed (nothing consumed)")
	# medbed but no medicine
	var r_nomed = Gear.TendService.tend(htend, {"things": [medbed], "stock": {}}, 5.0)
	ok(not r_nomed.ok, "tend fails with medbed but no medicine")
	# both present -> success, consumes exactly one medicine
	var w_ok := {"things": [medbed], "stock": {&"medicine": 2}}
	var r_ok = Gear.TendService.tend(htend, w_ok, 5.0)
	ok(r_ok.ok and r_ok.tended >= 1, "tend succeeds with medicine + medbed")
	ok(int(w_ok.stock[&"medicine"]) == 1, "tend consumes exactly one medicine (2 -> 1)")
	ok(not htend.hediffs.is_empty() and htend.hediffs[0].tended, "tended hediff flagged tended")
	# higher medic level => higher effectiveness; higher medicine quality => higher effectiveness
	var eff_lo: float = Gear.TendService.effectiveness(1.0, 1.0)
	var eff_hi_medic: float = Gear.TendService.effectiveness(10.0, 1.0)
	var eff_hi_qual: float = Gear.TendService.effectiveness(1.0, 1.5)
	ok(eff_hi_medic > eff_lo, "higher medic level raises effectiveness (%.2f > %.2f)" % [eff_hi_medic, eff_lo])
	ok(eff_hi_qual > eff_lo, "higher medicine quality raises effectiveness (%.2f > %.2f)" % [eff_hi_qual, eff_lo])
	# effectiveness must scale the DELIVERED relief, not just the standalone number: a higher-eff tend leaves
	# LOWER infection (injury) and HIGHER immunity (disease) on the actual tracker than a lower-eff tend.
	var mb_lo = Things.Thing.new(null); mb_lo.add_comp(Gear.CompMedbed.new({"med_quality": 1}))
	var mb_hi = Things.Thing.new(null); mb_hi.add_comp(Gear.CompMedbed.new({"med_quality": 4}))
	# infection relief scaling: two fresh trackers, a wound pre-seeded with nonzero infection each
	var t_inf_lo = Health.HealthTracker.new(); t_inf_lo.injure(&"torso", 20.0); t_inf_lo.hediffs[0].infection = 1.0
	var t_inf_hi = Health.HealthTracker.new(); t_inf_hi.injure(&"torso", 20.0); t_inf_hi.hediffs[0].infection = 1.0
	Gear.TendService.tend(t_inf_lo, {"things": [mb_lo], "stock": {&"medicine": 1}}, 1.0)
	Gear.TendService.tend(t_inf_hi, {"things": [mb_hi], "stock": {&"medicine": 1}}, 10.0)
	ok(t_inf_hi.hediffs[0].infection < t_inf_lo.hediffs[0].infection,
		"higher-eff tend drives infection LOWER (%.3f hi < %.3f lo)" % [t_inf_hi.hediffs[0].infection, t_inf_lo.hediffs[0].infection])
	# immunity relief scaling: two fresh trackers each carrying a fresh disease
	var t_imm_lo = Health.HealthTracker.new(); t_imm_lo.afflict()
	var t_imm_hi = Health.HealthTracker.new(); t_imm_hi.afflict()
	Gear.TendService.tend(t_imm_lo, {"things": [mb_lo], "stock": {&"medicine": 1}}, 1.0)
	Gear.TendService.tend(t_imm_hi, {"things": [mb_hi], "stock": {&"medicine": 1}}, 10.0)
	ok(t_imm_hi.hediffs[0].immunity > t_imm_lo.hediffs[0].immunity,
		"higher-eff tend raises immunity MORE (%.3f hi > %.3f lo)" % [t_imm_hi.hediffs[0].immunity, t_imm_lo.hediffs[0].immunity])
	# nothing-to-tend guard: a full-health tracker must NOT consume a medicine and must fail
	var t_empty = Health.HealthTracker.new()
	var w_empty := {"things": [mb_hi], "stock": {&"medicine": 1}}
	var r_empty = Gear.TendService.tend(t_empty, w_empty, 5.0)
	ok(not r_empty.ok and r_empty.tended == 0, "tend fails when there is nothing to tend")
	ok(int(w_empty.stock[&"medicine"]) == 1, "nothing-to-tend consumes no medicine (1 -> 1)")

	# 4) WATER need: falls, falls FASTER when hot, and drinking satisfies.
	ok(Gear.hero_needs().size() == 3, "hero_needs adds water to food + rest (3 needs)")
	var wn = Gear.Need_Water.new()
	var w_start: float = wn.cur
	wn.need_tick({"dday": 0.2, "temp_c": 20.0})
	var w_cool_drop: float = w_start - wn.cur
	ok(w_cool_drop > 0.0, "water need falls over time")
	var wn2 = Gear.Need_Water.new()
	wn2.need_tick({"dday": 0.2, "temp_c": 40.0})
	var w_hot_drop: float = w_start - wn2.cur
	ok(w_hot_drop > w_cool_drop, "water falls FASTER when hot (%.3f hot vs %.3f cool)" % [w_hot_drop, w_cool_drop])
	var before: float = wn.cur
	var restored: float = Gear.drink(wn, &"river")
	ok(wn.cur > before and restored > 0.0, "drinking from a river satisfies thirst (+%.2f)" % restored)

	# 5) SCARS + PROSTHETICS: a severe healed injury leaves a scar (capacity penalty); a prosthetic restores it.
	var hs = Health.HealthTracker.new()
	hs.injure(&"leg_l", 20.0)          # severe (>= threshold 8)
	hs.tend_all()                       # tended => heals fast
	var full_move: float = 1.0
	# tick until the injury heals away, running the scar sweep each tick
	for i in 40:
		hs.tick({"dday": 0.5})
		Gear.resolve_to_scar(hs)
		if hs.hediffs.filter(func(h): return h is Health.Hediff_Injury).is_empty() and not hs.hediffs.filter(func(h): return h is Gear.Hediff_Scar).is_empty():
			break
	var scar = _find_h(hs, Gear.Hediff_Scar)
	ok(scar != null, "a severe healed injury leaves a permanent scar")
	var scarred_move: float = hs.capacity(Health.CAP_MOVING)
	ok(scarred_move < full_move and scarred_move > 0.0, "scar imposes a measurable capacity penalty (moving %.2f < 1.0)" % scarred_move)
	ok(scar.gone() == false, "scar is permanent (never gone)")
	# install a prosthetic leg -> restores the Moving capacity to full
	var implant = Gear.Hediff_Implant.new(null, "біопротез", [Health.CAP_MOVING])
	var installed: bool = Gear.install_prosthetic(hs, &"leg_l", implant)
	ok(installed, "prosthetic installs on the scarred part")
	var restored_move: float = hs.capacity(Health.CAP_MOVING)
	ok(is_equal_approx(restored_move, 1.0), "prosthetic restores the lost Moving capacity to full (%.2f)" % restored_move)
	ok(_find_h(hs, Gear.Hediff_Scar) == null, "surgery removed the scar it replaced")

	# --- ComfortSystem registration + priority ---
	var reg = Gear.build_comfort()
	ok(reg.count() == 1 and reg.systems[0].system_id == &"comfort" and reg.systems[0].priority == 25,
		"build_comfort registers ComfortSystem at priority 25")
	_detach_all(eq.slots.values())
	_detach_all(eq2.slots.values())
	_detach_all([medbed, mb_lo, mb_hi])
	_detach_all(_fresh_eq_things)
	_fresh_eq_things.clear()

# gear test helpers
func _find_h(tracker, cls):
	for h in tracker.hediffs:
		if is_instance_of(h, cls):
			return h
	return null

func _fresh_eq(rating: float):
	var eq = Gear.EquipModel.new()
	var t = Things.Thing.new(null)
	t.add_comp(Gear.CompApparel.new({"slot": &"torso", "insulation_c": 0.0, "armor": {Gear.DMG_SHARP: rating}}))
	eq.equip(t)
	_fresh_eq_things.append(t)   # cleanup bookkeeping: the returned EquipModel may be discarded by the caller
	return eq

# ---------------- Combat (Batch 5: threats & combat objects) ----------------
func _t_combat() -> void:
	# --- helper: a hostile raider Agent at a cell ---
	var raider_at := func(cell: Vector2i):
		var a = Agents.Agent_Raider.new(); a.pos = cell; a.hp = 100.0; return a

	# --- helper: a powered turret Thing (turret comp + a live power trader) ---
	var make_turret := func(cell: Vector2i, powered: bool, ammo: int):
		var t = Things.Thing.new(null); t.pos = cell
		t.add_comp(Combat.CompTurret.new({"range": 6.0, "damage": 15.0, "cooldown": 1.0,
			"ammo": ammo, "ammo_max": 20, "heat_max": 3.0, "heat_per_shot": 1.0, "cool_rate": 2.0}))
		var tr = Power.CompPowerTrader.new({"draw": 100.0})
		tr.powered = powered   # simulate the net verdict directly
		t.add_comp(tr)
		return t

	# 1) TURRET fires only with a hostile in range AND ammo>0 AND powered ------------------------------
	var turret = make_turret.call(Vector2i(0, 0), true, 20)
	var tc = turret.get_comp(Combat.CompTurret)
	var enemy = raider_at.call(Vector2i(3, 0))
	var world_t := {"agents": [enemy]}
	turret.tick({"dday": 1.0, "world": world_t})
	ok(tc.fired_last and enemy.hp < 100.0 and tc.ammo == 19, "powered turret with ammo fires at the in-range hostile")

	# no power => no fire
	var turret_off = make_turret.call(Vector2i(0, 0), false, 20)
	var e_off = raider_at.call(Vector2i(2, 0))
	turret_off.tick({"dday": 1.0, "world": {"agents": [e_off]}})
	ok(not turret_off.get_comp(Combat.CompTurret).fired_last and e_off.hp == 100.0, "unpowered turret does not fire")

	# empty ammo => no fire
	var turret_dry = make_turret.call(Vector2i(0, 0), true, 0)
	var e_dry = raider_at.call(Vector2i(2, 0))
	turret_dry.tick({"dday": 1.0, "world": {"agents": [e_dry]}})
	ok(not turret_dry.get_comp(Combat.CompTurret).fired_last and e_dry.hp == 100.0, "empty-ammo turret does not fire")

	# out-of-range hostile => no fire
	var turret_r = make_turret.call(Vector2i(0, 0), true, 20)
	var e_far = raider_at.call(Vector2i(50, 0))
	turret_r.tick({"dday": 1.0, "world": {"agents": [e_far]}})
	ok(not turret_r.get_comp(Combat.CompTurret).fired_last, "turret holds fire when no hostile is in range")

	# hero (player faction) in range is NEVER shot
	var turret_h = make_turret.call(Vector2i(0, 0), true, 20)
	var hero_agent = Agents.Agent_Animal.new(true, &"guard"); hero_agent.pos = Vector2i(1, 0); hero_agent.hp = 100.0
	turret_h.tick({"dday": 1.0, "world": {"agents": [hero_agent]}})
	ok(not turret_h.get_comp(Combat.CompTurret).fired_last and hero_agent.hp == 100.0, "turret never targets a player-faction actor")

	# 1b) COOLDOWN gates the rate: a second tick with dday too small to clear cooldown does not fire ---
	var turret_cd = make_turret.call(Vector2i(0, 0), true, 20)
	var cd = turret_cd.get_comp(Combat.CompTurret)
	var e_cd = raider_at.call(Vector2i(1, 0))
	var w_cd := {"agents": [e_cd]}
	turret_cd.tick({"dday": 1.0, "world": w_cd})    # fires; cool -> 1.0
	var after_first: int = cd.ammo
	turret_cd.tick({"dday": 0.1, "world": w_cd})    # only 0.1 of the 1.0 cooldown elapses -> still cooling
	ok(cd.ammo == after_first and not cd.fired_last, "cooldown gates the fire rate (no shot while cooling)")
	turret_cd.tick({"dday": 1.0, "world": w_cd})    # cooldown clears -> fires again
	ok(cd.ammo == after_first - 1 and cd.fired_last, "turret fires again once the cooldown clears")

	# 1c) HEAT gate: keep firing until heat_max is reached, then it must hold fire --------------------
	var turret_ht = make_turret.call(Vector2i(0, 0), true, 20)
	var ht = turret_ht.get_comp(Combat.CompTurret)
	var e_ht = raider_at.call(Vector2i(1, 0))
	var w_ht := {"agents": [e_ht]}
	# dday=1.0: +1 heat/shot, -2 heat/tick cool_rate => net -1 heat, never overheats. Use big dday so the
	# per-tick fire adds heat faster than it bleeds within a single tick sequence.
	var fires := 0
	for i in 10:
		var before_ammo: int = ht.ammo
		turret_ht.tick({"dday": 1.0, "world": w_ht})
		if ht.ammo < before_ammo:
			fires += 1
	# with heat_max 3.0, heat_per_shot 1.0 and cool_rate 2.0*dday(1.0)=2.0 bled BEFORE the fire check,
	# heat never reaches the cap here, so this proves the recovery path; the direct heat gate below proves the stop.
	ok(fires > 0, "turret sustains fire while heat stays under the cap")
	# direct heat-gate proof: force heat at/over the cap -> can_fire() false even powered+ammo+in-range
	ht.heat = ht.heat_max() + 1.0
	ht.cool = 0.0
	ok(not ht.can_fire(), "overheated turret cannot fire (heat gate)")

	# reload never overfills past ammo_max (capacity is a hard ceiling) -------------------------------
	var turret_rl = make_turret.call(Vector2i(0, 0), true, 20)
	var rl = turret_rl.get_comp(Combat.CompTurret)
	rl.ammo = 19
	rl.reload(10)   # 19 + 10 = 29 requested, but ammo_max is 20
	ok(rl.ammo == rl.ammo_max(), "reload caps at ammo_max (no overfill: %d/%d)" % [rl.ammo, rl.ammo_max()])

	# 2) MORTAR projectile lands within scatter radius of its target (deterministic per seed) ---------
	var mortar = Things.Thing.new(null); mortar.pos = Vector2i(0, 0)
	mortar.add_comp(Combat.CompMortar.new({"fuse_days": 2.0, "blast_radius": 2, "damage": 40.0,
		"scatter_base": 1.0, "scatter_per_cell": 0.05}))
	var mc = mortar.get_comp(Combat.CompMortar)
	var aim := Vector2i(20, 0)
	var proj1 = mc.fire(aim, _rng(11))
	var proj2 = mc.fire(aim, _rng(11))
	ok(proj1.landed_at == proj2.landed_at, "mortar scatter is deterministic per seed")
	var dist: float = Vector2(mortar.pos).distance_to(Vector2(aim))
	var scat: float = mc.scatter_for(dist)
	var off: int = Combat._manhattan(proj1.landed_at, aim)
	ok(off <= int(ceil(scat)) * 2 + 1, "projectile lands within the scatter radius of its target (off=%d, scatter=%.1f)" % [off, scat])

	# projectile lands after its fuse and deals area damage to a hostile at the impact cell
	var proj = Combat.Projectile.new(Vector2i(20, 0), 2.0, 2, 40.0, &"player")
	var victim = raider_at.call(Vector2i(20, 1))   # 1 cell from impact, inside blast radius 2
	var w_proj := {"agents": [victim]}
	proj.tick({"dday": 1.0, "world": w_proj})       # fuse 2 -> 1, not yet
	ok(proj.in_flight() and victim.hp == 100.0, "projectile still in flight before its fuse expires")
	proj.tick({"dday": 1.0, "world": w_proj})       # fuse -> 0, explodes
	ok(proj.exploded and victim.hp < 100.0, "projectile lands after its fuse and damages the nearby hostile")

	# enemy siege builds hostile enemy mortars aimed at the base
	var siege = Combat.from_siege(3, Vector2i(10, 10), Vector2i(0, 0))
	ok(siege.size() == 3 and siege[0].get_comp(Combat.CompMortar) != null and siege[0].flags.get("faction") == &"hostile",
		"from_siege builds a battery of hostile enemy mortars")

	# enemy-siege shell detonates: smashes the player's Things & player agents, spares hostiles ---------
	var siege_shell = Combat.Projectile.new(Vector2i(10, 10), 2.0, 2, 40.0, &"hostile")
	var wall = Things.Thing.new(null); wall.pos = Vector2i(10, 10); wall.max_hp = 100.0; wall.hp = 100.0
	var defender = Agents.Agent_Bot.new(); defender.pos = Vector2i(10, 11); defender.hp = 100.0   # player faction, in blast
	var raider_near = raider_at.call(Vector2i(10, 10))     # hostile standing at impact — must NOT be hit
	var w_siege := {"things": [wall], "agents": [defender, raider_near]}
	siege_shell.tick({"dday": 1.0, "world": w_siege})       # fuse 2 -> 1, still in flight
	ok(siege_shell.in_flight() and wall.hp == 100.0, "siege shell in flight before its fuse expires")
	siege_shell.tick({"dday": 1.0, "world": w_siege})       # fuse -> 0, explodes
	ok(siege_shell.exploded and wall.hp < 100.0, "siege shell smashes the player's base Thing")
	ok(defender.hp < 100.0, "siege shell damages the player-faction agent in the blast")
	ok(raider_near.hp == 100.0, "siege shell spares its own hostile faction")

	# a sibling in-flight shell in world.things is NOT caught in the blast (no chain-cancel) -----------
	var shell_a = Combat.Projectile.new(Vector2i(12, 12), 1.0, 2, 40.0, &"hostile")
	var shell_b = Combat.Projectile.new(Vector2i(12, 13), 2.0, 2, 40.0, &"hostile")   # 1 cell away, in blast radius
	var w_salvo := {"things": [shell_b], "agents": []}
	shell_a.tick({"dday": 1.0, "world": w_salvo})           # fuse -> 0, shell_a explodes
	ok(shell_a.exploded and shell_b.in_flight() and not shell_b.destroyed,
		"an exploding siege shell does not destroy a sibling in-flight shell")

	# 3) TRAP triggers on a raider entering its cell but NOT on the hero -------------------------------
	var trap = Things.Thing.new(null); trap.pos = Vector2i(5, 5)
	trap.add_comp(Combat.CompTrap.new({"damage": 30.0, "uses": 1}))
	var trc = trap.get_comp(Combat.CompTrap)
	var stepper = raider_at.call(Vector2i(5, 5))    # standing ON the trap
	trap.tick({"dday": 1.0, "world": {"agents": [stepper]}})
	ok(trc.sprung_last and stepper.hp < 100.0 and trc.uses == 0 and not trc.armed, "trap springs on a hostile on its cell and disarms at 0 uses")

	# a disarmed trap never triggers again
	var stepper2 = raider_at.call(Vector2i(5, 5))
	trap.tick({"dday": 1.0, "world": {"agents": [stepper2]}})
	ok(not trc.sprung_last and stepper2.hp == 100.0, "a disarmed trap does not trigger again")

	# the hero standing on a fresh trap is safe (friendly fire impossible)
	var trap_h = Things.Thing.new(null); trap_h.pos = Vector2i(5, 5)
	trap_h.add_comp(Combat.CompTrap.new({"damage": 30.0, "uses": 1}))
	var hero_on = Agents.Agent_Bot.new(); hero_on.pos = Vector2i(5, 5); hero_on.hp = 100.0   # player faction
	trap_h.tick({"dday": 1.0, "world": {"agents": [hero_on]}})
	ok(not trap_h.get_comp(Combat.CompTrap).sprung_last and hero_on.hp == 100.0 and trap_h.get_comp(Combat.CompTrap).armed,
		"trap NEVER triggers on the hero/player faction")

	# 4) FIRE spreads to an adjacent flammable Thing; ctx.wet stops the spread / extinguishes ---------
	var fire_sys = Combat.FireSystem.new()
	ok(fire_sys.system_id == &"fire" and fire_sys.priority == 30, "FireSystem id=fire priority=30 (after comfort@25)")
	var burn = Things.Thing.new(null); burn.pos = Vector2i(0, 0)
	burn.add_comp(Combat.CompFlammable.new({"flammability": 1.0, "burn_damage": 5.0}))
	burn.get_comp(Combat.CompFlammable).ignite()
	var neighbor = Things.Thing.new(null); neighbor.pos = Vector2i(1, 0)   # Manhattan 1 from the fire
	neighbor.add_comp(Combat.CompFlammable.new({"flammability": 1.0, "burn_damage": 5.0}))
	var far = Things.Thing.new(null); far.pos = Vector2i(10, 0)             # too far to catch
	far.add_comp(Combat.CompFlammable.new({"flammability": 1.0}))
	var w_fire := {"things": [burn, neighbor, far], "rng": _rng(3)}
	fire_sys.system_tick(w_fire, {"dday": 1.0, "wet": false})
	ok(neighbor.get_comp(Combat.CompFlammable).on_fire(), "fire spreads to the adjacent flammable Thing")
	ok(not far.get_comp(Combat.CompFlammable).on_fire(), "fire does not reach a non-adjacent Thing in one tick")
	ok(burn.hp < 100.0, "a burning Thing takes fire damage over time")

	# ctx.wet extinguishes everything and suppresses ignition
	var burn2 = Things.Thing.new(null); burn2.pos = Vector2i(0, 0)
	burn2.add_comp(Combat.CompFlammable.new({"flammability": 1.0}))
	burn2.get_comp(Combat.CompFlammable).ignite()
	var neigh2 = Things.Thing.new(null); neigh2.pos = Vector2i(1, 0)
	neigh2.add_comp(Combat.CompFlammable.new({"flammability": 1.0}))
	var w_wet := {"things": [burn2, neigh2], "rng": _rng(3)}
	fire_sys.system_tick(w_wet, {"dday": 1.0, "wet": true})
	ok(not burn2.get_comp(Combat.CompFlammable).on_fire(), "rain/snow (ctx.wet) extinguishes a burning Thing")
	ok(not neigh2.get_comp(Combat.CompFlammable).on_fire(), "ctx.wet suppresses ignition: the neighbour never catches")

	# fire is deterministic per seed (same seed -> same spread outcome)
	var mk_pair := func():
		var b = Things.Thing.new(null); b.pos = Vector2i(0, 0)
		b.add_comp(Combat.CompFlammable.new({"flammability": 0.5}))
		b.get_comp(Combat.CompFlammable).ignite()
		var n = Things.Thing.new(null); n.pos = Vector2i(1, 0)
		n.add_comp(Combat.CompFlammable.new({"flammability": 0.5}))
		return [b, n]
	var pair_a = mk_pair.call(); var pair_b = mk_pair.call()
	fire_sys.system_tick({"things": pair_a, "rng": _rng(77)}, {"dday": 0.5, "wet": false})
	fire_sys.system_tick({"things": pair_b, "rng": _rng(77)}, {"dday": 0.5, "wet": false})
	ok(pair_a[1].get_comp(Combat.CompFlammable).on_fire() == pair_b[1].get_comp(Combat.CompFlammable).on_fire(),
		"fire ignition is deterministic per seed")

	# 5) COVER reduces ranged damage taken vs no cover ------------------------------------------------
	var w_cover := {"cover": [Vector2i(7, 7)], "cover_frac": 0.5}
	var dmg_open: float = Combat.apply_cover(40.0, Vector2i(0, 0), w_cover)        # nowhere near cover
	var dmg_covered: float = Combat.apply_cover(40.0, Vector2i(7, 7), w_cover)     # on the cover cell
	ok(is_equal_approx(dmg_open, 40.0), "no cover: full ranged damage taken")
	ok(dmg_covered < dmg_open and is_equal_approx(dmg_covered, 20.0), "cover reduces ranged damage taken (%.1f < %.1f)" % [dmg_covered, dmg_open])
	# adjacency counts as cover too
	ok(Combat.in_cover(Vector2i(7, 8), w_cover) and not Combat.in_cover(Vector2i(0, 0), w_cover), "a defender adjacent to cover benefits; a defender in the open does not")
	# StatPart_Cover folds the same term into a damage StatWorker
	var dmg_worker = Stats.StatWorker.new(&"ranged_dmg", 40.0, [Combat.StatPart_Cover.new()])
	var open_stat: float = dmg_worker.value({"cover_mult": 1.0})
	var cover_stat: float = dmg_worker.value({"cover_mult": 0.5})
	ok(cover_stat < open_stat and is_equal_approx(cover_stat, 20.0), "StatPart_Cover lowers ranged damage in the stat pipeline (%.1f < %.1f)" % [cover_stat, open_stat])

	# --- build_combat registration ---
	var reg = Combat.build_combat()
	ok(reg.count() == 1 and reg.systems[0].system_id == &"fire" and reg.systems[0].priority == 30,
		"build_combat registers FireSystem at priority 30")
	_detach_all([turret, turret_off, turret_dry, turret_r, turret_h, turret_cd, turret_ht, turret_rl])
	_detach_all([mortar, wall, trap, trap_h, burn, neighbor, far, burn2, neigh2])
	_detach_all([proj1, proj2, proj, siege_shell, shell_a, shell_b])
	_detach_all(siege)
	_detach_all(pair_a)
	_detach_all(pair_b)

# =====================================================================================================
# CAPSTONE — end-to-end integration: all five kernel layers composed in ONE SystemRegistry tick spine.
#
# Проводить один інтерлівнутий такт-хребет (10→30) крізь усі п'ять шарів kernel і доводить, що вони
# компонуються без хаків: environment пише ctx (temp_c/indoor/weather/wet/light) -> power читає ctx.light,
# рахує мережу й перемикає active емітерів -> production крутить білль на верстаті -> comfort реагує на
# ctx.temp_c -> fire поширюється по world.things. Плюс детермінізм: той самий seed -> той самий підпис.
# =====================================================================================================

# Build ONE registry holding every system from the five layers, so priorities interleave 10→30.
func _build_full_spine():
	var reg = Systems.SystemRegistry.new()
	# environment: temperature@10, weather@11, light@12
	for s in Env.build_environment().systems:
		reg.add(s)
	reg.add(Power.PowerNetSystem.new())          # power@15
	reg.add(Production.ProductionSystem.new())    # production@20
	reg.add(Gear.ComfortSystem.new())             # comfort@25
	reg.add(Combat.FireSystem.new())              # fire@30
	return reg

# Wire a COMPLETE world dict populating every key the five layers read. Deterministic per `seed`.
# Kyiv deep winter (day 1, midday) so bare climate (-8.4°C) is below the comfort band -> comfort has
# something to do; seed 2 rolls CLEAR (dry) weather so fire can spread. One shared world.things list holds
# the generator (power), the workbench (production) and the two flammables (fire) — each system selects its
# own participants by comp type, proving they coexist on one list.
func _wire_integration_world(seed_val: int) -> Dictionary:
	var cm = Climate.ClimateModel_Deterministic.new()

	# --- roof with an indoor cell (hero stands OUTDOORS at origin so the cold is felt) ---
	var roof = Env.RoofMap.new()
	roof.set_indoor(Vector2i(5, 5), true)

	# --- an active heater emitter + a lamp entry (env reads these plain lists) ---
	var heater_entry := {"pos": Vector2i(1, 0), "delta_c": 6.0, "active": true}
	var lamp_entry := {"pos": Vector2i(0, 0), "radius": 4.0, "active": true}

	# --- power participants on the shared things list: a fuel source + a battery + a heater consumer ---
	var gen = Things.Thing.new(null)
	gen.add_comp(Power.CompPowerSource.new({"kind": "fuel", "rated": 300.0, "fuel": 100.0, "burn_per_day": 1.0}))
	var batt = Things.Thing.new(null)
	batt.add_comp(Power.CompBattery.new({"capacity": 500.0, "stored": 0.0}))
	var heater_dev = Things.Thing.new(null)                       # a powered device driving the heater emitter
	heater_dev.add_comp(Power.CompPowerTrader.new({"draw": 100.0, "priority": 5}))
	heater_dev.flags["emitter"] = heater_entry

	# --- production: a db with a simple recipe + a workbench carrying a bill ---
	var db = Defs.DefDatabase.new()
	db.register(Production.RecipeDef.new(&"plank", {"inputs": {"wood": 2}, "output": {"id": "plank", "count": 1}, "work": 1.0}))
	var bench = Things.Thing.new(null)
	var wb = Production.CompWorkbench.new({"maker_level": 4.0})
	bench.add_comp(wb)
	wb.add_bill(Production.Bill.new(&"plank", &"count", 3))

	# --- fire: a burning flammable + an adjacent flammable it can spread to ---
	var burn = Things.Thing.new(null); burn.pos = Vector2i(20, 20)
	burn.add_comp(Combat.CompFlammable.new({"flammability": 1.0, "burn_damage": 5.0}))
	burn.get_comp(Combat.CompFlammable).ignite()
	var neighbor = Things.Thing.new(null); neighbor.pos = Vector2i(21, 20)   # Manhattan 1 from the fire
	neighbor.add_comp(Combat.CompFlammable.new({"flammability": 1.0, "burn_damage": 5.0}))

	# --- health: a hero tracker carrying an injury so comfort/tend have something to act on ---
	var hero_health = Health.HealthTracker.new()
	hero_health.injure(&"leg_l", 12.0, "поріз")

	return {
		"climate": cm, "lat": 50.45, "lon": 30.52, "day": 1, "frac": 0.5,
		"hero": Vector2i(0, 0), "roof": roof,
		"temp_emitters": [heater_entry], "temp_offset": 0.0,
		"lights": [lamp_entry],
		"things": [gen, batt, heater_dev, bench, burn, neighbor],
		"db": db, "stock": {"wood": 100}, "spawn": [],
		"hero_health": hero_health,
		"rng": _rng(seed_val),
		# handles the assertions reach into:
		"_gen": gen, "_batt": batt, "_heater_dev": heater_dev, "_bench": bench, "_wb": wb,
		"_burn": burn, "_neighbor": neighbor, "_heater_entry": heater_entry,
	}

# Run the wired spine `n` ticks and return an end-state signature (for determinism comparison).
func _run_spine_signature(seed_val: int, n: int) -> Dictionary:
	var reg = _build_full_spine()
	var world = _wire_integration_world(seed_val)
	var last_ctx := {}
	for i in n:
		last_ctx = {"dday": 1.0}
		reg.tick_all(world, last_ctx)
	var sig := {
		"temp_c": snappedf(float(last_ctx.get("temp_c", 999.0)), 0.001),
		"weather": String(last_ctx.get("weather", &"?")),
		"wet": bool(last_ctx.get("wet", false)),
		"light": snappedf(float(last_ctx.get("light", -1.0)), 0.001),
		"supply": snappedf(float(world.power.supply), 0.001),
		"draw": snappedf(float(world.power.draw), 0.001),
		"bill_done": world._wb.bills[0].done if not world._wb.bills.is_empty() else -1,
		"plank": int(world.stock.get("plank", 0)),
		"hediffs": world.hero_health.hediffs.size(),
		"neighbor_on_fire": world._neighbor.get_comp(Combat.CompFlammable).on_fire(),
	}
	_detach_all(world.things)   # cleanup only: this world is dropped here
	return sig

func _t_integration() -> void:
	print("  -- capstone: five layers in one tick spine --")
	var reg = _build_full_spine()

	# The merged spine must interleave 10→30 across all five layers.
	var ids: Array = reg.systems.map(func(s): return String(s.system_id))
	ok(ids == ["temperature", "weather", "light", "power", "production", "comfort", "fire"],
		"один хребет інтерлівить усі 5 шарів у порядку 10→30 (%s)" % [", ".join(ids)])
	ok(reg.count() == 7, "spine registers all 7 systems from the five layers")

	var world = _wire_integration_world(2)
	var raw_climate: float = world.climate.temperature_c(50.45, 30.52, 1, 0.5)

	# --- tick ONCE first: on tick 0 the seed rolls dry CLEAR weather so fire can spread; capture that
	#     first-tick state, then keep ticking. (Contract note: world.rng is SHARED across weather/production/
	#     fire and ADVANCES every tick, so later ticks re-roll weather — a faithful, deterministic spine.) ---
	var ctx := {"dday": 1.0}
	reg.tick_all(world, ctx)
	ok(true, "повний хребет тікає без падінь через усі 5 шарів (no crash across the interleaved tick)")

	# (a) ENVIRONMENT ran: ctx carries temp_c, indoor, weather, light.
	ok(ctx.has("temp_c") and ctx.has("indoor") and ctx.has("weather") and ctx.has("light") and ctx.has("wet"),
		"(a) environment wrote ctx.temp_c/indoor/weather/wet/light")
	ok(ctx.weather == &"clear" and not bool(ctx.wet), "(a) seed rolled dry CLEAR weather on tick 0 (fire can spread)")

	# (b) POWER ran: world.power snapshot exists with supply/draw; the heater is live and its emitter is on.
	ok(world.has("power") and world.power.has("supply") and world.power.has("draw"),
		"(b) power wrote world.power snapshot with supply/draw")
	ok(float(world.power.supply) > 0.0 and float(world.power.draw) > 0.0, "(b) power net has supply and draw")
	ok(bool(world._heater_dev.get_comp(Power.CompPowerTrader).is_live()) and bool(world._heater_entry.active),
		"(b) powered heater is live -> PowerNetSystem flipped its emitter active TRUE")

	# (b2) the powered heater raised ctx.temp_c above the bare Kyiv-winter climate.
	var powered_temp: float = float(ctx.temp_c)
	ok(powered_temp > raw_climate, "(b2) powered heater raised ctx.temp_c above bare climate (%.1f > %.1f)" % [powered_temp, raw_climate])

	# (e) FIRE ran: fire spread from the burning Thing to its adjacent flammable in the dry tick-0 ctx.
	ok(world._neighbor.get_comp(Combat.CompFlammable).on_fire(), "(e) fire spread to the adjacent flammable Thing (dry ctx)")
	ok(world._burn.hp < 100.0, "(e) the burning Thing took fire damage on the tick")

	# --- keep ticking the same spine so production finishes the bill + comfort accumulates ---
	for i in 3:
		ctx = {"dday": 1.0}
		reg.tick_all(world, ctx)

	# (c) PRODUCTION ran: the 'count 3' plank bill produced exactly to target across the ticks.
	ok(int(world.stock.get("plank", 0)) == 3, "(c) production made 3 planks then stopped (bill made progress/produced)")
	ok(int(world.stock.wood) == 100 - 3 * 2, "(c) production consumed inputs for exactly 3 completions")

	# (d) COMFORT ran: in the cold (felt <12°C, no insulation) a hypothermia hediff appeared on the hero.
	var hypo = _find_h(world.hero_health, Gear.Hediff_Hypothermia)
	ok(hypo != null and hypo.severity > 0.0, "(d) comfort grew a hypothermia hediff in the cold (тяж.%.2f)" % (hypo.severity if hypo else -1.0))
	# comfort is in-band control: warm the hero for many ticks -> hypothermia recedes and clears.
	for i in 40:
		Gear.update_comfort(world.hero_health, 22.0, 0.0, 0.5)
	ok(_find_h(world.hero_health, Gear.Hediff_Hypothermia) == null, "(d) warm control: hypothermia recedes to nothing when in-band")

	# (e2) fire is suppressed under a WET ctx: force wet on a fresh spine and confirm ignition is quenched.
	var wet_world = _wire_integration_world(2)
	var fsys = Combat.FireSystem.new()
	fsys.system_tick(wet_world, {"dday": 1.0, "wet": true})
	ok(not wet_world._burn.get_comp(Combat.CompFlammable).on_fire() and not wet_world._neighbor.get_comp(Combat.CompFlammable).on_fire(),
		"(e2) a wet ctx extinguishes the fire and suppresses spread")

	# (f) BROWNOUT handoff: kill generation -> heater shed -> emitter goes inactive -> temp is no longer heated.
	# Ordering note (a real property of the composed spine): TemperatureSystem@10 runs BEFORE PowerNetSystem@15
	# within a tick, so the brownout tick's temperature still reads the emitter's PRIOR-tick `active`. The
	# emitter goes inactive that tick; the cell only cools on the NEXT tick when TemperatureSystem re-reads it.
	# So we tick twice: once to shed+flip the emitter, once for the environment to see it cold.
	world._gen.get_comp(Power.CompPowerSource).props["rated"] = 0.0
	world._batt.get_comp(Power.CompBattery).stored = 0.0
	var ctx_brown := {"dday": 1.0}
	reg.tick_all(world, ctx_brown)                    # PowerNetSystem sheds the heater + flips emitter inactive
	ok(bool(world.power.brownout) and not bool(world._heater_entry.active),
		"(f) brownout sheds the heater -> PowerNetSystem flips its emitter active FALSE")
	reg.tick_all(world, ctx_brown)                    # next tick: TemperatureSystem re-reads the cold emitter
	# Strict drop rather than exact raw_climate equality: the shared rng may roll a cold_snap dip too — either
	# way, removing the heater can only make the cell colder than when it was powered.
	ok(float(ctx_brown.temp_c) < powered_temp and float(ctx_brown.temp_c) <= raw_climate + 1e-6,
		"(f) unpowered heater stops heating: temp_c drops to <= bare climate, colder than powered (%.1f < %.1f) [Batch1<->Batch2 handoff]" % [float(ctx_brown.temp_c), powered_temp])

	# --- DETERMINISM: the same wired scenario from the same seed yields an identical end-state signature. ---
	var sig_a := _run_spine_signature(2, 4)
	var sig_b := _run_spine_signature(2, 4)
	ok(JSON.stringify(sig_a) == JSON.stringify(sig_b),
		"детермінізм: той самий seed -> ідентичний підпис усього хребта (temp_c/supply/draw/bill/hediffs/fire)")
	# a DIFFERENT seed changes the weather roll (proving the signature actually reflects the rng-driven spine).
	var sig_c := _run_spine_signature(12345, 4)   # seed 12345 rolls SNOW (wet) -> different weather + wet + fire out
	ok(sig_c.weather != sig_a.weather or sig_c.wet != sig_a.wet,
		"детермінізм-контраст: інший seed дає інший погодний підпис хребта (%s wet=%s vs %s wet=%s)" % [sig_c.weather, sig_c.wet, sig_a.weather, sig_a.wet])
	_detach_all(world.things)
	_detach_all(world.spawn)
	_detach_all(wet_world.things)
	_detach_all(wet_world.spawn)

# A minimal ClimateProvider stub that returns a fixed weather (for the wet-flag tests).
class _StubClimate extends Climate.ClimateProvider:
	var _w: StringName
	func _init(p_w: StringName) -> void:
		_w = p_w
	func weather(_lat: float, _lon: float, _day: int, _frac: float, _rng: RandomNumberGenerator) -> StringName:
		return _w

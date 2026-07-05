# RealWorld — headless tests for the mechanics kernel (spec 0003).
# Run: Godot_console.exe --headless --path godot -s res://tests/run_kernel_tests.gd
extends SceneTree

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

var passed := 0
var failed := 0

func _init() -> void:
	print("== RealWorld kernel tests (spec 0003) ==")
	_t_defs()
	_t_thing_comps()
	_t_stats()
	_t_systems()
	_t_climate()
	_t_needs()
	_t_health()
	_t_balance()
	_t_agents()
	_t_environment()
	_t_power()
	_t_production()
	print("\n== RESULT: %d passed, %d failed ==" % [passed, failed])
	quit(1 if failed > 0 else 0)

func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [pass] ", name)
	else:
		failed += 1
		printerr("  [FAIL] ", name)
		print("  [FAIL] ", name)

func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r

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
	# post_make the spawned things with the world rng (host responsibility) to roll quality.
	for th in world_m.spawn:
		th.post_make(world_m.rng)
	ok(world_m.spawn.size() == 1, "cook recipe spawns a meal Thing into world.spawn")
	var meal = world_m.spawn[0]
	ok(meal.get_comp(Things.CompRottable) != null, "spawned meal carries CompRottable (freshness)")
	ok(meal.get_comp(Things.CompQuality) != null, "spawned meal is quality-stamped from the maker")

	# --- quality wiring: a crafted item's quality flows into a stat (deterministic per seed) ---
	# Two swords from the same maker level roll a fixed quality per seed; a hi-level maker >= lo-level.
	var lo_bench = Things.Thing.new(null); var lo_wb = Production.CompWorkbench.new({"maker_level": 0.0}); lo_bench.add_comp(lo_wb)
	var hi_bench = Things.Thing.new(null); var hi_wb = Production.CompWorkbench.new({"maker_level": 20.0}); hi_bench.add_comp(hi_wb)
	db.register(Production.RecipeDef.new(&"sword", {"inputs": {"steel": 1}, "work": 1.0,
		"output": {"id": "sword", "count": 1, "thing": true}}))
	lo_wb.add_bill(Production.Bill.new(&"sword", &"count", 1))
	hi_wb.add_bill(Production.Bill.new(&"sword", &"count", 1))
	var world_lo := {"things": [lo_bench], "db": db, "stock": {"steel": 5}, "spawn": []}
	var world_hi := {"things": [hi_bench], "db": db, "stock": {"steel": 5}, "spawn": []}
	prod_sys.system_tick(world_lo, {"dday": 1.0})
	prod_sys.system_tick(world_hi, {"dday": 1.0})
	world_lo.spawn[0].post_make(_rng(3))
	world_hi.spawn[0].post_make(_rng(3))
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

	# --- build_production registration -----------------------------------------------
	var reg = Production.build_production()
	ok(reg.count() == 1 and reg.systems[0].system_id == &"production" and reg.systems[0].priority == 20,
		"build_production registers ProductionSystem at priority 20")

# A minimal ClimateProvider stub that returns a fixed weather (for the wet-flag tests).
class _StubClimate extends Climate.ClimateProvider:
	var _w: StringName
	func _init(p_w: StringName) -> void:
		_w = p_w
	func weather(_lat: float, _lon: float, _day: int, _frac: float, _rng: RandomNumberGenerator) -> StringName:
		return _w

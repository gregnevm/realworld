# RealWorld — tests/off_scenarios.gd : the scripted "everything-OFF" scenarios behind
# godot/tests/fixtures/off_baseline.json (specs 0010 REQ-01/02/60/61 + 0012 REQ-1/2/3/4/81, wave S0).
#
# ONE source of scenario code, used by BOTH the dev-only capture (tests/capture_baseline.gd, which
# WRITES the fixture from the unmodified baseline code) and the CI suites (run_capsule_tests.gd /
# run_realtime_tests.gd, which RE-RUN the same scenarios and compare). Keeping a single copy means
# the pin can never drift from the capture; the fixture is the only thing that is "remembered".
#
# Why scripted scenarios and not just the twin-ambient hash: the 0010/0012 waves edit exactly the
# branches an ambient 300-tick run never reaches (raid damage on buildings, death + respawn,
# demolish, bench crafting, storage reach, the daily capsule at the day boundary, base_center,
# region travel, power/farm/director dday maths). Every such branch has a scenario below.
#
# Two result tiers per scenario ({"portable": {...}, "numeric": {...}}):
#   portable — integers/strings/booleans that do NOT flow through libm sin/cos (refusal texts, reach
#              booleans, cell coordinates, key sets, byte-exact save strings of a fixed text). The
#              tests compare these on EVERY platform.
#   numeric  — world_hash / float state after ticks. The climate model (kernel/climate.gd) calls
#              cos(), so these bits are only reproducible on the platform that captured them; the
#              suites compare them hard on the same platform and SKIP LOUDLY elsewhere.
#
# Flags: every scenario runs with the spec flags at their DEFAULT (OFF). _force_off() additionally
# sets any flag that a LATER wave introduces (use_main_capsule / use_orbit / use_realtime) to false
# BEFORE new_game/start — a no-op at baseline, an explicit "OFF" assertion afterwards.
extends RefCounted

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Persistence = preload("res://scripts/persistence.gd")
const GameData = preload("res://scripts/data.gd")
const SessionScript = preload("res://scripts/session.gd")
const Inventory = preload("res://scripts/sim/inventory.gd")
const Director = preload("res://scripts/sim/director.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const KernelBalance = preload("res://scripts/kernel/balance.gd")
const Goals = preload("res://scripts/goals.gd")
const WorldInputScript = preload("res://scripts/ui/world_input.gd")
const Progression = preload("res://scripts/kernel/progression.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const Social = preload("res://scripts/social.gd")
const Upkeep = preload("res://scripts/sim/upkeep.gd")
const HudModel = preload("res://scripts/ui/hud_model.gd")
const Lifecycle = preload("res://scripts/ui/lifecycle.gd")
const WorldPanels = preload("res://scripts/ui/world_panels.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")

const LAT := 50.4501          # Київ — the determinism suite's coordinate
const LON := 30.5234
const LAT2 := 49.8397         # Львів — second region for travel
const LON2 := 24.0297
const N := 56
const DT := 0.1
const WORLD_HASH_FINAL_EXPECTED := "c4dbef44fe0f95d6"   # run_determinism_tests.gd WORLD_HASH_FINAL on the baseline

# flags introduced by later waves — default OFF, forced OFF explicitly when present
const FUTURE_FLAGS := ["use_main_capsule", "use_orbit", "use_realtime"]

# parent keys whose CHILD keys are data (coords, cell ids, resource ids) and not schema: collapsed to "*"
const DATA_MAPS := ["regions", "nodes", "stock", "carry", "unlocked", "progress", "research_unlocked"]

# every scenario name -> Callable-free dispatch in run(); the order is the fixture order
const SCENARIOS := [
	"twin_ambient_300", "flat_100", "inventory_on_300", "catalog_on_300", "catalog_power_farm",
	"raid_forced_building", "raid_director_apply", "patrol_fight", "death_respawn", "death_respawn_inventory",
	"death_respawn_away", "demolish_base_center", "storage_reach", "workbench_craft", "capsule_day_transition",
	"capsule_launch", "travel_regions", "save_continue", "gather_haul", "needs_pace", "spawn_presets",
	"record_keys", "goals_speeds", "osm_overlay", "fuzz_verbs", "director_grace", "director_long", "hud_and_strings",
	# S27-S29 (integrity re-review of S0): the player-facing STRINGS that live outside world_hash — appended, never inserted
	"session_feed", "flash_hints", "capsule_panel_off",
]


# ======================================================================================
# dispatch
# ======================================================================================
static func run(name: String) -> Dictionary:
	match name:
		"twin_ambient_300": return twin_ambient_300()
		"flat_100": return flat_100()
		"inventory_on_300": return inventory_on_300()
		"catalog_on_300": return catalog_on_300()
		"catalog_power_farm": return catalog_power_farm()
		"raid_forced_building": return raid_forced_building()
		"raid_director_apply": return raid_director_apply()
		"patrol_fight": return patrol_fight()
		"death_respawn": return death_respawn(false)
		"death_respawn_inventory": return death_respawn(true)
		"death_respawn_away": return death_respawn_away()
		"demolish_base_center": return demolish_base_center()
		"storage_reach": return storage_reach()
		"workbench_craft": return workbench_craft()
		"capsule_day_transition": return capsule_day_transition()
		"capsule_launch": return capsule_launch()
		"travel_regions": return travel_regions()
		"save_continue": return save_continue()
		"gather_haul": return gather_haul()
		"needs_pace": return needs_pace()
		"spawn_presets": return spawn_presets()
		"record_keys": return record_keys()
		"goals_speeds": return goals_speeds()
		"osm_overlay": return osm_overlay()
		"fuzz_verbs": return fuzz_verbs()
		"director_grace": return director_grace()
		"director_long": return director_long()
		"hud_and_strings": return hud_and_strings()
		"session_feed": return session_feed()
		"flash_hints": return flash_hints()
		"capsule_panel_off": return capsule_panel_off()
	return {"portable": {}, "numeric": {"error": "unknown scenario " + name}}


static func run_all() -> Dictionary:
	var out: Dictionary = {}
	for name in SCENARIOS:
		out[name] = run(String(name))
	return out


# ======================================================================================
# builders / helpers
# ======================================================================================
static func _force_off(o: Object) -> void:
	for f in FUTURE_FLAGS:
		if f in o:
			o.set(f, false)


static func _kyiv(inventory: bool = false, catalog: bool = false) -> Variant:
	var sim: Variant = Sim.new()
	_force_off(sim)
	sim.use_inventory = inventory
	sim.use_catalog = catalog
	sim.new_game(WorldGen.generate_map(LAT, LON, N))
	return sim


# the run_tests `_flat_sim`: a 16x16 grass pad, spawn (8,8), storage lands on (9,8); director muted
static func _flat(day: int = 195, inventory: bool = false, catalog: bool = false) -> Variant:
	var tiles: PackedByteArray = PackedByteArray()
	tiles.resize(16 * 16)
	tiles.fill(WorldGen.GRASS)
	var s: Variant = Sim.new()
	_force_off(s)
	s.use_inventory = inventory
	s.use_catalog = catalog
	s.new_game({"n": 16, "tiles": tiles, "nodes": {}, "spawn": Vector2i(8, 8), "lat": LAT, "lon": LON})
	s.time.day = day
	s.time.frac = 0.5
	s.weather = &"clear"
	s.patrol.next = 1.0e9
	_mute(s)
	s.messages.clear()
	return s


static func _mute(s: Variant) -> void:
	s.balance = KernelBalance.Balance.new()
	for cat in s.balance.category_weight:
		s.balance.category_weight[cat] = 0.0


static func _topup(s: Variant) -> void:
	s.player.hp = 100.0
	s.player.hunger = 100.0
	s.player.rest = 100.0


static func _dispose(s: Variant) -> void:
	if s == null:
		return
	s.dispose_farm()
	s.dispose_power()


static func _v(c: Vector2i) -> Array:
	return [c.x, c.y]


static func _texts(s: Variant) -> Array:
	var out: Array = []
	for m in s.messages:
		out.append(String(m.text))
	return out


static func _sorted_keys(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort()
	return ks


static func _sorted_stock(s: Variant) -> Dictionary:
	var out: Dictionary = {}
	for k in _sorted_keys(s.stock):
		out[String(k)] = s.stock[k]
	return out


static func _buildings(s: Variant) -> Array:
	var out: Array = []
	for b in s.buildings:
		out.append("%s@%d,%d:%s" % [String(b.kind), int(b.x), int(b.y), str(snappedf(float(b.hp), 0.0001))])
	return out


static func _nearest_tree(s: Variant) -> Vector2i:
	var sp: Vector2i = s.map.spawn
	var best: Vector2i = Vector2i(-1, -1)
	var bd: int = 1 << 30
	for key in s.map.nodes:
		if s.map.nodes[key].kind != "tree":
			continue
		var d: int = absi(int(key) % s.n - sp.x) + absi(int(int(key) / s.n) - sp.y)
		if d < bd:
			bd = d
			best = Vector2i(int(key) % s.n, int(int(key) / s.n))
	return best


static func _buildable_near_spawn(s: Variant, skip: int = 0) -> Vector2i:
	var sp: Vector2i = s.map.spawn
	var seen: int = 0
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if s.build_valid(sp.x + dx, sp.y + dy):
					if seen == skip:
						return Vector2i(sp.x + dx, sp.y + dy)
					seen += 1
	return Vector2i(-1, -1)


# the numeric-tier readout of a live sim (everything the tick-driven branches can move)
static func _numeric_state(s: Variant) -> Dictionary:
	var rt: Dictionary = Persistence.serialize_runtime(s)
	return {
		"world_hash": Persistence.world_hash(s),
		"region_hash": Persistence.content_hash(Persistence.serialize_region(s)),
		"runtime_hash": Persistence.content_hash(rt),
		"day": int(s.time.day), "frac": float(s.time.frac),
		"player": [float(s.player.px), float(s.player.py), float(s.player.hp), float(s.player.hunger), float(s.player.rest)],
		"stock": _sorted_stock(s),
		"buildings": _buildings(s),
		"enemies": s.enemies.size(),
		"raid": [bool(s.raid.active), bool(s.raid.warned), int(s.raid.wave), float(s.raid.timer)],
		"patrol_wave": int(s.patrol.wave),
		"dead": bool(s.dead),
		"messages_hash": Persistence.content_hash(_texts(s)),
		# the three seeded streams' cursors (64-bit: strings, like the record): REQ-0010-34 compares ON against these
		"rng_cursors": [str(s.env_rng.state), str(s.threat_rng.state), str(s.director_rng.state)],
	}


# ---- key-path collector (schema of a JSON-ish value; dynamic data maps collapse to "*") ----
static func key_paths(v: Variant, prefix: String, out: Dictionary) -> void:
	if v is Dictionary:
		var parent: String = prefix.get_slice(".", prefix.get_slice_count(".") - 1)
		var collapse: bool = DATA_MAPS.has(parent)
		for k in v:
			var seg: String = "*" if collapse else str(k)
			var p: String = prefix + "." + seg
			out[p] = true
			key_paths(v[k], p, out)
	elif v is Array:
		for e in v:
			key_paths(e, prefix + "[]", out)


static func paths_of(v: Variant) -> Array:
	var out: Dictionary = {}
	key_paths(v, "", out)
	var ks: Array = out.keys()
	ks.sort()
	return ks


# ======================================================================================
# S1  twin ambient — THE determinism pin (WORLD_HASH_FINAL) + record schema
# ======================================================================================
static func twin_ambient_300() -> Dictionary:
	var sim: Variant = _kyiv()
	for t in 300:
		sim.update(DT)
		_topup(sim)
	var numeric: Dictionary = _numeric_state(sim)
	var rec: Dictionary = Persistence.serialize_region(sim)
	var rt: Dictionary = Persistence.serialize_runtime(sim)
	var portable: Dictionary = {
		"region_keys": _sorted_keys(rec), "runtime_keys": _sorted_keys(rt),
		"world_hash_is_region_plus_dyn": Persistence.world_hash(sim) == Persistence.content_hash({"region": rec, "dyn": rt}),
	}
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


# ======================================================================================
# S2  flat 100 ticks (run_tests._flat_sim) with the director muted
# ======================================================================================
static func flat_100() -> Dictionary:
	var s: Variant = _flat()
	for t in 100:
		s.update(DT)
	var numeric: Dictionary = _numeric_state(s)
	_dispose(s)
	return {"portable": {}, "numeric": numeric}


# ======================================================================================
# S3  use_inventory ON — hand-placed campfire from the pack, a gather order, 300 ticks
# ======================================================================================
static func inventory_on_300() -> Dictionary:
	var sim: Variant = _kyiv(true, false)
	var tree: Vector2i = _nearest_tree(sim)
	var cell: Vector2i = _buildable_near_spawn(sim, 2)
	var placed: bool = false
	for t in 300:
		if t == 0 and cell.x >= 0:
			sim.try_build("campfire", cell.x, cell.y)
			placed = sim.has_building("campfire")
		elif t == 20:
			sim.order_gather(tree.x, tree.y)
		sim.update(DT)
		_topup(sim)
	var rec: Dictionary = Persistence.serialize_region(sim)
	var numeric: Dictionary = _numeric_state(sim)
	numeric["pack"] = {"wood": Inventory.count(sim, "wood"), "stone": Inventory.count(sim, "stone"), "food": Inventory.count(sim, "food"),
		"campfire_item": Inventory.count(sim, "bld:campfire"), "gather_skill": float(sim.player.skills.gather)}
	var portable: Dictionary = {
		"campfire_placed": placed, "region_keys": _sorted_keys(rec), "use_inventory_in_record": bool(rec.get("use_inventory", false)),
		"bags": (rec.get("bags", []) as Array).size(),
	}
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


# ======================================================================================
# S4  use_catalog ON — gated kiln, catalogue craft, 300 ticks
# ======================================================================================
static func catalog_on_300() -> Dictionary:
	var sim: Variant = _kyiv(false, true)
	sim.research_unlocked = {"fire_mastery": true}
	sim.stock[sim.res_key("clay")] = 20
	sim.stock[sim.res_key("stone")] = 40
	sim.stock[sim.res_key("wood")] = 60
	var cell: Vector2i = _buildable_near_spawn(sim, 3)
	sim.try_build("kiln", cell.x, cell.y)
	var kiln_ok: bool = sim.has_building("kiln")
	var craft: Dictionary = sim.craft_catalog("make_charcoal")
	for t in 300:
		sim.update(DT)
		_topup(sim)
	var rec: Dictionary = Persistence.serialize_region(sim)
	var numeric: Dictionary = _numeric_state(sim)
	var portable: Dictionary = {
		"kiln_built": kiln_ok, "craft_ok": bool(craft.get("ok", false)), "craft_label": str(craft.get("label", "")),
		"craft_added": int(craft.get("added", -1)), "region_keys": _sorted_keys(rec), "use_catalog_in_record": bool(rec.get("use_catalog", false)),
	}
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


# ======================================================================================
# S5  catalogue power grid + grow zone over ~1.3 game-days (power/farm/environment dday maths)
# ======================================================================================
static func catalog_power_farm() -> Dictionary:
	var s: Variant = _flat(195, false, true)
	s.research_unlocked = {"electricity": true, "plasteel_working": true, "agriculture": true}
	for res in ["planks", "components", "steel", "circuit", "stone", "clay", "wood", "copper_wire", "chemfuel"]:
		s.stock[s.res_key(res)] = 40
	s.try_build("electric_smelter", 3, 3)
	s.try_build("wood_generator", 5, 3)
	s.try_build("power_conduit", 4, 3)
	s.try_build("grow_zone", 3, 6)
	s.apply_temp_anomaly(-6.0, 1.0)   # the cold-snap seam: temp_offset_days must tick down by dday
	var kinds: Array = []
	for b in s.buildings:
		kinds.append(String(b.kind))
	for t in 400:
		s.update(0.5)
		_topup(s)
	var zone: Variant = null
	var gen: Variant = null
	for b in s.buildings:
		if String(b.kind) == "grow_zone":
			zone = b
		elif String(b.kind) == "wood_generator":
			gen = b
	var numeric: Dictionary = _numeric_state(s)
	numeric["power_net"] = {"supply": float(s.power_net.get("supply", 0.0)), "draw": float(s.power_net.get("draw", 0.0)),
		"stored": float(s.power_net.get("stored", 0.0)), "brownout": bool(s.power_net.get("brownout", false))}
	numeric["zone_growth"] = float(zone.get("growth", -1.0)) if zone != null else -1.0
	numeric["zone_harvests"] = int(zone.get("harvests", -1)) if zone != null else -1
	numeric["gen_fuel"] = float(gen.get("fuel", -1.0)) if gen != null else -1.0
	numeric["temp_offset_days"] = float(s.temp_offset_days)
	numeric["weather"] = String(s.weather)
	numeric["weather_t"] = float(s.weather_t)
	var portable: Dictionary = {"built": kinds}
	_dispose(s)
	return {"portable": portable, "numeric": numeric}


# ======================================================================================
# S6  forced raid, hero far from the base: spawn_wave + edge_cell + damage_building(+steal) + wall hits
# ======================================================================================
static func raid_forced_building() -> Dictionary:
	var sim: Variant = _kyiv()
	var sp: Vector2i = sim.map.spawn
	var base: Vector2i = sim.base_center()
	# a wall ring (Chebyshev r=2) round the storage: raiders must smash BLOCKING buildings (steal=false)
	# on their way in, then loot the storage itself (steal=true) — both damage_building branches
	sim.stock[sim.res_key("stone")] = 400
	var ring: int = 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if maxi(absi(dx), absi(dy)) == 2 and sim.build_valid(base.x + dx, base.y + dy):
				sim.try_build("wall", base.x + dx, base.y + dy)
				ring += 1
	# the hero walks away: the raiders go for the BASE (the branch the capsule waves redirect)
	var far: Vector2i = sim._nearest_free(sim.astar, Vector2i(sim.n - 6, sim.n - 6))
	sim.player.px = far.x + 0.5
	sim.player.py = far.y + 0.5
	var stock_before: int = sim.stock_total()
	var walls_before: int = _count_kind(sim, "wall")
	sim.raid.next = 0.0   # tests/smoke force a wave exactly like this
	var min_wall_hp: float = 1.0e9
	for t in 1500:
		sim.update(DT)
		_topup(sim)
		for b in sim.buildings:
			if String(b.kind) == "wall":
				min_wall_hp = minf(min_wall_hp, float(b.hp))
	var numeric: Dictionary = _numeric_state(sim)
	numeric["stock_lost"] = stock_before - sim.stock_total()
	numeric["walls_before"] = walls_before
	numeric["walls_after"] = _count_kind(sim, "wall")
	numeric["min_wall_hp"] = min_wall_hp
	numeric["storage_alive"] = sim.has_building("storage")
	var portable: Dictionary = {"spawn": _v(sp), "base": _v(base), "ring_walls": ring}
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


static func _count_kind(s: Variant, kind: String) -> int:
	var c: int = 0
	for b in s.buildings:
		if String(b.kind) == kind:
			c += 1
	return c


# ======================================================================================
# S7  Director.apply({incident: raid}) after GRACE_DAYS: the legacy payload path -> sized wave
# ======================================================================================
static func raid_director_apply() -> Dictionary:
	var sim: Variant = _kyiv()
	sim.time.day = 6
	sim.time.frac = 0.5
	Director.apply(sim, {"incident": "raid", "count": 3, "faction": "Тестові мародери"})
	var armed: Dictionary = {"warned": bool(sim.raid.warned), "next": float(sim.raid.next), "has_payload": sim.raid.has("director"), "banner": String(sim.banner)}
	# the hero stays at the base: the wave may kill her — then the rookie respawns MID-raid
	# (respawn_new_pawn clears enemies/raid) and the world runs on
	var died_at: int = -1
	var respawns: int = 0
	for t in 1200:
		sim.update(DT)
		if sim.dead:
			if died_at < 0:
				died_at = t
			sim.respawn_new_pawn()
			respawns += 1
		_topup(sim)
	var numeric: Dictionary = _numeric_state(sim)
	numeric["died_at"] = died_at
	numeric["respawns"] = respawns
	var portable: Dictionary = {"armed": armed}
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


# ======================================================================================
# S8  patrol robots (update_patrols/spawn_patrol) fought by the hero + a turret (damage_enemy loot rolls)
# ======================================================================================
static func patrol_fight() -> Dictionary:
	var sim: Variant = _kyiv()
	sim.research_unlocked = {"machining": true}
	sim.stock[sim.res_key("scrap")] = 60
	sim.stock[sim.res_key("components")] = 10
	var c: Vector2i = _buildable_near_spawn(sim, 1)
	sim.try_build("turret", c.x, c.y)
	sim.patrol.next = 0.0
	for t in 1200:
		sim.update(DT)
		_topup(sim)
	var numeric: Dictionary = _numeric_state(sim)
	numeric["shots"] = sim.shots.size()
	_dispose(sim)
	return {"portable": {"turret_built": sim.has_building("turret")}, "numeric": numeric}


# ======================================================================================
# S9  death -> Session.respawn (fresh pawn at base_center); stock path, inventory path
# ======================================================================================
# keep_feed = false: the landing lines are wiped (every scenario but S27 compares state, not the feed);
# true: the feed exactly as a player sees it after the drop (S27 pins THOSE strings)
static func _session(inventory: bool, keep_feed: bool = false) -> Variant:
	var a: Variant = SessionScript.new()
	_force_off(a)
	a.autosave = false
	a.use_inventory = inventory
	a.start(LAT, LON, "Київ")
	if not keep_feed:
		a.sim.messages.clear()
	return a


static func _kill(sim: Variant) -> void:
	# a smashed vital part is death on the next tick (hero_health verdict) — hit until the verdict falls
	var guard: int = 0
	while not sim.dead and guard < 40:
		HeroHealth.damage(sim, 500.0, "тест")
		sim.update(DT)
		guard += 1


static func death_respawn(inventory: bool) -> Dictionary:
	var a: Variant = _session(inventory)
	var sim: Variant = a.sim
	for t in 40:
		sim.update(DT)
	sim.player.skills.gather = 5.0
	if inventory:
		Inventory.add(sim, "wood", 9)
	else:
		sim.player.carry = {"wood": 4}
		sim.player.items = ["axe"]
	var born_before: int = int(sim.player.born)
	var pre_center: Vector2i = sim.base_center()
	sim.messages.clear()
	_kill(sim)
	var died: Dictionary = {"dead": bool(sim.dead), "cause": String(sim.last_death.get("cause", "")), "bags": sim.bags.size(),
		"bag_slots": Persistence.content_hash(sim.bags)}
	var death_lines: Array = _texts(sim)
	sim.time.day = int(sim.time.day) + 1
	a.respawn()
	var after: Dictionary = {
		"dead": bool(sim.dead), "pos": [snappedf(float(sim.player.px), 0.0001), snappedf(float(sim.player.py), 0.0001)],
		"born_is_today": int(sim.player.born) == int(sim.time.day), "born_before": born_before,
		"gather_skill": float(sim.player.skills.gather), "carry_total": sim.carry_total(), "items": (sim.player.items as Array).size(),
		"hediffs": sim.health.hediffs.size(), "enemies": sim.enemies.size(), "raid_active": bool(sim.raid.active), "banner": String(sim.banner),
		"base_center": _v(sim.base_center()), "pre_center": _v(pre_center),
		"inv_wood": Inventory.count(sim, "wood") if inventory else -1, "bags": sim.bags.size(),
	}
	var respawn_lines: Array = _texts(sim).slice(death_lines.size())
	var portable: Dictionary = {"died": died, "after": after, "death_lines_hash": Persistence.content_hash(death_lines.filter(func(t: String) -> bool: return "°" not in t)),
		"respawn_lines": respawn_lines}
	var numeric: Dictionary = _numeric_state(sim)
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


# death in a SECOND region: respawn flies the pawn home first (travel_to -> load_region + apply_pawn)
static func death_respawn_away() -> Dictionary:
	var a: Variant = _session(false)
	var sim: Variant = a.sim
	for t in 20:
		sim.update(DT)
	a.travel_to(LAT2, LON2, "Львів")
	for t in 20:
		sim.update(DT)
	var away_key: String = Persistence.region_key(float(sim.map.lat), float(sim.map.lon))
	_kill(sim)
	var was_dead: bool = bool(sim.dead)
	a.respawn()
	var home_key: String = Persistence.region_key(float(a.home.lat), float(a.home.lon))
	var cur_key: String = Persistence.region_key(float(sim.map.lat), float(sim.map.lon))
	var portable: Dictionary = {
		"away_key": away_key, "home_key": home_key, "cur_key_after": cur_key, "was_dead": was_dead, "dead_after": bool(sim.dead),
		"has_home": bool(a.has_home), "stored_regions": a.stored_region_count(),
		"pos": [snappedf(float(sim.player.px), 0.0001), snappedf(float(sim.player.py), 0.0001)],
		"base_center": _v(sim.base_center()),
	}
	var numeric: Dictionary = _numeric_state(sim)
	numeric["chain_head"] = a.chain_head()
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


# ======================================================================================
# S10  demolish matrix + base_center in every shape (storage / second storage / none)
# ======================================================================================
static func demolish_base_center() -> Dictionary:
	var s: Variant = _flat()
	var p: Dictionary = {}
	p["bc_initial"] = _v(s.base_center())
	p["demolish_empty"] = s.demolish(2, 2)
	p["demolish_last_storage"] = s.demolish(9, 8)
	s.try_build("storage", 9, 10)
	p["second_storage_built"] = s.has_building("storage")
	p["bc_two_storages"] = _v(s.base_center())
	p["stock_before_demolish"] = _sorted_stock(s)
	p["demolish_first_storage"] = s.demolish(9, 8)
	p["bc_after_first_gone"] = _v(s.base_center())
	p["stock_after_demolish"] = _sorted_stock(s)
	s.try_build("wall", 5, 5)
	p["wall_stock"] = _sorted_stock(s)
	p["demolish_wall"] = s.demolish(5, 5)
	p["wall_refund_stock"] = _sorted_stock(s)
	p["wall_cell_free_again"] = s.build_valid(5, 5)
	# the last storage dies to damage (not demolish): base_center falls back to the hero's cell
	s.player.px = 3.5
	s.player.py = 4.5
	s._damage_building(s.bgrid[10 * 16 + 9], 1000.0, false)
	p["storage_gone_by_damage"] = not s.has_building("storage")
	p["bc_no_storage"] = _v(s.base_center())
	# respawn with no storage: the rookie lands near the hero's last cell
	s.respawn_new_pawn()
	p["respawn_no_storage_pos"] = [snappedf(float(s.player.px), 0.0001), snappedf(float(s.player.py), 0.0001)]
	p["messages"] = _texts(s)
	var numeric: Dictionary = _numeric_state(s)
	_dispose(s)
	# the same verbs in an inventory world: a block comes back to the pack (Minecraft)
	var inv: Variant = _flat(195, true)
	Inventory.add(inv, "bld:wall", 2)
	inv.try_build("wall", 5, 5)
	p["inv_wall_placed"] = inv.has_building("wall")
	p["inv_pack_walls_after_place"] = Inventory.count(inv, "bld:wall")
	p["inv_demolish_wall"] = inv.demolish(5, 5)
	p["inv_pack_walls_after_demolish"] = Inventory.count(inv, "bld:wall")
	p["inv_demolish_last_storage"] = inv.demolish(9, 8)
	p["inv_messages"] = _texts(inv)
	numeric["inv_world_hash"] = Persistence.world_hash(inv)
	_dispose(inv)
	return {"portable": p, "numeric": numeric}


# ======================================================================================
# S11  storage reach: stash/take radius, full storage, link perk, bench reach (inventory world) + OFF auto-deposit/eat
# ======================================================================================
static func storage_reach() -> Dictionary:
	var p: Dictionary = {}
	var s: Variant = _flat(195, true)
	var rows: Dictionary = {}
	for d in [0.0, 2.45, 2.49, 2.5, 2.51, 2.55, 3.0]:
		s.player.px = 9.5 + d
		s.player.py = 8.5
		s.player.inv = Inventory.empty_slots()
		s.stock[s.res_key("wood")] = 50
		Inventory.add(s, "wood", 7)
		var near: bool = Inventory.near_storage(s)
		var stash: Dictionary = Inventory.stash_all(s)
		var take: Dictionary = Inventory.take_from_storage(s, "wood", 3)
		rows[str(d)] = {"near": near, "stash": stash, "take": take, "stock_wood": s.res_amount("wood"), "pack_wood": Inventory.count(s, "wood")}
	p["reach_rows"] = rows
	# full / almost-full storage (cap = 200 base + 250 per storage)
	s.player.px = 9.5
	s.player.py = 8.5
	s.player.inv = Inventory.empty_slots()
	s.stock.clear()
	s.stock[s.res_key("wood")] = s.storage_cap() - 3
	Inventory.add(s, "wood", 7)
	p["cap"] = s.storage_cap()
	p["stash_almost_full"] = Inventory.stash_all(s)
	p["pack_after_almost_full"] = Inventory.count(s, "wood")
	p["stash_full"] = Inventory.stash_all(s)
	p["take_nothing_there"] = Inventory.take_from_storage(s, "stone", 1)
	# storage link perk (gather >= 2): pays from storages within 10 tiles of `at`
	s.stock.clear()
	s.stock[s.res_key("wood")] = 30
	s.player.inv = Inventory.empty_slots()
	var cost: Dictionary = {"wood": 5}
	var link: Dictionary = {}
	for skill in [0.0, 1.9, 2.0]:
		s.player.skills.gather = skill
		for dx in [0.0, 9.99, 10.0, 10.01, 10.1]:
			var at: Vector2 = Vector2(9.5 + dx, 8.5)
			link["%s@%s" % [str(skill), str(dx)]] = Inventory.can_pay(s, cost, at)
	p["link_can_pay"] = link
	# bench reach for non-hand-craft buildings (STATION_REACH 3.5 from the bench centre)
	s.research_unlocked = {"machining": true}
	s.stock.clear()
	s._place_building("workbench", 4, 8, -1)
	var bench_rows: Dictionary = {}
	for d in [0.0, 3.45, 3.5, 3.51, 3.6]:
		s.player.px = 4.5 + d
		s.player.py = 8.5
		s.player.inv = Inventory.empty_slots()
		Inventory.add(s, "scrap", 14)
		Inventory.add(s, "components", 2)
		bench_rows[str(d)] = Inventory.craft_building(s, "turret")
	p["bench_rows"] = bench_rows
	p["hand_craft_bed_without_bench_msg"] = Inventory.craft_building(_hand_probe(), "bed")
	_dispose(s)
	# OFF world (stock path): auto-deposit within 1.8, auto-eat within 2.2 of a storage
	var o: Variant = _flat(195, false)
	var off_rows: Dictionary = {}
	for d in [1.7, 1.79, 1.81, 1.9, 2.1, 2.19, 2.21, 2.3]:
		o.player.px = 9.5 + d
		o.player.py = 8.5
		o.player.carry = {"wood": 5}
		o.player.eat_cd = 0.0
		o.player.dep_cd = 0.0
		o.player.hunger = 40.0
		o.stock[o.res_key("wood")] = 50
		o.stock[o.res_key("food")] = 18
		o.update(DT)
		off_rows[str(d)] = {"carry": o.carry_total(), "wood": o.res_amount("wood"), "food": o.res_amount("food"),
			"hunger": snappedf(float(o.player.hunger), 0.0001)}
	p["off_rows"] = off_rows
	# nearest storage (haul target): two storages, the hero closer to the second
	o.try_build("storage", 9, 13)
	var near_pick: Dictionary = {}
	for py in [6.5, 10.4, 10.49, 10.51, 10.6, 14.5]:
		o.player.px = 9.5
		o.player.py = py
		var st: Variant = o._nearest_storage()
		near_pick[str(py)] = [int(st.x), int(st.y)] if st != null else []
	p["nearest_storage"] = near_pick
	_dispose(o)
	return {"portable": p, "numeric": {}}


# a hand-craft probe sim for the "bed needs no bench" refusal/ok text (own tiny inventory world)
static func _hand_probe() -> Variant:
	var h: Variant = _flat(195, true)
	h.player.px = 9.5
	h.player.py = 8.5
	h.stock.clear()
	return h


# ======================================================================================
# S12  workbench: build cost, craft_item gates/refusals, plank crafting timer
# ======================================================================================
static func workbench_craft() -> Dictionary:
	var s: Variant = _flat()
	var p: Dictionary = {}
	p["axe_without_bench"] = s.craft_item("axe")
	p["unknown_item"] = s.craft_item("nope")
	p["stock_start"] = _sorted_stock(s)
	s.try_build("workbench", 5, 8)
	p["bench_built"] = s.has_workbench()
	p["stock_after_bench"] = _sorted_stock(s)
	p["axe"] = s.craft_item("axe")
	p["axe_equipped"] = String(s.player.equipped.tool)
	p["stock_after_axe"] = _sorted_stock(s)
	p["axe_again_free"] = s.craft_item("axe")
	p["stock_after_axe_again"] = _sorted_stock(s)
	p["sledge_gated"] = s.craft_item("sledge")
	var wood_keep: int = s.res_amount("wood")
	s.stock[s.res_key("wood")] = 3
	p["club_short"] = s.craft_item("club")
	s.stock[s.res_key("wood")] = wood_keep + 30   # enough wood for the plank loop below
	p["gather_time_tree_skill0"] = snappedf(s.gather_time({"kind": "tree"}), 0.0001)
	s.try_build("workbench", 5, 10)
	for t in 700:
		s.update(DT)
	var numeric: Dictionary = _numeric_state(s)
	numeric["planks"] = s.res_amount("planks")
	numeric["wood"] = s.res_amount("wood")
	numeric["craft_timer"] = float(s.craft_timer)
	var portable_tail: Dictionary = {"planks_made": s.res_amount("planks")}
	p["after_700"] = portable_tail
	_dispose(s)
	# inventory world: tools crafted into the pack, paid from the pack
	var inv: Variant = _flat(195, true)
	Inventory.add(inv, "wood", 40)
	Inventory.add(inv, "stone", 30)
	inv._place_building("workbench", 8, 9, -1)
	inv.player.px = 8.5
	inv.player.py = 8.5
	p["inv_axe"] = inv.craft_item("axe")
	p["inv_pack_after"] = {"wood": Inventory.count(inv, "wood"), "stone": Inventory.count(inv, "stone"), "axe": Inventory.count(inv, "axe")}
	numeric["inv_world_hash"] = Persistence.world_hash(inv)
	_dispose(inv)
	return {"portable": p, "numeric": numeric}


# ======================================================================================
# S13  REQ-0012-81 / S6: the daily capsule (spec 0002) across the day boundary (150 s days)
# ======================================================================================
static func capsule_day_transition() -> Dictionary:
	var f: Variant = _flat()   # summer noon on a flat pad: survivable by construction -> portable arithmetic
	f.capsule.charges = 0
	f.capsule.last_day = int(f.time.day)
	var day0: int = int(f.time.day)
	var ticks: int = 0
	while int(f.time.day) == day0 and ticks < 2000:
		f.update(DT)
		ticks += 1
	var portable: Dictionary = {
		"day_len": float(f.time.day_len), "time_keys": _sorted_keys(f.time), "ticks_to_next_day": ticks,
		"day_after": int(f.time.day), "capsule_after": f.capsule.duplicate(true), "capsule_keys": _sorted_keys(f.capsule),
		"lines": _texts(f).filter(func(t: String) -> bool: return "Новий день" in t or "капсул" in t),
		"default_capsule": f._default_capsule(),
		"consts": [GameData.CAPSULE_DAILY_CHARGES, GameData.CAPSULE_BASE_RADIUS_KM],
	}
	# a second boundary while the charge is still unused: no new line, charges stay at the cap
	var lines_before: int = _texts(f).size()
	var day1: int = int(f.time.day)
	var t2: int = 0
	while int(f.time.day) == day1 and t2 < 2000:
		f.update(DT)
		t2 += 1
	portable["second_boundary_ticks"] = t2
	portable["second_boundary_capsule"] = f.capsule.duplicate(true)
	portable["second_boundary_new_lines"] = _texts(f).size() - lines_before
	# the Kyiv world: same transition through the live climate/director path (numeric tier)
	var sim: Variant = _kyiv()
	sim.capsule.charges = 0
	var kd0: int = int(sim.time.day)
	var kt: int = 0
	while int(sim.time.day) == kd0 and kt < 2000:
		sim.update(DT)
		_topup(sim)
		kt += 1
	var numeric: Dictionary = _numeric_state(sim)
	numeric["kyiv_ticks_to_next_day"] = kt
	numeric["kyiv_capsule"] = sim.capsule.duplicate(true)
	_dispose(f)
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


# ======================================================================================
# S14  try_launch_capsule / capsule_can_reach / invites (texts + charge accounting)
# ======================================================================================
static func capsule_launch() -> Dictionary:
	var sim: Variant = _kyiv()
	sim.messages.clear()
	var p: Dictionary = {}
	var numeric: Dictionary = {}
	var far: Dictionary = sim.capsule_can_reach(LAT2, LON2)   # Львів: > 100 km
	p["far_ok"] = bool(far.ok)
	numeric["far_msg"] = String(far.msg)
	numeric["far_km"] = float(far.km)
	var near_lat: float = 50.2
	var near_lon: float = 30.6
	var near: Dictionary = sim.capsule_can_reach(near_lat, near_lon)
	p["near_ok"] = bool(near.ok)
	numeric["near_msg"] = String(near.msg)
	var l1: Dictionary = sim.try_launch_capsule(near_lat, near_lon, "Недалеко")
	p["launch_ok"] = bool(l1.ok)
	p["launch_keys"] = _sorted_keys(l1)
	p["charges_after"] = int(sim.capsule.charges)
	var l2: Dictionary = sim.try_launch_capsule(near_lat, near_lon, "Недалеко")
	p["second_launch"] = l2
	p["second_reach"] = sim.capsule_can_reach(near_lat, near_lon)
	var l3: Dictionary = sim.try_launch_capsule(LAT2, LON2, "Львів")
	p["launch_too_far_after_use"] = l3
	# invites
	sim.add_invite({"id": "i1", "inviter": "Друг", "clan": "К", "name": "Місце", "lat": near_lat, "lon": near_lon, "allow_receive": false, "radius_km": 100.0}, true)
	sim.add_invite({"id": "i1", "inviter": "Дубль", "clan": "К", "name": "Дубль", "lat": near_lat, "lon": near_lon, "allow_receive": true, "radius_km": 100.0}, true)
	p["invites_after_dup"] = sim.invites.size()
	p["accept_missing"] = sim.accept_invite("nope")
	p["accept_denied"] = sim.accept_invite("i1")
	sim.invites[0].allow_receive = true
	sim.capsule.charges = 1
	var acc: Dictionary = sim.accept_invite("i1")
	p["accept_ok"] = bool(acc.ok)
	p["invites_after_accept"] = sim.invites.size()
	p["charges_after_accept"] = int(sim.capsule.charges)
	p["launch_lines"] = _texts(sim).filter(func(t: String) -> bool: return "км" not in t)
	numeric["launch_lines_km"] = _texts(sim).filter(func(t: String) -> bool: return "км" in t)
	_dispose(sim)
	return {"portable": p, "numeric": numeric}


# ======================================================================================
# S15  Session.travel_to: new region (arrive_region), return (load_region + apply_pawn), hash chain
# ======================================================================================
static func travel_regions() -> Dictionary:
	var a: Variant = _session(false)
	var sim: Variant = a.sim
	var c: Vector2i = _buildable_near_spawn(sim, 2)
	sim.try_build("campfire", c.x, c.y)
	sim.try_build("wall", _buildable_near_spawn(sim, 5).x, _buildable_near_spawn(sim, 5).y)
	for t in 60:
		sim.update(DT)
		_topup(sim)
	var home_buildings: Array = _buildings(sim)
	var home_center: Vector2i = sim.base_center()
	var day_before: int = int(sim.time.day)
	a.travel_to(LAT2, LON2, "Львів")
	var away: Dictionary = {
		"buildings": sim.buildings.size(), "stock": sim.stock.size(), "base_center_is_hero": sim.base_center() == Vector2i(int(sim.player.px), int(sim.player.py)),
		"key": Persistence.region_key(float(sim.map.lat), float(sim.map.lon)), "day_kept": int(sim.time.day) == day_before,
		"regions": sim.regions.size(), "place": String(sim.map.get("place_name", "")),
	}
	for t in 60:
		sim.update(DT)
		_topup(sim)
	a.travel_to(LAT, LON, "Київ")
	var back: Dictionary = {
		"buildings": _buildings(sim), "same_as_before": _buildings(sim) == home_buildings, "base_center": _v(sim.base_center()), "home_center": _v(home_center),
		"pos": [snappedf(float(sim.player.px), 0.0001), snappedf(float(sim.player.py), 0.0001)],
		"stored_regions": a.stored_region_count(), "key": Persistence.region_key(float(sim.map.lat), float(sim.map.lon)),
		"day_kept": int(sim.time.day) >= day_before,
	}
	var portable: Dictionary = {"away": away, "back": back}
	var numeric: Dictionary = _numeric_state(sim)
	numeric["chain_head"] = a.chain_head()
	numeric["regions"] = Persistence.content_hash(sim.regions)
	_dispose(sim)
	return {"portable": portable, "numeric": numeric}


# ======================================================================================
# S16  Session.save_game: key-path schema, SAVE_VERSION, byte-exact string, restore, resave (3 world kinds)
# ======================================================================================
const SAVE_TMP := "user://off_baseline_save.json"
const SAVE_KINDS := ["stock", "inventory", "catalog"]

# the Session of a catalogue world (Session.start has no catalog knob: assemble the same fields by hand)
static func _catalog_session() -> Variant:
	var a: Variant = SessionScript.new()
	_force_off(a)
	a.autosave = false
	var sim: Variant = Sim.new()
	_force_off(sim)
	sim.use_catalog = true
	var m: Dictionary = WorldGen.generate_map(LAT, LON, N)
	m["place_name"] = "Київ"
	sim.new_game(m, false)
	a.sim = sim
	a.progression = Progression.new(Catalog.load_json())
	a.store = Persistence.store_new()
	a.social = Social.new_graph("Ти", WorldGen.hash_seed(LAT, LON), LAT, LON)
	sim.social = a.social
	a.home = {"lat": LAT, "lon": LON, "name": "Київ"}
	a.has_home = true
	sim.messages.clear()
	return a


static func _give(sim: Variant, kind: String) -> void:
	if sim.use_inventory:
		Inventory.add(sim, "bld:" + kind, 1)   # buildings are items in the personal-inventory world


# the canonical OFF session used for the fixture saves: a base, research, goals, two regions in the store
static func _save_session(kind: String) -> Variant:
	var a: Variant = _catalog_session() if kind == "catalog" else _session(kind == "inventory")
	var sim: Variant = a.sim
	var c: Vector2i = _buildable_near_spawn(sim, 2)
	sim.try_build("campfire", c.x, c.y)
	var w: Vector2i = _buildable_near_spawn(sim, 6)
	_give(sim, "wall")
	sim.try_build("wall", w.x, w.y)
	var wb: Vector2i = _buildable_near_spawn(sim, 8)
	_give(sim, "workbench")
	sim.try_build("workbench", wb.x, wb.y)
	a.enqueue_research("carpentry")
	for i in 120:
		sim.update(0.25)
		a.tick_research(0.25)
	a.tick_goals(1.0)
	a.travel_to(LAT2, LON2, "Львів")
	for i in 20:
		sim.update(0.25)
	a.travel_to(LAT, LON, "Київ")
	for i in 20:
		sim.update(0.25)
	return a


static func read_text(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt


static func _rm(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# {"text": String, "result": {portable, numeric}} — text is the exact save string a baseline build writes.
# NB: no "restore -> same world_hash" pin on purpose: Godot's JSON number parser is off by 1 ulp for ~9% of
# doubles, so a restored world may legitimately differ from the live one in the 15th digit of a float
# (see the S0 report); pinning that would freeze a defect as an expectation.
static func save_session_text(kind: String) -> Dictionary:
	var a: Variant = _save_session(kind)
	var ok_write: bool = bool(a.save_game(SAVE_TMP))
	var txt: String = read_text(SAVE_TMP)
	var parsed: Variant = JSON.parse_string(txt)
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var portable: Dictionary = {
		"written": ok_write, "version": int(data.get("version", -1)), "save_version_const": SessionScript.SAVE_VERSION,
		"top_keys": _sorted_keys(data), "key_paths": paths_of(data), "goals": data.get("goals", []),
		"capsule": data.get("capsule", {}), "meta_keys": _sorted_keys(data.get("meta", {})),
		"store_version": int(((data.get("store", {}) as Dictionary).get("version", -1))),
		"store_regions": (((data.get("store", {}) as Dictionary).get("regions", {})) as Dictionary).size(),
		"active_use_inventory": bool((((data.get("active", {}) as Dictionary).get("region", {})) as Dictionary).get("use_inventory", false)),
		"active_use_catalog": bool((((data.get("active", {}) as Dictionary).get("region", {})) as Dictionary).get("use_catalog", false)),
	}
	var b: Variant = SessionScript.new()
	_force_off(b)
	b.autosave = false
	var restored: bool = bool(b.restore_game(SAVE_TMP))
	portable["restored"] = restored
	var live_hash: String = Persistence.world_hash(a.sim)
	var numeric: Dictionary = {
		"sha256": txt.sha256_text(), "length": txt.length(), "world_hash": live_hash,
		"content_hash_of_text": Persistence.content_hash(data),
	}
	if restored:
		var resaved: bool = bool(b.save_game(SAVE_TMP + ".2"))
		var txt2: String = read_text(SAVE_TMP + ".2")
		var parsed2: Variant = JSON.parse_string(txt2)
		portable["resave_written"] = resaved
		portable["resave_paths_equal"] = paths_of(parsed2 if parsed2 is Dictionary else {}) == portable["key_paths"]
		numeric["restored_world_hash"] = Persistence.world_hash(b.sim)
		numeric["resave_sha256"] = txt2.sha256_text()
	_rm(SAVE_TMP)
	_rm(SAVE_TMP + ".2")
	_dispose(a.sim)
	if restored:
		_dispose(b.sim)
	return {"text": txt, "result": {"portable": portable, "numeric": numeric}}


static func save_continue() -> Dictionary:
	var portable: Dictionary = {}
	var numeric: Dictionary = {}
	for kind in SAVE_KINDS:
		var r: Dictionary = save_session_text(String(kind)).result
		portable[kind] = r.portable
		numeric[kind] = r.numeric
	return {"portable": portable, "numeric": numeric}


# Replays a SAVED TEXT (a legacy fixture) through restore_game and reports what a baseline-OFF load must show.
# portable = what the text alone determines; numeric = hashes / the world continued for 40 ticks.
static func restore_legacy(text: String) -> Dictionary:
	var path: String = "user://off_baseline_legacy.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var a: Variant = SessionScript.new()
	_force_off(a)
	a.autosave = false
	var restored: bool = bool(a.restore_game(path))
	var portable: Dictionary = {"restored": restored}
	var numeric: Dictionary = {}
	if restored:
		var sim: Variant = a.sim
		portable["flags"] = {
			"use_inventory": bool(sim.use_inventory), "use_catalog": bool(sim.use_catalog),
			"future_flags_off": _future_flags_off(sim) and _future_flags_off(a),
		}
		portable["home"] = a.home.duplicate()
		portable["has_home"] = bool(a.has_home)
		portable["capsule"] = sim.capsule.duplicate(true)
		portable["invites"] = sim.invites.size()
		portable["goals_done"] = _sorted_keys(a.goals_done)
		portable["buildings"] = _buildings(sim)
		portable["bags"] = sim.bags.size()
		portable["day"] = int(sim.time.day)
		portable["day_len"] = float(sim.time.day_len)
		portable["dead"] = bool(sim.dead)
		portable["stored_regions"] = a.stored_region_count()
		portable["chain_head"] = a.chain_head()
		var parsed: Variant = JSON.parse_string(text)
		var orig_paths: Array = paths_of(parsed if parsed is Dictionary else {})
		var resaved: bool = bool(a.save_game(path + ".2"))
		var txt2: String = read_text(path + ".2")
		var parsed2: Variant = JSON.parse_string(txt2)
		portable["resave_paths_equal"] = resaved and paths_of(parsed2 if parsed2 is Dictionary else {}) == orig_paths
		numeric["world_hash"] = Persistence.world_hash(sim)
		numeric["resave_sha256"] = txt2.sha256_text()
		for i in 40:
			sim.update(0.25)
		numeric["continue_world_hash"] = Persistence.world_hash(sim)
		_dispose(sim)
	_rm(path)
	_rm(path + ".2")
	return {"portable": portable, "numeric": numeric}


static func _future_flags_off(o: Object) -> bool:
	for f in FUTURE_FLAGS:
		if f in o and bool(o.get(f)):
			return false
	return true


# ======================================================================================
# S17  gather -> auto-haul loop with a tiny carry cap (nearest-storage + haul resume branches)
# ======================================================================================
static func gather_haul() -> Dictionary:
	var sim: Variant = _kyiv()
	var tree: Vector2i = _nearest_tree(sim)
	sim.player.carry_cap = 3
	sim.order_gather(tree.x, tree.y)
	for t in 2500:
		sim.update(DT)
		_topup(sim)
	var numeric: Dictionary = _numeric_state(sim)
	numeric["carry"] = sim.carry_total()
	numeric["gather_skill"] = float(sim.player.skills.gather)
	numeric["nodes_hash"] = Persistence.content_hash(sim.map.nodes)
	_dispose(sim)
	return {"portable": {}, "numeric": numeric}


# ======================================================================================
# S18  the per-second need constants + day length, through observable arithmetic (portable)
# ======================================================================================
static func needs_pace() -> Dictionary:
	var p: Dictionary = {}
	var s: Variant = _flat()
	p["day_len"] = float(s.time.day_len)
	p["start"] = [float(s.player.hunger), float(s.player.rest), float(s.time.frac)]
	for t in 100:
		s.update(DT)
	p["after_100_ticks"] = [float(s.player.hunger), float(s.player.rest), float(s.time.frac), int(s.time.day)]
	_dispose(s)
	# eating at a storage (hunger < 55, within 2.2): +38, 2.5 s cooldown
	var e: Variant = _flat()
	e.player.px = 9.5
	e.player.py = 8.5
	e.player.hunger = 40.0
	e.update(DT)
	p["eat_one_tick"] = [float(e.player.hunger), e.res_amount("food"), float(e.player.eat_cd)]
	for t in 30:
		e.update(DT)
	p["eat_after_3s"] = [float(e.player.hunger), e.res_amount("food")]
	_dispose(e)
	# sleeping in a bed: rest climbs +14/s instead of draining 0.30/s
	var b: Variant = _flat()
	b._place_building("bed", 7, 8, -1)
	b.player.px = 7.5
	b.player.py = 8.5
	b.player.rest = 40.0
	for t in 50:
		b.update(DT)
	p["sleep_50_ticks"] = [float(b.player.rest), bool(b.player.sleeping)]
	_dispose(b)
	# a full day of frac arithmetic: the day counter turns exactly when frac crosses 1.0
	var d: Variant = _flat()
	var n_ticks: int = 0
	var d0: int = int(d.time.day)
	while int(d.time.day) == d0 and n_ticks < 5000:
		d.update(DT)
		n_ticks += 1
	p["ticks_to_day_turn_from_noon"] = n_ticks
	p["frac_after_turn"] = float(d.time.frac)
	_dispose(d)
	return {"portable": p, "numeric": {}}


# ======================================================================================
# S19  spawn presets: map generation + storage landing + base_center (pure, portable)
# ======================================================================================
static func spawn_presets() -> Dictionary:
	var rows: Dictionary = {}
	for pr in GameData.SPAWN_PRESETS:
		var m: Dictionary = WorldGen.generate_map(float(pr.lat), float(pr.lon), N)
		var sim: Variant = Sim.new()
		_force_off(sim)
		sim.new_game(m, false)
		var storage: Array = []
		for b in sim.buildings:
			if String(b.kind) == "storage":
				storage = [int(b.x), int(b.y)]
		rows[String(pr.name)] = {
			"key": WorldGen.canon_coord(float(pr.lat), float(pr.lon)), "seed": WorldGen.hash_seed(float(pr.lat), float(pr.lon)),
			"spawn": _v(m.spawn), "storage": storage, "base_center": _v(sim.base_center()),
			"player": [float(sim.player.px), float(sim.player.py)], "tiles_sha256": m.tiles.hex_encode().sha256_text(),
			"nodes_hash": Persistence.content_hash(m.nodes), "buildings": sim.buildings.size(), "regions": sim.regions.size(),
			"stock": _sorted_stock(sim),
		}
		_dispose(sim)
	return {"portable": {"rows": rows}, "numeric": {}}


# ======================================================================================
# S20  record schema across every OFF variant (inventory / catalog / osm / buildings with module state)
# ======================================================================================
static func record_keys() -> Dictionary:
	var p: Dictionary = {}
	var base: Variant = _flat()
	var rec: Dictionary = Persistence.serialize_region(base)
	p["base_region_paths"] = paths_of(rec)
	p["base_runtime_paths"] = paths_of(Persistence.serialize_runtime(base))
	p["player_fields"] = Persistence.PLAYER_FIELDS
	p["store_version"] = Persistence.STORE_VERSION
	p["enemy_hash_fields"] = Persistence.ENEMY_HASH_FIELDS
	p["shot_hash_fields"] = Persistence.SHOT_HASH_FIELDS
	p["health_dict_keys"] = _sorted_keys(base.health_dict())
	_dispose(base)
	var inv: Variant = _flat(195, true)
	p["inventory_region_keys"] = _sorted_keys(Persistence.serialize_region(inv))
	_dispose(inv)
	var cat: Variant = _flat(195, false, true)
	p["catalog_region_keys"] = _sorted_keys(Persistence.serialize_region(cat))
	_dispose(cat)
	var osm: Variant = _flat()
	osm.map["source"] = "osm"
	p["osm_region_keys"] = _sorted_keys(Persistence.serialize_region(osm))
	_dispose(osm)
	# building records carry module state only for defs that have it
	var cs: Variant = _flat(195, false, true)
	cs.research_unlocked = {"electricity": true, "plasteel_working": true, "agriculture": true, "defense_systems": true}
	for res in ["planks", "components", "steel", "circuit", "stone", "clay", "wood", "copper_wire", "chemfuel", "ammo"]:
		cs.stock[cs.res_key(res)] = 40
	cs.try_build("wood_generator", 5, 3)
	cs.try_build("grow_zone", 3, 6)
	cs.try_build("auto_turret", 7, 3)
	cs.try_build("campfire", 10, 10)
	for t in 20:
		cs.update(0.5)
	var bkeys: Dictionary = {}
	for b in Persistence.serialize_region(cs).buildings:
		var ks: Array = _sorted_keys(b)
		bkeys[String(b.kind)] = ks
	p["building_record_keys"] = bkeys
	_dispose(cs)
	return {"portable": p, "numeric": {}}


# ======================================================================================
# S21  REQ-0012-3: goals chain (10, ordered), speed grammar (x1-x3 + pause), session goals_view at start
# ======================================================================================
static func goals_speeds() -> Dictionary:
	var p: Dictionary = {}
	var ids: Array = []
	var titles: Array = []
	var hints: Array = []
	for g in Goals.GOALS:
		ids.append(String(g.id))
		titles.append(String(g.title))
		hints.append(String(g.hint))
	p["goal_count"] = Goals.count()
	p["goal_ids"] = ids
	p["goal_titles_hash"] = Persistence.content_hash(titles)
	p["goal_hints_hash"] = Persistence.content_hash(hints)
	p["inv_hint_hash"] = Persistence.content_hash(Goals.INV_HINT)
	p["goal_consts"] = [Goals.FOOD_TARGET, Goals.GATHER_TARGET, Goals.SURVIVE_DAY]
	var WI: Variant = WorldInputScript.WorldInput
	p["speeds"] = WI.SPEEDS
	var matrix: Dictionary = {}
	for cur in [0.0, 1.0, 2.0, 3.0]:
		for last in [1.0, 2.0, 3.0]:
			for act in [&"toggle_pause", &"faster", &"slower", &"set", &"noop"]:
				matrix["%s/%s/%s" % [str(cur), str(last), String(act)]] = WI.next_speed(cur, last, act, 0.0 if act == &"set" else 1.0)
	p["speed_matrix"] = matrix
	var a: Variant = _session(false)
	p["goals_view_at_start"] = a.goals_view()
	var prog: Dictionary = {}
	for g in Goals.GOALS:
		prog[String(g.id)] = Goals.progress(String(g.id), a.sim, a)
	p["goal_progress_at_start"] = prog
	p["day_len_at_start"] = float(a.sim.time.day_len)
	_dispose(a.sim)
	return {"portable": p, "numeric": {}}


# ======================================================================================
# S22  OSM overlay + after_map_change: the storage RELOCATES to the new clearing, tiles ride the record
# ======================================================================================
static func _storage_cell(s: Variant) -> Array:
	for b in s.buildings:
		if String(b.kind) == "storage":
			return [int(b.x), int(b.y)]
	return []


static func osm_overlay() -> Dictionary:
	var s: Variant = Sim.new()
	_force_off(s)
	s.new_game(WorldGen.generate_map(50.0, 30.0, 16), false)
	var p: Dictionary = {"storage_before": _storage_cell(s), "spawn_before": _v(s.map.spawn)}
	var bbox: Dictionary = {"s": 49.99, "n": 50.01, "w": 29.99, "e": 30.01}
	var elements: Array = [
		{"type": "way", "tags": {"highway": "residential"}, "geometry": [{"lat": 50.0, "lon": 29.991}, {"lat": 50.0, "lon": 30.009}]},
		{"type": "way", "tags": {"natural": "water"}, "geometry": [{"lat": 50.004, "lon": 29.992}, {"lat": 50.004, "lon": 29.996},
			{"lat": 50.008, "lon": 29.996}, {"lat": 50.008, "lon": 29.992}, {"lat": 50.004, "lon": 29.992}]},
	]
	WorldGen.overlay_osm(s.map, elements, bbox)
	s.after_map_change()
	var sc: Array = _storage_cell(s)
	p["source"] = String(s.map.get("source", ""))
	p["spawn_after"] = _v(s.map.spawn)
	p["storage_after"] = sc
	p["storage_in_bgrid"] = sc.size() == 2 and s.bgrid.has(int(sc[1]) * s.n + int(sc[0]))
	p["base_center"] = _v(s.base_center())
	p["player"] = [float(s.player.px), float(s.player.py)]
	p["tiles_sha256"] = s.map.tiles.hex_encode().sha256_text()
	var rec: Dictionary = Persistence.serialize_region(s)
	p["record_keys"] = _sorted_keys(rec)
	var s2: Variant = Sim.new()
	_force_off(s2)
	s2.load_region(rec)
	p["reload_tiles_equal"] = s2.map.tiles == s.map.tiles
	p["reload_spawn"] = _v(s2.map.spawn)
	p["reload_storage"] = _storage_cell(s2)
	var numeric: Dictionary = {"world_hash": Persistence.world_hash(s), "reload_region_hash": Persistence.content_hash(Persistence.serialize_region(s2))}
	_dispose(s)
	_dispose(s2)
	return {"portable": p, "numeric": numeric}


# ======================================================================================
# S23  seeded verb fuzz: a long random command stream through the PUBLIC verbs (stock + inventory worlds).
# One hash over a messy path that touches build/demolish/repair/craft/stash/convoy/raid/respawn together —
# any OFF-mode behaviour change in any of them moves it. The rng is test-side and seeded (never the sim's).
# ======================================================================================
static func _fuzz_world(inventory: bool, seed_val: int, ticks: int) -> Dictionary:
	var sim: Variant = _kyiv(inventory, false)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val
	var sp: Vector2i = sim.map.spawn
	var node_cells: Array = sim.map.nodes.keys()
	node_cells.sort()
	var kinds: Array = ["wall", "door", "floor", "campfire", "torch", "bed", "workbench", "storage"]
	var counts: Dictionary = {"build": 0, "demolish_ok": 0, "repair_ok": 0, "craft_ok": 0, "stash_ok": 0, "take_ok": 0, "convoy_ok": 0, "respawn": 0, "raid": 0}
	sim.research_unlocked = {"hunting": true, "machining": true}
	for t in ticks:
		if t == 40:
			if inventory:
				Inventory.add(sim, "bld:workbench", 1)
			sim.try_build("workbench", sp.x - 2, sp.y - 2)
			if inventory:
				Inventory.add(sim, "wood", 40)
		if t == 600 or t == 1500:
			sim.raid.next = float(sim.raid.timer) + 1.0   # forced waves, like the smoke tests
			counts.raid += 1
		if t % 8 == 0:
			var verb: int = rng.randi() % 10
			var cx: int = sp.x + rng.randi_range(-6, 6)
			var cy: int = sp.y + rng.randi_range(-6, 6)
			match verb:
				0, 1:
					var kind: String = String(kinds[rng.randi() % kinds.size()])
					if inventory:
						Inventory.craft_building(sim, kind)
					var before: int = sim.buildings.size()
					sim.try_build(kind, cx, cy)
					counts.build += 1 if sim.buildings.size() > before else 0
				2:
					counts.demolish_ok += 1 if bool(sim.demolish(cx, cy).ok) else 0
				3:
					var cell: int = int(node_cells[rng.randi() % node_cells.size()])
					if sim.map.nodes.has(cell):
						sim.order_gather(cell % sim.n, cell / sim.n)
				4:
					sim.order_move(cx, cy)
				5:
					var item: String = String(GameData.ITEM_ORDER[rng.randi() % GameData.ITEM_ORDER.size()])
					counts.craft_ok += 1 if bool(sim.craft_item(item).ok) else 0
				6:
					var rx: int = cx
					var ry: int = cy
					for b in sim.buildings:   # aim at the first worn building, else a random cell
						if float(b.hp) < float(sim.building_def(String(b.kind)).get("hp", 50.0)):
							rx = int(b.x)
							ry = int(b.y)
							break
					counts.repair_ok += 1 if bool(Upkeep.repair(sim, rx, ry).ok) else 0
				7:
					if inventory:
						var st: Variant = sim._nearest_storage()
						if st != null and rng.randi() % 2 == 0:
							sim.player.px = float(st.x) + 0.5
							sim.player.py = float(st.y) + 0.5
						counts.stash_ok += 1 if bool(Inventory.stash_all(sim).ok) else 0
						var res: String = String(GameData.RES_ORDER[rng.randi() % GameData.RES_ORDER.size()])
						counts.take_ok += 1 if bool(Inventory.take_from_storage(sim, res, 1 + rng.randi() % 9).ok) else 0
					else:
						var hub: int = 1 + rng.randi() % 3
						var offer: Dictionary = sim.regions[hub].offer if hub < sim.regions.size() else {}
						if not offer.is_empty():
							counts.convoy_ok += 1 if bool(sim.dispatch_convoy(hub, String(offer.buys), 1 + rng.randi() % 20).ok) else 0
				8:
					var near_b: Variant = sim.bgrid.get(cy * sim.n + cx, null)
					if near_b != null:
						sim._damage_building(near_b, 10.0, false)   # wear, so repair has work
				9:
					sim.player.carry = {"wood": rng.randi() % 5}
		sim.update(DT)
		_topup(sim)
		if sim.dead:
			sim.respawn_new_pawn()
			counts.respawn += 1
	var numeric: Dictionary = _numeric_state(sim)
	numeric["counts"] = counts
	_dispose(sim)
	return numeric


static func fuzz_verbs() -> Dictionary:
	return {"portable": {}, "numeric": {"stock_world": _fuzz_world(false, 20261105, 2400), "inventory_world": _fuzz_world(true, 20261106, 2400)}}


# ======================================================================================
# S24  Director gating without the rng: a balance stub fires ONE incident every tick; the sim must enact it
# only for LIVE incidents past their grace day (raid 5, disease 3, cold_snap 3) — the table the capsule
# waves re-wire (Director.apply(raid) -> the raid automaton). Forced apply() bypasses grace.
# ======================================================================================
class FiringBalance extends KernelBalance.Balance:
	var payload: Dictionary = {}

	func tick(_world: Variant, _ctx: Dictionary, _rng: RandomNumberGenerator) -> Array:
		return [payload.duplicate(true)]


static func _incident_outcome(s: Variant, wood_before: int) -> Dictionary:
	return {
		"raid_armed": bool(s.raid.get("warned", false)) and s.raid.has("director"), "banner": String(s.banner),
		"disease": s.health.hediffs.size() > 0, "cold_snap": float(s.temp_offset_days) > 0.0 and float(s.temp_offset) < 0.0,
		"cargo_wood": s.res_amount("wood") - wood_before,
	}


static func director_grace() -> Dictionary:
	var payloads: Dictionary = {
		"raid": {"incident": "raid", "count": 2, "faction": "Тест"},
		"disease": {"incident": "disease", "label": "тест-хвороба"},
		"cold_snap": {"incident": "cold_snap", "drop_c": 10.0, "days": 2.0},
		"cargo": {"incident": "cargo", "stock": {"wood": 5}},
		"infestation": {"incident": "infestation"},
		"quest": {"incident": "quest"},
		"manhunter": {"incident": "manhunter"},
	}
	var rolled: Dictionary = {}
	var forced: Dictionary = {}
	for name in payloads:
		for day in range(1, 8):
			var s: Variant = _flat(day)
			var fb: Variant = FiringBalance.new()
			fb.payload = payloads[name]
			s.balance = fb
			var wood0: int = s.res_amount("wood")
			Director.update(s, 0.1)
			rolled["%s@day%d" % [name, day]] = _incident_outcome(s, wood0)
			_dispose(s)
		var f: Variant = _flat(1)
		var wood1: int = f.res_amount("wood")
		Director.apply(f, payloads[name])
		forced[name] = _incident_outcome(f, wood1)
		_dispose(f)
	return {"portable": {"rolled": rolled, "forced": forced, "live": Director.LIVE_INCIDENTS, "grace": Director.GRACE_DAYS,
		"warn_lead": Director.RAID_WARN_LEAD, "threat_big_weight": Director.THREAT_BIG_WEIGHT}, "numeric": {}}


# ======================================================================================
# S25  ~53 game days of the LIVE storyteller at dt=2 s: enough rolls that its cadence (the MTB maths, grace,
# the dday scaling) is visible in what actually fires — a 50% error in any of them moves this.
# ======================================================================================
static func director_long() -> Dictionary:
	var sim: Variant = _kyiv()
	var kinds: Dictionary = {"director_raid": 0, "cold_snap": 0, "disease": 0, "cargo": 0, "raid_wave": 0, "patrol": 0, "death": 0}
	var last_seq: int = int(sim.messages_seq)
	for t in 4000:
		sim.update(2.0)
		var fresh: int = int(sim.messages_seq) - last_seq
		last_seq = int(sim.messages_seq)
		var msgs: Array = _texts(sim)
		for line in msgs.slice(maxi(0, msgs.size() - fresh)):
			var l: String = String(line)
			if l.begins_with("⚠ Режисер"):
				kinds.director_raid += 1
			elif l.begins_with("🌨"):
				kinds.cold_snap += 1
			elif l.begins_with("🦠"):
				kinds.disease += 1
			elif l.begins_with("📦 Вантажний дрон"):
				kinds.cargo += 1
			elif l.begins_with("⚔ Рейд"):
				kinds.raid_wave += 1
			elif l.begins_with("🤖"):
				kinds.patrol += 1
		_topup(sim)
		if sim.dead:
			kinds.death += 1
			sim.respawn_new_pawn()
	var numeric: Dictionary = _numeric_state(sim)
	numeric["kinds"] = kinds
	numeric["messages_seq"] = int(sim.messages_seq)
	_dispose(sim)
	return {"portable": {}, "numeric": numeric}


# ======================================================================================
# S26  what the HUD is FED (D9): the HudModel snapshot schema + the capsule/death/raid/region DATA slices, and the
# shipped OFF death-screen strings (REQ-0010-40/85 «при OFF рядки смерті/панелі без нових формулювань»).
# NOT the panel labels, the landing feed or the flash hints — those are S27 session_feed, S28 flash_hints and
# S29 capsule_panel_off below (an earlier note here claimed S26 covered "what the player sees": it covers the data only)
# ======================================================================================
static func hud_and_strings() -> Dictionary:
	var a: Variant = _session(false)
	var sim: Variant = a.sim
	for i in 30:
		sim.update(DT)
	var bal: Variant = KernelBalance.Balance.new()
	var snap: Dictionary = HudModel.snapshot(a, {"buildings": [], "stock": sim.stock, "items": []}, {"day": int(sim.time.day)}, bal)
	var p: Dictionary = {
		"snapshot_paths": paths_of(snap),
		"capsule_charges": snap.capsule.charges, "capsule_radius_km": snap.capsule.radius_km,
		"capsule_invite_count": (snap.capsule.invites as Array).size(),
		"death_slice": snap.death, "raid_slice": snap.raid, "region_slice_keys": _sorted_keys(snap.region),
		"goals_slice": snap.goals, "alive": snap.alive, "dead": snap.dead,
	}
	var numeric: Dictionary = {"snapshot_hash": Persistence.content_hash(snap), "invites": snap.capsule.invites}
	_kill(sim)
	var dead_snap: Dictionary = HudModel.snapshot(a, {"buildings": [], "stock": sim.stock, "items": []}, {"day": int(sim.time.day)}, bal)
	p["dead_snapshot_death_slice"] = dead_snap.death
	p["dead_snapshot_dead"] = dead_snap.dead
	var DS: Variant = Lifecycle.DeathScreen
	var lessons: Dictionary = {}
	for cause in ["", "переохолодження", "голод", "тепловий удар", "смертельні рани (тулуб)", "втрата крові", "щось інше"]:
		lessons[cause] = DS._lesson(cause)
	p["death_screen"] = {
		"fate_stock": DS._fate({}), "fate_inventory_empty": DS._fate({"inventory": true, "bag_items": 0}),
		"fate_inventory_bag": DS._fate({"inventory": true, "bag_items": 3}), "lessons": lessons,
	}
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/lifecycle.gd")
	var literals: Dictionary = {}
	for lit in ["ЗАГИБЕЛЬ", "Новий виживальник", "Поселення й склад лишаються", "до 5-го дня"]:
		literals[lit] = src.contains(lit)
	p["lifecycle_literals_present"] = literals
	_dispose(sim)
	return {"portable": p, "numeric": numeric}


# ======================================================================================
# S27  the feed lines Session writes (REQ-0010-40/85, M5/F10): landing, travel, continue. NO clear after start() —
# `_session()` wipes the feed for every other scenario, which is exactly how the landing wording went unpinned.
# These strings live in sim.messages = «view, not sim» (persistence.gd): world_hash never sees them, so ONLY a
# text pin can catch «Висадка:» / «капсула (V)» / «розпали багаття (9)» turning into something else.
# Tiers: portable = every line WITHOUT a °C figure, exact, + the °C hint lines with the figure masked to «#»
# (Київ day 1 is deep winter, far from the comfort edge, so the cold/hot BRANCH is stable on any libm);
# numeric = every raw line, figure included (the felt °C flows through cos()).
# ======================================================================================
const FEED_TMP := "user://off_baseline_feed.json"


# the felt-°C figure of a hint line is climate maths (libm); the wording around it is what the spec rewrites
static func _mask_c(text: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("-?\\d+(?=°C)")
	return re.sub(text, "#", true)


# "cls|text" per line from index `from`: plain (no °C), hints (°C masked), raw (exact)
static func _feed_split(s: Variant, from: int = 0) -> Dictionary:
	var plain: Array = []
	var hints: Array = []
	var raw: Array = []
	var i: int = 0
	for m in s.messages:
		if i >= from:
			var line: String = "%s|%s" % [String(m.cls), String(m.text)]
			raw.append(line)
			if "°" in line:
				hints.append(_mask_c(line))
			else:
				plain.append(line)
		i += 1
	return {"plain": plain, "hints": hints, "raw": raw}


static func session_feed() -> Dictionary:
	var p: Dictionary = {}
	var numeric: Dictionary = {}
	for inventory in [false, true]:
		var key: String = "inventory" if inventory else "stock"
		var a: Variant = _session(inventory, true)
		var sim: Variant = a.sim
		var start: Dictionary = _feed_split(sim)
		var row: Dictionary = {
			"start_plain": start.plain, "start_hints": start.hints, "start_count": sim.messages.size(),
			"invites_seeded": sim.invites.size(), "has_home": bool(a.has_home),
		}
		var raw: Dictionary = {"start": start.raw}
		# a capsule hop away and back: the arrival lines («🛬 Нова місцевість», «↩ Повернення», the climate hint on arrival)
		var n0: int = sim.messages.size()
		a.travel_to(LAT2, LON2, "Львів")
		var away: Dictionary = _feed_split(sim, n0)
		row["away_plain"] = away.plain
		row["away_hints"] = away.hints
		raw["away"] = away.raw
		n0 = sim.messages.size()
		a.travel_to(LAT, LON, "Київ")
		var back: Dictionary = _feed_split(sim, n0)
		row["back_plain"] = back.plain
		row["back_hints"] = back.hints
		raw["back"] = back.raw
		# Continue: a fresh Session restores the save and says «▶ Продовжено …»
		var saved: bool = bool(a.save_game(FEED_TMP))
		var b: Variant = SessionScript.new()
		_force_off(b)
		b.autosave = false
		var restored: bool = saved and bool(b.restore_game(FEED_TMP))
		row["saved"] = saved
		row["restored"] = restored
		if restored:
			var cont: Dictionary = _feed_split(b.sim)
			row["continue_plain"] = cont.plain
			row["continue_hints"] = cont.hints
			raw["continue"] = cont.raw
			_dispose(b.sim)
		_rm(FEED_TMP)
		p[key] = row
		numeric[key] = raw
		_dispose(sim)
	return {"portable": p, "numeric": numeric}


# ======================================================================================
# S28  the flash hints with a KEY in them («(4)») and the build refusals (REQ-0010-85, D9, critique-0010 п.13).
# `flash_msg` is a view string (never in the record / world_hash): «Склад повний — збудуй ще один склад (4)» and
# «Несеш максимум — збудуй склад (4)» are the OFF texts that name the build-bar key a capsule-as-storage world no
# longer needs, and the build refusals are the texts REQ-0010-06 («клітинка капсули непрохідна для будівництва»)
# will sit next to. Driven ONLY through public verbs (order_gather / try_build / update).
# ======================================================================================
# every DISTINCT flash raised while `ticks` ran (flash_t > 0 is the live bit: the text itself is never cleared)
static func _watch_flash(s: Variant, ticks: int) -> Dictionary:
	var seen: Array = []
	var last: String = ""
	for _t in ticks:
		s.update(DT)
		_topup(s)
		if float(s.flash_t) > 0.0 and String(s.flash_msg) != last:
			last = String(s.flash_msg)
			seen.append(last)
	return {"seen": seen, "action_cleared": s.player.action == null, "carry_full": s.carry_total() >= int(s.player.carry_cap)}


static func _build_flash(s: Variant, kind: String, x: int, y: int) -> Dictionary:
	s.flash_msg = ""
	s.flash_t = 0.0
	var before: int = s.buildings.size()
	s.try_build(kind, x, y)
	return {"flash": String(s.flash_msg), "placed": s.buildings.size() > before}


static func flash_hints() -> Dictionary:
	var p: Dictionary = {}
	# (1) a FULL storage: the load stays in the hands, the haul stops, the flash names the fix
	var f: Variant = _flat()
	f.map.nodes[8 * 16 + 12] = {"kind": "tree", "amount": 40}
	f.stock[f.res_key("stone")] = int(f.res_amount("stone")) + (f.storage_cap() - f.stock_total())
	f.order_gather(12, 8)
	p["full_storage"] = _watch_flash(f, 1800)
	_dispose(f)
	# (2) NO storage at all (the last one smashed by damage — demolish refuses): full hands cannot haul anywhere
	var g: Variant = _flat()
	g.map.nodes[8 * 16 + 12] = {"kind": "tree", "amount": 40}
	g._damage_building(g.bgrid[8 * 16 + 9], 1000.0, false)
	p["storage_gone"] = not g.has_building("storage")
	g.order_gather(12, 8)
	p["no_storage"] = _watch_flash(g, 1800)
	_dispose(g)
	# (2b) a storage walled in on all sides (Chebyshev r=2 ring): the haul walks up, is not within reach, says so
	var w: Variant = _flat()
	w.map.nodes[3 * 16 + 4] = {"kind": "tree", "amount": 40}
	w.stock[w.res_key("wood")] = 150
	w.stock[w.res_key("stone")] = 150
	var ring: int = 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if maxi(absi(dx), absi(dy)) == 2:
				w.try_build("wall", 9 + dx, 8 + dy)
				ring += 1
	p["walled_ring"] = [_count_kind(w, "wall"), ring]
	w.player.px = 3.5   # outside the ring, next to the tree
	w.player.py = 3.5
	w.flash_msg = ""
	w.flash_t = 0.0
	w.order_gather(4, 3)
	p["storage_unreachable"] = _watch_flash(w, 2500)
	_dispose(w)
	# (3) build refusals in the stock world (try_build): occupied / off-map / unknown id / research-gated / unaffordable / ok
	var b: Variant = _flat()
	var refusals: Dictionary = {}
	refusals["occupied"] = _build_flash(b, "wall", 9, 8)
	refusals["off_map"] = _build_flash(b, "wall", -1, 3)
	refusals["unknown_kind"] = _build_flash(b, "nope", 5, 5)
	refusals["research_gated"] = _build_flash(b, "turret", 5, 5)
	b.stock.clear()
	refusals["unaffordable"] = _build_flash(b, "wall", 5, 5)
	b.stock[b.res_key("wood")] = 40
	b.stock[b.res_key("stone")] = 40
	refusals["affordable"] = _build_flash(b, "wall", 5, 5)
	p["build_stock_world"] = refusals
	_dispose(b)
	# (4) the personal-inventory world: no block in the pack, and a FULL pack stops the gather
	var inv: Variant = _flat(195, true)
	var inv_rows: Dictionary = {}
	inv_rows["no_item"] = _build_flash(inv, "wall", 5, 5)
	inv.map.nodes[8 * 16 + 12] = {"kind": "tree", "amount": 40}
	Inventory.add(inv, "wood", 100000)   # every slot a full stack of wood: the next log has nowhere to go
	inv_rows["pack_room_for_wood"] = Inventory.room(inv, "wood")
	inv.flash_msg = ""   # the «no_item» flash above is still alive (flash_t 2.2 s): not part of THIS watch
	inv.flash_t = 0.0
	inv.order_gather(12, 8)
	inv_rows["pack_full_gather"] = _watch_flash(inv, 600)
	p["inventory_world"] = inv_rows
	_dispose(inv)
	return {"portable": p, "numeric": {}}


# ======================================================================================
# S29  the capsule panel the player SEES at OFF (REQ-0010-41/85, D9): labels, button texts, disabled/dimmed state,
# the intents it emits, the coordinate-parse refusal — bound to a hand-made vm AND to the real Session snapshot
# before/after a launch (one truth: the panel shows what sim.capsule counts). S26 pins the slice DATA only.
# ======================================================================================
static func _h2_texts(node: Node, out: Array) -> void:
	if node is Widgets.H2Header:
		out.append(String(node._text))
	for c in node.get_children():
		_h2_texts(c, out)


# invite rows: label/button text only for VISIBLE slots (a hidden pool slot keeps stale text nobody sees)
static func _panel_state(panel: Variant) -> Dictionary:
	var rows: Array = []
	for i in panel._invite_rows.size():
		var vis: bool = bool(panel._invite_rows[i].visible)
		var row: Dictionary = {"visible": vis}
		if vis:
			row["label"] = String(panel._invite_labels[i].text)
			row["button"] = String(panel._invite_buttons[i].text)
			row["button_disabled"] = bool(panel._invite_buttons[i].disabled)
			row["button_dimmed"] = panel._invite_buttons[i].modulate == Tokens.DIMMED
		rows.append(row)
	return {
		"status": String(panel._status.text), "launch": String(panel._launch.text), "launch_disabled": bool(panel._launch.disabled),
		"launch_dimmed": panel._launch.modulate == Tokens.DIMMED, "rows": rows,
	}


static func capsule_panel_off() -> Dictionary:
	var p: Dictionary = {}
	var panel: Variant = WorldPanels.CapsulePanel.new()
	p["meta"] = {"panel_id": String(panel.panel_id), "hotkey": int(panel.hotkey), "menu_label": String(panel.menu_label),
		"default_open": bool(panel.default_open), "dock": int(panel.dock), "priority": int(panel.priority), "compact_open": int(panel.compact_open),
		"invite_max": int(panel.INVITE_MAX)}
	# a hand-made vm: 5 invites (the pool has 4 slots), the 2nd without a clan (the «—» default)
	var full_vm: Dictionary = {"capsule": {"charges": 1, "radius_km": 100.0, "invites": [
		{"id": "inv_a", "inviter": "Друг", "clan": "К", "name": "Місце"}, {"id": "inv_b", "inviter": "Інший", "name": "Пункт"},
		{"id": "inv_c", "inviter": "Третій", "clan": "Л", "name": "Брід"}, {"id": "inv_d", "inviter": "Четвертий", "clan": "М", "name": "Гай"},
		{"id": "inv_e", "inviter": "П'ятий", "clan": "Н", "name": "Ліс"}]}}
	panel.bind(full_vm)
	var heads: Array = []
	_h2_texts(panel, heads)
	p["headers"] = heads
	p["placeholders"] = [String(panel._lat_edit.placeholder_text), String(panel._lon_edit.placeholder_text)]
	p["full_vm"] = _panel_state(panel)
	var drained_vm: Dictionary = {"capsule": {"charges": 0, "radius_km": 100.0, "invites": [{"id": "inv_a", "inviter": "Друг", "clan": "К", "name": "Місце"}]}}
	panel.bind(drained_vm)
	p["drained_vm"] = _panel_state(panel)
	# the intents a tap emits (the wire names the capsule waves must keep at OFF) + the coordinate-parse refusal
	var intents: Array = []
	panel.intent.connect(func(verb: StringName, args: Dictionary) -> void: intents.append({"verb": String(verb), "args": args.duplicate(true)}))
	panel._on_take(0)
	panel._on_take(2)   # a hidden pool slot: no invite id -> no intent
	panel._lat_edit.text = "50.2"
	panel._lon_edit.text = "30.6"
	panel._on_launch()
	var refusals: Dictionary = {"status_before": String(panel._status.text)}
	# NB: a non-numeric field ("abc") parses to 0.0 and LAUNCHES at (0,0) — a baseline quirk (LatLon.parse is «lifted verbatim»);
	# it is reported to the designer, deliberately NOT pinned here (that would freeze a defect as an expectation)
	panel._lat_edit.text = "120"   # out of range: the refusal, the base line stays and the reason is appended under it
	panel._lon_edit.text = "30.6"
	panel._on_launch()
	refusals["out_of_range"] = String(panel._status.text)
	panel._lat_edit.text = ""
	panel._lon_edit.text = ""
	panel._on_launch()
	refusals["empty"] = String(panel._status.text)
	p["intents"] = intents   # exactly the take + the ONE valid launch: a refusal emits nothing
	p["refusals"] = refusals
	panel.free()
	# the REAL snapshot of a fresh OFF Session, then after the daily charge is spent: the panel follows the sim
	var a: Variant = _session(false)
	var sim: Variant = a.sim
	var bal: Variant = KernelBalance.Balance.new()
	var real: Variant = WorldPanels.CapsulePanel.new()
	var snap: Dictionary = HudModel.snapshot(a, {"buildings": [], "stock": sim.stock, "items": []}, {"day": int(sim.time.day)}, bal)
	real.bind(snap)
	var fresh: Dictionary = _panel_state(real)
	fresh["sim_charges"] = int(sim.capsule.charges)
	fresh["sim_radius_km"] = int(sim.capsule.radius_km)
	fresh["sim_invites"] = sim.invites.size()
	fresh["status_is_sim_truth"] = String(fresh.status) == "Зарядів: %d · радіус %d км" % [int(sim.capsule.charges), int(sim.capsule.radius_km)]
	p["real_session_fresh"] = fresh
	var launched: Dictionary = sim.try_launch_capsule(50.2, 30.6, "Недалеко")
	snap = HudModel.snapshot(a, {"buildings": [], "stock": sim.stock, "items": []}, {"day": int(sim.time.day)}, bal)
	real.bind(snap)
	var spent: Dictionary = _panel_state(real)
	spent["launch_ok"] = bool(launched.ok)
	spent["sim_charges"] = int(sim.capsule.charges)
	spent["status_is_sim_truth"] = String(spent.status) == "Зарядів: %d · радіус %d км" % [int(sim.capsule.charges), int(sim.capsule.radius_km)]
	p["real_session_spent"] = spent
	real.free()
	_dispose(sim)
	return {"portable": p, "numeric": {}}

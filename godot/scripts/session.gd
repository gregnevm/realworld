# RealWorld — session.gd : world/session orchestration (spec 0002 refactor)
#
# Owns the multi-region persistent world (Persistence store), the social graph, and the home base,
# and drives region travel + permadeath respawn. Extracted out of main.gd so this state machine is
# scene-free and headless-testable — main.gd keeps only rendering, input and UI. The live sim for
# the active region is `sim`; travelling swaps its contents in place (same instance).
extends RefCounted

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Social = preload("res://scripts/social.gd")
const Persistence = preload("res://scripts/persistence.gd")
const Progression = preload("res://scripts/kernel/progression.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const GameData = preload("res://scripts/data.gd")
const Goals = preload("res://scripts/goals.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const LocalRealm = preload("res://scripts/net/local_realm.gd")   # spec 0013: the RealGPS stack, in-process
const MAP_N := 56
const STORE_PATH := "user://world.json"
const SAVE_PATH := "user://save.json"   # the whole session (continue): store + live region + account
const SAVE_VERSION := 1

var sim: Variant = null   # Sim (scripts/sim.gd); Variant, бо тести підставляють легкі фейки
var store: Dictionary = {}
var social: Dictionary = {}
var _map_b64: String = ""        # terrain cache for nearby_view (spec 0013)
var _map_b64_key: int = -1
var realm_net: Variant = null   # LocalRealm (spec 0013): created lazily by tick_realm, never saved (a pure function of the place)
const NO_HOME := {"lat": 0.0, "lon": 0.0, "name": ""}   # «дому нема»: початкове значення й те, до чого скидає відмовлений start()
var home := NO_HOME.duplicate()
var has_home := false   # explicit — a legitimate spawn at (0,0) must not read as "no home"
var autosave := true   # tests disable disk writes

# The tech pipeline (kernel/progression.gd). Account-global: it survives region travel + respawn
# (never reset in travel_to/respawn), like the day clock. Research-points accrue from research benches.
var progression: Variant = null   # kernel/progression.gd; створюється лише в start()
var auto_research := true   # idle research benches auto-pick the cheapest available project (queue wins)
var bench_announced := false   # one-time «стіл працює» toast (the ResearchPanel reveals with it)

# Onboarding goals (goals.gd): account-level and STICKY — a goal done stays done across travel,
# respawn and save/continue. Pure observation of sim state: never steers the sim, never hashed.
var goals_done: Dictionary = {}   # goal id -> true
var use_inventory := false        # spec 0009: set by the entry scene BEFORE start(); tests keep the stock path
var use_catalog := false          # spec 0008: відкритий склад; ON-капсула його вимагає (REQ-0010-59). ДО start()
var use_main_capsule := false     # spec 0010: Основна капсула; ставиться ДО start(), далі замкнений (dev-перемикач `-- capsule`)
var last_error: StringName = &""  # чому start()/restore_game()/travel_to() відмовили (&"" — усе гаразд); для UI/тестів
var _goal_t := 0.0

# false (+ last_error, sim == null) — конфігурація не дозволила створити світ (ON без інвентаря/каталогу, мапа без місця);
# OFF завжди true. `now_ms` — годинник пристрою на межі сесії (власник — spec 0012): push_clock ДО new_game, щоб landed_at
# капсули взявся з нього, а не з 0 (0 == годинник не подано). Сим сам час не читає (REQ-0010-92).
func start(lat: float, lon: float, place_name: String, now_ms: int = 0) -> bool:
	last_error = &""
	realm_net = null
	var m := WorldGen.generate_map(lat, lon, MAP_N)
	m["place_name"] = place_name
	sim = Sim.new()
	sim.use_inventory = use_inventory   # spec 0009: the playable scene opts new games into the personal inventory
	sim.use_catalog = use_catalog
	sim.use_main_capsule = use_main_capsule   # ДО new_game: setter замикається після нього (REQ-0010-02/60)
	push_clock(now_ms)
	sim.new_game(m, false)   # the session issues the climate hint itself, after the landing lines
	if sim.config_error != &"":
		last_error = sim.config_error
		_clear_world()
		return false
	var on: bool = bool(sim.use_main_capsule)
	progression = Progression.new(Catalog.load_json())
	store = Persistence.store_new()
	social = Social.new_graph("Ти", WorldGen.hash_seed(lat, lon), lat, lon)
	sim.social = social
	home = {"lat": lat, "lon": lon, "name": place_name}
	if on:   # дім = посилання на капсулу {region_key, tile}; has_home <=> капсула є (REQ-0010-09)
		var cap_tile: Vector2i = MainCapsule.tile(sim)
		home["region_key"] = WorldGen.canon_coord(lat, lon)
		home["tile"] = [cap_tile.x, cap_tile.y]
	has_home = true
	sim._log("Висадка: %s · біом %s" % [place_name, m.biome], "good")
	sim._log("Клан: %s · рейди від ворожих фракцій." % Social.my_clan(social).name)
	# seed a couple of friend invites so the capsule flow has content immediately — ONE feed line.
	# ON: щоденної капсули нема (запуск відхиляється, REQ-0010-41), тож інвайтів «капсула (V) долетить» не сіємо.
	var seeded := 0
	for i in range(0 if on else min(3, social.friends.size())):
		sim.add_invite(Social.friend_invite(social, i, sim.capsule.radius_km), true)
		seeded += 1
	if seeded > 0:
		sim._log("✉ Друзі надіслали інвайтів: %d — капсула (V) долетить до них." % seeded)
	sim.spawn_hint()
	return true

# Відмовлений start(): сесія не лишається з рештками ПОПЕРЕДНЬОГО світу. Світ, дім, склад регіонів, соцграф і дослідження
# належать одному світові; без sim «дім» без капсули порушив би has_home <=> капсула є (REQ-0010-09). Акаунтні дані
# (goals_done, auto_research) — не світ, їх start() і так не чіпає.
func _clear_world() -> void:
	sim = null
	home = NO_HOME.duplicate()
	has_home = false
	store = {}
	social = {}
	progression = null
	realm_net = null

# Годинник пристрою -> sim (Sim.set_clock, монотонно). Викликає край пристрою (newhud_main), ніколи сам sim.
func push_clock(now_ms: int) -> void:
	if sim != null:
		sim.set_clock(now_ms)

# RealGPS layer (spec 0013): advance presence to the device clock. The hero's GPS fix is the active region's
# coordinate; a region change relocates (leave + re-join). Value data for the HUD NearbyPanel in nearby_view().
func tick_realm(now_ms: int) -> void:
	if sim == null or sim.get("map") == null or not (sim.map is Dictionary) or not sim.map.has("lat"):
		return
	var lat := float(sim.map.lat)
	var lon := float(sim.map.lon)
	if realm_net == null:
		realm_net = LocalRealm.new("Ти", lat, lon, now_ms)
	else:
		realm_net.relocate(lat, lon, now_ms)
		realm_net.tick(now_ms)

# Value data for the HUD minimap: presence rows + the active region's terrain (base64, rebuilt only when the
# region's seed changes) + the hero's tile. Plain data — the view decodes the terrain once per seed.
func nearby_view() -> Dictionary:
	if realm_net == null:
		return {"available": false}
	var v: Dictionary = realm_net.view()
	if bool(v.get("available", false)) and sim != null and sim.get("map") is Dictionary and sim.map.has("tiles"):
		var key := int(sim.map.get("seed", 0))
		if key != _map_b64_key or _map_b64 == "":
			_map_b64 = Marshalls.raw_to_base64(sim.map.tiles)
			_map_b64_key = key
		var cap: Dictionary = {}
		if sim.get("use_main_capsule") == true:
			var ct: Vector2i = MainCapsule.tile(sim)
			cap = {"x": ct.x, "y": ct.y}
		v["map"] = {"key": key, "n": int(sim.map.get("n", MAP_N)), "tiles": _map_b64,
			"hero": {"x": float(sim.player.px), "y": float(sim.player.py)}, "capsule": cap}
	return v

# Serialize the active region into the store (seed + diff + save), advancing the hash chain.
func commit_region() -> void:
	Persistence.store_commit(store, Persistence.serialize_region(sim))
	if autosave:
		Persistence.save_to_file(store, STORE_PATH)

# Persist the current region, fly the pawn to (lat,lon), then load it (if visited) or generate it.
func travel_to(lat: float, lon: float, place_name: String) -> void:
	if sim == null:
		return
	if sim.use_main_capsule:   # spec 0010: капсула одна й лишається у своєму регіоні (REQ-0010-04/75) — відмова ДО commit_region/стирання
		sim._log(MainCapsule.MSG_NO_TRAVEL, "warn")
		last_error = &"capsule_no_travel"
		return
	commit_region()
	var pawn: Dictionary = sim.extract_pawn()
	var gday: int = int(sim.time.day)      # the clock is account-global, not per-region
	var gfrac: float = float(sim.time.frac)
	var key := Persistence.region_key(lat, lon)
	if Persistence.store_has(store, key):
		sim.load_region(Persistence.store_get(store, key))
		sim.apply_pawn(pawn)
		sim._log("↩ Повернення в %s." % str(sim.map.get("place_name", place_name)), "good")
	else:
		var m := WorldGen.generate_map(lat, lon, MAP_N)
		m["place_name"] = place_name
		sim.arrive_region(m, pawn)
		sim._log("🛬 Нова місцевість: %s · біом %s." % [place_name, m.biome], "good")
	sim.social = social
	sim.time.day = gday
	sim.time.frac = gfrac

# Permadeath: a fresh pawn at the clan home. If you died away, fly home first (region identity,
# NOT presence of any storage — you may have built one at a remote outpost).
func respawn() -> void:
	if sim.get("use_main_capsule") == true:   # ON: місце задає шов respawn_anchor, посадку робить landing (REQ-0010-07/09/98)
		sim.respawn_new_pawn(MainCapsule.respawn_anchor(self))
		return
	var cur_key := Persistence.region_key(float(sim.map.lat), float(sim.map.lon))
	var home_key := Persistence.region_key(float(home.lat), float(home.lon))
	if has_home and cur_key != home_key:
		travel_to(home.lat, home.lon, home.name)
	sim.respawn_new_pawn()

# ---------------- research pipeline (kernel/progression.gd driven from research benches) ----------------

# Research-points per game-day produced by all standing research benches (data.gd `research_rate`).
func research_rate() -> float:
	if sim == null:
		return 0.0
	if sim.get("use_main_capsule") == true:   # spec 0010: стіл у зоні капсули — з бафом research_mult (OFF-цикл нижче дослівно)
		return MainCapsule.research_rate(sim)
	var rate := 0.0
	for b in sim.buildings:
		rate += float((GameData.BUILDINGS.get(b.kind, {}) as Dictionary).get("research_rate", 0.0))
	return rate

# Advance research by this frame's worth of bench work. `dt` is real seconds; cost is measured in
# game-days (production.gd's unit), so one bench (rate 1.0) funds ~1 project-day per in-game day. Feeds
# the pipeline (queue first, then — if auto_research — the cheapest available), and toasts each unlock.
func tick_research(dt: float) -> void:
	if sim == null or progression == null or sim.dead:
		return
	# міст ворітних станів: сим бачить відкриті дослідження як value-мапу (гейти try_build/craft_item)
	sim.research_unlocked = progression.research.unlocked
	var rate := research_rate()
	if rate <= 0.0:
		return
	if not bench_announced:
		bench_announced = true
		sim._log("🔬 Дослідницький стіл працює — обери проєкт у панелі «Дослідження».", "good")
	var dday: float = dt / maxf(1.0, float(sim.time.day_len))
	var newly: Array = progression.add_points(rate * dday, auto_research)
	for id in newly:
		sim._log("🔬 Досліджено: %s (рівень %d)." % [progression.label_of(id), progression.tech_level()], "good")

# Player intents (routed here from the ResearchPanel via InputController). Thin wrappers + a feed line.
func enqueue_research(id: String) -> bool:
	if progression == null:
		return false
	var ok: bool = progression.enqueue(StringName(id))
	if ok and sim != null:
		sim._log("🔬 У чергу досліджень: %s." % progression.label_of(StringName(id)))
	return ok

func start_research(id: String) -> bool:
	if progression == null:
		return false
	var ok: bool = progression.start(StringName(id))
	if ok and sim != null:
		sim._log("🔬 Розпочато дослідження: %s." % progression.label_of(StringName(id)))
	return ok

func clear_research_queue() -> void:
	if progression != null:
		progression.queue = []

# ---------------- onboarding goals (goals.gd) ----------------
# Evaluate the open goals a few times a second (cheap pure checks), mark completions sticky, toast
# each one with the NEXT goal so the feed itself walks a new player through the loop.
func tick_goals(dt: float) -> void:
	if sim == null or sim.dead:
		return
	_goal_t -= dt
	if _goal_t > 0.0:
		return
	_goal_t = 0.5
	var titles: Array = []
	for g in Goals.GOALS:
		var id := String(g.id)
		if goals_done.has(id):
			continue
		if Goals.progress(id, sim, self) >= 1.0:
			goals_done[id] = true
			titles.append(String(g.title))
	if titles.is_empty():
		return
	# several goals can close in one check (a loaded base, a big build): ONE toast, not a stack of repeats
	var nxt: Dictionary = _current_goal()
	var tail: String = (" · далі — %s" % String(nxt.title)) if not nxt.is_empty() else " · усі цілі виконано!"
	# one line in the feed: a big batch is a count, not a list (the chip and the goals panel hold the details)
	var head: String = ("Ціль виконано: " + String(titles[0])) if titles.size() == 1 else ("Виконано цілей: %d" % titles.size())
	sim._log("✔ %s%s" % [head, tail], "good")

func _current_goal() -> Dictionary:
	for g in Goals.GOALS:
		if not goals_done.has(String(g.id)):
			return g
	return {}

# Value data for the HUD GoalsPanel (R8): the first open goal + its live progress + what follows.
func goals_view() -> Dictionary:
	var cur: Dictionary = _current_goal()
	var view := {"available": true, "done": goals_done.size(), "total": Goals.count(), "all_done": cur.is_empty()}
	if cur.is_empty():
		return view
	var id := String(cur.id)
	var hint := String(cur.hint)
	if sim != null and sim.get("use_inventory") == true and Goals.INV_HINT.has(id):
		hint = String(Goals.INV_HINT[id])   # inventory world: the how-to speaks hotbar/backpack, not the build palette
	view["current"] = {"id": id, "title": String(cur.title), "hint": hint, "build": String(cur.get("build", "")),
		"pct": Goals.progress(id, sim, self) if sim != null else 0.0}
	var after := ""
	var seen := false
	for g in Goals.GOALS:
		if String(g.id) == id:
			seen = true
		elif seen and not goals_done.has(String(g.id)):
			after = String(g.title)
			break
	view["next"] = after
	return view

# ---------------- save / continue (playability: closing the game no longer erases it) ----------------
# ONE file holds the whole session: the region store (every visited region — seed + diff + save,
# hash-chained), the ACTIVE region as a resume payload (save half + runtime half: threats, weather,
# rng cursors, the pawn mid-action — rejoin-grade, so continuing lands exactly where you left), and
# the account layer the store never carried (home, research pipeline, goals, capsule, invites).
# The social graph is NOT stored: it is a pure function of the home coordinate (Social.new_graph).
func save_game(path: String = SAVE_PATH) -> bool:
	if sim == null:
		return false
	var data := {
		"version": SAVE_VERSION,
		"home": home.duplicate(), "has_home": has_home,
		"store": store,
		"active": Persistence.resume_payload(sim),
		"progression": progression.to_dict() if progression != null else {},
		"goals": goals_done.keys(),
		"capsule": (sim.capsule as Dictionary).duplicate(true),
		"invites": (sim.invites as Array).duplicate(true),
		"auto_research": auto_research,
		"bench_announced": bench_announced,
		"meta": {"place": String(sim.map.get("place_name", "")), "day": int(sim.time.day), "dead": bool(sim.dead)},
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	# full_precision (the wire rule, net/snapshot.gd to_wire): the default stringify rounds floats to
	# 15 digits and a continued world drifts off the saved one within a tick
	f.store_string(JSON.stringify(data, "", true, true))
	f.close()
	return true

# What the spawn screen offers to continue («Київ · день 7»). {} == no usable save.
static func save_meta(path: String = SAVE_PATH) -> Dictionary:
	var d := _read_save(path)
	return (d.get("meta", {}) as Dictionary) if not d.is_empty() else {}

static func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and int((parsed as Dictionary).get("version", 0)) == SAVE_VERSION and (parsed as Dictionary).has("active"):
		return parsed
	return {}

# Rebuild THIS session from a save; false (and untouched) when there is none / it is unreadable / the world record is
# refused (an ON save without its capsule, a newer record version… — sim.load_error -> last_error, REQ-0010-60/83).
# The sim is restored into a LOCAL instance first: a refusal leaves this session exactly as it was (no half-alive world).
func restore_game(path: String = SAVE_PATH) -> bool:
	last_error = &""
	var d := _read_save(path)
	if d.is_empty():
		return false
	var restored: Variant = Sim.new()
	if not Persistence.restore(restored, d.active):
		last_error = restored.load_error
		return false
	sim = restored
	var h: Dictionary = d.get("home", {})
	home = {"lat": float(h.get("lat", 0.0)), "lon": float(h.get("lon", 0.0)), "name": str(h.get("name", ""))}
	has_home = bool(d.get("has_home", true))
	if sim.use_main_capsule:   # ON: дім = посилання на капсулу з відновленого сима (ключі додаються лише при ON; OFF-дім незмінний)
		use_main_capsule = true   # Session відображає живий світ
		var cap_tile: Vector2i = MainCapsule.tile(sim)
		home["region_key"] = WorldGen.canon_coord(float(home.lat), float(home.lon))
		home["tile"] = [cap_tile.x, cap_tile.y]
		has_home = true
		MainCapsule.mark_reentry(sim)   # «Продовжити» = власник був поза грою: рейд, що не дійшов до контакту, переплановується (REQ-0010-62/119, стаб до Q-1)
	var st: Variant = d.get("store", {})
	store = st if (st is Dictionary and (st as Dictionary).has("regions")) else Persistence.store_new()
	progression = Progression.new(Catalog.load_json())
	progression.from_dict(d.get("progression", {}))
	social = Social.new_graph("Ти", WorldGen.hash_seed(float(home.lat), float(home.lon)), float(home.lat), float(home.lon))
	sim.social = social
	var cap: Dictionary = d.get("capsule", {})
	if not cap.is_empty():
		sim.capsule = {"charges": int(cap.get("charges", 0)), "radius_km": float(cap.get("radius_km", GameData.CAPSULE_BASE_RADIUS_KM)),
			"last_day": int(cap.get("last_day", int(sim.time.day)))}
	sim.invites = (d.get("invites", []) as Array).duplicate(true)
	goals_done = {}
	for id in d.get("goals", []):
		goals_done[str(id)] = true
	auto_research = bool(d.get("auto_research", true))
	bench_announced = bool(d.get("bench_announced", false))
	sim.research_unlocked = progression.research.unlocked   # the gates are live before the first tick
	sim._log("▶ Продовжено: %s · день %d." % [str(sim.map.get("place_name", "")), int(sim.time.day)], "good")
	return true

func stored_region_count() -> int:
	return (store.get("regions", {}) as Dictionary).size()

func chain_head() -> String:
	return str(store.get("head", ""))

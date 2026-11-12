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
const Clock = preload("res://scripts/clock.gd")
const Orbit = preload("res://scripts/sim/orbit.gd")   # spec 0011: Орбіта — акаунт-рівень (клони, safe_stock)
const OrbitStub = preload("res://scripts/sim/orbit_stub.gd")   # шви 0010↔0011: safe zone / respawn_source
const Hints = preload("res://scripts/hints.gd")   # spec 0012 §3.8: м'які підказки FTUE за ON (OD-146)
const Location = preload("res://scripts/location.gd")   # spec 0012 §3.7: валідація місця, провайдери, «вільне поруч»
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
var use_realtime := false         # spec 0012: реальний час 1:1; ставиться ДО start(), далі замкнений (dev-перемикач `-- realtime`)
var use_main_capsule := false     # spec 0010: Основна капсула; ставиться ДО start(), далі замкнений (dev-перемикач `-- capsule`)
var use_orbit := false             # spec 0011: Орбіта й клони; ставиться ДО start(), потребує use_inventory (REQ-0011-3); dev-перемикач `-- orbit`
var orbit: Variant = null         # spec 0011: акаунт-запис Орбіти (Dictionary, sim/orbit.gd) за use_orbit; інакше null — не в сейві
var hint_active: Dictionary = {}    # spec 0012 (ON): {id, since_ms} — видима підказка (≤ 1); не сейв, не хеш
var hint_cooldowns: Dictionary = {} # spec 0012 (ON): id -> until_ms; sticky у сейві поза world_hash (REQ-0012-49/51)
var last_catch_up: Dictionary = {}
var _frame_now: int = 0             # spec 0012 REQ-38: годинник попереднього кадру (розрив ⇒ догін); не сейв   # spec 0012: звіт останнього догону (для картки «поки тебе не було»); не сейв
var last_error: StringName = &""  # чому start()/restore_game()/travel_to() відмовили (&"" — усе гаразд); для UI/тестів
var _goal_t := 0.0

# false (+ last_error, sim == null) — конфігурація не дозволила створити світ (ON без інвентаря/каталогу, мапа без місця);
# OFF завжди true. `now_ms` — годинник пристрою на межі сесії (власник — spec 0012): push_clock ДО new_game, щоб landed_at
# капсули взявся з нього, а не з 0 (0 == годинник не подано). Сим сам час не читає (REQ-0010-92).
func start(lat: float, lon: float, place_name: String, now_ms: int = 0) -> bool:
	last_error = &""
	realm_net = null
	if use_orbit and not use_inventory:   # spec 0011 REQ-0011-3: орбіта без особистого інвентаря заборонена — явна відмова ДО побудови світу
		last_error = &"orbit_needs_inventory"
		return false
	var loc: Dictionary = Location.validate({"lat": lat, "lon": lon})   # spec 0012 REQ-75: невалідне місце не створює регіон
	if not bool(loc.ok):
		last_error = StringName(loc.reason)
		return false
	var m := WorldGen.generate_map(lat, lon, MAP_N)
	m["place_name"] = place_name
	sim = Sim.new()
	sim.use_inventory = use_inventory   # spec 0009: the playable scene opts new games into the personal inventory
	sim.use_catalog = use_catalog
	sim.use_realtime = use_realtime   # spec 0012: ДО new_game (setter замикається після мапи, REQ-0012-5)
	sim.use_main_capsule = use_main_capsule   # ДО new_game: setter замикається після нього (REQ-0010-02/60)
	push_clock(now_ms)
	sim.new_game(m, false)   # the session issues the climate hint itself, after the landing lines
	if sim.config_error != &"":
		last_error = sim.config_error
		_clear_world()
		return false
	var on: bool = bool(sim.use_main_capsule)
	orbit = Orbit.new_account(WorldGen.hash_seed(lat, lon), maxi(0, now_ms)) if use_orbit else null   # REQ-0011-4/63: 1 active + 1 sleeping
	_sync_orbit_to_sim()
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
	if sim.use_realtime:
		Sim.Realtime.init(sim)   # spec 0012 REQ-9: таймзона — властивість РЕГІОНУ; frac перераховується з now, а не переноситься
	else:
		sim.time.frac = gfrac

# Permadeath: a fresh pawn at the clan home. If you died away, fly home first (region identity,
# NOT presence of any storage — you may have built one at a remote outpost).
func respawn(clone_id: String = "") -> void:
	if orbit != null and not orbit_respawn(clone_id):   # spec 0011 REQ-0011-13: за ON респавн = вибір клона; без клона світ не оживає
		return
	if sim.get("use_main_capsule") == true:   # ON: місце задає шов respawn_anchor, посадку робить landing (REQ-0010-07/09/98)
		sim.respawn_new_pawn(MainCapsule.respawn_anchor(self))
		return
	var cur_key := Persistence.region_key(float(sim.map.lat), float(sim.map.lon))
	var home_key := Persistence.region_key(float(home.lat), float(home.lon))
	if has_home and cur_key != home_key:
		travel_to(home.lat, home.lon, home.name)
	sim.respawn_new_pawn()

# Орбіта → sim: TTL торби (OD-59/90: 24 год) і id активного клона. OFF — нуль/порожньо (торби як до спеки).
func _sync_orbit_to_sim() -> void:
	if sim == null:
		return
	sim.bag_ttl_ms = 86400000 if orbit != null else 0
	sim.active_clone_id = String(Orbit.active_clone(orbit).get("id", "")) if orbit != null else ""

# spec 0011: value data для екрана смерті/Орбіти (лише читання): сплячі клони + секунди до безкоштовного базового.
func orbit_rows() -> Array:
	var out: Array = []
	if orbit == null:
		return out
	for c in orbit["clones"]:
		var d: Dictionary = c
		if String(d["state"]) == Orbit.ACTIVE and sim != null and sim.dead:
			continue   # мертвий активний клон не пропонується
		if String(d["state"]) == Orbit.ACTIVE:
			continue
		out.append({"id": String(d["id"]), "state": String(d["state"]), "genome": String((Orbit.GENOME_NAMES.get(String(d["genome_type"]), "")))})
	return out

@warning_ignore("integer_division")
func orbit_base_wait_s() -> int:
	if orbit == null or sim == null:
		return 0
	return maxi(0, (int(orbit["base_ready_at"]) - int(sim.now_ms)) / 1000)

# spec 0011 REQ-0011-12/13/14: смерть активного клона вилучає його (ідемпотентно за id) і пише last_death; тіло приходить від сплячого
# клона (явний `clone_id` або перший за id), а коли ростер порожній — від безкоштовного базового (кулдаун 5 хв, REQ-0011-60).
# false + last_error (&"orbit_cooldown" / &"orbit_no_clone") — світ лишається мертвим, UI показує Орбіту.
func orbit_respawn(clone_id: String = "") -> bool:
	if orbit == null:
		return true
	var now: int = int(sim.now_ms) if sim != null else 0
	var act: Dictionary = Orbit.active_clone(orbit)
	if not act.is_empty() and sim != null and sim.dead:
		var cause: String = String((sim.last_death as Dictionary).get("cause", "unknown"))
		Orbit.on_death(orbit, String(act["id"]), cause, now)
	else:
		Orbit.to_orbit(orbit)
	var pick: String = clone_id
	if pick == "":
		for c in orbit["clones"]:
			if String((c as Dictionary)["state"]) == Orbit.SLEEPING:
				pick = String((c as Dictionary)["id"])
				break
	if pick == "":
		var b: Dictionary = Orbit.claim_base_clone(orbit, now)
		if not bool(b["ok"]):
			last_error = &"orbit_cooldown" if String(b["reason"]) == "cooldown" else &"orbit_no_clone"
			return false
		pick = String(b["id"])
	var r: Dictionary = Orbit.choose(orbit, pick)
	if not bool(r["ok"]):
		last_error = &"orbit_no_clone"
		return false
	_sync_orbit_to_sim()
	return true

# spec 0011 REQ-0011-7/8: «піднятись на орбіту» — склад капсули → safe_stock (частковий перенос, OD-58). Єдиний шлях поповнення
# safe_stock із світу; потребує капсули (use_main_capsule) і Орбіти. Повертає {ok, moved, left} | {ok:false, reason}.
func orbit_ascend() -> Dictionary:
	if orbit == null or sim == null:
		return {"ok": false, "reason": &"no_orbit"}
	return OrbitStub.send_to_safe_zone(sim, orbit["safe_stock"])

# spec 0011 REQ-0011-8: з рюкзака (обрані id) → safe_stock, лише біля капсули. {ok, moved} | {ok:false, reason}.
func orbit_ascend_pack(picks: Array) -> Dictionary:
	if orbit == null or sim == null:
		return {"ok": false, "reason": &"no_orbit"}
	return OrbitStub.ascend_from_pack(sim, orbit["safe_stock"], picks)

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
	var dday: float = Sim.Realtime.work_dday(sim, dt)   # OD-140: дослідження за ON — робочий темп (REQ-25)
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
	if sim.use_realtime:
		_tick_hints()   # spec 0012 REQ-47/48: за ON — ситуативні підказки замість ланцюга (цілі далі тихо липнуть для журналу)
	var titles: Array = []
	for g in Goals.GOALS:
		var id := String(g.id)
		if goals_done.has(id):
			continue
		if Goals.progress(id, sim, self) >= 1.0:
			goals_done[id] = true
			titles.append(String(g.title))
	if titles.is_empty() or sim.use_realtime:
		return   # за ON — без тостів «далі — …»: порядку цілей нема (REQ-0012-47)
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

# spec 0012 REQ-48/49: одна підказка за раз; гасне, коли ситуація минула або за SHOW_MS, і йде на cooldown.
func _tick_hints() -> void:
	var now: int = int(sim.now_ms)
	var view: Dictionary = Hints.view_of(sim)
	if not hint_active.is_empty():
		var id := String(hint_active.id)
		if Hints.applies(id, view) and now - int(hint_active.since_ms) < Hints.SHOW_MS:
			return
		hint_cooldowns[id] = now + Hints.COOLDOWN_MS
		hint_active = {}
	var nxt: String = Hints.evaluate(view, hint_cooldowns, now)
	if nxt != "":
		hint_active = {"id": nxt, "since_ms": now}

func _hints_to_wire() -> Dictionary:
	var out := {}
	for k in hint_cooldowns:
		out[k] = Clock.to_wire(int(hint_cooldowns[k]))
	return out

func _hint_view() -> Dictionary:
	if hint_active.is_empty():
		return {"available": false, "hints": true}
	var h: Dictionary = Hints.def_of(String(hint_active.id))
	return {"available": true, "hints": true, "done": 0, "total": 0, "all_done": false, "next": "",
		"current": {"id": String(h.id), "title": String(h.title), "hint": String(h.hint), "build": String(h.build), "pct": 0.0}}

# Value data for the HUD GoalsPanel (R8): the first open goal + its live progress + what follows.
func goals_view() -> Dictionary:
	if sim != null and sim.use_realtime:
		return _hint_view()   # spec 0012 REQ-53: за ON постійного чипа «Цілі» нема — лише ефемерна підказка (≤ 1)
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
	if sim.use_realtime:   # spec 0012 REQ-49: cooldown-и підказок — sticky, у сейві (поза world_hash); REQ-73: схема й версія темпу
		data["hints"] = _hints_to_wire()
		data["schema"] = "realtime"
		data["pacing_version"] = Sim.Realtime.Pacing.VERSION
	if sim.use_realtime:   # spec 0012 REQ-31: мітка збереження — годинник пристрою (UTC-мс, рядком); OFF-сейв без нового ключа (REQ-2)
		data["saved_at"] = Clock.to_wire(int(sim.now_ms))
	if orbit != null:   # spec 0011 REQ-0011-36: акаунт-запис Орбіти (OFF-сейв без ключа — байт-у-байт, REQ-0011-2)
		data["orbit"] = Orbit.to_dict(orbit)
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
func restore_game(path: String = SAVE_PATH, now_ms: int = 0) -> bool:
	last_error = &""
	var d := _read_save(path)
	if d.is_empty():
		return false
	if int(d.get("pacing_version", 0)) > Sim.Realtime.Pacing.VERSION:
		last_error = &"pacing_newer"   # spec 0012 REQ-73: сейв новішої збірки (інша таблиця темпу) — відмова з причиною, не мовчазне OFF
		return false
	var restored: Variant = Sim.new()
	if not Persistence.restore(restored, d.active):
		last_error = restored.load_error
		return false
	sim = restored
	use_realtime = bool(sim.use_realtime)   # spec 0012 REQ-62: значення з сейву перемагає дефолт збірки (і в обидва боки)
	# spec 0012 REQ-31/84: догін при вході — чиста функція (стан, saved_at, now), без атак; потім годинник -> frac
	hint_cooldowns = {}
	var hc: Variant = d.get("hints", {})
	if hc is Dictionary:
		for k in hc:
			hint_cooldowns[String(k)] = Clock.from_wire(hc[k], 0)
	last_catch_up = Sim.Realtime.catch_up(sim, Clock.from_wire(d.get("saved_at", "0"), 0), now_ms)
	push_clock(maxi(now_ms, Clock.from_wire(d.get("saved_at", "0"), 0)))
	_log_catch_up(last_catch_up)   # монотонно: відкат годинника нижче saved_at не відкочує світ (REQ-68)
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
	var want_orbit: bool = use_orbit and bool(sim.use_inventory)   # прапор збірки; сейв без `orbit` + ON ⇒ міграція (REQ-0011-37)
	orbit = null
	use_orbit = false
	if not (d.get("orbit", null) is Dictionary) and want_orbit:
		orbit = Orbit.migrate_from_pawn(WorldGen.hash_seed(float(home.lat), float(home.lon)), maxi(0, now_ms), (sim.player.get("skills", {}) as Dictionary))
		use_orbit = true
	elif d.get("orbit", null) is Dictionary:   # spec 0011: Орбіта наздоганяє відсутність одним settle (REQ-0011-19/57), без нападів
		orbit = Orbit.from_dict(d["orbit"])
		use_orbit = true
		if now_ms > 0:
			orbit = Orbit.settle(orbit, now_ms)
	_sync_orbit_to_sim()
	sim.research_unlocked = progression.research.unlocked   # the gates are live before the first tick
	sim._log("▶ Продовжено: %s · день %d." % [str(sim.map.get("place_name", "")), int(sim.time.day)], "good")
	return true

# spec 0012 REQ-38 (OD-149): dt кадру для сима. OFF — як є. ON — розрив кадрів ≥ 5 с (застосунок у фоні) іде через догін
# (без нападів, REQ-84) і цей кадр сим не тікає; коротший розрив — dt обрізається до 0.25 с. Викликати ДО push_clock.
func frame_dt(dt: float, now_ms: int) -> float:
	if sim == null or not sim.use_realtime:
		return dt
	var prev: int = _frame_now
	_frame_now = maxi(_frame_now, now_ms)
	if prev > 0 and now_ms - prev >= Sim.Realtime.MICRO_PAUSE_MS:
		last_catch_up = Sim.Realtime.catch_up(sim, prev, now_ms)
		_log_catch_up(last_catch_up)
		return 0.0
	return minf(dt, Sim.Realtime.MAX_FRAME_DT)

# spec 0012 REQ-37/72 (OD-148): один рядок-підсумок у стрічці після догону ≥ 1 хв — що змінилось, без абзаців; «обрізано», якщо Δ > ліміту.
func _log_catch_up(r: Dictionary) -> void:
	var off_ms: int = int(r.get("offline_ms", 0))
	if off_ms < 60000:
		return
	var parts: Array = ["⏳ Поки тебе не було: %s" % _dur_words(off_ms)]
	if float(r.get("hunger_lost", 0.0)) >= 1.0:
		parts.append("🍖 −%d" % int(round(float(r.hunger_lost))))
	if float(r.get("rest_lost", 0.0)) >= 1.0:
		parts.append("💤 −%d" % int(round(float(r.rest_lost))))
	if int(r.get("days", 0)) > 0:
		parts.append("🌅 +%d дн." % int(r.days))
	if off_ms > int(r.get("applied_ms", 0)):
		parts.append("✂ враховано %s" % _dur_words(int(r.applied_ms)))
	parts.append("🛡 нападів не було")
	sim._log(" · ".join(parts), "warn")

static func _dur_words(ms: int) -> String:
	var mins: int = ms / 60000
	if mins < 60:
		return "%d хв" % mins
	if mins < 48 * 60:
		return "%d год" % (mins / 60)
	return "%d дн." % (mins / 1440)

func stored_region_count() -> int:
	return (store.get("regions", {}) as Dictionary).size()

func chain_head() -> String:
	return str(store.get("head", ""))

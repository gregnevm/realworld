# RealWorld — sim.gd : deterministic, scene-free game simulation (testable headless)
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Climate = preload("res://scripts/kernel/climate.gd")
const Threats = preload("res://scripts/sim/threats.gd")
const SimEnv = preload("res://scripts/sim/environment.gd")
const WorldMeta = preload("res://scripts/sim/world_meta.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const Inventory = preload("res://scripts/sim/inventory.gd")
const Upkeep = preload("res://scripts/sim/upkeep.gd")
const SimPower = preload("res://scripts/sim/power.gd")
const SimFarm = preload("res://scripts/sim/farming.gd")
const Director = preload("res://scripts/sim/director.gd")
const DataBridge = preload("res://scripts/data_bridge.gd")
const CatalogDefs = preload("res://scripts/catalog_defs.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const Persistence = preload("res://scripts/persistence.gd")
const OrbitStub = preload("res://scripts/sim/orbit_stub.gd")
const Haul = preload("res://scripts/sim/haul.gd")

var map: Dictionary
var n: int = 0
var player: Dictionary = {}
var stock: Dictionary = {}
var buildings: Array = []
var bgrid: Dictionary = {}
var enemies: Array = []
var shots: Array = []
var time := {"frac": 0.28, "day": 1, "day_len": 150.0}
# Raid pacing is DIRECTOR-driven (sim/director.gd): `next` idles at RAID_IDLE until Balance's raid
# incident arms the cycle (warning + wave). The timer/next machinery stays so tests/smoke can still
# force a wave by lowering `next` manually.
const RAID_IDLE := 1.0e12
var raid := {"timer": 0.0, "next": RAID_IDLE, "active": false, "warned": false, "wave": 0}
var patrol := {"timer": 0.0, "next": 300.0, "wave": 0}   # патрульні роботи; перший контакт ~день 3
var research_unlocked: Dictionary = {}   # catalog research id -> true; session мостить із kernel/progression
var use_inventory := false   # spec 0009: ON = Minecraft-style personal inventory (buildings are items). Set BEFORE new_game.
var bags: Array = []          # spec 0009: death bags [{x, y, slots, day}] — region state (save + world_hash)
var use_catalog := false   # spec 0008 phase 2: OFF = stock живе на 6 data.gd-ключах (шліфований зріз
                           # байт-у-байт, його сьюти це доводять); ON = ключі stock — catalogue-ids через
                           # data_bridge, тож каталожні рецепти можуть afford-итись проти живого складу.
                           # Прапор ставиться ДО new_game і не фліпається посеред сейва (§5.2 spec 0008).
var use_main_capsule: bool = false:   # spec 0010: ON = Основна капсула (дім/склад/орієнтир); ДО new_game, далі замкнений
	set(v):
		use_main_capsule = MainCapsule.set_flag(self, v)
var main_capsule: Dictionary = {}   # {} при OFF/до посадки; запис — MainCapsule.new_record (tile живе тут)
var config_error: StringName = &""  # непорожнє => new_game нічого не створив (див. MainCapsule.preflight)
var load_error: StringName = &""    # непорожнє => load_region відхилив запис ДО мутацій (MainCapsule.validate_region)
var now_ms: int = 0                 # ВХІД часу (UTC-мс), лише через set_clock; НЕ в сейві й НЕ в world_hash (REQ-0010-92)
var capsule_table: Dictionary = {}  # override таблиці capsule_levels (тести/пак контенту); {} = каталог (MainCapsule.table)
var capsule_cmds_tick: Dictionary = {}   # дедуп cmd_id upgrade_capsule в межах тіка: очищається на початку update(); не хеш
var convoys: Array = []
var regions: Array = []
var convoy_seq := 0
var craft_timer := 0.0
var dead := false
# The last death's value-data epitaph {cause, day, born} for the death screen (view memory like
# health_alerts — not save/hash state; overwritten by the next death).
var last_death: Dictionary = {}
# Located hero health (kernel/health.gd tracker; driven by sim/hero_health.gd). player.hp is a
# DERIVED readout of it; the tracker is what saves, travels and gets hit.
var health: Variant = null
var health_alerts: Dictionary = {}   # feed-toast stages per condition (view-side memory, not hashed)
# Power grid (Batch 8c, sim/power.gd): a derived Thing fleet over the placed powered buildings.
# power_net/power_active are the per-tick verdicts; fuel/charge live ON the building dicts (saved).
var power_things: Dictionary = {}    # cell -> kernel Thing (derived cache; never serialized)
var power_nets: Array = []           # Array of participant-cell Arrays: SPATIAL grids (adjacency+conduits)
var power_net: Dictionary = {}       # aggregate {supply, draw, stored, capacity, brownout} readout
var power_active: Dictionary = {}    # cell -> bool : did the net deliver this tick
var power_dirty := true              # building set changed -> rebuild the fleet lazily
var power_sys: Variant = null        # kernel PowerNetSystem (created once)
# Farming (sim/farming.gd): grower Thing per grow zone; b.growth/b.harvests are the saved truth.
var farm_things: Dictionary = {}     # cell -> kernel Thing carrying CompGrower (derived cache)
var farm_dirty := true
# The Balance director (sim/director.gd): kernel/balance.gd finally PACES the game, not just the
# HUD. Its own seeded stream (env_init) so storyteller rolls never desync raids or weather.
var balance: Variant = null          # kernel Balance instance (knobs at defaults; AI seam later)
var director_rng := RandomNumberGenerator.new()
var move_input := Vector2.ZERO
var messages: Array = []
var messages_seq := 0              # monotonic lifetime append counter (spec 0005 §2.7 FeedbackBus seam);
                                   # NEVER reset by the 40-cap trim so a sequence cursor survives it.
var banner := ""
var flash_msg := ""
var flash_t := 0.0

# spec 0002: capsules / invites / social graph
var capsule: Dictionary = {}
var invites: Array = []
var social: Variant = null        # optional social graph (Social.new_graph); null in headless unit tests

# Batch 8a: живе довкілля (spec 0004 A9/B3/B4/E6). The region's REAL latitude drives temperature,
# season, daylight and weather through the SAME deterministic climate model the kernel proves out;
# enclosure ("roofing" collapsed to 2D) buffers indoor cells; campfires/heaters emit heat; torches/
# lamps emit light. Constants mirror kernel/environment.gd so both layers agree on the physics.
var climate := Climate.ClimateModel_Deterministic.new()
var weather: StringName = &"clear"
var weather_t := 0.0                # game-days until the next weather reroll
var temp_offset := 0.0              # transient regional °C shift (cold snap / heat wave incidents)
var temp_offset_days := 0.0         # remaining days of the shift; <=0 == none
var env_rng := RandomNumberGenerator.new()   # seeded from the region seed -> deterministic weather
var threat_rng := RandomNumberGenerator.new()  # seeded from the region seed -> deterministic raids/ambushes/loot;
                                               # own stream so raids never consume from the weather sequence
var indoor: Dictionary = {}         # cell index -> true : enclosed room cells (flood-fill)

const INDOOR_SETPOINT_C := 21.0     # kernel environment.gd parity
const INDOOR_INSULATION := 0.6
const EMITTER_RADIUS := 6           # Manhattan reach of heat emitters (kernel parity)
const LIGHT_RADIUS := {"campfire": 3.5, "torch": 3.0, "lamp": 5.0}
const DARK_LIGHT_THRESHOLD := 0.35  # below this working slows (spec B3 «−темрява»)
const DARK_WORK_PENALTY := 0.5      # up to +50% gather time in pitch black
const GATHER_REACH := 1.4           # tiles to the node's centre: closer — the hero works where he stands (MainCapsule.gather_stand reads it)
const COLD_SNAP_DIP_C := 6.0        # kernel WeatherSystem parity
const WEATHER_LABEL := SimEnv.WEATHER_LABEL   # re-export: the frozen main.gd reads Sim.WEATHER_LABEL

var astar: AStarGrid2D            # terrain + blocking buildings (player)
var astar_terrain: AStarGrid2D    # terrain only (raiders smash walls)

# ---------------- setup ----------------
func _default_player(sp: Vector2i) -> Dictionary:
	return {
		"px": sp.x + 0.5, "py": sp.y + 0.5, "face": 0.0,
		"hp": 100.0, "hunger": 82.0, "rest": 92.0,
		"carry": {}, "carry_cap": 30, "action": null, "sleeping": false,
		"eat_cd": 0.0, "atk_cd": 0.0, "dep_cd": 0.0,
		"skills": {"gather": 0.0, "combat": 0.0},
		"equipped": {"tool": "", "weapon": ""}, "items": [],
		"born": int(time.day),   # the day this pawn arrived (death screen: «прожив N днів»)
	}

func _default_capsule() -> Dictionary:
	return {"charges": GameData.CAPSULE_DAILY_CHARGES, "radius_km": GameData.CAPSULE_BASE_RADIUS_KM, "last_day": int(time.day)}

func new_game(m: Dictionary, hint: bool = true) -> void:
	config_error = MainCapsule.preflight(use_main_capsule, use_inventory, use_catalog, m)   # &"" при OFF
	if config_error != &"":
		return   # ДО будь-якої мутації: порожній світ + явна причина (REQ-0010-03/59)
	map = m
	n = m.n
	var sp: Vector2i = m.spawn
	player = _default_player(sp)
	bags = []
	if use_inventory:
		Inventory.starter(self)
	stock = {}
	for pair in [["wood", 50], ["stone", 30], ["food", 18], ["scrap", 16], ["planks", 0], ["components", 2]]:
		stock[res_key(pair[0])] = int(pair[1])
	capsule = _default_capsule()
	invites = []
	_build_astar()
	if use_main_capsule:
		MainCapsule.landing(self, WorldGen.canon_coord(float(m.lat), float(m.lon)), sp)   # капсула = склад + дім
	else:
		var lx := sp.x + 1
		var ly := sp.y
		if not build_valid(lx, ly):
			lx = sp.x
			ly = sp.y + 1
		_place_building("storage", lx, ly, -1)
	_init_regions()
	_env_init()
	HeroHealth.reset(self)
	if hint:
		HeroHealth.spawn_hint(self)

# The climate onboarding line (also re-issued by the session AFTER its landing log, so the most
# urgent card sits lowest in the feed, next to where the player is looking).
func spawn_hint() -> void:
	HeroHealth.spawn_hint(self)

# Arrive in a NEW region by capsule: your pawn + full personal inventory, but no base/stock here.
func arrive_region(m: Dictionary, pawn: Dictionary) -> void:
	if MainCapsule.refuses_region_swap(self):
		return   # ON: капсула одна й лишається у своєму регіоні (REQ-0010-04/75) — нічого не стираємо
	map = m
	n = int(m.n)
	_build_astar()
	player = _default_player(m.spawn)
	for k in PAWN_FIELDS:
		if pawn.has(k):
			player[k] = (pawn[k].duplicate(true) if (pawn[k] is Dictionary or pawn[k] is Array) else pawn[k])
	player.carry_cap = int(player.carry_cap)
	stock = {}
	buildings = []
	bgrid = {}
	_reset_local_threats()
	_init_regions()
	_env_init()
	apply_health_dict(pawn.get("health", {}))   # wounds travel with the pawn (legacy pawn -> from hp)
	HeroHealth.spawn_hint(self)
	dead = false

# Region-local state (raiders, convoys, pending raid) does not travel between regions.
func _reset_local_threats() -> void:
	enemies = []
	convoys = []
	shots = []
	raid = {"timer": 0.0, "next": RAID_IDLE, "active": false, "warned": false, "wave": int(raid.get("wave", 0))}
	patrol = {"timer": 0.0, "next": 300.0, "wave": int(patrol.get("wave", 0))}
	banner = ""

# The pawn's portable inventory + condition (what a capsule carries).
const PAWN_FIELDS := ["carry", "carry_cap", "skills", "equipped", "items", "hp", "hunger", "rest", "born", "inv", "hand"]

func extract_pawn() -> Dictionary:
	return {
		"carry": (player.carry as Dictionary).duplicate(true),
		"carry_cap": int(player.carry_cap),
		"skills": (player.skills as Dictionary).duplicate(true),
		"equipped": (player.equipped as Dictionary).duplicate(true),
		"items": (player.items as Array).duplicate(true),
		"hp": float(player.hp), "hunger": float(player.hunger), "rest": float(player.rest),
		"born": int(player.get("born", int(time.day))),
		"health": health_dict(),
	}.merged({"inv": (player.inv as Array).duplicate(true), "hand": int(player.get("hand", 0))} if player.has("inv") else {})

# Overwrite the current pawn's portable state with a travelling pawn, placed at this region's base.
func apply_pawn(pawn: Dictionary) -> void:
	for k in PAWN_FIELDS:
		if pawn.has(k):
			player[k] = (pawn[k].duplicate(true) if (pawn[k] is Dictionary or pawn[k] is Array) else pawn[k])
	player.carry_cap = int(player.carry_cap)
	apply_health_dict(pawn.get("health", {}))
	var c := base_center()
	player.px = c.x + 0.5
	player.py = c.y + 1.5
	player.action = null

# Rebuild a previously-visited region from a persistence record (seed + diff + save).
func load_region(data: Dictionary) -> void:
	load_error = MainCapsule.validate_region(data, not map.is_empty(), use_main_capsule)
	if load_error != &"":
		return   # відхилено ДО будь-якої мутації: ні мапи, ні будівель, ні потоків (REQ-0010-60/83)
	use_main_capsule = bool(data.get("use_main_capsule", false))   # ДО мапи й будівель; сейв без ключа -> OFF (REQ-0010-02)
	var nn := int(data.n)
	var decoded: Dictionary = Persistence.map_from_record(data)
	var m: Dictionary = decoded.map
	if decoded.osm_lost:
		_log("⚠ OSM-регіон пошкоджено (немає збережених тайлів) — тимчасово процедурна карта.", "bad")
	map = m
	n = nn
	_build_astar()
	player = _default_player(m.spawn)
	var pd: Dictionary = data.player
	for f in pd:
		player[f] = (pd[f].duplicate(true) if (pd[f] is Dictionary or pd[f] is Array) else pd[f])
	player["action"] = null
	player.carry_cap = int(player.carry_cap)
	# spec 0008: сейв несе словник ключів складу — відновлюємо прапор ДО копії stock, інакше
	# крос-прапорний load читає чужі ключі й ресурси «зникають». Старі сейви — поточний прапор.
	use_catalog = bool(data.get("use_catalog", use_catalog))
	use_inventory = bool(data.get("use_inventory", false))
	bags = (data.get("bags", []) as Array).duplicate(true)
	stock = {}
	for k in data.stock:
		stock[k] = data.stock[k]
	time.day = int(data.day)
	time.frac = float(data.frac)
	buildings = []
	bgrid = {}
	_reset_local_threats()
	MainCapsule.from_record(self, data.get("main_capsule", {}))   # ON: капсула = buildings[0], як у new_game; OFF: no-op
	for b in data.buildings:
		var placed: Dictionary = _place_building(str(b.kind), int(b.x), int(b.y), float(b.hp))
		for f in ["fuel", "charge", "growth"]:   # power/farming/defense state rides the record
			if b.has(f):
				placed[f] = float(b[f])
		for f in ["harvests", "ammo"]:
			if b.has(f):
				placed[f] = int(b[f])
		if b.has("crop"):
			placed["crop"] = str(b.crop)
	_init_regions()
	_env_init()
	# AFTER the player fields: an old record has no "health" and migrates from the restored hp float
	apply_health_dict(data.get("health", {}))
	dead = false

func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	astar_terrain = AStarGrid2D.new()
	astar_terrain.region = Rect2i(0, 0, n, n)
	astar_terrain.cell_size = Vector2(1, 1)
	astar_terrain.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_terrain.update()
	for y in n:
		for x in n:
			var solid := WorldGen.is_terrain_blocked(map.tiles[y * n + x])
			astar.set_point_solid(Vector2i(x, y), solid)
			astar_terrain.set_point_solid(Vector2i(x, y), solid)

func _refresh_solid(x: int, y: int) -> void:
	var i := y * n + x
	var solid := WorldGen.is_terrain_blocked(map.tiles[i])
	if bgrid.has(i) and building_def(String(bgrid[i].kind)).get("blocks", false):
		solid = true
	astar.set_point_solid(Vector2i(x, y), solid)

func after_map_change() -> void:
	# OSM overlay rewrote terrain: rebuild pathing grids + relocate to the new clearing
	_build_astar()
	for b in buildings:
		if building_def(String(b.kind)).get("blocks", false):
			_refresh_solid(b.x, b.y)
	if MainCapsule.on_map_change(self):
		return   # ON: герой біля капсули (map.spawn = її непрохідна клітинка), склад не переносимо (REQ-0010-06/75)
	var sp: Vector2i = map.spawn
	player.px = sp.x + 0.5
	player.py = sp.y + 0.5
	player.action = null
	for b in buildings:
		if b.kind == "storage":
			bgrid.erase(b.y * n + b.x)
			var lx := sp.x + 1
			var ly := sp.y
			if not build_valid(lx, ly):
				lx = sp.x
				ly = sp.y + 1
			b.x = lx
			b.y = ly
			bgrid[ly * n + lx] = b
			break
	_recompute_indoor()

func _init_regions() -> void:
	WorldMeta.init_regions(self)   # home + 5 nearest hubs (sim/world_meta.gd)

# ---------------- helpers ----------------
func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < n and y < n

func _dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))

func is_blocked(x: int, y: int) -> bool:
	if not _in(x, y):
		return true
	if WorldGen.is_terrain_blocked(map.tiles[y * n + x]):
		return true
	if bgrid.has(y * n + x):
		return building_def(String(bgrid[y * n + x].kind)).get("blocks", false)
	return false

func carry_total() -> int:
	var s := 0
	for k in player.carry:
		s += int(player.carry[k])
	return s

func stock_total() -> int:
	var s := 0
	for k in stock:
		s += int(floor(stock[k]))
	return s

func storage_cap() -> int:
	var c := 200
	for b in buildings:
		var def: Dictionary = building_def(String(b.kind))
		if def.has("capacity"):
			c += int(def.capacity)
	return c

# `quiet`: the caller keeps the remainder (the pawn's own carry) and says so itself — only drops from
# OUTSIDE (loot, cargo, convoys, refunds) truly lose the overflow, so only they log the loss.
func deposit(res: String, amt: int, quiet: bool = false) -> int:
	var room: int = max(0, storage_cap() - stock_total())
	var add: int = min(amt, room)
	var k := res_key(res)
	stock[k] = stock.get(k, 0) + add
	if add < amt and not quiet:
		_log("⚠ Склад переповнений — частину втрачено.", "warn")
	return add

# ---------------- def seam (spec 0008 phase 3) ----------------
# The ONE place a building id becomes a def dict. data.gd owns its tuned Phase-0 defs; with the flag
# on, catalogue-only ids resolve through the CatalogDefs adapter (same dict shape), so every tick
# path (blocks/heat/light/traps/turrets/capacity/hp) serves both vocabularies without caring.
# {} == unknown/not-live-buildable (try_build refuses it).
func building_def(kind: String) -> Dictionary:
	if use_main_capsule and kind == MainCapsule.KIND:
		return MainCapsule.DEF
	if GameData.BUILDINGS.has(kind):
		return GameData.BUILDINGS[kind]
	return CatalogDefs.building(kind) if use_catalog else {}

# ---------------- open stock (spec 0008 phase 2) ----------------
# The ONE seam every stock access goes through. Live data.gd id -> storage key: identity while
# use_catalog is off, the catalogue id (data_bridge) when on. Callers (sim internals, sim/ modules,
# hud_model slices) never touch stock keys directly, so flipping the flag never chases call sites.
func res_key(res) -> String:
	return String(DataBridge.to_catalog(res)) if use_catalog else str(res)

func res_amount(res) -> int:
	return int(stock.get(res_key(res), 0))

# A data.gd cost dict re-keyed into the active stock vocabulary (identity while the flag is off).
func cost_keys(cost: Dictionary) -> Dictionary:
	if not use_catalog:
		return cost
	var out: Dictionary = {}
	for k in cost:
		out[res_key(k)] = cost[k]
	return out

func afford(cost: Dictionary) -> bool:
	return GameData.can_afford(stock, cost_keys(cost))

# «Склад» як можливість, не id: data.gd-склад і (при ON) def з `storage: true` — капсула (REQ-0010-05).
func has_storage_cap(kind: String) -> bool:
	return kind == "storage" or (use_main_capsule and bool(building_def(kind).get("storage", false)))

func base_center() -> Vector2i:
	if not main_capsule.is_empty():
		return MainCapsule.tile(self)
	for b in buildings:
		if b.kind == "storage":
			return Vector2i(b.x, b.y)
	return Vector2i(int(player.px), int(player.py))

func _nearest_enemy(x: float, y: float, maxr: float):
	var best: Variant = null
	var bd := maxr
	for e in enemies:
		var d := _dist(x, y, e.px, e.py)
		if d < bd:
			bd = d
			best = e
	return best

func _near_storage(r: float) -> bool:
	for b in buildings:
		if has_storage_cap(String(b.kind)) and _dist(player.px, player.py, b.x + 0.5, b.y + 0.5) < r:
			return true
	return false

func _log(text: String, cls: String = "") -> void:
	messages.append({"text": text, "cls": cls})
	messages_seq += 1
	if messages.size() > 40:
		messages.remove_at(0)

func _flash(text: String) -> void:
	flash_msg = text
	flash_t = 2.2

# ---------------- environment (Batch 8a) ----------------
# State transitions (region seeding, weather rerolls, indoor BFS) live in sim/environment.gd; the
# cheap per-tile getters below stay here as the sim's public read API. Delegates preserve the seam.
func _env_init() -> void:
	SimEnv.env_init(self)

func _update_environment(dday: float) -> void:
	SimEnv.update_environment(self, dday)

# Regional temperature anomaly (cold snap −, heat wave +) for `days` — Balance incidents (spec E6).
func apply_temp_anomaly(delta_c: float, days: float) -> void:
	temp_offset = delta_c
	temp_offset_days = maxf(0.0, days)

# Outdoor ambient °C right now: the real-latitude climate model + weather dip + incident anomaly.
func ambient_temp_c() -> float:
	var t: float = climate.temperature_c(float(map.lat), float(map.lon), int(time.day), float(time.frac))
	if weather == &"cold_snap":
		t -= COLD_SNAP_DIP_C
	return t + temp_offset

func is_indoor(x: int, y: int) -> bool:
	return indoor.has(y * n + x)

# Felt °C on a tile: ambient → indoor buffering toward the setpoint → nearby active heat emitters.
func temp_at(x: int, y: int) -> float:
	var t := ambient_temp_c()
	if is_indoor(x, y):
		t += (INDOOR_SETPOINT_C - t) * INDOOR_INSULATION
	for b in buildings:
		var heat := float(building_def(String(b.kind)).get("extra", {}).get("heat", 0.0))
		if heat <= 0.0 or not device_active(b):
			continue
		if absi(b.x - x) + absi(b.y - y) <= EMITTER_RADIUS:
			t += heat
	return t

func hero_temp_c() -> float:
	return temp_at(int(player.px), int(player.py))

# Equipped warmth °C (data.gd `insul` on worn gear) — raises the FELT temperature against the cold,
# and symmetrically pushes it up in the heat (a scrap vest is a parka in summer; kernel gear parity).
func hero_insulation_c() -> float:
	var w := 0.0
	for slot in player.equipped:
		var id: String = String(player.equipped[slot])
		if id != "" and GameData.ITEMS.has(id):
			w += float(GameData.ITEMS[id].get("insul", 0.0))
	return w

# The comfort °C the BODY experiences: tile temp (indoor buffering + emitters) + worn insulation.
func hero_felt_c() -> float:
	return hero_temp_c() + hero_insulation_c()

# ---------------- hero health (sim/hero_health.gd delegates) ----------------
func hero_downed() -> bool:
	return HeroHealth.is_downed(self)

func health_dict() -> Dictionary:
	return HeroHealth.to_dict(self)

func apply_health_dict(d: Dictionary) -> void:
	HeroHealth.apply_dict(self, d)

func health_reset() -> void:
	HeroHealth.reset(self)

# Ambient daylight 0..1 from the real-latitude model (long winter nights at high latitude).
func daylight_level() -> float:
	return climate.daylight(float(map.lat), int(time.day), float(time.frac))

# Light 0..1 on a tile: ambient daylight vs the brightest reachable light source (linear falloff).
func light_at(x: int, y: int) -> float:
	var light := daylight_level()
	for b in buildings:
		if not bool(building_def(String(b.kind)).get("extra", {}).get("light", false)):
			continue
		if not device_active(b):
			continue
		var radius: float = float(LIGHT_RADIUS.get(b.kind, 3.0))
		var dist := float(absi(b.x - x) + absi(b.y - y))
		if dist <= radius:
			light = maxf(light, clampf(1.0 - dist / radius, 0.0, 1.0))
	return clampf(light, 0.0, 1.0)

# Does this device run right now? Fuel-free passives (багаття/смолоскип — every data.gd def) always
# do; a def that declares a power TRADER role runs only when the net delivered this tick (Batch 8c,
# sim/power.gd — the seam this function was built for).
func device_active(b) -> bool:
	return SimPower.is_active(self, b)

func dispose_power() -> void:
	SimPower.dispose(self)

func dispose_farm() -> void:
	SimFarm.dispose(self)

func is_wet() -> bool:
	return weather == &"rain" or weather == &"snow"

func season_name() -> String:
	return str(Climate.SEASON_NAME.get(climate.season(float(map.lat), int(time.day)), "?"))

# spec B3: unlit night work is slower — up to +50% time in pitch black; torches/lamps cancel it.
func dark_work_mult() -> float:
	var light := light_at(int(player.px), int(player.py))
	if light >= DARK_LIGHT_THRESHOLD:
		return 1.0
	return 1.0 + DARK_WORK_PENALTY * (DARK_LIGHT_THRESHOLD - light) / DARK_LIGHT_THRESHOLD

# Enclosure geometry → indoor map (spec B4): the BFS lives in sim/environment.gd.
func _recompute_indoor() -> void:
	SimEnv.recompute_indoor(self)

# ---------------- building ----------------
func _place_building(kind: String, x: int, y: int, hp: float):
	var def: Dictionary = building_def(kind)
	var b := {"kind": kind, "x": x, "y": y, "hp": (float(def.get("hp", 50.0)) if hp < 0 else hp), "cool": 0.0, "aim": 0.0}
	buildings.append(b)
	bgrid[y * n + x] = b
	power_dirty = true
	farm_dirty = true
	if def.get("blocks", false):
		_refresh_solid(x, y)
	if def.get("blocks", false) or kind.begins_with("door"):
		_recompute_indoor()   # enclosure geometry changed (spec B4)
	return b

func _remove_building(b) -> void:
	buildings.erase(b)
	bgrid.erase(b.y * n + b.x)
	power_dirty = true
	farm_dirty = true
	_refresh_solid(b.x, b.y)
	if building_def(String(b.kind)).get("blocks", false) or String(b.kind).begins_with("door"):
		_recompute_indoor()

func build_valid(x: int, y: int) -> bool:
	if not _in(x, y):
		return false
	var t: int = map.tiles[y * n + x]
	if t == WorldGen.WATER or t == WorldGen.ROCK:
		return false
	if bgrid.has(y * n + x):
		return false
	if map.nodes.has(y * n + x):
		return false
	return true

func try_build(kind: String, x: int, y: int) -> void:
	if not build_valid(x, y):
		_flash("Тут не можна будувати.")
		return
	# ONE def seam serves both vocabularies: data.gd ids always; catalogue-only ids when the flag is
	# on ({} refusal covers unknown ids AND catalogue ids while the flag is off).
	var def: Dictionary = building_def(kind)
	if def.is_empty() or bool(def.get("landmark", false)):   # landmark (капсула) не будується: вона одна (REQ-0010-06)
		_flash("Тут не можна будувати." if def.is_empty() else "Основна капсула одна.")
		return
	if not research_ok(def):
		_flash("🔒 Потребує дослідження: %s." % _research_label(def))
		return
	if use_inventory:   # spec 0009: buildings are ITEMS — place the one you carry
		if not Inventory.take(self, Inventory.BLD + kind, 1):
			_flash("Нема «%s» у рюкзаку — скрафти (🎒)." % String(def.get("name", kind)))
			return
		_place_building(kind, x, y, -1)
		return
	if not afford(def.cost):
		_flash("Бракує: " + _cost_str(def.cost))
		return
	GameData.pay_cost(stock, cost_keys(def.cost))
	_place_building(kind, x, y, -1)

# Player-initiated teardown: recover half the build cost (rounded down). You can never
# demolish your last storage (that would strand deposits), matching the base-centric design.
func demolish(x: int, y: int) -> Dictionary:
	if not _in(x, y) or not bgrid.has(y * n + x):
		return {"ok": false, "msg": "Тут немає будівлі."}
	var b: Dictionary = bgrid[y * n + x]
	if bool(building_def(String(b.kind)).get("indestructible", false)):
		return {"ok": false, "reason": &"indestructible", "msg": "Капсулу не можна розібрати."}
	if b.kind == "storage":
		var storages := 0
		for o in buildings:
			if o.kind == "storage":
				storages += 1
		if storages <= 1:
			return {"ok": false, "msg": "Не можна знести єдиний склад."}
	var bdef: Dictionary = building_def(String(b.kind))
	if use_inventory and Inventory.add(self, Inventory.BLD + String(b.kind), 1) == 0:
		_remove_building(b)   # spec 0009: breaking a block gives the block back (Minecraft)
		_log("♻ %s → у рюкзак." % bdef.get("name", b.kind), "good")
		return {"ok": true}
	var refund := {}
	for res in bdef.get("cost", {}):
		var back: int = int(bdef.cost[res]) / 2
		if back > 0:
			deposit(res, back)
			refund[res] = back
	_remove_building(b)
	_log("♻ %s розібрано%s." % [bdef.get("name", b.kind), (" (+" + _cost_str(refund) + ")") if not refund.is_empty() else ""], "good")
	return {"ok": true}

# ---------------- items / equipment (spec 0001) ----------------
# `at` — клітинка, з якої герой ПРАЦЮВАТИМЕ (підказка вузла, MainCapsule.gather_preview); за замовчуванням — де він стоїть зараз.
func gather_time(node, at: Vector2i = MainCapsule.NO_CELL) -> float:
	var info: Dictionary = GameData.NODEINFO[node.kind]
	var mult: float = 1.0 + player.skills.gather * 0.04
	var tool: String = player.equipped.get("tool", "")
	if tool != "" and GameData.ITEMS.has(tool):
		mult *= float(GameData.ITEMS[tool].get("gather_mult", 1.0))
	if use_main_capsule:   # spec 0010: баф зони капсули на героя (клітинка героя, поточний рівень)
		mult *= MainCapsule.hero_buff(self, "gather_mult", at)
	# darkness and the body both slow the work: HeroHealth.work_mult reads the Manipulation capacity
	# (wounded arms, deep cold, starvation), 1.0 at full health.
	return info.time / mult * dark_work_mult() * HeroHealth.work_mult(self)

# Ворота дерева досліджень: def без поля `research` відкритий завжди; інакше — лише коли session
# домостив відповідний catalog-id у research_unlocked (ключі можуть бути String АБО StringName).
func research_ok(def: Dictionary) -> bool:
	var need := String(def.get("research", ""))
	return need == "" or research_unlocked.has(need) or research_unlocked.has(StringName(need))

func _research_label(def: Dictionary) -> String:
	var need := String(def.get("research", ""))
	# data.gd mirrors the labels for its own five gates; catalogue-only gates read the catalogue label
	return String(GameData.RESEARCH_LABEL.get(need, CatalogDefs.research_label(need)))

# ---------------- crop selection (farming v2) ----------------
# Cycle the selected crop of an OWN grow building ("" == the mixed rotation). Value-data result —
# the router owns the user-facing text (R10); label passes through catalogue data.
func set_crop(x: int, y: int) -> Dictionary:
	if not _in(x, y) or not bgrid.has(y * n + x):
		return {"ok": false}
	var b: Dictionary = bgrid[y * n + x]
	if not bool(building_def(String(b.kind)).get("grow", false)):
		return {"ok": false}
	var crop := CatalogDefs.next_crop(String(b.get("crop", "")))
	if crop == "":
		b.erase("crop")
	else:
		b["crop"] = crop
	return {"ok": true, "crop": crop,
		"label": CatalogDefs.res_label(crop) if crop != "" else "",
		"icon": CatalogDefs.res_icon(crop) if crop != "" else ""}

# The best cooked meal in stock ("" = none / flag off): highest nutrition first, deterministic
# tie-break by id. Meal keys only ever exist in the open-stock vocabulary.
func _best_meal() -> String:
	if not use_catalog:
		return ""
	var best := ""
	var best_n := 0.0
	var ids: Array = CatalogDefs.MEAL_NUTRITION.keys()
	ids.sort()
	for id in ids:
		var nutrition := float(CatalogDefs.MEAL_NUTRITION[id])
		if int(stock.get(id, 0)) >= 1 and nutrition > best_n:
			best = str(id)
			best_n = nutrition
	return best

# Cost line valid in EITHER stock vocabulary (data.gd RES icons know only the 6 live ids).
func _cost_str(cost: Dictionary) -> String:
	if not use_catalog:
		return GameData.cost_str(cost)
	var parts := []
	for k in cost:
		parts.append("%s%d" % [CatalogDefs.res_icon(str(k)), int(cost[k])])
	return " ".join(parts)

# Броня ріже вхідний урон: 1.0 без броні, 0.7 у жилеті, 0.5 у панцирі (data.gd dmg_cut).
func armor_mult() -> float:
	var arm: String = String(player.equipped.get("armor", ""))
	if arm != "" and GameData.ITEMS.has(arm):
		return 1.0 - float(GameData.ITEMS[arm].get("dmg_cut", 0.0))
	return 1.0

func melee_damage() -> float:
	var dmg: float = 12.0 + player.skills.combat
	var wpn: String = player.equipped.get("weapon", "")
	if wpn != "" and GameData.ITEMS.has(wpn):
		dmg += float(GameData.ITEMS[wpn].get("dmg_bonus", 0.0))
	return dmg * HeroHealth.melee_mult(self)   # a mangled arm swings weaker; 1.0 at full health

func has_workbench() -> bool:
	for b in buildings:
		if b.kind == "workbench":
			return true
	return false

func has_building(kind: String) -> bool:
	for b in buildings:
		if String(b.kind) == kind:
			return true
	return false

# ---------------- catalogue crafting (spec 0008 phase 3) ----------------
# Execute a catalogue recipe at its placed station: pay the inputs from the open stock, deposit the
# output. Instant, like the slice's craft_item (work-time bills stay kernel-side for now). Returns
# value-data {ok, reason, ...} — the ROUTER maps reasons to user-facing text (R10: no new Ukrainian
# authored here; `label` fields pass through catalogue data).
func craft_catalog(recipe_id: String) -> Dictionary:
	var rc: Dictionary = CatalogDefs.recipe(recipe_id)
	var refusal := _craft_refusal(rc)
	if not refusal.is_empty():
		return refusal
	var inputs: Dictionary = rc.get("inputs", {})
	GameData.pay_cost(stock, cost_keys(inputs))
	var out: Dictionary = rc.get("output", {})
	var added := deposit(String(out.get("id", "")), int(out.get("count", 1)))
	return {"ok": true, "label": String(rc.get("label", recipe_id)), "added": added,
		"out_icon": CatalogDefs.res_icon(String(out.get("id", "")))}

# The first failing precondition as a value-data refusal ({} == craftable now). Single-exit
# elif-chain so each guard names its reason without a return-ladder.
func _craft_refusal(rc: Dictionary) -> Dictionary:
	var station := String(rc.get("station", ""))
	var st: Variant = null
	for b in buildings:
		if String(b.kind) == station:
			st = b
			break
	var r: Dictionary = {}
	if not use_catalog:
		r = {"ok": false, "reason": &"catalog_off"}
	elif rc.is_empty():
		r = {"ok": false, "reason": &"unknown"}
	elif st == null:
		r = {"ok": false, "reason": &"no_station", "station_label": CatalogDefs.building_label(station)}
	elif not device_active(st):
		r = {"ok": false, "reason": &"no_power", "station_label": CatalogDefs.building_label(station)}
	elif not research_ok(rc):
		r = {"ok": false, "reason": &"locked", "research_label": _research_label(rc)}
	elif not afford(rc.get("inputs", {})):
		r = {"ok": false, "reason": &"cost", "missing": _cost_str(Catalog.missing_for(cost_keys(rc.get("inputs", {})), stock))}
	return r

# Repair lives in sim/upkeep.gd (touch Repair mode / radial «Ремонт»); one delegate keeps the verb API.
func repair(x: int, y: int) -> Dictionary:
	return Upkeep.repair(self, x, y)

func craft_item(item_id: String) -> Dictionary:
	if not GameData.ITEMS.has(item_id):
		return {"ok": false, "msg": "Невідомий предмет."}
	if player.items.has(item_id):
		equip(item_id)  # already owned -> just (re)equip for free, never re-pay
		_log("⚔ Екіпіровано: %s." % GameData.ITEMS[item_id].name)
		return {"ok": true}
	var gate := "" if has_workbench() else "Потрібен верстак."
	if gate == "" and not research_ok(GameData.ITEMS[item_id]):
		gate = "🔒 Потребує дослідження: %s." % _research_label(GameData.ITEMS[item_id])
	if gate != "":
		return {"ok": false, "msg": gate}
	if use_inventory:   # spec 0009: tools are crafted from what you carry and land in the backpack
		return Inventory.craft_tool(self, item_id)
	var recipe: Dictionary = GameData.ITEMS[item_id].recipe
	if not afford(recipe):
		return {"ok": false, "msg": "Бракує: " + GameData.cost_str(recipe)}
	GameData.pay_cost(stock, cost_keys(recipe))
	player.items.append(item_id)
	equip(item_id)
	_log("🛠 Скрафтив та екіпірував: %s." % GameData.ITEMS[item_id].name, "good")
	return {"ok": true}

func equip(item_id: String) -> void:
	if not GameData.ITEMS.has(item_id) or not player.items.has(item_id):
		return
	var slot: String = GameData.ITEMS[item_id].slot
	player.equipped[slot] = item_id

# ---------------- pathfinding ----------------
func _nearest_free(grid: AStarGrid2D, c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := c.x + dx
				var y := c.y + dy
				if not _in(x, y):
					continue
				if not grid.is_point_solid(Vector2i(x, y)):
					return Vector2i(x, y)
	return Vector2i(-1, -1)

func _path_on(grid: AStarGrid2D, fx: int, fy: int, tx: int, ty: int) -> Array:
	tx = clampi(tx, 0, n - 1)
	ty = clampi(ty, 0, n - 1)
	var from := Vector2i(fx, fy)
	var tgt := Vector2i(tx, ty)
	if grid.is_point_solid(tgt):
		tgt = _nearest_free(grid, tgt)
		if tgt == Vector2i(-1, -1):
			return []
	# A solid start (e.g. player built a wall on their own tile) would otherwise
	# yield an empty path; clear it for the query to match JS (it escapes anyway).
	var start_solid := grid.is_point_solid(from)
	if start_solid:
		grid.set_point_solid(from, false)
	# allow_partial_path=true => best-effort partial path toward the closest
	# reachable cell when the target is unreachable (matches JS findPath semantics).
	var p := grid.get_id_path(from, tgt, true)
	if start_solid:
		grid.set_point_solid(from, true)
	var out := []
	for i in range(1, p.size()):
		out.append(p[i])
	return out

func compute_path(fx: int, fy: int, tx: int, ty: int) -> Array:
	return _path_on(astar, fx, fy, tx, ty)

func _terrain_path(fx: int, fy: int, tx: int, ty: int) -> Array:
	return _path_on(astar_terrain, fx, fy, tx, ty)

# ---------------- orders ----------------
func order_move(tx: int, ty: int) -> void:
	player.sleeping = false
	var path := compute_path(int(player.px), int(player.py), tx, ty)
	if path.is_empty():
		_flash("Туди не дійти.")
		return
	player.action = {"type": "move", "path": path, "cell": (ty * n + tx if _in(tx, ty) else -1)}

func order_gather(x: int, y: int) -> void:
	player.sleeping = false
	if not _in(x, y) or not map.nodes.has(y * n + x):
		return
	var path := compute_path(int(player.px), int(player.py), x, y)
	player.action = {"type": "gather", "nx": x, "ny": y, "cell": y * n + x, "path": path, "t": 0.0, "dur": 0.0}

func order_attack(e) -> void:
	player.sleeping = false
	player.action = {"type": "attack", "target": e, "path": [], "repath_cd": 0.0}

# ---------------- movement ----------------
func _step_to(o: Dictionary, tx: float, ty: float, step: float) -> bool:
	var dx: float = tx - o.px
	var dy: float = ty - o.py
	var d := sqrt(dx * dx + dy * dy)
	if d <= step or d < 1e-6:
		o.px = tx
		o.py = ty
		return true
	o.px += dx / d * step
	o.py += dy / d * step
	o.face = atan2(dy, dx)
	return false

func _follow_path(o: Dictionary, path: Array, step: float) -> bool:
	if path.is_empty():
		return true
	var nx: Vector2i = path[0]
	if _step_to(o, nx.x + 0.5, nx.y + 0.5, step):
		path.remove_at(0)
	return path.is_empty()

# ---------------- main update ----------------
func update(dt: float) -> void:
	capsule_cmds_tick.clear()
	if flash_t > 0:
		flash_t = max(0.0, flash_t - dt)
	if dead:
		return  # match JS: the sim freezes after death (no needs/raids/convoys advance)
	time.frac += dt / time.day_len
	while time.frac >= 1.0:
		time.frac -= 1.0
		time.day += 1
		_log("🌅 Новий день: %d" % time.day)
		if not use_main_capsule:
			_grant_daily_capsule()   # щоденний заряд spec 0002 — лише OFF (REQ-0010-41)
	_update_environment(dt / time.day_len)
	SimPower.update(self, dt)   # after environment (solar reads daylight, wind reads weather)
	SimFarm.update(self, dt)    # after power (hydroponics grows only when the net delivered)
	Director.update(self, dt)   # Balance rolls incidents; raids arm BEFORE threats tick below
	_update_player(dt)
	_update_crafting(dt)
	_update_raids(dt)
	_update_patrols(dt)
	_update_enemies(dt)
	_update_turrets(dt)
	_update_convoys(dt)
	for i in range(shots.size() - 1, -1, -1):
		shots[i].t -= dt
		if shots[i].t <= 0:
			shots.remove_at(i)

func _update_player(dt: float) -> void:
	var p: Dictionary = player
	p.atk_cd = max(0.0, p.atk_cd - dt)
	p.eat_cd = max(0.0, p.eat_cd - dt)
	p.dep_cd = max(0.0, p.dep_cd - dt)
	p.hunger = clampf(p.hunger - 0.42 * dt, 0, 100)
	var rest0: float = p.rest   # spec 0010 (REQ-0010-107): множник відновлення сну застосовується до приросту OFF-рядка нижче
	p.rest = clampf(p.rest - (-14.0 if p.sleeping else 0.30) * dt, 0, 100)
	if use_main_capsule and p.sleeping:   # сон у зоні капсули відновлює швидше (need_recovery_mult); наростання втоми (0.30) і межі не чіпаємо
		p.rest = clampf(rest0 + (p.rest - rest0) * _capsule_recovery(), 0, 100)
	# located health (sim/hero_health.gd): empty needs and the real climate grow condition hediffs,
	# wounds heal/bleed, the death verdict falls, and p.hp becomes the derived readout of it all.
	HeroHealth.update(self, dt)
	if dead:
		return
	if HeroHealth.is_downed(self):
		return   # unconscious where they fell: no eating, hauling, orders or movement; needs run on
	if use_inventory:
		Inventory.pickup_bags(self)
		if p.hunger < 55 and p.eat_cd <= 0 and Inventory.count(self, "food") > 0:
			Inventory.take(self, "food", 1)   # food you carry is eaten on the go (the backpack IS the larder)
			p.hunger = min(100.0, p.hunger + 38.0)
			p.eat_cd = 2.5
	if p.hunger < 55 and p.eat_cd <= 0 and _near_storage(2.2):
		# cooked meals first (spec 0008: thing-outputs are edible stock — cooking beats foraging);
		# the flag-OFF path is byte-identical to the shipped slice (no meal keys can exist there)
		var meal := _best_meal()
		if meal != "":
			stock[meal] -= 1
			p.hunger = min(100.0, p.hunger + CatalogDefs.meal_nutrition(meal))
			p.eat_cd = 2.5
		elif res_amount("food") >= 1:
			stock[res_key("food")] -= 1
			p.hunger = min(100.0, p.hunger + 38.0)
			p.eat_cd = 2.5
	if carry_total() > 0 and p.dep_cd <= 0 and _near_storage(1.8):
		for k in p.carry.keys():
			if p.carry[k] > 0:
				var a := deposit(k, p.carry[k], true)
				p.carry[k] -= a
		p.dep_cd = 0.4
		if carry_total() > 0:
			# nothing is lost — the load stays in the pawn's hands; the flash re-arms, never spams
			_flash("📦 Склад повний — збудуй ще один склад (4).")
	var step := 3.4 * HeroHealth.move_mult(self) * dt   # wounded legs / blood loss / freezing slow you
	if move_input.length() > 0.1:
		p.action = null
		p.sleeping = false
		var v := move_input.normalized()
		var nx: float = p.px + v.x * step
		var ny: float = p.py + v.y * step
		if not is_blocked(int(floor(nx)), int(floor(p.py))):
			p.px = nx
		if not is_blocked(int(floor(p.px)), int(floor(ny))):
			p.py = ny
		p.face = atan2(v.y, v.x)
		return
	if p.action == null:
		var e: Variant = _nearest_enemy(p.px, p.py, 1.4)
		if e != null:
			p.action = {"type": "attack", "target": e, "path": [], "repath_cd": 0.0}
	if p.action == null:
		_maybe_sleep(dt)
		return
	match p.action.type:
		"move":
			if _follow_path(p, p.action.path, step):
				p.action = null
		"gather":
			_do_gather(dt, step)
		"haul":
			Haul.do_haul(self, step)
		"attack":
			_do_attack(dt, step)

func _do_gather(dt: float, step: float) -> void:
	var p: Dictionary = player
	var a: Dictionary = p.action
	if not map.nodes.has(a.cell):
		p.action = null
		return
	var node: Dictionary = map.nodes[a.cell]
	if _dist(p.px, p.py, a.nx + 0.5, a.ny + 0.5) >= GATHER_REACH:
		var done := _follow_path(p, a.path, step)
		p.face = atan2(a.ny + 0.5 - p.py, a.nx + 0.5 - p.px)
		if done and not WorldGen.is_terrain_blocked(map.tiles[a.cell]):
			_step_to(p, a.nx + 0.5, a.ny + 0.5, step)
		return
	var info: Dictionary = GameData.NODEINFO[node.kind]
	a.dur = gather_time(node)
	a.t += dt
	if a.t >= a.dur:
		a.t = 0.0
		if not use_inventory and carry_total() >= p.carry_cap:
			Haul.start_haul(self, int(a.cell), String(node.kind))   # full hands: carry the load home, come back
			return
		# phase 4 (spec 0008): under the open catalogue, a node yields its catalogue BUNDLE — rocks
		# occasionally give ore/coal/clay/sand, trees fiber, bushes herbs. Pure function of
		# (cell, remaining amount): deterministic, and it consumes NO rng stream.
		var res: String = str(info.res)
		if use_catalog:
			var enriched := CatalogDefs.gather_yield(str(node.kind), int(a.cell), int(node.amount))
			if enriched != "":
				res = enriched
		if use_inventory:   # spec 0009: the yield lands in the backpack; a full one stops the work
			if Inventory.room(self, res) <= 0:
				_flash("🎒 Рюкзак повний — розклади на складі.")
				p.action = null
				return
			Inventory.add(self, res, 1)
		else:
			p.carry[res] = p.carry.get(res, 0) + 1
		node.amount -= 1
		p.skills.gather = min(20.0, p.skills.gather + 0.2)
		if node.amount <= 0:
			map.nodes.erase(a.cell)
			p.action = null
			Haul.continue_gather(self, int(a.cell), String(node.kind))

# ---------------- auto-haul (gather loop closes itself) lives in sim/haul.gd ----------------

func _nearest_storage() -> Variant:
	var best: Variant = null
	var bd := INF
	for b in buildings:
		if not has_storage_cap(String(b.kind)):
			continue
		var d := _dist(player.px, player.py, b.x + 0.5, b.y + 0.5)
		if d < bd:
			bd = d
			best = b
	return best

func _do_attack(dt: float, step: float) -> void:
	var p: Dictionary = player
	var a: Dictionary = p.action
	var e: Variant = a.target
	if e == null or e.dead or not enemies.has(e):
		var nx: Variant = _nearest_enemy(p.px, p.py, 2.5)
		if nx != null:
			a.target = nx
			e = nx
		else:
			p.action = null
			return
	var d := _dist(p.px, p.py, e.px, e.py)
	if d > 1.25:
		a.repath_cd -= dt
		if a.path.is_empty() or a.repath_cd <= 0:
			a.path = compute_path(int(p.px), int(p.py), int(e.px), int(e.py))
			a.repath_cd = 0.4
		_follow_path(p, a.path, step)
		p.face = atan2(e.py - p.py, e.px - p.px)
	else:
		p.face = atan2(e.py - p.py, e.px - p.px)
		if p.atk_cd <= 0:
			_damage_enemy(e, melee_damage())
			p.atk_cd = 0.7
			p.skills.combat = min(20.0, p.skills.combat + 0.15)

func _maybe_sleep(_dt: float) -> void:
	var p: Dictionary = player
	if p.rest >= 99:
		p.sleeping = false
		return
	var bed: Variant = null
	for b in buildings:
		# bed CAPABILITY, not the id: data.gd's bed carries `bed:true`, and so do the live
		# catalogue medical beds (medbed/hospital_bed) — a future bed def sleeps without edits
		if building_def(String(b.kind)).get("bed", false) and _dist(p.px, p.py, b.x + 0.5, b.y + 0.5) < 1.6:
			bed = b
			break
	p.sleeping = (bed != null and _nearest_enemy(p.px, p.py, 9) == null)

func _update_crafting(dt: float) -> void:
	var count := 0
	for b in buildings:
		if b.kind == "workbench":
			count += 1
	if count == 0:
		return
	if use_main_capsule:   # spec 0010: кожен верстак — зі своїм бафом місця; таймер лише накопичується (REQ-0010-80)
		craft_timer += dt * MainCapsule.craft_rate(self)
	else:
		craft_timer += dt * count
	while craft_timer >= 3.5:
		craft_timer -= 3.5
		if res_amount("wood") >= 2 and stock_total() < storage_cap():
			stock[res_key("wood")] -= 2
			stock[res_key("planks")] = res_amount("planks") + 1

# ---------------- threats (raids / patrol robots / enemies / turrets) ----------------
# The whole threat domain lives in sim/threats.gd; these one-line delegates preserve the sim API for
# every caller (session, tests, frozen main.gd). Adding threat behaviour edits the module, not this file.
func _update_raids(dt: float) -> void:
	Threats.update_raids(self, dt)

func _spawn_wave() -> void:
	Threats.spawn_wave(self)

func _update_patrols(dt: float) -> void:
	Threats.update_patrols(self, dt)

func _spawn_patrol() -> void:
	Threats.spawn_patrol(self)

func _update_enemies(dt: float) -> void:
	Threats.update_enemies(self, dt)

func _update_turrets(dt: float) -> void:
	Threats.update_turrets(self, dt)

func _damage_building(b, amt: float, steal: bool) -> void:
	Threats.damage_building(self, b, amt, steal)

func _damage_enemy(e, amt: float) -> void:
	Threats.damage_enemy(self, e, amt)

func _on_death() -> void:
	Threats.on_death(self)

func respawn_new_pawn(anchor: Dictionary = {}) -> void:
	Threats.respawn_new_pawn(self, anchor)   # anchor — MainCapsule.respawn_anchor (лише ON; OFF ігнорує)

# ЧИЄ тіло повертається після смерті — шов spec 0011 (до неї стаб OrbitStub: стартовий пішак); його підміняють 0011 і тести.
func respawn_source() -> Dictionary:
	return OrbitStub.respawn_source(self)

# Прокачка Основної капсули: value-data результат (MainCapsule.upgrade); verb/роутер — W4a. cmd_id -1 == без дедуплікації.
func upgrade_capsule(cmd_id: int = -1) -> Dictionary:
	return MainCapsule.upgrade(self, cmd_id)

func capsule_level() -> int:
	return int(main_capsule.get("level", 0))

# Множник ВІДНОВЛЕННЯ потреб героя в зоні капсули (REQ-0010-107; 1.0 — нейтральний): читають sim._update_player (сон) і HeroHealth.update (комфорт).
func _capsule_recovery() -> float:
	return MainCapsule.recovery_mult(self)

# Годинник пристрою -> sim: єдиний вхід абсолютного часу (власник Clock — spec 0012). Монотонний: відкат не скорочує таймери.
func set_clock(ms: int) -> void:
	now_ms = maxi(now_ms, ms)

# ---------------- capsules & invites (spec 0002) ----------------
# Bodies live in sim/world_meta.gd (capsule travel + invite envelopes); delegates keep the sim API.
func _grant_daily_capsule() -> void:
	WorldMeta.grant_daily_capsule(self)

func capsule_can_reach(lat: float, lon: float) -> Dictionary:
	return WorldMeta.capsule_can_reach(self, lat, lon)

func try_launch_capsule(lat: float, lon: float, place_name: String) -> Dictionary:
	return WorldMeta.try_launch_capsule(self, lat, lon, place_name)

func add_invite(inv: Dictionary, quiet: bool = false) -> void:
	WorldMeta.add_invite(self, inv, quiet)

func accept_invite(id: String) -> Dictionary:
	return WorldMeta.accept_invite(self, id)

func region_display() -> String:
	# show coordinates at the SAME 4-dp precision that actually seeds the world, so what the player
	# reads is a faithful, shareable handle on this exact world (not a coarser, ambiguous one).
	return "%s (%.4f, %.4f)" % [str(map.get("place_name", "Регіон")), float(map.lat), float(map.lon)]

# The seed IS the coordinate: the terrain/nodes of this region are a pure function of it.
func region_seed() -> int:
	return int(map.get("seed", WorldGen.hash_seed(float(map.lat), float(map.lon))))

# ---------------- logistics ----------------
# Convoy bodies live in sim/world_meta.gd; delegates keep the sim API (tests drive _update_convoys).
func dispatch_convoy(hub_index: int, send_res: String, send_amt: int) -> Dictionary:
	return WorldMeta.dispatch_convoy(self, hub_index, send_res, send_amt)

func _update_convoys(dt: float) -> void:
	WorldMeta.update_convoys(self, dt)

# ---------------- presentation helpers ----------------
const NIGHT_ALPHA_MAX := 0.46   # darkest night tint (the view's ambient-night pass reads the same const)

func daylight() -> float:
	# night-overlay alpha from the REAL daylight curve: high latitude gets long winter nights.
	return clampf(NIGHT_ALPHA_MAX * (1.0 - daylight_level()), 0.0, NIGHT_ALPHA_MAX)

func phase_name() -> String:
	var f: float = time.frac
	if f < 0.22 or f > 0.80:
		return "🌙 ніч"
	if f < 0.30:
		return "🌅 світанок"
	if f > 0.72:
		return "🌇 сутінки"
	return "☀ день"

func clock_str() -> String:
	var mins := int(time.frac * 24 * 60)
	return "%02d:%02d" % [mins / 60, mins % 60]


func _inv_drop_bag() -> void:
	Inventory.drop_bag(self)
func _inv_empty() -> Array:
	return Inventory.empty_slots()
# stock withdrawal THROUGH the seam (spec 0008 tripwire: no stock[...] outside sim.gd's seam)
func _stock_take(res: String, k: int) -> void:
	var key: String = res_key(res)
	stock[key] = int(stock.get(key, 0)) - k

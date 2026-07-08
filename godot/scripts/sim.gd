# RealWorld — sim.gd : deterministic, scene-free game simulation (testable headless)
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Social = preload("res://scripts/social.gd")
const Climate = preload("res://scripts/kernel/climate.gd")

var map: Dictionary
var n: int = 0
var player: Dictionary = {}
var stock: Dictionary = {}
var buildings: Array = []
var bgrid: Dictionary = {}
var enemies: Array = []
var shots: Array = []
var time := {"frac": 0.28, "day": 1, "day_len": 150.0}
var raid := {"timer": 0.0, "next": 95.0, "active": false, "warned": false, "wave": 0}
var convoys: Array = []
var regions: Array = []
var convoy_seq := 0
var craft_timer := 0.0
var dead := false
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
var social = null                 # optional social graph (Social.new_graph); null in headless unit tests

# Batch 8a: живе довкілля (spec 0004 A9/B3/B4/E6). The region's REAL latitude drives temperature,
# season, daylight and weather through the SAME deterministic climate model the kernel proves out;
# enclosure ("roofing" collapsed to 2D) buffers indoor cells; campfires/heaters emit heat; torches/
# lamps emit light. Constants mirror kernel/environment.gd so both layers agree on the physics.
var climate = Climate.ClimateModel_Deterministic.new()
var weather: StringName = &"clear"
var weather_t := 0.0                # game-days until the next weather reroll
var temp_offset := 0.0              # transient regional °C shift (cold snap / heat wave incidents)
var temp_offset_days := 0.0         # remaining days of the shift; <=0 == none
var env_rng := RandomNumberGenerator.new()   # seeded from the region seed -> deterministic weather
var indoor: Dictionary = {}         # cell index -> true : enclosed room cells (flood-fill)

const INDOOR_SETPOINT_C := 21.0     # kernel environment.gd parity
const INDOOR_INSULATION := 0.6
const EMITTER_RADIUS := 6           # Manhattan reach of heat emitters (kernel parity)
const MAX_ROOM_CELLS := 120         # bigger enclosed pockets are courtyards/caves, not rooms
const LIGHT_RADIUS := {"campfire": 3.5, "torch": 3.0, "lamp": 5.0}
const DARK_LIGHT_THRESHOLD := 0.35  # below this working slows (spec B3 «−темрява»)
const DARK_WORK_PENALTY := 0.5      # up to +50% gather time in pitch black
const COLD_SNAP_DIP_C := 6.0        # kernel WeatherSystem parity
const WEATHER_LABEL := {&"clear": "ясно", &"rain": "дощ", &"snow": "сніг", &"fog": "туман", &"cold_snap": "мороз"}

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
	}

func _default_capsule() -> Dictionary:
	return {"charges": GameData.CAPSULE_DAILY_CHARGES, "radius_km": GameData.CAPSULE_BASE_RADIUS_KM, "last_day": int(time.day)}

func new_game(m: Dictionary) -> void:
	map = m
	n = m.n
	var sp: Vector2i = m.spawn
	player = _default_player(sp)
	stock = {"wood": 50, "stone": 30, "food": 18, "scrap": 16, "planks": 0, "components": 2}
	capsule = _default_capsule()
	invites = []
	_build_astar()
	var lx := sp.x + 1
	var ly := sp.y
	if not build_valid(lx, ly):
		lx = sp.x
		ly = sp.y + 1
	_place_building("storage", lx, ly, -1)
	_init_regions()
	_env_init()

# Arrive in a NEW region by capsule: your pawn + full personal inventory, but no base/stock here.
func arrive_region(m: Dictionary, pawn: Dictionary) -> void:
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
	dead = false

# Region-local state (raiders, convoys, pending raid) does not travel between regions.
func _reset_local_threats() -> void:
	enemies = []
	convoys = []
	shots = []
	raid = {"timer": 0.0, "next": 95.0, "active": false, "warned": false, "wave": int(raid.get("wave", 0))}
	banner = ""

# The pawn's portable inventory + condition (what a capsule carries).
const PAWN_FIELDS := ["carry", "carry_cap", "skills", "equipped", "items", "hp", "hunger", "rest"]

func extract_pawn() -> Dictionary:
	return {
		"carry": (player.carry as Dictionary).duplicate(true),
		"carry_cap": int(player.carry_cap),
		"skills": (player.skills as Dictionary).duplicate(true),
		"equipped": (player.equipped as Dictionary).duplicate(true),
		"items": (player.items as Array).duplicate(true),
		"hp": float(player.hp), "hunger": float(player.hunger), "rest": float(player.rest),
	}

# Overwrite the current pawn's portable state with a travelling pawn, placed at this region's base.
func apply_pawn(pawn: Dictionary) -> void:
	for k in PAWN_FIELDS:
		if pawn.has(k):
			player[k] = (pawn[k].duplicate(true) if (pawn[k] is Dictionary or pawn[k] is Array) else pawn[k])
	player.carry_cap = int(player.carry_cap)
	var c := base_center()
	player.px = c.x + 0.5
	player.py = c.y + 1.5
	player.action = null

# Rebuild a previously-visited region from a persistence record (seed + diff + save).
func load_region(data: Dictionary) -> void:
	var nn := int(data.n)
	var lat := float(data.lat)
	var lon := float(data.lon)
	var m := WorldGen.generate_map(lat, lon, nn)
	m["place_name"] = str(data.get("place_name", "Регіон"))
	# OSM terrain is the ONE thing not reproducible from the coordinate, so it is persisted as a tile
	# blob. Restore it only if intact (right length); never silently fall back to a DIFFERENT world.
	if str(data.get("source", "")) == "osm":
		var decoded := Marshalls.base64_to_raw(str(data.get("tiles_b64", "")))
		if decoded.size() == nn * nn:
			m.tiles = decoded
			m["source"] = "osm"
			# spawn was picked against procedural tiles; re-pick against the real OSM terrain
			m.spawn = WorldGen._pick_spawn(m.tiles, m.nodes, nn)
		else:
			_log("⚠ OSM-регіон пошкоджено (немає збережених тайлів) — тимчасово процедурна карта.", "bad")
	var nodes := {}
	for k in data.nodes:
		var nd = data.nodes[k]
		nodes[int(str(k))] = {"kind": str(nd.kind), "amount": int(nd.amount)}
	m.nodes = nodes
	map = m
	n = nn
	_build_astar()
	player = _default_player(m.spawn)
	var pd: Dictionary = data.player
	for f in pd:
		player[f] = (pd[f].duplicate(true) if (pd[f] is Dictionary or pd[f] is Array) else pd[f])
	player["action"] = null
	player.carry_cap = int(player.carry_cap)
	stock = {}
	for k in data.stock:
		stock[k] = data.stock[k]
	time.day = int(data.day)
	time.frac = float(data.frac)
	buildings = []
	bgrid = {}
	_reset_local_threats()
	for b in data.buildings:
		_place_building(str(b.kind), int(b.x), int(b.y), float(b.hp))
	_init_regions()
	_env_init()
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
	if bgrid.has(i) and GameData.BUILDINGS[bgrid[i].kind].get("blocks", false):
		solid = true
	astar.set_point_solid(Vector2i(x, y), solid)

func after_map_change() -> void:
	# OSM overlay rewrote terrain: rebuild pathing grids + relocate to the new clearing
	_build_astar()
	for b in buildings:
		if GameData.BUILDINGS[b.kind].get("blocks", false):
			_refresh_solid(b.x, b.y)
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
	var home := {"name": map.get("place_name", "Поселення"), "lat": map.lat, "lon": map.lon, "home": true}
	var ranked := []
	for hb in GameData.HUBS:
		var d := WorldGen.haversine_km(home.lat, home.lon, hb.lat, hb.lon)
		if d > 8:
			ranked.append({"name": hb.name, "lat": hb.lat, "lon": hb.lon, "d": d})
	ranked.sort_custom(func(a, b): return a.d < b.d)
	regions = [home]
	for i in range(min(3, ranked.size())):
		var hb = ranked[i]
		regions.append({"name": hb.name, "lat": hb.lat, "lon": hb.lon, "d": hb.d, "offer": GameData.OFFERS[i % GameData.OFFERS.size()]})

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
		return GameData.BUILDINGS[bgrid[y * n + x].kind].get("blocks", false)
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
		var def = GameData.BUILDINGS[b.kind]
		if def.has("capacity"):
			c += int(def.capacity)
	return c

func deposit(res: String, amt: int) -> int:
	var room: int = max(0, storage_cap() - stock_total())
	var add: int = min(amt, room)
	stock[res] = stock.get(res, 0) + add
	if add < amt:
		_log("⚠ Склад переповнений — частину втрачено.", "warn")
	return add

func base_center() -> Vector2i:
	for b in buildings:
		if b.kind == "storage":
			return Vector2i(b.x, b.y)
	return Vector2i(int(player.px), int(player.py))

func _nearest_enemy(x: float, y: float, maxr: float):
	var best = null
	var bd := maxr
	for e in enemies:
		var d := _dist(x, y, e.px, e.py)
		if d < bd:
			bd = d
			best = e
	return best

func _near_storage(r: float) -> bool:
	for b in buildings:
		if b.kind == "storage" and _dist(player.px, player.py, b.x + 0.5, b.y + 0.5) < r:
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
# Seed the deterministic environment for THIS region: the weather stream reproduces from the region
# seed (координати — це seed: погода теж адреса світу), and the indoor map is derived from geometry.
func _env_init() -> void:
	env_rng = RandomNumberGenerator.new()
	env_rng.seed = region_seed()
	temp_offset = 0.0
	temp_offset_days = 0.0
	weather = climate.weather(float(map.lat), float(map.lon), int(time.day), float(time.frac), env_rng)
	weather_t = 0.15 + env_rng.randf() * 0.2
	_recompute_indoor()

func _update_environment(dday: float) -> void:
	weather_t -= dday
	if weather_t <= 0.0:
		var prev := weather
		weather = climate.weather(float(map.lat), float(map.lon), int(time.day), float(time.frac), env_rng)
		weather_t = 0.15 + env_rng.randf() * 0.2
		if weather != prev:
			_log("⛅ Погода: %s." % WEATHER_LABEL.get(weather, str(weather)))
	if temp_offset_days > 0.0:
		temp_offset_days -= dday
		if temp_offset_days <= 0.0:
			temp_offset = 0.0
			temp_offset_days = 0.0
			_log("🌡 Температурна аномалія минула.", "good")

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
		var heat := float(GameData.BUILDINGS[b.kind].get("extra", {}).get("heat", 0.0))
		if heat <= 0.0 or not device_active(b):
			continue
		if absi(b.x - x) + absi(b.y - y) <= EMITTER_RADIUS:
			t += heat
	return t

func hero_temp_c() -> float:
	return temp_at(int(player.px), int(player.py))

# Ambient daylight 0..1 from the real-latitude model (long winter nights at high latitude).
func daylight_level() -> float:
	return climate.daylight(float(map.lat), int(time.day), float(time.frac))

# Light 0..1 on a tile: ambient daylight vs the brightest reachable light source (linear falloff).
func light_at(x: int, y: int) -> float:
	var light := daylight_level()
	for b in buildings:
		if not bool(GameData.BUILDINGS[b.kind].get("extra", {}).get("light", false)):
			continue
		if not device_active(b):
			continue
		var radius: float = float(LIGHT_RADIUS.get(b.kind, 3.0))
		var dist := float(absi(b.x - x) + absi(b.y - y))
		if dist <= radius:
			light = maxf(light, clampf(1.0 - dist / radius, 0.0, 1.0))
	return clampf(light, 0.0, 1.0)

# Does this device run right now? Fuel-free passives (багаття/смолоскип) always do; grid devices
# (heater/lamp/cooler/turret) gate on the power net once Batch 8c wires it — this is that seam.
func device_active(_b) -> bool:
	return true

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

# spec B4 ("roofing") collapsed to 2D: a cell is INDOOR when outside air can't reach it from the map
# edge without crossing a wall/door/blocked terrain, and its enclosed pocket is room-sized. One BFS
# floods the outdoor air in from the edges; enclosed leftovers are grouped into components.
func _recompute_indoor() -> void:
	indoor = {}
	var open := PackedByteArray()
	open.resize(n * n)
	for i in n * n:
		open[i] = 0 if WorldGen.is_terrain_blocked(map.tiles[i]) else 1
	for b in buildings:
		if GameData.BUILDINGS[b.kind].get("blocks", false) or String(b.kind).begins_with("door"):
			open[b.y * n + b.x] = 0
	var outdoor := PackedByteArray()
	outdoor.resize(n * n)
	var queue: Array = []
	for i in n:
		for cell in [Vector2i(i, 0), Vector2i(i, n - 1), Vector2i(0, i), Vector2i(n - 1, i)]:
			var idx: int = cell.y * n + cell.x
			if open[idx] == 1 and outdoor[idx] == 0:
				outdoor[idx] = 1
				queue.append(idx)
	while not queue.is_empty():
		var idx: int = queue.pop_back()
		var cx := idx % n
		var cy := idx / n
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if nx < 0 or ny < 0 or nx >= n or ny >= n:
				continue
			var ni := ny * n + nx
			if open[ni] == 1 and outdoor[ni] == 0:
				outdoor[ni] = 1
				queue.append(ni)
	# every open cell the air didn't reach is enclosed; small pockets are rooms, big ones stay outdoor
	for i in n * n:
		if open[i] != 1 or outdoor[i] == 1 or indoor.has(i):
			continue
		var comp: Array = [i]
		var seen := {i: true}
		var head := 0
		while head < comp.size():
			var idx2: int = comp[head]
			head += 1
			var cx2 := idx2 % n
			var cy2 := idx2 / n
			for d2 in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx2: int = cx2 + d2[0]
				var ny2: int = cy2 + d2[1]
				if nx2 < 0 or ny2 < 0 or nx2 >= n or ny2 >= n:
					continue
				var ni2 := ny2 * n + nx2
				if open[ni2] == 1 and outdoor[ni2] == 0 and not seen.has(ni2):
					seen[ni2] = true
					comp.append(ni2)
		if comp.size() <= MAX_ROOM_CELLS:
			for c in comp:
				indoor[c] = true
		else:
			for c in comp:
				outdoor[c] = 1

# ---------------- building ----------------
func _place_building(kind: String, x: int, y: int, hp: float):
	var def = GameData.BUILDINGS[kind]
	var b := {"kind": kind, "x": x, "y": y, "hp": (def.hp if hp < 0 else hp), "cool": 0.0, "aim": 0.0}
	buildings.append(b)
	bgrid[y * n + x] = b
	if def.get("blocks", false):
		_refresh_solid(x, y)
	if def.get("blocks", false) or kind.begins_with("door"):
		_recompute_indoor()   # enclosure geometry changed (spec B4)
	return b

func _remove_building(b) -> void:
	buildings.erase(b)
	bgrid.erase(b.y * n + b.x)
	_refresh_solid(b.x, b.y)
	if GameData.BUILDINGS[b.kind].get("blocks", false) or String(b.kind).begins_with("door"):
		_recompute_indoor()

func build_valid(x: int, y: int) -> bool:
	if not _in(x, y):
		return false
	var t = map.tiles[y * n + x]
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
	var def = GameData.BUILDINGS[kind]
	if not GameData.can_afford(stock, def.cost):
		_flash("Бракує: " + GameData.cost_str(def.cost))
		return
	GameData.pay_cost(stock, def.cost)
	_place_building(kind, x, y, -1)

# Player-initiated teardown: recover half the build cost (rounded down). You can never
# demolish your last storage (that would strand deposits), matching the base-centric design.
func demolish(x: int, y: int) -> Dictionary:
	if not _in(x, y) or not bgrid.has(y * n + x):
		return {"ok": false, "msg": "Тут немає будівлі."}
	var b = bgrid[y * n + x]
	if b.kind == "storage":
		var storages := 0
		for o in buildings:
			if o.kind == "storage":
				storages += 1
		if storages <= 1:
			return {"ok": false, "msg": "Не можна знести єдиний склад."}
	var refund := {}
	for res in GameData.BUILDINGS[b.kind].cost:
		var back: int = int(GameData.BUILDINGS[b.kind].cost[res]) / 2
		if back > 0:
			deposit(res, back)
			refund[res] = back
	_remove_building(b)
	_log("♻ %s розібрано%s." % [GameData.BUILDINGS[b.kind].name, (" (+" + GameData.cost_str(refund) + ")") if not refund.is_empty() else ""], "good")
	return {"ok": true}

# ---------------- items / equipment (spec 0001) ----------------
func gather_time(node) -> float:
	var info = GameData.NODEINFO[node.kind]
	var mult: float = 1.0 + player.skills.gather * 0.04
	var tool: String = player.equipped.get("tool", "")
	if tool != "" and GameData.ITEMS.has(tool):
		mult *= float(GameData.ITEMS[tool].get("gather_mult", 1.0))
	return info.time / mult * dark_work_mult()

func melee_damage() -> float:
	var dmg: float = 12.0 + player.skills.combat
	var wpn: String = player.equipped.get("weapon", "")
	if wpn != "" and GameData.ITEMS.has(wpn):
		dmg += float(GameData.ITEMS[wpn].get("dmg_bonus", 0.0))
	return dmg

func has_workbench() -> bool:
	for b in buildings:
		if b.kind == "workbench":
			return true
	return false

func craft_item(item_id: String) -> Dictionary:
	if not GameData.ITEMS.has(item_id):
		return {"ok": false, "msg": "Невідомий предмет."}
	if player.items.has(item_id):
		equip(item_id)  # already owned -> just (re)equip for free, never re-pay
		_log("⚔ Екіпіровано: %s." % GameData.ITEMS[item_id].name)
		return {"ok": true}
	if not has_workbench():
		return {"ok": false, "msg": "Потрібен верстак."}
	var recipe = GameData.ITEMS[item_id].recipe
	if not GameData.can_afford(stock, recipe):
		return {"ok": false, "msg": "Бракує: " + GameData.cost_str(recipe)}
	GameData.pay_cost(stock, recipe)
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
	var p = grid.get_id_path(from, tgt, true)
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
	if flash_t > 0:
		flash_t = max(0.0, flash_t - dt)
	if dead:
		return  # match JS: the sim freezes after death (no needs/raids/convoys advance)
	time.frac += dt / time.day_len
	while time.frac >= 1.0:
		time.frac -= 1.0
		time.day += 1
		_log("🌅 Новий день: %d" % time.day)
		_grant_daily_capsule()
	_update_environment(dt / time.day_len)
	_update_player(dt)
	_update_crafting(dt)
	_update_raids(dt)
	_update_enemies(dt)
	_update_turrets(dt)
	_update_convoys(dt)
	for i in range(shots.size() - 1, -1, -1):
		shots[i].t -= dt
		if shots[i].t <= 0:
			shots.remove_at(i)

func _update_player(dt: float) -> void:
	var p = player
	p.atk_cd = max(0.0, p.atk_cd - dt)
	p.eat_cd = max(0.0, p.eat_cd - dt)
	p.dep_cd = max(0.0, p.dep_cd - dt)
	p.hunger = clampf(p.hunger - 0.42 * dt, 0, 100)
	p.rest = clampf(p.rest - (-14.0 if p.sleeping else 0.30) * dt, 0, 100)
	if p.hunger <= 0:
		p.hp -= 2.0 * dt
	if p.rest <= 0:
		p.hp -= 1.0 * dt
	if p.hunger > 45 and p.rest > 25 and p.hp < 100:
		p.hp = min(100.0, p.hp + 0.7 * dt)
	p.hp = clampf(p.hp, 0, 100)
	if p.hp <= 0 and not dead:
		_on_death()
		return
	if p.hunger < 55 and p.eat_cd <= 0 and int(stock.get("food", 0)) >= 1 and _near_storage(2.2):
		stock.food -= 1
		p.hunger = min(100.0, p.hunger + 38.0)
		p.eat_cd = 2.5
	if carry_total() > 0 and p.dep_cd <= 0 and _near_storage(1.8):
		for k in p.carry.keys():
			if p.carry[k] > 0:
				var a := deposit(k, p.carry[k])
				p.carry[k] -= a
		p.dep_cd = 0.4
	if move_input.length() > 0.1:
		p.action = null
		p.sleeping = false
		var spd := 3.4 * dt
		var v := move_input.normalized()
		var nx: float = p.px + v.x * spd
		var ny: float = p.py + v.y * spd
		if not is_blocked(int(floor(nx)), int(floor(p.py))):
			p.px = nx
		if not is_blocked(int(floor(p.px)), int(floor(ny))):
			p.py = ny
		p.face = atan2(v.y, v.x)
		return
	if p.action == null:
		var e = _nearest_enemy(p.px, p.py, 1.4)
		if e != null:
			p.action = {"type": "attack", "target": e, "path": [], "repath_cd": 0.0}
	if p.action == null:
		_maybe_sleep(dt)
		return
	var step := 3.4 * dt
	match p.action.type:
		"move":
			if _follow_path(p, p.action.path, step):
				p.action = null
		"gather":
			_do_gather(dt, step)
		"attack":
			_do_attack(dt, step)

func _do_gather(dt: float, step: float) -> void:
	var p = player
	var a = p.action
	if not map.nodes.has(a.cell):
		p.action = null
		return
	var node = map.nodes[a.cell]
	if _dist(p.px, p.py, a.nx + 0.5, a.ny + 0.5) >= 1.4:
		var done := _follow_path(p, a.path, step)
		p.face = atan2(a.ny + 0.5 - p.py, a.nx + 0.5 - p.px)
		if done and not WorldGen.is_terrain_blocked(map.tiles[a.cell]):
			_step_to(p, a.nx + 0.5, a.ny + 0.5, step)
		return
	var info = GameData.NODEINFO[node.kind]
	a.dur = gather_time(node)
	a.t += dt
	if a.t >= a.dur:
		a.t = 0.0
		if carry_total() >= p.carry_cap:
			_flash("Несеш максимум — на склад 📦.")
			p.action = null
			return
		p.carry[info.res] = p.carry.get(info.res, 0) + 1
		node.amount -= 1
		p.skills.gather = min(20.0, p.skills.gather + 0.2)
		if node.amount <= 0:
			map.nodes.erase(a.cell)
			p.action = null

func _do_attack(dt: float, step: float) -> void:
	var p = player
	var a = p.action
	var e = a.target
	if e == null or e.dead or not enemies.has(e):
		var nx = _nearest_enemy(p.px, p.py, 2.5)
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
	var p = player
	if p.rest >= 99:
		p.sleeping = false
		return
	var bed = null
	for b in buildings:
		if b.kind == "bed" and _dist(p.px, p.py, b.x + 0.5, b.y + 0.5) < 1.6:
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
	craft_timer += dt * count
	while craft_timer >= 3.5:
		craft_timer -= 3.5
		if int(stock.get("wood", 0)) >= 2 and stock_total() < storage_cap():
			stock.wood -= 2
			stock.planks = stock.get("planks", 0) + 1

# ---------------- raids ----------------
func _update_raids(dt: float) -> void:
	var r = raid
	if r.active:
		if enemies.is_empty():
			r.active = false
			r.warned = false
			r.next = 78.0 + randf() * 46.0
			r.timer = 0.0
			banner = ""
			_log("✅ Рейд відбито!", "good")
		return
	r.timer += dt
	if not r.warned and r.timer > r.next - 12.0:
		r.warned = true
		banner = "⚠ НАБЛИЖАЄТЬСЯ РЕЙД"
		_log("⚠ Рейдери на підході — укріплюй базу!", "warn")
	if r.timer >= r.next:
		_spawn_wave()

func _spawn_wave() -> void:
	var r = raid
	r.active = true
	r.wave += 1
	# diplomacy: hostile clans raid harder; allied/empire clans never do (spec 0002)
	var pressure := 1.0
	var faction := "невідомі мародери"
	if social != null:
		pressure = Social.raid_pressure(social)
		faction = Social.raid_faction_name(social, r.wave)
	var cnt: int = clampi(int(ceil(float(GameData.raid_wave_size(time.day)) * pressure)), 1, 20)
	var edge := randi() % 4
	var placed := 0
	var guard := 0
	while placed < cnt and guard < 500:
		guard += 1
		var x := 0
		var y := 0
		var o := 1 + randi() % 3
		match edge:
			0:
				x = o
				y = 2 + randi() % (n - 4)
			1:
				x = n - 1 - o
				y = 2 + randi() % (n - 4)
			2:
				x = 2 + randi() % (n - 4)
				y = o
			_:
				x = 2 + randi() % (n - 4)
				y = n - 1 - o
		if WorldGen.is_terrain_blocked(map.tiles[y * n + x]):
			continue
		enemies.append(GameData.make_raider(x + 0.5, y + 0.5, time.day))
		placed += 1
	banner = "⚔ РЕЙД! %d рейдерів — %s" % [cnt, faction]
	_log("⚔ Рейд #%d: %d рейдерів (%s) атакують базу!" % [r.wave, cnt, faction], "bad")

func _update_enemies(dt: float) -> void:
	var p = player
	var center := base_center()
	for k in range(enemies.size() - 1, -1, -1):
		var e = enemies[k]
		e.atk_cd = max(0.0, e.atk_cd - dt)
		e.hit_flash = max(0.0, e.hit_flash - dt)
		var step: float = e.speed * dt
		var dtp := _dist(e.px, e.py, p.px, p.py)
		if dtp < 1.25:
			e.face = atan2(p.py - e.py, p.px - e.px)
			if e.atk_cd <= 0:
				p.hp = clampf(p.hp - e.dmg, 0, 100)
				e.atk_cd = 1.1
				if p.hp <= 0 and not dead:
					_on_death()
			continue
		var st = null
		for b in buildings:
			if b.kind == "storage" and _dist(e.px, e.py, b.x + 0.5, b.y + 0.5) < 1.35:
				st = b
				break
		if st != null:
			if e.atk_cd <= 0:
				_damage_building(st, e.dmg, true)
				e.atk_cd = 1.0
			continue
		var tx := int(p.px) if dtp < 6 else center.x
		var ty := int(p.py) if dtp < 6 else center.y
		e.path_cd -= dt
		if e.path.is_empty() or e.path_cd <= 0 or e.tx != tx or e.ty != ty:
			e.tx = tx
			e.ty = ty
			e.path_cd = 0.9 + randf() * 0.5
			e.path = _terrain_path(int(e.px), int(e.py), tx, ty)
		if not e.path.is_empty():
			var nx: Vector2i = e.path[0]
			var bi := nx.y * n + nx.x
			if bgrid.has(bi) and GameData.BUILDINGS[bgrid[bi].kind].get("blocks", false):
				e.face = atan2(nx.y + 0.5 - e.py, nx.x + 0.5 - e.px)
				if e.atk_cd <= 0:
					_damage_building(bgrid[bi], e.dmg, false)
					e.atk_cd = 1.0
			else:
				if _step_to(e, nx.x + 0.5, nx.y + 0.5, step):
					e.path.remove_at(0)
		else:
			_step_to(e, center.x + 0.5, center.y + 0.5, step)

func _update_turrets(dt: float) -> void:
	for b in buildings:
		if b.kind != "turret":
			continue
		var def = GameData.BUILDINGS.turret
		b.cool = max(0.0, b.cool - dt)
		var e = _nearest_enemy(b.x + 0.5, b.y + 0.5, def.range)
		if e == null:
			continue
		b.aim = atan2(e.py - (b.y + 0.5), e.px - (b.x + 0.5))
		if b.cool <= 0:
			b.cool = 0.5
			_damage_enemy(e, def.dps * 0.5)
			shots.append({"x1": b.x + 0.5, "y1": b.y + 0.5, "x2": e.px, "y2": e.py, "t": 0.12})

func _damage_building(b, amt: float, steal: bool) -> void:
	b.hp -= amt
	if steal and b.kind == "storage":
		var keys := []
		for kk in GameData.RES_ORDER:
			if int(stock.get(kk, 0)) > 0:
				keys.append(kk)
		if not keys.is_empty():
			var kk = keys[randi() % keys.size()]
			var lost: int = min(int(stock[kk]), 1 + randi() % 2)
			stock[kk] -= lost
	if b.hp <= 0:
		_remove_building(b)
		_log("💥 %s зруйновано рейдерами." % GameData.BUILDINGS[b.kind].name, "bad")

func _damage_enemy(e, amt: float) -> void:
	e.hp -= amt
	e.hit_flash = 0.12
	if e.hp <= 0 and not e.dead:
		e.dead = true
		enemies.erase(e)
		deposit("scrap", 2 + randi() % 2)
		if randf() < 0.25:
			deposit("components", 1)
		if randf() < 0.4:
			deposit("food", 1)

func _on_death() -> void:
	dead = true
	banner = ""
	_log("☠ Твій персонаж загинув. Все нажите втрачено.", "bad")

# Permadeath (spec 0002): the pawn is gone entirely — skills, carried loot and items reset.
# You get a fresh un-leveled rookie at the clan base; the settlement (buildings + stock) persists.
func respawn_new_pawn() -> void:
	var sp := base_center()
	var open := _nearest_free(astar, sp)
	if open == Vector2i(-1, -1):
		open = map.spawn
	player = _default_player(open)
	enemies = []
	raid.active = false
	raid.warned = false
	raid.timer = 0.0
	banner = ""
	dead = false
	_log("🧬 Нова пішка прибула в поселення — прокачка з нуля.", "warn")

# ---------------- capsules & invites (spec 0002) ----------------
func _grant_daily_capsule() -> void:
	if capsule.is_empty():
		capsule = _default_capsule()
		return
	if int(time.day) != int(capsule.last_day):
		capsule.last_day = int(time.day)
		if int(capsule.charges) < GameData.CAPSULE_DAILY_CHARGES:
			capsule.charges = GameData.CAPSULE_DAILY_CHARGES
			_log("🚀 Щоденна капсула готова (радіус %d км)." % int(capsule.radius_km), "good")

func capsule_can_reach(lat: float, lon: float) -> Dictionary:
	var km := WorldGen.haversine_km(float(map.lat), float(map.lon), lat, lon)
	if int(capsule.get("charges", 0)) <= 0:
		return {"ok": false, "km": km, "msg": "Капсула вже використана — чекай нового дня."}
	if km > float(capsule.radius_km):
		return {"ok": false, "km": km, "msg": "Задалеко: %d км > ліміт %d км." % [int(km), int(capsule.radius_km)]}
	return {"ok": true, "km": km, "msg": "Готова до запуску (%d км)." % int(km)}

# Validate + consume a charge. Returns a travel intent for the session (main.travel_to).
func try_launch_capsule(lat: float, lon: float, place_name: String) -> Dictionary:
	var chk := capsule_can_reach(lat, lon)
	if not chk.ok:
		return {"ok": false, "msg": chk.msg}
	capsule.charges = int(capsule.charges) - 1
	_log("🚀 Капсула запущена → %s (%d км)." % [place_name, int(chk.km)], "good")
	return {"ok": true, "lat": lat, "lon": lon, "name": place_name, "km": chk.km}

func add_invite(inv: Dictionary) -> void:
	for e in invites:
		if e.id == inv.id:
			return
	invites.append(inv)
	_log("✉ Інвайт від %s (%s) → %s." % [inv.get("inviter", "?"), inv.get("clan", "—"), inv.get("name", "?")])

func accept_invite(id: String) -> Dictionary:
	var inv = null
	for e in invites:
		if e.id == id:
			inv = e
			break
	if inv == null:
		return {"ok": false, "msg": "Інвайт не знайдено."}
	if not bool(inv.get("allow_receive", false)):
		return {"ok": false, "msg": "Інвайт не дозволяє прийом капсули."}
	var res := try_launch_capsule(float(inv.lat), float(inv.lon), str(inv.name))
	if res.ok:
		invites.erase(inv)
	return res

func region_display() -> String:
	# show coordinates at the SAME 4-dp precision that actually seeds the world, so what the player
	# reads is a faithful, shareable handle on this exact world (not a coarser, ambiguous one).
	return "%s (%.4f, %.4f)" % [str(map.get("place_name", "Регіон")), float(map.lat), float(map.lon)]

# The seed IS the coordinate: the terrain/nodes of this region are a pure function of it.
func region_seed() -> int:
	return int(map.get("seed", WorldGen.hash_seed(float(map.lat), float(map.lon))))

# ---------------- logistics ----------------
func dispatch_convoy(hub_index: int, send_res: String, send_amt: int) -> Dictionary:
	if hub_index <= 0 or hub_index >= regions.size():
		return {"ok": false, "msg": "Невірний пункт."}
	var hub = regions[hub_index]
	if hub.get("home", false):
		return {"ok": false, "msg": "Невірний пункт."}
	send_amt = max(1, int(send_amt))
	if int(stock.get(send_res, 0)) < send_amt:
		return {"ok": false, "msg": "Недостатньо ресурсу на складі."}
	if send_res != hub.offer.buys:
		return {"ok": false, "msg": "%s приймає лише %s." % [hub.name, GameData.RES[hub.offer.buys].label]}
	stock[send_res] -= send_amt
	var recv_res = hub.offer.sells
	var recv_amt: int = max(1, int(send_amt / int(hub.offer.rate)))
	var dist := WorldGen.haversine_km(regions[0].lat, regions[0].lon, hub.lat, hub.lon)
	var one_way := clampf(dist * 0.045, 7, 55)
	convoy_seq += 1
	convoys.append({
		"id": convoy_seq, "hub_index": hub_index, "hub_name": hub.name,
		"send_res": send_res, "send_amt": send_amt, "recv_res": recv_res, "recv_amt": recv_amt,
		"phase": "out", "t": 0.0, "dur": one_way, "dist": int(dist), "ambushed": false,
	})
	_log("🚚 Конвой #%d вирушив до %s (%d км)." % [convoy_seq, hub.name, int(dist)], "good")
	return {"ok": true}

func _update_convoys(dt: float) -> void:
	for k in range(convoys.size() - 1, -1, -1):
		var c = convoys[k]
		c.t += dt
		if c.t < c.dur:
			continue
		if c.phase == "out":
			c.phase = "back"
			c.t = 0.0
			_log("🔄 Конвой #%d обміняв вантаж у %s." % [c.id, c.hub_name])
			if randf() < 0.25:
				c.ambushed = true
				var lost: int = max(1, int(round(c.recv_amt * (0.3 + randf() * 0.4))))
				c.recv_amt = max(0, c.recv_amt - lost)
				_log("⚔ Засідка на конвой #%d! −%d." % [c.id, lost], "bad")
		else:
			deposit(c.recv_res, c.recv_amt)
			_log("📦 Конвой #%d повернувся: +%d %s." % [c.id, c.recv_amt, GameData.RES[c.recv_res].icon], "good")
			convoys.remove_at(k)

# ---------------- presentation helpers ----------------
func daylight() -> float:
	# night-overlay alpha from the REAL daylight curve: high latitude gets long winter nights.
	return clampf(0.46 * (1.0 - daylight_level()), 0.0, 0.46)

func phase_name() -> String:
	var f = time.frac
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

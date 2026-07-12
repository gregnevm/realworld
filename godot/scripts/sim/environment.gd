# RealWorld — sim/environment.gd : the ENVIRONMENT domain of the live sim (Batch 8a), extracted from
# the sim.gd monolith.
#
# Seeds the deterministic weather/threat streams for a region (координати — це seed: погода теж адреса
# світу), rerolls weather over game-days, and derives the indoor map from enclosure geometry (spec B4
# "roofing" collapsed to 2D). The cheap per-tile getters (temp_at/light_at/…) stay on sim.gd as its
# public read API; this module owns the state transitions. Static functions over the sim instance `s`:
# no state here, no sim.gd preload (no cycle) — sim.gd delegates.
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

const THREAT_STREAM_SALT := 0x7A1D5EED  # decorrelates the threat stream from the weather stream
const MAX_ROOM_CELLS := 120             # bigger enclosed pockets are courtyards/caves, not rooms
const WEATHER_LABEL := {&"clear": "ясно", &"rain": "дощ", &"snow": "сніг", &"fog": "туман", &"cold_snap": "мороз"}

# Seed the deterministic environment for THIS region: the weather stream reproduces from the region
# seed, and the indoor map is derived from geometry.
static func env_init(s) -> void:
	s.env_rng = RandomNumberGenerator.new()
	s.env_rng.seed = s.region_seed()
	s.threat_rng = RandomNumberGenerator.new()
	s.threat_rng.seed = s.region_seed() ^ THREAT_STREAM_SALT
	s.temp_offset = 0.0
	s.temp_offset_days = 0.0
	s.weather = s.climate.weather(float(s.map.lat), float(s.map.lon), int(s.time.day), float(s.time.frac), s.env_rng)
	s.weather_t = 0.15 + s.env_rng.randf() * 0.2
	recompute_indoor(s)

static func update_environment(s, dday: float) -> void:
	s.weather_t -= dday
	if s.weather_t <= 0.0:
		var prev: StringName = s.weather
		s.weather = s.climate.weather(float(s.map.lat), float(s.map.lon), int(s.time.day), float(s.time.frac), s.env_rng)
		s.weather_t = 0.15 + s.env_rng.randf() * 0.2
		if s.weather != prev:
			s._log("⛅ Погода: %s." % WEATHER_LABEL.get(s.weather, str(s.weather)))
	if s.temp_offset_days > 0.0:
		s.temp_offset_days -= dday
		if s.temp_offset_days <= 0.0:
			s.temp_offset = 0.0
			s.temp_offset_days = 0.0
			s._log("🌡 Температурна аномалія минула.", "good")

# spec B4 ("roofing") collapsed to 2D: a cell is INDOOR when outside air can't reach it from the map
# edge without crossing a wall/door/blocked terrain, and its enclosed pocket is room-sized. One BFS
# floods the outdoor air in from the edges; enclosed leftovers are grouped into components.
static func recompute_indoor(s) -> void:
	s.indoor = {}
	var n: int = s.n
	var open := PackedByteArray()
	open.resize(n * n)
	for i in n * n:
		open[i] = 0 if WorldGen.is_terrain_blocked(s.map.tiles[i]) else 1
	for b in s.buildings:
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
		if open[i] != 1 or outdoor[i] == 1 or s.indoor.has(i):
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
				s.indoor[c] = true
		else:
			for c in comp:
				outdoor[c] = 1

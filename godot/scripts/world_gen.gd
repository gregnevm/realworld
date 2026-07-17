# RealWorld — world_gen.gd : real lat/lon -> deterministic tile map (no scene deps)
#
# "Координати — це seed": the world is a pure function of the coordinate. hash_seed folds the
# canonical coordinate string (canon_coord) into a 32-bit seed; generate_map expands that seed
# through Godot's RandomNumberGenerator (PCG32) into terrain/nodes/spawn. The seed INTEGER is
# byte-identical to the frozen JS reference (util.js hashSeed), but the RNG differs (JS uses
# mulberry32), so the two engines are intentionally SEPARATE shards — the Godot port's PCG32 stream
# is the canonical generator here, pinned by a golden-vector test (run_tests _t_worldgen_golden) so
# it can never silently drift across engine versions. Cross-engine world parity is a deliberate
# non-goal at Phase 0; if it is ever wanted, port mulberry32 into GDScript and re-pin the golden.
extends RefCounted

enum {WATER, GRASS, FOREST, ROCK, ROAD, SOIL, RUIN, SAND, SNOW}
const TERRAIN_COLOR := ["27557e", "5c7d3c", "39562a", "6c7077", "3b4148", "6e5836", "4f4a42", "c7b377", "dde6ee"]
const TERRAIN_NAME := ["вода", "трава", "ліс", "скеля", "дорога", "ґрунт", "руїни", "пісок", "сніг"]

static func is_terrain_blocked(t: int) -> bool:
	return t == WATER or t == ROCK

# "Coordinates ARE the seed": the canonical coordinate string is the SINGLE source of truth for both
# the terrain seed (hash_seed) and the region identity (persistence.region_key). Rounding to 4 dp
# (~11 m) defines the world's resolution; both must derive from this one function so they can never
# drift apart (a region's storage key and its terrain seed must always agree).
static func canon_coord(lat: float, lon: float) -> String:
	# Normalize to a single well-defined point on the globe BEFORE formatting, so the seed/identity
	# is unambiguous everywhere: clamp latitude to the poles, wrap longitude at the antimeridian
	# (+180 → −180), and collapse signed/near-zero to +0 (kills the "-0.0000" equator/meridian seam).
	# All of these are no-ops for ordinary in-range coordinates, so existing seeds are unchanged.
	lat = clampf(lat, -90.0, 90.0)
	lon = wrapf(lon, -180.0, 180.0)
	if absf(lat) < 0.00005:
		lat = 0.0
	if absf(lon) < 0.00005:
		lon = 0.0
	return "%.4f,%.4f" % [lat, lon]

# deterministic 32-bit FNV-1a fold of the canonical coordinate string
static func hash_seed(lat: float, lon: float) -> int:
	var s := canon_coord(lat, lon)
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xffffffff
		h = (h * 16777619) & 0xffffffff
	return h

static func haversine_km(la1: float, lo1: float, la2: float, lo2: float) -> float:
	var d2r := PI / 180.0
	var dla := (la2 - la1) * d2r
	var dlo := (lo2 - lo1) * d2r
	var a := pow(sin(dla / 2.0), 2) + cos(la1 * d2r) * cos(la2 * d2r) * pow(sin(dlo / 2.0), 2)
	return 2.0 * 6371.0 * asin(sqrt(a))

static func _make_noise(rng: RandomNumberGenerator, size: int) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(size * size)
	for i in g.size():
		g[i] = rng.randf()
	return g

static func _g(grid: PackedFloat32Array, size: int, a: int, b: int) -> float:
	var bb := ((b % size) + size) % size
	var aa := ((a % size) + size) % size
	return grid[bb * size + aa]

static func _noise_at(grid: PackedFloat32Array, size: int, x: float, y: float) -> float:
	var xi := int(floor(x))
	var yi := int(floor(y))
	var xf := x - xi
	var yf := y - yi
	var a := _g(grid, size, xi, yi)
	var b := _g(grid, size, xi + 1, yi)
	var c := _g(grid, size, xi, yi + 1)
	var d := _g(grid, size, xi + 1, yi + 1)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	return a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v

static func generate_map(lat: float, lon: float, n: int = 56) -> Dictionary:
	var seed_val := hash_seed(lat, lon)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = seed_val ^ 0x9e3779b9
	var noise := _make_noise(rng, 8)
	var noise2 := _make_noise(rng2, 16)
	var abs_lat := absf(lat)
	var snowy := abs_lat > 57
	var arid := abs_lat > 14 and abs_lat < 33 and _noise_at(noise, 8, 31.7, 12.3) > 0.52
	var urban := float(seed_val % 997) / 997.0

	var tiles := PackedByteArray()
	tiles.resize(n * n)
	for y in n:
		for x in n:
			var i := y * n + x
			var e := _noise_at(noise, 8, float(x) / n * 4.0, float(y) / n * 4.0)
			var f := _noise_at(noise2, 16, float(x) / n * 4.0 * 1.7 + 5.0, float(y) / n * 4.0 * 1.7 + 5.0)
			var t := GRASS
			if e < 0.30:
				t = WATER
			elif e < 0.355:
				t = SNOW if snowy else (SAND if arid else SOIL)
			elif f > 0.66:
				t = FOREST
			elif f < 0.19:
				t = ROCK
			else:
				t = SNOW if (snowy and e > 0.8) else (SAND if arid else GRASS)
			tiles[i] = t

	var nodes := {}
	var clusters := int(2 + urban * 6)
	for k in clusters:
		var cx := 4 + int(rng.randf() * (n - 8))
		var cy := 4 + int(rng.randf() * (n - 8))
		var w := 2 + int(rng.randf() * 3)
		var h := 2 + int(rng.randf() * 3)
		for yy in range(-h, h + 1):
			for xx in range(-w, w + 1):
				if rng.randf() < 0.35:
					continue
				var x := cx + xx
				var y := cy + yy
				if x < 1 or y < 1 or x >= n - 1 or y >= n - 1:
					continue
				var i := y * n + x
				if tiles[i] == WATER:
					continue
				tiles[i] = RUIN

	for y in n:
		for x in n:
			var i := y * n + x
			var t := tiles[i]
			if nodes.has(i):
				continue
			if t == FOREST and rng.randf() < 0.6:
				nodes[i] = {"kind": "tree", "amount": 16 + int(rng.randf() * 12)}
			elif t == ROCK and rng.randf() < 0.45:
				nodes[i] = {"kind": "rock", "amount": 22 + int(rng.randf() * 16)}
			elif t == GRASS and rng.randf() < 0.045:
				nodes[i] = {"kind": "bush", "amount": 5 + int(rng.randf() * 4)}
			elif t == RUIN and rng.randf() < 0.5:
				nodes[i] = {"kind": "scrap", "amount": 8 + int(rng.randf() * 10)}

	var spawn := _pick_spawn(tiles, nodes, n)
	return {
		"n": n, "tiles": tiles, "nodes": nodes, "spawn": spawn, "lat": lat, "lon": lon,
		"seed": seed_val,   # the coordinate-derived world id, carried so the UI/fingerprint need not recompute
		"biome": "бореальний / сніжний" if snowy else ("посушливий" if arid else "помірний"),
		"urban": urban,
	}

static func _pick_spawn(tiles: PackedByteArray, nodes: Dictionary, n: int) -> Vector2i:
	var c := n >> 1
	var best := Vector2i(c, c)
	var best_d := 1 << 30
	for y in range(4, n - 4):
		for x in range(4, n - 4):
			var i := y * n + x
			if tiles[i] != GRASS and tiles[i] != SOIL:
				continue
			var d := absi(x - c) + absi(y - c)
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	for yy in range(-2, 3):
		for xx in range(-2, 3):
			var x := best.x + xx
			var y := best.y + yy
			if x < 0 or y < 0 or x >= n or y >= n:
				continue
			var i := y * n + x
			if tiles[i] == WATER or tiles[i] == ROCK:
				tiles[i] = GRASS
			nodes.erase(i)
	return best

# ---------------- real OSM overlay (pure rasterisation; network lives in main.gd) ----------------
# elements: Array of {type:"way", tags:{}, geometry:[{lat,lon},...]} (Overpass `out geom`)
# bbox: {s,n,w,e}. Mutates map.tiles/nodes in place; re-picks spawn. Deterministic.
static func overlay_osm(map: Dictionary, elements: Array, bbox: Dictionary) -> Dictionary:
	var n: int = map.n
	var tiles: PackedByteArray = map.tiles
	var nodes: Dictionary = map.nodes
	var stats := {"road": 0, "water": 0, "forest": 0, "building": 0}
	for el in elements:
		if el.get("type", "") != "way":
			continue
		var geom: Array = el.get("geometry", [])
		if geom.size() < 2:
			continue
		var kind := _classify(el.get("tags", {}))
		if kind == "":
			continue
		var closed: bool = geom.size() > 3 \
			and absf(float(geom[0].lat) - float(geom[geom.size() - 1].lat)) < 1e-7 \
			and absf(float(geom[0].lon) - float(geom[geom.size() - 1].lon)) < 1e-7
		if kind == "road":
			for k in range(geom.size() - 1):
				_osm_line(tiles, nodes, n, _to_cell(geom[k].lat, geom[k].lon, bbox, n), _to_cell(geom[k + 1].lat, geom[k + 1].lon, bbox, n), ROAD)
			stats.road += 1
		elif kind == "water":
			if closed:
				_osm_fill(tiles, nodes, n, geom, bbox, WATER, "")
			else:
				for k in range(geom.size() - 1):
					_osm_line(tiles, nodes, n, _to_cell(geom[k].lat, geom[k].lon, bbox, n), _to_cell(geom[k + 1].lat, geom[k + 1].lon, bbox, n), WATER)
			stats.water += 1
		elif kind == "forest":
			_osm_fill(tiles, nodes, n, geom, bbox, FOREST, "tree")
			stats.forest += 1
		elif kind == "grass":
			_osm_fill(tiles, nodes, n, geom, bbox, GRASS, "")
		elif kind == "building":
			_osm_fill(tiles, nodes, n, geom, bbox, RUIN, "scrap")
			stats.building += 1
	map.spawn = _pick_spawn(tiles, nodes, n)
	map.source = "osm"
	map.osm_stats = stats
	return stats

static func _classify(tags: Dictionary) -> String:
	if tags.has("building"):
		return "building"
	if tags.has("highway"):
		return "road"
	if tags.has("waterway"):
		return "water"
	if tags.get("natural", "") == "water":
		return "water"
	if tags.get("natural", "") == "wood" or tags.get("landuse", "") == "forest":
		return "forest"
	if tags.get("landuse", "") == "grass":
		return "grass"
	return ""

static func _to_cell(lat: float, lon: float, bbox: Dictionary, n: int) -> Vector2i:
	var x := clampi(int(round((lon - float(bbox.w)) / (float(bbox.e) - float(bbox.w)) * (n - 1))), 0, n - 1)
	var y := clampi(int(round((float(bbox.n) - lat) / (float(bbox.n) - float(bbox.s)) * (n - 1))), 0, n - 1)
	return Vector2i(x, y)

static func _osm_set(tiles: PackedByteArray, nodes: Dictionary, n: int, x: int, y: int, t: int, mk: String) -> void:
	if x < 0 or y < 0 or x >= n or y >= n:
		return
	var i := y * n + x
	tiles[i] = t
	if t == WATER or t == ROAD:
		nodes.erase(i)
	# deterministic node seeding (no RNG) so the overlay is reproducible
	if mk == "tree" and not nodes.has(i) and (i * 2654435761) % 100 < 50:
		nodes[i] = {"kind": "tree", "amount": 16 + (i % 12)}
	elif mk == "scrap" and not nodes.has(i) and (i * 2654435761) % 100 < 40:
		nodes[i] = {"kind": "scrap", "amount": 8 + (i % 10)}

static func _osm_line(tiles: PackedByteArray, nodes: Dictionary, n: int, a: Vector2i, b: Vector2i, t: int) -> void:
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - x0)
	var dy := -absi(b.y - y0)
	var sx := 1 if x0 < b.x else -1
	var sy := 1 if y0 < b.y else -1
	var err := dx + dy
	while true:
		_osm_set(tiles, nodes, n, x0, y0, t, "")
		if x0 == b.x and y0 == b.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

static func _osm_fill(tiles: PackedByteArray, nodes: Dictionary, n: int, geom: Array, bbox: Dictionary, t: int, mk: String) -> void:
	var minx := n
	var miny := n
	var maxx := 0
	var maxy := 0
	var pts := []
	var lons := []
	var lats := []
	for g in geom:
		var c := _to_cell(g.lat, g.lon, bbox, n)
		pts.append(c)
		lons.append(float(g.lon))
		lats.append(float(g.lat))
		minx = mini(minx, c.x)
		miny = mini(miny, c.y)
		maxx = maxi(maxx, c.x)
		maxy = maxi(maxy, c.y)
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var clon: float = float(bbox.w) + (x + 0.5) / n * (float(bbox.e) - float(bbox.w))
			var clat: float = float(bbox.n) - (y + 0.5) / n * (float(bbox.n) - float(bbox.s))
			if _point_in(clon, clat, lons, lats):
				_osm_set(tiles, nodes, n, x, y, t, mk)
	for k in range(pts.size() - 1):
		_osm_line(tiles, nodes, n, pts[k], pts[k + 1], t)

static func _point_in(px: float, py: float, xs: Array, ys: Array) -> bool:
	var inside := false
	var j := xs.size() - 1
	for i in range(xs.size()):
		var xi: float = xs[i]
		var yi: float = ys[i]
		var xj: float = xs[j]
		var yj: float = ys[j]
		if ((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi):
			inside = not inside
		j = i
	return inside

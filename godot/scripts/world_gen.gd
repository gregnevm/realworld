# RealWorld — world_gen.gd : real lat/lon -> deterministic tile map (no scene deps)
extends RefCounted

enum {WATER, GRASS, FOREST, ROCK, ROAD, SOIL, RUIN, SAND, SNOW}
const TERRAIN_COLOR := ["27557e", "5c7d3c", "39562a", "6c7077", "3b4148", "6e5836", "4f4a42", "c7b377", "dde6ee"]
const TERRAIN_NAME := ["вода", "трава", "ліс", "скеля", "дорога", "ґрунт", "руїни", "пісок", "сніг"]

static func is_terrain_blocked(t: int) -> bool:
	return t == WATER or t == ROCK

# deterministic 32-bit FNV-1a fold of the formatted coordinates
static func hash_seed(lat: float, lon: float) -> int:
	var s := "%.4f,%.4f" % [lat, lon]
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

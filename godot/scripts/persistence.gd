# RealWorld — persistence.gd : "seed + diff + save" world store (spec 0002)
#
# A region's terrain is fully reproducible from its SEED (WorldGen.hash_seed(lat,lon)), so for
# procedural regions we persist only the DIFF (player buildings, depleted nodes) + a small SAVE
# (player, stock, time). OSM-overlaid regions also carry a compacted tile SAVE (base64).
#
# Records are chained: each commit links to the previous `head` via `prev` and a content-addressed
# `hash` — an append-only hash chain whose on-chain shape IS `seed + diffs + save`. Today this reads/
# writes user://world.json; a chain backend would commit the identical record.  SEAM: content_hash /
# store_commit / save_to_file  are the three functions a real ledger would replace.
extends RefCounted

const WorldGen = preload("res://scripts/world_gen.gd")
const STORE_VERSION := 2

# ---------------- region keys ----------------
# Region identity == the canonical coordinate string (same source of truth as the terrain seed:
# WorldGen.hash_seed folds this exact string). Delegating here guarantees the persistence key and
# the terrain seed can never diverge — "coordinates ARE the seed".
static func region_key(lat: float, lon: float) -> String:
	return WorldGen.canon_coord(lat, lon)

# ---------------- content addressing (chain seam) ----------------
# Canonical JSON with recursively sorted dict keys so the hash is stable regardless of field order.
static func _canonical(v) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = v.keys()
			keys.sort()
			var parts := PackedStringArray()
			for k in keys:
				parts.append(JSON.stringify(str(k)) + ":" + _canonical(v[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts2 := PackedStringArray()
			for e in v:
				parts2.append(_canonical(e))
			return "[" + ",".join(parts2) + "]"
		TYPE_FLOAT:
			# JSON round-trips coerce every int to float; emit whole-number floats in integer form
			# so an in-memory 24 and an on-disk 24.0 hash identically (verify survives save/load).
			if is_finite(v) and v == floor(v) and absf(v) < 9007199254740992.0:
				return str(int(v))
			return JSON.stringify(v)
		_:
			return JSON.stringify(v)

# Deterministic 64-bit-ish content hash (two mixed 32-bit FNV-1a folds -> 16 hex chars).
# NOT cryptographic — a prototype content address; a chain backend swaps in a real digest.
static func content_hash(v) -> String:
	var s := _canonical(v)
	var h1 := 2166136261
	var h2: int = 2166136261 ^ 0x9e3779b9
	for i in s.length():
		var c := s.unicode_at(i)
		h1 = ((h1 ^ c) * 16777619) & 0xffffffff
		h2 = ((h2 ^ (c + i + 1)) * 16777619) & 0xffffffff
	return "%08x%08x" % [h1, h2]

# The body hash excludes the chain fields (prev/hash) so a record can address its own contents.
static func _body_hash(record: Dictionary) -> String:
	var body: Dictionary = record.duplicate(true)
	body.erase("prev")
	body.erase("hash")
	return content_hash(body)

# ---------------- serialize a live region (diff + save) ----------------
const PLAYER_FIELDS := ["px", "py", "face", "hp", "hunger", "rest", "carry", "carry_cap", "sleeping", "skills", "equipped", "items"]

static func serialize_region(sim) -> Dictionary:
	var m: Dictionary = sim.map
	var lat := float(m.lat)
	var lon := float(m.lon)
	var rec := {
		"key": region_key(lat, lon),
		"lat": lat, "lon": lon, "n": int(m.n),
		"seed": WorldGen.hash_seed(lat, lon),
		"source": str(m.get("source", "proc")),
		"place_name": str(m.get("place_name", "Регіон")),
		"day": int(sim.time.day), "frac": float(sim.time.frac),
		"player": _pick(sim.player, PLAYER_FIELDS),
		# stock keys follow the sim's vocabulary (spec 0008: live ids vs catalogue ids) — persist the
		# flag with them, else a cross-flag load reads the wrong keys and resources silently vanish.
		"use_catalog": bool(sim.use_catalog),
		"stock": (sim.stock as Dictionary).duplicate(true),
		"buildings": [],
		"nodes": {},
	}
	for b in sim.buildings:
		rec.buildings.append({"kind": b.kind, "x": int(b.x), "y": int(b.y), "hp": float(b.hp)})
	for cell in m.nodes:
		var nd: Dictionary = m.nodes[cell]
		rec.nodes[str(cell)] = {"kind": nd.kind, "amount": int(nd.amount)}
	# OSM regions: terrain was externally overlaid and is not reproducible from seed -> save it.
	if rec.source == "osm":
		rec["tiles_b64"] = Marshalls.raw_to_base64(m.tiles)
	return rec

static func _pick(src: Dictionary, fields: Array) -> Dictionary:
	var out := {}
	for f in fields:
		if src.has(f):
			var val: Variant = src[f]
			out[f] = (val.duplicate(true) if (val is Dictionary or val is Array) else val)
	return out

# ---------------- authoritative world-state hash (spec 0006 §4) ----------------
# The full-world extension of content_hash: serialize_region (the save fields) PLUS the live
# dynamics a save never carries — combat actors, raid/patrol cycle timers, weather state and the
# rng cursors. Two independent instances fed the same seed and the same command stream MUST agree
# on this hash after every tick; run_determinism_tests.gd enforces it as the Phase-1 acceptance
# backbone and permanent anti-desync tripwire (spec 0006 §10). Deliberately excluded: feedback
# channels (messages/banner/flash — view, not sim), the enemies' hit_flash (render juice), the
# move_input channel (an input, not state) and derived caches (bgrid/astar/indoor — recomputed).
const ENEMY_HASH_FIELDS := ["px", "py", "face", "hp", "maxhp", "dmg", "speed", "atk_cd", "path_cd", "tx", "ty", "dead", "kind"]
const SHOT_HASH_FIELDS := ["x1", "y1", "x2", "y2", "t"]


static func world_hash(sim) -> String:
	var enemies: Array = []
	for e in sim.enemies:
		var slice := _pick(e, ENEMY_HASH_FIELDS)
		# A* waypoints are Vector2i, which _canonical cannot address — flatten to [x, y] pairs.
		var path: Array = []
		for p in e.path:
			path.append([int(p.x), int(p.y)])
		slice["path"] = path
		enemies.append(slice)
	var shots: Array = []
	for sh in sim.shots:
		shots.append(_pick(sh, SHOT_HASH_FIELDS))
	var dyn := {
		"dead": bool(sim.dead),
		"craft_timer": float(sim.craft_timer),
		"weather": String(sim.weather),
		"weather_t": float(sim.weather_t),
		"temp_offset": float(sim.temp_offset),
		"temp_offset_days": float(sim.temp_offset_days),
		"raid": (sim.raid as Dictionary).duplicate(true),
		"patrol": (sim.patrol as Dictionary).duplicate(true),
		"research_unlocked": (sim.research_unlocked as Dictionary).duplicate(true),
		"env_rng_state": int(sim.env_rng.state),
		"threat_rng_state": int(sim.threat_rng.state),
		"enemies": enemies,
		"shots": shots,
	}
	return content_hash({"region": serialize_region(sim), "dyn": dyn})

static func decode_tiles(b64: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(b64)

# ---------------- world store (append-only hash chain) ----------------
static func store_new() -> Dictionary:
	return {"version": STORE_VERSION, "head": "", "regions": {}}

static func store_has(store: Dictionary, key: String) -> bool:
	return (store.regions as Dictionary).has(key)

static func store_get(store: Dictionary, key: String):
	return (store.regions as Dictionary).get(key, null)

# Commit a region record: link to the current head, content-address it, advance the head.
static func store_commit(store: Dictionary, record: Dictionary) -> String:
	var bh := _body_hash(record)
	record["prev"] = str(store.get("head", ""))
	record["hash"] = content_hash(record.prev + ":" + bh)
	store.regions[str(record.key)] = record
	store["head"] = record.hash
	return record.hash

# A record is self-consistent when its stored hash matches prev + its recomputed body hash.
static func verify_record(record: Dictionary) -> bool:
	if not record.has("hash") or not record.has("prev"):
		return false
	return record.hash == content_hash(str(record.prev) + ":" + _body_hash(record))

static func verify_store(store: Dictionary) -> bool:
	for key in store.regions:
		if not verify_record(store.regions[key]):
			return false
	return true

# ---------------- file backend (chain seam) ----------------
static func save_to_file(store: Dictionary, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(store))
	f.close()
	return true

static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return store_new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return store_new()
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary and parsed.has("regions"):
		return parsed
	return store_new()

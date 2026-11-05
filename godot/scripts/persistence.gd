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
const MainCapsule = preload("res://scripts/sim/capsule.gd")
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
const PLAYER_FIELDS := ["px", "py", "face", "hp", "hunger", "rest", "carry", "carry_cap", "sleeping", "skills", "equipped", "items", "born", "inv", "hand"]

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
		# located health (sim/hero_health.gd): the tracker IS the body, so it saves with the pawn;
		# records predating the field migrate from the player.hp float on load.
		"health": sim.health_dict(),
		# stock keys follow the sim's vocabulary (spec 0008: live ids vs catalogue ids) — persist the
		# flag with them, else a cross-flag load reads the wrong keys and resources silently vanish.
		"use_catalog": bool(sim.use_catalog),
		"stock": (sim.stock as Dictionary).duplicate(true),
		"buildings": [],
		"nodes": {},
	}
	var capsule_on: bool = sim.get("use_main_capsule") == true
	for b in sim.buildings:
		if capsule_on and String(b.kind) == MainCapsule.KIND:
			continue   # spec 0010: капсула живе у main_capsule.tile (єдина правда про позицію), не в buildings
		var brec := {"kind": b.kind, "x": int(b.x), "y": int(b.y), "hp": float(b.hp)}
		# building-module state: a generator's tank, a battery's charge (Batch 8c) and a grow zone's
		# cycle (farming) are save-state and world_hash-state. Only defs with those mechanics ever
		# carry the keys, so older saves are unchanged.
		for f in ["fuel", "charge", "growth"]:
			if b.has(f):
				brec[f] = float(b[f])
		for f in ["harvests", "ammo"]:
			if b.has(f):
				brec[f] = int(b[f])
		if b.has("crop"):
			brec["crop"] = str(b.crop)   # the zone's selected crop (farming v2)
		rec.buildings.append(brec)
	for cell in m.nodes:
		var nd: Dictionary = m.nodes[cell]
		rec.nodes[str(cell)] = {"kind": nd.kind, "amount": int(nd.amount)}
	# OSM regions: terrain was externally overlaid and is not reproducible from seed -> save it.
	if rec.source == "osm":
		rec["tiles_b64"] = Marshalls.raw_to_base64(m.tiles)
	# spec 0009: the personal-inventory world carries its flag + death bags (only then — OFF records unchanged)
	if sim.get("use_inventory") == true:
		rec["use_inventory"] = true
		rec["bags"] = (sim.bags as Array).duplicate(true)
	# spec 0010: Основна капсула — прапор + запис (версія запису всередині) лише при ON; OFF-записи без жодного нового ключа
	if capsule_on:
		rec["use_main_capsule"] = true
		rec["main_capsule"] = MainCapsule.to_record(sim)
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
	return content_hash({"region": serialize_region(sim), "dyn": serialize_runtime(sim)})


# ---------------- runtime half (spec 0006 plan §5) ----------------
# serialize_region is the SAVE format: everything a player's world needs to come back tomorrow.
# It deliberately does NOT carry the live dynamics — load_region resets threats and re-seeds the
# environment, which is right for loading a save and WRONG for a rejoining client, who must land
# byte-identical to the authoritative server or desync on the next raid roll. This is that missing
# half: the volatile state world_hash covers. It is a NET/runtime record, not a save-format change
# — the save keeps its shape and its migration story.
static func serialize_runtime(sim) -> Dictionary:
	var enemies: Array = []
	for e in sim.enemies:
		var slice := _pick(e, ENEMY_HASH_FIELDS)
		# A* waypoints are Vector2i, which neither _canonical nor JSON can address — flatten.
		var path: Array = []
		for p in e.path:
			path.append([int(p.x), int(p.y)])
		slice["path"] = path
		enemies.append(slice)
	var shots: Array = []
	for sh in sim.shots:
		shots.append(_pick(sh, SHOT_HASH_FIELDS))
	return {
		"dead": bool(sim.dead),
		"craft_timer": float(sim.craft_timer),
		"weather": String(sim.weather),
		"weather_t": float(sim.weather_t),
		"temp_offset": float(sim.temp_offset),
		"temp_offset_days": float(sim.temp_offset_days),
		"raid": (sim.raid as Dictionary).duplicate(true),
		"patrol": (sim.patrol as Dictionary).duplicate(true),
		"research_unlocked": (sim.research_unlocked as Dictionary).duplicate(true),
		# STRINGS, not numbers: an rng cursor is a full 64-bit integer and JSON numbers are
		# doubles — anything past 2^53 silently rounds (2564435455463813531 arrived as
		# ...632), which resumes every stochastic stream at the wrong cursor. Strings
		# round-trip exactly, and both sides hash the same string.
		"env_rng_state": str(sim.env_rng.state),
		"threat_rng_state": str(sim.threat_rng.state),
		"director_rng_state": str(sim.director_rng.state),
		"enemies": enemies,
		"shots": shots,
		# convoys are authoritative state that PAYS OUT later (goods return on arrival), so two
		# instances that disagree on them diverge at that moment — they belong in the hash and in
		# any resume payload, even though the save format has never carried them.
		"convoys": (sim.convoys as Array).duplicate(true),
		"convoy_seq": int(sim.convoy_seq),
		# The pawn's LIVE half. load_region deliberately drops `action` (a save resumes with the
		# pawn idle — correct for a save, fatal for a rejoin: the server's pawn is mid-walk and the
		# joiner's stands still, so their positions diverge on the very next tick) and PLAYER_FIELDS
		# omits the cooldowns for the same reason.
		"player_live": {
			"action": _pack_action(sim),
			"eat_cd": float(sim.player.get("eat_cd", 0.0)),
			"atk_cd": float(sim.player.get("atk_cd", 0.0)),
			"dep_cd": float(sim.player.get("dep_cd", 0.0)),
		},
	}


# An action carries an A* path (Vector2i) and, when attacking, a LIVE enemy reference — neither
# survives a wire. The path flattens; the target becomes its INDEX into the enemies array, which is
# a stable id precisely because that array travels in the same record, in the same order.
static func _pack_action(sim) -> Variant:
	var a: Variant = sim.player.get("action")
	if not (a is Dictionary):
		return null
	var out: Dictionary = (a as Dictionary).duplicate(true)
	var path: Array = []
	for p in (out.get("path", []) as Array):
		path.append([int(p.x), int(p.y)])
	out["path"] = path
	if out.has("target"):
		out["target_idx"] = (sim.enemies as Array).find(out.target)
		out.erase("target")
	return out


static func _unpack_action(sim, packed: Variant) -> Variant:
	if not (packed is Dictionary):
		return null
	var out: Dictionary = (packed as Dictionary).duplicate(true)
	var path: Array = []
	for p in (out.get("path", []) as Array):
		path.append(Vector2i(int(p[0]), int(p[1])))
	out["path"] = path
	for f in ["cell", "nx", "ny"]:
		if out.has(f):
			out[f] = int(out[f])
	if out.has("target_idx"):
		var i := int(out.target_idx)
		out.erase("target_idx")
		if i >= 0 and i < (sim.enemies as Array).size():
			out["target"] = sim.enemies[i]
		else:
			return null                    # the target died while we were away: the order is void
	return out


# Inverse of serialize_runtime. Applied AFTER load_region (which resets exactly these fields).
static func apply_runtime(sim, rec: Dictionary) -> void:
	sim.dead = bool(rec.get("dead", false))
	sim.craft_timer = float(rec.get("craft_timer", 0.0))
	sim.weather = StringName(str(rec.get("weather", "clear")))
	sim.weather_t = float(rec.get("weather_t", 0.0))
	sim.temp_offset = float(rec.get("temp_offset", 0.0))
	sim.temp_offset_days = float(rec.get("temp_offset_days", 0.0))
	sim.raid = _num_dict(rec.get("raid", {}), ["wave"])
	sim.patrol = _num_dict(rec.get("patrol", {}), ["wave"])
	sim.research_unlocked = (rec.get("research_unlocked", {}) as Dictionary).duplicate(true)
	# The seed stays derived from the region (env_init already set it); only the CURSOR moves, and
	# it is the cursor that decides the next raid roll. Restoring the seed without the state would
	# silently rewind every stochastic stream to tick 0.
	sim.env_rng.state = _rng_state(rec.get("env_rng_state"), sim.env_rng.state)
	sim.threat_rng.state = _rng_state(rec.get("threat_rng_state"), sim.threat_rng.state)
	sim.director_rng.state = _rng_state(rec.get("director_rng_state"), sim.director_rng.state)
	sim.enemies = []
	for e in (rec.get("enemies", []) as Array):
		var live: Dictionary = (e as Dictionary).duplicate(true)
		var path: Array = []
		for p in (live.get("path", []) as Array):
			path.append(Vector2i(int(p[0]), int(p[1])))
		live["path"] = path
		for f in ["tx", "ty"]:
			live[f] = int(live.get(f, -1))
		live["dead"] = bool(live.get("dead", false))
		live["hit_flash"] = 0.0            # render-only juice; never replicated
		sim.enemies.append(live)
	sim.shots = (rec.get("shots", []) as Array).duplicate(true)
	sim.convoys = (rec.get("convoys", []) as Array).duplicate(true)
	for c in sim.convoys:
		for f in ["id", "hub_index", "send_amt", "recv_amt", "dist"]:
			if c.has(f):
				c[f] = int(c[f])
	sim.convoy_seq = int(rec.get("convoy_seq", 0))
	# the pawn's live half — AFTER enemies, because an attack order resolves its target by index
	var live: Dictionary = rec.get("player_live", {})
	sim.player["action"] = _unpack_action(sim, live.get("action"))
	for f in ["eat_cd", "atk_cd", "dep_cd"]:
		sim.player[f] = float(live.get(f, 0.0))


# A cursor written as a decimal string (see serialize_runtime); tolerate a raw int from an
# in-process payload that never touched the wire.
static func _rng_state(v: Variant, fallback: int) -> int:
	if v is String:
		return (v as String).to_int()
	if v is int:
		return v
	return fallback


# JSON turns every int into a float; these counters are compared and printed as ints.
static func _num_dict(src: Variant, int_fields: Array) -> Dictionary:
	var out: Dictionary = (src as Dictionary).duplicate(true)
	for f in int_fields:
		if out.has(f):
			out[f] = int(out[f])
	return out


# What a rejoining client needs to land EXACTLY where the authoritative server is: the save half
# (terrain, base, stock, pawn, clock) plus the runtime half (threats, weather, rng cursors).
static func resume_payload(sim) -> Dictionary:
	return {"region": serialize_region(sim), "runtime": serialize_runtime(sim)}


# false == відхилено: load_region не змінив світ (sim.load_error каже чому), тож runtime-половина НЕ накладається на
# порожній sim (спільний шлях Session.restore_game і net-rejoin; REQ-0010-60/83 — жодного напівживого світу).
static func restore(sim, payload: Dictionary) -> bool:
	sim.load_region(payload.region)
	var refused: Variant = sim.get("load_error")
	if refused != null and refused != &"":
		return false
	apply_runtime(sim, payload.runtime)
	return true

# Мапа з запису регіону (зворотне до map-половини serialize_region): рельєф — з seed координат (OSM — з blob тайлів, якщо
# цілий), ноди — з diff. {map, osm_lost}: osm_lost — запис казав «osm», але тайлів нема/пошкоджені (викликач каже гравцю).
static func map_from_record(data: Dictionary) -> Dictionary:
	var nn := int(data.n)
	var m := WorldGen.generate_map(float(data.lat), float(data.lon), nn)
	m["place_name"] = str(data.get("place_name", "Регіон"))
	# OSM terrain is the ONE thing not reproducible from the coordinate, so it is persisted as a tile blob.
	# Restore it only if intact (right length); never silently fall back to a DIFFERENT world.
	var osm_lost := false
	if str(data.get("source", "")) == "osm":
		var decoded := Marshalls.base64_to_raw(str(data.get("tiles_b64", "")))
		if decoded.size() == nn * nn:
			m.tiles = decoded
			m["source"] = "osm"
			# spawn was picked against procedural tiles; re-pick against the real OSM terrain
			m.spawn = WorldGen._pick_spawn(m.tiles, m.nodes, nn)
		else:
			osm_lost = true
	var nodes := {}
	for k in data.nodes:
		var nd: Dictionary = data.nodes[k]
		nodes[int(str(k))] = {"kind": str(nd.kind), "amount": int(nd.amount)}
	m.nodes = nodes
	return {"map": m, "osm_lost": osm_lost}

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

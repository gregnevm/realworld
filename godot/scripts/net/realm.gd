# RealWorld — net/realm.gd : who is where, and who can see whom (spec 0013 §3.5).
#
# The server-side presence registry of the RealGPS layer. It owns exactly three things:
#   1. player records  — id, name, last accepted fix, grid cell;
#   2. a cell index    — cell key -> sorted player ids (the cheap candidate lookup);
#   3. per-observer memory of whom they were last told about (enter/leave events).
# It does NOT own transport, wire format or the sim (those are RealmServer / RealmProtocol / Sim),
# and it never reads a clock: `now_ms` is always an argument (spec 0012 REQ-10). Geometry comes from
# an injected `grid` (GeoGrid) and fix plausibility from GpsGuard, so each can change on its own.
#
# Determinism: every list this class returns is sorted by player id; ties never depend on join order
# or dictionary iteration (run_realm_tests pins this by joining the same players in two orders).
extends RefCounted

const Geo = preload("res://scripts/net/geo.gd")
const GeoGrid = preload("res://scripts/net/geo_grid.gd")
const GpsGuard = preload("res://scripts/net/gps_guard.gd")

const OK := &"ok"
const R_ID := &"bad_id"
const R_NAME := &"bad_name"
const R_DUPLICATE := &"duplicate"
const R_UNKNOWN := &"unknown_player"
const R_FULL := &"realm_full"

const MAX_NAME_LEN := 24
const DEFAULT_AOI_M := 1200.0     # proposed: a bit over one cell — you see the neighbours you could walk to
const DEFAULT_MAX_PLAYERS := 2000

var grid: Variant = null                      # GeoGrid-like: cell_of / key / cells_within / region_of / key_of
var aoi_m: float = DEFAULT_AOI_M
var max_players: int = DEFAULT_MAX_PLAYERS
var guard_params: Dictionary = GpsGuard.DEFAULT_PARAMS.duplicate()

var _players: Dictionary = {}    # int id -> {id, name, lat, lon, t_ms, seen_ms, cell}
var _cells: Dictionary = {}      # String cell key -> Array[int] (sorted)
var _known: Dictionary = {}      # int observer id -> {int other id: true} announced so far


func _init(p_grid: Variant = null, p_aoi_m: float = DEFAULT_AOI_M) -> void:
	grid = p_grid if p_grid != null else GeoGrid.new()
	aoi_m = maxf(p_aoi_m, 1.0)


# ---------------- membership ----------------
func join(id: int, p_name: String, lat: float, lon: float, now_ms: int) -> Dictionary:
	if id < 0:
		return _refuse(R_ID)
	var nm := p_name.strip_edges()
	if nm == "" or nm.length() > MAX_NAME_LEN:
		return _refuse(R_NAME)
	if _players.has(id):
		return _refuse(R_DUPLICATE)
	if _players.size() >= max_players:
		return _refuse(R_FULL)
	var fix := GpsGuard.check({}, {"lat": lat, "lon": lon, "t_ms": now_ms}, guard_params)
	if not bool(fix.ok):
		return _refuse(fix.reason)
	var cell: Vector2i = grid.cell_of(lat, lon)
	_players[id] = {"id": id, "name": nm, "lat": lat, "lon": lon, "t_ms": now_ms, "seen_ms": now_ms, "cell": cell}
	_index_add(GeoGrid.key(cell), id)
	_known[id] = {}
	return {"ok": true, "reason": OK, "cell": GeoGrid.key(cell), "region": grid.region_of(cell)}


func leave(id: int) -> bool:
	if not _players.has(id):
		return false
	_index_remove(GeoGrid.key(_players[id].cell), id)
	_players.erase(id)
	_known.erase(id)
	return true


# A new GPS fix for a joined player. A refused fix (teleport, time going back, junk) changes nothing.
func move(id: int, lat: float, lon: float, now_ms: int) -> Dictionary:
	if not _players.has(id):
		return _refuse(R_UNKNOWN)
	var p: Dictionary = _players[id]
	var fix := GpsGuard.check({"lat": p.lat, "lon": p.lon, "t_ms": p.t_ms}, {"lat": lat, "lon": lon, "t_ms": now_ms}, guard_params)
	if not bool(fix.ok):
		return _refuse(fix.reason)
	var old_cell: Vector2i = p.cell
	var new_cell: Vector2i = grid.cell_of(lat, lon)
	if new_cell != old_cell:
		_index_remove(GeoGrid.key(old_cell), id)
		_index_add(GeoGrid.key(new_cell), id)
	p.lat = lat
	p.lon = lon
	p.t_ms = now_ms
	p.seen_ms = now_ms
	p.cell = new_cell
	return {"ok": true, "reason": OK, "cell": GeoGrid.key(new_cell), "changed_cell": new_cell != old_cell}


# Liveness without a fix (heartbeat) — keeps the record out of expire() but does not move anyone.
func touch(id: int, now_ms: int) -> bool:
	if not _players.has(id):
		return false
	_players[id].seen_ms = maxi(int(_players[id].seen_ms), now_ms)
	return true


# Drop everyone not heard from for more than ttl_ms. Returns the removed ids, ascending.
func expire(now_ms: int, ttl_ms: int) -> Array:
	var gone: Array = []
	for id in _players:
		if now_ms - int(_players[id].seen_ms) > ttl_ms:
			gone.append(int(id))
	gone.sort()
	for id in gone:
		leave(int(id))
	return gone


# ---------------- queries ----------------
func has_player(id: int) -> bool:
	return _players.has(id)


func count() -> int:
	return _players.size()


func player(id: int) -> Dictionary:
	return (_players[id] as Dictionary).duplicate(true) if _players.has(id) else {}


func population(cell_key: String) -> int:
	return (_cells[cell_key] as Array).size() if _cells.has(cell_key) else 0


func occupied_cells() -> Array:
	var keys: Array = _cells.keys()
	keys.sort()
	return keys


# Everyone `id` can currently see: within aoi_m by EXACT distance, self excluded, ascending ids.
func interest(id: int) -> Array:
	if not _players.has(id):
		return []
	var me: Dictionary = _players[id]
	var out: Array = []
	var cells: Array = grid.cells_within(float(me.lat), float(me.lon), aoi_m)
	for cell in cells:
		var k := GeoGrid.key(cell)
		if not _cells.has(k):
			continue
		for oid in _cells[k]:
			if int(oid) == id:
				continue
			var o: Dictionary = _players[oid]
			if Geo.distance_m(float(me.lat), float(me.lon), float(o.lat), float(o.lon)) <= aoi_m:
				out.append(int(oid))
	out.sort()
	return out


# Players standing in the SAME cell — they share one world (the region seeded by the cell anchor).
func cohabitants(id: int) -> Array:
	if not _players.has(id):
		return []
	var out: Array = []
	for oid in _cells.get(GeoGrid.key(_players[id].cell), []):
		if int(oid) != id:
			out.append(int(oid))
	return out


# Value-data presence slice for one observer — JSON-safe, integer-rounded so equal worlds give equal
# slices (delta-codable by net/snapshot.gd without float noise). Keys of "near" are id strings.
func presence_view(id: int) -> Dictionary:
	if not _players.has(id):
		return {}
	var me: Dictionary = _players[id]
	var near := {}
	var same := {}
	for oid in cohabitants(id):
		same[int(oid)] = true
	for oid in interest(id):
		var o: Dictionary = _players[oid]
		var brg := Geo.bearing_deg(float(me.lat), float(me.lon), float(o.lat), float(o.lon))
		near[str(oid)] = {
			"name": str(o.name),
			"dist_m": int(roundf(Geo.distance_m(float(me.lat), float(me.lon), float(o.lat), float(o.lon)))),
			"brg": int(roundf(brg)) % 360,
			"dir": Geo.cardinal8(brg),
			"same_region": same.has(int(oid)),
		}
	var cell: Vector2i = me.cell
	return {
		"me": {"id": id, "name": str(me.name)},
		"region": GeoGrid.key(cell),
		"region_pop": population(GeoGrid.key(cell)),
		"near": near,
	}


# Enter/leave events for one observer since the last call (the first call announces everyone nearby).
func poll_changes(id: int) -> Dictionary:
	if not _players.has(id):
		return {"enter": [], "leave": []}
	var now_set := {}
	for oid in interest(id):
		now_set[int(oid)] = true
	var known: Dictionary = _known.get(id, {})
	var enter: Array = []
	var gone: Array = []
	for oid in now_set:
		if not known.has(oid):
			enter.append(int(oid))
	for oid in known:
		if not now_set.has(oid):
			gone.append(int(oid))
	enter.sort()
	gone.sort()
	_known[id] = now_set
	return {"enter": enter, "leave": gone}


# ---------------- internals ----------------
func _index_add(cell_key: String, id: int) -> void:
	var arr: Array = _cells.get(cell_key, [])
	arr.append(id)
	arr.sort()
	_cells[cell_key] = arr


func _index_remove(cell_key: String, id: int) -> void:
	if not _cells.has(cell_key):
		return
	var arr: Array = _cells[cell_key]
	arr.erase(id)
	if arr.is_empty():
		_cells.erase(cell_key)


static func _refuse(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason}

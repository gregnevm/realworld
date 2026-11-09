# RealWorld — tests/run_realm_tests.gd : the RealGPS layer suite (spec 0013).
#
# Geometry, grid, GPS plausibility, shard routing, presence registry — all pure and clock-free.
# Run: godot --headless --path godot -s res://tests/run_realm_tests.gd
extends "res://tests/harness.gd"

const Geo = preload("res://scripts/net/geo.gd")
const GeoGrid = preload("res://scripts/net/geo_grid.gd")
const GpsGuard = preload("res://scripts/net/gps_guard.gd")
const ShardRouter = preload("res://scripts/net/shard_router.gd")
const Realm = preload("res://scripts/net/realm.gd")
const Snapshot = preload("res://scripts/net/snapshot.gd")
const Persistence = preload("res://scripts/persistence.gd")

const KYIV := Vector2(50.4501, 30.5234)


func _init() -> void:
	print("== RealWorld RealGPS suite (spec 0013) ==")
	_t_geo()
	_t_grid()
	_t_grid_extremes()
	_t_guard()
	_t_router()
	_t_realm_membership()
	_t_realm_interest()
	_t_realm_determinism()
	_t_realm_changes_and_delta()
	_t_realm_expiry()
	finish()


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


# ---------------- geo ----------------
func _t_geo() -> void:
	ok(_near(Geo.distance_m(0.0, 0.0, 0.0, 1.0), Geo.M_PER_DEG, 400.0), "one degree of longitude on the equator ~111.2 km")
	ok(Geo.distance_m(KYIV.x, KYIV.y, KYIV.x, KYIV.y) == 0.0, "distance to self is exactly 0")
	var d1 := Geo.distance_m(50.0, 30.0, 51.0, 31.0)
	var d2 := Geo.distance_m(51.0, 31.0, 50.0, 30.0)
	ok(_near(d1, d2, 0.001), "distance is symmetric")
	ok(_near(Geo.bearing_deg(0.0, 0.0, 1.0, 0.0), 0.0, 0.01), "bearing due north = 0")
	ok(_near(Geo.bearing_deg(0.0, 0.0, 0.0, 1.0), 90.0, 0.01), "bearing due east = 90")
	ok(_near(Geo.bearing_deg(0.0, 0.0, -1.0, 0.0), 180.0, 0.01), "bearing due south = 180")
	ok(_near(Geo.bearing_deg(0.0, 0.0, 0.0, -1.0), 270.0, 0.01), "bearing due west = 270")
	ok(Geo.cardinal8(0.0) == "Пн" and Geo.cardinal8(90.0) == "Сх" and Geo.cardinal8(359.0) == "Пн" and Geo.cardinal8(225.0) == "Пд-Зх", "8-wind labels use the game's Ukrainian compass")
	var dest := Geo.destination(KYIV.x, KYIV.y, 45.0, 500.0)
	ok(_near(Geo.distance_m(KYIV.x, KYIV.y, float(dest.lat), float(dest.lon)), 500.0, 0.5), "destination lands exactly the asked distance away")
	ok(_near(Geo.bearing_deg(KYIV.x, KYIV.y, float(dest.lat), float(dest.lon)), 45.0, 0.1), "destination lies on the asked bearing")
	var wrapped := Geo.destination(0.0, 179.999, 90.0, 5000.0)
	ok(float(wrapped.lon) < 0.0 and float(wrapped.lon) > -180.0, "destination wraps across the antimeridian")
	ok(Geo.is_valid(0.0, 0.0) and Geo.is_valid(90.0, -180.0), "legal extremes are valid")
	ok(not Geo.is_valid(NAN, 0.0) and not Geo.is_valid(0.0, INF) and not Geo.is_valid(90.1, 0.0) and not Geo.is_valid(0.0, 180.5), "NaN/inf/out-of-range fixes are invalid")


# ---------------- grid ----------------
func _t_grid() -> void:
	var g := GeoGrid.new()
	var c := g.cell_of(KYIV.x, KYIV.y)
	ok(g.is_valid_cell(c), "a real coordinate maps to a valid cell")
	ok(g.cell_of(KYIV.x, KYIV.y) == c, "cell_of is a pure function (same input, same cell)")
	var ctr := g.center(c)
	ok(g.cell_of(float(ctr.lat), float(ctr.lon)) == c, "center(cell) lies inside that cell")
	var other := g.cell_of(KYIV.x + 0.02, KYIV.y)   # ~2.2 km north
	ok(other != c, "a point ~2 km away is a different cell")
	var step := Geo.distance_m(float(ctr.lat), 0.0, float(g.center(Vector2i(c.x + 1, c.y)).lat), 0.0)   # latitude step only
	ok(_near(step, g.cell_m, 60.0), "adjacent rows are ~cell_m apart (%.0f m)" % step)
	var k := GeoGrid.key(c)
	ok(GeoGrid.parse_key(k) == c, "key round-trips through parse_key")
	ok(GeoGrid.parse_key("12") == null and GeoGrid.parse_key("a:b") == null and GeoGrid.parse_key("1:2:3") == null, "malformed keys parse to null")
	var reg := g.region_of(c)
	ok(str(reg.key) == k and int(reg.seed) > 0 and str(reg.canon) != "", "region_of carries key, canonical coordinate and the terrain seed")
	var reg2 := GeoGrid.new().region_of(c)
	ok(int(reg2.seed) == int(reg.seed), "two grids with the same cell_m agree on the region seed (client == server)")
	# cells_within: candidate set is a SUPERSET of every cell holding a point inside the disc
	var covered := true
	for brg in range(0, 360, 15):
		for dist in [0.0, 300.0, 900.0, 1190.0]:
			var p := Geo.destination(KYIV.x, KYIV.y, float(brg), float(dist))
			if not (g.cells_within(KYIV.x, KYIV.y, 1200.0) as Array).has(g.cell_of(float(p.lat), float(p.lon))):
				covered = false
	ok(covered, "cells_within(r) covers every point within r on 24 bearings x 4 distances")
	var cells := g.cells_within(KYIV.x, KYIV.y, 1200.0)
	var sorted_ok := true
	for i in range(1, cells.size()):
		if not GeoGrid.compare(cells[i - 1], cells[i]):
			sorted_ok = false
	ok(sorted_ok and cells.size() >= 4 and cells.size() <= 25, "cells_within is strictly sorted and small (%d cells)" % cells.size())


func _t_grid_extremes() -> void:
	var g := GeoGrid.new()
	# antimeridian: two players 100 m apart on either side of lon=180 must see each other's cells
	var east := g.cell_of(10.0, 179.9995)
	var west := g.cell_of(10.0, -179.9995)
	ok((g.cells_within(10.0, 179.9995, 500.0) as Array).has(west), "cells_within wraps across the antimeridian (east -> west)")
	ok((g.cells_within(10.0, -179.9995, 500.0) as Array).has(east), "cells_within wraps across the antimeridian (west -> east)")
	ok(g.cell_of(10.0, 180.0) == g.cell_of(10.0, -180.0), "lon +180 and -180 are the same cell")
	# poles: the top row is a single wide cell, never a divide-by-zero
	var north := g.cell_of(90.0, 0.0)
	ok(g.is_valid_cell(north) and g.cols_in_row(north.x) >= 1, "the pole maps to a valid cell")
	ok(g.cell_of(90.0, 10.0).x == g.cell_of(90.0, -170.0).x, "pole latitude rows agree for every longitude")
	var near_pole := g.cells_within(89.995, 0.0, 800.0)
	ok(near_pole.size() >= 1 and near_pole.size() < 5000, "cells_within near the pole stays finite (%d cells)" % near_pole.size())
	ok(g.cols_in_row(g.row_of(0.0)) > g.cols_in_row(g.row_of(60.0)) and g.cols_in_row(g.row_of(60.0)) > g.cols_in_row(g.row_of(85.0)), "columns shrink toward the poles (cells keep their metre width)")
	var tiny := GeoGrid.new(1.0)
	ok(_near(tiny.cell_m, GeoGrid.MIN_CELL_M, 0.0001), "cell_m is clamped to a sane minimum")


# ---------------- guard ----------------
func _t_guard() -> void:
	ok(bool(GpsGuard.check({}, {"lat": 50.0, "lon": 30.0, "t_ms": 0}).ok), "first fix of a session is accepted")
	ok(GpsGuard.check({}, {"lat": NAN, "lon": 30.0, "t_ms": 0}).reason == GpsGuard.R_BAD_FIX, "NaN fix refused as bad_fix")
	ok(GpsGuard.check({}, {"lat": "50", "lon": 30.0, "t_ms": 0}).reason == GpsGuard.R_BAD_FIX, "string coordinate refused as bad_fix")
	ok(GpsGuard.check({}, {"lat": 95.0, "lon": 30.0, "t_ms": 0}).reason == GpsGuard.R_BAD_FIX, "latitude out of range refused")
	var a := {"lat": 50.4501, "lon": 30.5234, "t_ms": 1000}
	var walk := Geo.destination(50.4501, 30.5234, 90.0, 1.5 * 10.0)   # 1.5 m/s for 10 s
	ok(bool(GpsGuard.check(a, {"lat": walk.lat, "lon": walk.lon, "t_ms": 11000}).ok), "walking pace accepted")
	var jitter := Geo.destination(50.4501, 30.5234, 0.0, 20.0)
	ok(bool(GpsGuard.check(a, {"lat": jitter.lat, "lon": jitter.lon, "t_ms": 1000}).ok), "20 m of GPS jitter at dt=0 is absorbed")
	var jump := Geo.destination(50.4501, 30.5234, 0.0, 5000.0)
	var r := GpsGuard.check(a, {"lat": jump.lat, "lon": jump.lon, "t_ms": 2000})
	ok(r.reason == GpsGuard.R_TELEPORT and _near(float(r.dist_m), 5000.0, 1.0), "5 km in one second is a teleport")
	ok(bool(GpsGuard.check(a, {"lat": jump.lat, "lon": jump.lon, "t_ms": 1000 + 600000}).ok), "the same 5 km over 10 minutes is fine")
	ok(GpsGuard.check(a, {"lat": 50.4501, "lon": 30.5234, "t_ms": 500}).reason == GpsGuard.R_TIME_BACK, "a fix older than the accepted one is refused")
	var strict := {"max_speed_mps": 3.0, "jitter_m": 5.0}
	var run := Geo.destination(50.4501, 30.5234, 0.0, 100.0)
	ok(GpsGuard.check(a, {"lat": run.lat, "lon": run.lon, "t_ms": 11000}, strict).reason == GpsGuard.R_TELEPORT, "injected params tighten the rule (100 m / 10 s > 3 m/s)")


# ---------------- router ----------------
func _t_router() -> void:
	var shards := ["eu-1", "eu-2", "us-1", "ap-1"]
	var keys: Array = []
	for i in 400:
		keys.append("%d:%d" % [i * 7 % 241, i * 13 % 997])
	var owners := {}
	for k in keys:
		owners[k] = ShardRouter.route(k, shards)
	var shuffled := ["ap-1", "us-1", "eu-2", "eu-1"]
	var same := true
	for k in keys:
		if ShardRouter.route(k, shuffled) != owners[k]:
			same = false
	ok(same, "owner does not depend on the order of the shard list")
	ok(ShardRouter.route("1:1", []) == "", "no shards -> no owner")
	var share := {}
	for k in keys:
		share[owners[k]] = int(share.get(owners[k], 0)) + 1
	var balanced := share.size() == 4
	for s in share:
		if int(share[s]) < 40 or int(share[s]) > 180:
			balanced = false
	ok(balanced, "400 cells spread over 4 shards without starving any (%s)" % str(share))
	var fewer := ["eu-1", "eu-2", "ap-1"]   # us-1 leaves
	var moved_wrongly := 0
	for k in keys:
		var now := ShardRouter.route(k, fewer)
		if owners[k] != "us-1" and now != owners[k]:
			moved_wrongly += 1
	ok(moved_wrongly == 0, "removing a shard moves ONLY that shard's cells (minimal churn)")
	var top := ShardRouter.route_n("5:5", shards, 3)
	ok(top.size() == 3 and top[0] == ShardRouter.route("5:5", shards), "route_n puts the owner first and returns n distinct shards")
	ok(ShardRouter.route_n("5:5", shards, 99).size() == 4 and ShardRouter.route_n("5:5", shards, -1).is_empty(), "route_n clamps n to the shard count and to zero")


# ---------------- realm ----------------
func _realm() -> Variant:
	return Realm.new(GeoGrid.new(), 1200.0)


func _spot(brg: float, dist: float) -> Dictionary:
	return Geo.destination(KYIV.x, KYIV.y, brg, dist)


func _t_realm_membership() -> void:
	var r: Variant = _realm()
	var j: Dictionary = r.join(1, "Остап", KYIV.x, KYIV.y, 0)
	ok(bool(j.ok) and str(j.cell) != "" and int(j.region.seed) > 0, "join returns the cell and the shared region")
	ok(r.join(1, "Дубль", KYIV.x, KYIV.y, 0).reason == Realm.R_DUPLICATE, "joining twice is refused as duplicate")
	ok(r.join(-4, "X", KYIV.x, KYIV.y, 0).reason == Realm.R_ID, "negative id refused")
	ok(r.join(2, "   ", KYIV.x, KYIV.y, 0).reason == Realm.R_NAME and r.join(2, "x".repeat(40), KYIV.x, KYIV.y, 0).reason == Realm.R_NAME, "blank / over-long name refused")
	ok(r.join(2, "Ярина", 123.0, 10.0, 0).reason == GpsGuard.R_BAD_FIX, "an impossible fix cannot join")
	ok(r.count() == 1, "refused joins leave no trace")
	ok(r.move(9, KYIV.x, KYIV.y, 10).reason == Realm.R_UNKNOWN, "moving an unknown player is refused")
	ok(r.leave(1) and not r.leave(1) and r.count() == 0, "leave removes once, then reports unknown")
	var small: Variant = Realm.new(GeoGrid.new(), 1200.0)
	small.max_players = 2
	small.join(1, "A", KYIV.x, KYIV.y, 0)
	small.join(2, "B", KYIV.x, KYIV.y, 0)
	ok(small.join(3, "C", KYIV.x, KYIV.y, 0).reason == Realm.R_FULL, "the realm refuses joins beyond max_players")


func _t_realm_interest() -> void:
	var r: Variant = _realm()
	var p2 := _spot(90.0, 300.0)
	var p3 := _spot(0.0, 1000.0)
	var p4 := _spot(180.0, 3000.0)
	r.join(1, "Я", KYIV.x, KYIV.y, 0)
	r.join(2, "Схід", float(p2.lat), float(p2.lon), 0)
	r.join(3, "Північ", float(p3.lat), float(p3.lon), 0)
	r.join(4, "Далеко", float(p4.lat), float(p4.lon), 0)
	ok(r.interest(1) == [2, 3], "interest = players within aoi_m by exact distance, ascending, self excluded")
	ok(r.interest(4).is_empty(), "a lone far player sees nobody")
	ok(r.interest(3) == [1, 2], "interest is symmetric for mutual neighbours")
	var v: Dictionary = r.presence_view(1)
	ok(v.near.has("2") and v.near["2"].dir == "Сх" and absi(int(v.near["2"].dist_m) - 300) <= 1, "presence_view reports east at ~300 m")
	ok(v.near.has("3") and v.near["3"].dir == "Пн" and not v.near.has("4"), "presence_view lists north, omits the out-of-range player")
	ok(str(v.region) == str(r.player(1).cell.x) + ":" + str(r.player(1).cell.y) and int(v.region_pop) >= 1, "presence_view carries region key and population")
	ok(Persistence.content_hash(v) == Persistence.content_hash(JSON.parse_string(JSON.stringify(v))), "presence_view survives the JSON wire byte-for-byte (content hash)")
	# a player walking out of range disappears; back in range reappears
	var far := Geo.destination(KYIV.x, KYIV.y, 90.0, 300.0)
	var step := Geo.destination(float(far.lat), float(far.lon), 90.0, 2000.0)
	ok(bool(r.move(2, float(step.lat), float(step.lon), 3600000).ok), "a plausible hour-long walk is accepted")
	ok(r.interest(1) == [3], "after walking 2 km east, player 2 leaves player 1's interest")
	ok(r.cohabitants(1).has(2) == (r.player(1).cell == r.player(2).cell), "cohabitants agree with the cell index")
	var tele := Geo.destination(KYIV.x, KYIV.y, 0.0, 8000.0)
	var before: Dictionary = r.player(3)
	ok(r.move(3, float(tele.lat), float(tele.lon), 1000).reason == GpsGuard.R_TELEPORT, "a teleport is refused by the guard")
	ok(r.player(3).lat == before.lat and r.player(3).cell == before.cell and r.population(GeoGrid.key(before.cell)) >= 1, "a refused fix changes neither the record nor the cell index")


func _t_realm_determinism() -> void:
	var spots: Array = []
	for i in 12:
		var p := _spot(float(i * 30), 200.0 + float(i) * 90.0)
		spots.append({"id": i + 1, "lat": float(p.lat), "lon": float(p.lon)})
	var a: Variant = _realm()
	for s in spots:
		a.join(int(s.id), "P%d" % int(s.id), float(s.lat), float(s.lon), 0)
	var b: Variant = _realm()
	for i in range(spots.size() - 1, -1, -1):
		var s: Dictionary = spots[i]
		b.join(int(s.id), "P%d" % int(s.id), float(s.lat), float(s.lon), 0)
	var same := true
	for s in spots:
		if Persistence.content_hash(a.presence_view(int(s.id))) != Persistence.content_hash(b.presence_view(int(s.id))):
			same = false
	ok(same, "presence views are identical whatever order the players joined in")
	ok(a.occupied_cells() == b.occupied_cells(), "the cell index is identical too (sorted keys)")


func _t_realm_changes_and_delta() -> void:
	var r: Variant = _realm()
	r.join(1, "Я", KYIV.x, KYIV.y, 0)
	var first: Dictionary = r.poll_changes(1)
	ok(first.enter.is_empty() and first.leave.is_empty(), "alone: nothing to announce")
	var p := _spot(45.0, 400.0)
	r.join(2, "Гість", float(p.lat), float(p.lon), 10)
	var ev: Dictionary = r.poll_changes(1)
	ok(ev.enter == [2] and ev.leave.is_empty(), "a newcomer in range is announced as enter")
	ok(r.poll_changes(1).enter.is_empty(), "events are one-shot (second poll is quiet)")
	var base: Dictionary = r.presence_view(1)
	r.leave(2)
	var ev2: Dictionary = r.poll_changes(1)
	ok(ev2.leave == [2] and ev2.enter.is_empty(), "a departure is announced as leave")
	var next: Dictionary = r.presence_view(1)
	var delta: Variant = Snapshot.encode(base, next)
	var wire: Variant = JSON.parse_string(JSON.stringify(delta))
	var rebuilt: Variant = Snapshot.apply(JSON.parse_string(JSON.stringify(base)), wire)
	ok(Persistence.content_hash(rebuilt) == Persistence.content_hash(next), "presence delta over the JSON wire reconstructs the next view exactly")
	ok(Snapshot.encode(next, r.presence_view(1)) == null, "an unchanged presence view encodes to no delta at all")
	ok(r.poll_changes(404).enter.is_empty(), "polling an unknown observer is inert")


func _t_realm_expiry() -> void:
	var r: Variant = _realm()
	r.join(1, "A", KYIV.x, KYIV.y, 0)
	r.join(2, "B", KYIV.x, KYIV.y, 0)
	r.join(3, "C", KYIV.x, KYIV.y, 0)
	r.touch(2, 50000)
	r.move(3, KYIV.x, KYIV.y, 40000)
	var gone: Array = r.expire(70000, 30000)
	ok(gone == [1], "only the player silent for more than ttl is expired (heartbeat/fix keep the others)")
	ok(r.count() == 2 and not r.has_player(1), "expired players are fully removed")
	ok(r.expire(70000, 30000).is_empty(), "expiry is idempotent")
	ok(not r.touch(1, 80000), "touching an expired player is refused")

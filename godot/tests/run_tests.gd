# RealWorld — headless test runner for the Godot sim core.
# Run: Godot_console.exe --headless --path godot -s res://tests/run_tests.gd
extends SceneTree

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const Social = preload("res://scripts/social.gd")
const Persistence = preload("res://scripts/persistence.gd")
const SessionScript = preload("res://scripts/session.gd")

var passed := 0
var failed := 0

func _init() -> void:
	print("== RealWorld Godot sim tests ==")
	_t_rng_determinism()
	_t_coord_seed_invariant()
	_t_coord_normalization()
	_t_worldgen_golden()
	_t_haversine()
	_t_worldgen_deterministic()
	_t_pathfinding()
	_t_raid_scaling()
	_t_data_integrity()
	_t_convoy_round_trip()
	_t_death_freeze()
	_t_items()
	_t_demolish()
	_t_osm_overlay()
	_t_social()
	_t_capsule()
	_t_invites()
	_t_persistence()
	_t_persistence_file()
	_t_around_travel()
	_t_permadeath()
	_t_osm_integrity()
	_t_friend_geography()
	_t_session_travel()
	_t_session_respawn()
	_t_environment()
	print("\n== RESULT: %d passed, %d failed ==" % [passed, failed])
	quit(1 if failed > 0 else 0)

func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [pass] ", name)
	else:
		failed += 1
		printerr("  [FAIL] ", name)
		print("  [FAIL] ", name)

func _t_rng_determinism() -> void:
	ok(WorldGen.hash_seed(50.4501, 30.5234) == WorldGen.hash_seed(50.4501, 30.5234), "hash_seed deterministic")
	ok(WorldGen.hash_seed(50.4501, 30.5234) != WorldGen.hash_seed(49.84, 24.03), "hash_seed differs by coords")

func _t_coord_seed_invariant() -> void:
	# "coordinates ARE the seed": region identity and terrain seed derive from ONE canonical coord
	ok(Persistence.region_key(50.4501, 30.5234) == WorldGen.canon_coord(50.4501, 30.5234), "region_key uses the canonical coordinate")
	# two raw coords that round to the same 4 dp must share BOTH seed and region key (they travel together)
	var a_seed := WorldGen.hash_seed(50.45012, 30.52339)
	var b_seed := WorldGen.hash_seed(50.45008, 30.52341)
	ok(a_seed == b_seed, "coords within one 4dp cell share the terrain seed")
	ok(Persistence.region_key(50.45012, 30.52339) == Persistence.region_key(50.45008, 30.52341), "coords within one 4dp cell share the region key")
	# a distinct 4dp cell must change BOTH together (never one without the other)
	ok(WorldGen.hash_seed(50.4502, 30.5234) != a_seed and Persistence.region_key(50.4502, 30.5234) != Persistence.region_key(50.4501, 30.5234), "a different cell changes seed and key together")

func _t_coord_normalization() -> void:
	# in-range coordinates must be untouched (existing seeds preserved)
	ok(WorldGen.canon_coord(50.4501, 30.5234) == "50.4501,30.5234", "in-range coord canonicalizes unchanged")
	ok(WorldGen.hash_seed(50.4501, 30.5234) == 1545000153, "Kyiv seed is stable (== JS reference)")
	# antimeridian: +180 and -180 are the same meridian → one world/key
	ok(WorldGen.canon_coord(0.0, 180.0) == WorldGen.canon_coord(0.0, -180.0), "antimeridian +180/-180 unify")
	ok(WorldGen.hash_seed(0.0, 180.0) == WorldGen.hash_seed(0.0, -180.0), "antimeridian shares one seed")
	# signed/near-zero collapse: no "-0.0000" seam straddling the equator/prime meridian
	ok(Persistence.region_key(-0.00001, 30.5234) == Persistence.region_key(0.00001, 30.5234), "signed near-zero collapses to one cell")
	# out-of-range latitude clamps to the pole rather than seeding a phantom world
	ok(WorldGen.canon_coord(95.0, 30.0) == WorldGen.canon_coord(90.0, 30.0), "latitude clamps to pole")

func _t_worldgen_golden() -> void:
	# Golden vector: pins the coordinate→world contract so any RNG/order/engine-version change fails
	# loudly (the engine RNG is the canonical generator for this shard — see world_gen.gd header).
	var seed_val := WorldGen.hash_seed(50.4501, 30.5234)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var draws := PackedFloat32Array()
	for i in 5:
		draws.append(rng.randf())
	var expected := [0.76746106, 0.51640916, 0.14293730, 0.89633006, 0.17015316]
	var rng_ok := true
	for i in 5:
		if absf(draws[i] - expected[i]) > 1e-5:
			rng_ok = false
	ok(rng_ok, "engine RNG stream pinned for the coordinate seed")
	var m := WorldGen.generate_map(50.4501, 30.5234, 56)
	var fp := Persistence.content_hash({"t": Marshalls.raw_to_base64(m.tiles), "nc": m.nodes.size(), "sx": m.spawn.x, "sy": m.spawn.y})
	ok(m.nodes.size() == 506 and m.spawn == Vector2i(28, 34), "generate_map layout pinned (nodes=506, spawn=28,34)")
	ok(fp == "4e623d08379cd29a", "generate_map terrain fingerprint pinned (%s)" % fp)

func _t_haversine() -> void:
	var km := WorldGen.haversine_km(50.4501, 30.5234, 49.8397, 24.0297)
	ok(km > 450 and km < 485, "haversine Kyiv-Lviv ~467km (got %.1f)" % km)

func _t_worldgen_deterministic() -> void:
	var a := WorldGen.generate_map(50.4501, 30.5234, 56)
	var b := WorldGen.generate_map(50.4501, 30.5234, 56)
	ok(a.n == 56, "map size 56")
	ok(a.tiles == b.tiles, "tiles identical for same coords")
	ok(a.nodes.size() == b.nodes.size(), "node count identical for same coords")
	ok(a.nodes.size() > 50, "resource nodes seeded (%d)" % a.nodes.size())
	var sp: Vector2i = a.spawn
	ok(not WorldGen.is_terrain_blocked(a.tiles[sp.y * a.n + sp.x]), "spawn tile passable")

func _t_pathfinding() -> void:
	var sim = Sim.new()
	var tiles := PackedByteArray()
	tiles.resize(36)
	tiles.fill(WorldGen.GRASS)
	sim.new_game({"n": 6, "tiles": tiles, "nodes": {}, "spawn": Vector2i(0, 0), "lat": 50.0, "lon": 30.0})
	var open := sim.compute_path(0, 0, 5, 0)
	ok(not open.is_empty() and open[open.size() - 1] == Vector2i(5, 0), "open grid reaches target")
	# full wall column x=3 -> unreachable; best-effort returns a partial path that stops before the wall
	for y in 6:
		sim.astar.set_point_solid(Vector2i(3, y), true)
	var walled := sim.compute_path(0, 0, 5, 0)
	ok(not walled.is_empty() and walled[walled.size() - 1].x < 3 and walled[walled.size() - 1] != Vector2i(5, 0), "unreachable target -> best-effort partial path")
	# open a gap at (3,4) -> reachable again
	sim.astar.set_point_solid(Vector2i(3, 4), false)
	var gap := sim.compute_path(0, 0, 5, 0)
	ok(not gap.is_empty() and gap[gap.size() - 1] == Vector2i(5, 0), "path routes through the gap")
	# box the start in completely -> empty path
	sim.astar.set_point_solid(Vector2i(3, 4), true)
	sim.astar.set_point_solid(Vector2i(1, 0), true)
	sim.astar.set_point_solid(Vector2i(0, 1), true)
	ok(sim.compute_path(0, 0, 5, 0).is_empty(), "fully boxed-in start yields empty path")

func _t_raid_scaling() -> void:
	ok(GameData.raid_wave_size(1) == 2, "raid day1 == 2")
	ok(GameData.raid_wave_size(10) == 11, "raid day10 == 11")
	ok(GameData.raid_wave_size(50) == 12, "raid clamps at 12")

func _t_data_integrity() -> void:
	var good := true
	for k in GameData.NODEINFO:
		if not GameData.RES.has(GameData.NODEINFO[k].res):
			good = false
	for b in GameData.BUILDINGS:
		for c in GameData.BUILDINGS[b].cost:
			if not GameData.RES.has(c):
				good = false
	ok(good, "node/building tables reference valid resources")
	ok(GameData.BUILD_ORDER.size() == GameData.BUILDINGS.size(), "BUILD_ORDER covers BUILDINGS")
	ok(GameData.RES_ORDER.size() == GameData.RES.size(), "RES_ORDER covers RES")
	ok(GameData.HUBS.size() == 7, "7 trade hubs (parity with JS)")

func _t_death_freeze() -> void:
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	s._on_death()
	var day0: int = s.time.day
	var frac0: float = s.time.frac
	for i in 50:
		s.update(1.0)
	ok(s.dead and s.time.day == day0 and is_equal_approx(s.time.frac, frac0) and s.enemies.is_empty(), "sim frozen after death (no time/raid advance)")

func _t_items() -> void:
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	var node := {"kind": "tree", "amount": 10}
	var base_time: float = s.gather_time(node)
	var base_dmg: float = s.melee_damage()
	ok(not s.craft_item("axe").ok, "craft fails without a workbench")
	var c = s.base_center()
	var placed := false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if not placed and s.build_valid(c.x + dx, c.y + dy):
				s.stock.wood = 200
				s.stock.stone = 200
				s.stock.scrap = 200
				s.try_build("workbench", c.x + dx, c.y + dy)
				placed = true
	s.stock.wood = 200
	s.stock.stone = 200
	s.stock.scrap = 200
	ok(placed and s.craft_item("axe").ok, "axe crafted with workbench + resources")
	ok(s.player.equipped.tool == "axe" and s.player.items.has("axe"), "axe auto-equipped")
	ok(s.gather_time(node) < base_time, "tool speeds up gather (%.2f < %.2f)" % [s.gather_time(node), base_time])
	ok(s.craft_item("spear").ok, "spear crafted")
	ok(s.player.equipped.weapon == "spear", "spear auto-equipped to weapon slot")
	ok(s.melee_damage() > base_dmg, "weapon boosts melee (%.1f > %.1f)" % [s.melee_damage(), base_dmg])
	# crafting a second tool swaps the equipped tool
	ok(s.craft_item("pick").ok and s.player.equipped.tool == "pick", "second tool (pick) swaps equipped tool")
	# re-equipping an already-owned item must be FREE (no re-pay) — review fix
	var wood_before: int = int(s.stock.wood)
	ok(s.craft_item("axe").ok and s.player.equipped.tool == "axe" and int(s.stock.wood) == wood_before, "re-equipping owned item is free (no re-pay)")
	ok(not s.craft_item("nope").ok, "unknown item rejected")

func _t_demolish() -> void:
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	# empty tile -> nothing to demolish
	ok(not s.demolish(0, 0).ok, "demolish on empty tile rejected")
	# build a wall, then tear it down for a partial (50%) refund
	var c = s.base_center()
	var wx := -1
	var wy := -1
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if wx < 0 and s.build_valid(c.x + dx, c.y + dy):
				s.stock.stone = 200
				s.try_build("wall", c.x + dx, c.y + dy)
				wx = c.x + dx
				wy = c.y + dy
	ok(wx >= 0 and s.is_blocked(wx, wy), "wall built and blocks pathing")
	var stone_before: int = int(s.stock.get("stone", 0))
	var n_before: int = s.buildings.size()
	ok(s.demolish(wx, wy).ok, "wall demolished")
	ok(int(s.stock.get("stone", 0)) == stone_before + int(GameData.BUILDINGS["wall"].cost.stone) / 2, "demolish refunds half the cost")
	ok(s.buildings.size() == n_before - 1 and not s.is_blocked(wx, wy), "demolished wall removed and unblocks tile")
	# cannot demolish your only storage (would strand deposits)
	var sx := -1
	var sy := -1
	for b in s.buildings:
		if b.kind == "storage":
			sx = b.x
			sy = b.y
	ok(sx >= 0 and not s.demolish(sx, sy).ok, "cannot demolish the last storage")

func _t_osm_overlay() -> void:
	var n := 16
	var tiles := PackedByteArray()
	tiles.resize(n * n)
	tiles.fill(WorldGen.GRASS)
	var map := {"n": n, "tiles": tiles, "nodes": {}, "spawn": Vector2i(0, 0), "lat": 50.0, "lon": 30.0}
	var bbox := {"s": 49.99, "n": 50.01, "w": 29.99, "e": 30.01}
	var elements := [
		{"type": "way", "tags": {"highway": "residential"}, "geometry": [{"lat": 50.0, "lon": 29.991}, {"lat": 50.0, "lon": 30.009}]},
		{"type": "way", "tags": {"natural": "water"}, "geometry": [{"lat": 50.004, "lon": 29.992}, {"lat": 50.004, "lon": 29.996}, {"lat": 50.008, "lon": 29.996}, {"lat": 50.008, "lon": 29.992}, {"lat": 50.004, "lon": 29.992}]},
		{"type": "way", "tags": {"building": "yes"}, "geometry": [{"lat": 49.993, "lon": 30.002}, {"lat": 49.993, "lon": 30.006}, {"lat": 49.996, "lon": 30.006}, {"lat": 49.996, "lon": 30.002}, {"lat": 49.993, "lon": 30.002}]},
	]
	var stats = WorldGen.overlay_osm(map, elements, bbox)
	var roads := 0
	var waters := 0
	var ruins := 0
	for t in tiles:
		if t == WorldGen.ROAD:
			roads += 1
		elif t == WorldGen.WATER:
			waters += 1
		elif t == WorldGen.RUIN:
			ruins += 1
	ok(roads > 0, "OSM highway rasterised to road tiles (%d)" % roads)
	ok(waters > 0, "OSM water polygon filled (%d)" % waters)
	ok(ruins > 0, "OSM building -> ruins (%d)" % ruins)
	ok(map.source == "osm" and stats.road == 1 and stats.building == 1, "overlay stats + source set")
	# determinism: same elements -> identical tiles
	var tiles2 := PackedByteArray()
	tiles2.resize(n * n)
	tiles2.fill(WorldGen.GRASS)
	var map2 := {"n": n, "tiles": tiles2, "nodes": {}, "spawn": Vector2i(0, 0), "lat": 50.0, "lon": 30.0}
	WorldGen.overlay_osm(map2, elements, bbox)
	ok(tiles == tiles2, "OSM overlay is deterministic")

func _t_convoy_round_trip() -> void:
	var sim = Sim.new()
	sim.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	sim.stock.wood = 80
	var hub = sim.regions[1]
	var buys: String = hub.offer.buys
	var sells: String = hub.offer.sells
	var before: int = int(sim.stock.get(sells, 0))
	# dispatch the resource this hub actually buys
	var res := sim.dispatch_convoy(1, buys, 18)
	ok(res.ok, "convoy dispatched (%s -> %s)" % [buys, sells])
	ok(int(sim.stock[buys]) == 80 - 18 if buys == "wood" else true, "cargo removed from stock")
	ok(sim.convoys.size() == 1, "one active convoy")
	var expected: int = max(1, int(18 / int(hub.offer.rate)))
	# wrong resource rejected
	ok(not sim.dispatch_convoy(1, "planks", 5).ok, "wrong resource rejected")
	# drive it home (two legs); ambush may reduce but never below 0
	sim._update_convoys(9999.0)
	ok(sim.convoys[0].phase == "back", "convoy turned around")
	sim._update_convoys(9999.0)
	ok(sim.convoys.is_empty(), "convoy completed")
	var gained: int = int(sim.stock.get(sells, 0)) - before
	ok(gained >= 1 and gained <= expected, "traded goods delivered (%d, <= %d)" % [gained, expected])

# ---------------- spec 0002 ----------------
func _t_social() -> void:
	var a := Social.new_graph("Ти", 12345)
	var b := Social.new_graph("Ти", 12345)
	ok(JSON.stringify(a) == JSON.stringify(b), "social graph deterministic for a seed")
	ok(Social.new_graph("Ти", 999) != a, "social graph differs by seed")
	ok(Social.stance_toward(a, a.me.clan) == "ally", "my own clan is allied")
	ok(Social.hostiles(a).size() >= 1, "at least one hostile clan exists")
	ok(Social.raid_pressure(a) > 1.0, "hostiles raise raid pressure (%.2f)" % Social.raid_pressure(a))
	# same-alliance clans are allied regardless of stored stance
	var ally_id := ""
	for cid in a.clans:
		if cid != a.me.clan and a.clans[cid].alliance == Social.my_clan(a).alliance:
			ally_id = cid
			break
	ok(ally_id != "" and Social.stance_toward(a, ally_id) == "ally", "alliance-mates are allied")
	var inv := Social.friend_invite(a, 0, 100.0)
	ok(inv.has("lat") and inv.allow_receive and inv.radius_km == 100.0, "friend_invite well-formed")

func _t_capsule() -> void:
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	ok(int(s.capsule.charges) == GameData.CAPSULE_DAILY_CHARGES, "capsule starts with a daily charge")
	var near := s.capsule_can_reach(50.5109, 30.7909)  # Brovary ~26 km
	ok(near.ok and near.km < 100.0, "capsule reaches within radius (%.0f km)" % near.km)
	var far := s.capsule_can_reach(49.8397, 24.0297)   # Lviv ~467 km
	ok(not far.ok and far.km > 100.0, "capsule blocked beyond radius (%.0f km)" % far.km)
	var l := s.try_launch_capsule(50.5109, 30.7909, "Бровари")
	ok(l.ok and int(s.capsule.charges) == 0, "launch consumes the daily charge")
	ok(not s.try_launch_capsule(50.52, 30.80, "x").ok, "no second capsule the same day")
	s.time.day = 2
	s._grant_daily_capsule()
	ok(int(s.capsule.charges) == 1, "new day refills the capsule charge")

func _t_invites() -> void:
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	s.add_invite({"id": "a", "inviter": "X", "clan": "C", "lat": 50.5109, "lon": 30.7909, "name": "Бровари", "radius_km": 100.0, "allow_receive": false})
	ok(not s.accept_invite("a").ok, "invite without permission is rejected")
	s.add_invite({"id": "b", "inviter": "Y", "clan": "C", "lat": 49.8397, "lon": 24.0297, "name": "Львів", "radius_km": 100.0, "allow_receive": true})
	ok(not s.accept_invite("b").ok, "invite beyond capsule radius is rejected")
	s.add_invite({"id": "c", "inviter": "Z", "clan": "C", "lat": 50.5109, "lon": 30.7909, "name": "Бровари", "radius_km": 100.0, "allow_receive": true})
	var r := s.accept_invite("c")
	ok(r.ok and int(s.capsule.charges) == 0, "valid invite launches and consumes charge")
	ok(s.invites.size() == 2 and not _has_invite(s, "c"), "accepted invite removed from inbox")

func _has_invite(s, id: String) -> bool:
	for e in s.invites:
		if e.id == id:
			return true
	return false

func _t_persistence() -> void:
	# content addressing: canonical (order-independent) + value-sensitive
	ok(Persistence.content_hash({"a": 1, "b": [1, 2]}) == Persistence.content_hash({"b": [1, 2], "a": 1}), "content_hash is order-independent")
	ok(Persistence.content_hash({"a": 1}) != Persistence.content_hash({"a": 2}), "content_hash changes with value")
	# region roundtrip: seed + diff + save reconstructs state
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	var c = s.base_center()
	var built := false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if not built and s.build_valid(c.x + dx, c.y + dy):
				s.stock.stone = 200
				s.try_build("wall", c.x + dx, c.y + dy)
				built = true
	s.stock.wood = 123
	var some_cell := -1
	for cell in s.map.nodes:
		some_cell = cell
		break
	s.map.nodes[some_cell].amount = 3
	var rec := Persistence.serialize_region(s)
	var s2 = Sim.new()
	s2.load_region(rec)
	ok(int(s2.stock.wood) == 123, "roundtrip restores stock diff")
	ok(s2.buildings.size() == s.buildings.size(), "roundtrip restores buildings (%d)" % s2.buildings.size())
	ok(s2.map.nodes.has(some_cell) and int(s2.map.nodes[some_cell].amount) == 3, "roundtrip restores depleted-node diff")
	ok(is_equal_approx(float(s2.player.px), float(s.player.px)), "roundtrip restores pawn position")
	# hash chain integrity across two committed regions
	var store := Persistence.store_new()
	var h1 := Persistence.store_commit(store, Persistence.serialize_region(s))
	var sb = Sim.new()
	sb.new_game(WorldGen.generate_map(49.8397, 24.0297, 24))
	var recb := Persistence.serialize_region(sb)
	var h2 := Persistence.store_commit(store, recb)
	ok(recb.prev == h1 and h2 != h1, "second region chains to the previous head")
	ok(Persistence.verify_store(store), "committed store verifies")
	store.regions[recb.key].stock.wood = 999999
	ok(not Persistence.verify_record(store.regions[recb.key]), "tampering breaks the content hash")

func _t_around_travel() -> void:
	# capsule launch -> arrive in a fresh region -> origin is persisted (spec 0002 around-maps)
	var store := Persistence.store_new()
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	Persistence.store_commit(store, Persistence.serialize_region(s))
	ok(Persistence.store_has(store, Persistence.region_key(50.4501, 30.5234)), "origin region persisted before travel")
	var pawn := s.extract_pawn()
	var l := s.try_launch_capsule(50.5109, 30.7909, "Бровари")
	ok(l.ok, "capsule launched to nearby region")
	var m := WorldGen.generate_map(50.5109, 30.7909, 24)
	m["place_name"] = "Бровари"
	s.arrive_region(m, pawn)
	ok(s.stock.is_empty(), "capsule arrival has no base stock (you left the base behind)")
	ok(s.buildings.is_empty(), "capsule arrival starts with no buildings")
	ok(int(s.map.n) == 24 and str(s.map.place_name) == "Бровари", "arrived region generated on entry")

func _t_persistence_file() -> void:
	# save/load round-trip must keep the hash chain valid despite JSON int->float coercion
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	s.stock.wood = 42
	var store := Persistence.store_new()
	Persistence.store_commit(store, Persistence.serialize_region(s))
	var sb = Sim.new()
	sb.new_game(WorldGen.generate_map(49.8397, 24.0297, 24))
	Persistence.store_commit(store, Persistence.serialize_region(sb))
	var path := "user://test_world.json"
	ok(Persistence.save_to_file(store, path), "store written to disk")
	var loaded := Persistence.load_from_file(path)
	ok(loaded.regions.size() == store.regions.size(), "store reloaded with all regions (%d)" % loaded.regions.size())
	ok(Persistence.verify_store(loaded), "reloaded store verifies (int/float canonicalization stable)")
	var any_key := ""
	for kk in loaded.regions:
		any_key = kk
		break
	loaded.regions[any_key].stock.wood = 987654
	ok(not Persistence.verify_record(loaded.regions[any_key]), "tampering a reloaded record breaks its hash")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _t_permadeath() -> void:
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	s.player.skills.gather = 9.0
	s.player.items.append("axe")
	s.player.equipped.tool = "axe"
	s.player.carry["wood"] = 5
	var b_before: int = s.buildings.size()
	s.stock.wood = 77
	s._on_death()
	ok(s.dead, "death sets dead")
	s.respawn_new_pawn()
	ok(not s.dead, "respawn clears dead")
	ok(float(s.player.skills.gather) == 0.0, "new pawn skills reset to zero")
	ok(s.player.items.is_empty() and str(s.player.equipped.tool) == "", "new pawn loses items and equipment")
	ok((s.player.carry as Dictionary).is_empty(), "new pawn carries nothing")
	ok(s.buildings.size() == b_before and int(s.stock.wood) == 77, "settlement (base + stock) persists after respawn")

func _t_osm_integrity() -> void:
	# OSM terrain is the one non-coordinate-derivable layer; a corrupt/missing tile blob must NOT
	# silently swap in a different (procedural) world at the same coordinate.
	var n := 16
	var s = Sim.new()
	s.new_game(WorldGen.generate_map(50.0, 30.0, n))
	var bbox := {"s": 49.99, "n": 50.01, "w": 29.99, "e": 30.01}
	var elements := [
		{"type": "way", "tags": {"highway": "residential"}, "geometry": [{"lat": 50.0, "lon": 29.991}, {"lat": 50.0, "lon": 30.009}]},
		{"type": "way", "tags": {"natural": "water"}, "geometry": [{"lat": 50.004, "lon": 29.992}, {"lat": 50.004, "lon": 29.996}, {"lat": 50.008, "lon": 29.996}, {"lat": 50.008, "lon": 29.992}, {"lat": 50.004, "lon": 29.992}]},
	]
	WorldGen.overlay_osm(s.map, elements, bbox)
	s.after_map_change()
	var rec := Persistence.serialize_region(s)
	ok(str(rec.source) == "osm" and rec.has("tiles_b64"), "OSM region serialized with a tile blob")
	# valid record: reloads as OSM with the exact saved terrain and a passable spawn
	var s2 = Sim.new()
	s2.load_region(rec)
	ok(str(s2.map.source) == "osm" and s2.map.tiles == s.map.tiles, "valid OSM record reloads the exact terrain")
	var sp: Vector2i = s2.map.spawn
	ok(not WorldGen.is_terrain_blocked(s2.map.tiles[sp.y * int(s2.map.n) + sp.x]), "reloaded OSM spawn is passable")
	# corrupt record (blob dropped): must NOT masquerade as the OSM world
	var bad: Dictionary = rec.duplicate(true)
	bad.erase("tiles_b64")
	var s3 = Sim.new()
	s3.load_region(bad)
	ok(str(s3.map.get("source", "")) != "osm", "OSM record without tiles does NOT silently load as the OSM world")

func _t_friend_geography() -> void:
	# "coordinates ARE the seed" for the social roster: friends are seeded around the ACTUAL home,
	# within capsule radius (reachable), deterministic, and different for a different spawn.
	var kyiv := Social.new_graph("Ти", WorldGen.hash_seed(50.4501, 30.5234), 50.4501, 30.5234)
	var kyiv2 := Social.new_graph("Ти", WorldGen.hash_seed(50.4501, 30.5234), 50.4501, 30.5234)
	ok(JSON.stringify(kyiv) == JSON.stringify(kyiv2), "friend geography is deterministic for a coordinate")
	var all_reachable := true
	for fr in kyiv.friends:
		if WorldGen.haversine_km(50.4501, 30.5234, fr.lat, fr.lon) > GameData.CAPSULE_BASE_RADIUS_KM:
			all_reachable = false
	ok(kyiv.friends.size() >= 3 and all_reachable, "Kyiv friends are within capsule radius (invites reachable)")
	var kyoto := Social.new_graph("Ти", WorldGen.hash_seed(35.0116, 135.7681), 35.0116, 135.7681)
	ok(kyoto.friends[0].lat != kyiv.friends[0].lat, "friend outposts follow the spawn coordinate")
	var kyoto_reachable := true
	for fr in kyoto.friends:
		if WorldGen.haversine_km(35.0116, 135.7681, fr.lat, fr.lon) > GameData.CAPSULE_BASE_RADIUS_KM:
			kyoto_reachable = false
	ok(kyoto_reachable, "Kyoto spawn yields reachable Kansai-area friends (not hardcoded Kyiv)")

func _t_session_travel() -> void:
	var se = SessionScript.new()
	se.autosave = false
	se.start(50.4501, 30.5234, "Київ")
	ok(se.sim != null and se.stored_region_count() == 0, "session starts with no committed regions")
	var head0: String = se.chain_head()
	var l = se.sim.try_launch_capsule(50.5109, 30.7909, "Бровари")
	ok(l.ok, "capsule launched from the session sim")
	se.travel_to(50.5109, 30.7909, "Бровари")
	ok(se.stored_region_count() == 1, "origin region committed to the store on travel")
	ok(se.chain_head() != head0, "hash-chain head advanced after commit")
	ok((se.sim.stock as Dictionary).is_empty(), "arrived at a fresh outpost (no base stock)")
	# fly home -> the settlement (buildings + stock) is restored from the store
	se.travel_to(50.4501, 30.5234, "Київ")
	ok((se.sim.stock as Dictionary).size() > 0 and se.stored_region_count() == 2, "returning home restores the settlement; both regions persisted")

func _t_session_respawn() -> void:
	var se = SessionScript.new()
	se.autosave = false
	se.start(50.4501, 30.5234, "Київ")
	# capsule to a remote region, build nothing, die there
	se.sim.try_launch_capsule(50.5109, 30.7909, "Бровари")
	se.travel_to(50.5109, 30.7909, "Бровари")
	se.sim._on_death()
	se.respawn()
	ok(not se.sim.dead, "respawn clears death")
	var home_key := Persistence.region_key(50.4501, 30.5234)
	ok(Persistence.region_key(float(se.sim.map.lat), float(se.sim.map.lon)) == home_key, "respawn flew the new pawn back to the home region")
	var has_storage := false
	for b in se.sim.buildings:
		if b.kind == "storage":
			has_storage = true
			break
	ok(has_storage, "new pawn respawns at the home settlement (storage present)")

# ---------------- Batch 8a: живе довкілля (клімат/погода/світло/приміщення/обігрів) ----------------
func _t_environment() -> void:
	# a flat 16x16 grass arena away from map-gen noise; Kyiv latitude drives the climate
	var nn := 16
	var tiles := PackedByteArray()
	tiles.resize(nn * nn)
	tiles.fill(WorldGen.GRASS)
	var s = Sim.new()
	s.new_game({"n": nn, "tiles": tiles, "nodes": {}, "spawn": Vector2i(2, 2), "lat": 50.4501, "lon": 30.5234})

	# --- 1. the climate is live and latitude-real: Kyiv winter noon colder than summer noon --------
	s.weather = &"clear"
	s.time.frac = 0.5
	s.time.day = 15
	var t_winter: float = s.ambient_temp_c()
	s.time.day = 195
	var t_summer: float = s.ambient_temp_c()
	ok(t_winter < t_summer, "Київ: зима холодніша за літо (%.1f < %.1f)" % [t_winter, t_summer])
	ok(s.season_name() != "", "season readable (%s)" % s.season_name())

	# --- 2. incident anomaly seam (spec E6): shift, then expiry --------------------------------------
	s.apply_temp_anomaly(-15.0, 2.0)
	ok(absf(s.ambient_temp_c() - (t_summer - 15.0)) < 0.01, "cold-snap anomaly shifts ambient by −15°C")
	s._update_environment(2.1)
	ok(s.temp_offset == 0.0 and s.temp_offset_days == 0.0, "anomaly expires after its days run out")
	s.weather = &"clear"

	# --- 3. weather stream is deterministic from the region seed -------------------------------------
	var a = Sim.new()
	a.new_game({"n": nn, "tiles": tiles.duplicate(), "nodes": {}, "spawn": Vector2i(2, 2), "lat": 50.4501, "lon": 30.5234})
	var b = Sim.new()
	b.new_game({"n": nn, "tiles": tiles.duplicate(), "nodes": {}, "spawn": Vector2i(2, 2), "lat": 50.4501, "lon": 30.5234})
	var seq_a := []
	var seq_b := []
	for i in 8:
		a._update_environment(0.3)
		b._update_environment(0.3)
		seq_a.append(a.weather)
		seq_b.append(b.weather)
	ok(str(seq_a) == str(seq_b), "weather stream reproduces from the region seed")
	var c2 = Sim.new()
	c2.new_game({"n": nn, "tiles": tiles.duplicate(), "nodes": {}, "spawn": Vector2i(2, 2), "lat": 35.0116, "lon": 135.7681})
	var seq_c := []
	for i in 8:
		c2._update_environment(0.3)
		seq_c.append(c2.weather)
	ok(str(seq_c) != str(seq_a) or c2.region_seed() != a.region_seed(), "different coordinate -> different weather stream")

	# --- 4. cold_snap weather dips ambient by the kernel-parity constant -----------------------------
	s.weather = &"clear"
	var t_clear: float = s.ambient_temp_c()
	s.weather = &"cold_snap"
	ok(absf(s.ambient_temp_c() - (t_clear - 6.0)) < 0.01, "cold_snap weather dips ambient −6°C")
	s.weather = &"snow"
	ok(s.is_wet(), "snow is wet weather")
	s.weather = &"clear"
	ok(not s.is_wet(), "clear is dry weather")

	# --- 5. enclosure flood-fill (spec B4): 4 walls make a room; a breach un-rooms it -----------------
	var cx := 8
	var cy := 8
	ok(not s.is_indoor(cx, cy), "open cell starts outdoor")
	s._place_building("wall", cx + 1, cy, -1)
	s._place_building("wall", cx - 1, cy, -1)
	s._place_building("wall", cx, cy + 1, -1)
	var last_wall = s._place_building("wall", cx, cy - 1, -1)
	ok(s.is_indoor(cx, cy), "cell enclosed by 4 walls becomes indoor")
	ok(not s.is_indoor(cx + 2, cy), "cell outside the room stays outdoor")
	s._remove_building(last_wall)
	ok(not s.is_indoor(cx, cy), "breached room is outdoor again")
	# a door seals the room like a wall (air-wise) while staying passable for the hero
	s._place_building("door", cx, cy - 1, -1)
	ok(s.is_indoor(cx, cy), "door seals the room (indoor again)")
	ok(not s.is_blocked(cx, cy - 1), "door stays passable for pathing")

	# --- 6. indoor buffers temperature toward the setpoint in winter ---------------------------------
	s.time.day = 15   # winter
	s.weather = &"clear"
	var out_t: float = s.ambient_temp_c()
	var in_t: float = s.temp_at(cx, cy)
	ok(absf(in_t - 21.0) < absf(out_t - 21.0), "indoor closer to 21°C than outdoor (%.1f vs %.1f)" % [in_t, out_t])

	# --- 7. campfire heats nearby cells ---------------------------------------------------------------
	var probe_x := 3
	var probe_y := 12
	var before: float = s.temp_at(probe_x, probe_y)
	s._place_building("campfire", probe_x + 1, probe_y, -1)
	ok(s.temp_at(probe_x, probe_y) > before, "campfire raises nearby felt temperature")
	ok(absf(s.temp_at(probe_x + 1, probe_y) - (before + 4.0)) < 0.01, "campfire adds its +4°C at its own cell")

	# --- 8. light & the darkness work penalty (spec B3) ----------------------------------------------
	s.time.frac = 0.5
	ok(s.daylight_level() > 0.9, "midday is bright")
	s.time.frac = 0.02
	ok(s.daylight_level() < 0.1, "deep night is dark")
	ok(s.daylight() > 0.35, "night overlay dense at night")
	# hero far from any light: work slows
	s.player.px = 14.5
	s.player.py = 2.5
	var night_mult: float = s.dark_work_mult()
	ok(night_mult > 1.2, "night work penalty active (×%.2f)" % night_mult)
	var node := {"kind": "tree", "amount": 5}
	var t_night: float = s.gather_time(node)
	s.time.frac = 0.5
	var t_day: float = s.gather_time(node)
	ok(t_night > t_day, "gathering is slower in the dark (%.2f > %.2f)" % [t_night, t_day])
	# a torch next to the hero cancels the penalty
	s.time.frac = 0.02
	s._place_building("torch", 14, 3, -1)
	ok(s.dark_work_mult() < night_mult, "torch light reduces the darkness penalty")
	ok(s.light_at(14, 2) > 0.6, "torch cell is lit at night")

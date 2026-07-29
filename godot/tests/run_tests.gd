# RealWorld — headless test runner for the Godot sim core.
# Run: Godot_console.exe --headless --path godot -s res://tests/run_tests.gd
extends "res://tests/harness.gd"

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const Social = preload("res://scripts/social.gd")
const Persistence = preload("res://scripts/persistence.gd")
const SessionScript = preload("res://scripts/session.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const KernelGear = preload("res://scripts/kernel/gear.gd")
const KernelNeeds = preload("res://scripts/kernel/needs.gd")
const KernelHealth = preload("res://scripts/kernel/health.gd")
const CatalogDefs = preload("res://scripts/catalog_defs.gd")


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
	_t_open_stock()
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
	_t_hero_health()
	_t_cold_exposure()
	_t_deprivation_live()
	_t_health_persistence()
	_t_raid_determinism()
	_t_patrols()
	_t_content_pack()
	_t_research_gates()
	_t_use_catalog_persist()
	_t_catalog_live()
	_t_no_global_rng()
	_t_static_typing()
	_t_stock_seam()
	finish()


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

# ---------------- spec 0008 phase 2: open catalogue-keyed stock behind use_catalog ----------------
# OFF must stay byte-identical to the shipped slice (guarded by exact keys below); ON re-keys the same
# game onto catalogue ids through data_bridge, so catalogue recipes can afford against the LIVE stock.
func _t_open_stock() -> void:
	# flag OFF (default): the shipped 6-key vocabulary, untouched
	var a = Sim.new()
	a.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	ok(not a.use_catalog, "use_catalog defaults to OFF (shipped slice unchanged)")
	var off_keys := true
	for k in ["wood", "stone", "food", "scrap", "planks", "components"]:
		if not a.stock.has(k):
			off_keys = false
	ok(off_keys and a.stock.size() == 6, "flag OFF: stock carries exactly the 6 live ids")
	ok(a.res_key("food") == "food" and a.res_amount("food") == 18, "flag OFF: res_key is the identity")

	# flag ON: the same new game speaks catalogue ids (set BEFORE new_game, never mid-save)
	var b = Sim.new()
	b.use_catalog = true
	b.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	ok(b.stock.has("raw_food") and not b.stock.has("food"), "flag ON: live 'food' lands on catalogue 'raw_food'")
	ok(b.res_amount("food") == 18, "flag ON: res_amount reads a live id through the bridge")
	b.deposit("food", 4)
	ok(int(b.stock["raw_food"]) == 22, "flag ON: deposit('food') lands on 'raw_food'")
	# build affords + pays the re-keyed cost from the open stock
	b.stock[b.res_key("wood")] = 200
	b.stock[b.res_key("stone")] = 200
	b.stock[b.res_key("scrap")] = 200
	var c: Vector2i = b.base_center()
	var placed := false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if not placed and b.build_valid(c.x + dx, c.y + dy):
				b.try_build("workbench", c.x + dx, c.y + dy)
				placed = true
	ok(b.has_workbench(), "flag ON: try_build pays the re-keyed cost and places the building")
	ok(b.res_amount("wood") < 200, "flag ON: the build consumed wood from the open stock")
	# convoy dispatch draws through the same seam
	var hub = b.regions[1]
	b.stock[b.res_key(String(hub.offer.buys))] = 80
	ok(b.dispatch_convoy(1, String(hub.offer.buys), 10).ok, "flag ON: convoy affords against the open stock")
	# the hunger path eats catalogue-keyed food (player spawns beside the starter storage)
	b.player.hunger = 40.0
	b.player.eat_cd = 0.0
	var food_before: int = b.res_amount("food")
	b.update(0.05)
	ok(b.res_amount("food") == food_before - 1, "flag ON: eating consumes 'raw_food' through the seam")

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

# ---------------- located hero health (sim/hero_health.gd wiring the kernel tracker live) ----------------
# a flat warm-summer arena: no map noise, comfort in-band, threats disarmed — isolates the channel under test
func _flat_sim(day: int = 195, use_catalog: bool = false) -> Variant:
	var nn := 16
	var tiles := PackedByteArray()
	tiles.resize(nn * nn)
	tiles.fill(WorldGen.GRASS)
	var s = Sim.new()
	s.use_catalog = use_catalog   # BEFORE new_game (spec 0008 §5.2 — never flipped mid-save)
	s.new_game({"n": nn, "tiles": tiles, "nodes": {}, "spawn": Vector2i(8, 8), "lat": 50.4501, "lon": 30.5234})
	s.time.day = day
	s.time.frac = 0.5
	s.weather = &"clear"
	s.raid.next = 1e9
	s.patrol.next = 1e9
	return s

func _t_hero_health() -> void:
	var s = _flat_sim()
	ok(s.health != null and float(s.player.hp) == 100.0, "new game starts a fresh located-health tracker")
	# an enemy blow lands as a LOCATED injury: severity = dmg × armor × INJURY_SCALE on a real part
	var atk: Dictionary = GameData.make_raider(s.player.px + 0.5, s.player.py, 1)
	atk.atk_cd = 0.0
	s.enemies.append(atk)
	s._update_enemies(0.01)
	ok(s.health.hediffs.size() == 1, "the hit sits on the tracker as one wound")
	var wound: Variant = s.health.hediffs[0]
	ok(absf(float(wound.severity) - float(atk.dmg) * 0.55) < 0.01, "wound severity = post-armor damage × 0.55")
	ok(wound.part != null, "the wound names a body part (%s)" % wound.part.label)
	s.enemies.clear()
	# hit location replays from the seeded threat stream: twin sims take the same wound
	var a = _flat_sim()
	var b = _flat_sim()
	for tw in [a, b]:
		var e2: Dictionary = GameData.make_raider(tw.player.px + 0.5, tw.player.py, 1)
		e2.atk_cd = 0.0
		tw.enemies.append(e2)
		tw._update_enemies(0.01)
	ok(String(a.health.hediffs[0].part.key) == String(b.health.hediffs[0].part.key), "same seed -> same hit location")
	# an untended wound bleeds; sleeping in a bed tends it and the bleeding stops
	var s2 = _flat_sim()
	s2.health.injure(&"torso", 20.0, "рвана рана")
	s2.update(0.5)
	ok(float(s2.health.total_bleed()) > 0.0, "untended torso wound bleeds")
	var blood0: float = float(s2.health.blood)
	for i in 20:
		s2.update(0.5)
	ok(float(s2.health.blood) < blood0, "bleeding drains blood over ticks")
	ok(float(s2.player.hp) < 100.0, "hp readout reflects the wounded body")
	s2._place_building("bed", int(s2.player.px) + 1, int(s2.player.py), -1)
	s2.player.rest = 50.0
	s2.player.action = null
	for i in 6:
		s2.update(0.5)
	ok(bool(s2.player.sleeping), "pawn sleeps by the bed")
	ok(bool(s2.health.hediffs[0].tended) and float(s2.health.total_bleed()) == 0.0, "bed sleep tends the wound (bleeding stops)")
	# a smashed vital part is death, and the verdict names the cause — through the real combat
	# entry (HeroHealth.damage picks parts off the seeded stream; massive blows soon find a vital)
	var s3 = _flat_sim()
	var hits := 0
	while not s3.dead and hits < 12:
		Sim.HeroHealth.damage(s3, 200.0)
		hits += 1
	ok(s3.dead, "massive blows destroy a vital part and kill (%d hits)" % hits)
	var died_msg := false
	for m in s3.messages:
		if "Причина смерті" in String(m.text):
			died_msg = true
	ok(died_msg, "death verdict names its cause in the feed")
	# permadeath: the rookie arrives in an unscarred body
	s3.respawn_new_pawn()
	ok(s3.health.hediffs.is_empty() and float(s3.player.hp) == 100.0, "respawned pawn has a fresh tracker")
	# wounded arms work slower and hit weaker; wounded legs walk slower (capacities feed the sim)
	var s4 = _flat_sim()
	var node := {"kind": "tree", "amount": 5}
	var t0: float = s4.gather_time(node)
	var dmg0: float = s4.melee_damage()
	s4.health.injure(&"arm_l", 20.0)
	s4.health.injure(&"arm_r", 20.0)
	s4.health.injure(&"leg_l", 20.0)
	ok(s4.gather_time(node) > t0, "wounded arms gather slower")
	ok(s4.melee_damage() < dmg0, "wounded arms hit weaker")

func _t_cold_exposure() -> void:
	# Kyiv day 15 == deep winter: standing outside with no heat grows hypothermia — the climate BITES
	var s = _flat_sim(15)
	ok(s.hero_felt_c() < 12.0, "winter noon outdoors is below the comfort band (%.1f°C)" % s.hero_felt_c())
	var hint := false
	for m in s.messages:
		if "холодно" in String(m.text):
			hint = true
	ok(hint, "cold spawn logs the fire-first onboarding hint")
	var node := {"kind": "tree", "amount": 5}
	var warm_time: float = s.gather_time(node)
	for i in 60:
		s.update(0.5)
		s.player.hunger = 100.0
		s.player.rest = 100.0
	var hypo: Variant = null
	for h in s.health.hediffs:
		if h is KernelGear.Hediff_Hypothermia:
			hypo = h
	ok(hypo != null and float(hypo.severity) > 0.1, "unheated winter grows hypothermia (тяж.%.2f)" % (float(hypo.severity) if hypo else -1.0))
	ok(s.gather_time(node) > warm_time, "freezing hands work slower (%.2f > %.2f)" % [s.gather_time(node), warm_time])
	ok(float(s.player.hp) < 100.0, "hp readout drops as the cold deepens")
	# a scrap vest adds felt warmth (data.gd insul)
	var felt_bare: float = s.hero_felt_c()
	s.player.items.append("vest")
	s.equip("vest")
	ok(absf(s.hero_felt_c() - (felt_bare + 3.0)) < 0.01, "vest adds +3°C felt warmth")
	s.player.equipped["armor"] = ""
	# an ENCLOSED, heated room holds the comfort band: severity recedes to nothing inside
	# (a fire in the open field is NOT enough in deep winter — shelter + heat is the lesson)
	s.player.px = 3.5
	s.player.py = 3.5
	s.player.action = null
	s._place_building("wall", 2, 3, -1)
	s._place_building("wall", 4, 3, -1)
	s._place_building("wall", 3, 2, -1)
	s._place_building("door", 3, 4, -1)
	ok(s.is_indoor(3, 3), "the pawn's cell is now a room")
	s._place_building("campfire", 3, 3, -1)
	s._place_building("heater", 3, 3, -1)
	ok(s.hero_felt_c() >= 12.0, "walls + campfire + heater lift the felt °C into the band (%.1f)" % s.hero_felt_c())
	for i in 40:
		s.update(0.5)
		s.player.hunger = 100.0
		s.player.rest = 100.0
	var still_cold := false
	for h in s.health.hediffs:
		if h is KernelGear.Hediff_Hypothermia:
			still_cold = true
	ok(not still_cold, "sheltered heat recedes hypothermia to nothing (heat sources have teeth)")
	# unrelenting deep cold is lethal: the death verdict says so
	var s2 = _flat_sim(15)
	s2.apply_temp_anomaly(-45.0, 20.0)
	var guard := 0
	while not s2.dead and guard < 400:
		s2.update(0.5)
		s2.player.hunger = 100.0
		s2.player.rest = 100.0
		guard += 1
	ok(s2.dead, "unsheltered −45°C anomaly eventually kills")
	var froze := false
	for m in s2.messages:
		if "замерз" in String(m.text):
			froze = true
	ok(froze, "the verdict names the cold")

func _t_deprivation_live() -> void:
	# starvation: an empty stomach is now a rising condition, not a silent hp drain — and it kills
	var s = _flat_sim()
	s.stock[s.res_key("food")] = 0
	var guard := 0
	while not s.dead and guard < 800:
		s.update(0.5)
		s.player.hunger = 0.0
		s.player.rest = 100.0
		guard += 1
	ok(s.dead, "starvation kills after ~2 hungry days")
	var starved := false
	for m in s.messages:
		if "голодна смерть" in String(m.text).to_lower():
			starved = true
	ok(starved, "the verdict names starvation")
	# sleeplessness: collapse where you stand (downed -> forced sleep), NOT death
	var s2 = _flat_sim()
	var downed_seen := false
	var guard2 := 0
	while guard2 < 500 and not downed_seen:
		s2.update(0.5)
		s2.player.hunger = 100.0
		s2.player.rest = 0.0
		s2.player.sleeping = false   # no bed: fight the sleep until the body gives out
		guard2 += 1
		downed_seen = s2.hero_downed()
	ok(downed_seen and not s2.dead, "exhaustion downs the pawn without killing")
	# released to sleep, the collapse resolves: rest recovers, consciousness returns, the pawn wakes
	var guard3 := 0
	while s2.hero_downed() and guard3 < 200:
		s2.update(0.5)
		s2.player.hunger = 100.0
		guard3 += 1
	ok(not s2.hero_downed() and not s2.dead, "the collapsed pawn sleeps it off and gets up")

func _t_health_persistence() -> void:
	# wounds survive save/load byte-exactly, and the world hash covers them
	var s = _flat_sim()
	s.health.injure(&"leg_l", 9.0, "поріз")   # >= scar threshold: also seeds the scar debt
	s.health.injure(&"torso", 6.0)
	s.health.hediffs[0].tended = true
	s.update(0.5)   # registers scar_watch + recomputes hp
	var rec := Persistence.serialize_region(s)
	ok(rec.has("health"), "serialize_region carries the health record")
	var s2 = Sim.new()
	s2.load_region(rec)
	ok(Persistence.content_hash(s.health_dict()) == Persistence.content_hash(s2.health_dict()),
		"load_region restores the tracker exactly (wounds, tended flags, scar debt)")
	ok(absf(float(s.player.hp) - float(s2.player.hp)) < 0.01, "restored hp readout matches")
	var watch: Array = s2.health_dict().get("scar_watch", [])
	ok(watch.has("leg_l"), "the scar debt survives the round-trip")
	# the wound is IN the world hash: twin worlds agree, a wound splits them
	var t1 = _flat_sim()
	var t2 = _flat_sim()
	ok(Persistence.world_hash(t1) == Persistence.world_hash(t2), "twin worlds hash identically")
	t1.health.injure(&"arm_l", 5.0)
	ok(Persistence.world_hash(t1) != Persistence.world_hash(t2), "a wound changes the world hash (health is authoritative state)")
	# rejoin: the resume payload lands the wounded pawn byte-identical
	var r1 := Persistence.resume_payload(s)
	var s3 = Sim.new()
	Persistence.restore(s3, r1)
	ok(Persistence.world_hash(s3) == Persistence.world_hash(s), "resume payload restores a hash-exact wounded world")
	# travel: the capsule carries the body, wounds and all
	var pawn: Dictionary = s.extract_pawn()
	ok(pawn.has("health"), "extract_pawn packs the tracker")
	var m := WorldGen.generate_map(50.5109, 30.7909, 16)
	m["place_name"] = "Бровари"
	var s4 = Sim.new()
	s4.new_game(WorldGen.generate_map(49.8397, 24.0297, 16))
	s4.arrive_region(m, pawn)
	ok(Persistence.content_hash(s4.health_dict()) == Persistence.content_hash(s.health_dict()),
		"arrive_region lands the same wounded body")
	# legacy save (no health record): the old hp float migrates to a tended torso wound
	var old_rec: Dictionary = Persistence.serialize_region(_flat_sim())
	old_rec.erase("health")
	old_rec.player.hp = 40.0
	var s5 = Sim.new()
	s5.load_region(old_rec)
	ok(s5.health.hediffs.size() == 1 and s5.health.hediffs[0] is KernelHealth.Hediff_Injury, "legacy hp migrates to one torso wound")
	ok(float(s5.health.total_bleed()) == 0.0, "the migrated wound is tended (no bleed surprise)")
	ok(float(s5.player.hp) < 100.0 and float(s5.player.hp) > 0.0, "migrated readout reflects the lived-in body")
	# JSON file round-trip (int->float coercion) keeps the record hash-stable
	var via_json: Variant = JSON.parse_string(JSON.stringify(rec))
	var s6 = Sim.new()
	s6.load_region(via_json)
	ok(Persistence.content_hash(s6.health_dict()) == Persistence.content_hash(s.health_dict()),
		"health record survives a JSON round-trip")

# «координати — це seed» поширюється й на загрози: рейд-хвилі, засідки на конвої та лут
# ідуть з окремого seeded потоку (sim.threat_rng), незалежного від погодного (env_rng).
func _t_raid_determinism() -> void:
	var a = Sim.new()
	a.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	var b = Sim.new()
	b.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	a._spawn_wave()
	b._spawn_wave()
	var pos_a := []
	var pos_b := []
	for e in a.enemies:
		pos_a.append([e.px, e.py])
	for e in b.enemies:
		pos_b.append([e.px, e.py])
	ok(not pos_a.is_empty(), "wave spawned raiders (%d)" % pos_a.size())
	ok(str(pos_a) == str(pos_b), "same region seed -> identical raid wave placement")
	# the reroll of the next-raid timer comes from the same seeded stream
	a.enemies = []
	b.enemies = []
	a._update_raids(0.1)
	b._update_raids(0.1)
	ok(absf(float(a.raid.next) - float(b.raid.next)) < 0.0001, "same region seed -> identical next-raid timer")
	# weather stream is untouched by threat consumption: raids never desync the climate
	var c = Sim.new()
	c.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	for i in 4:
		a._update_environment(0.3)
		c._update_environment(0.3)
	ok(a.weather == c.weather, "threat stream does not consume from the weather stream")

# Лор-контент: патрульні роботи Старого світу (постапокаліпсис) — амбієнтна загроза поза
# рейд-циклом, з того самого seeded threat-потоку; розібраний робот — джерело компонентів.
func _t_patrols() -> void:
	var a = Sim.new()
	a.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	ok(float(a.patrol.next) > 0.0 and int(a.patrol.wave) == 0, "патруль зведений і чекає свого часу")
	a._spawn_patrol()
	ok(not a.enemies.is_empty(), "патруль виходить на мапу (%d од.)" % a.enemies.size())
	var bot: Dictionary = a.enemies[0]
	ok(String(bot.get("kind", "")) == "bot", "патрульний юніт — робот, не рейдер")
	ok(float(bot.hp) > float(GameData.make_raider(0.0, 0.0, 1).hp), "робот дня 1 міцніший за рейдера дня 1")
	ok(float(bot.speed) < float(GameData.make_raider(0.0, 0.0, 1).speed), "робот повільніший — в'язкий танк")
	# лут: розібрані роботи насипають брухт (і стохастично, але детерміновано — компоненти)
	var scrap0 := int(a.stock.get("scrap", 0))
	while not a.enemies.is_empty():
		a._damage_enemy(a.enemies[0], 9999.0)
	ok(int(a.stock.scrap) > scrap0, "розібраний робот дає брухт")
	ok(GameData.patrol_size(1) == 1 and GameData.patrol_size(20) == 4 and GameData.patrol_size(99) == 4,
		"патруль росте з днями і капиться на ланці з 4 машин")
	# детермінізм: той самий seed -> ідентичний патруль (позиції обох сімів збігаються)
	var b = Sim.new()
	b.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	var c = Sim.new()
	c.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	b._spawn_patrol()
	c._spawn_patrol()
	var pos_b := []
	var pos_c := []
	for e in b.enemies:
		pos_b.append([e.px, e.py])
	for e in c.enemies:
		pos_c.append([e.px, e.py])
	ok(str(pos_b) == str(pos_c), "той самий seed -> ідентичний маршрут входу патруля")
	# рейд глушить появу патруля, але таймер перезаряджається (одна битва за раз)
	var d = Sim.new()
	d.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	d.raid.active = true
	d.patrol.timer = 99999.0
	var wave0 := int(d.patrol.wave)
	d._update_patrols(0.1)
	ok(int(d.patrol.wave) == wave0 and d.enemies.is_empty(), "під час рейду патруль не накладається")
	ok(float(d.patrol.timer) == 0.0 and float(d.patrol.next) >= 95.0, "таймер патруля перезаряджений")

# Контент-пак: лампа/обігрівач/шипи (будівлі), кувалда/лук/броня (спорядження), 5-хабова торгівля.
func _t_content_pack() -> void:
	var nn := 16
	var tiles := PackedByteArray()
	tiles.resize(nn * nn)
	tiles.fill(WorldGen.GRASS)
	var s = Sim.new()
	s.new_game({"n": nn, "tiles": tiles, "nodes": {}, "spawn": Vector2i(2, 2), "lat": 50.4501, "lon": 30.5234})
	s.stock.scrap = 200
	s.stock.components = 20
	s.stock.wood = 200
	s.stock.stone = 200
	# лампа: міні-сонце свого радіуса вночі (генеричний light-емітер із data.gd)
	s.time.frac = 0.02
	ok(s.light_at(10, 8) < 0.1, "до лампи вночі темно")
	s._place_building("lamp", 10, 10, -1)
	ok(s.light_at(10, 8) > 0.5, "лампа освітлює сусідні клітини вночі")
	# обігрівач: +6°C на своїй клітині (генеричний heat-емітер)
	s.time.day = 15
	s.weather = &"clear"
	var t0: float = s.temp_at(3, 12)
	s._place_building("heater", 3, 12, -1)
	ok(absf(s.temp_at(3, 12) - (t0 + 6.0)) < 0.01, "обігрівач додає +6°C на своїй клітині")
	# шипи: ворог на пастці отримує урон, пастка зношується
	var trap: Variant = s._place_building("spike_trap", 8, 3, -1)
	var raider: Dictionary = GameData.make_raider(8.5, 3.5, 1)
	s.enemies.append(raider)
	var hp0: float = raider.hp
	var trap_hp0: float = trap.hp
	s._update_enemies(0.5)
	ok(float(raider.hp) < hp0, "шипи ранять ворога на клітині (%.1f → %.1f)" % [hp0, float(raider.hp)])
	ok(float(trap.hp) < trap_hp0, "шипи зношуються від використання")
	s.enemies.clear()
	# ворота досліджень: до відкриття гейтові предмети/будівлі відмовляють з поясненням
	s._place_building("workbench", 4, 4, -1)
	var refused: Dictionary = s.craft_item("plate")
	ok(not bool(refused.ok) and "дослідження" in String(refused.msg), "панцир заборонений до Ковальства")
	s.stock.stone = 200
	var stone0 := int(s.stock.stone)
	s.try_build("turret", 12, 12)
	ok(int(s.stock.stone) == stone0 and "дослідження" in s.flash_msg, "турель заборонена до Механіки (кошти цілі)")
	# відкриваємо гілки — все стає доступним
	s.research_unlocked = {"masonry": true, "hunting": true, "smelting": true, "smithing": true, "machining": true}
	# броня: панцир ріже вхідний урон удвічі — удар лягає ЛОКАЛІЗОВАНОЮ раною на тракер
	# (sim/hero_health.gd), тож звіряємо сумарну тяжкість ран, а не віднімання від hp-флоата
	ok(bool(s.craft_item("plate").ok), "панцир скрафчено на верстаку (після Ковальства)")
	ok(String(s.player.equipped.get("armor", "")) == "plate", "панцир екіповано у слот armor")
	ok(absf(s.armor_mult() - 0.5) < 0.001, "панцир ріже урон удвічі")
	var atk: Dictionary = GameData.make_raider(s.player.px + 0.5, s.player.py, 1)
	atk.atk_cd = 0.0
	s.enemies.append(atk)
	var php0: float = float(s.player.hp)
	s._update_enemies(0.01)
	var wound_sev := 0.0
	for h in s.health.hediffs:
		wound_sev += float(h.severity)
	ok(absf(wound_sev - float(atk.dmg) * 0.5 * 0.55) < 0.01, "вхідний удар порізаний бронею і ліг раною на частину тіла")
	ok(float(s.player.hp) <= php0, "hp-редаут відбиває отриману рану")
	s.enemies.clear()
	# кувалда і лук: топ-тір спорядження (свіже тіло — поранена рука била б слабше, і це фіча)
	s.health_reset()
	ok(bool(s.craft_item("sledge").ok) and bool(s.craft_item("bow").ok), "кувалда і лук скрафчені")
	ok(absf(s.melee_damage() - (12.0 + float(s.player.skills.combat) + 18.0)) < 0.01, "лук додає +18 урону")
	ok(float(GameData.ITEMS.sledge.gather_mult) > float(GameData.ITEMS.pick.gather_mult), "кувалда швидша за кайло")
	# торгова мережа: 5 хабів на регіон, усі оффери валідні
	var s2 = Sim.new()
	s2.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	ok(s2.regions.size() == 6, "регіон бачить 5 торгових хабів (+дім), маємо %d" % (s2.regions.size() - 1))
	var offers_ok := true
	for i in range(1, s2.regions.size()):
		var off: Dictionary = s2.regions[i].offer
		if not (GameData.RES.has(off.buys) and GameData.RES.has(off.sells)):
			offers_ok = false
	ok(offers_ok, "усі хаб-оффери посилаються на валідні ресурси")
	ok(GameData.OFFERS.size() == 6, "торгова мережа розширена до 6 офферів")
	# живий міст: unlock у kernel-прогресії відкриває sim-ворота через session.tick_research
	var sess = SessionScript.new()
	sess.start(50.4501, 30.5234, "Тест-міст")
	ok(not sess.sim.research_ok(GameData.BUILDINGS.turret), "свіжий світ: турель за ворітьми")
	sess.progression.research.unlock(&"machining")
	sess.tick_research(0.016)
	ok(sess.sim.research_ok(GameData.BUILDINGS.turret), "kernel-unlock відкриває турель через session-міст")

# Tripwire (стиль run_ui_tests): глобальні randf()/randi()/randomize() заборонені у scripts/ —
# лише seeded RandomNumberGenerator, інакше ламається стовп «світ = чиста функція lat/lon».
func _t_no_global_rng() -> void:
	var re := RegEx.new()
	re.compile("(^|[^.\\w])(randf|randi|randfn|randf_range|randi_range|randomize)\\s*\\(")
	var offenders := []
	var files := _product_scripts()
	for path in files:
		if re.search(_read_code(path)) != null:
			offenders.append(path)
	ok(files.size() > 20, "rng tripwire scans the script tree (%d files)" % files.size())
	ok(offenders.is_empty(), "no global randf()/randi() anywhere in scripts (seeded RNG only)%s"
		% ("" if offenders.is_empty() else " — " + ", ".join(PackedStringArray(offenders))))

# Tripwire: нові нетипізовані `var` у продуктових скриптах заборонені (AGENTS.md: «статична типізація
# скрізь»). Редакторський ворнінг (untyped_declaration у project.godot) у headless/CI не емітиться —
# перевірено: аналайзер друкує його лише в редакторі — тож примус живе тут. Ловить `var x = ...`
# (без `:` типу і без `:=`) та голе `var x` (навіть із трейлінг-коментом).
func _t_static_typing() -> void:
	var re_assign := RegEx.new()
	re_assign.compile("(^|[\\t ])var\\s+[A-Za-z_]\\w*\\s*=[^=]")
	var re_bare := RegEx.new()
	re_bare.compile("(^|[\\t ])var\\s+[A-Za-z_]\\w*[\\t ]*$")
	var offenders := []
	for path in _product_scripts():
		var n_hits := 0
		for line in _read_code(path).split("\n"):
			# inline comments must not trip the scan; strip \r too — на CRLF-чекауті (Windows)
			# "var x\r" інакше не матчить $-якір і tripwire зеленіє там, де Linux-CI впаде
			var code := str(line).replace("\r", "").get_slice("#", 0)
			if re_assign.search(code) != null or re_bare.search(code) != null:
				n_hits += 1
		if n_hits > 0:
			offenders.append("%s (%d)" % [path, n_hits])
	ok(offenders.is_empty(), "every product var declaration is statically typed%s"
		% ("" if offenders.is_empty() else " — " + ", ".join(PackedStringArray(offenders))))

# Tripwire spec 0008: «жодного прямого stock[...] поза швом res_key/res_amount/cost_keys/afford».
# Поза корпусом: sim.gd (дім шва), hud_model.gd (документований фолбек для test-fakes), kernel/
# (його world.stock — окремий контракт кернела), заморожений main.gd. Інлайн-патерни: індексація
# без res_key усередині дужок та крапковий доступ (stock.wood / stock.get(...)).
func _t_stock_seam() -> void:
	var re_idx := RegEx.new()
	re_idx.compile("\\.stock\\s*\\[(?![^\\]\\n]*res_key\\()")
	var re_dot := RegEx.new()
	re_dot.compile("\\.stock\\.[A-Za-z_]")
	var offenders := []
	for path in _product_scripts():
		var p := str(path)
		if p.ends_with("/sim.gd") or p.ends_with("/hud_model.gd") or "/kernel/" in p or p.ends_with("scripts/main.gd"):
			continue
		var body := _read_code(p)
		if re_idx.search(body) != null or re_dot.search(body) != null:
			offenders.append(p)
	ok(offenders.is_empty(), "no direct stock access outside the res_key seam (spec 0008)%s"
		% ("" if offenders.is_empty() else " — " + ", ".join(PackedStringArray(offenders))))

# Ворота живого контенту (spec 0007): кожен research-id з data.gd існує в catalog.json, а
# RESEARCH_LABEL — точне дзеркало його label. Інакше неіснуючий id = контент замкнено назавжди
# (session не має що мостити), а 🔒-повідомлення деградує до сирого id — і жоден тест цього не бачив.
func _t_research_gates() -> void:
	var cat: Dictionary = Catalog.load_json()
	var labels := {}
	for r in cat.get("research", []):
		labels[String((r as Dictionary).id)] = String((r as Dictionary).get("label", ""))
	var gated := {}
	for def in GameData.BUILDINGS.values():
		if def.has("research"):
			gated[String(def.research)] = true
	for it in GameData.ITEMS.values():
		if it.has("research"):
			gated[String(it.research)] = true
	ok(gated.size() >= 5, "gated content present (%d research gates)" % gated.size())
	var missing := []
	var drifted := []
	for gid in gated:
		if not labels.has(gid):
			missing.append(gid)
		elif String(GameData.RESEARCH_LABEL.get(gid, "")) != String(labels[gid]):
			drifted.append(gid)
	ok(missing.is_empty(), "every data.gd research gate exists in catalog.json%s"
		% ("" if missing.is_empty() else " — " + ", ".join(PackedStringArray(missing))))
	ok(drifted.is_empty(), "RESEARCH_LABEL mirrors catalogue labels exactly%s"
		% ("" if drifted.is_empty() else " — " + ", ".join(PackedStringArray(drifted))))

# ---------------- spec 0008 phases 3–4: живі каталожні build/craft + курований тір ----------------
func _t_catalog_live() -> void:
	# 0) курований фільтр — capability-driven чесність: без power-мережі powered-дефи не будуються,
	# defense без живого мозку (турель/пастка) — теж; data.gd-ids каталог НЕ дублює (одна правда на id)
	ok(CatalogDefs.building("auto_turret").is_empty(), "powered турель поза живим тіром (немає мережі — була б безкоштовна)")
	ok(CatalogDefs.building("mortar").is_empty(), "мінoмет без живого мозку не будується (не декорація)")
	ok(CatalogDefs.building("bed").is_empty() and CatalogDefs.building("wall").is_empty(), "data.gd-ids каталог не дублює")
	ok(float(CatalogDefs.building("deadfall_trap").get("trap_dps", 0.0)) > 0.0, "каталожна пастка мапиться на живий trap_dps-мозок")
	ok(int(CatalogDefs.building("warehouse").get("capacity", 0)) == 800, "ангар несе свою місткість у шов")
	ok(bool(CatalogDefs.building("stone_wall").get("blocks", false)), "кам'яна стіна блокує (blocks з каталогу)")
	# збагачений видобуток — чиста функція (cell, amount): детермінований і містить руду
	var seq_a := []
	var seq_b := []
	var kinds := {}
	for amt in range(1, 13):
		seq_a.append(CatalogDefs.gather_yield("rock", 77, amt))
		seq_b.append(CatalogDefs.gather_yield("rock", 77, amt))
		kinds[CatalogDefs.gather_yield("rock", 77, amt)] = true
	ok(str(seq_a) == str(seq_b), "вихід ноди — чиста функція (реплей точний)")
	ok(kinds.has("stone") and kinds.has("iron_ore"), "скеля дає і камінь, і руду (%s)" % str(kinds.keys()))

	# 1) прапор OFF: каталожні id-и відмовляють — шліфований зріз незмінний
	var off = _flat_sim()
	off.try_build("kiln", 3, 3)
	ok(not off.has_building("kiln"), "flag OFF: каталожна будівля не ставиться")
	ok(not bool(off.craft_catalog("make_charcoal").ok), "flag OFF: каталожний крафт відмовляє")

	# 2) прапор ON: ворота -> будівництво -> крафт-ланцюг на ЖИВОМУ складі
	var s = _flat_sim(195, true)
	s.stock[s.res_key("clay")] = 20
	s.stock[s.res_key("stone")] = 20
	s.stock[s.res_key("wood")] = 20
	s.try_build("kiln", 3, 3)
	ok(not s.has_building("kiln") and "дослідження" in s.flash_msg, "ворота тримають: піч до Опанування вогню не ставиться")
	s.research_unlocked = {"fire_mastery": true}
	s.try_build("kiln", 3, 3)
	ok(s.has_building("kiln"), "після unlock: каталожна піч стоїть у живому світі")
	ok(int(s.res_amount("clay")) == 8, "будівництво сплатило каталожну ціну (глина 20→8)")
	var r_no: Dictionary = s.craft_catalog("cut_block")
	ok(not bool(r_no.ok) and StringName(r_no.reason) == &"no_station", "рецепт без станції відмовляє з причиною")
	var r_ok: Dictionary = s.craft_catalog("make_charcoal")
	ok(bool(r_ok.ok) and int(s.stock.get("charcoal", 0)) == 2, "піч перепалює дерево на вугілля (+2)")
	ok(int(s.res_amount("wood")) == 16, "крафт сплатив входи (дерево 20→16)")

	# 3) живий видобуток: скеля під прапором насипає руду в реальному циклі збору
	var node_cell := 8 * 16 + 5
	s.map.nodes[node_cell] = {"kind": "rock", "amount": 12}
	s.order_gather(5, 8)
	var guard := 0
	while s.map.nodes.has(node_cell) and guard < 600:
		s.update(0.1)
		s.player.hunger = 100.0
		s.player.rest = 100.0
		guard += 1
	var got_ore: bool = int(s.player.carry.get("iron_ore", 0)) + int(s.res_amount("iron_ore")) > 0
	ok(got_ore, "живий збір зі скелі приніс залізну руду (курований тір відкрився)")

	# 4) персистенс: каталожна будівля і відкритий склад переживають save/load + world_hash близнюки
	var rec := Persistence.serialize_region(s)
	var s2 = Sim.new()
	s2.load_region(rec)
	ok(s2.has_building("kiln"), "save/load відновлює каталожну будівлю")
	ok(int(s2.stock.get("charcoal", 0)) == 2, "save/load відновлює каталожний склад")
	var t1 = _flat_sim(195, true)
	var t2 = _flat_sim(195, true)
	ok(Persistence.world_hash(t1) == Persistence.world_hash(t2), "близнюки з прапором ON хешуються однаково")
	t1.research_unlocked = {"fire_mastery": true}
	t1.stock[t1.res_key("clay")] = 20
	t1.try_build("kiln", 3, 3)
	ok(Persistence.world_hash(t1) != Persistence.world_hash(t2), "каталожна будівля входить у world_hash")

	# 5) досяжність живого тіра — виведена, не хардкоджена: замикання від живих сировин мусить
	# накривати сталевий ланцюг (дзеркало tests/catalog.test.js — два валідатори не розійдуться)
	var cat: Dictionary = Catalog.load_json()
	var live_raws := ["wood", "stone", "raw_food", "scrap", "iron_ore", "coal", "clay", "sand", "copper_ore", "plant_fiber", "herbal"]
	var closure := _live_closure(cat, live_raws)
	for res_id in ["charcoal", "iron_bar", "steel", "components", "medicine", "ammo"]:
		ok((closure.obtainable as Dictionary).has(StringName(res_id)), "живий тір досягає %s" % res_id)
	ok((closure.obtainable as Dictionary).size() == 38, "замикання живого тіра: 38 ресурсів (закріплено)")
	# кожен збагачений вихід нод — справжня сировина каталогу (одруківка = мертвий ресурс у кишені)
	var res_ids := {}
	for r in cat.get("resources", []):
		res_ids[str(r.get("id", ""))] = true
	for kind in CatalogDefs.GATHER_YIELD:
		for rid in CatalogDefs.GATHER_YIELD[kind]:
			ok(res_ids.has(str(rid)), "вихід ноди '%s' існує в каталозі (%s)" % [rid, kind])

# Замикання досяжності від заданих сировин (та сама логіка, що Catalog.reachability, але з
# довільним сідом замість усіх raw-джерел) — тестова копія для звірки живого тіра.
func _live_closure(cat: Dictionary, seed_raws: Array) -> Dictionary:
	var obtainable := {}
	for rid in seed_raws:
		obtainable[StringName(str(rid))] = true
	var unlocked := {}
	var built := {}
	var made := {}
	var changed := true
	while changed:
		changed = false
		for r in cat.get("research", []):
			var rid := StringName(str(r.get("id", "")))
			if unlocked.has(rid):
				continue
			var all_met := true
			for p in r.get("prereqs", []):
				if not unlocked.has(StringName(str(p))):
					all_met = false
			if all_met:
				unlocked[rid] = true
				changed = true
		for b in cat.get("buildings", []):
			var bid := StringName(str(b.get("id", "")))
			if built.has(bid):
				continue
			var cost_ok := true
			for c in b.get("cost", {}):
				if not obtainable.has(StringName(str(c))):
					cost_ok = false
			var gate := str(b.get("research", ""))
			if cost_ok and (gate == "" or unlocked.has(StringName(gate))):
				built[bid] = true
				changed = true
		for rc in cat.get("recipes", []):
			var rcid := StringName(str(rc.get("id", "")))
			if made.has(rcid):
				continue
			var in_ok := true
			for c in rc.get("inputs", {}):
				if not obtainable.has(StringName(str(c))):
					in_ok = false
			var rgate := str(rc.get("research", ""))
			if built.has(StringName(str(rc.get("station", "")))) and in_ok and (rgate == "" or unlocked.has(StringName(rgate))):
				made[rcid] = true
				obtainable[StringName(str(rc.get("output", {}).get("id", "")))] = true
				changed = true
	return {"obtainable": obtainable, "built": built, "made": made}

# spec 0008: сейв несе словник ключів складу — use_catalog мусить пережити роундтрип, інакше
# save(ON) -> load(OFF) читає чужі ключі й склад «зникає» без діагностики.
func _t_use_catalog_persist() -> void:
	var s = Sim.new()
	s.use_catalog = true
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 24))
	var rec := Persistence.serialize_region(s)
	ok(bool(rec.use_catalog), "serialize_region persists use_catalog")
	var s2 = Sim.new()
	ok(not s2.use_catalog, "fresh sim defaults to OFF")
	s2.load_region(rec)
	ok(s2.use_catalog, "load_region restores the stock vocabulary flag")
	ok(int(s2.res_amount("food")) == 18, "restored save reads food through the bridge (catalogue keys)")

# every product .gd (the scripts tree + the scene entry) — the corpus for source-scan tripwires
func _product_scripts() -> Array:
	var files := ["res://newhud_main.gd"]
	for dir_path in ["res://scripts", "res://scripts/sim", "res://scripts/kernel", "res://scripts/ui", "res://scripts/ui/dev", "res://scripts/net"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				files.append(dir_path + "/" + f)
	return files

func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

# comment-stripped source (drops full-line # comments) so doc comments may mention forbidden calls
func _read_code(path: String) -> String:
	var out := PackedStringArray()
	for line in _read_file(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)

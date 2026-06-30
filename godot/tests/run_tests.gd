# RealWorld — headless test runner for the Godot sim core.
# Run: Godot_console.exe --headless --path godot -s res://tests/run_tests.gd
extends SceneTree

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")

var passed := 0
var failed := 0

func _init() -> void:
	print("== RealWorld Godot sim tests ==")
	_t_rng_determinism()
	_t_haversine()
	_t_worldgen_deterministic()
	_t_pathfinding()
	_t_raid_scaling()
	_t_data_integrity()
	_t_convoy_round_trip()
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
	# full wall column x=3
	for y in 6:
		sim.astar.set_point_solid(Vector2i(3, y), true)
	ok(sim.compute_path(0, 0, 5, 0).is_empty(), "fully walled target unreachable")
	# open a gap at (3,4)
	sim.astar.set_point_solid(Vector2i(3, 4), false)
	var gap := sim.compute_path(0, 0, 5, 0)
	ok(not gap.is_empty() and gap[gap.size() - 1] == Vector2i(5, 0), "path routes through the gap")

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

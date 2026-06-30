# RealWorld — headless playthrough smoke test (drives the integrated update loop).
# Run: Godot_console.exe --headless --path godot -s res://tests/run_smoke.gd
extends SceneTree

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")

var passed := 0
var failed := 0
var sim

func _init() -> void:
	print("== RealWorld Godot playthrough smoke ==")
	sim = Sim.new()
	sim.new_game(WorldGen.generate_map(50.4501, 30.5234, 56))
	_smoke_gather()
	_smoke_build_and_craft()
	_smoke_raid()
	_smoke_convoy()
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

func _topup() -> void:
	sim.player.hp = 100.0
	sim.player.hunger = 100.0
	sim.player.rest = 100.0

func _smoke_gather() -> void:
	var n: int = sim.n
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for key in sim.map.nodes:
		if sim.map.nodes[key].kind != "tree":
			continue
		var x: int = key % n
		var y: int = int(key / n)
		var d: int = absi(x - int(sim.player.px)) + absi(y - int(sim.player.py))
		if d < bd:
			bd = d
			best = Vector2i(x, y)
	sim.order_gather(best.x, best.y)
	var ticks := 0
	while ticks < 700 and sim.carry_total() < 3:
		sim.update(0.1)
		_topup()
		ticks += 1
	ok(sim.carry_total() >= 3, "walked to tree and gathered wood (%d ticks, carry=%d)" % [ticks, sim.carry_total()])

func _smoke_build_and_craft() -> void:
	_topup()
	var wall := Vector2i(-1, -1)
	var px := int(sim.player.px)
	var py := int(sim.player.py)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if wall.x < 0 and sim.build_valid(px + dx, py + dy):
				var stone0: int = int(sim.stock.stone)
				sim.try_build("wall", px + dx, py + dy)
				if int(sim.stock.stone) < stone0:
					wall = Vector2i(px + dx, py + dy)
	ok(wall.x >= 0, "built a wall, paid stone")
	ok(sim.is_blocked(wall.x, wall.y), "wall blocks pathing")
	# workbench + crafting automation
	var wb := false
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if not wb and sim.build_valid(px + dx, py + dy):
				var wood0: int = int(sim.stock.wood)
				sim.try_build("workbench", px + dx, py + dy)
				if int(sim.stock.wood) < wood0:
					wb = true
	var planks0: int = int(sim.stock.planks)
	for i in 300:
		sim.update(0.1)
		_topup()
	ok(wb and int(sim.stock.planks) > planks0, "workbench auto-crafted planks (%d)" % int(sim.stock.planks))

func _smoke_raid() -> void:
	_topup()
	sim.raid.active = false
	sim.raid.warned = false
	sim.raid.timer = 0.0
	sim.raid.next = 0.05
	for i in 30:
		sim.update(0.1)
	var spawned: int = sim.enemies.size()
	ok(spawned > 0, "raid wave spawned (%d raiders)" % spawned)
	# place a turret at base centre
	sim.stock.scrap = 60
	sim.stock.components = 12
	var c = sim.base_center()
	var turret := false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not turret and sim.build_valid(c.x + dx, c.y + dy):
				sim.try_build("turret", c.x + dx, c.y + dy)
				turret = true
	var ticks := 0
	while ticks < 1200 and not sim.enemies.is_empty():
		sim.update(0.1)
		_topup()
		ticks += 1
	ok(turret and sim.enemies.is_empty() and not sim.dead, "turret cleared the raid (%d ticks)" % ticks)

func _smoke_convoy() -> void:
	_topup()
	sim.stock.wood = 80
	var hub = sim.regions[1]
	var sells: String = hub.offer.sells
	var before: int = int(sim.stock.get(sells, 0))
	var res = sim.dispatch_convoy(1, hub.offer.buys, 18)
	ok(res.ok, "convoy dispatched")
	var ticks := 0
	while ticks < 2000 and not sim.convoys.is_empty():
		sim._update_convoys(0.5)
		ticks += 1
	var gained: int = int(sim.stock.get(sells, 0)) - before
	ok(sim.convoys.is_empty() and gained >= 1, "convoy returned with traded goods (+%d %s)" % [gained, sells])

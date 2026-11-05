# RealWorld — tests/run_determinism_tests.gd : the spec 0006 §4 acceptance backbone.
#
# Two INDEPENDENT sim instances fed the same seed and the same command stream must agree on
# Persistence.world_hash at every probe point. This is the determinism half of the Plan §2 spike
# (the socket transport is deliberately out of scope — the risk the spike de-risks is state
# drift, not socket plumbing) and the permanent anti-desync tripwire of §10. The last line prints
#   WORLD_HASH_FINAL=<hash>
# so CI can run this suite twice as two OS processes and diff the lines — literally the
# "two independent server instances" wording of §4 (catches per-process nondeterminism that a
# single in-process twin run cannot).
# Run: godot --headless --path godot -s res://tests/run_determinism_tests.gd
extends "res://tests/harness.gd"

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Persistence = preload("res://scripts/persistence.gd")

const LAT := 50.4501
const LON := 30.5234
const N := 56
const DT := 0.1
const CAPSULE_CLOCK_MS := 1800000000000   # spec 0010: the injected device clock of the ON scenario (a fixed UTC ms instant)


func _init() -> void:
	print("== RealWorld determinism suite (spec 0006 §4) ==")
	_t_twin_ambient()
	_t_twin_commands()
	_t_seed_contrast()
	_t_region_roundtrip_hash()
	_t_twin_capsule_on()
	_print_final_hash()
	_print_capsule_hash()
	finish()


func _fresh(lat: float, lon: float) -> Variant:
	var sim: Variant = Sim.new()
	sim.new_game(WorldGen.generate_map(lat, lon, N))
	return sim


# identical top-up on both twins keeps the pawns alive through raids without breaking symmetry
func _topup(sim: Variant) -> void:
	sim.player.hp = 100.0
	sim.player.hunger = 100.0
	sim.player.rest = 100.0


# nearest tree to the spawn — computed from the map only, so both twins get the same target
func _nearest_tree(sim: Variant) -> Vector2i:
	var n: int = sim.n
	var sp: Vector2i = sim.map.spawn
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for key in sim.map.nodes:
		if sim.map.nodes[key].kind != "tree":
			continue
		var x: int = key % n
		var y: int = int(key / n)
		var d: int = absi(x - sp.x) + absi(y - sp.y)
		if d < bd:
			bd = d
			best = Vector2i(x, y)
	return best


# first buildable cell scanning out from the spawn — again a pure function of the shared map
func _buildable_near_spawn(sim: Variant) -> Vector2i:
	var sp: Vector2i = sim.map.spawn
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if sim.build_valid(sp.x + dx, sp.y + dy):
					return Vector2i(sp.x + dx, sp.y + dy)
	return Vector2i(-1, -1)


func _t_twin_ambient() -> void:
	var a: Variant = _fresh(LAT, LON)
	var b: Variant = _fresh(LAT, LON)
	var diverged := -1
	for t in 600:
		a.update(DT)
		b.update(DT)
		_topup(a)
		_topup(b)
		if (t + 1) % 150 == 0 and Persistence.world_hash(a) != Persistence.world_hash(b):
			diverged = t + 1
			break
	var label := "identical" if diverged < 0 else "DIVERGED at tick %d" % diverged
	ok(diverged < 0, "twin ambient run: world_hash %s across 600 ticks (probe every 150)" % label)


func _t_twin_commands() -> void:
	var a: Variant = _fresh(LAT, LON)
	var b: Variant = _fresh(LAT, LON)
	var tree := _nearest_tree(a)
	var cell := _buildable_near_spawn(a)
	var sp: Vector2i = a.map.spawn
	var diverged := -1
	for t in 500:
		# the scripted command stream: same verbs, same args, same tick — on both instances
		if t == 30:
			a.order_gather(tree.x, tree.y)
			b.order_gather(tree.x, tree.y)
		elif t == 120 and cell.x >= 0:
			a.try_build("wall", cell.x, cell.y)
			b.try_build("wall", cell.x, cell.y)
		elif t == 240:
			a.order_move(sp.x + 3, sp.y)
			b.order_move(sp.x + 3, sp.y)
		a.update(DT)
		b.update(DT)
		_topup(a)
		_topup(b)
		if (t + 1) % 100 == 0 and Persistence.world_hash(a) != Persistence.world_hash(b):
			diverged = t + 1
			break
	var label := "identical" if diverged < 0 else "DIVERGED at tick %d" % diverged
	ok(diverged < 0, "twin command run (gather/build/move): world_hash %s across 500 ticks" % label)


func _t_seed_contrast() -> void:
	var a: Variant = _fresh(LAT, LON)
	var b: Variant = _fresh(49.8397, 24.0297)
	for t in 150:
		a.update(DT)
		b.update(DT)
		_topup(a)
		_topup(b)
	var ha := Persistence.world_hash(a)
	var hb := Persistence.world_hash(b)
	ok(ha != hb, "seed contrast: different coordinates yield a different world_hash (%s vs %s)" % [ha.left(8), hb.left(8)])


func _t_region_roundtrip_hash() -> void:
	var a: Variant = _fresh(LAT, LON)
	for t in 200:
		a.update(DT)
		_topup(a)
	var rec := Persistence.serialize_region(a)
	var fresh: Variant = Sim.new()
	fresh.load_region(rec)
	var ha := Persistence.content_hash(Persistence.serialize_region(a))
	var hb := Persistence.content_hash(Persistence.serialize_region(fresh))
	ok(ha == hb, "region payload survives a serialize -> load_region -> serialize round-trip bit-stable")


# spec 0010 (REQ-0010-04/35/82/92): the Основна капсула world, ON — two independent instances, the SAME injected clock,
# 600 ticks: world_hash (the capsule record rides in serialize_region) must agree. The clock enters ONLY through
# Sim.set_clock (never read inside the sim); landed_at/grace_start take it at landing, now_ms itself is not hashed.
func _capsule_on(now_ms: int) -> Variant:
	var sim: Variant = Sim.new()
	sim.use_inventory = true
	sim.use_catalog = true
	sim.use_main_capsule = true
	sim.set_clock(now_ms)
	sim.new_game(WorldGen.generate_map(LAT, LON, N))
	return sim


func _t_twin_capsule_on() -> void:
	var a: Variant = _capsule_on(CAPSULE_CLOCK_MS)
	var b: Variant = _capsule_on(CAPSULE_CLOCK_MS)
	var diverged := -1
	for t in 600:
		a.update(DT)
		b.update(DT)
		_topup(a)
		_topup(b)
		if (t + 1) % 150 == 0 and Persistence.world_hash(a) != Persistence.world_hash(b):
			diverged = t + 1
			break
	var label := "identical" if diverged < 0 else "DIVERGED at tick %d" % diverged
	ok(diverged < 0 and not (a.main_capsule as Dictionary).is_empty(), "twin ON capsule run (fixed set_clock): world_hash %s across 600 ticks" % label)
	var late: Variant = _capsule_on(CAPSULE_CLOCK_MS + 1)
	ok(Persistence.world_hash(late) != Persistence.world_hash(_capsule_on(CAPSULE_CLOCK_MS)), "a different landing instant is a different world (landed_at is hashed)")
	var same: Variant = _capsule_on(CAPSULE_CLOCK_MS)
	same.set_clock(CAPSULE_CLOCK_MS + 5000)   # later pushes move now_ms, not the world record
	ok(Persistence.world_hash(same) == Persistence.world_hash(_capsule_on(CAPSULE_CLOCK_MS)), "now_ms itself is NOT in world_hash (only the instants stored in the capsule record are)")


# canonical scenario for the cross-process check: CI runs the suite twice and diffs this line
func _print_final_hash() -> void:
	var sim: Variant = _fresh(LAT, LON)
	for t in 300:
		sim.update(DT)
		_topup(sim)
	print("WORLD_HASH_FINAL=" + Persistence.world_hash(sim))


# the same cross-process check for the ON world (spec 0010): CI diffs this line too, so per-process nondeterminism in the
# capsule path (record, landing, clock input) has nowhere to hide. WORLD_HASH_FINAL (OFF) above must stay c4dbef44fe0f95d6.
func _print_capsule_hash() -> void:
	var sim: Variant = _capsule_on(CAPSULE_CLOCK_MS)
	for t in 300:
		sim.update(DT)
		_topup(sim)
	print("WORLD_HASH_CAPSULE=" + Persistence.world_hash(sim))

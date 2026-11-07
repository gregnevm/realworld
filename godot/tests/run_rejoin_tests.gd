# RealWorld — tests/run_rejoin_tests.gd : the spec 0006 plan §5 persistence + rejoin suite.
#
# Two things Phase 1 needs from Persistence and neither the save format nor the delta stream
# provides on its own:
#   RESUME  — a client that was not there (fresh join, reconnect) must land BYTE-IDENTICAL to the
#             authoritative server and stay identical as the world keeps ticking. Landing "close
#             enough" is a desync with a delay: the next raid roll pulls a different rng cursor.
#   INTEGRITY — the append-only hash chain is the server's authoritative record; a tampered link
#             must be detectable, or an authoritative store is just a file.
# Run: godot --headless --path godot -s res://tests/run_rejoin_tests.gd
extends "res://tests/harness.gd"

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Persistence = preload("res://scripts/persistence.gd")
const Snapshot = preload("res://scripts/net/snapshot.gd")
const Command = preload("res://scripts/net/command.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const Director = preload("res://scripts/sim/director.gd")

const LAT := 50.4501
const LON := 30.5234
const N := 56
const DT := 0.1


func _init() -> void:
	print("== RealWorld persistence + rejoin suite (spec 0006 plan §5) ==")
	_t_save_format_alone_is_not_enough()
	_t_resume_is_hash_exact()
	_t_resume_carries_a_busy_pawn()
	_t_resume_survives_the_wire()
	_t_chain_integrity()
	_t_seq_resume()
	_t_resume_on_raid_states()
	finish()


func _fresh() -> Variant:
	var sim: Variant = Sim.new()
	sim.new_game(WorldGen.generate_map(LAT, LON, N))
	return sim


func _topup(sim: Variant) -> void:
	sim.player.hp = 100.0
	sim.player.hunger = 100.0
	sim.player.rest = 100.0


# advance far enough that raids/patrols/weather have all moved off their initial values
func _advance(sim: Variant, ticks: int) -> void:
	for i in ticks:
		sim.update(DT)
		_topup(sim)


# The motivating defect, pinned as a test: restoring from the SAVE half alone lands a client in a
# different world (threats reset, rng cursors rewound). If this ever starts passing, the save
# format has silently absorbed runtime state and the two halves need re-splitting.
func _t_save_format_alone_is_not_enough() -> void:
	var live: Variant = _fresh()
	_advance(live, 400)
	var half: Variant = Sim.new()
	half.load_region(Persistence.serialize_region(live))
	ok(Persistence.world_hash(half) != Persistence.world_hash(live),
		"save-format restore alone does NOT reproduce the live world (this is why plan §5 exists)")


func _t_resume_is_hash_exact() -> void:
	var server: Variant = _fresh()
	_advance(server, 400)
	var joiner: Variant = Sim.new()
	Persistence.restore(joiner, Persistence.resume_payload(server))
	ok(Persistence.world_hash(joiner) == Persistence.world_hash(server),
		"a rejoining client lands byte-identical to the server (full resume payload)")
	# ...and STAYS identical: this is the part a snapshot cannot buy you, because it proves the
	# stochastic streams resumed at the right cursor rather than merely looking the same right now
	var diverged := -1
	for t in 300:
		server.update(DT)
		joiner.update(DT)
		_topup(server)
		_topup(joiner)
		if (t + 1) % 100 == 0 and Persistence.world_hash(server) != Persistence.world_hash(joiner):
			diverged = t + 1
			break
	ok(diverged < 0, "server and rejoined client stay identical for 300 further ticks%s" % (
		"" if diverged < 0 else " — DIVERGED at +%d" % diverged))
	# convoys are part of the payload: an in-flight convoy must survive the rejoin, or its cargo
	# reappears (or vanishes) on arrival only for the client
	var s2: Variant = _fresh()
	# hub 0 is home and each hub buys ONE resource — ask the world, do not assume
	var hub_i := 1
	var buys: String = str(s2.regions[hub_i].offer.buys)
	s2.stock[s2.res_key(buys)] = 200
	var sent: Dictionary = s2.dispatch_convoy(hub_i, buys, 10)
	var j2: Variant = Sim.new()
	Persistence.restore(j2, Persistence.resume_payload(s2))
	ok(bool(sent.ok) and (j2.convoys as Array).size() == (s2.convoys as Array).size() and not (j2.convoys as Array).is_empty(),
		"an in-flight convoy survives the resume payload (%d carried)" % (j2.convoys as Array).size())


# The gap the live spike exposed and unit tests had missed: an IDLE pawn resumes fine either way,
# so the payload only proves itself when the pawn is mid-order. load_region nulls `action` (right
# for a save, fatal for a rejoin) — if this regresses, the joiner stands still while the server
# walks and their positions part company on the very next tick.
func _t_resume_carries_a_busy_pawn() -> void:
	var server: Variant = _fresh()
	var tree := _nearest_tree(server)
	server.order_gather(tree.x, tree.y)
	_advance(server, 12)                      # mid-walk: an action with a live path
	ok(server.player.action != null, "the server's pawn is mid-order (a walking gatherer)")
	var joiner: Variant = Sim.new()
	Persistence.restore(joiner, Persistence.resume_payload(server))
	ok(joiner.player.action != null and str(joiner.player.action.type) == str(server.player.action.type),
		"the pawn's live order survives the resume payload (%s)" % str(server.player.action.type))
	var diverged := -1
	for t in 200:
		server.update(DT)
		joiner.update(DT)
		_topup(server)
		_topup(joiner)
		if Persistence.world_hash(server) != Persistence.world_hash(joiner):
			diverged = t + 1
			break
	ok(diverged < 0, "a busy pawn keeps walking the SAME path on both sides%s" % (
		"" if diverged < 0 else " — DIVERGED at +%d tick(s)" % diverged))


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


func _t_resume_survives_the_wire() -> void:
	var server: Variant = _fresh()
	_advance(server, 250)
	var payload: Variant = JSON.parse_string(Snapshot.to_wire(Persistence.resume_payload(server)))
	ok(payload is Dictionary, "resume payload serializes to JSON")
	var joiner: Variant = Sim.new()
	Persistence.restore(joiner, payload)
	ok(Persistence.world_hash(joiner) == Persistence.world_hash(server),
		"resume payload is hash-exact AFTER a real wire round-trip (int->float coercion survived)")
	var ok_after := true
	for t in 200:
		server.update(DT)
		joiner.update(DT)
		_topup(server)
		_topup(joiner)
	ok_after = Persistence.world_hash(server) == Persistence.world_hash(joiner)
	ok(ok_after, "wire-restored client still identical after 200 further ticks")


func _t_chain_integrity() -> void:
	var sim: Variant = _fresh()
	var store := Persistence.store_new()
	var heads: Array = []
	for i in 3:
		_advance(sim, 100)
		heads.append(Persistence.store_commit(store, Persistence.serialize_region(sim)))
	ok(heads.size() == 3 and str(store.head) == str(heads[2]), "three commits chain onto one head")
	ok(Persistence.verify_store(store), "an untouched chain verifies")
	# tamper with the middle record's payload — the chain must notice
	var key: String = Persistence.region_key(LAT, LON)
	var rec: Dictionary = Persistence.store_get(store, key)
	ok(rec != null and not rec.is_empty(), "the committed record is retrievable by region key")
	var saved: Variant = rec.stock.duplicate(true)
	rec.stock[sim.res_key("wood")] = 999999
	ok(not Persistence.verify_record(rec), "a tampered record fails its own body hash")
	rec.stock = saved
	ok(Persistence.verify_record(rec), "restoring the payload makes the record verify again")


# The command envelope's idempotency ledger is what a rejoining client resumes its seq from
# (plan §4 -> §5 hook): resume at last_seq + 1 and the server accepts; replay an old seq and it
# is refused, so a reconnect storm cannot double-apply yesterday's intents.
func _t_seq_resume() -> void:
	var ib := Command.Inbox.new()
	var ctx := {"n": N}
	for s in 3:
		ib.accept(Command.make(1, s, "cancel_action", {}), ctx)
	ib.drain()
	var resume_at: int = ib.last_seq(1) + 1
	ok(resume_at == 3, "a reconnecting client resumes at last_seq + 1 (= %d)" % resume_at)
	ok(bool(ib.accept(Command.make(1, resume_at, "cancel_action", {}), ctx).ok), "the resumed seq is accepted")
	ok(ib.accept(Command.make(1, 1, "cancel_action", {}), ctx).reason == Command.R_STALE,
		"a replayed pre-disconnect intent is refused as stale (no double-apply on reconnect)")


# ---------------------------------------------------------------------------------------------
# spec 0010 W3a (REQ-0010-62/82/34): a rejoining client resumes an ON world MID-RAID — in the warning and in contact — hash-exact, and STAYS in
# lock-step through the contact, the raiders' spawn (the raid stream cursor resumed at the right place) and the breach. The capsule world needs
# the injected clock on BOTH sides (now_ms is an input, not state), so the joiner is told the server's instant before the payload lands.
# ---------------------------------------------------------------------------------------------
const CAP_T0 := 1800000000000
const CAP_GRACE := 259200001


func _fresh_on() -> Variant:
	var sim: Variant = Sim.new()
	sim.use_inventory = true
	sim.use_catalog = true
	sim.use_main_capsule = true
	sim.set_clock(CAP_T0)
	sim.new_game(WorldGen.generate_map(LAT, LON, N))
	sim.stock[sim.res_key("wood")] = 20000
	sim.stock[sim.res_key("stone")] = 20000
	var up: Dictionary = sim.upgrade_capsule()
	ok(bool(up.get("ok", false)), "setup: the ON server's capsule is upgraded to level 1 (first_upgrade_at > 0, OD-107)")
	sim.set_clock(CAP_T0 + CAP_GRACE)   # the 3-day grace (OD-66) is over: the gates are open
	return sim


func _on_joiner(server: Variant, wire: bool) -> Variant:
	var j: Variant = Sim.new()
	j.set_clock(int(server.now_ms))
	var payload: Dictionary = Persistence.resume_payload(server)
	var landed: bool = Persistence.restore(j, JSON.parse_string(Snapshot.to_wire(payload)) if wire else payload)
	ok(landed, "setup: the ON resume payload restores (load_error=%s)" % str(j.load_error))
	return j


func _t_resume_on_raid_states() -> void:
	for stage in ["warning", "contact"]:
		var server: Variant = _fresh_on()
		Director.apply(server, {"incident": "raid", "count": 3, "faction": "Тестові мародери"})
		server.update(DT)   # planned -> warning
		if stage == "contact":
			server.set_clock(int(server.capsule_raid.contact_at))
			server.update(DT)
			for i in 6:
				server.update(DT)
				_topup(server)
		ok(str(server.capsule_raid.state) == stage, "[%s] setup: the server raid machine is in `%s` (state %s)" % [stage, stage, str(server.capsule_raid.state)])
		var joiner: Variant = _on_joiner(server, false)
		ok(str(joiner.capsule_raid.state) == stage and int(joiner.capsule_raid.id) == int(server.capsule_raid.id) and joiner.enemies.size() == server.enemies.size(),
			"[%s] the rejoined machine is in the same state, same raid id, %d raiders carried" % [stage, joiner.enemies.size()])
		ok(Persistence.world_hash(joiner) == Persistence.world_hash(server), "[%s] resume ON mid-raid lands byte-identical to the server (REQ-0010-62/82)" % stage)
		ok(str(joiner.main_capsule.raid_rng_cursor) == str(server.main_capsule.raid_rng_cursor), "[%s] the raid stream cursor resumed at the same place (%s)" % [stage, str(joiner.main_capsule.raid_rng_cursor)])
		var diverged := -1
		for t in 150:
			if stage == "warning" and t == 3:
				var at: int = int(server.capsule_raid.contact_at)
				server.set_clock(at)
				joiner.set_clock(at)   # the same device instant on both sides: the contact (and the raiders' spawn cells) must land identically
			server.update(DT)
			joiner.update(DT)
			_topup(server)
			_topup(joiner)
			if Persistence.world_hash(server) != Persistence.world_hash(joiner):
				diverged = t + 1
				break
		ok(diverged < 0 and str(server.capsule_raid.state) == "contact", "[%s] server and rejoined client stay identical for 150 ticks through the contact%s" % [stage, "" if diverged < 0 else " — DIVERGED at +%d" % diverged])
		# the breach lands the same on both sides (stream cursor, consequence, immunity)
		MainCapsule.on_hit(server, 1.0e9)
		MainCapsule.on_hit(joiner, 1.0e9)
		server.update(DT)
		joiner.update(DT)
		ok(Persistence.world_hash(server) == Persistence.world_hash(joiner) and int(server.main_capsule.level) == 0 and int(joiner.main_capsule.level) == 0 and int(joiner.main_capsule.free_transport_token) == 1,
			"[%s] the breach lands identically: level 1 -> 0, one token, same immunity, same world_hash" % stage)
	# the WIRE (a JSON text): the capsule half — the record with its int64 instants and the raid machine — must land EXACT. (The whole-world hash is NOT
	# asserted here: decimal JSON drifts the odd hero float, e.g. a hypothermia severity by 1 ULP — the spec-0006 delta stream normalizes that; not a capsule field.)
	var s2: Variant = _fresh_on()
	Director.apply(s2, {"incident": "raid", "count": 3, "faction": "Тестові мародери"})
	s2.update(DT)
	var jw: Variant = _on_joiner(s2, true)
	ok(Persistence.content_hash(Persistence.serialize_region(jw).main_capsule) == Persistence.content_hash(Persistence.serialize_region(s2).main_capsule)
		and Persistence.content_hash(MainCapsule.serialize_raid(jw)) == Persistence.content_hash(MainCapsule.serialize_raid(s2)) and str(jw.capsule_raid.state) == "warning",
		"a warning-state ON resume keeps the capsule record (int64 instants as strings, stream cursor) and the raid machine EXACT after a real wire round-trip")

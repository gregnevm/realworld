# RealWorld — tests/run_orbit_tests.gd : spec 0011 (Орбіта, клони, геном) — core model, written FROM the REQ table.
# Run: godot --headless --path godot -s res://tests/run_orbit_tests.gd
# Scope (wave 0011-W1): sim/orbit.gd + safe_stock.gd + clone_tuning.gd as pure account-level models. Session/UI wiring and
# `use_orbit` come in later waves, so OFF stays byte-identical (REQ-0011-1/2) — guarded here by the file-level checks.
extends "res://tests/harness.gd"

const Orbit = preload("res://scripts/sim/orbit.gd")
const SafeStock = preload("res://scripts/sim/safe_stock.gd")
const Tuning = preload("res://scripts/sim/clone_tuning.gd")
const Stub = preload("res://scripts/sim/orbit_stub.gd")
const SessionScript = preload("res://scripts/session.gd")
const LifecycleScript = preload("res://scripts/ui/lifecycle.gd")
const Persistence = preload("res://scripts/persistence.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

const T0 := 1800000000000
const Q := 60000
const H := 3600000
const D := 86400000


func _init() -> void:
	print("== RealWorld orbit tests (spec 0011) ==")
	_t_safe_stock()
	_t_new_account()
	_t_choose_and_invariant()
	_t_base_clone()
	_t_death()
	_t_stats_determinism()
	_t_creation()
	_t_settle_consumption()
	_t_settle_idempotent()
	_t_settle_stages()
	_t_settle_clock_back()
	_t_roundtrip_and_hash()
	_t_stub_seam()
	_t_session_flags()
	_t_session_death_respawn()
	_t_session_save_restore()
	_t_session_ascend()
	_t_single_saved_at()
	_t_damaged_record_and_bio_table()
	_t_bag_ttl()
	_t_ascend_pack()
	_t_bag_kit_returns()
	_t_bag_ttl_capsule_only()
	_t_respawn_anchor_default()
	_t_tech_branch_and_sources()
	_t_reinforcement()
	_t_record_shape_and_survival()
	_t_genome_loot_and_synthesis()
	_t_tuning_and_base_rules()
	_t_determinism_scenario()
	await _t_death_screen()
	await _t_orbit_intro()
	_t_source_hygiene()
	finish()


func _t_safe_stock() -> void:
	var ss: Variant = SafeStock.new()
	ok(ss.slots.size() == 32, "REQ-0011-71: 32 slots")
	ok(int(ss.deposit("wood", 0)) == 0 and int(ss.deposit("wood", -5)) == 0, "REQ-0011-54: deposit 0 / negative rejected")
	ok(int(ss.deposit("wood", 120)) == 120 and ss.used_slots() == 3, "wood 120 = 3 stacks of 50/50/20")
	ok(int(ss.take("wood", 70)) == 70 and int(ss.count("wood")) == 50, "take 70 leaves 50")
	var full: Variant = SafeStock.new()
	var total: int = 0
	for i in 40:
		total += int(full.deposit("res%d" % i, 1))
	ok(total == 32 and full.used_slots() == 32, "REQ-0011-68: 33rd distinct stack does not fit (partial transfer)")
	ok(int(full.deposit("res0", 5)) == 5, "an open stack still accepts when slots are full")
	var rt: Variant = SafeStock.from_dict(JSON.parse_string(JSON.stringify(ss.to_dict())))
	ok(int(rt.count("wood")) == 50, "to_dict/from_dict survives a JSON round-trip")


func _t_new_account() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)
	var cl: Array = o["clones"]
	ok(cl.size() == 2, "REQ-0011-63: exactly 2 clones at start")
	ok(String(cl[0]["state"]) == "active" and String(cl[1]["state"]) == "sleeping", "REQ-0011-63: 1 active + 1 sleeping")
	ok(int(o["base_ready_at"]) <= T0, "REQ-0011-63: base cooldown does not block the first choice")
	ok(int(o["clone_counter"]) == 2, "REQ-0011-53: counter = clones made")
	ok(Orbit.check_invariants(o).is_empty(), "REQ-0011-11: invariants hold at start")


func _t_choose_and_invariant() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)
	ok(not bool(Orbit.choose(o, "c2")["ok"]), "cannot wake a second clone while one is active")
	Orbit.to_orbit(o)
	ok(Orbit.active_clone(o).is_empty(), "0 active on the Orbit screen is valid")
	ok(bool(Orbit.choose(o, "c2")["ok"]) and String(Orbit.active_clone(o)["id"]) == "c2", "REQ-0011-13: respawn = choose a sleeper")
	ok(Orbit.check_invariants(o).is_empty(), "REQ-0011-11: still ≤ 1 active")
	ok(not bool(Orbit.choose(o, "zz")["ok"]), "unknown clone refused")


func _t_base_clone() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)
	Orbit.to_orbit(o)
	var r: Dictionary = Orbit.claim_base_clone(o, T0)
	ok(bool(r["ok"]), "REQ-0011-14/59: base clone available at once")
	var base: Dictionary = (o["clones"] as Array)[Orbit.find(o, String(r["id"]))]
	ok(String(base["genome_type"]) == "" and int(base["stats"]["gather"]) == 1000 and int(base["stats"]["ride"]) == 1000, "REQ-0011-61: flat stats, no genome")
	ok(int(o["base_ready_at"]) == T0 + Tuning.value("base_cooldown_ms"), "REQ-0011-60: cooldown 5 min from now")
	ok(String(Orbit.claim_base_clone(o, T0 + 1000)["reason"]) == "cooldown", "REQ-0011-60: second claim inside 5 min refused")
	var o2: Dictionary = Orbit.new_account(7, T0)
	Orbit.claim_base_clone(o2, T0)
	var late: Dictionary = Orbit.claim_base_clone(o2, T0 + 300000)
	ok(bool(late["ok"]), "claim after cooldown (3 → 4 clones)")
	ok(String(Orbit.claim_base_clone(o2, T0 + 700000)["reason"]) == "roster_full", "roster full refuses the base clone")
	var o3: Dictionary = Orbit.new_account(7, T0)
	for c in (o3["clones"] as Array).duplicate():
		Orbit.on_death(o3, String(c["id"]), "test", T0)
	ok((o3["clones"] as Array).is_empty() and bool(Orbit.claim_base_clone(o3, T0)["ok"]), "REQ-0011-14: empty roster is never a softlock")
	var o4: Dictionary = Orbit.new_account(7, T0)
	o4["last_seen_now"] = T0 + 10 * Q
	ok(String(Orbit.claim_base_clone(o4, T0)["reason"]) == "clock_back", "REQ-0011-22: clock rolled back does not claim")


func _t_death() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)
	var r: Dictionary = Orbit.on_death(o, "c1", "cold", T0 + 2 * H, [3, 4], "r1")
	ok(bool(r["ok"]) and Orbit.find(o, "c1") < 0, "REQ-0011-12: the clone is removed")
	var ld: Dictionary = o["last_death"]
	ok(String(ld["clone_id"]) == "c1" and String(ld["cause"]) == "cold" and int(ld["lived_real_sec"]) == 7200, "REQ-0011-17: last_death with real-time «lived»")
	ok(not bool(Orbit.on_death(o, "c1", "cold", T0 + 3 * H)["ok"]), "REQ-0011-12: on_death idempotent by clone_id")
	ok(int(o["clone_counter"]) == 2, "REQ-0011-53: counter does not decrease on death")
	ok(Orbit.find(o, "c2") >= 0, "the other clone is untouched")


func _t_stats_determinism() -> void:
	var a: Dictionary = Orbit.derive_stats(11, 5, {"n1": 2}, "builder", false)
	var b: Dictionary = Orbit.derive_stats(11, 5, {"n1": 2}, "builder", false)
	ok(a == b, "REQ-0011-16: same inputs → identical clone")
	var plain: Dictionary = Orbit.derive_stats(11, 5, {"n1": 2}, "", false)
	ok(int(a["build"]) - int(plain["build"]) == Tuning.value("genome_start_permille"), "REQ-0011-70: genome gives +10% on its axis only")
	ok(int(a["gather"]) == int(plain["gather"]) and int(a["ride"]) == int(plain["ride"]), "REQ-0011-70: other axes unchanged")
	ok(int(Orbit.derive_stats(11, 5, {}, "", true)["gather"]) == 1000, "REQ-0011-61: base clone ignores tech/genome")
	ok(Tuning.GENOMES.size() == 3, "REQ-0011-69: three genome types, from data")


func _t_creation() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)
	ok(String(Orbit.begin_creation(o, "builder", T0)["reason"]) == "no_genome", "creation needs a genome")
	Orbit.add_genome(o, "builder", 1)
	ok(String(Orbit.begin_creation(o, "builder", T0)["reason"]) == "no_bio", "…and bio")
	o["safe_stock"].deposit("food", 12)
	var r: Dictionary = Orbit.begin_creation(o, "builder", T0)
	ok(bool(r["ok"]), "REQ-0011-15: creation starts")
	ok(Orbit.genome_count(o, "builder") == 0 and int(o["safe_stock"].count("food")) == 2, "genome (account counter, OD-152) + 10 bio (safe stock) spent")
	ok(Orbit.collect_ready(o, T0 + 11 * H) == 0, "not ready before ~12 h")
	ok(Orbit.collect_ready(o, T0 + 12 * H) == 1, "ready at 12 h real time")
	var made: Dictionary = (o["clones"] as Array)[(o["clones"] as Array).size() - 1]
	ok(String(made["genome_type"]) == "builder" and String(made["state"]) == "sleeping", "levelled clone arrives sleeping with its genome")


func _t_settle_consumption() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)
	o["safe_stock"].deposit("food", 10)
	var r: Dictionary = Orbit.settle(o, T0 + 2 * H)
	ok(int(o["safe_stock"].count("food")) == 10, "REQ-0011-19: settle is pure — the input is untouched")
	# 1 sleeper × 3 bio/h × 2 h = 6 units (taken as whole rations into the micro pool: 6 consumed, pool may hold ≤ 1 unit)
	var left: int = int(r["safe_stock"].count("food"))
	ok(left == 4 or left == 3, "REQ-0011-18: sleeper eats 3 bio/h from the safe stock (left %d)" % left)
	ok(String((r["clones"] as Array)[0]["state"]) == "active", "the active clone eats nothing from the safe stock")
	ok(int(r["saved_at"]) == T0 + 2 * H, "saved_at advanced by whole quanta")


func _t_settle_idempotent() -> void:
	var o: Dictionary = Orbit.new_account(9, T0)
	o["safe_stock"].deposit("food", 30)
	for t1 in [Q, 7 * Q, 100 * Q]:
		for t2 in [100 * Q, 300 * Q, 1000 * Q]:
			if t2 < t1:
				continue
			var direct: Dictionary = Orbit.settle(o, T0 + t2)
			var chain: Dictionary = Orbit.settle(Orbit.settle(o, T0 + t1), T0 + t2)
			ok(Orbit.account_hash(direct) == Orbit.account_hash(chain), "REQ-0011-20: settle(settle(o,%d),%d) == settle(o,%d)" % [t1, t2, t2])
	var odd: Dictionary = Orbit.settle(o, T0 + 90000)
	ok(int(odd["saved_at"]) == T0 + 90000, "REQ-0011-57: saved_at is the real moment (the quantum grid is absolute, no remainder to carry)")
	var odd2: Dictionary = Orbit.settle(Orbit.settle(o, T0 + 90000), T0 + 400000)
	ok(Orbit.account_hash(odd2) == Orbit.account_hash(Orbit.settle(o, T0 + 400000)), "REQ-0011-20/57: composition holds for ANY times on the absolute grid, not only aligned ones")
	ok(not _has_float(Orbit.to_dict(Orbit.settle(o, T0 + 5 * H))), "REQ-0011-20: no float in the account record")


func _t_settle_stages() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)   # no bio at all
	var r3: Dictionary = Orbit.settle(o, T0 + 2 * D)
	ok(String((r3["clones"] as Array)[1]["state"]) == "sleeping", "REQ-0011-21: before 3 days — still sleeping")
	var r4: Dictionary = _advance(o, T0 + 3 * D + 2 * Q)
	ok(String((r4["clones"] as Array)[1]["state"]) == "degrading", "REQ-0011-21: after 3 days without bio — degrading")
	# cap 24 h per call: reach day 7 by chained logins (each ≤ 24 h)
	var r: Dictionary = _advance(o, T0 + 8 * D)
	ok(Orbit.find(r, "c2") < 0, "REQ-0011-21: after 7 days without bio the sleeper dies for good")
	ok(String((r["last_death"] as Dictionary)["cause"]) == "bio_starvation", "REQ-0011-21: last_death cause = starvation in the Orbit")
	ok(Orbit.find(r, "c1") >= 0, "the active clone is not touched by the Orbit")
	ok(Orbit.check_invariants(r).is_empty(), "invariants hold after settle")
	var heal: Dictionary = _advance(o, T0 + 3 * D + 2 * Q)
	heal["safe_stock"].deposit("food", 20)
	var healed: Dictionary = Orbit.settle(heal, T0 + 3 * D + 3 * Q)
	ok(String((healed["clones"] as Array)[1]["state"]) == "sleeping", "OD-151: bio restores a degrading sleeper")


func _t_settle_clock_back() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)
	o["safe_stock"].deposit("food", 20)
	var fwd: Dictionary = Orbit.settle(o, T0 + 4 * H)
	var back: Dictionary = Orbit.settle(fwd, T0 + 1 * H)
	ok(int(back["saved_at"]) == int(fwd["saved_at"]) and int(back["last_seen_now"]) == int(fwd["last_seen_now"]), "REQ-0011-22: now < last_seen → nothing changes, marks never decrease")
	ok(int(back["safe_stock"].count("food")) == int(fwd["safe_stock"].count("food")), "REQ-0011-22: rolled-back clock does not consume or restore")
	var merged: Dictionary = Orbit.monotone_merge(fwd, {"saved_at": 5, "last_seen_now": 5, "base_ready_at": 1})
	ok(int(merged["saved_at"]) == int(fwd["saved_at"]) and int(merged["last_seen_now"]) == int(fwd["last_seen_now"]) and int(merged["base_ready_at"]) == 1, "REQ-0011-22: monotone merge")
	var capped: Dictionary = Orbit.settle(o, T0 + 30 * D)
	ok(int(capped["saved_at"]) == T0 + 30 * D, "OD-49: a gap over 24 h is capped, then saved_at jumps to now")


func _t_roundtrip_and_hash() -> void:
	var o: Dictionary = Orbit.new_account(5, T0)
	o["safe_stock"].deposit("food", 9)
	Orbit.on_death(o, "c2", "cold", T0 + H)
	var h1: String = Orbit.account_hash(o)
	var back: Dictionary = Orbit.from_dict(JSON.parse_string(JSON.stringify(Orbit.to_dict(o))))
	ok(Orbit.account_hash(back) == h1, "REQ-0011-36/38: JSON round-trip keeps account_hash")
	ok(Orbit.account_hash(Orbit.new_account(5, T0)) == Orbit.account_hash(Orbit.new_account(5, T0)), "REQ-0011-38: same seed and actions → same hash")
	ok(Orbit.account_hash(Orbit.new_account(5, T0)) != Orbit.account_hash(Orbit.new_account(6, T0)), "different account_seed → different hash")
	ok(h1.length() == 16, "account_hash is 64 bits hex")


func _t_stub_seam() -> void:
	var o: Dictionary = Orbit.new_account(7, T0)
	ok(int((o["safe_stock"] as RefCounted).call("deposit", "wood", 10)) == 10, "orbit_stub duck-typing: SafeStock.deposit(res, n) -> accepted")


func _new_session(orbit_on: bool) -> Variant:
	var s: Variant = SessionScript.new()
	s.use_inventory = true
	s.use_orbit = orbit_on
	s.autosave = false
	return s


func _t_session_flags() -> void:
	var bad: Variant = SessionScript.new()
	bad.use_orbit = true   # use_inventory stays false
	ok(not bool(bad.start(50.45, 30.52, "Київ", T0)) and String(bad.last_error) == "orbit_needs_inventory", "REQ-0011-3: use_orbit without use_inventory is refused with a reason")
	ok(bad.sim == null, "…and no world is left behind")
	var off: Variant = _new_session(false)
	ok(bool(off.start(50.45, 30.52, "Київ", T0)) and off.orbit == null, "REQ-0011-1: OFF — no orbit record at all")
	var on: Variant = _new_session(true)
	ok(bool(on.start(50.45, 30.52, "Київ", T0)) and on.orbit != null, "ON — account record is created with the session")
	ok((on.orbit["clones"] as Array).size() == 2, "REQ-0011-63 through Session: 2 clones")
	ok(int(on.orbit["account_seed"]) == int(WorldGen.hash_seed(50.45, 30.52)), "REQ-0011-53: account_seed comes from outside (the coordinate hash), not from an Orbit RNG")


func _t_session_death_respawn() -> void:
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	var first: String = String(Orbit.active_clone(s.orbit)["id"])
	s.sim.dead = true
	s.sim.last_death = {"cause": "cold", "day": 1, "born": 1}
	s.respawn()
	ok(Orbit.find(s.orbit, first) < 0, "REQ-0011-12: the dead clone left the roster")
	ok(String((s.orbit["last_death"] as Dictionary)["cause"]) == "cold", "REQ-0011-52: last_death is in the account record")
	ok(String(Orbit.active_clone(s.orbit)["id"]) != first and not s.sim.dead, "REQ-0011-13: the sleeper took over, the world lives again")
	# second death: the roster is empty → the free base clone; third right away → cooldown, world stays dead
	var second: String = String(Orbit.active_clone(s.orbit)["id"])
	s.sim.dead = true
	s.sim.last_death = {"cause": "raid", "day": 1, "born": 1}
	s.respawn()
	ok(String(Orbit.active_clone(s.orbit)["id"]) != second, "REQ-0011-14: empty roster → the free base clone")
	var base: String = String(Orbit.active_clone(s.orbit)["id"])
	s.sim.dead = true
	s.sim.last_death = {"cause": "raid", "day": 1, "born": 1}
	s.respawn()
	ok(Orbit.find(s.orbit, base) < 0 and String(s.last_error) == "orbit_cooldown" and s.sim.dead, "REQ-0011-60: inside the 5-min cooldown the world stays dead, with a reason")
	s.sim.set_clock(T0 + 301000)
	s.respawn()
	ok(not s.sim.dead and not Orbit.active_clone(s.orbit).is_empty(), "after the cooldown the base clone returns")
	ok(Orbit.check_invariants(s.orbit).is_empty(), "REQ-0011-11: invariants after the chain of deaths")


func _t_session_save_restore() -> void:
	var path: String = "user://orbit_test_save.json"
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	s.orbit["safe_stock"].deposit("food", 12)
	ok(s.save_game(path), "save with orbit ON")
	var txt: String = FileAccess.get_file_as_string(path)
	ok(txt.find('"orbit"') >= 0, "REQ-0011-36: the orbit record is in the account layer of the save")
	var r: Variant = SessionScript.new()
	ok(r.restore_game(path, T0 + 2 * H) and r.use_orbit and r.orbit != null, "restore brings the orbit back and flips use_orbit")
	ok(int(r.orbit["safe_stock"].count("food")) < 12, "REQ-0011-19/57: login settles the sleeper's rations")
	var off: Variant = _new_session(false)
	off.start(50.45, 30.52, "Київ", T0)
	off.save_game(path)
	ok(FileAccess.get_file_as_string(path).find('"orbit"') < 0, "REQ-0011-2: OFF save has no orbit key")
	var r2: Variant = SessionScript.new()
	r2.restore_game(path, T0)
	ok(not r2.use_orbit and r2.orbit == null, "an OFF save restores OFF when the build flag is off too")
	var r3: Variant = SessionScript.new()
	r3.use_orbit = true
	ok(r3.restore_game(path, T0) and r3.orbit != null, "REQ-0011-37: an old save + build flag ON migrates into an Orbit")
	var cl: Array = r3.orbit["clones"]
	ok(cl.size() == 1 and String(cl[0]["state"]) == "active" and int(r3.orbit["clone_counter"]) == 1, "REQ-0011-37: exactly ONE active clone (not the base clone, not the 2-clone start)")
	r3.save_game(path)
	var r4: Variant = SessionScript.new()
	r4.restore_game(path, T0)
	ok(r4.orbit != null and (r4.orbit["clones"] as Array).size() == 1 and Orbit.account_hash(r4.orbit) == Orbit.account_hash(r3.orbit), "REQ-0011-37: migration is idempotent (second load keeps the same Orbit)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _t_session_ascend() -> void:
	var off: Variant = _new_session(false)
	off.start(50.45, 30.52, "Київ", T0)
	ok(String(off.orbit_ascend()["reason"]) == "no_orbit", "REQ-0011-8: no Orbit → no ascend")
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	var r: Dictionary = s.orbit_ascend()
	ok(not bool(r["ok"]), "REQ-0011-8: without a capsule (use_main_capsule OFF) the ascend is refused (%s)" % String(r.get("reason", "")))


func _t_bag_ttl() -> void:
	var InvMod: Variant = load("res://scripts/sim/inventory.gd")
	var off: Variant = _new_session(false)
	off.start(50.45, 30.52, "Київ", T0)
	InvMod.drop_bag(off.sim)
	ok(off.sim.bags.size() == 1 and not (off.sim.bags[0] as Dictionary).has("expires_at") and not (off.sim.bags[0] as Dictionary).has("owner_clone_id"), "REQ-0011-56: OFF bag has no TTL keys (byte-for-byte)")
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	var cid: String = String(Orbit.active_clone(s.orbit)["id"])
	s.sim.player.items = ["axe"]
	InvMod.drop_bag(s.sim)
	var bag: Dictionary = s.sim.bags[0]
	ok((bag["items"] as Array) == ["axe"] and (s.sim.player.items as Array).is_empty(), "REQ-0011-32: the Orbit bag carries the kit (items/equipped) and the body is left without it")
	ok(int(bag["expires_at"]) == T0 + D and String(bag["owner_clone_id"]) == cid, "REQ-0011-33: expires_at = now + 24 h, owner_clone_id is a mere label")
	s.sim.set_clock(T0 + D - 1000)
	InvMod.pickup_bags(s.sim, {"px": -50.0, "py": -50.0})
	ok(s.sim.bags.size() == 1, "REQ-0011-34: the bag lives until its TTL (actor argument accepted, far away)")
	s.sim.set_clock(T0 + D)
	InvMod.pickup_bags(s.sim, {"px": -50.0, "py": -50.0})
	ok(s.sim.bags.is_empty(), "REQ-0011-33/OD-59: the bag expires at 24 h of real time")


func _t_genome_loot_and_synthesis() -> void:
	var hits: int = 0
	var kinds: Dictionary = {}
	for x in 100:
		for y in 40:
			var g: String = Orbit.genome_loot("50.45,30.52", x, y, 7)
			if g != "":
				hits += 1
				kinds[g] = true
	ok(hits > 40 and hits < 220, "REQ-0011-28: loot is rare (~3%% of 4000 cells, got %d)" % hits)
	ok(kinds.size() == 3, "REQ-0011-28/69: all three genome types occur")
	ok(Orbit.genome_loot("a", 3, 4, 1) == Orbit.genome_loot("a", 3, 4, 1), "REQ-0011-28: pure function of (coord, tile, salt)")
	var o: Dictionary = Orbit.new_account(7, T0)
	ok(String(Orbit.begin_synthesis(o, T0)["reason"]) == "no_bio", "REQ-0011-29: synthesis needs bio")
	o["safe_stock"].deposit("food", 35)
	ok(bool(Orbit.begin_synthesis(o, T0)["ok"]) and int(o["safe_stock"].count("food")) == 5, "synthesis takes 30 bio")
	ok(String(Orbit.begin_synthesis(o, T0)["reason"]) == "busy", "one job at a time")
	ok(String(Orbit.collect_synthesis(o, T0 + H)["reason"]) == "not_ready", "not ready before 6 h of real time")
	var rt: Dictionary = Orbit.from_dict(JSON.parse_string(JSON.stringify(Orbit.to_dict(o))))
	var done: Dictionary = Orbit.collect_synthesis(rt, T0 + 6 * H)
	ok(bool(done["ok"]) and Orbit.genome_count(rt, String(done["genome"]).trim_prefix("genome:")) == 1, "REQ-0011-29: genome arrives in the account counter (job survives save/load)")


# REQ-0011-43/59/62/73: tuning provider is swappable; the base clone is offered in every roster state and inherits nothing; no grants.
func _t_tuning_and_base_rules() -> void:
	ok(Tuning.value("roster_slots") == 4, "REQ-0011-43: default provider = local table")
	Tuning.provider = func(key: String) -> Variant: return 6 if key == "roster_slots" else null
	ok(Tuning.value("roster_slots") == 6 and Tuning.value("base_cooldown_ms") == 300000, "REQ-0011-43: a provider overrides single keys, the rest falls back")
	Tuning.provider = null
	ok(Tuning.value("roster_slots") == 4, "REQ-0011-43: provider removed → default again")
	var txt: String = FileAccess.get_file_as_string("res://scripts/sim/clone_tuning.gd")
	ok(not ("deposit" in txt) and not ("safe_stock" in txt), "REQ-0011-73: the tuning interface has no way to hand out resources")
	# REQ-0011-59: base clone in every roster state (empty / all degrading / no bio)
	var o: Dictionary = Orbit.new_account(3, T0)
	for c in o["clones"]:
		(c as Dictionary)["state"] = "degrading"
	Orbit.to_orbit(o)
	o["clones"] = (o["clones"] as Array).slice(0, 1)   # one degrading clone left, room for the base clone
	ok(bool(Orbit.claim_base_clone(o, T0)["ok"]), "REQ-0011-59: offered with degrading clones, no bio, no safe_stock")
	ok(int(o["safe_stock"].used_slots()) == 0, "REQ-0011-59: costs no bio/genome")
	# REQ-0011-62: the dead clone's skills do not pass on
	var p: Dictionary = Orbit.new_account(3, T0)
	((p["clones"] as Array)[0]["pawn"] as Dictionary)["skills"] = {"gather": 9}
	Orbit.on_death(p, "c1", "cold", T0 + H)
	Orbit.claim_base_clone(p, T0 + H)
	var base: Dictionary = (p["clones"] as Array)[(p["clones"] as Array).size() - 1]
	ok((base["pawn"]["skills"] as Dictionary).is_empty(), "REQ-0011-62: skills of the dead clone do not transfer to the base clone")


# REQ-0011-38/1: «орбіта ON, N тіків, смерть, респавн» — twin runs agree on world_hash AND account_hash; the Orbit does not leak into world_hash.
func _run_scenario(orbit_on: bool) -> Array:
	var s: Variant = _new_session(orbit_on)
	s.start(50.45, 30.52, "Київ", T0)
	for i in 120:
		s.sim.update(0.1)
	var mid: String = Persistence.world_hash(s.sim)
	if orbit_on:
		s.sim.dead = true
		s.sim.last_death = {"cause": "cold", "day": 1, "born": 1}
		s.respawn()
		for i in 60:
			s.sim.update(0.1)
	return [mid, Persistence.world_hash(s.sim), Orbit.account_hash(s.orbit) if orbit_on else ""]


func _t_determinism_scenario() -> void:
	var a: Array = _run_scenario(true)
	var b: Array = _run_scenario(true)
	ok(a == b, "REQ-0011-38: twin orbit runs (ticks → death → respawn → ticks) agree on world_hash and account_hash")
	var off: Array = _run_scenario(false)
	ok(String(a[0]) == String(off[0]), "REQ-0011-1/38: before any death an Orbit session has the SAME world_hash as an OFF session (the Orbit is outside world_hash)")


# REQ-0011-6/13/41/42/51: the death screen under the Orbit — a clone choice, signals only, no «new survivor» texts.
func _t_death_screen() -> void:
	var ds: Variant = LifecycleScript.DeathScreen.new()
	get_root().add_child(ds)
	await process_frame
	ds.bind({"cause": "переохолодження", "lived": 1, "inventory": true, "bag_items": 3})
	var rows: Array = [{"id": "c2", "state": "sleeping", "genome": ""}, {"id": "c5", "state": "degrading", "genome": "Будівельник"}]
	ds.bind_orbit(rows, 0)
	ds.bind_orbit(rows, 0)   # idempotent: bind() runs every frame
	var box: Variant = ds._orbit_box
	ok(box.visible and box.get_child_count() == 3, "REQ-0011-13: one button per sleeping clone + the free base clone (no duplicates after a re-bind)")
	ok(not ds._btn.visible, "REQ-0011-42: the old single «Новий виживальник» button is hidden")
	var txt: String = ""
	for ch in box.get_children():
		txt += String((ch as Button).text) + " "
	ok("⚠" in txt and "😴" in txt, "REQ-0011-23: stage is shown by an icon, not by colour only")
	ok(not ("Новий виживальник" in String(ds._what.text)) and not ("лишаються" in String(ds._what.text)), "REQ-0011-42: no old «Новий виживальник»/«Поселення й склад лишаються» texts")
	var got: Array = []
	ds.clone_chosen.connect(func(cid: String) -> void: got.append(cid))
	(box.get_child(1) as Button).pressed.emit()
	(box.get_child(2) as Button).pressed.emit()
	ok(got == ["c5", ""], "REQ-0011-6: the screen only emits the choice (clone id / empty = base clone)")
	ds.bind_orbit(rows, 0, {"lived_real_sec": 7300, "cause": "cold"})
	ok("Прожито: 2 год" in String(ds._what.text) and "Причина" in String(ds._what.text) and "втрачено назавжди" in String(ds._what.text), "REQ-0011-51: the first Orbit frame after a death shows cause, how long the clone lived (real units) and what is lost")
	ds.bind_orbit(rows, 120)
	ok((box.get_child(2) as Button).disabled and "120" in (box.get_child(2) as Button).text, "REQ-0011-60: base clone shows the cooldown seconds and is disabled")
	ds.queue_free()


# REQ-0011-7/8: from the BACKPACK, only near the capsule; partial transfer; far/dead/no-orbit refused.
func _t_bag_kit_returns() -> void:
	var InvMod: Variant = load("res://scripts/sim/inventory.gd")
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	s.sim.player.items = ["axe"]
	InvMod.drop_bag(s.sim)
	var b: Dictionary = s.sim.bags[0]
	var px: float = float(b["x"]) + 0.5
	var py: float = float(b["y"]) + 0.5
	var finder: Dictionary = {"px": px, "py": py, "items": []}
	InvMod.pickup_bags(s.sim, finder)
	ok(s.sim.bags.is_empty(), "REQ-0011-32: anyone walking over the bag picks it up (OD-91)")
	ok((finder["items"] as Array) == ["axe"], "REQ-0011-32: the kit goes to whoever picked the bag up (not bound to the owner)")


# REQ-0010-116/118 (OD-158): TTL 24 h under `use_main_capsule` WITHOUT the Orbit; the expiry hands the contents to the bag_expired seam exactly once.
func _t_bag_ttl_capsule_only() -> void:
	var InvMod: Variant = load("res://scripts/sim/inventory.gd")
	var s: Variant = SessionScript.new()
	s.use_inventory = true
	s.use_catalog = true
	s.use_main_capsule = true
	s.autosave = false
	s.start(50.45, 30.52, "Київ", T0)
	if s.sim == null:
		ok(false, "REQ-0010-116: precondition — a capsule world (%s)" % String(s.last_error))
		return
	ok(s.orbit == null and int(s.sim.bag_ttl_ms) == 86400000, "REQ-0010-116: capsule ON, Orbit OFF — the bag TTL is 24 h")
	InvMod.drop_bag(s.sim)
	if s.sim.bags.is_empty():
		InvMod.add(s.sim, "wood", 3)
		InvMod.drop_bag(s.sim)
	var bag: Dictionary = s.sim.bags[0]
	ok(int(bag["expires_at"]) == T0 + D, "REQ-0010-116: expires_at = death moment + 86 400 000 ms")
	var calls: Array = []
	InvMod.expired_sink = func(items: Array, pos: Vector2i) -> void: calls.append([items.size(), pos])
	s.sim.set_clock(T0 + D)
	InvMod.pickup_bags(s.sim, {"px": -50.0, "py": -50.0})
	InvMod.pickup_bags(s.sim, {"px": -50.0, "py": -50.0})
	InvMod.expired_sink = Callable()
	ok(calls.size() == 1 and s.sim.bags.is_empty(), "REQ-0010-118: the expired bag reaches the bag_expired seam exactly once and is gone")
	var off: Variant = SessionScript.new()
	off.use_inventory = true
	off.autosave = false
	off.start(50.45, 30.52, "Київ", T0)
	ok(int(off.sim.bag_ttl_ms) == 0, "REQ-0010-116: capsule OFF and Orbit OFF — no TTL, the bag is byte-for-byte as before")


# REQ-0011-55: the landing goes to the CAPSULE's anchor (any region); without a home (`has_home=false`) there is an explicit default, not a crash.
func _t_respawn_anchor_default() -> void:
	var s: Variant = SessionScript.new()
	s.use_inventory = true
	s.use_catalog = true
	s.use_main_capsule = true
	s.use_orbit = true
	s.autosave = false
	s.start(50.45, 30.52, "Київ", T0)
	if s.sim == null:
		ok(false, "REQ-0011-55: precondition — a capsule + Orbit world (%s)" % String(s.last_error))
		return
	s.has_home = false
	s.sim.dead = true
	s.sim.last_death = {"cause": "cold", "day": 1, "born": 1}
	s.respawn()
	ok(not s.sim.dead, "REQ-0011-55: with has_home=false the respawn still lands (explicit default, no crash)")
	var cap: Array = s.sim.main_capsule.tile
	var d: float = Vector2(float(s.sim.player.px), float(s.sim.player.py)).distance_to(Vector2(float(cap[0]) + 0.5, float(cap[1]) + 0.5))
	ok(d < 6.0, "REQ-0011-55: the clone lands next to the capsule's anchor (%.1f tiles)" % d)


# REQ-0011-9/27/30/65/7: the Orbit's own upgrade branch; genome producers; the 4 genome sources; catch-up harms nobody; the safe-stock tripwire.
func _t_tech_branch_and_sources() -> void:
	var o: Dictionary = Orbit.new_account(4, T0)
	ok(Orbit.slots(o) == 4 and Orbit.create_ms(o) == 43200000, "REQ-0011-9: base — 4 clone slots, ~12 h creation (OD-94)")
	o["safe_stock"].deposit("food", 100)
	var u1: Dictionary = Orbit.upgrade_tech(o, "clone_slots")
	ok(bool(u1["ok"]) and Orbit.slots(o) == 5 and int(u1["paid"]) == 20, "REQ-0011-9: «clone_slots» L1 costs 20 bio and adds a slot")
	ok(bool(Orbit.upgrade_tech(o, "clone_slots")["ok"]) and int(o["safe_stock"].count("food")) == 40, "…L2 costs 40 bio (taken from the safe stock)")
	ok(String(Orbit.upgrade_tech(o, "clone_slots")["reason"]) == "no_bio", "…L3 (60 bio) is refused with 40 left")
	ok(String(Orbit.upgrade_tech(o, "nope")["reason"]) == "bad_node", "an unknown node is refused")
	var q: Dictionary = Orbit.new_account(4, T0)
	q["safe_stock"].deposit("food", 100)
	Orbit.upgrade_tech(q, "create_speed")
	ok(Orbit.create_ms(q) == 38880000, "REQ-0011-9: «create_speed» L1 — 10 % faster creation")
	var base: Dictionary = Orbit.new_account(4, T0)
	base["safe_stock"].deposit("food", 100)
	var cheap: Dictionary = Orbit.new_account(4, T0)
	cheap["safe_stock"].deposit("food", 100)
	(cheap["tech"] as Dictionary)["sleeper_upkeep"] = 3
	var eaten_base: int = 100 - int(Orbit.settle(base, T0 + 20 * H)["safe_stock"].count("food"))
	var eaten_cheap: int = 100 - int(Orbit.settle(cheap, T0 + 20 * H)["safe_stock"].count("food"))
	ok(eaten_cheap < eaten_base, "REQ-0011-9: «sleeper_upkeep» lowers the sleeper's bio consumption (%d < %d)" % [eaten_cheap, eaten_base])
	# REQ-0011-27: genome has exactly two producers in code — the synthesis (collect_synthesis) and, by the loot function's id, nobody writes it elsewhere
	var offenders: Array = []
	var dirs: Array = ["res://scripts"]
	while not dirs.is_empty():
		var d: String = String(dirs.pop_back())
		for sub in DirAccess.get_directories_at(d):
			dirs.append(d + "/" + String(sub))
		for f in DirAccess.get_files_at(d):
			if String(f).ends_with(".gd") and String(f) != "orbit.gd":
				if FileAccess.get_file_as_string(d + "/" + String(f)).contains("add_genome("):
					offenders.append(String(f))
	ok(offenders.is_empty(), "REQ-0011-27: nothing outside orbit.gd writes the genome counter (%s)" % str(offenders))
	# REQ-0011-30: the 4 genome sources of OD-34, two of them deferred
	var deferred: int = 0
	for k in Tuning.GENOME_SOURCES:
		if String(Tuning.GENOME_SOURCES[k]) == "deferred":
			deferred += 1
	ok(Tuning.GENOME_SOURCES.size() == 4 and deferred == 2, "REQ-0011-30: the 4 OD-34 sources are listed, 2 are `deferred`")
	# REQ-0011-65: a catch-up changes only the Orbit — the hero and the world are untouched
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	var path: String = "user://orbit_catchup_test.json"
	s.save_game(path)
	var hp: float = float(s.sim.player.hp)
	var h0: String = Persistence.world_hash(s.sim)
	var r: Variant = SessionScript.new()
	r.restore_game(path, T0 + 20 * H)
	ok(float(r.sim.player.hp) == hp and Persistence.world_hash(r.sim) == h0, "REQ-0011-65: the login catch-up leaves the hero's HP and the world hash untouched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _t_ascend_pack() -> void:
	var InvMod: Variant = load("res://scripts/sim/inventory.gd")
	var s: Variant = _new_session(true)
	s.use_main_capsule = true
	s.use_catalog = true
	s.start(50.45, 30.52, "Київ", T0)
	if s.sim == null or (s.sim.main_capsule as Dictionary).is_empty():
		ok(false, "REQ-0011-8: precondition — a capsule world (%s)" % String(s.last_error))
		return
	InvMod.add(s.sim, "wood", 30)
	var cap: Array = s.sim.main_capsule.tile
	s.sim.player.px = float(cap[0]) + 1.0
	s.sim.player.py = float(cap[1]) + 0.5
	var near: Dictionary = s.orbit_ascend_pack(["wood"])
	ok(bool(near["ok"]) and int(near["moved"]["wood"]) >= 30, "REQ-0011-8: near the capsule the backpack stack goes to the safe stock")
	ok(InvMod.count(s.sim, "wood") == 0 and int(s.orbit["safe_stock"].count("wood")) >= 30, "…and leaves the backpack (moved, not copied)")
	InvMod.add(s.sim, "stone", 5)
	var stone_before: int = InvMod.count(s.sim, "stone")
	s.sim.player.px = float(cap[0]) + 30.0
	ok(String(s.orbit_ascend_pack(["stone"])["reason"]) == "far", "REQ-0011-8: far from the capsule the ascend is refused")
	ok(InvMod.count(s.sim, "stone") == stone_before, "…and nothing is lost")
	s.sim.player.px = float(cap[0]) + 1.0
	ok(String(s.orbit_ascend_pack(["iron_ore"])["reason"]) == "empty", "an id the backpack does not hold moves nothing")
	s.sim.dead = true
	ok(String(s.orbit_ascend_pack(["stone"])["reason"]) == "dead", "a dead hero cannot ascend")


# REQ-0011-72 / REQ-0010-28 (OD-154): reinforcement from the Orbit — window, once, price 10 % of the current level's investment, payload from the safe stock.
func _t_reinforcement() -> void:
	var s: Variant = _new_session(true)
	s.use_main_capsule = true
	s.use_catalog = true
	s.start(50.45, 30.52, "Київ", T0)
	if s.sim == null or (s.sim.main_capsule as Dictionary).is_empty():
		ok(false, "REQ-0011-72: precondition — a capsule world (%s)" % String(s.last_error))
		return
	var sim: Variant = s.sim
	var Stub: Variant = load("res://scripts/sim/orbit_stub.gd")
	var ss: Variant = s.orbit["safe_stock"]
	ss.deposit("wood", 50)
	sim.main_capsule["level"] = 1
	sim.main_capsule["invested"] = {"1": {"wood": 45}}
	sim._stock_add("wood", 100)
	ok(String(Stub.call_reinforcement(sim, ss)["reason"]) == "no_window", "REQ-0011-72: outside the post-breach window the call is refused")
	ok(not Stub.reinforcement_offered(sim, ss), "…and the panel does not offer it")
	sim.main_capsule["immune_until"] = int(sim.now_ms) + 86400000
	ok(Stub.reinforcement_offered(sim, ss), "inside the window, with a payload in the safe stock — offered")
	var before: int = int(sim.res_amount("wood"))
	var r: Dictionary = Stub.call_reinforcement(sim, ss)
	ok(bool(r["ok"]), "REQ-0011-72: the call succeeds inside the window")
	ok(int(r["paid"]["wood"]) == 5, "price = 10%% of the current level's investment, rounded up (45 -> 5), got %s" % str(r["paid"]))
	ok(int(r["delivered"]["wood"]) == 20, "payload = up to 20 wood from the Orbit")
	ok(int(sim.res_amount("wood")) == before - 5 + 20 and int(ss.count("wood")) == 30, "base stock: -price +payload; safe stock: -payload")
	ok(int(sim.main_capsule.reinforcement_used) == 1 and String(Stub.call_reinforcement(sim, ss)["reason"]) == "no_window", "REQ-0010-113: once per window")
	ok(not Stub.reinforcement_offered(sim, ss), "…and no longer offered")
	sim.main_capsule["reinforcement_used"] = 0
	sim.main_capsule["invested"] = {"1": {"wood": 99999}}
	var h0: String = var_to_str(sim.stock)
	ok(String(Stub.call_reinforcement(sim, ss)["reason"]) == "no_funds" and var_to_str(sim.stock) == h0 and int(sim.main_capsule.reinforcement_used) == 0, "an unaffordable price is refused atomically (no charge, no flag)")
	var empty: Variant = load("res://scripts/sim/safe_stock.gd").new()
	ok(String(Stub.call_reinforcement(sim, empty)["reason"]) == "orbit_empty", "an empty Orbit offers nothing")


# REQ-0011-5/41/66: the Orbit is the FIRST screen; one main button, no explanation wall; the screen only emits.
func _t_orbit_intro() -> void:
	var oi: Variant = LifecycleScript.OrbitIntro.new()
	get_root().add_child(oi)
	await process_frame
	var buttons: Array = []
	var stack: Array = [oi]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Button:
			buttons.append(n)
	ok(buttons.size() == 1 and String((buttons[0] as Button).text) == "Висадка", "REQ-0011-41: a new account sees exactly ONE main button")
	var fired: Array = []
	oi.landing_chosen.connect(func() -> void: fired.append(1))
	(buttons[0] as Button).pressed.emit()
	ok(fired.size() == 1, "REQ-0011-6: the screen emits a signal, it mutates nothing")
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	var path: String = "user://orbit_intro_save.json"
	s.save_game(path)
	var rows: Array = SessionScript.save_orbit_rows(path)
	ok(rows.size() == 2 and String(rows[0]["state"]) == "active", "REQ-0011-5: a continued session shows the saved roster (2 clones)")
	ok(SessionScript.save_orbit_rows("user://no_such_save.json").is_empty(), "no save -> new account preview")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	oi.queue_free()


# REQ-0011-4/10/35/64: the account record shape, the clone record shape, the safe stock surviving a death, the cooldown clock.
func _t_record_shape_and_survival() -> void:
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	for k in ["clones", "safe_stock", "tech", "account_seed", "clone_counter", "creating", "base_ready_at", "last_death"]:
		ok((s.orbit as Dictionary).has(k), "REQ-0011-4: the account record has `%s`" % k)
	var region: String = JSON.stringify(Persistence.resume_payload(s.sim))
	ok(region.find('"clones"') < 0 and region.find('"safe_stock"') < 0, "REQ-0011-4: the Orbit is account-level, NOT part of the region record")
	var c: Dictionary = (s.orbit["clones"] as Array)[0]
	for k in ["id", "state", "born_at", "pawn", "genome_type"]:
		ok(c.has(k), "REQ-0011-10: the clone record has `%s`" % k)
	for k in ["skills", "items", "equipped", "inv", "hand"]:
		ok((c["pawn"] as Dictionary).has(k), "REQ-0011-10: the clone pawn carries `%s` (PLAYER_FIELDS shape)" % k)
	ok(typeof(c["born_at"]) == TYPE_INT and String(c["state"]) in ["active", "sleeping", "degrading"], "REQ-0011-10: born_at is an int (UTC ms), state is one of the three stages")
	# REQ-0011-35: the safe stock is untouched by a death
	s.orbit["safe_stock"].deposit("wood", 30)
	s.sim.dead = true
	s.sim.last_death = {"cause": "cold", "day": 1, "born": 1}
	s.respawn()
	ok(int(s.orbit["safe_stock"].count("wood")) == 30, "REQ-0011-35: the safe stock is untouched after a death")
	# REQ-0011-64: the cooldown reads only the absolute `now` (the sim clock input), counting down in real seconds
	var o2: Variant = _new_session(true)
	o2.start(50.45, 30.52, "Київ", T0)
	Orbit.to_orbit(o2.orbit)
	Orbit.claim_base_clone(o2.orbit, T0)
	ok(o2.orbit_base_wait_s() == 300, "REQ-0011-64: right after the claim, 300 s of cooldown")
	o2.sim.set_clock(T0 + 100000)
	ok(o2.orbit_base_wait_s() == 200, "REQ-0011-64: the countdown follows the absolute clock only")


# REQ-0011-57 / REQ-0012-80: one saved_at — the Orbit is caught up to the SAVE moment, and a login settles only the gap after it.
func _t_single_saved_at() -> void:
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	s.orbit["safe_stock"].deposit("food", 50)
	s.orbit["safe_stock"].deposit("food", 50)
	s.orbit["safe_stock"].deposit("food", 50)
	s.orbit["safe_stock"].deposit("food", 50)
	var path: String = "user://orbit_saved_at_test.json"
	s.sim.set_clock(T0 + 30 * H)
	s.save_game(path)
	var left_at_save: int = int(s.orbit["safe_stock"].count("food"))
	ok(left_at_save <= 200 - 70 and left_at_save >= 200 - 74, "save settles up to the 24 h cap: ~72 rations eaten (left %d)" % left_at_save)
	var r: Variant = SessionScript.new()
	r.restore_game(path, T0 + 31 * H)
	var left_after: int = int(r.orbit["safe_stock"].count("food"))
	ok(left_at_save - left_after >= 2 and left_at_save - left_after <= 4, "login settles only the 1 h after the save (~3 rations), got %d" % (left_at_save - left_after))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# REQ-0011-36: a damaged orbit record never crashes a load (and migrates when the flag is ON); REQ-0011-24: the bio table is data.
func _t_damaged_record_and_bio_table() -> void:
	var path: String = "user://orbit_damaged_test.json"
	var s: Variant = _new_session(true)
	s.start(50.45, 30.52, "Київ", T0)
	s.save_game(path)
	var txt: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	for bad in ["garbage", {"clones": "nope"}, {"clones": [{"id": "c1", "state": "active"}, {"id": "c1", "state": "sleeping"}]}]:
		(parsed as Dictionary)["orbit"] = bad
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(parsed))
		f.close()
		var r: Variant = SessionScript.new()
		r.use_orbit = true
		ok(r.restore_game(path, T0) and r.orbit != null and (r.orbit["clones"] as Array).size() == 1, "REQ-0011-36: a damaged orbit record (%s) -> safe default (one active clone), no crash" % str(bad).left(24))
		var r2: Variant = SessionScript.new()
		ok(r2.restore_game(path, T0) and r2.orbit == null, "…and with the flag OFF the save still loads, without an Orbit")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ok(Tuning.is_bio("food") and Tuning.is_bio("wood") and Tuning.is_bio("water"), "REQ-0011-24: edible and renewable materials are bio")
	ok(not Tuning.is_bio("stone") and not Tuning.is_bio("scrap"), "REQ-0011-24/OD-84: stone/ore stay finite, not bio")


func _t_source_hygiene() -> void:
	for f in ["orbit.gd", "safe_stock.gd", "clone_tuning.gd"]:
		var txt: String = FileAccess.get_file_as_string("res://scripts/sim/" + f)
		ok(not ("Time.get_" in txt) and not ("randf" in txt) and not ("randi" in txt) and not ("RandomNumberGenerator" in txt), "REQ-0011-39: %s has no clock/RNG" % f)
		ok(not ("price" in txt.to_lower()) and not ("shop" in txt.to_lower()) and not ("USD" in txt), "REQ-0011-44: %s has no money talk" % f)


# chained logins, each within the 24 h catch-up cap
func _advance(o: Dictionary, to: int) -> Dictionary:
	var r: Dictionary = o
	var t: int = int(o["saved_at"])
	while t < to:
		t = mini(to, t + D)
		r = Orbit.settle(r, t)
	return r


func _has_float(v: Variant) -> bool:
	if typeof(v) == TYPE_FLOAT:
		return true
	if v is Dictionary:
		for k in v:
			if _has_float(v[k]):
				return true
	elif v is Array:
		for e in v:
			if _has_float(e):
				return true
	return false

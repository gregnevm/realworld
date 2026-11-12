# RealWorld — tests/run_orbit_tests.gd : spec 0011 (Орбіта, клони, геном) — core model, written FROM the REQ table.
# Run: godot --headless --path godot -s res://tests/run_orbit_tests.gd
# Scope (wave 0011-W1): sim/orbit.gd + safe_stock.gd + clone_tuning.gd as pure account-level models. Session/UI wiring and
# `use_orbit` come in later waves, so OFF stays byte-identical (REQ-0011-1/2) — guarded here by the file-level checks.
extends "res://tests/harness.gd"

const Orbit = preload("res://scripts/sim/orbit.gd")
const SafeStock = preload("res://scripts/sim/safe_stock.gd")
const Tuning = preload("res://scripts/sim/clone_tuning.gd")
const Stub = preload("res://scripts/sim/orbit_stub.gd")

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
	o["safe_stock"].deposit("genome:builder", 1)
	ok(String(Orbit.begin_creation(o, "builder", T0)["reason"]) == "no_bio", "…and bio")
	o["safe_stock"].deposit("food", 12)
	var r: Dictionary = Orbit.begin_creation(o, "builder", T0)
	ok(bool(r["ok"]), "REQ-0011-15: creation starts")
	ok(int(o["safe_stock"].count("genome:builder")) == 0 and int(o["safe_stock"].count("food")) == 2, "genome + 10 bio spent from the safe stock")
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
	ok(int(odd["saved_at"]) == T0 + Q, "the sub-quantum remainder stays in saved_at")
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
	ok(int(merged["saved_at"]) == int(fwd["saved_at"]) and int(merged["base_ready_at"]) == int(fwd["base_ready_at"]), "REQ-0011-22: monotone merge")
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

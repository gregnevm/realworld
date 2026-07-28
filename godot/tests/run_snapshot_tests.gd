# RealWorld — tests/run_snapshot_tests.gd : the spec 0006 §8.3 snapshot delta codec suite.
#
# Proves the wire works before any client renders from it: on a LIVE session, every tick's
# HudModel.snapshot() is delta-encoded against the previous one, pushed through a real JSON
# round-trip (the wire), applied on a simulated receiving side — and the reconstruction must
# match the sender's snapshot via Persistence.content_hash, which already canonicalizes the
# int→float / StringName→String / int-key→string-key coercions JSON introduces. Also prints the
# §8.3 measurement: full-snapshot vs delta payload bytes at tick cadence and at 1-in-5 cadence.
# Run: godot --headless --path godot -s res://tests/run_snapshot_tests.gd
extends "res://tests/harness.gd"

const Session = preload("res://scripts/session.gd")
const HudModel = preload("res://scripts/ui/hud_model.gd")
const Balance = preload("res://scripts/kernel/balance.gd")
const Snapshot = preload("res://scripts/net/snapshot.gd")
const Persistence = preload("res://scripts/persistence.gd")

const DT := 0.1
const TICKS := 600


func _init() -> void:
	print("== RealWorld snapshot delta codec suite (spec 0006 §8.3) ==")
	_t_codec_primitives()
	_t_live_fidelity_and_size()
	finish()


func _t_codec_primitives() -> void:
	var kf: Variant = Snapshot.encode(null, {"a": 1, "b": {"c": 2}})
	ok(kf is Array and str(kf[0]) == "r", "encode(null, snap) emits a keyframe replace node")
	ok(Snapshot.apply(null, kf) == {"a": 1, "b": {"c": 2}}, "keyframe applies onto nothing")
	ok(Snapshot.encode({"a": 1}, {"a": 1}) == null, "identical snapshots encode to null (nothing to send)")
	ok(Snapshot.encode({"a": 1}, {"a": 1.0}) == null, "int vs float of the same number is not a change (wire coercion)")
	var d: Variant = Snapshot.encode({"a": 1, "b": {"c": 2, "e": 5}, "z": 9}, {"a": 1, "b": {"c": 3}, "n": 7})
	var out: Variant = Snapshot.apply({"a": 1, "b": {"c": 2, "e": 5}, "z": 9}, d)
	ok(out == {"a": 1, "b": {"c": 3}, "n": 7}, "nested set + delete round-trips")
	ok(Snapshot.apply({"a": 1}, ["junk"]) == {"a": 1}, "malformed delta leaves the base untouched (keyframe heals later)")
	var arr: Variant = Snapshot.encode({"rows": [1, 2]}, {"rows": [1, 2, 3]})
	ok(Snapshot.apply({"rows": [1, 2]}, arr) == {"rows": [1, 2, 3]}, "arrays replace wholesale by design")


# world/ctx built the same deterministic way on both ends of the wire (parity with the spike)
func _snap(sess: Variant, bal: Variant) -> Dictionary:
	var sim: Variant = sess.sim
	var world := {"buildings": [], "stock": sim.stock, "items": []}
	var ctx := {"day": int(sim.time.day)}
	return HudModel.snapshot(sess, world, ctx, bal)


func _t_live_fidelity_and_size() -> void:
	var sess: Variant = Session.new()
	sess.start(50.4501, 30.5234, "Київ")
	var bal: Variant = Balance.Balance.new()
	var prev: Variant = null           # sender's last-encoded snapshot
	var recon: Variant = null          # receiver's reconstruction
	var mism := 0
	var first_bad := -1
	var full_sum := 0
	var delta_sum := 0
	var delta_peak := 0
	var sent := 0
	# cadence experiment: a second receiver that only gets every 5th tick's delta
	var prev5: Variant = null
	var delta5_sum := 0
	var sent5 := 0
	for t in TICKS:
		sess.sim.update(DT)
		sess.tick_research(DT)
		sess.sim.player.hp = 100.0
		sess.sim.player.hunger = 100.0
		sess.sim.player.rest = 100.0
		# the delta-stream contract: the sender diffs WIRE-normalized snapshots (see snapshot.gd —
		# decimal JSON cannot round-trip an arbitrary double bit-exactly, even at full precision)
		var snap: Variant = Snapshot.wire_normalize(_snap(sess, bal))
		var delta: Variant = Snapshot.encode(prev, snap)
		prev = snap
		if delta != null:
			sent += 1
			delta_sum += Snapshot.wire_size(delta)
			delta_peak = maxi(delta_peak, Snapshot.wire_size(delta))
		var wire: Variant = JSON.parse_string(Snapshot.to_wire({"d": delta})).get("d")
		recon = Snapshot.apply(recon, wire)
		if Persistence.content_hash(recon) != Persistence.content_hash(snap):
			mism += 1
			if first_bad < 0:
				first_bad = t + 1
		full_sum += Snapshot.wire_size(snap)
		if (t + 1) % 5 == 0:
			var d5: Variant = Snapshot.encode(prev5, snap)
			prev5 = snap
			if d5 != null:
				sent5 += 1
				delta5_sum += Snapshot.wire_size(d5)
	ok(mism == 0, "wire fidelity: reconstruction hash-equal to the sender on all %d ticks%s" % [
		TICKS, "" if mism == 0 else " — first mismatch at tick %d (%d total)" % [first_bad, mism]
	])
	ok(sent > 0 and delta_sum * 5 < full_sum, "deltas are at least 5x smaller than full snapshots overall")
	print("  §8.3 payload: full avg=%d B | delta avg=%d B peak=%d B (%d sent/tick cadence) | delta@5-tick avg=%d B (%d sent) | 10 t/s stream ≈ %.1f KB/s vs %.1f KB/s full" % [
		full_sum / TICKS, delta_sum / maxi(sent, 1), delta_peak, sent,
		delta5_sum / maxi(sent5, 1), sent5,
		(delta_sum / float(TICKS)) * 10.0 / 1024.0, (full_sum / float(TICKS)) * 10.0 / 1024.0,
	])

# RealWorld — tests/run_command_tests.gd : the spec 0006 plan §4 command-envelope suite.
#
# Locks the three properties the envelope exists for — validation (with a REASON, never a silent
# drop), canonical ordering (arrival order must not reach the sim) and idempotency (a resend is
# applied exactly once) — plus the wire seam that makes them survive JSON.
# Run: godot --headless --path godot -s res://tests/run_command_tests.gd
extends "res://tests/harness.gd"

const Command = preload("res://scripts/net/command.gd")
const Snapshot = preload("res://scripts/net/snapshot.gd")
const InputVerbs = preload("res://scripts/ui/input_verbs.gd")

const N := 56
const CTX := {"n": N}


func _init() -> void:
	print("== RealWorld command envelope suite (spec 0006 plan §4) ==")
	_t_validation()
	_t_wire_seam()
	_t_vocabulary_is_a_subset()
	_t_idempotency()
	_t_canonical_ordering()
	_t_rejoin_hook()
	finish()


func _reason(env: Variant) -> StringName:
	return Command.validate(env, CTX).reason


func _t_validation() -> void:
	var good := Command.validate(Command.make(1, 0, "build", {"kind": "wall", "x": 10, "y": 12}), CTX)
	ok(bool(good.ok) and good.args.x == 10 and good.args.kind == "wall", "well-formed command validates and returns coerced args")
	ok(_reason(Command.make(1, 0, "order_move", {"x": 3})) == Command.R_ARGS, "missing arg refused")
	ok(_reason(Command.make(1, 0, "order_move", {"x": 3, "y": 4, "z": 9})) == Command.R_ARGS, "extra arg refused (no silent ignore)")
	ok(_reason(Command.make(1, 0, "order_move", {"x": "3", "y": 4})) == Command.R_ARGS, "string where a coordinate belongs is refused")
	ok(_reason(Command.make(1, 0, "order_move", {"x": true, "y": 4})) == Command.R_ARGS, "bool coordinate refused (GDScript would int(true) -> 1)")
	ok(_reason(Command.make(1, 0, "order_move", {"x": 3.5, "y": 4})) == Command.R_ARGS, "fractional coordinate refused")
	ok(_reason(Command.make(1, 0, "order_move", {"x": -1, "y": 4})) == Command.R_ARGS, "negative coordinate refused")
	ok(_reason(Command.make(1, 0, "order_move", {"x": N, "y": 4})) == Command.R_ARGS, "coordinate at n refused (bounds are [0, n))")
	ok(_reason(Command.make(1, 0, "craft", {"id": "x".repeat(200)})) == Command.R_ARGS, "over-long string refused")
	ok(_reason(Command.make(1, 0, "no_such_verb", {})) == Command.R_VERB, "unknown verb refused")
	ok(_reason({"c": 1, "v": "order_move"}) == Command.R_SHAPE, "envelope missing seq refused")
	ok(_reason(Command.make(1, -3, "cancel_action", {})) == Command.R_SHAPE, "negative seq refused")
	ok(bool(Command.validate(Command.make(1, 0, "cancel_action", {}), CTX).ok), "a no-arg verb validates with an empty arg set")
	# spec 0010 REQ-0010-36: both capsule axes are wire verbs without arguments; a client cannot smuggle a price, a level or a cmd id through
	for v in ["capsule_upgrade", "capsule_protect"]:
		ok(bool(Command.validate(Command.make(1, 0, v, {}), CTX).ok), "%s validates as an argument-less wire verb" % v)
		ok(_reason(Command.make(1, 0, v, {"level": 5})) == Command.R_ARGS, "%s refuses any argument (the server reads the level and the price itself)" % v)
	# the refusal TEXT lives in the router, from value data (R10): the first reason in words, a duplicate stays silent
	ok(InputVerbs.capsule_result_text({"ok": false, "reason": &"duplicate"}) == "", "a duplicate capsule command is silent")
	ok(InputVerbs.capsule_result_text({"ok": false, "reason": &"cost", "missing": {"wood": 8, "stone": 2}, "far": false}).begins_with("Бракує: "),
		"a cost refusal says «Бракує: …» (first reason, in words)")
	# without a map in ctx the bounds check is simply skipped — a unit test need not build a world
	ok(bool(Command.validate(Command.make(1, 0, "order_move", {"x": 9999, "y": 1})).ok), "no ctx.n -> coordinates are type-checked but not bounded")


func _t_wire_seam() -> void:
	var env := Command.make(7, 42, "send_convoy", {"hub": 2, "res": "wood", "amt": 15})
	var round_trip: Variant = JSON.parse_string(Snapshot.to_wire(env))
	var v := Command.validate(round_trip, CTX)
	ok(bool(v.ok), "envelope survives a real JSON round-trip")
	ok(v.args.hub is int and v.args.amt is int and v.args.amt == 15, "wire floats are coerced back to ints (the sim would choke on 15.0)")
	ok(int(round_trip.c) == 7 and int(round_trip.n) == 42, "client id and seq survive the wire")


# The wire vocabulary must stay a SUBSET of the router grammar — a verb the router cannot dispatch
# is a dead command, and a verb invented here would be the second mutation vocabulary R9 forbids.
func _t_vocabulary_is_a_subset() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/input_verbs.gd")
	var missing: Array = []
	for verb in Command.WIRE_VERBS:
		if not src.contains("&\"%s\"" % verb):
			missing.append(verb)
	ok(missing.is_empty(), "every wire verb is bound in input_verbs.gd (no parallel vocabulary): %s" % str(missing))
	# order_attack takes a LIVE enemy Dictionary — it cannot cross a socket and must stay off the wire
	ok(not Command.WIRE_VERBS.has("order_attack"), "order_attack is excluded: its arg is a live ref, not value data")
	ok(_reason(Command.make(1, 0, "order_attack", {"target": {}})) == Command.R_VERB, "a client sending order_attack is refused, not crashed on")
	# ...and ONE executor, not just one vocabulary: a net process that re-implemented the verb table
	# would drift from the router the moment a verb gained a rule (this regressed once — the server
	# passed raw args where the client coerced them). Every net file dispatches, none re-implements.
	var offenders: Array = []
	for f in ["net_server.gd", "net_client.gd"]:
		var net_src := FileAccess.get_file_as_string("res://tests/net/" + f)
		if net_src.contains("sim.order_move(") or net_src.contains("sim.try_build(") or net_src.contains("sim.order_gather("):
			offenders.append(f)
	ok(offenders.is_empty(), "no net process calls a sim mutator directly — all go through the router (R9): %s" % str(offenders))


func _t_idempotency() -> void:
	var ib := Command.Inbox.new()
	var cmd := Command.make(1, 0, "order_gather", {"x": 5, "y": 6})
	ok(bool(ib.accept(cmd, CTX).ok), "first send accepted")
	ok(ib.accept(cmd, CTX).reason == Command.R_DUPLICATE, "resend inside the same batch refused as duplicate")
	ok(ib.drain().size() == 1, "the duplicate never reaches the batch")
	ok(ib.accept(cmd, CTX).reason == Command.R_DUPLICATE, "resend AFTER the batch was applied is still a duplicate")
	ok(ib.accept(Command.make(1, 5, "cancel_action", {}), CTX).ok, "a later seq from the same client is accepted")
	ib.drain()
	ok(ib.accept(Command.make(1, 3, "cancel_action", {}), CTX).reason == Command.R_STALE, "a seq below the applied high-water mark is stale")
	# per-client ledgers are independent: client 2 starting at seq 0 is not shadowed by client 1
	ok(bool(ib.accept(Command.make(2, 0, "cancel_action", {}), CTX).ok), "seq counters are per client, not global")
	ok(int(ib.refusals.get(Command.R_DUPLICATE, 0)) == 2 and int(ib.refusals.get(Command.R_STALE, 0)) == 1,
		"refusals are counted by reason (a silent channel hides a broken ack loop)")


func _t_canonical_ordering() -> void:
	# the same four intents, offered in two different arrival orders — as two racing sockets would
	var a := Command.Inbox.new()
	var b := Command.Inbox.new()
	var cmds := [
		Command.make(2, 0, "order_move", {"x": 1, "y": 1}),
		Command.make(1, 0, "order_move", {"x": 2, "y": 2}),
		Command.make(2, 1, "cancel_action", {}),
		Command.make(1, 1, "order_gather", {"x": 3, "y": 3}),
	]
	for c in cmds:
		a.accept(c, CTX)
	for c in [cmds[3], cmds[0], cmds[1], cmds[2]]:
		b.accept(c, CTX)
	var ba := a.drain()
	var bb := b.drain()
	var key := func(batch: Array) -> String:
		var parts := PackedStringArray()
		for c in batch:
			parts.append("%d:%d:%s" % [int(c.c), int(c.n), str(c.v)])
		return "|".join(parts)
	ok(key.call(ba) == key.call(bb), "arrival order does not survive the inbox: both orders drain identically")
	ok(key.call(ba) == "1:0:order_move|1:1:order_gather|2:0:order_move|2:1:cancel_action",
		"canonical order is (client_id, seq): %s" % key.call(ba))
	ok(a.drain().is_empty(), "drain empties the batch (no command applied twice next tick)")


func _t_rejoin_hook() -> void:
	var ib := Command.Inbox.new()
	ib.accept(Command.make(4, 0, "cancel_action", {}), CTX)
	ib.accept(Command.make(4, 1, "cancel_action", {}), CTX)
	ib.drain()
	ok(ib.last_seq(4) == 1, "last_seq reports the high-water mark a rejoining client must resume from")
	ok(ib.last_seq(99) == -1, "an unknown client starts at -1 (its seq 0 is fresh, not stale)")

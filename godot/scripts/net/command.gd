# RealWorld — net/command.gd : the client→server command envelope (spec 0006 §3 seam 2 / plan §4).
#
# The transport spike proved commands can round-trip; this formalizes the three properties a
# Phase-1 command channel needs, on top of the SAME InputController verbs (R9 — one mutation
# channel, no second vocabulary):
#
#   VALIDATION  — a client may only send a WIRE_VERBS verb, with exactly the declared args, of the
#                 declared types, within bounds. Everything else is refused WITH A REASON (never
#                 silently dropped: a silent refusal on the wire is a desync the client cannot see).
#   ORDERING    — a batch is applied in canonical (client_id, seq) order, NEVER socket-arrival
#                 order. Two clients acting in the same tick must produce the same schedule on
#                 every instance, or the world hashes diverge (spec 0006 §4).
#   IDEMPOTENCY — (client_id, seq) is the identity of an intent. A resend (reconnect, retry) is
#                 applied exactly once; a stale seq is refused. This is what makes rejoin (plan §5)
#                 safe to build on.
#
# Structural validation only, by design: this layer knows shapes, types and map bounds — the SIM
# stays the authority on content (does this building exist, is it affordable, is the cell free) and
# already refuses gracefully. Duplicating content rules here would create a second, drifting truth.
extends RefCounted

const Snapshot = preload("res://scripts/net/snapshot.gd")

# Arg contracts for the verbs a CLIENT may send. Keys are ui/input_verbs.gd verb names — the wire
# vocabulary is a SUBSET of the router grammar, never a parallel one. Type tags: "i" int, "f" float,
# "s" String; "xy" additionally bounds-checks against the map size.
#
# Deliberately ABSENT — `order_attack`. Its router arg is `a.target`, a LIVE enemy Dictionary
# (spec 0005 R8 forbids live refs in value data, and a reference cannot cross a socket at all).
# Putting it on the wire needs stable server-side enemy ids first; until then a client cannot
# express "attack that one" and the omission is explicit rather than a runtime crash. Also absent:
# `travel`/`launch_capsule`/`accept_invite`, which move a pawn BETWEEN regions — a session-level
# migration that Phase 1 handles as its own protocol (plan §5), not as an in-region tick command.
const WIRE_VERBS := {
	"order_move": {"x": "xy", "y": "xy"},
	"order_gather": {"x": "xy", "y": "xy"},
	"build": {"kind": "s", "x": "xy", "y": "xy"},
	"deconstruct": {"x": "xy", "y": "xy"},
	"cancel_action": {},
	"craft": {"id": "s"},
	"equip": {"id": "s"},
	"send_convoy": {"hub": "i", "res": "s", "amt": "i"},
	"enqueue_research": {"id": "s"},
	"start_research": {"id": "s"},
	"clear_research": {},
}

# Refusal reasons — a closed set, so a client can branch on them and tests can assert on them.
const OK := &"ok"
const R_SHAPE := &"bad_shape"          # not a dictionary / missing envelope fields
const R_VERB := &"unknown_verb"        # not in WIRE_VERBS (includes router verbs kept off the wire)
const R_ARGS := &"bad_args"            # missing, extra, wrong-typed or out-of-bounds args
const R_DUPLICATE := &"duplicate"      # (client_id, seq) already applied — idempotent no-op
const R_STALE := &"stale_seq"          # seq below what this client already had applied

const MAX_STRING_LEN := 64             # ids/kinds are short; a long string is junk or an attack


# Build an envelope. Short keys (c/n/v/a) because this is the highest-frequency message on the wire.
static func make(client_id: int, seq: int, verb: String, args: Dictionary = {}) -> Dictionary:
	return {"t": "cmd", "c": client_id, "n": seq, "v": verb, "a": args}


# Structural + type + bounds check. `ctx` may carry {"n": map_size} to bounds-check coordinates;
# without it, coordinate args are only type-checked (a headless unit test need not build a map).
# Returns {ok: bool, reason: StringName, args: Dictionary} — `args` is the COERCED arg set, which
# is what callers must apply: the JSON wire turns every int into a float, so applying the raw
# payload would feed 12.0 where the sim expects 12.
static func validate(env: Variant, ctx: Dictionary = {}) -> Dictionary:
	if not (env is Dictionary):
		return {"ok": false, "reason": R_SHAPE, "args": {}}
	var d: Dictionary = env
	if not (d.has("c") and d.has("n") and d.has("v")):
		return {"ok": false, "reason": R_SHAPE, "args": {}}
	if not _is_num(d.c) or not _is_num(d.n) or int(d.n) < 0:
		return {"ok": false, "reason": R_SHAPE, "args": {}}
	var verb := str(d.v)
	if not WIRE_VERBS.has(verb):
		return {"ok": false, "reason": R_VERB, "args": {}}
	var spec: Dictionary = WIRE_VERBS[verb]
	var raw: Variant = d.get("a", {})
	if not (raw is Dictionary):
		return {"ok": false, "reason": R_ARGS, "args": {}}
	var got: Dictionary = raw
	if got.size() != spec.size():                      # extra args are as wrong as missing ones
		return {"ok": false, "reason": R_ARGS, "args": {}}
	var out := {}
	for key in spec:
		if not got.has(key):
			return {"ok": false, "reason": R_ARGS, "args": {}}
		var coerced: Variant = _coerce(got[key], str(spec[key]), ctx)
		if coerced == null:
			return {"ok": false, "reason": R_ARGS, "args": {}}
		out[key] = coerced
	return {"ok": true, "reason": OK, "args": out}


# null = rejected. Coercion is the wire seam: ints arrive as floats, StringNames as Strings.
static func _coerce(v: Variant, tag: String, ctx: Dictionary) -> Variant:
	match tag:
		"i":
			return int(v) if _is_num(v) else null
		"f":
			return float(v) if _is_num(v) else null
		"s":
			if not (v is String or v is StringName):
				return null
			var s := str(v)
			return s if s.length() <= MAX_STRING_LEN else null
		"xy":
			if not _is_num(v):
				return null
			var i := int(v)
			if i < 0:
				return null
			# a float that is not a whole number was never a tile coordinate
			if absf(float(v) - float(i)) > 0.0:
				return null
			if ctx.has("n") and i >= int(ctx.n):
				return null
			return i
	return null


# bool is NOT a number here: GDScript would happily int(true) -> 1 and let `{"x": true}` through
static func _is_num(v: Variant) -> bool:
	return not (v is bool) and (v is int or v is float)


# The server-side intake: validates, de-duplicates and hands back a canonically ordered batch.
# One per server (not per peer) — the ordering guarantee is across clients, which is exactly the
# part a per-peer queue cannot give you.
class Inbox:
	extends RefCounted

	var pending: Array = []            # accepted this batch: [{c, n, v, a}] with COERCED args
	var applied: Dictionary = {}       # client_id -> highest seq applied (idempotency ledger)
	var accepted := 0
	var refused := 0
	var refusals: Dictionary = {}      # reason -> count (observability; a silent channel hides bugs)

	# Returns {ok, reason}. A duplicate is NOT an error the caller must surface to the player — it
	# is the retry working as designed — but it is counted, because a rising duplicate rate means
	# the client's ack loop is broken.
	func accept(env: Variant, ctx: Dictionary = {}) -> Dictionary:
		var v := Command.validate(env, ctx)
		if not bool(v.ok):
			return _refuse(v.reason)
		var d: Dictionary = env
		var cid := int(d.c)
		var seq := int(d.n)
		var last: int = int(applied.get(cid, -1))
		if seq <= last:
			return _refuse(R_DUPLICATE if seq == last else R_STALE)
		for p in pending:                                    # duplicate within THIS batch
			if int(p.c) == cid and int(p.n) == seq:
				return _refuse(R_DUPLICATE)
		pending.append({"c": cid, "n": seq, "v": str(d.v), "a": v.args})
		accepted += 1
		return {"ok": true, "reason": OK}

	func _refuse(reason: StringName) -> Dictionary:
		refused += 1
		refusals[reason] = int(refusals.get(reason, 0)) + 1
		return {"ok": false, "reason": reason}

	# Drain into canonical (client_id, seq) order and mark the seqs applied. Socket arrival order,
	# Dictionary iteration order and peer index all drop out here — that is the whole point.
	func drain() -> Array:
		var batch: Array = pending
		pending = []
		batch.sort_custom(func(a, b): return (int(a.c) < int(b.c)) if int(a.c) != int(b.c) else (int(a.n) < int(b.n)))
		for c in batch:
			applied[int(c.c)] = int(c.n)
		return batch

	# What a rejoining client must be told so it can resume its seq counter (plan §5 hook).
	func last_seq(client_id: int) -> int:
		return int(applied.get(client_id, -1))


# self-reference for the inner class (an inner class cannot see the outer script's statics by name)
const Command = preload("res://scripts/net/command.gd")

# RealWorld — net/snapshot.gd : the snapshot delta codec (spec 0006 §3 seam 1 / plan §8.3).
#
# Phase 1 replicates state as HudModel.snapshot() payloads (the one ViewModel — no second state
# model), and this codec turns consecutive snapshots into wire deltas: `encode(prev, next)` emits
# the minimal patch (or null when nothing changed), `apply(base, delta)` reconstructs the next
# snapshot on the receiving side. The format survives a JSON round-trip (the wire), so it is
# expressed in plain Arrays/Dictionaries with string tags:
#   ["r", value]              — replace this node wholesale (also the keyframe: encode(null, snap))
#   ["p", {key: node}, [del]] — patch a Dictionary: recurse per key, then erase `del` keys
# Arrays are replaced wholesale — HudModel slices keep them small (rows/bars); measure before
# inventing an index-diff (run_snapshot_tests.gd prints the payload numbers that justify this).
# Equality leans on Variant `==` (GDScript 4 compares Array/Dictionary by value, int==float is
# numeric), and cross-machine fidelity is asserted via Persistence.content_hash, which already
# canonicalizes the int→float and StringName→String coercions the JSON wire introduces.
extends RefCounted

const TAG_REPLACE := "r"
const TAG_PATCH := "p"


# null = no change. Feed prev=null (or any non-Dictionary) to get a keyframe.
static func encode(prev: Variant, next: Variant) -> Variant:
	if prev is Dictionary and next is Dictionary:
		var setd := {}
		var deld: Array = []
		for k in (next as Dictionary):
			if not (prev as Dictionary).has(k):
				setd[k] = [TAG_REPLACE, next[k]]
			else:
				var sub: Variant = encode(prev[k], next[k])
				if sub != null:
					setd[k] = sub
		for k in (prev as Dictionary):
			if not (next as Dictionary).has(k):
				deld.append(k)
		if setd.is_empty() and deld.is_empty():
			return null
		return [TAG_PATCH, setd, deld]
	if _eq(prev, next):
		return null
	return [TAG_REPLACE, next]


# Canonical equality — must agree with Persistence.content_hash, NOT with Variant `==`:
# GDScript promotes bool to int (`true == 1`), which the canonical JSON keeps distinct, so a
# bool→int drift would silently skip a delta and desync the receiver (caught live at tick 330
# of the first suite run). Numbers stay numerically equal (24 == 24.0 — the JSON wire coerces
# int to float); everything else must match by type family and value.
static func _eq(a: Variant, b: Variant) -> bool:
	if a is bool or b is bool:
		return a is bool and b is bool and a == b
	if (a is int or a is float) and (b is int or b is float):
		return a == b
	if a is Array and b is Array:
		var aa := a as Array
		var ba := b as Array
		if aa.size() != ba.size():
			return false
		for i in aa.size():
			if not _eq(aa[i], ba[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		var ad := a as Dictionary
		var bd := b as Dictionary
		if ad.size() != bd.size():
			return false
		for k in ad:
			if not bd.has(k) or not _eq(ad[k], bd[k]):
				return false
		return true
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	return typeof(a) == typeof(b) and a == b


static func apply(base: Variant, delta: Variant) -> Variant:
	if delta == null:
		return base
	if delta is Array and (delta as Array).size() == 2 and str(delta[0]) == TAG_REPLACE:
		return delta[1]
	if delta is Array and (delta as Array).size() == 3 and str(delta[0]) == TAG_PATCH and base is Dictionary:
		var out: Dictionary = (base as Dictionary).duplicate(true)
		var setd: Dictionary = delta[1]
		for k in setd:
			out[k] = apply(out.get(k), setd[k])
		for k in (delta[2] as Array):
			out.erase(k)
		return out
	# malformed / type drift: keep the base — the server is authoritative and the next keyframe heals
	return base


# THE wire serializer — every net message must go through this, not bare JSON.stringify:
# the default stringify rounds floats (full_precision=false), which mutates state in transit —
# a 1.358e-14 daylight factor came back as 0.00000000000001358 and desynced the reconstruction
# hash at tick 330 of the first suite run. full_precision=true is better but STILL not a
# guaranteed bit round-trip for an arbitrary double (observed: …6282704 → wire → …6282703), so
# the sender must never diff against its native floats — see wire_normalize below.
static func to_wire(msg: Variant) -> String:
	return JSON.stringify(msg, "", true, true)


# Projects a snapshot into the wire domain (one stringify+parse round-trip). The delta-stream
# contract: the sender KEEPS its previous snapshot in wire form and encodes each new snapshot
# against it after normalizing — so sender and receiver diff/patch the exact same numbers, and
# decimal-JSON float drift can never accumulate into a desync. One round-trip is idempotent:
# re-serializing a parsed wire value reproduces the same string.
static func wire_normalize(v: Variant) -> Variant:
	return JSON.parse_string(to_wire(v))


# the payload metric the spec asks to measure: bytes on the JSON wire
static func wire_size(v: Variant) -> int:
	return to_wire(v).length()

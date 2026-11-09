# RealWorld — net/realm_protocol.gd : the wire vocabulary of the RealGPS channel (spec 0013 §3.6).
#
# One responsibility: say which messages exist, what their fields are, and refuse everything else WITH
# A REASON (a silent drop on the wire is a desync the client cannot see — same discipline as
# net/command.gd). It knows shapes and types only; whether a fix is plausible is GpsGuard's call and
# who may join is Realm's. Messages are plain Dictionaries, JSON-safe, tagged by "t".
#
# client -> server:   hello {t, c, name, lat, lon}   join the realm at this fix
#                     fix   {t, c, lat, lon}         a new GPS fix
#                     ping  {t, c}                   heartbeat, no movement
#                     bye   {t, c}                   leave
# server -> client:   welcome  {t, c, region, cell, tick, aoi} accepted; region = shared world anchor, aoi = view radius (m)
#                     presence {t, c, d}                    d = Snapshot delta of the presence view
#                     refuse   {t, c, for, reason}          a request was not applied (reason is a closed set)
# The client NEVER sends a timestamp: the server stamps arrival time itself, so a client cannot
# back-date a fix to dodge the speed guard.
extends RefCounted

const VERSION := 1

const T_HELLO := "hello"
const T_FIX := "fix"
const T_PING := "ping"
const T_BYE := "bye"
const T_WELCOME := "welcome"
const T_PRESENCE := "presence"
const T_REFUSE := "refuse"

const OK := &"ok"
const R_SHAPE := &"bad_shape"      # not a Dictionary / no usable "t" / no client id
const R_TYPE := &"unknown_type"    # a "t" this side does not accept
const R_ARGS := &"bad_args"        # missing, extra or wrong-typed fields
const R_RATE := &"rate_limited"
const R_BOUND := &"id_bound"       # this client id is already bound to another connection
const R_NOT_JOINED := &"not_joined"

const MAX_NAME_LEN := 64           # raw wire bound; the realm applies the stricter display limit

const CLIENT_TYPES := {
	T_HELLO: {"name": "s", "lat": "f", "lon": "f"},
	T_FIX: {"lat": "f", "lon": "f"},
	T_PING: {},
	T_BYE: {},
}


static func hello(client_id: int, p_name: String, lat: float, lon: float) -> Dictionary:
	return {"t": T_HELLO, "c": client_id, "name": p_name, "lat": lat, "lon": lon}


static func fix(client_id: int, lat: float, lon: float) -> Dictionary:
	return {"t": T_FIX, "c": client_id, "lat": lat, "lon": lon}


static func ping(client_id: int) -> Dictionary:
	return {"t": T_PING, "c": client_id}


static func bye(client_id: int) -> Dictionary:
	return {"t": T_BYE, "c": client_id}


static func welcome(client_id: int, region: Dictionary, cell: String, tick: int, aoi_m: float = 0.0) -> Dictionary:
	return {"t": T_WELCOME, "c": client_id, "region": region, "cell": cell, "tick": tick, "aoi": aoi_m}


static func presence(client_id: int, delta: Variant) -> Dictionary:
	return {"t": T_PRESENCE, "c": client_id, "d": delta}


static func refuse(client_id: int, for_type: String, reason: StringName) -> Dictionary:
	return {"t": T_REFUSE, "c": client_id, "for": for_type, "reason": str(reason)}


# Structural validation of one CLIENT message as it came off the wire (after JSON: ints may be floats).
# Returns {ok, reason, msg} — `msg` is the coerced copy the server may act on.
static func validate_client(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return _bad(R_SHAPE)
	var m := raw as Dictionary
	var t: Variant = m.get("t")
	if not (t is String):
		return _bad(R_SHAPE)
	if not CLIENT_TYPES.has(t):
		return _bad(R_TYPE)
	var cid: Variant = _as_int(m.get("c"))
	if cid == null or int(cid) < 0:
		return _bad(R_SHAPE)
	var spec: Dictionary = CLIENT_TYPES[t]
	var out := {"t": t, "c": int(cid)}
	if m.size() != 2 + spec.size():
		return _bad(R_ARGS)
	for field in spec:
		if not m.has(field):
			return _bad(R_ARGS)
		var v: Variant = m[field]
		if spec[field] == "s":
			if not (v is String) or (v as String).length() > MAX_NAME_LEN:
				return _bad(R_ARGS)
			out[field] = v
		else:
			if not (v is float or v is int) or v is bool or not is_finite(float(v)):
				return _bad(R_ARGS)
			out[field] = float(v)
	return {"ok": true, "reason": OK, "msg": out}


static func _as_int(v: Variant) -> Variant:
	if v is bool:
		return null
	if v is int:
		return v
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	return null


static func _bad(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason, "msg": {}}

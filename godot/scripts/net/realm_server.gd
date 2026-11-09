# RealWorld — net/realm_server.gd : the RealGPS server loop (spec 0013 §3.8).
#
# Orchestration only — it owns no rules. Each tick() it (1) drains the transport, (2) validates every
# message with RealmProtocol, (3) lets Realm apply it (membership, GpsGuard, interest), (4) answers
# refusals WITH a reason, (5) expires silent clients and (6) pushes each bound client a presence
# delta over net/snapshot.gd — the first push is a keyframe, later ones only what changed, none at all
# when nothing did. Collaborators are injected (Realm, a ServerTransport), so swapping the socket or
# the interest policy never edits this file. `now_ms` is an ARGUMENT: the server reads no clock.
#
# Identity: a connection (peer) binds to exactly one client id at hello; the id cannot be taken by a
# second connection and a bound peer cannot speak for another id. Flood control: at most
# MAX_MSGS_PER_TICK messages per peer per tick are processed, the rest are refused as rate_limited.
extends RefCounted

const Protocol = preload("res://scripts/net/realm_protocol.gd")
const Realm = preload("res://scripts/net/realm.gd")
const Snapshot = preload("res://scripts/net/snapshot.gd")
const Transport = preload("res://scripts/net/transport.gd")

const MAX_MSGS_PER_TICK := 8
const DEFAULT_TTL_MS := 60000

var realm: Variant = null          # Realm
var transport: Variant = null      # Transport.ServerTransport
var shard_id: String = "local"
var ttl_ms: int = DEFAULT_TTL_MS
var tick_no: int = 0
var stats: Dictionary = {"accepted": 0, "refused": 0, "presence_sent": 0, "expired": 0}

var _peer_client: Dictionary = {}   # int peer -> int client id
var _client_peer: Dictionary = {}   # int client id -> int peer
var _sent: Dictionary = {}          # int client id -> last presence view pushed (delta base)


func _init(p_realm: Variant, p_transport: Variant, p_shard_id: String = "local") -> void:
	realm = p_realm
	transport = p_transport
	shard_id = p_shard_id


func tick(now_ms: int) -> void:
	tick_no += 1
	var handled: Dictionary = {}    # peer -> messages processed this tick
	for ev in transport.poll():
		var peer := int(ev.peer)
		match str(ev.kind):
			Transport.KIND_CLOSE:
				_unbind(peer)
			Transport.KIND_MSG:
				var n := int(handled.get(peer, 0)) + 1
				handled[peer] = n
				if n > MAX_MSGS_PER_TICK:
					_refuse(peer, "?", Protocol.R_RATE)
				else:
					_handle(peer, ev.get("msg"), now_ms)
	for id in realm.expire(now_ms, ttl_ms):
		stats.expired = int(stats.expired) + 1
		_drop_client(int(id))
	_push_presence()


func bound_clients() -> Array:
	var ids: Array = _client_peer.keys()
	ids.sort()
	return ids


# ---------------- message handling ----------------
func _handle(peer: int, raw: Variant, now_ms: int) -> void:
	var v: Dictionary = Protocol.validate_client(raw)
	if not bool(v.ok):
		_refuse(peer, "?", v.reason)
		return
	var m: Dictionary = v.msg
	var t := str(m.t)
	var cid := int(m.c)
	if t == Protocol.T_HELLO:
		_on_hello(peer, cid, m, now_ms)
		return
	if int(_peer_client.get(peer, -1)) != cid:
		_refuse(peer, t, Protocol.R_NOT_JOINED)
		return
	match t:
		Protocol.T_FIX:
			var r: Dictionary = realm.move(cid, float(m.lat), float(m.lon), now_ms)
			if bool(r.ok):
				stats.accepted = int(stats.accepted) + 1
			else:
				_refuse(peer, t, r.reason)
		Protocol.T_PING:
			realm.touch(cid, now_ms)
		Protocol.T_BYE:
			_unbind(peer)
			transport.drop(peer)


func _on_hello(peer: int, cid: int, m: Dictionary, now_ms: int) -> void:
	if _peer_client.has(peer) or _client_peer.has(cid):
		_refuse(peer, Protocol.T_HELLO, Protocol.R_BOUND)
		return
	var r: Dictionary = realm.join(cid, str(m.name), float(m.lat), float(m.lon), now_ms)
	if not bool(r.ok):
		_refuse(peer, Protocol.T_HELLO, r.reason)
		return
	_peer_client[peer] = cid
	_client_peer[cid] = peer
	_sent.erase(cid)
	stats.accepted = int(stats.accepted) + 1
	transport.send(peer, Protocol.welcome(cid, r.region, str(r.cell), tick_no))


# ---------------- presence push ----------------
func _push_presence() -> void:
	for cid in bound_clients():
		var view: Dictionary = realm.presence_view(int(cid))
		var delta: Variant = Snapshot.encode(_sent.get(cid), view)
		if delta == null:
			continue
		_sent[cid] = view
		transport.send(int(_client_peer[cid]), Protocol.presence(int(cid), delta))
		stats.presence_sent = int(stats.presence_sent) + 1


# ---------------- bookkeeping ----------------
func _refuse(peer: int, for_type: String, reason: StringName) -> void:
	stats.refused = int(stats.refused) + 1
	transport.send(peer, Protocol.refuse(int(_peer_client.get(peer, -1)), for_type, reason))


func _unbind(peer: int) -> void:
	if not _peer_client.has(peer):
		return
	var cid := int(_peer_client[peer])
	_peer_client.erase(peer)
	_client_peer.erase(cid)
	_sent.erase(cid)
	realm.leave(cid)


# Realm already removed the player (expiry); drop the connection and the bindings.
func _drop_client(cid: int) -> void:
	if not _client_peer.has(cid):
		return
	var peer := int(_client_peer[cid])
	_peer_client.erase(peer)
	_client_peer.erase(cid)
	_sent.erase(cid)
	transport.drop(peer)

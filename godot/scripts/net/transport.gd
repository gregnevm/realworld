# RealWorld — net/transport.gd : the seam between RealmServer and a socket (spec 0013 §3.7).
#
# RealmServer depends on this tiny interface, never on WebSocketPeer (dependency inversion): the same
# server logic runs over an in-memory loopback in tests and over WebSocket in production. The
# interface is three calls — poll() drains events, send() and drop() act on one peer — and events are
# plain Dictionaries: {kind: "open"|"msg"|"close", peer: int, msg: Variant (only for "msg")}.
#
# Peer ids are assigned by the transport and are the AUTHORITATIVE identity of a connection; the
# client id in a message is only a claim the server binds to a peer (and refuses to rebind).
extends RefCounted

const KIND_OPEN := "open"
const KIND_MSG := "msg"
const KIND_CLOSE := "close"


# Interface (never instantiated directly; the base is inert, not random).
class ServerTransport extends RefCounted:
	func poll() -> Array:
		return []

	func send(_peer: int, _msg: Dictionary) -> void:
		pass

	func drop(_peer: int) -> void:
		pass


# In-memory transport: tests and single-process play. Deterministic — events come out in the exact
# order they were queued, and "the network" is a JSON round-trip, so what a test sees is what a real
# socket would deliver (ints become floats, StringNames become Strings, live refs cannot leak).
class Loopback extends ServerTransport:
	var _next_peer: int = 1
	var _events: Array = []
	var _outbox: Dictionary = {}     # peer -> Array of messages the server sent
	var _alive: Dictionary = {}

	func connect_client() -> int:
		var peer := _next_peer
		_next_peer += 1
		_alive[peer] = true
		_outbox[peer] = []
		_events.append({"kind": KIND_OPEN, "peer": peer})
		return peer

	func client_send(peer: int, msg: Variant) -> void:
		if _alive.has(peer):
			_events.append({"kind": KIND_MSG, "peer": peer, "msg": JSON.parse_string(JSON.stringify(msg))})

	func client_close(peer: int) -> void:
		if _alive.has(peer):
			_alive.erase(peer)
			_events.append({"kind": KIND_CLOSE, "peer": peer})

	func client_recv(peer: int) -> Array:
		var got: Array = _outbox.get(peer, [])
		_outbox[peer] = []
		return got

	func is_connected_peer(peer: int) -> bool:
		return _alive.has(peer)

	# --- ServerTransport ---
	func poll() -> Array:
		var out := _events
		_events = []
		return out

	func send(peer: int, msg: Dictionary) -> void:
		if _alive.has(peer):
			(_outbox[peer] as Array).append(JSON.parse_string(JSON.stringify(msg)))

	func drop(peer: int) -> void:
		if _alive.has(peer):
			_alive.erase(peer)
			_events.append({"kind": KIND_CLOSE, "peer": peer})


# WebSocketServer transport: the production adapter (WebSocket is the Phase-1 pick, spec 0006 §9.2 — the
# web export has no UDP). Text frames carrying one JSON message each. The ONLY class in the net layer
# that touches Godot networking; everything above it is testable without a socket.
class WebSocketServer extends ServerTransport:
	var _tcp: TCPServer = TCPServer.new()
	var _peers: Dictionary = {}      # int peer -> WebSocketPeer
	var _announced: Dictionary = {}  # peer -> true once its "open" event was emitted
	var _next_peer: int = 1
	var max_frame_bytes: int = 4096  # a presence/fix message is tiny; a big frame is junk or an attack

	func listen(port: int, bind: String = "127.0.0.1") -> int:
		return _tcp.listen(port, bind)

	func close_all() -> void:
		for peer in _peers:
			(_peers[peer] as WebSocketPeer).close()
		_peers.clear()
		_tcp.stop()

	func poll() -> Array:
		var out: Array = []
		while _tcp.is_connection_available():
			var ws := WebSocketPeer.new()
			if ws.accept_stream(_tcp.take_connection()) == OK:
				_peers[_next_peer] = ws
				_next_peer += 1
		var ids: Array = _peers.keys()
		ids.sort()
		for peer in ids:
			var ws: WebSocketPeer = _peers[peer]
			ws.poll()
			var state := ws.get_ready_state()
			if state == WebSocketPeer.STATE_OPEN:
				if not _announced.has(peer):
					_announced[peer] = true
					out.append({"kind": KIND_OPEN, "peer": int(peer)})
				while ws.get_available_packet_count() > 0:
					var pkt := ws.get_packet()
					if pkt.size() > max_frame_bytes:
						out.append({"kind": KIND_MSG, "peer": int(peer), "msg": null})   # oversize -> validated away as bad_shape
						continue
					out.append({"kind": KIND_MSG, "peer": int(peer), "msg": JSON.parse_string(pkt.get_string_from_utf8())})
			elif state == WebSocketPeer.STATE_CLOSED:
				if _announced.has(peer):
					out.append({"kind": KIND_CLOSE, "peer": int(peer)})
				_peers.erase(peer)
				_announced.erase(peer)
		return out

	func send(peer: int, msg: Dictionary) -> void:
		if _peers.has(peer) and (_peers[peer] as WebSocketPeer).get_ready_state() == WebSocketPeer.STATE_OPEN:
			(_peers[peer] as WebSocketPeer).send_text(JSON.stringify(msg))

	func drop(peer: int) -> void:
		if _peers.has(peer):
			(_peers[peer] as WebSocketPeer).close()

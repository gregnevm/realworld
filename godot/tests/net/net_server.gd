# RealWorld — tests/net/net_server.gd : the authoritative half of the spec 0006 transport spike.
#
# A real --headless Godot process owning the authoritative sim (option A made literal): listens on
# a WebSocket port, waits for N clients, then drives a fixed-tick lockstep — client commands are
# QUEUED, scheduled into the next advance batch, echoed to everyone (server included) and applied
# by all instances at the same tick. Every HASH_EVERY ticks it broadcasts Persistence.world_hash
# so clients can verify against their own state; the orchestrator (run_net_spike.gd) collects the
# verdict files. WebSocket (not ENet) is the deliberate Phase-1 transport pick: the web export
# (threads OFF) has no UDP, and TCP ordering is what makes this lockstep envelope trivial.
# Args (after --): port=<int> clients=<int> ticks=<int> out=<abs path of the verdict json>
extends SceneTree

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Persistence = preload("res://scripts/persistence.gd")

const LAT := 50.4501
const LON := 30.5234
const N := 56
const DT := 0.1
const BATCH := 10
const HASH_EVERY := 100
const ALLOWED_VERBS := ["order_gather", "order_move", "try_build"]
const ACCEPT_TIMEOUT_MSEC := 30000

var _tcp := TCPServer.new()
var _peers: Array = []          # WebSocketPeer per connected client
var _pending: Array = []        # commands queued from clients for the NEXT batch


func _init() -> void:
	var args := _parse_args()
	var port: int = args.get("port", 8901)
	var want_clients: int = args.get("clients", 2)
	var total_ticks: int = args.get("ticks", 600)
	var out_path: String = args.get("out", "user://net_spike_server.json")

	var sim: Variant = Sim.new()
	sim.new_game(WorldGen.generate_map(LAT, LON, N))

	var verdict := {"role": "server", "ok": false, "clients_seen": 0, "cmd_echoes": 0, "final": "", "err": ""}
	if _tcp.listen(port, "127.0.0.1") != OK:
		verdict.err = "listen failed on %d" % port
		_finish(out_path, verdict)
		return
	if not _accept_clients(want_clients):
		verdict.err = "clients did not connect"
		verdict.clients_seen = _peers.size()
		_finish(out_path, verdict)
		return
	verdict.clients_seen = _peers.size()

	# handshake: each client learns its index and the world recipe (seed inputs, not state)
	for i in _peers.size():
		_send(_peers[i], {"t": "welcome", "idx": i, "lat": LAT, "lon": LON, "n": N, "ticks": total_ticks})

	var tick := 0
	var echoes := 0
	while tick < total_ticks:
		_poll_incoming()
		var count := mini(BATCH, total_ticks - tick)
		var cmds: Array = []
		for c in _pending:                       # schedule everything queued into this batch's first tick
			c["tick"] = tick + 1
			cmds.append(c)
		_pending = []
		echoes += cmds.size()
		var msg := {"t": "advance", "base": tick, "count": count, "cmds": cmds}
		for p in _peers:
			_send(p, msg)
		for step in count:                       # the server applies the SAME schedule it broadcast
			tick += 1
			for c in cmds:
				if int(c.tick) == tick:
					_apply(sim, c)
			sim.update(DT)
		if tick % HASH_EVERY == 0:
			var h := {"t": "hash", "tick": tick, "h": Persistence.world_hash(sim)}
			for p in _peers:
				_send(p, h)
		# ack-gated lockstep (Plan §4 flow control): a headless server outruns real clients by
		# orders of magnitude — without this gate a client command can arrive after the run is
		# over. TCP ordering guarantees a command sent before the ack is received before it, so
		# every command lands in the very next batch, deterministically.
		if not _wait_acks(tick):
			verdict.err = "ack timeout at tick %d" % tick
			break
	var final_hash := Persistence.world_hash(sim)
	for p in _peers:
		_send(p, {"t": "bye", "tick": tick, "final": final_hash})
	_flush_and_close()

	verdict.ok = str(verdict.err) == "" and tick == total_ticks
	verdict.cmd_echoes = echoes
	verdict.final = final_hash
	_finish(out_path, verdict)


# ---- lockstep helpers ----

# a client command is trusted only by verb allowlist + int-coerced args — §8.4 validation seed
func _apply(sim: Variant, c: Dictionary) -> void:
	var verb := str(c.verb)
	if not ALLOWED_VERBS.has(verb):
		return
	var a: Dictionary = c.get("args", {})
	match verb:
		"order_gather":
			sim.order_gather(int(a.x), int(a.y))
		"order_move":
			sim.order_move(int(a.x), int(a.y))
		"try_build":
			sim.try_build(str(a.kind), int(a.x), int(a.y))


func _poll_incoming() -> void:
	for i in _peers.size():
		var p: WebSocketPeer = _peers[i]
		p.poll()
		while p.get_available_packet_count() > 0:
			var d: Variant = JSON.parse_string(p.get_packet().get_string_from_utf8())
			if not (d is Dictionary):
				continue
			match str(d.get("t")):
				"cmd":
					_pending.append({"verb": str(d.get("verb")), "args": d.get("args", {}), "from": i})
				"ack":
					_acked[i] = int(d.get("tick", -1))


var _acked: Dictionary = {}     # peer index -> last acked tick


func _wait_acks(tick: int) -> bool:
	var waited := 0
	while waited < ACCEPT_TIMEOUT_MSEC:
		_poll_incoming()
		var got := 0
		for i in _peers.size():
			if int(_acked.get(i, -1)) >= tick:
				got += 1
		if got == _peers.size():
			return true
		OS.delay_msec(1)
		waited += 1
	return false


# ---- plumbing ----

func _accept_clients(want: int) -> bool:
	var waited := 0
	while _peers.size() < want and waited < ACCEPT_TIMEOUT_MSEC:
		if _tcp.is_connection_available():
			var ws := WebSocketPeer.new()
			if ws.accept_stream(_tcp.take_connection()) == OK:
				_peers.append(ws)
		for p in _peers:
			p.poll()
		OS.delay_msec(5)
		waited += 5
	# let every handshake reach OPEN before the welcome goes out
	var settle := 0
	while settle < ACCEPT_TIMEOUT_MSEC:
		var open := 0
		for p in _peers:
			p.poll()
			if p.get_ready_state() == WebSocketPeer.STATE_OPEN:
				open += 1
		if open == want:
			return true
		OS.delay_msec(5)
		settle += 5
	return false


func _send(p: WebSocketPeer, msg: Dictionary) -> void:
	p.poll()
	if p.get_ready_state() == WebSocketPeer.STATE_OPEN:
		p.send_text(JSON.stringify(msg))
		p.poll()


func _flush_and_close() -> void:
	for i in 100:                        # drain the socket so the bye actually leaves the process
		for p in _peers:
			p.poll()
		OS.delay_msec(5)
	for p in _peers:
		p.close()
	for i in 40:
		for p in _peers:
			p.poll()
		OS.delay_msec(5)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		if kv.size() == 2:
			var v: String = kv[1]
			out[kv[0]] = int(v) if v.is_valid_int() else v
	return out


func _finish(out_path: String, verdict: Dictionary) -> void:
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(verdict))
		f.close()
	quit(0 if bool(verdict.ok) else 1)

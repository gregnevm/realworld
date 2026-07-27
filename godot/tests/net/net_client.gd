# RealWorld — tests/net/net_client.gd : a client half of the spec 0006 transport spike.
#
# Connects to the spike server, builds its OWN sim from the seed recipe in the welcome (the
# client never receives state — determinism IS the replication in this lockstep spike), then
# advances exactly as instructed by `advance` batches, applying the echoed command schedule.
# Client #0 injects the scripted gather/build commands from ITS OWN sim's map (both maps are the
# same pure function of lat/lon), which round-trips through the server queue back to everyone.
# Every `hash` message is compared against the local world_hash at that tick; any mismatch is a
# desync and fails the spike. Args (after --): port=<int> out=<abs path>
extends SceneTree

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Persistence = preload("res://scripts/persistence.gd")

const DT := 0.1
const CONNECT_TIMEOUT_MSEC := 30000
const IDLE_TIMEOUT_MSEC := 60000


func _init() -> void:
	var args := _parse_args()
	var port: int = args.get("port", 8901)
	var out_path: String = args.get("out", "user://net_spike_client.json")

	var verdict := {"role": "client", "idx": -1, "ok": false, "hash_checks": 0, "mismatches": 0, "cmds_sent": 0, "final": "", "err": ""}
	var ws := WebSocketPeer.new()
	if ws.connect_to_url("ws://127.0.0.1:%d" % port) != OK:
		verdict.err = "connect_to_url failed"
		_finish(out_path, verdict)
		return
	if not _wait_open(ws):
		verdict.err = "handshake timed out"
		_finish(out_path, verdict)
		return

	ws.send_text(JSON.stringify({"t": "hello"}))
	var sim: Variant = null
	var idx := -1
	var tick := 0
	var total := 0
	var done := false
	var idle := 0
	while not done and idle < IDLE_TIMEOUT_MSEC:
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() == 0:
			verdict.err = "connection dropped at tick %d" % tick
			break
		if ws.get_available_packet_count() == 0:
			OS.delay_msec(2)
			idle += 2
			continue
		idle = 0
		var m: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if not (m is Dictionary):
			continue
		match str(m.get("t")):
			"welcome":
				idx = int(m.idx)
				total = int(m.ticks)
				verdict.idx = idx
				sim = Sim.new()
				sim.new_game(WorldGen.generate_map(float(m.lat), float(m.lon), int(m.n)))
			"advance":
				if sim == null:
					continue
				var cmds: Array = m.get("cmds", [])
				for step in int(m.count):
					tick += 1
					for c in cmds:
						if int(c.tick) == tick:
							_apply(sim, c)
					sim.update(DT)
					# client #0 originates the scripted commands from its own (identical) map
					if idx == 0:
						var cmd := _scripted(sim, tick)
						if not cmd.is_empty():
							ws.send_text(JSON.stringify(cmd))
							verdict.cmds_sent = int(verdict.cmds_sent) + 1
				# ack AFTER any commands from this batch: TCP ordering then guarantees the server
				# sees those commands before it opens the next batch (Plan §4 flow control)
				ws.send_text(JSON.stringify({"t": "ack", "tick": tick}))
			"hash":
				if sim == null or tick != int(m.tick):
					verdict.mismatches = int(verdict.mismatches) + 1
					continue
				verdict.hash_checks = int(verdict.hash_checks) + 1
				if Persistence.world_hash(sim) != str(m.h):
					verdict.mismatches = int(verdict.mismatches) + 1
			"bye":
				verdict.final = Persistence.world_hash(sim) if sim != null else ""
				verdict.ok = tick == int(m.tick) and verdict.final == str(m.final) \
					and int(verdict.mismatches) == 0 and int(verdict.hash_checks) > 0
				if not bool(verdict.ok) and str(verdict.err) == "":
					verdict.err = "final check failed (tick %d vs %d)" % [tick, int(m.tick)]
				done = true
	if not done and str(verdict.err) == "":
		verdict.err = "idle timeout at tick %d/%d" % [tick, total]
	ws.close()
	for i in 20:
		ws.poll()
		OS.delay_msec(5)
	_finish(out_path, verdict)


# same allowlisted application as the server — one grammar, three processes
func _apply(sim: Variant, c: Dictionary) -> void:
	var a: Dictionary = c.get("args", {})
	match str(c.verb):
		"order_gather":
			sim.order_gather(int(a.x), int(a.y))
		"order_move":
			sim.order_move(int(a.x), int(a.y))
		"try_build":
			sim.try_build(str(a.kind), int(a.x), int(a.y))


# the deterministic command script: targets computed from the map only (shared by all instances)
func _scripted(sim: Variant, tick: int) -> Dictionary:
	if tick == 30:
		var tree := _nearest_tree(sim)
		return {"t": "cmd", "verb": "order_gather", "args": {"x": tree.x, "y": tree.y}}
	if tick == 200:
		var cell := _buildable_near_spawn(sim)
		if cell.x >= 0:
			return {"t": "cmd", "verb": "try_build", "args": {"kind": "wall", "x": cell.x, "y": cell.y}}
	if tick == 350:
		var sp: Vector2i = sim.map.spawn
		return {"t": "cmd", "verb": "order_move", "args": {"x": sp.x + 3, "y": sp.y}}
	return {}


func _nearest_tree(sim: Variant) -> Vector2i:
	var n: int = sim.n
	var sp: Vector2i = sim.map.spawn
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for key in sim.map.nodes:
		if sim.map.nodes[key].kind != "tree":
			continue
		var x: int = key % n
		var y: int = int(key / n)
		var d: int = absi(x - sp.x) + absi(y - sp.y)
		if d < bd:
			bd = d
			best = Vector2i(x, y)
	return best


func _buildable_near_spawn(sim: Variant) -> Vector2i:
	var sp: Vector2i = sim.map.spawn
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if sim.build_valid(sp.x + dx, sp.y + dy):
					return Vector2i(sp.x + dx, sp.y + dy)
	return Vector2i(-1, -1)


func _wait_open(ws: WebSocketPeer) -> bool:
	var waited := 0
	while waited < CONNECT_TIMEOUT_MSEC:
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				return true
			WebSocketPeer.STATE_CLOSED:
				return false
		OS.delay_msec(5)
		waited += 5
	return false


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

# RealWorld — tests/run_realm_server_tests.gd : RealmServer over Loopback + a real WebSocket (spec 0013).
# Run: godot --headless --path godot -s res://tests/run_realm_server_tests.gd
extends "res://tests/harness.gd"

const Geo = preload("res://scripts/net/geo.gd")
const GeoGrid = preload("res://scripts/net/geo_grid.gd")
const Protocol = preload("res://scripts/net/realm_protocol.gd")
const Realm = preload("res://scripts/net/realm.gd")
const RealmServer = preload("res://scripts/net/realm_server.gd")
const RealmClient = preload("res://scripts/net/realm_client.gd")
const Transport = preload("res://scripts/net/transport.gd")
const Persistence = preload("res://scripts/persistence.gd")
const LocalRealm = preload("res://scripts/net/local_realm.gd")
const Session = preload("res://scripts/session.gd")

const KYIV := Vector2(50.4501, 30.5234)


func _init() -> void:
	print("== RealWorld RealGPS server suite (spec 0013) ==")
	_t_protocol()
	_t_handshake_and_presence()
	_t_refusals()
	_t_identity_binding()
	_t_rate_limit()
	_t_expiry_and_close()
	_t_determinism()
	_t_local_realm()
	_t_session_integration()
	_t_websocket()
	finish()


func _rig() -> Dictionary:
	var tr := Transport.Loopback.new()
	var srv: Variant = RealmServer.new(Realm.new(GeoGrid.new(), 1200.0), tr, "test")
	return {"tr": tr, "srv": srv}


func _pt(brg: float, dist: float) -> Dictionary:
	return Geo.destination(KYIV.x, KYIV.y, brg, dist)


# connect a client, say hello, run one server tick; returns {peer, cli}
func _join(rig: Dictionary, cid: int, p_name: String, lat: float, lon: float, now: int) -> Dictionary:
	var tr: Variant = rig.tr
	var peer: int = tr.connect_client()
	tr.client_send(peer, Protocol.hello(cid, p_name, lat, lon))
	rig.srv.tick(now)
	var cli := RealmClient.new(cid)
	cli.handle_all(tr.client_recv(peer))
	return {"peer": peer, "cli": cli}


func _t_protocol() -> void:
	var good := Protocol.validate_client(JSON.parse_string(JSON.stringify(Protocol.hello(7, "Остап", 50.0, 30.0))))
	ok(bool(good.ok) and good.msg.c == 7 and good.msg.lat == 50.0, "a hello survives the JSON wire and validates (ids arrive as floats)")
	ok(Protocol.validate_client("junk").reason == Protocol.R_SHAPE and Protocol.validate_client(null).reason == Protocol.R_SHAPE, "non-dictionary refused as bad_shape")
	ok(Protocol.validate_client({"t": 5, "c": 1}).reason == Protocol.R_SHAPE, "non-string type refused")
	ok(Protocol.validate_client({"t": "launch", "c": 1}).reason == Protocol.R_TYPE, "unknown type refused")
	ok(Protocol.validate_client({"t": "fix", "lat": 1.0, "lon": 1.0}).reason == Protocol.R_SHAPE, "missing client id refused")
	ok(Protocol.validate_client({"t": "fix", "c": 1.5, "lat": 1.0, "lon": 1.0}).reason == Protocol.R_SHAPE, "fractional client id refused")
	ok(Protocol.validate_client({"t": "fix", "c": true, "lat": 1.0, "lon": 1.0}).reason == Protocol.R_SHAPE, "bool client id refused")
	ok(Protocol.validate_client({"t": "fix", "c": 1, "lat": 1.0}).reason == Protocol.R_ARGS, "missing field refused")
	ok(Protocol.validate_client({"t": "fix", "c": 1, "lat": 1.0, "lon": 1.0, "t_ms": 5}).reason == Protocol.R_ARGS, "an extra field (a smuggled timestamp) is refused")
	ok(Protocol.validate_client({"t": "fix", "c": 1, "lat": "1", "lon": 1.0}).reason == Protocol.R_ARGS, "string coordinate refused")
	ok(Protocol.validate_client({"t": "fix", "c": 1, "lat": true, "lon": 1.0}).reason == Protocol.R_ARGS, "bool coordinate refused")
	ok(Protocol.validate_client({"t": "fix", "c": 1, "lat": INF, "lon": 1.0}).reason == Protocol.R_ARGS, "infinite coordinate refused")
	ok(Protocol.validate_client({"t": "hello", "c": 1, "name": "x".repeat(100), "lat": 1.0, "lon": 1.0}).reason == Protocol.R_ARGS, "over-long wire name refused")
	ok(bool(Protocol.validate_client(Protocol.ping(3)).ok) and bool(Protocol.validate_client(Protocol.bye(3)).ok), "ping and bye validate as argument-less messages")


func _t_handshake_and_presence() -> void:
	var rig := _rig()
	var a := _join(rig, 1, "Остап", KYIV.x, KYIV.y, 1000)
	var cli_a: Variant = a.cli
	ok(cli_a.joined and cli_a.region.has("seed") and cli_a.cell != "", "welcome carries the shared region and cell")
	ok(cli_a.presence_updates == 1 and cli_a.view.near.is_empty(), "the first push is a keyframe, even for an empty neighbourhood")
	var p := _pt(90.0, 400.0)
	var b := _join(rig, 2, "Ярина", float(p.lat), float(p.lon), 1100)
	var cli_b: Variant = b.cli
	rig.srv.tick(1200)
	cli_a.handle_all(rig.tr.client_recv(a.peer))
	cli_b.handle_all(rig.tr.client_recv(b.peer))
	var rows: Array = cli_a.nearby_rows()
	ok(rows.size() == 1 and rows[0].id == 2 and rows[0].dir == "Сх" and absi(int(rows[0].dist_m) - 400) <= 1, "A sees B ~400 m to the east after the delta")
	ok(cli_b.nearby_rows().size() == 1 and cli_b.nearby_rows()[0].id == 1 and cli_b.nearby_rows()[0].dir == "Зх", "B sees A to the west")
	ok(cli_a.region.seed == cli_b.region.seed or cli_a.cell != cli_b.cell, "players in the same cell are given the same world seed")
	var updates_a: int = cli_a.presence_updates
	rig.srv.tick(1300)
	cli_a.handle_all(rig.tr.client_recv(a.peer))
	ok(cli_a.presence_updates == updates_a, "an unchanged neighbourhood pushes nothing (no empty deltas)")
	# B walks away; A's view must follow, reconstructed from deltas alone
	var far := Geo.destination(float(p.lat), float(p.lon), 90.0, 3000.0)
	rig.tr.client_send(b.peer, Protocol.fix(2, float(far.lat), float(far.lon)))
	rig.tr.client_send(a.peer, Protocol.ping(1))   # A stays alive across the 400 s gap
	rig.srv.tick(1000 + 400000)
	cli_a.handle_all(rig.tr.client_recv(a.peer))
	ok(cli_a.nearby_rows().is_empty(), "after B walks 3 km away it disappears from A's view")
	ok(Persistence.content_hash(cli_a.view) == Persistence.content_hash(rig.srv.realm.presence_view(1)), "the client's reconstructed view equals the server's, hash for hash")


func _t_refusals() -> void:
	var rig := _rig()
	var tr: Variant = rig.tr
	var peer: int = tr.connect_client()
	tr.client_send(peer, {"t": "fix", "c": 1, "lat": KYIV.x, "lon": KYIV.y})
	rig.srv.tick(10)
	var r1: Array = tr.client_recv(peer)
	ok(r1.size() == 1 and r1[0].t == "refuse" and r1[0].reason == "not_joined", "a fix before hello is refused as not_joined")
	tr.client_send(peer, {"t": "warp", "c": 1})
	tr.client_send(peer, "garbage")
	rig.srv.tick(20)
	var r2: Array = tr.client_recv(peer)
	ok(r2.size() == 2 and r2[0].reason == "unknown_type" and r2[1].reason == "bad_shape", "unknown type and garbage each get their own refusal reason")
	tr.client_send(peer, Protocol.hello(1, "Остап", 123.0, 0.0))
	rig.srv.tick(30)
	ok(tr.client_recv(peer)[0].reason == "bad_fix", "an impossible hello is refused with the guard's reason")
	tr.client_send(peer, Protocol.hello(1, "Остап", KYIV.x, KYIV.y))
	rig.srv.tick(40)
	tr.client_recv(peer)
	var tele := _pt(0.0, 9000.0)
	tr.client_send(peer, Protocol.fix(1, float(tele.lat), float(tele.lon)))
	rig.srv.tick(1040)
	var out: Array = tr.client_recv(peer)
	var refused_for_tp := false
	for m in out:
		if m.t == "refuse" and m.reason == "teleport":
			refused_for_tp = true
	ok(refused_for_tp, "a 9 km fix one second after the last is refused as teleport")
	ok(absf(float(rig.srv.realm.player(1).lat) - KYIV.x) < 0.0001, "and the player's position did not move")


func _t_identity_binding() -> void:
	var rig := _rig()
	var a := _join(rig, 1, "Остап", KYIV.x, KYIV.y, 0)
	var tr: Variant = rig.tr
	var thief: int = tr.connect_client()
	tr.client_send(thief, Protocol.hello(1, "Самозванець", KYIV.x, KYIV.y))
	rig.srv.tick(10)
	ok(tr.client_recv(thief)[0].reason == "id_bound", "a second connection cannot take a bound client id")
	tr.client_send(thief, Protocol.fix(1, KYIV.x, KYIV.y))
	rig.srv.tick(20)
	ok(tr.client_recv(thief)[0].reason == "not_joined", "an unbound connection cannot move someone else's player")
	tr.client_send(a.peer, Protocol.hello(5, "Інше імʼя", KYIV.x, KYIV.y))
	rig.srv.tick(30)
	var again: Array = tr.client_recv(a.peer)
	var rebound := false
	for m in again:
		if m.t == "refuse" and m.reason == "id_bound":
			rebound = true
	ok(rebound, "a bound connection cannot rebind to another id")
	tr.client_send(a.peer, Protocol.fix(9, KYIV.x, KYIV.y))
	rig.srv.tick(40)
	var spoof := false
	for m in tr.client_recv(a.peer):
		if m.t == "refuse" and m.reason == "not_joined":
			spoof = true
	ok(spoof, "a bound connection cannot send fixes for another client id")
	ok(rig.srv.bound_clients() == [1], "the registry still holds exactly one binding")


func _t_rate_limit() -> void:
	var rig := _rig()
	var a := _join(rig, 1, "Остап", KYIV.x, KYIV.y, 0)
	for i in 20:
		rig.tr.client_send(a.peer, Protocol.ping(1))
	rig.srv.tick(10)
	var limited := 0
	for m in rig.tr.client_recv(a.peer):
		if m.t == "refuse" and m.reason == "rate_limited":
			limited += 1
	ok(limited == 20 - RealmServer.MAX_MSGS_PER_TICK, "messages beyond the per-tick budget are refused as rate_limited (%d)" % limited)
	rig.srv.tick(20)
	rig.tr.client_send(a.peer, Protocol.ping(1))
	rig.srv.tick(30)
	ok(rig.tr.client_recv(a.peer).is_empty(), "the budget resets every tick")


func _t_expiry_and_close() -> void:
	var rig := _rig()
	rig.srv.ttl_ms = 30000
	var a := _join(rig, 1, "A", KYIV.x, KYIV.y, 0)
	var b := _join(rig, 2, "B", KYIV.x, KYIV.y, 0)
	rig.tr.client_send(b.peer, Protocol.ping(2))
	rig.srv.tick(25000)
	rig.srv.tick(40000)
	ok(rig.srv.bound_clients() == [2], "a silent client is expired after ttl, the pinging one stays")
	ok(not rig.tr.is_connected_peer(a.peer), "the expired client's connection is dropped")
	ok(rig.srv.stats.expired == 1, "expiry is counted")
	rig.tr.client_close(b.peer)
	rig.srv.tick(41000)
	ok(rig.srv.bound_clients().is_empty() and rig.srv.realm.count() == 0, "closing the socket removes the player from the realm")
	var c := _join(rig, 3, "C", KYIV.x, KYIV.y, 50000)
	rig.tr.client_send(c.peer, Protocol.bye(3))
	rig.srv.tick(51000)
	ok(rig.srv.realm.count() == 0 and not rig.tr.is_connected_peer(c.peer), "bye leaves the realm and drops the connection")


func _t_determinism() -> void:
	var views: Array = []
	for order in [[1, 2, 3, 4], [4, 3, 2, 1]]:
		var rig := _rig()
		var peers := {}
		for id in order:
			var p := _pt(float(id * 70), 150.0 * float(id))
			var peer: int = rig.tr.connect_client()
			rig.tr.client_send(peer, Protocol.hello(int(id), "P%d" % int(id), float(p.lat), float(p.lon)))
			peers[int(id)] = peer
		rig.srv.tick(1000)
		var h := ""
		for id in [1, 2, 3, 4]:
			h += Persistence.content_hash(rig.srv.realm.presence_view(id))
		views.append(h)
	ok(views[0] == views[1], "the same players joining in opposite order produce identical presence views")


func _t_local_realm() -> void:
	var a := LocalRealm.new("Ти", KYIV.x, KYIV.y, 1000)
	a.tick(2000)
	var va: Dictionary = a.view()
	ok(bool(va.available) and va.total == LocalRealm.AMBIENT_COUNT and va.sim == LocalRealm.AMBIENT_COUNT and va.live == 0, "solo hero sees the simulated survivors, all labelled sim")
	ok(float(va.aoi_m) == Realm.DEFAULT_AOI_M and str(va.region) != "", "the hero went through the real client/server path (welcome carried aoi and region)")
	var b := LocalRealm.new("Ти", KYIV.x, KYIV.y, 999999)
	b.tick(1000000)
	var names_a: Array = []
	var names_b: Array = []
	for r in va.rows:
		names_a.append(str(r.name))
	for r in b.view().rows:
		names_b.append(str(r.name))
	names_a.sort()
	names_b.sort()
	ok(names_a == names_b, "coordinates are the seed: the same place gets the same neighbours at any time")
	var before_total: int = int(va.total)
	var steps_ok := true
	for t in range(3000, 120000, 1000):
		a.tick(t)
		if not a.view().refusal == "":
			steps_ok = false
	ok(steps_ok and int(a.view().total) == before_total, "two minutes of wandering never trips the GPS guard and nobody leaves the radar")
	a.tick(120100)
	var calls: int = a.server.tick_no
	a.tick(120200)
	ok(a.server.tick_no == calls, "the layer throttles itself to one step per second of device time")
	a.relocate(35.6762, 139.6503, 130000)
	a.tick(131000)
	var vt: Dictionary = a.view()
	ok(vt.available and vt.total == LocalRealm.AMBIENT_COUNT and str(vt.region) != str(va.region), "relocating (travel) re-joins elsewhere with that place's own neighbours")
	ok(a.realm.count() == 1 + LocalRealm.AMBIENT_COUNT, "the old place's survivors were removed (no ghosts follow the hero)")


func _t_session_integration() -> void:
	var s := Session.new()
	s.autosave = false
	ok(not bool(s.nearby_view().available), "a session before start has no presence layer")
	s.tick_realm(1000)
	ok(s.realm_net == null, "tick_realm without a world is inert")
	ok(s.start(50.4501, 30.5234, "Київ", 5000), "session starts")
	s.tick_realm(6000)
	s.tick_realm(8000)
	var v: Dictionary = s.nearby_view()
	ok(bool(v.available) and int(v.total) == LocalRealm.AMBIENT_COUNT, "after tick_realm the session exposes nearby value data")
	ok(v.has("map") and int(v.map.n) == 56 and Marshalls.base64_to_raw(str(v.map.tiles)).size() == 56 * 56, "nearby_view carries the region terrain (base64, n*n tiles)")
	ok(absf(float(v.map.hero.x) - float(s.sim.player.px)) < 0.001 and float(v.cell_m) == 760.0, "and the hero tile and the metres-per-cell scale for the minimap")
	ok(v.map.capsule is Dictionary and (v.map.capsule as Dictionary).is_empty() and JSON.parse_string(JSON.stringify(v.rows)) is Array, "capsule tile is absent while the capsule flag is OFF; the rows are JSON-safe")
	var hash_before := Persistence.world_hash(s.sim)
	for t in range(9000, 30000, 1000):
		s.tick_realm(t)
	ok(Persistence.world_hash(s.sim) == hash_before, "presence never touches the sim: world_hash is unchanged by 20 s of realm ticks")
	ok(s.start(35.6762, 139.6503, "Кіото", 40000) and s.realm_net == null, "starting a new world drops the old presence layer")

func _t_websocket() -> void:
	var ws := Transport.WebSocketServer.new()
	var port := 18931
	if ws.listen(port) != OK:
		ok(false, "websocket server could not listen on %d" % port)
		return
	var srv: Variant = RealmServer.new(Realm.new(GeoGrid.new(), 1200.0), ws, "ws")
	var peers: Array = []
	var clients: Array = []
	for i in 2:
		var c := WebSocketPeer.new()
		c.connect_to_url("ws://127.0.0.1:%d" % port)
		peers.append(c)
		clients.append(RealmClient.new(i + 1))
	var sent := [false, false]
	var now := 0
	var got_view := false
	for step in 400:
		now += 100
		for i in 2:
			peers[i].poll()
			if peers[i].get_ready_state() == WebSocketPeer.STATE_OPEN:
				if not sent[i]:
					var p := _pt(90.0, 200.0 * float(i))
					peers[i].send_text(JSON.stringify(Protocol.hello(i + 1, "WS%d" % (i + 1), float(p.lat), float(p.lon))))
					sent[i] = true
				while peers[i].get_available_packet_count() > 0:
					clients[i].handle(JSON.parse_string(peers[i].get_packet().get_string_from_utf8()))
		srv.tick(now)
		if clients[0].nearby_rows().size() == 1 and clients[1].nearby_rows().size() == 1:
			got_view = true
			break
		OS.delay_msec(5)
	ok(got_view, "two real WebSocket clients join, bind and see each other through deltas")
	ok(got_view and clients[0].nearby_rows()[0].dir == "Сх", "the over-the-wire bearing is correct (A sees B east)")
	for c in peers:
		c.close()
	for step in 40:
		now += 100
		for c in peers:
			c.poll()
		srv.tick(now)
		if srv.realm.count() == 0:
			break
		OS.delay_msec(5)
	ok(srv.realm.count() == 0, "closing the sockets empties the realm")
	ws.close_all()

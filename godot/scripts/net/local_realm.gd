# RealWorld — net/local_realm.gd : the in-process RealGPS stack for single-player play (spec 0013 §3.10).
#
# The solo game talks to the SAME server logic a hosted realm runs: the hero is a RealmClient behind a
# Loopback transport into a RealmServer over a Realm — nothing here is a mock of the network, it is the
# network without a socket. Pointing `transport` at a WebSocketServer (and the client at a socket) is the
# only change a hosted realm needs, which is the whole point of the RealmServer/Transport seam.
#
# Other survivors in solo play are SIMULATED, honestly labelled KIND_SIM on the wire: a pure function of
# the region coordinate ("coordinates are the seed") — same place, same neighbours, every visit, no RNG
# state and no clock read (now_ms is always passed in). They wander on slow circles so the radar lives.
# Spec 0002's Social.new_graph is the seam a real backend replaces; so is this class's bot list.
extends RefCounted

const Geo = preload("res://scripts/net/geo.gd")
const GeoGrid = preload("res://scripts/net/geo_grid.gd")
const Protocol = preload("res://scripts/net/realm_protocol.gd")
const Realm = preload("res://scripts/net/realm.gd")
const RealmClient = preload("res://scripts/net/realm_client.gd")
const RealmServer = preload("res://scripts/net/realm_server.gd")
const ShardRouter = preload("res://scripts/net/shard_router.gd")
const Social = preload("res://scripts/social.gd")
const Transport = preload("res://scripts/net/transport.gd")

const HERO_ID := 1
const SIM_ID_BASE := 1000
const AMBIENT_COUNT := 3
const AMBIENT_MIN_M := 250
const AMBIENT_SPAN_M := 700
const WANDER_R_M := 60.0
const WANDER_PERIOD_MS := 600000
const STEP_EVERY_MS := 1000       # the layer advances at most once a second of device time
const ROWS_IN_VIEW := 6

var realm: Variant = null
var transport: Variant = null
var server: Variant = null
var client: Variant = null
var hero_name: String = "Ти"
var hero_lat: float = 0.0
var hero_lon: float = 0.0

var _peer: int = -1
var _last_ms: int = -1
var _bots: Array = []      # {id, name, lat, lon, phase}  (anchor + wander phase)


func _init(p_hero_name: String, lat: float, lon: float, now_ms: int, aoi_m: float = Realm.DEFAULT_AOI_M) -> void:
	hero_name = p_hero_name
	realm = Realm.new(GeoGrid.new(), aoi_m)
	transport = Transport.Loopback.new()
	server = RealmServer.new(realm, transport, "local")
	server.ttl_ms = 10 * 60 * 1000   # solo: a heartbeat every step, so only a long stall expires us
	_enter(lat, lon, now_ms)


# Advance the layer to `now_ms`. Cheap to call every frame — it throttles itself.
func tick(now_ms: int) -> void:
	if _last_ms >= 0 and now_ms - _last_ms < STEP_EVERY_MS:
		return
	_last_ms = now_ms
	for b in _bots:
		var p: Dictionary = _bot_pos(b, now_ms)
		realm.move(int(b.id), float(p.lat), float(p.lon), now_ms)
	transport.client_send(_peer, Protocol.ping(HERO_ID))
	server.tick(now_ms)
	client.handle_all(transport.client_recv(_peer))


# The hero's region changed (travel / respawn elsewhere): an explicit relocation — leave, re-join, and
# let the new place's neighbours appear. A relocation is NOT a GPS fix, so the speed guard is bypassed
# by design (the relocation limit is an open owner decision, OD-17/22).
func relocate(lat: float, lon: float, now_ms: int) -> void:
	if absf(lat - hero_lat) < 0.00001 and absf(lon - hero_lon) < 0.00001:
		return
	transport.client_send(_peer, Protocol.bye(HERO_ID))
	server.tick(now_ms)
	for b in _bots:
		realm.leave(int(b.id))
	_enter(lat, lon, now_ms)


# Value data for the HUD NearbyPanel (R8): plain numbers/strings, no refs, no sockets.
func view() -> Dictionary:
	if client == null or not bool(client.joined):
		return {"available": false}
	var rows: Array = client.nearby_rows()
	var live := 0
	for r in rows:
		if str(r.kind) == Realm.KIND_LIVE:
			live += 1
	var refusal := ""
	if not (client.refusals as Array).is_empty():
		refusal = str(client.refusals[(client.refusals as Array).size() - 1].reason)
	return {
		"available": true,
		"region": str(client.cell),
		"pop": int(client.view.get("region_pop", 1)),
		"aoi_m": float(client.aoi_m),
		"live": live,
		"sim": rows.size() - live,
		"total": rows.size(),
		"rows": rows.slice(0, ROWS_IN_VIEW),
		"refusal": refusal,
	}


# ---------------- internals ----------------
func _enter(lat: float, lon: float, now_ms: int) -> void:
	hero_lat = lat
	hero_lon = lon
	_peer = transport.connect_client()
	client = RealmClient.new(HERO_ID)
	transport.client_send(_peer, Protocol.hello(HERO_ID, hero_name, lat, lon))
	_bots = _ambient(lat, lon)
	for b in _bots:
		var p: Dictionary = _bot_pos(b, now_ms)
		realm.join(int(b.id), str(b.name), float(p.lat), float(p.lon), now_ms, Realm.KIND_SIM)
	_last_ms = -1
	tick(now_ms)


# The neighbours of a place: a pure function of its canonical coordinate string.
static func _ambient(lat: float, lon: float) -> Array:
	var canon := GeoGrid.new().region_of(GeoGrid.new().cell_of(lat, lon)).canon as String
	var out: Array = []
	for i in AMBIENT_COUNT:
		var h1 := ShardRouter.score("ambient_dir_%d" % i, canon)
		var h2 := ShardRouter.score("ambient_dist_%d" % i, canon)
		var h3 := ShardRouter.score("ambient_name_%d" % i, canon)
		var h4 := ShardRouter.score("ambient_phase_%d" % i, canon)
		var p := Geo.destination(lat, lon, float(h1 % 3600) / 10.0, float(AMBIENT_MIN_M + h2 % AMBIENT_SPAN_M))
		out.append({"id": SIM_ID_BASE + i, "name": Social.PERSON_NAMES[h3 % Social.PERSON_NAMES.size()],
			"lat": float(p.lat), "lon": float(p.lon), "phase": float(h4 % 3600) / 10.0})
	return out


static func _bot_pos(b: Dictionary, now_ms: int) -> Dictionary:
	var brg := fposmod(float(b.phase) + 360.0 * float(now_ms % WANDER_PERIOD_MS) / float(WANDER_PERIOD_MS), 360.0)
	return Geo.destination(float(b.lat), float(b.lon), brg, WANDER_R_M)

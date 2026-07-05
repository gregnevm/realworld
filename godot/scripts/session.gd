# RealWorld — session.gd : world/session orchestration (spec 0002 refactor)
#
# Owns the multi-region persistent world (Persistence store), the social graph, and the home base,
# and drives region travel + permadeath respawn. Extracted out of main.gd so this state machine is
# scene-free and headless-testable — main.gd keeps only rendering, input and UI. The live sim for
# the active region is `sim`; travelling swaps its contents in place (same instance).
extends RefCounted

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Social = preload("res://scripts/social.gd")
const Persistence = preload("res://scripts/persistence.gd")
const MAP_N := 56
const STORE_PATH := "user://world.json"

var sim
var store: Dictionary = {}
var social: Dictionary = {}
var home := {"lat": 0.0, "lon": 0.0, "name": ""}
var has_home := false   # explicit — a legitimate spawn at (0,0) must not read as "no home"
var autosave := true   # tests disable disk writes

func start(lat: float, lon: float, place_name: String) -> void:
	var m := WorldGen.generate_map(lat, lon, MAP_N)
	m["place_name"] = place_name
	sim = Sim.new()
	sim.new_game(m)
	store = Persistence.store_new()
	social = Social.new_graph("Ти", WorldGen.hash_seed(lat, lon), lat, lon)
	sim.social = social
	home = {"lat": lat, "lon": lon, "name": place_name}
	has_home = true
	# seed a couple of friend invites so the capsule flow has content immediately
	for i in range(min(3, social.friends.size())):
		sim.add_invite(Social.friend_invite(social, i, sim.capsule.radius_km))
	sim._log("Висадка: %s · біом %s" % [place_name, m.biome], "good")
	sim._log("Клан: %s · рейди від ворожих фракцій." % Social.my_clan(social).name)

# Serialize the active region into the store (seed + diff + save), advancing the hash chain.
func commit_region() -> void:
	Persistence.store_commit(store, Persistence.serialize_region(sim))
	if autosave:
		Persistence.save_to_file(store, STORE_PATH)

# Persist the current region, fly the pawn to (lat,lon), then load it (if visited) or generate it.
func travel_to(lat: float, lon: float, place_name: String) -> void:
	if sim == null:
		return
	commit_region()
	var pawn: Dictionary = sim.extract_pawn()
	var gday: int = int(sim.time.day)      # the clock is account-global, not per-region
	var gfrac: float = float(sim.time.frac)
	var key := Persistence.region_key(lat, lon)
	if Persistence.store_has(store, key):
		sim.load_region(Persistence.store_get(store, key))
		sim.apply_pawn(pawn)
		sim._log("↩ Повернення в %s." % str(sim.map.get("place_name", place_name)), "good")
	else:
		var m := WorldGen.generate_map(lat, lon, MAP_N)
		m["place_name"] = place_name
		sim.arrive_region(m, pawn)
		sim._log("🛬 Нова місцевість: %s · біом %s." % [place_name, m.biome], "good")
	sim.social = social
	sim.time.day = gday
	sim.time.frac = gfrac

# Permadeath: a fresh pawn at the clan home. If you died away, fly home first (region identity,
# NOT presence of any storage — you may have built one at a remote outpost).
func respawn() -> void:
	var cur_key := Persistence.region_key(float(sim.map.lat), float(sim.map.lon))
	var home_key := Persistence.region_key(float(home.lat), float(home.lon))
	if has_home and cur_key != home_key:
		travel_to(home.lat, home.lon, home.name)
	sim.respawn_new_pawn()

func stored_region_count() -> int:
	return (store.get("regions", {}) as Dictionary).size()

func chain_head() -> String:
	return str(store.get("head", ""))

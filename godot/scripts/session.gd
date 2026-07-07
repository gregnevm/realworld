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
const Catalog = preload("res://scripts/kernel/catalog.gd")
const Production = preload("res://scripts/kernel/production.gd")
const Things = preload("res://scripts/kernel/things.gd")
const GameData = preload("res://scripts/data.gd")
const MAP_N := 56
const STORE_PATH := "user://world.json"

var sim
var store: Dictionary = {}
var social: Dictionary = {}
var home := {"lat": 0.0, "lon": 0.0, "name": ""}
var has_home := false   # explicit — a legitimate spawn at (0,0) must not read as "no home"
var autosave := true   # tests disable disk writes

# --- the Batch-6 kernel world (account-level, survives region travel) --------------------------------
# Carries the full content catalogue (db), the research state, and the kernel Things (benches with
# bills, crops...). `stock` is re-aliased to sim.stock every tick because travel/respawn can swap the
# sim's dictionary identity. Ticked by kernel_tick() with elapsed GAME-DAYS (the kernel's dday unit).
var kernel: Dictionary = {}
var _kernel_reg   # Systems.SystemRegistry running the kernel systems (production for now)

func _init_kernel() -> void:
	var db = Catalog.build_db()
	kernel = {
		"db": db,
		"research": Production.ResearchState.new(db),
		"things": [],
		"spawn": [],
		"zones": [],
	}
	_kernel_reg = Production.build_production()

# Advance the kernel world by `dday` game-days. Seeds the kernel rng from the region seed on first use
# (deterministic quality rolls), syncs benches with the sim's station buildings, advances the active
# research project (needs a built research bench), ticks the systems, then drains spawned Things
# (their stock tally IS the playable inventory; per-item quality becomes a live surface later).
func kernel_tick(dday: float) -> void:
	if kernel.is_empty() or sim == null or dday <= 0.0:
		return
	kernel["stock"] = sim.stock
	if not (kernel.get("rng") is RandomNumberGenerator):
		var rng := RandomNumberGenerator.new()
		rng.seed = sim.region_seed()
		kernel["rng"] = rng
	_sync_benches()
	var research = kernel.research
	var active_id: StringName = research.active
	if active_id != &"" and has_research_bench() and research.advance(dday):
		var d = kernel.db.get_def(active_id)
		var label: String = String(d.field(&"label", active_id)) if d != null else String(active_id)
		sim._log("🔬 Дослідження завершено: %s" % label, "good")
	_kernel_reg.tick_all(kernel, {"dday": dday})
	if not (kernel.spawn as Array).is_empty():
		kernel.spawn.clear()

# --- benches: one kernel workbench Thing per station building the sim has built ----------------------
# Keyed "kind:x:y"; a demolished/destroyed building drops its bench (and its bill queue) next tick;
# travelling to another region swaps sim.buildings, so foreign benches drop automatically too.
func _sync_benches() -> void:
	if not kernel.has("bench_keys"):
		kernel["bench_keys"] = {}
	var by_key: Dictionary = kernel.bench_keys
	var live := {}
	for b in sim.buildings:
		var st := String(GameData.BUILDINGS.get(b.kind, {}).get("station", ""))
		if st == "":
			continue
		var key := "%s:%d:%d" % [b.kind, int(b.x), int(b.y)]
		live[key] = true
		if by_key.has(key):
			var wb0 = by_key[key].get_comp(Production.CompWorkbench)
			if wb0 != null:
				wb0.props["maker_level"] = float(sim.player.skills.get("gather", 0.0))
			continue
		var thing = Things.Thing.new(null)
		thing.flags["building"] = StringName(str(b.kind))
		thing.flags["bkey"] = key
		thing.add_comp(Production.CompWorkbench.new({
			"station": st, "maker_level": float(sim.player.skills.get("gather", 0.0))}))
		kernel.things.append(thing)
		by_key[key] = thing
	for key in by_key.keys():
		if not live.has(key):
			var t = by_key[key]
			t.destroyed = true
			kernel.things.erase(t)
			t.detach()
			by_key.erase(key)

func has_research_bench() -> bool:
	if sim == null:
		return false
	for b in sim.buildings:
		if bool(GameData.BUILDINGS.get(b.kind, {}).get("extra", {}).get("research", false)):
			return true
	return false

# The kernel bench Thing for a sim building (null if it isn't a station or isn't synced yet).
func bench_for(b) -> Variant:
	if kernel.is_empty():
		return null
	_sync_benches()
	return (kernel.bench_keys as Dictionary).get("%s:%d:%d" % [b.kind, int(b.x), int(b.y)], null)

# UI seam: queue a bill on a station building. mode &"count"/&"until". Returns ok+msg for a flash.
func add_bill(b, recipe_id: StringName, mode: StringName, target: int) -> Dictionary:
	var bench = bench_for(b)
	if bench == null:
		return {"ok": false, "msg": "Це не верстат."}
	var recipe = kernel.db.get_def(recipe_id)
	if recipe == null:
		return {"ok": false, "msg": "Невідомий рецепт."}
	if not Production.can_make(recipe, kernel.research):
		return {"ok": false, "msg": "🔒 Спершу дослідження."}
	bench.get_comp(Production.CompWorkbench).add_bill(Production.Bill.new(recipe_id, mode, target))
	return {"ok": true}

func start(lat: float, lon: float, place_name: String) -> void:
	_init_kernel()
	var m := WorldGen.generate_map(lat, lon, MAP_N)
	m["place_name"] = place_name
	sim = Sim.new()
	sim.new_game(m)
	sim.research = kernel.research   # Batch 7: build gating reads the account research state
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

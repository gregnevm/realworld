# RealWorld — tests/run_capsule_balance.gd : the ECONOMY BOT of spec 0010 (informational, NOT a CI gate — like run_perf).
#
# The owner DECIDED (decisions.md): a level costs ~1–2 hours of gathering at 1:1 for level 1 (OD-93), ×2 per level (OD-65/93); the defence
# axis is ×2 per level, ×16 at level 5 (OD-103); the buffs are +10% per level, +50% at level 5 (OD-98); the solo zone radius is ~50 m, static
# (OD-99). What the owner did NOT decide is only PROPOSED here, by this executable method (the owner approves at merge, data status:"proposed"):
# the concrete resources of the level-1 price (OD-93 gives hours, not items), the price of the defence axis (Q-5), the radius in CELLS (Q-4),
# the core-HP base (the reference raider). Run:  godot --headless --path godot -s res://tests/run_capsule_balance.gd
#   1. INCOME + SUPPLY — a deterministic gather bot (nearest tree / rock / scrap node, use_inventory + use_catalog + use_main_capsule ON,
#      600 sim-s, stash trips to the capsule when the pack is full) on the 5 SPAWN_PRESETS, for two equipment tiers (bare hands; tier-1 tool).
#      Output: units/min per resource (median over presets) and the region's FINITE node supply (nodes never regrow).
#      Planks are not gathered: income[planks] = income[wood] x the catalogue recipe ratio (make_planks: 3 wood -> 2 planks).
#   2. COST (the method, owner numbers in capitals): cost_L[res] = round(T_L x income_hand[res] x share_L[res]), T_L = T_1 x LADDER^(L-1),
#      T_1 = 90 min (the middle of OD-93's 1–2 h), LADDER = 2 (OD-65/93). The weight of a level is its GATHER-MINUTES at the bare-hand income (the unit
#      OD-93 itself speaks); one income basis for all levels keeps the unit totals at ~x2 too. share_L spreads the minutes over the resources so that
#      the prices get RARER with the level (OD-75: level 1 — basic raw wood/stone; planks (processed) from level 2; scrap (the rarest node) from
#      level 3 on, growing): the shares are PROPOSED hypotheses, the rarity rank wood < stone < planks < scrap mirrors the finite supply order.
#      The same method prices the defence axis (Q-5 A: «за тими самими правилами, що й рівня»).
#   3. FEASIBILITY + SCALE (OD-109, 2026-11-07: «ціни вниз», x2 per level stays, the number is PROPOSED by this method): the owner's literal formula
#      (scale 1.0 = T_1 90 gather-min) does not fit the finite 56x56 map (the BEFORE table). The bot therefore SOLVES one uniform scale g (the same for every
#      level and resource, so x2 per level and the composition stay) by an EXPLICIT CRITERION, checked on the ROUNDED integer prices that go into the data:
#        C1 supply — for EVERY one of the 5 presets and EVERY finite resource (wood-equivalent: planks count 1/ratio wood, stone, scrap) the cumulative price of
#           levels 1..5 of BOTH axes (capsule + protection, Q-5 A: the same prices) <= RESERVE_CAP of the region's nodes (nodes never regrow here; the other
#           1 - RESERVE_CAP stays for building, tools, crafting);
#        C2 pack — the level-1 price fits the backpack (PACK_SLOTS slots, stacks by Inventory.stack_max);
#        C3 ladder — total units of level L / level L-1 within LADDER_TOL of x2 AFTER rounding, and every listed resource >= 1;
#        C4 order — level 1 is basic raw only (OD-75) and the rarest ingredient never gets more common (RARITY rank).
#      g = the largest multiple of SCALE_STEP that passes C1..C4. HONEST output: level 1 is then g x 90 gather-minutes, NOT 60..120 — the owner's 1–2 h
#      holds only if gathering is g x 90 / (60..120) of the PLAY time (printed). Alternatives printed as a diagnosis: composition balanced to the supply,
#      tools (pace, not supply), map size (OD-110 open: neighbouring maps are not in this work).
#   4. DEFENCE — core_hp(P) = base x FACTOR^(P-1), P >= 1 (OD-103: x2 per level, x16 at 5), P = 0 is base / FACTOR; base = what the REFERENCE raid
#      (the weakest: day_equiv 4 through the EXISTING GameData.make_raider / raid_wave_size) deals to an undefended core in T_OPEN_REF seconds
#      (working interpretation until Q-5; the raider strength by capsule level is Balance.assess, a later wave).
#   5. RADIUS — R_cells = ceil(RADIUS_M / CELL_M); CELL_M is the ONLY trace of a map scale in the code (the frozen main.gd _fetch_osm: a 380 m radius
#      over the 56-cell map = 760 m / 56 cells); the live procedural map has none — Q-4, a proposal until the owner fixes N m per cell.
#   6. BUFFS — the owner's +10% per level (OD-98): printed, with the payback of a level's price through the gather buff (informational).
#   7. RAID (W3a, REQ-0010-62/81/112; OD-65/87/88): the numbers the owner did NOT decide, PROPOSED by this method: (a) wealth_ref_points = the median
#      Balance.assess threat of the freshly landed base over the 5 presets (a base at this wealth meets the by_level row as written; richer — more raiders, REQ-0010-87);
#      (b) by_level = {count, day_equiv} per capsule level: the raider POWER measure count x dmg x hp (the two things the defender must out-last and out-kill) doubles
#      per level (OD-65 decided) starting from the reference raid (day_equiv 4 x raid_wave_size = the SAME raid that anchors core_hp(1)); a grid search over count
#      (non-decreasing, <= COUNT_MAX) and day_equiv (non-decreasing) picks the row with the smallest relative error; (c) roll_spread = the smallest candidate that
#      leaves the breach probability strictly inside (0,1) across a +-10% power band around the core (a spread of 0 turns the roll into a coin that never lands: the
#      raid either always or never breaks); (d) queue_max = the largest number of raid payloads the Balance roster fires in ONE tick (it fires <= 1 big threat per
#      tick and gates on threat_active), over 5 presets x RAID_TICKS ticks — a waiting raid needs no more room than that; (e) take_round = the rounding mode that never
#      lets the attacker take MORE than the defender keeps, checked over every ledger row the proposed prices can produce. DECIDED numbers (immunity 24 h, 50%, grace
#      3 days, warning 10..30 min — OD-24/107/66/88) are printed verbatim, not derived.
#   8. W3b (REQ-0010-18/19/70; OD-65/66/86/88): (a) HOLD vs BREAK — for L = 1..5 a LIVE raid (the Sim.update path, capsule level L, protection P = L, no defenders but the
#      core) of the by_level row grows (count bisection, day_equiv fixed) until it breaches the core inside the ASSAULT window; k_L = that minimal count / the row's count,
#      and the defence price (gather-minutes of protection level L) against the attack «price» (the breaching power in units of the level-1 reference raid, anchored to T_1
#      gather-minutes — a PROPOSED anchor) gives a_L = defence : attack (REQ-0010-18 needs a_L < 1); (b) CADENCE — N days of the injected clock (set_clock advances
#      CLOCK_STEP_MS per tick, independent of the tick count: REQ-0010-93) x 5 presets, the intervals between raid warnings (capsule_events drained like a push consumer):
#      histogram + mean (OD-86: 3..4 days) + the minimal gap + «no raid before grace + first upgrade»; (c) WARNING — contact_at - warn_at of every raid, and the hero's walk
#      from the farthest reachable cell to the capsule against warn_min (REQ-0010-19/71). Run only this part: `-- w3b`.
# Finally it prints MATCH/DIFF of every proposed number against godot/content/catalog.json (capsule_levels), so the data cannot drift from the
# method unnoticed. The pass/fail counter only says the probe ran — read the printed tables.
extends "res://tests/harness.gd"

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const Inventory = preload("res://scripts/sim/inventory.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const Director = preload("res://scripts/sim/director.gd")
const KernelBalance = preload("res://scripts/kernel/balance.gd")

const DT := 0.1                    # the production tick step
const MEASURE_S := 600.0           # 10 sim-minutes of continuous gathering per (preset, resource, tier)
const MAP_N := 56                  # Session.MAP_N
const STUCK_S := 15.0             # a gather target whose amount has not dropped for this long is skipped
const COMFORT_TARGET_C := 20.0     # the bot measures the ECONOMY, not survival: a standing regional shift pins the ambient near 20 C in every preset
const STASH_TRIGGER_ROOM := 3      # fewer free units than this for the gathered resource: walk to the capsule and stash (a real player does)
const NODE_OF := {"wood": "tree", "stone": "rock", "scrap": "scrap"}
const TOOL_FOR := {"wood": "axe", "stone": "pick", "scrap": "pick"}
const GATHERED := ["wood", "stone", "scrap"]
const LEVELS := 5

# ---- the OWNER's numbers (decisions.md) ----
const LADDER := 2.0                # OD-65/93: every level costs ~x2 (the same coefficient for the defence axis, OD-103)
const T1_MIN := 90.0               # OD-93: level 1 ~ 1–2 hours of gathering at 1:1 -> the middle, 1.5 h (the UNSCALED weight; OD-109 scales it down by g)
const BUFF_STEP := 0.10            # OD-98: +10% per level, +50% at level 5
const RADIUS_M := 50.0             # OD-99: ~50 m, static
const PROTECTION_FACTOR := 2.0     # OD-103: x2 per defence level, x16 at level 5 (relative to level 1)

# ---- the PROPOSAL knobs (the METHOD's hypotheses — change here, re-run, re-sync catalog.json) ----
# time shares of the level's gather-minutes: rarer with the level (OD-75): L1 basic raw; planks from L2; scrap (the rarest node) from L3
const SHARES := {
	1: {"wood": 0.60, "stone": 0.40},
	2: {"wood": 0.40, "stone": 0.30, "planks": 0.30},
	3: {"wood": 0.30, "stone": 0.25, "planks": 0.25, "scrap": 0.20},
	4: {"wood": 0.25, "stone": 0.25, "planks": 0.20, "scrap": 0.30},
	5: {"wood": 0.20, "stone": 0.20, "planks": 0.20, "scrap": 0.40},
}
const RARITY := {"wood": 0, "stone": 1, "planks": 2, "scrap": 3}   # rank by finite supply order (planks = processed wood) — the data tests mirror it
const CELL_M := 760.0 / 56.0       # frozen main.gd _fetch_osm: 2 x 380 m over MAP_N cells — the only scale trace in the code (Q-4)
const REF_DAY_EQUIV := 4           # the weakest raid the old ladder opened with (GameData.make_raider day_equiv)
const T_OPEN_REF_S := 20.0         # seconds an UNDEFENDED core holds against the reference raid (hypothesis 20–30 s)
const BUILDING_ATK_CD := 1.0       # threats.gd: a raider swings at a building once per 1.0 s
const PACK_SLOTS := 24             # the backpack proper (slots 8..31); the hotbar holds tools/buildings
const BASE_STORAGE_ROOM := 450     # storage_cap() at the start: 200 + the capsule's 250 (GameData.BUILDINGS.storage.capacity)
const STORAGE_STEP := 250

# ---- the SCALE criterion (OD-109): PROPOSED knobs of the method ----
const AXES := 2                    # the capsule axis and the protection axis carry the same prices (Q-5 A): a full 0->5 on both buys the ladder twice
const RESERVE_CAP := 0.60          # C1: both axes together may take at most this fraction of a region's finite nodes (= 30% per axis, the former SUPPLY_BUDGET)
const SCALE_STEP := 0.0001         # the scale is a multiple of this (the data carries rounded integers)
const LADDER_TOL := 0.15           # C3: |total(L)/total(L-1) - LADDER| <= LADDER * LADDER_TOL after rounding (tests/catalog.test.js accepts 1.6..2.4)

# ---- RAID (W3a): the OWNER's numbers ----
const IMMUNITY_MS := 86400000          # OD-24: 24 h
const TAKE_PERCENT := 50               # OD-107: 50% of invested[L]
const GRACE_MS := 259200000            # OD-66: 3 days from the first landing
const WARN_MIN_MS := 600000            # OD-88: 10 min
const WARN_MAX_MS := 1800000           # OD-88: 30 min
const LEVEL_FACTOR := 2.0              # OD-65: the raid is x2 harder per capsule level
# ---- RAID (W3a): the method's knobs ----
const COUNT_MAX := 30                  # Balance._exec_raid clamps a raid to 1..30 raiders
const DAY_EQUIV_MAX := 60
const SPREAD_CANDIDATES := [0.0, 0.1, 0.25, 0.5]
const BAND := 0.10                     # +-10% power band around the core for the spread rule
const RAID_TICKS := 100000             # Balance ticks per preset for the queue_max measurement (dt 0.1 s -> ~2.8 h of sim)


var _scale: float = 1.0            # the solved g (OD-109); 1.0 = the owner's literal formula


func _init() -> void:
	print("== RealWorld capsule ECONOMY BOT (spec 0010, informational) ==")
	if "w3b" in OS.get_cmdline_user_args():
		_w3b_report({})
		ok(true, "W3b probe completed — read the tables above")
		finish()
		return
	var income_hand: Dictionary = {}
	var income_tool: Dictionary = {}
	var supply: Dictionary = {}
	var by_preset: Array = []
	_measure_income(income_hand, income_tool, supply, by_preset)
	var planks_ratio: float = _planks_per_wood()
	print("\n-- planks per wood from the catalogue recipe make_planks: %.4f (1 plank = %.2f wood)" % [planks_ratio, 1.0 / planks_ratio])
	var inc_hand: Dictionary = _medians(income_hand)
	var inc_tool: Dictionary = _medians(income_tool)
	inc_hand["planks"] = float(inc_hand["wood"]) * planks_ratio
	inc_tool["planks"] = float(inc_tool["wood"]) * planks_ratio
	print("\n-- income used for the ladder (units/min, median over the 5 presets) --")
	for res in ["wood", "stone", "scrap", "planks"]:
		print("   %-7s hand %6.2f   tool %6.2f" % [res, float(inc_hand[res]), float(inc_tool[res])])
	print("\n-- finite node SUPPLY per region (units; nodes never regrow) --")
	for res in GATHERED:
		var arr: Array = (supply[res] as Array).duplicate()
		arr.sort()
		print("   %-6s min %5d  median %5d  max %5d" % [String(res), int(arr[0]), int(arr[arr.size() / 2]), int(arr[arr.size() - 1])])
	var before: Array = _ladder(inc_hand, 1.0)
	_scale = _solve_scale(inc_hand, by_preset, planks_ratio)
	var capsule: Array = _ladder(inc_hand, _scale)
	_print_ladder("BEFORE (OD-93/65 literal, scale 1.0): T_1=%.0f min x %.0f per level over the bare-hand income — the former catalog.json table" % [T1_MIN, LADDER], before, inc_hand)
	_print_ladder("AFTER (OD-109): the same method x g = %.4f -> T_1 = %.2f gather-min x %.0f per level (the PROPOSAL; both axes, Q-5 A: identical prices)" % [_scale, T1_MIN * _scale, LADDER], capsule, inc_hand)
	print("   protection axis (Q-5 A: the SAME rules) — identical prices by construction: %s" % str(capsule == _ladder(inc_hand, _scale)))
	_feasibility_report(before, capsule, inc_hand, inc_tool, by_preset, supply, planks_ratio)
	var hp: Array = _defence_report()
	var cells: int = _radius_report()
	_buff_report(capsule, inc_hand)
	var raid: Dictionary = _raid_report(capsule)
	_compare_with_catalog(capsule, hp, cells)
	_compare_raid(raid)
	_w3b_report(inc_hand)
	ok(true, "probe completed — read the tables above (they are the PROPOSAL; the owner approves at merge)")
	finish()


# keep the hero alive and fed: the bot measures the ECONOMY, not survival
func _topup(sim: Variant) -> void:
	sim.player.hp = 100.0
	sim.player.hunger = 100.0
	sim.player.rest = 100.0


func _new_world(preset: Dictionary) -> Variant:
	var sim: Variant = Sim.new()
	sim.use_inventory = true
	sim.use_catalog = true
	sim.use_main_capsule = true
	sim.new_game(WorldGen.generate_map(float(preset.lat), float(preset.lon), MAP_N), false)
	return sim


# nearest node of `kind` that is not in `skip` (squared Euclid from the hero, tie -> lower cell index)
func _nearest_node(sim: Variant, kind: String, skip: Dictionary) -> int:
	var best: int = -1
	var bd: float = INF
	for k in (sim.map.nodes as Dictionary):
		var node: Dictionary = sim.map.nodes[k]
		if String(node.kind) != kind or skip.has(int(k)):
			continue
		var dx: float = float(int(k) % int(sim.n)) + 0.5 - float(sim.player.px)
		var dy: float = float(int(k) / int(sim.n)) + 0.5 - float(sim.player.py)
		var d: float = dx * dx + dy * dy
		if d < bd or (d == bd and int(k) < best):
			bd = d
			best = int(k)
	return best


# an orthogonal neighbour of a node on a BLOCKED tile (a rock) the hero can stand on: nearest to the hero, tie -> lower index.
# (sim.order_gather on a rock walks to nearest_free, which may be a DIAGONAL cell 1.414 away — beyond the 1.4 work range, so the hero
# idles there forever. That is a sim bug outside this wave; the bot plays like a careful player and stands beside the rock.)
func _stand_cell(sim: Variant, node_cell: int) -> int:
	var nn: int = int(sim.n)
	var cx: int = node_cell % nn
	var cy: int = node_cell / nn
	var best: int = -1
	var bd: float = INF
	for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var x: int = cx + d.x
		var y: int = cy + d.y
		if x < 0 or y < 0 or x >= nn or y >= nn or sim.is_blocked(x, y):
			continue
		var dx: float = float(x) + 0.5 - float(sim.player.px)
		var dy: float = float(y) + 0.5 - float(sim.player.py)
		var dd: float = dx * dx + dy * dy
		if dd < bd or (dd == bd and y * nn + x < best):
			bd = dd
			best = y * nn + x
	return best


# units of `res` gathered in MEASURE_S sim-seconds (backpack + stock delta + units thrown away when the stock was full), the map's
# finite supply of that node kind, the nodes given up on (amount not dropping for STUCK_S) and the stash trips walked
func _gather_run(preset: Dictionary, res: String, tier: String) -> Dictionary:
	var sim: Variant = _new_world(preset)
	var shift: float = COMFORT_TARGET_C - float(sim.ambient_temp_c())
	if tier == "tool":
		sim.player.equipped["tool"] = String(TOOL_FOR[res])
	var kind: String = String(NODE_OF[res])
	var supply: int = 0
	for k in (sim.map.nodes as Dictionary):
		if String(sim.map.nodes[k].kind) == kind:
			supply += int(sim.map.nodes[k].amount)
	var before: int = Inventory.count(sim, res) + int(sim.res_amount(res))
	var skip: Dictionary = {}
	var target: int = -1
	var target_amount: int = 0
	var since: int = 0
	var phase: int = 0      # 0 choose a node · 1 walk beside it · 2 work it
	var returning: bool = false
	var trips: int = 0
	var banked: int = 0
	var died: bool = false
	var home: Vector2i = MainCapsule.respawn_cell(sim)
	for t in int(MEASURE_S / DT):
		if sim.dead:
			died = true
			break
		sim.temp_offset = shift          # a cold-snap incident would otherwise freeze the pawn mid-run (the bot measures income, not survival)
		sim.temp_offset_days = 1.0e9
		_discard_junk(sim)
		if returning:
			if Inventory.near_storage(sim):
				var moved: int = int(Inventory.stash_all(sim).get("moved", 0))
				if moved == 0 or Inventory.room(sim, res) < STASH_TRIGGER_ROOM:   # the stock is full: bank the load (counted), keep working
					banked += Inventory.count(sim, res)
					Inventory.take(sim, res, Inventory.count(sim, res))
				returning = false
				trips += 1
				sim.player.action = null
				phase = 0
			elif sim.player.action == null:
				sim.order_move(home.x, home.y)
		elif Inventory.room(sim, res) < STASH_TRIGGER_ROOM:
			returning = true
			sim.player.action = null
		else:
			match phase:
				0:
					target = _nearest_node(sim, kind, skip)
					if target < 0:
						break
					since = 0
					if WorldGen.is_terrain_blocked(int(sim.map.tiles[target])):
						var stand: int = _stand_cell(sim, target)
						if stand < 0:
							skip[target] = true
						else:
							sim.order_move(stand % int(sim.n), stand / int(sim.n))
							phase = 1
					else:
						target_amount = int(sim.map.nodes[target].amount)
						sim.order_gather(target % int(sim.n), target / int(sim.n))
						phase = 2
				1:
					since += 1
					if sim.player.action == null:
						target_amount = int(sim.map.nodes[target].amount)
						sim.order_gather(target % int(sim.n), target / int(sim.n))
						phase = 2
						since = 0
					elif since > int(STUCK_S / DT):
						skip[target] = true
						sim.player.action = null
						phase = 0
				2:
					var a: Variant = sim.player.action
					if a == null or String(a.type) != "gather" or int(a.cell) != target or not sim.map.nodes.has(target):
						sim.player.action = null   # depleted (the sim auto-continued onto a neighbour) or hijacked: choose by the bot's own rule
						phase = 0
					else:
						since += 1
						if int(sim.map.nodes[target].amount) < target_amount:
							target_amount = int(sim.map.nodes[target].amount)
							since = 0
						elif since > int(STUCK_S / DT):
							skip[target] = true
							sim.player.action = null
							phase = 0
		sim.update(DT)
		_topup(sim)
	var got: int = Inventory.count(sim, res) + int(sim.res_amount(res)) + banked - before
	return {"units": got, "per_min": float(got) / (MEASURE_S / 60.0), "supply": supply, "skipped": skip.size(), "trips": trips, "died": died, "cause": String(sim.last_death.get("cause", ""))}


# the open catalogue makes rocks/trees yield ore/clay/fibre bundles that cannot be stashed (stash_all moves only data.gd resources);
# the bot throws them away for free — pack management is NOT modelled, so the income below is an UPPER bound on the real pace
func _discard_junk(sim: Variant) -> void:
	for sl in sim.player.inv:
		var id: String = String(sl.id)
		if id != "" and not Inventory.is_building(id) and not GameData.ITEMS.has(id) and not GameData.RES.has(id):
			sl.id = ""
			sl.n = 0


func _measure_income(hand: Dictionary, tool: Dictionary, supply: Dictionary, by_preset: Array) -> void:
	print("-- INCOME: 600 sim-s of gathering the nearest node, per preset (units/min) --")
	print("   %-10s | %-21s | %-21s | node supply per kind (units; skipped stuck nodes, stash trips hand/tool)" % ["preset", "hand  wood stone scrap", "tool  wood stone scrap"])
	for preset in GameData.SPAWN_PRESETS:
		var line_h: String = ""
		var line_t: String = ""
		var supplies: String = ""
		var ps_supply: Dictionary = {}
		for res in GATHERED:
			var rh: Dictionary = _gather_run(preset, String(res), "hand")
			var rt: Dictionary = _gather_run(preset, String(res), "tool")
			for d in [hand, tool, supply]:
				if not (d as Dictionary).has(res):
					d[res] = []
			(hand[res] as Array).append(float(rh.per_min))
			(tool[res] as Array).append(float(rt.per_min))
			(supply[res] as Array).append(int(rh.supply))
			ps_supply[res] = int(rh.supply)
			line_h += "%6.1f" % float(rh.per_min)
			line_t += "%6.1f" % float(rt.per_min)
			supplies += "%4d (skip %d, trips %d/%d%s) " % [int(rh.supply), int(rh.skipped), int(rh.trips), int(rt.trips), " DIED:" + String(rh.cause) if bool(rh.died) or bool(rt.died) else ""]
		print("   %-10s | %-21s | %-21s | %s" % [String(preset.name), line_h, line_t, supplies])
		by_preset.append({"name": String(preset.name), "supply": ps_supply})


func _medians(per_preset: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for res in per_preset:
		var arr: Array = (per_preset[res] as Array).duplicate()
		arr.sort()
		out[res] = float(arr[arr.size() / 2])
		print("   median %-6s %6.2f  (min %.2f .. max %.2f)" % [String(res), float(out[res]), float(arr[0]), float(arr[arr.size() - 1])])
	return out


func _planks_per_wood() -> float:
	for rc in Catalog.load_json().get("recipes", []):
		if String(rc.get("id", "")) == "make_planks":
			return float(int((rc.output as Dictionary).get("count", 1))) / float(int((rc.inputs as Dictionary).get("wood", 1)))
	return 0.0


# the method's ladder: Array[level 1..5] of {level, cost:{res:n}}; cost = round(T_L * income_hand * share), T_L = T_1 * LADDER^(L-1)
func _ladder(inc_hand: Dictionary, scale: float) -> Array:
	var out: Array = []
	for level in range(1, LEVELS + 1):
		var minutes: float = T1_MIN * scale * pow(LADDER, level - 1)
		var cost: Dictionary = {}
		var shares: Dictionary = SHARES[level]
		for res in ["wood", "stone", "planks", "scrap"]:
			if shares.has(res):
				cost[res] = maxi(1, roundi(minutes * float(inc_hand[res]) * float(shares[res])))
		out.append({"level": level, "cost": cost, "minutes": minutes})
	return out


# minutes of pure bare-hand gathering a price costs (the unit OD-93 speaks; an OUTPUT here, T_L is the input)
func _minutes(cost: Dictionary, inc: Dictionary) -> float:
	var m: float = 0.0
	for res in cost:
		m += float(cost[res]) / float(inc[res])
	return m


# slots a price occupies in the pack + the extra storages the stock part needs (pack first, then the capsule's room)
func _payable(cost: Dictionary) -> Dictionary:
	var slots: int = 0
	var units: int = 0
	for res in cost:
		slots += ceili(float(cost[res]) / float(Inventory.stack_max(String(res))))
		units += int(cost[res])
	var pack_units: int = 0
	var left_slots: int = PACK_SLOTS
	var order: Array = cost.keys()
	order.sort_custom(func(a: String, b: String) -> bool:   # biggest stacks first: that packs the most units into the slots
		var sa: int = Inventory.stack_max(a)
		var sb: int = Inventory.stack_max(b)
		return sa > sb or (sa == sb and a < b))
	for res in order:
		var cap_units: int = left_slots * Inventory.stack_max(String(res))
		var put: int = mini(int(cost[res]), cap_units)
		pack_units += put
		left_slots -= ceili(float(put) / float(Inventory.stack_max(String(res))))
	var stock_units: int = units - pack_units
	var extra: int = maxi(0, ceili(float(stock_units - BASE_STORAGE_ROOM) / float(STORAGE_STEP)))
	return {"slots": slots, "units": units, "pack_units": pack_units, "stock_units": stock_units, "extra_storages": extra}


func _print_ladder(title: String, ladder: Array, inc_hand: Dictionary) -> void:
	print("\n== %s ==" % title)
	print("   L  cost                                          units  ratio  minutes  rarest  pack-slots  extra-storages")
	var prev_units: int = 0
	var prev_rank: int = 0
	var rank_ok: bool = true
	for row in ladder:
		var p: Dictionary = _payable(row.cost)
		var cost_s: String = ""
		var rank: int = 0
		for res in ["wood", "stone", "planks", "scrap"]:
			if (row.cost as Dictionary).has(res):
				cost_s += "%s %d  " % [res, int(row.cost[res])]
				rank = maxi(rank, int(RARITY[res]))
		var minutes: float = _minutes(row.cost, inc_hand)
		var ratio: String = "%.2f" % (float(p.units) / float(prev_units)) if prev_units > 0 else "  - "
		print("   %d  %-44s %6d  %5s  %7.1f  %6d  %10d  %d" % [int(row.level), cost_s, int(p.units), ratio, minutes, rank, int(p.slots), int(p.extra_storages)])
		rank_ok = rank_ok and rank >= prev_rank
		prev_rank = rank
		prev_units = int(p.units)
	print("   rarest ingredient never gets more common with the level (OD-75): %s · level-1 price = %.2f min of gathering (OD-93 literal 60..120 — true only BEFORE; OD-109 scales it down): %s" % [
		str(rank_ok), float(ladder[0].minutes), str(float(ladder[0].minutes) >= 60.0 and float(ladder[0].minutes) <= 120.0)])
	var total_min: float = 0.0
	for row in ladder:
		total_min += float(row.minutes)
	print("   whole ladder (levels 1..5): %.0f min = %.1f h of pure gathering (level 5 alone: %.1f h)" % [total_min, total_min / 60.0, float(ladder[LEVELS - 1].minutes) / 60.0])


# wood-equivalent units a ladder takes of each FINITE resource, both axes, levels 1..L (the planks are processed wood: 1/ratio wood each)
func _cum_use(ladder: Array, upto: int, planks_ratio: float) -> Dictionary:
	var cum: Dictionary = {"wood": 0.0, "stone": 0.0, "scrap": 0.0}
	for i in upto:
		var c: Dictionary = (ladder[i] as Dictionary).cost
		cum["wood"] = float(cum["wood"]) + float(AXES) * (float(c.get("wood", 0)) + float(c.get("planks", 0)) / planks_ratio)
		cum["stone"] = float(cum["stone"]) + float(AXES) * float(c.get("stone", 0))
		cum["scrap"] = float(cum["scrap"]) + float(AXES) * float(c.get("scrap", 0))
	return cum


# C1: the worst (preset, resource) use of the region's nodes by the whole ladder of both axes -> {pct, preset, res}
func _worst_use(ladder: Array, by_preset: Array, planks_ratio: float) -> Dictionary:
	var cum: Dictionary = _cum_use(ladder, LEVELS, planks_ratio)
	var worst: Dictionary = {"pct": 0.0, "preset": "", "res": ""}
	for ps in by_preset:
		for res in GATHERED:
			var pct: float = 100.0 * float(cum[res]) / float((ps.supply as Dictionary)[res])
			if pct > float(worst.pct):
				worst = {"pct": pct, "preset": String(ps.name), "res": String(res)}
	return worst


# C1..C4 on the ROUNDED ladder -> "" when it passes, else the first failed criterion
func _criterion_fail(ladder: Array, by_preset: Array, planks_ratio: float) -> String:
	var w: Dictionary = _worst_use(ladder, by_preset, planks_ratio)
	if float(w.pct) > RESERVE_CAP * 100.0:
		return "C1 supply: %s/%s %.1f%% > %.0f%%" % [String(w.preset), String(w.res), float(w.pct), RESERVE_CAP * 100.0]
	var p1: Dictionary = _payable(ladder[0].cost)
	if int(p1.slots) > PACK_SLOTS:
		return "C2 pack: level 1 needs %d slots > %d" % [int(p1.slots), PACK_SLOTS]
	var prev_units: int = 0
	var prev_rank: int = 0
	for row in ladder:
		var units: int = 0
		var rank: int = 0
		for res in (row.cost as Dictionary):
			units += int(row.cost[res])
			rank = maxi(rank, int(RARITY[res]))
			if int(row.cost[res]) < 1:
				return "C3 ladder: level %d has a zero price" % int(row.level)
		if prev_units > 0 and absf(float(units) / float(prev_units) - LADDER) > LADDER * LADDER_TOL:
			return "C3 ladder: level %d / level %d = %.2f, not within %.0f%% of x%.0f" % [int(row.level), int(row.level) - 1, float(units) / float(prev_units), LADDER_TOL * 100.0, LADDER]
		if rank < prev_rank:
			return "C4 order: level %d is more common than the previous" % int(row.level)
		if int(row.level) == 1:
			for res in (row.cost as Dictionary):
				if not ["wood", "stone"].has(String(res)):
					return "C4 order: level 1 is not basic raw"
		prev_units = units
		prev_rank = rank
	return ""


# the largest multiple of SCALE_STEP that passes C1..C4 (searched downwards from the analytic C1 bound)
func _solve_scale(inc_hand: Dictionary, by_preset: Array, planks_ratio: float) -> float:
	var unit: Array = _ladder(inc_hand, 1.0)
	var worst: Dictionary = _worst_use(unit, by_preset, planks_ratio)
	var bound: float = RESERVE_CAP * 100.0 / float(worst.pct)    # use is linear in the scale (before rounding)
	var g: float = floorf(bound / SCALE_STEP) * SCALE_STEP
	while g > SCALE_STEP:
		if _criterion_fail(_ladder(inc_hand, g), by_preset, planks_ratio) == "":
			return snappedf(g, SCALE_STEP)
		g -= SCALE_STEP
	return SCALE_STEP


# OD-109: the BEFORE ladder (the owner's literal formula) vs the AFTER ladder (scaled down), per preset, by the criterion above
func _feasibility_report(before: Array, after: Array, inc_hand: Dictionary, inc_tool: Dictionary, by_preset: Array, supply: Dictionary, planks_ratio: float) -> void:
	print("\n== FEASIBILITY on the finite 56x56 map: both axes (x%d), levels 1..5 cumulative, share of each region's nodes (wood-eq / stone / scrap); criterion C1 <= %.0f%% ==" % [AXES, RESERVE_CAP * 100.0])
	print("   preset     |  BEFORE (scale 1.0)               |  AFTER (g = %.4f)" % _scale)
	var all_ok: bool = true
	for ps in by_preset:
		var line: String = "   %-10s |" % String(ps.name)
		for ladder in [before, after]:
			var cum: Dictionary = _cum_use(ladder, LEVELS, planks_ratio)
			var bad: bool = false
			for res in GATHERED:
				var pct: float = 100.0 * float(cum[res]) / float((ps.supply as Dictionary)[res])
				line += " %7.1f%%" % pct
				bad = bad or pct > RESERVE_CAP * 100.0
			line += "  %s  |" % ("НЕ ЗДІЙСНЕННО" if bad else "ok            ")
			if ladder == after:
				all_ok = all_ok and not bad
		print(line)
	var fail: String = _criterion_fail(after, by_preset, planks_ratio)
	var w: Dictionary = _worst_use(after, by_preset, planks_ratio)
	print("   CRITERION on the AFTER ladder: %s (worst use %.1f%% at %s/%s, cap %.0f%%)" % ["PASS C1..C4" if fail == "" else "FAIL " + fail, float(w.pct), String(w.preset), String(w.res), RESERVE_CAP * 100.0])
	var wb: Dictionary = _worst_use(before, by_preset, planks_ratio)
	print("   BEFORE: worst use %.0f%% at %s/%s -> НЕ ЗДІЙСНЕННО (the owner's literal formula; OD-109 scales it down)" % [float(wb.pct), String(wb.preset), String(wb.res)])
	print("   level 1 = %.2f gather-min at the bare-hand income (NOT the 60..120 of OD-93); it equals 1–2 h of PLAY only if gathering is %.1f%%..%.1f%% of the play time" % [
		T1_MIN * _scale, 100.0 * T1_MIN * _scale / 120.0, 100.0 * T1_MIN * _scale / 60.0])
	# diagnosis: what the composition alone could give (shares balanced to the poorest supply) — NOT applied, the composition stays (OD-109 changes prices only)
	var supply_min: Dictionary = {}
	for res in GATHERED:
		var arr: Array = (supply[res] as Array).duplicate()
		arr.sort()
		supply_min[res] = float(arr[0])
	var unit_use: Dictionary = _cum_use(before, LEVELS, planks_ratio)
	var total_demand: float = float(unit_use["wood"]) + float(unit_use["stone"]) + float(unit_use["scrap"])
	var total_supply: float = float(supply_min["wood"]) + float(supply_min["stone"]) + float(supply_min["scrap"])
	print("   DIAGNOSIS (not applied): with the composition balanced to the poorest region's supply the same cap would allow g <= %.4f (now %.4f) — still ~%.1f gather-min at level 1; the supply, not the composition, is the limit" % [
		RESERVE_CAP * total_supply / total_demand, _scale, T1_MIN * RESERVE_CAP * total_supply / total_demand])
	var tool_gain: float = float(inc_tool["wood"]) / float(inc_hand["wood"])
	print("   tools do not rescue it: the tier-1 tool speeds wood x%.2f, stone x%.2f, scrap x%.2f (the supply, not the pace, is the limit)" % [
		tool_gain, float(inc_tool["stone"]) / float(inc_hand["stone"]), float(inc_tool["scrap"]) / float(inc_hand["scrap"])])
	print("   more supply is OD-110 (open): neighbouring maps / travel are NOT in this work; regrowth and a bigger map were rejected by the owner (OD-109)")
	var p1: Dictionary = _payable(after[0].cost)
	print("   payability of level 1 (AFTER): %d pack slots needed (the backpack has %d), %d units, %d extra storages beyond the capsule's (+%d units each)" % [
		int(p1.slots), PACK_SLOTS, int(p1.units), int(p1.extra_storages), STORAGE_STEP])
	var pb: Dictionary = _payable(before[0].cost)
	print("   (BEFORE it needed %d slots and %d extra storages)" % [int(pb.slots), int(pb.extra_storages)])


# core_hp(P) per defence level: base x FACTOR^(P-1) (P >= 1), P = 0 -> base / FACTOR; base from the weakest reference raid
func _defence_report() -> Array:
	var raider: Dictionary = GameData.make_raider(0.0, 0.0, REF_DAY_EQUIV)
	var count: int = GameData.raid_wave_size(REF_DAY_EQUIV)
	var base: float = float(count) * float(raider.dmg) * T_OPEN_REF_S / BUILDING_ATK_CD
	print("\n-- DEFENCE (Q-5 working interpretation): reference raid day_equiv %d = %d raiders x dmg %.1f, undefended core holds %.0f s -> core_hp(1) = %.0f --" % [
		REF_DAY_EQUIV, count, float(raider.dmg), T_OPEN_REF_S, base])
	print("   P  core_hp   ratio   (OD-103: x%.0f per level, x%.0f at P=5 relative to P=1)" % [PROTECTION_FACTOR, pow(PROTECTION_FACTOR, 4)])
	var out: Array = []
	for p in range(0, LEVELS + 1):
		var hp: int = roundi(base * pow(PROTECTION_FACTOR, p - 1))
		out.append(hp)
		print("   %d  %7d   %s" % [p, hp, "x%.2f" % (float(hp) / float(out[p - 1])) if p > 0 else "  -"])
	print("   core_hp(5)/core_hp(1) = %.2f" % (float(out[5]) / float(out[1])))
	return out


# R in CELLS from the owner's ~50 m and the (only trace of a) map scale; buildable cells inside the zone on the real maps
func _radius_report() -> int:
	var cells: int = ceili(RADIUS_M / CELL_M)
	print("\n-- RADIUS (OD-99, static; Q-4): %.0f m / %.3f m per cell (frozen main.gd OSM overlay: 760 m over %d cells) -> %d cells ; R >= ceil(STASH_REACH=%.1f)=%d ; R <= n/4=%d : %s --" % [
		RADIUS_M, CELL_M, MAP_N, cells, Inventory.STASH_REACH, ceili(Inventory.STASH_REACH), MAP_N / 4, str(cells >= ceili(Inventory.STASH_REACH) and cells <= MAP_N / 4)])
	var free_counts: Array = []
	for preset in GameData.SPAWN_PRESETS:
		var sim: Variant = _new_world(preset)
		var t: Vector2i = MainCapsule.tile(sim)
		var free: int = 0
		for dy in range(-cells, cells + 1):
			for dx in range(-cells, cells + 1):
				if dx == 0 and dy == 0:
					continue
				if MainCapsule.cell_free(sim.map, Vector2i(t.x + dx, t.y + dy), sim.bgrid):
					free += 1
		free_counts.append(free)
	free_counts.sort()
	var area: int = (2 * cells + 1) * (2 * cells + 1) - 1
	print("   zone area (2R+1)^2-1 = %d cells ; buildable inside (median over presets) = %d (min %d .. max %d)" % [
		area, int(free_counts[free_counts.size() / 2]), int(free_counts[0]), int(free_counts[free_counts.size() - 1])])
	return cells


func _buff_report(ladder: Array, inc_hand: Dictionary) -> void:
	print("\n-- BUFFS (OD-98, decided): buff(L) = 1 + %.2f*L on the four axes %s ; payback of a level's price through the gather buff (informational) --" % [BUFF_STEP, str(MainCapsule.BUFF_KEYS)])
	print("   L  buff   buy(min)  payback(min of gathering at +step) = buy/step")
	for row in ladder:
		var buy: float = _minutes(row.cost, inc_hand)
		print("   %d  %.2f   %7.1f   %10.1f" % [int(row.level), 1.0 + BUFF_STEP * int(row.level), buy, buy / BUFF_STEP])


func _compare_with_catalog(ladder: Array, hp: Array, cells: int) -> void:
	print("\n-- catalog.json capsule_levels vs this proposal (MATCH / DIFF; informational) --")
	var table: Dictionary = (Catalog.load_json().get("capsule_levels", {}) as Dictionary)
	if table.is_empty():
		print("   catalog.json has no capsule_levels yet")
		return
	var levels: Array = table.get("levels", [])
	var plevels: Array = (table.get("protection", {}) as Dictionary).get("levels", [])
	for row in ladder:
		var same_cost: bool = _same_cost((levels[int(row.level)] as Dictionary).cost, row.cost)
		print("   L%d capsule cost     %s" % [int(row.level), "MATCH" if same_cost else "DIFF  data=%s bot=%s" % [str((levels[int(row.level)] as Dictionary).cost), str(row.cost)]])
		var same_p: bool = _same_cost((plevels[int(row.level)] as Dictionary).cost, row.cost)
		print("   P%d protection cost  %s" % [int(row.level), "MATCH" if same_p else "DIFF  data=%s bot=%s" % [str((plevels[int(row.level)] as Dictionary).cost), str(row.cost)]])
	for p in range(0, LEVELS + 1):
		var got: float = float((plevels[p] as Dictionary).core_hp)
		print("   P%d core_hp          %s" % [p, "MATCH" if roundi(got) == int(hp[p]) else "DIFF data=%s bot=%d" % [str(got), int(hp[p])]])
	for level in range(0, LEVELS + 1):
		var b: Dictionary = (levels[level] as Dictionary).get("buffs", {})
		var same_b: bool = b.size() == MainCapsule.BUFF_KEYS.size()
		for key in MainCapsule.BUFF_KEYS:
			same_b = same_b and b.has(key) and absf(float(b[key]) - (1.0 + BUFF_STEP * level)) < 0.0001
		print("   L%d buffs            %s" % [level, "MATCH" if same_b else "DIFF data=%s want 1+%.2f*L on all four keys" % [str(b), BUFF_STEP]])
	var zone: Dictionary = table.get("zone", {})
	var cells_ok: String = "MATCH" if int(zone.get("radius_cells", -1)) == cells else "DIFF"
	var m_ok: String = "MATCH" if float(zone.get("radius_m", -1.0)) == RADIUS_M else "DIFF"
	var cell_ok: String = "MATCH" if absf(float(zone.get("cell_m", -1.0)) - CELL_M) < 0.01 else "DIFF data=%s bot=%.3f" % [str(zone.get("cell_m")), CELL_M]
	print("   zone radius_cells    %s (data %s, bot %d) · radius_m %s · cell_m %s" % [cells_ok, str(zone.get("radius_cells")), cells, m_ok, cell_ok])
	print("   protection.factor    %s" % ("MATCH" if float((table.get("protection", {}) as Dictionary).get("factor", -1.0)) == PROTECTION_FACTOR else "DIFF"))


func _same_cost(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for res in b:
		if int(a.get(res, -1)) != int(b[res]):
			return false
	return true


# ---------------- RAID (W3a) ----------------
func _power_of(count: int, day: int) -> float:
	var r: Dictionary = GameData.make_raider(0.0, 0.0, day)
	return float(count) * float(r.dmg) * float(r.maxhp)


func _raid_report(capsule: Array) -> Dictionary:
	print("\n== RAID (W3a): proposed numbers + their evidence ==")
	print("   DECIDED (verbatim, not derived): immunity %d ms (OD-24) · take %d%% (OD-107) · grace %d ms (OD-66) · warning %d..%d ms (OD-88) · raid x%.0f per level (OD-65)" % [
		IMMUNITY_MS, TAKE_PERCENT, GRACE_MS, WARN_MIN_MS, WARN_MAX_MS, LEVEL_FACTOR])
	# (a) wealth_ref_points
	var pts: Array = []
	for preset in GameData.SPAWN_PRESETS:
		var sim: Variant = _new_world(preset)
		var b: Variant = KernelBalance.Balance.new()
		pts.append(float(b.assess(Director.world_of(sim), {"day": 0, "hostile_pressure": 1.0}).threat))
	pts.sort()
	var ref_pts: int = roundi(float(pts[pts.size() / 2]))
	print("   (a) Balance.assess(threat) of the landed base per preset: %s -> wealth_ref_points = %d (median)" % [str(pts), ref_pts])
	# (b) by_level
	var ref_count: int = GameData.raid_wave_size(REF_DAY_EQUIV)
	var p1: float = _power_of(ref_count, REF_DAY_EQUIV)
	var by_level: Dictionary = {"1": {"count": ref_count, "day_equiv": REF_DAY_EQUIV}}
	var prev_c: int = ref_count
	var prev_d: int = REF_DAY_EQUIV
	print("   (b) raider power = count x dmg x hp ; L1 = reference raid (%d raiders, day_equiv %d) = %.0f ; target x%.0f per level" % [ref_count, REF_DAY_EQUIV, p1, LEVEL_FACTOR])
	print("       L  count  day_equiv  power      target     err%    ratio-to-previous")
	print("       1  %5d  %9d  %9.0f  %9.0f  %5.2f   -" % [ref_count, REF_DAY_EQUIV, p1, p1, 0.0])
	var prev_p: float = p1
	for level in range(2, LEVELS + 1):
		var target: float = p1 * pow(LEVEL_FACTOR, level - 1)
		var best_c: int = prev_c
		var best_d: int = prev_d
		var best_e: float = INF
		for c in range(prev_c, COUNT_MAX + 1):
			for d in range(prev_d, DAY_EQUIV_MAX + 1):
				var e: float = absf(_power_of(c, d) - target) / target
				if e < best_e - 1.0e-12:
					best_e = e
					best_c = c
					best_d = d
		var pw: float = _power_of(best_c, best_d)
		by_level[str(level)] = {"count": best_c, "day_equiv": best_d}
		print("       %d  %5d  %9d  %9.0f  %9.0f  %5.2f   x%.2f" % [level, best_c, best_d, pw, target, best_e * 100.0, pw / prev_p])
		prev_c = best_c
		prev_d = best_d
		prev_p = pw
	# (c) roll_spread
	print("   (c) roll_spread: P(breach) over power/core = %.2f .. %.2f (a strictly-inside-(0,1) spread keeps the roll meaningful)" % [1.0 - BAND, 1.0 + BAND])
	var chosen: float = -1.0
	for sp in SPREAD_CANDIDATES:
		var line: String = "       spread %.2f:" % float(sp)
		var inside: bool = true
		for ratio in [1.0 - BAND, 1.0, 1.0 + BAND]:
			var prob: float = _breach_prob(float(ratio), float(sp))
			line += "  ratio %.2f -> P=%.2f" % [float(ratio), prob]
			inside = inside and prob > 0.0 and prob < 1.0
		print(line + ("   <- inside (0,1)" if inside else ""))
		if inside and chosen < 0.0:
			chosen = float(sp)
	print("       -> roll_spread = %s (the smallest candidate that works)" % str(chosen))
	# (d) queue_max
	var burst: int = 0
	for preset in GameData.SPAWN_PRESETS:
		var sim2: Variant = _new_world(preset)
		var b2: Variant = KernelBalance.Balance.new()
		b2.category_weight[KernelBalance.CAT_THREAT_BIG] = Director.THREAT_BIG_WEIGHT
		var rng := RandomNumberGenerator.new()
		rng.seed = int(sim2.region_seed()) ^ 0x0D1EC70
		var world: Dictionary = Director.world_of(sim2)
		world["threat_active"] = false
		for tick in RAID_TICKS:
			var raids: int = 0
			for pl in b2.tick(world, {"day": 1 + tick / 1500, "dday": DT / 150.0, "hostile_pressure": 1.0, "hostile_faction": "x"}, rng):
				if String(pl.get("incident", "")) == "raid":
					raids += 1
			burst = maxi(burst, raids)
	print("   (d) most raid payloads Balance fired in ONE tick over 5 presets x %d ticks = %d -> queue_max = %d" % [RAID_TICKS, burst, maxi(1, burst)])
	# (e) take_round
	var attacker_floor: int = 0
	var attacker_ceil: int = 0
	var attacker_round: int = 0
	var rows: int = 0
	for row in capsule:
		for res in (row.cost as Dictionary):
			var inv: int = int(row.cost[res])
			rows += 1
			var kept_f: int = inv - MainCapsule.take_of(inv, TAKE_PERCENT, "floor")
			attacker_floor += 1 if MainCapsule.take_of(inv, TAKE_PERCENT, "floor") > kept_f else 0
			attacker_ceil += 1 if MainCapsule.take_of(inv, TAKE_PERCENT, "ceil") > inv - MainCapsule.take_of(inv, TAKE_PERCENT, "ceil") else 0
			attacker_round += 1 if MainCapsule.take_of(inv, TAKE_PERCENT, "round") > inv - MainCapsule.take_of(inv, TAKE_PERCENT, "round") else 0
	var odd: int = 0
	for n in [1, 3, 5, 7, 99]:   # odd amounts are where the rules differ
		odd += 1 if MainCapsule.take_of(n, TAKE_PERCENT, "ceil") > n - MainCapsule.take_of(n, TAKE_PERCENT, "ceil") else 0
	print("   (e) take rounding over %d ledger rows of the proposed prices: attacker takes MORE than the defender keeps — floor %d · ceil %d · round %d ; on odd amounts 1/3/5/7/99 ceil does so %d times -> take_round = floor" % [
		rows, attacker_floor, attacker_ceil, attacker_round, odd])
	return {"wealth_ref_points": ref_pts, "by_level": by_level, "roll_spread": chosen, "queue_max": maxi(1, burst), "take_round": "floor", "count_max": COUNT_MAX}


# P(breach) when the raid's power is `ratio` x the core's HP and the damage is power x (1 - spread + 2 x spread x roll), roll uniform [0,1): breach iff damage >= core
func _breach_prob(ratio: float, spread: float) -> float:
	if spread <= 0.0:
		return 1.0 if ratio >= 1.0 else 0.0
	var need: float = ((1.0 / ratio) - (1.0 - spread)) / (2.0 * spread)   # roll >= need breaks the core
	return clampf(1.0 - need, 0.0, 1.0)


func _compare_raid(raid: Dictionary) -> void:
	print("\n-- catalog.json capsule_levels.raid vs this proposal (MATCH / DIFF) --")
	var rd: Dictionary = (Catalog.load_json().get("capsule_levels", {}) as Dictionary).get("raid", {})
	if rd.is_empty() or not rd.has("by_level"):
		print("   catalog.json has no raid proposal yet")
		return
	var decided: Dictionary = {"immunity_ms": IMMUNITY_MS, "take_percent": TAKE_PERCENT, "grace_ms": GRACE_MS, "warn_min_ms": WARN_MIN_MS, "warn_max_ms": WARN_MAX_MS,
		"cadence_min_ms": CADENCE_MIN_MS, "cadence_max_ms": CADENCE_MAX_MS}
	for k in decided:
		print("   decided %-12s %s (data %s, owner %s)" % [String(k), "MATCH" if int(rd.get(k, -1)) == int(decided[k]) else "DIFF", str(rd.get(k)), str(decided[k])])
	for k in ["wealth_ref_points", "roll_spread", "queue_max", "take_round", "count_max"]:
		print("   proposed %-18s %s (data %s, bot %s)" % [String(k), "MATCH" if str(rd.get(k)) == str(raid[k]) or (rd.get(k) is float and absf(float(rd.get(k)) - float(raid[k])) < 1.0e-9) else "DIFF", str(rd.get(k)), str(raid[k])])
	for level in range(1, LEVELS + 1):
		var want: Dictionary = raid.by_level[str(level)]
		var got: Dictionary = (rd.by_level as Dictionary).get(str(level), {})
		print("   proposed by_level[%d]        %s (data %s, bot %s)" % [level, "MATCH" if int(got.get("count", -1)) == int(want.count) and int(got.get("day_equiv", -1)) == int(want.day_equiv) else "DIFF", str(got), str(want)])


# =============================================================================================================================================================
# W3b: hold vs break (REQ-0010-18), cadence (REQ-0010-70/110), warning (REQ-0010-19/71/108)
# =============================================================================================================================================================
const CADENCE_MIN_MS := 259200000      # OD-86: ~1 raid per 3..4 days of REAL time
const CADENCE_MAX_MS := 345600000
const DAY_MS := 86400000
const T0_MS := 1700000000000           # the injected clock origin (any instant: nothing reads the wall clock)
const CLOCK_STEP_MS := 30000           # the injected clock advances this much per tick, independent of the tick count (REQ-0010-93)
const CADENCE_DAYS := 80               # clock days per preset
const ASSAULT_WINDOW_S := 180.0        # PROPOSED: a raid that cannot breach the core within this many sim-seconds after contact «does not break it» (the owner reacts)
const COUNT_CAP := 400                 # upper bound of the bisection over the raider count
const HOLD_TICK_CAP := 4000            # ticks of one hold run (0.1 s each) — above the window, so a held raid is observed to the end of the window only


func _world_at(preset: Dictionary, now_ms: int) -> Variant:
	var sim: Variant = Sim.new()
	sim.use_inventory = true
	sim.use_catalog = true
	sim.use_main_capsule = true
	sim.set_clock(now_ms)
	sim.new_game(WorldGen.generate_map(float(preset.lat), float(preset.lon), MAP_N), false)
	_quiet_world(sim)
	return sim


# the bot measures the raid machine, not the storyteller: no other incidents, no patrols, a comfortable hero
func _quiet_world(sim: Variant) -> void:
	sim.time.day = 195
	sim.time.frac = 0.5
	sim.weather = &"clear"
	sim.patrol.next = 1.0e9
	sim.balance = KernelBalance.Balance.new()
	for cat in sim.balance.category_weight:
		sim.balance.category_weight[cat] = 0.0


# the defender is the core ONLY: the hero stands in the map corner farthest from every raider (raiders chase him inside 6 cells, threats.gd) and cannot die
func _evade(sim: Variant) -> void:
	sim.player.hp = 1.0e9
	sim.player.hunger = 100.0
	sim.player.rest = 100.0
	if sim.enemies.is_empty():
		return
	var best_d: float = -1.0
	var best: Vector2 = Vector2(0.5, 0.5)
	for c in [Vector2(0.5, 0.5), Vector2(MAP_N - 0.5, 0.5), Vector2(0.5, MAP_N - 0.5), Vector2(MAP_N - 0.5, MAP_N - 0.5)]:
		var nearest: float = INF
		for e in sim.enemies:
			nearest = minf(nearest, c.distance_to(Vector2(float(e.px), float(e.py))))
		if nearest > best_d:
			best_d = nearest
			best = c
	sim.player.px = best.x
	sim.player.py = best.y


# direct injection of the levels (the economy of reaching them is the other half of this bot); the first upgrade is stamped at `now`
func _set_capsule(sim: Variant, level: int, prot: int, now_ms: int) -> void:
	sim.main_capsule["level"] = level
	sim.main_capsule["protection"] = prot
	sim.main_capsule["first_upgrade_at"] = now_ms


# One live raid of `count` raiders (day_equiv `day`) against capsule level `level` / protection `prot`; returns {breached, seconds-from-contact}. No defenders but the core.
func _hold_run(preset: Dictionary, level: int, prot: int, count: int, day: int) -> Dictionary:
	var sim: Variant = _world_at(preset, T0_MS)
	_set_capsule(sim, level, prot, T0_MS)
	sim.set_clock(T0_MS + GRACE_MS + 1)
	MainCapsule.on_director_raid(sim, {"incident": "raid", "faction": "бот"}, 0.0)
	sim.capsule_raid["count"] = count
	sim.capsule_raid["day_equiv"] = day
	sim.update(DT)   # planned -> warning
	sim.set_clock(int(sim.capsule_raid.contact_at) + 1)
	sim.update(DT)   # warning -> contact (the raiders appear on the edge)
	var ticks: int = 0
	while String(sim.capsule_raid.state) != "none" and ticks < HOLD_TICK_CAP:
		_evade(sim)
		sim.update(DT)
		ticks += 1
	var seconds: float = float(ticks) * DT
	var breached: bool = false
	for e in sim.capsule_events:
		if StringName(e.get("kind", &"")) == &"breach":
			breached = true
	return {"breached": breached and seconds <= ASSAULT_WINDOW_S, "seconds": seconds, "resolved": String(sim.capsule_raid.state) == "none"}


func _min_breaking_count(preset: Dictionary, level: int, prot: int, day: int) -> int:
	if not bool(_hold_run(preset, level, prot, COUNT_CAP, day).breached):
		return -1   # even COUNT_CAP raiders do not break it inside the window
	var lo: int = 1
	var hi: int = COUNT_CAP
	while lo < hi:
		var mid: int = (lo + hi) / 2
		if bool(_hold_run(preset, level, prot, mid, day).breached):
			hi = mid
		else:
			lo = mid + 1
	return lo


func _w3b_report(inc_hand: Dictionary) -> void:
	print("\n== W3b: HOLD vs BREAK, CADENCE, WARNING (spec 0010 REQ-0010-18/19/70/71/108/110; informational) ==")
	var tbl: Dictionary = Catalog.load_json().get("capsule_levels", {})
	var by: Dictionary = (tbl.get("raid", {}) as Dictionary).get("by_level", {})
	var levels: Array = tbl.get("levels", [])
	var prot: Array = (tbl.get("protection", {}) as Dictionary).get("levels", [])
	if by.is_empty() or levels.is_empty() or prot.is_empty():
		print("   catalog.json has no capsule_levels/raid data — nothing to measure")
		return
	_hold_report(by, prot, inc_hand)
	_cadence_report()
	_warning_report()


# (a) REQ-0010-18: for each L the minimal raider count that breaches P_L=L inside the assault window, on the first preset (the core is the same in all presets)
func _hold_report(by: Dictionary, prot: Array, inc_hand: Dictionary) -> void:
	var preset: Dictionary = GameData.SPAWN_PRESETS[0]
	print("\n   (a) HOLD vs BREAK — live raid (Sim.update), protection P = capsule level L, defenders: the core only; assault window %.0f s from contact (PROPOSED)" % ASSAULT_WINDOW_S)
	print("       L  row(count x day)  core_hp  row breaks in (s)  min breaking count  k=min/row   attack power (x ref)  defence price (gather-min)  a = defence : attack")
	var ref_power: float = _power_of(int(by["1"].count), int(by["1"].day_equiv))
	var worst_a: float = 0.0
	for level in range(1, LEVELS + 1):
		var row: Dictionary = by[str(level)]
		var hp: float = float((prot[level] as Dictionary).get("core_hp", 0.0))
		var row_run: Dictionary = _hold_run(preset, level, level, int(row.count), int(row.day_equiv))
		var nmin: int = _min_breaking_count(preset, level, level, int(row.day_equiv))
		var k: float = float(nmin) / float(row.count) if nmin > 0 else INF
		var power: float = _power_of(nmin, int(row.day_equiv)) if nmin > 0 else INF
		var attack_x: float = power / ref_power
		var minutes: float = _minutes(_prot_cost(prot, level), inc_hand) if not inc_hand.is_empty() else -1.0
		var a: float = minutes / (T1_MIN * _scale * attack_x) if minutes >= 0.0 and nmin > 0 else -1.0
		worst_a = maxf(worst_a, a)
		print("       %d  %2d x %-3d          %7.0f  %-17s  %-18s  %-9s   %-20s  %-26s  %s" % [level, int(row.count), int(row.day_equiv), hp, "%.1f s" % float(row_run.seconds) if bool(row_run.resolved) else "never",
			str(nmin) if nmin > 0 else ">%d" % COUNT_CAP, "x%.2f" % k if nmin > 0 else "-", "%.2f" % attack_x if nmin > 0 else "-",
			"%.1f" % minutes if minutes >= 0.0 else "(run the full bot)", "%.3f" % a if a >= 0.0 else "-"])
	if worst_a > 0.0:
		print("       worst a = %.3f  (REQ-0010-18 wants a < 1: holding is cheaper than breaking; the attack price anchor «the level-1 reference raid = the level-1 price = T_1 x g = %.2f gather-minutes» is PROPOSED)" % [worst_a, T1_MIN * _scale])


func _prot_cost(prot: Array, level: int) -> Dictionary:
	var c: Dictionary = {}
	for res in ((prot[level] as Dictionary).get("cost", {}) as Dictionary):
		c[String(res)] = int(prot[level].cost[res])
	return c


# (b) REQ-0010-70/110: the cadence of the planner over CADENCE_DAYS of injected clock, 5 presets
func _cadence_report() -> void:
	print("\n   (b) CADENCE — %d clock days per preset, the clock advances %d ms per tick (independent of the tick count), capsule L1 upgraded at day 0, no defence" % [CADENCE_DAYS, CLOCK_STEP_MS])
	var gaps: Array = []
	var first_ok: bool = true
	var firsts: Array = []
	var per_preset: Array = []
	for preset in GameData.SPAWN_PRESETS:
		var sim: Variant = _world_at(preset, T0_MS)
		_set_capsule(sim, 1, 2, T0_MS)   # protection 2: some raids are held, some break — the cadence must not care
		var warns: Array = []
		var now: int = T0_MS
		var end: int = T0_MS + CADENCE_DAYS * DAY_MS
		var guard_ms: int = 0
		while now < end:
			now += CLOCK_STEP_MS
			sim.set_clock(now)
			_evade(sim)
			sim.update(DT)
			for e in MainCapsule.drain_events(sim):
				if StringName(e.get("kind", &"")) == &"warning":
					warns.append(int(e.warn_at))
		for i in warns.size():
			if i == 0:
				firsts.append(int(warns[0]) - T0_MS)
				first_ok = first_ok and int(warns[0]) - T0_MS >= GRACE_MS
			else:
				gaps.append(int(warns[i]) - int(warns[i - 1]))
		per_preset.append(warns.size())
	gaps.sort()
	var sum: float = 0.0
	for g in gaps:
		sum += float(g)
	var mean_d: float = sum / float(maxi(1, gaps.size())) / float(DAY_MS)
	print("       raids per preset over %d days: %s ; intervals measured: %d" % [CADENCE_DAYS, str(per_preset), gaps.size()])
	print("       first raid after landing (days): %s  -> never before the %d-day grace: %s" % [str(firsts.map(func(x: int) -> String: return "%.2f" % (float(x) / float(DAY_MS)))), GRACE_MS / DAY_MS, "yes" if first_ok else "NO"])
	if not gaps.is_empty():
		print("       interval histogram (days, bin 0.25):")
		var bins: Dictionary = {}
		for g in gaps:
			var b: float = floor(float(g) / float(DAY_MS) / 0.25) * 0.25
			bins[b] = int(bins.get(b, 0)) + 1
		var keys: Array = bins.keys()
		keys.sort()
		for b in keys:
			print("         %4.2f..%4.2f  %s %d" % [float(b), float(b) + 0.25, "#".repeat(int(bins[b])), int(bins[b])])
		print("       mean interval %.3f days (OD-86 wants 3..4) · min %.3f · max %.3f days · window [%.2f; %.2f] days -> %s" % [mean_d, float(gaps[0]) / float(DAY_MS),
			float(gaps[gaps.size() - 1]) / float(DAY_MS), float(CADENCE_MIN_MS) / float(DAY_MS), float(CADENCE_MAX_MS) / float(DAY_MS),
			"INSIDE the window" if float(gaps[0]) >= float(CADENCE_MIN_MS) - 1.0 and float(gaps[gaps.size() - 1]) <= float(CADENCE_MAX_MS) + 1.0 else "OUTSIDE"])


# (c) REQ-0010-19/71/108: the warning lead of every raid and the hero's walk to shelter
func _warning_report() -> void:
	print("\n   (c) WARNING — contact_at - warn_at over 30 raids per preset on the injected clock, and the hero's walk to the capsule")
	var leads: Array = []
	for preset in GameData.SPAWN_PRESETS:
		for i in 6:
			var sim: Variant = _world_at(preset, T0_MS + i * 1000)
			_set_capsule(sim, 1, 1, T0_MS)
			sim.set_clock(T0_MS + GRACE_MS + 1 + i * 7919)
			MainCapsule.on_director_raid(sim, {"incident": "raid", "faction": "бот"}, 0.0)
			sim.update(DT)
			leads.append(int(sim.capsule_raid.contact_at) - int(sim.capsule_raid.warn_at))
	leads.sort()
	print("       leads (min..max ms): %d .. %d   window [%d; %d]  -> %s" % [int(leads[0]), int(leads[leads.size() - 1]), WARN_MIN_MS, WARN_MAX_MS,
		"INSIDE" if int(leads[0]) >= WARN_MIN_MS and int(leads[leads.size() - 1]) <= WARN_MAX_MS else "OUTSIDE"])
	var worst_walk: float = 0.0
	for preset in GameData.SPAWN_PRESETS:
		var sim2: Variant = _world_at(preset, T0_MS)
		var cap: Vector2i = MainCapsule.tile(sim2)
		var far: Vector2i = cap
		var best: int = -1
		for c in [Vector2i(0, 0), Vector2i(MAP_N - 1, 0), Vector2i(0, MAP_N - 1), Vector2i(MAP_N - 1, MAP_N - 1)]:
			var path: Array = sim2.compute_path(c.x, c.y, cap.x, cap.y)
			if path.size() > best:
				best = path.size()
				far = c
		worst_walk = maxf(worst_walk, float(best) / 3.4)
		print("       %s: longest walk from a map corner %s to the capsule = %d cells ≈ %.0f s of hero walking (3.4 cells/s)" % [str(preset.get("name", "preset")), str(far), best, float(best) / 3.4])
	print("       the walk (%.0f s at worst) is %.1f%% of the shortest warning (%d s): the shelter is reachable inside the warning with a wide margin" % [worst_walk, 100.0 * worst_walk / (float(WARN_MIN_MS) / 1000.0), WARN_MIN_MS / 1000])

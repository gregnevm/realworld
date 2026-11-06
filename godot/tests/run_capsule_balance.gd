# RealWorld — tests/run_capsule_balance.gd : the ECONOMY BOT of spec 0010 (informational, NOT a CI gate — like run_perf).
#
# OD-58/59 delegate to the agent only a PROPOSAL of the capsule numbers (cost / radius / buffs / raider strength /
# core HP), with the method written down and the owner approving at merge. This bot is that method, executable:
#   1. INCOME + SUPPLY — a deterministic gather bot (nearest tree / rock / scrap node, use_inventory + use_catalog + use_main_capsule ON,
#      600 sim-s, stash trips to the capsule when the pack is full) on the 5 SPAWN_PRESETS, for two equipment tiers (bare hands; tier-1
#      tool: axe for wood, pick for stone/scrap — GameData.ITEMS multipliers). Output: units/min per resource (median over presets) and
#      the region's FINITE node supply (nodes never regrow) — the poorest preset bounds what any price can ever ask for.
#      Planks are not gathered: income[planks] = income[wood] x the catalogue recipe ratio (make_planks: 3 wood -> 2 planks).
#   2. COST — the method's time-to-buy ladder T_L = T_1 g^(L-1) with cost_L[res] = round(T_L income[res] share[res]) is printed LITERALLY
#      (T_1=12 min, g=2.0/2.5) together with the share of the poorest region's supply it would swallow (it swallows several times
#      the supply: infeasible). The PROPOSAL is the supply-bounded form of the SAME formula: the whole ladder may take SUPPLY_BUDGET of the
#      poorest region's nodes, split over levels by weights W_L = g^(L-1)/sum(g^k), i.e. T_total and the shares are DERIVED from the supply
#      (cost_L[res] = round(W_L x SUPPLY_BUDGET x supply_min[res])); the minutes each level then costs are an OUTPUT, printed per level.
#      Each level is also checked for PAYABILITY (paid atomically from the backpack + the capsule stock: pack slots + storage room).
#   3. RADIUS — R(L) = R0 + k*L, R0 >= ceil(Inventory.STASH_REACH), R(5) <= n/4; buildable cells inside the zone are measured on the map.
#   4. BUFFS — buff(L) = 1 + 0.05*L; cut-off: payback of a level's price through the buff >= 2 x its time-to-buy (a convenience, not a snowball).
#   5. RAIDER / CORE HP — day_equiv(L) = 2 + 2L through the EXISTING GameData.make_raider / raid_wave_size (no new stat formulas);
#      core_hp(L) = count(L) * dmg(day_equiv) * t_open(L) / atk_cd, t_open(L) = 17.5 + 2.5 L seconds (the time an UNDEFENDED capsule holds).
# Finally it prints MATCH/DIFF of every proposed number against godot/content/catalog.json (capsule_levels), so the data cannot drift
# from the method unnoticed. The pass/fail counter only says the probe ran — read the printed tables. Run:
#   godot --headless --path godot -s res://tests/run_capsule_balance.gd
extends "res://tests/harness.gd"

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const Inventory = preload("res://scripts/sim/inventory.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")

const DT := 0.1                    # the production tick step
const MEASURE_S := 600.0           # 10 sim-minutes of continuous gathering per (preset, resource, tier)
const MAP_N := 56                  # Session.MAP_N
const STUCK_S := 15.0             # a gather target whose amount has not dropped for this long is skipped
const COMFORT_TARGET_C := 20.0     # the bot measures the ECONOMY, not survival: a standing regional shift pins the ambient near 20 C in every preset
const STASH_TRIGGER_ROOM := 3      # fewer free units than this for the gathered resource: walk to the capsule and stash (a real player does)
const NODE_OF := {"wood": "tree", "stone": "rock", "scrap": "scrap"}
const TOOL_FOR := {"wood": "axe", "stone": "pick", "scrap": "pick"}
const GATHERED := ["wood", "stone", "scrap"]

# ---- the proposal knobs (the METHOD's hypotheses — change them here, re-run, and re-sync catalog.json) ----
const T1_MIN := 12.0               # the method's literal hypothesis: first upgrade ~12 minutes of pure gathering
const LITERAL_G := [2.0, 2.5]      # the method's growth factors (literal ladders, shown for the infeasibility verdict)
const LITERAL_SHARES := {          # the method's shares: L1-L2 wood/stone/scrap, planks from L2 (components excluded: no live source under ON)
	1: {"wood": 0.50, "stone": 0.30, "scrap": 0.20},
	2: {"wood": 0.35, "stone": 0.25, "scrap": 0.20, "planks": 0.20},
	3: {"wood": 0.30, "stone": 0.25, "scrap": 0.20, "planks": 0.25},
	4: {"wood": 0.30, "stone": 0.25, "scrap": 0.20, "planks": 0.25},
	5: {"wood": 0.30, "stone": 0.25, "scrap": 0.20, "planks": 0.25},
}
const SUPPLY_BUDGET := 0.30        # the capsule ladder may take this fraction of the POOREST preset's finite nodes (the rest: buildings, tools, defense)
const PLANKS_OF_WOOD := 0.40       # the part of the wood budget spent as planks (from L2), at the recipe ratio
const CHOSEN_G := 1.5              # weights W_L = g^(L-1)/sum(g^k): gentler than the method's 2.0-2.5 so that level 1 is not trivially cheap
const EXTRA_STORAGES_OK := 3       # a level may need at most this many EXTRA storages (+250 each) beyond the capsule to be payable
const R0 := 3
const R_STEP := 2
const BUFF_STEP := 0.05
const DAY_EQUIV_BASE := 2
const DAY_EQUIV_STEP := 2
const T_OPEN_BASE_S := 17.5
const T_OPEN_STEP_S := 2.5
const BUILDING_ATK_CD := 1.0       # threats.gd: a raider swings at a building once per 1.0 s
const WARNING_S := 45.0            # the method: reaction ~30 s + R(5)/v_hero(3.4) ~ 4 s, one constant with a margin
const PACK_SLOTS := 24             # the backpack proper (slots 8..31); the hotbar holds tools/buildings
const BASE_STORAGE_ROOM := 450     # storage_cap() at the start: 200 + the capsule's 250 (GameData.BUILDINGS.storage.capacity)
const STORAGE_STEP := 250


func _init() -> void:
	print("== RealWorld capsule ECONOMY BOT (spec 0010, informational) ==")
	var income_hand: Dictionary = {}
	var income_tool: Dictionary = {}
	var supply: Dictionary = {}
	_measure_income(income_hand, income_tool, supply)
	var planks_ratio: float = _planks_per_wood()
	print("\n-- planks per wood from the catalogue recipe make_planks: %.4f (1 plank = %.2f wood)" % [planks_ratio, 1.0 / planks_ratio])
	var inc_hand: Dictionary = _medians(income_hand)
	var inc_tool: Dictionary = _medians(income_tool)
	inc_hand["planks"] = float(inc_hand["wood"]) * planks_ratio
	inc_tool["planks"] = float(inc_tool["wood"]) * planks_ratio
	print("\n-- income used for the ladder (units/min, median over the 5 presets) --")
	for res in ["wood", "stone", "scrap", "planks"]:
		print("   %-7s hand %6.2f   tool %6.2f" % [res, float(inc_hand[res]), float(inc_tool[res])])
	var supply_min: Dictionary = {}
	print("\n-- finite node SUPPLY per region (units; nodes never regrow): poorest preset bounds every price --")
	for res in GATHERED:
		var arr: Array = (supply[res] as Array).duplicate()
		arr.sort()
		supply_min[res] = int(arr[0])
		print("   %-6s min %5d  median %5d  max %5d" % [String(res), int(arr[0]), int(arr[arr.size() / 2]), int(arr[arr.size() - 1])])
	for g in LITERAL_G:
		var lit: Array = _ladder_literal(float(g), inc_hand, inc_tool)
		_print_ladder("LITERAL method T_1=%.0f min, g=%.1f (infeasible: see the supply use)" % [T1_MIN, float(g)], lit, inc_hand, inc_tool, supply_min, planks_ratio)
	var chosen: Array = _ladder_supply(CHOSEN_G, supply_min, planks_ratio)
	var title: String = "PROPOSAL: supply-bounded, budget %.0f%% of the poorest region, planks %.0f%% of wood, g=%.2f" % [SUPPLY_BUDGET * 100.0, PLANKS_OF_WOOD * 100.0, CHOSEN_G]
	_print_ladder(title, chosen, inc_hand, inc_tool, supply_min, planks_ratio)
	_radius_report()
	_buff_report(chosen, inc_hand, inc_tool)
	var raid: Array = _raid_report()
	_compare_with_catalog(chosen, raid)
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


func _measure_income(hand: Dictionary, tool: Dictionary, supply: Dictionary) -> void:
	print("-- INCOME: 600 sim-s of gathering the nearest node, per preset (units/min) --")
	print("   %-10s | %-21s | %-21s | node supply per kind (units; skipped stuck nodes, stash trips hand/tool)" % ["preset", "hand  wood stone scrap", "tool  wood stone scrap"])
	for preset in GameData.SPAWN_PRESETS:
		var line_h: String = ""
		var line_t: String = ""
		var supplies: String = ""
		for res in GATHERED:
			var rh: Dictionary = _gather_run(preset, String(res), "hand")
			var rt: Dictionary = _gather_run(preset, String(res), "tool")
			for d in [hand, tool, supply]:
				if not (d as Dictionary).has(res):
					d[res] = []
			(hand[res] as Array).append(float(rh.per_min))
			(tool[res] as Array).append(float(rt.per_min))
			(supply[res] as Array).append(int(rh.supply))
			line_h += "%6.1f" % float(rh.per_min)
			line_t += "%6.1f" % float(rt.per_min)
			supplies += "%4d (skip %d, trips %d/%d%s) " % [int(rh.supply), int(rh.skipped), int(rh.trips), int(rt.trips), " DIED:" + String(rh.cause) if bool(rh.died) or bool(rt.died) else ""]
		print("   %-10s | %-21s | %-21s | %s" % [String(preset.name), line_h, line_t, supplies])


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


# the method's LITERAL ladder: Array[level 1..5] of {level, tier, cost:{res:n}}; cost = round(T_L * income * share)
func _ladder_literal(g: float, inc_hand: Dictionary, inc_tool: Dictionary) -> Array:
	var out: Array = []
	for level in range(1, 6):
		var minutes: float = T1_MIN * pow(g, level - 1)
		var tier: String = _tier(level)
		var inc: Dictionary = inc_hand if tier == "hand" else inc_tool
		var cost: Dictionary = {}
		var shares: Dictionary = LITERAL_SHARES[level]
		for res in ["wood", "stone", "scrap", "planks"]:
			if shares.has(res):
				cost[res] = roundi(minutes * float(inc[res]) * float(shares[res]))
		out.append({"level": level, "tier": tier, "cost": cost})
	return out


# the PROPOSAL: the same time-to-buy formula with T_total and the shares DERIVED from the poorest region's finite supply:
# cost_L[res] = round(W_L x budget[res]), W_L = g^(L-1)/sum(g^k); planks (from L2) are carved out of the wood budget at the recipe ratio
func _ladder_supply(g: float, supply_min: Dictionary, planks_ratio: float) -> Array:
	var weights: Array = []
	var total: float = 0.0
	for level in range(1, 6):
		weights.append(pow(g, level - 1))
		total += float(weights[level - 1])
	var wood_budget: float = SUPPLY_BUDGET * float(supply_min["wood"])
	var out: Array = []
	for level in range(1, 6):
		var w: float = float(weights[level - 1]) / total
		var cost: Dictionary = {}
		if level == 1:
			cost["wood"] = roundi(w * wood_budget)
		else:
			cost["wood"] = roundi(w * wood_budget * (1.0 - PLANKS_OF_WOOD))
			cost["planks"] = roundi(w * wood_budget * PLANKS_OF_WOOD * planks_ratio)
		cost["stone"] = roundi(w * SUPPLY_BUDGET * float(supply_min["stone"]))
		cost["scrap"] = roundi(w * SUPPLY_BUDGET * float(supply_min["scrap"]))
		out.append({"level": level, "tier": _tier(level), "cost": cost})
	return out


func _tier(level: int) -> String:
	return "hand" if level <= 2 else "tool"   # tier-1 tools (axe / pick) are an early, cheap craft: from the 3rd level on the pace uses them


# minutes of pure gathering a price costs at the tier's income (an OUTPUT of the proposal, the INPUT of the literal ladder)
func _minutes(cost: Dictionary, tier: String, inc_hand: Dictionary, inc_tool: Dictionary) -> float:
	var inc: Dictionary = inc_hand if tier == "hand" else inc_tool
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


func _print_ladder(title: String, ladder: Array, inc_hand: Dictionary, inc_tool: Dictionary, supply_min: Dictionary, planks_ratio: float) -> void:
	print("\n== %s ==" % title)
	print("   L  tier  cost                                      units  minutes  pack-slots  extra-storages")
	var prev_units: int = 0
	var monotone: bool = true
	var feasible: bool = true
	var sum_wood_eq: float = 0.0
	var sum_stone: int = 0
	var sum_scrap: int = 0
	var sum_min: float = 0.0
	for row in ladder:
		var p: Dictionary = _payable(row.cost)
		var cost_s: String = ""
		for res in ["wood", "planks", "stone", "scrap"]:
			if (row.cost as Dictionary).has(res):
				cost_s += "%s %d  " % [res, int(row.cost[res])]
		var minutes: float = _minutes(row.cost, String(row.tier), inc_hand, inc_tool)
		sum_min += minutes
		print("   %d  %-4s  %-40s %5d  %7.1f  %10d  %d" % [int(row.level), String(row.tier), cost_s, int(p.units), minutes, int(p.slots), int(p.extra_storages)])
		if int(p.units) <= prev_units:
			monotone = false
		prev_units = int(p.units)
		if int(p.extra_storages) > EXTRA_STORAGES_OK:
			feasible = false
		sum_wood_eq += float(row.cost.get("wood", 0)) + float(row.cost.get("planks", 0)) / planks_ratio
		sum_stone += int(row.cost.get("stone", 0))
		sum_scrap += int(row.cost.get("scrap", 0))
	print("   whole ladder: %.1f min of pure gathering · strictly growing total: %s · payable with <= %d extra storages everywhere: %s" % [sum_min, str(monotone), EXTRA_STORAGES_OK, str(feasible)])
	var use_w: float = sum_wood_eq / float(supply_min["wood"])
	var use_st: float = float(sum_stone) / float(supply_min["stone"])
	var use_sc: float = float(sum_scrap) / float(supply_min["scrap"])
	print("   supply use of the POOREST region: wood-eq %.0f%% · stone %.0f%% · scrap %.0f%% · within the %.0f%% budget: %s" % [use_w * 100.0, use_st * 100.0, use_sc * 100.0, SUPPLY_BUDGET * 100.0,
		str(use_w <= SUPPLY_BUDGET + 0.005 and use_st <= SUPPLY_BUDGET + 0.005 and use_sc <= SUPPLY_BUDGET + 0.005)])


# R(L), the buildable cells inside the zone on the real maps (not water/rock, no node) — what an actual base can use
func _radius_report() -> void:
	print("\n-- RADIUS: R(L) = %d + %d*L ; R0 >= ceil(STASH_REACH=%.1f)=%d ; R(5)=%d <= n/4=%d : %s --" % [
		R0, R_STEP, Inventory.STASH_REACH, ceili(Inventory.STASH_REACH), R0 + R_STEP * 5, MAP_N / 4,
		str(R0 >= ceili(Inventory.STASH_REACH) and R0 + R_STEP * 5 <= MAP_N / 4)])
	print("   buildable cells inside the zone (median over presets; zone area (2R+1)^2-1):")
	var per_level: Array = []
	for level in range(0, 6):
		per_level.append([])
	for preset in GameData.SPAWN_PRESETS:
		var sim: Variant = _new_world(preset)
		var t: Vector2i = MainCapsule.tile(sim)
		for level in range(0, 6):
			var r: int = R0 + R_STEP * level
			var free: int = 0
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx == 0 and dy == 0:
						continue
					var c := Vector2i(t.x + dx, t.y + dy)
					if MainCapsule.cell_free(sim.map, c, sim.bgrid):
						free += 1
			(per_level[level] as Array).append(free)
	for level in range(0, 6):
		var arr: Array = (per_level[level] as Array).duplicate()
		arr.sort()
		var r: int = R0 + R_STEP * level
		print("   L%d  R=%2d  area=%4d  buildable median=%4d (min %d .. max %d)" % [level, r, (2 * r + 1) * (2 * r + 1) - 1, int(arr[arr.size() / 2]), int(arr[0]), int(arr[arr.size() - 1])])


func _buff_report(ladder: Array, inc_hand: Dictionary, inc_tool: Dictionary) -> void:
	print("\n-- BUFFS: buff(L) = 1 + %.2f*L (gather/melee/craft/research); cut-off: payback of the level's price through the buff >= 2 x its time-to-buy --" % BUFF_STEP)
	print("   L  buff   buy(min)  payback(min) = buy/step  >= 2*buy ?")
	for row in ladder:
		var buy: float = _minutes(row.cost, String(row.tier), inc_hand, inc_tool)
		var payback: float = buy / BUFF_STEP
		print("   %d  %.2f   %7.1f   %10.1f              %s" % [int(row.level), 1.0 + BUFF_STEP * int(row.level), buy, payback, str(payback >= 2.0 * buy)])


# count / day_equiv / dmg / t_open / core_hp per level through the EXISTING raider helpers
func _raid_report() -> Array:
	print("\n-- RAIDER + CORE HP: day_equiv(L) = %d + %d*L via GameData.make_raider / raid_wave_size; core_hp = count*dmg*t_open/atk_cd(%.1f) --" % [DAY_EQUIV_BASE, DAY_EQUIV_STEP, BUILDING_ATK_CD])
	print("   L  day_eq  raiders  dmg   hp     speed  t_open(s)  core_hp")
	var out: Array = []
	for level in range(0, 6):
		var day_eq: int = DAY_EQUIV_BASE + DAY_EQUIV_STEP * level
		var raider: Dictionary = GameData.make_raider(0.0, 0.0, day_eq)
		var count: int = GameData.raid_wave_size(day_eq)
		var t_open: float = T_OPEN_BASE_S + T_OPEN_STEP_S * level
		var core_hp: int = roundi(float(count) * float(raider.dmg) * t_open / BUILDING_ATK_CD)
		print("   %d  %5d  %7d  %4.1f  %5.1f  %4.1f  %8.1f  %7d" % [level, day_eq, count, float(raider.dmg), float(raider.maxhp), float(raider.speed), t_open, core_hp])
		out.append({"level": level, "day_equiv": day_eq, "count": count, "t_open_s": t_open, "core_hp": core_hp})
	print("   warning_s = %.0f  (reaction ~30 s + R(5)/v_hero ~ 4 s, one constant with a margin)" % WARNING_S)
	return out


func _compare_with_catalog(ladder: Array, raid: Array) -> void:
	print("\n-- catalog.json capsule_levels vs this proposal (MATCH / DIFF; informational) --")
	var table: Dictionary = (Catalog.load_json().get("capsule_levels", {}) as Dictionary)
	if table.is_empty():
		print("   catalog.json has no capsule_levels yet")
		return
	var levels: Array = table.get("levels", [])
	for row in ladder:
		var data_row: Dictionary = levels[int(row.level)]
		var same_cost: bool = true
		for res in row.cost:
			if int((data_row.cost as Dictionary).get(res, -1)) != int(row.cost[res]):
				same_cost = false
		if (data_row.cost as Dictionary).size() != (row.cost as Dictionary).size():
			same_cost = false
		print("   L%d cost  %s" % [int(row.level), "MATCH" if same_cost else "DIFF  data=%s bot=%s" % [str(data_row.cost), str(row.cost)]])
	for level in range(0, 6):
		var data_row: Dictionary = levels[level]
		var r: int = R0 + R_STEP * level
		var bot_hp: int = int((raid[level] as Dictionary).core_hp)
		print("   L%d radius %s · core_hp %s" % [level, "MATCH" if int(data_row.radius) == r else "DIFF data=%d bot=%d" % [int(data_row.radius), r],
			"MATCH" if roundi(float(data_row.core_hp)) == bot_hp else "DIFF data=%s bot=%d" % [str(data_row.core_hp), bot_hp]])
	for level in range(0, 6):
		var b: Dictionary = (levels[level] as Dictionary).get("buffs", {})
		var want_n: int = 0 if level == 0 else MainCapsule.BUFF_KEYS.size()
		var same_b: bool = b.size() == want_n
		for key in b:
			same_b = same_b and absf(float(b[key]) - (1.0 + BUFF_STEP * level)) < 0.0001
		print("   L%d buffs  %s" % [level, "MATCH" if same_b else "DIFF data=%s want 1+%.2f*L on %d keys" % [str(b), BUFF_STEP, want_n]])
	var warn: float = float((table.get("raid", {}) as Dictionary).get("warning_s", -1.0))
	print("   raid.warning_s  %s" % ["MATCH" if warn == WARNING_S else "DIFF data=%s bot=%s" % [str(warn), str(WARNING_S)]])
	var by_level: Dictionary = (table.get("raid", {}) as Dictionary).get("by_level", {})
	for level in range(1, 6):
		var bl: Dictionary = by_level.get(str(level), {})
		var bot: Dictionary = raid[level]
		var same: bool = int(bl.get("count", -1)) == int(bot.count) and int(bl.get("day_equiv", -1)) == int(bot.day_equiv) and float(bl.get("t_open_s", -1.0)) == float(bot.t_open_s)
		print("   L%d raider  %s" % [level, "MATCH" if same else "DIFF data=%s bot=%s" % [str(bl), str(bot)]])

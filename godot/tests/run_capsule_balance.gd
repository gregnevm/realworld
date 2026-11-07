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
#   3. FEASIBILITY — HONESTLY: the finite map cannot pay the owner's formula (a level-5 price is ~16x the level-1 one, 24 h of gathering). The bot
#      prints the cumulative supply use per preset, «НЕ ЗДІЙСНЕННО на карті 56x56» where it exceeds the region's nodes, the pack/storage payability,
#      and the two QUESTIONS for the owner: (a) scale the ladder to the supply (the largest uniform scale that fits the poorest region's budget),
#      (b) regrow resources (OD-84: wood only — stone and scrap stay finite, so regrowth alone does not fix it). The data keep the OD formula, NOT a
#      map-fitted number (feasibility_note says so).
#   4. DEFENCE — core_hp(P) = base x FACTOR^(P-1), P >= 1 (OD-103: x2 per level, x16 at 5), P = 0 is base / FACTOR; base = what the REFERENCE raid
#      (the weakest: day_equiv 4 through the EXISTING GameData.make_raider / raid_wave_size) deals to an undefended core in T_OPEN_REF seconds
#      (working interpretation until Q-5; the raider strength by capsule level is Balance.assess, a later wave).
#   5. RADIUS — R_cells = ceil(RADIUS_M / CELL_M); CELL_M is the ONLY trace of a map scale in the code (the frozen main.gd _fetch_osm: a 380 m radius
#      over the 56-cell map = 760 m / 56 cells); the live procedural map has none — Q-4, a proposal until the owner fixes N m per cell.
#   6. BUFFS — the owner's +10% per level (OD-98): printed, with the payback of a level's price through the gather buff (informational).
# Finally it prints MATCH/DIFF of every proposed number against godot/content/catalog.json (capsule_levels), so the data cannot drift from the
# method unnoticed. The pass/fail counter only says the probe ran — read the printed tables.
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
const LEVELS := 5

# ---- the OWNER's numbers (decisions.md) ----
const LADDER := 2.0                # OD-65/93: every level costs ~x2 (the same coefficient for the defence axis, OD-103)
const T1_MIN := 90.0               # OD-93: level 1 ~ 1–2 hours of gathering at 1:1 -> the middle, 1.5 h
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
const SUPPLY_BUDGET := 0.30        # alternative (a): the whole ladder may take this fraction of the POOREST region's nodes
const PACK_SLOTS := 24             # the backpack proper (slots 8..31); the hotbar holds tools/buildings
const BASE_STORAGE_ROOM := 450     # storage_cap() at the start: 200 + the capsule's 250 (GameData.BUILDINGS.storage.capacity)
const STORAGE_STEP := 250


func _init() -> void:
	print("== RealWorld capsule ECONOMY BOT (spec 0010, informational) ==")
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
	var capsule: Array = _ladder(inc_hand)
	_print_ladder("PROPOSAL: level-of-capsule axis — T_1=%.0f min x %.0f per level over the bare-hand income (OD-93/65)" % [T1_MIN, LADDER], capsule, inc_hand)
	print("   protection axis (Q-5 A: the SAME rules) — identical prices by construction: %s" % str(capsule == _ladder(inc_hand)))
	_feasibility_report(capsule, inc_hand, inc_tool, by_preset, supply, planks_ratio)
	var hp: Array = _defence_report()
	var cells: int = _radius_report()
	_buff_report(capsule, inc_hand)
	_compare_with_catalog(capsule, hp, cells)
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
func _ladder(inc_hand: Dictionary) -> Array:
	var out: Array = []
	for level in range(1, LEVELS + 1):
		var minutes: float = T1_MIN * pow(LADDER, level - 1)
		var cost: Dictionary = {}
		var shares: Dictionary = SHARES[level]
		for res in ["wood", "stone", "planks", "scrap"]:
			if shares.has(res):
				cost[res] = roundi(minutes * float(inc_hand[res]) * float(shares[res]))
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
	print("   rarest ingredient never gets more common with the level (OD-75): %s · level-1 price = %.1f min of gathering (OD-93: 60..120): %s" % [
		str(rank_ok), float(ladder[0].minutes), str(float(ladder[0].minutes) >= 60.0 and float(ladder[0].minutes) <= 120.0)])
	var total_min: float = 0.0
	for row in ladder:
		total_min += float(row.minutes)
	print("   whole ladder (levels 1..5): %.0f min = %.1f h of pure gathering (level 5 alone: %.1f h)" % [total_min, total_min / 60.0, float(ladder[LEVELS - 1].minutes) / 60.0])


# is the owner's formula payable on the real finite map? cumulative supply use per preset + the two alternatives (QUESTIONS for the owner)
func _feasibility_report(ladder: Array, inc_hand: Dictionary, inc_tool: Dictionary, by_preset: Array, supply: Dictionary, planks_ratio: float) -> void:
	print("\n== FEASIBILITY on the finite 56x56 map (cumulative price of levels 1..L vs the region's nodes; >100%% = НЕ ЗДІЙСНЕННО) ==")
	var cum: Dictionary = {"wood": 0.0, "stone": 0.0, "scrap": 0.0}
	var cum_rows: Array = []
	for row in ladder:
		cum["wood"] = float(cum["wood"]) + float(row.cost.get("wood", 0)) + float(row.cost.get("planks", 0)) / planks_ratio
		cum["stone"] = float(cum["stone"]) + float(row.cost.get("stone", 0))
		cum["scrap"] = float(cum["scrap"]) + float(row.cost.get("scrap", 0))
		cum_rows.append(cum.duplicate())
	print("   preset     |  L1 wood-eq/stone/scrap use     |  L2                           |  L3                           |  L4                           |  L5")
	var worst_level_poorest: int = LEVELS + 1
	for ps in by_preset:
		var line: String = "   %-10s |" % String(ps.name)
		var first_bad: int = LEVELS + 1
		for li in LEVELS:
			var u: Array = []
			var bad: bool = false
			for res in GATHERED:
				var pct: float = 100.0 * float((cum_rows[li] as Dictionary)[res]) / float((ps.supply as Dictionary)[res])
				u.append("%4.0f%%" % pct)
				bad = bad or pct > 100.0
			if bad and first_bad > li + 1:
				first_bad = li + 1
			line += " %s %s %s%s |" % [u[0], u[1], u[2], " X" if bad else "  "]
		print(line + ("  first infeasible level: %s" % (str(first_bad) if first_bad <= LEVELS else "none")))
		worst_level_poorest = mini(worst_level_poorest, first_bad)
	print("   -> НЕ ЗДІЙСНЕННО на карті 56x56 за формулою OD-93/65: у найбіднішому регіоні рівень %d уже неоплатний (деревина/камінь/брухт — скінченні);" % worst_level_poorest)
	var supply_min: Dictionary = {}
	var supply_med: Dictionary = {}
	for res in GATHERED:
		var arr: Array = (supply[res] as Array).duplicate()
		arr.sort()
		supply_min[res] = float(arr[0])
		supply_med[res] = float(arr[arr.size() / 2])
	var demand: Dictionary = cum_rows[LEVELS - 1]
	var scale_a: float = 1.0
	var binding: String = ""
	for res in GATHERED:
		var s_res: float = SUPPLY_BUDGET * float(supply_min[res]) / float(demand[res])
		if s_res < scale_a:
			scale_a = s_res
			binding = String(res)
	var scale_med: float = 1.0
	for res in GATHERED:
		scale_med = minf(scale_med, SUPPLY_BUDGET * float(supply_med[res]) / float(demand[res]))
	print("   QUESTION (a) scale the ladder to the supply: the largest uniform scale keeping the 5 levels within %.0f%% of the POOREST region" % [SUPPLY_BUDGET * 100.0])
	print("      is x%.4f (binding: %s) -> level 1 would cost %.2f min (not 60..120);" % [scale_a, binding, T1_MIN * scale_a])
	print("      for the MEDIAN region x%.4f -> level 1 = %.2f min. Either way the owner's 1–2 h at level 1 and x2 per level cannot both hold on this map" % [scale_med, T1_MIN * scale_med])
	var wood_free: float = 1.0
	for res in ["stone", "scrap"]:
		wood_free = minf(wood_free, SUPPLY_BUDGET * float(supply_min[res]) / float(demand[res]))
	print("   QUESTION (b) regrowth (OD-84: only wood is renewable): wood-eq demand of levels 1..5 = %.0f vs the poorest region's %.0f; stone %.0f vs %.0f; scrap %.0f vs %.0f —" % [
		float(demand["wood"]), float(supply_min["wood"]), float(demand["stone"]), float(supply_min["stone"]), float(demand["scrap"]), float(supply_min["scrap"])])
	print("      stone and scrap stay finite, so regrowing wood alone leaves the ladder %.1fx over the stone/scrap budget (scale x%.4f needed even then)" % [1.0 / maxf(wood_free, 0.000001), wood_free])
	print("   QUESTION (c) map size (OD-21: «карти великі, ресурси дуже численні, але скінченні»): the supply would have to grow x%.0f to pay the formula" % [1.0 / scale_a])
	var side: float = float(MAP_N) * sqrt(1.0 / scale_a)
	print("      within %.0f%% (the 56x56 prototype has %d cells; that is %.0f x %.0f cells)" % [SUPPLY_BUDGET * 100.0, MAP_N * MAP_N, side, side])
	var tool_gain: float = float(inc_tool["wood"]) / float(inc_hand["wood"])
	print("   tools do not rescue it: the tier-1 tool speeds wood x%.2f, stone x%.2f, scrap x%.2f (the supply, not the pace, is the limit)" % [
		tool_gain, float(inc_tool["stone"]) / float(inc_hand["stone"]), float(inc_tool["scrap"]) / float(inc_hand["scrap"])])
	var p1: Dictionary = _payable(ladder[0].cost)
	print("   payability of level 1 alone: %d pack slots needed (the backpack has %d) and %d extra storages beyond the capsule's (+%d units each)" % [
		int(p1.slots), PACK_SLOTS, int(p1.extra_storages), STORAGE_STEP])


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

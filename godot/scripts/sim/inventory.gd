# RealWorld — sim/inventory.gd : the Minecraft-style personal inventory (spec 0009).
#
# Domain module of the live sim (threats/environment pattern): stateless `static func`s on `s` (the sim),
# no preload of sim.gd (no cycle). Active only when `s.use_inventory` is ON (new games); OFF keeps the
# old stock/carry/build-palette path byte-for-byte (old saves, every pre-0009 suite).
#
# Model (owner decisions 2026-11-04): 32 slots = 8 hotbar + 24 backpack; slot = {id, n}; stacks by kind.
# BUILDINGS ARE ITEMS «bld:<kind>»: crafted into the backpack, placed from the hand. Crafting/building pays
# from the BACKPACK only; reaching into storages nearby is a progression perk (storage link, unlocked by
# the gather skill). Death drops the inventory as a BAG on the spot (persistent, picked up by walking to it).
# Everything is a pure function of state: deterministic, no RNG.
extends RefCounted

const GameData = preload("res://scripts/data.gd")

const SLOTS := 32
const HOTBAR := 8
const BLD := "bld:"
const RAW_STACK := 50          # wood, stone, fibre … (Valheim/Don't Starve-like caps, 1 item = 1 cell)
const PROCESSED_STACK := 25    # planks, bars, bricks
const SMALL_STACK := 10        # components, scrap-grade parts
const FOOD_STACK := 20
const BLOCK_STACK := 20        # walls, floors, doors, spikes — laid in rows
const BUILDING_STACK := 5      # benches, beds, turrets
const ROW_PIECES := ["wall", "floor", "door", "spike_trap"]
# hand-craftable buildings (anything else needs a workbench within reach)
const HAND_CRAFT := ["wall", "floor", "door", "campfire", "torch", "storage", "bed", "workbench"]
const STATION_REACH := 3.5
const STASH_REACH := 2.5       # stand this close to a storage to stash / take
const LINK_REACH := 10.0       # storage-link perk: storages within this many tiles count as yours
const LINK_SKILL := 2.0        # gather skill that unlocks the storage link (≈ 10 units gathered)
const BAG_REACH := 1.5

static func empty_slots() -> Array:
	var out: Array = []
	for i in SLOTS:
		out.append({"id": "", "n": 0})
	return out

static func is_building(id: String) -> bool:
	return id.begins_with(BLD)

static func building_kind(id: String) -> String:
	return id.substr(BLD.length()) if is_building(id) else ""

static func stack_max(id: String) -> int:
	if id == "":
		return 0
	if is_building(id):
		return BLOCK_STACK if ROW_PIECES.has(building_kind(id)) else BUILDING_STACK
	if GameData.ITEMS.has(id):
		return 1
	match id:
		"wood", "stone", "fiber", "clay", "sand", "grain", "herbs":
			return RAW_STACK
		"planks", "iron_bar", "bricks", "flour":
			return PROCESSED_STACK
		"food", "bread", "meat":
			return FOOD_STACK
	return SMALL_STACK

# ---- counting / adding / taking ------------------------------------------------------------------
static func count(s, id: String) -> int:
	var c := 0
	for sl in s.player.inv:
		if String(sl.id) == id:
			c += int(sl.n)
	return c

# Room for `id` (how many more units fit).
static func room(s, id: String) -> int:
	var cap := stack_max(id)
	var r := 0
	for sl in s.player.inv:
		if String(sl.id) == id:
			r += cap - int(sl.n)
		elif String(sl.id) == "":
			r += cap
	return r

# Add up to n units: fill existing stacks first (hotbar → backpack), then empty slots (backpack first, so
# loot never shoves the hotbar around). Returns the units that did NOT fit.
static func add(s, id: String, n: int) -> int:
	if n <= 0 or id == "":
		return maxi(0, n)
	var cap := stack_max(id)
	var inv: Array = s.player.inv
	for sl in inv:
		if n <= 0:
			break
		if String(sl.id) == id and int(sl.n) < cap:
			var k: int = mini(cap - int(sl.n), n)
			sl.n = int(sl.n) + k
			n -= k
	var order: Array = range(HOTBAR, SLOTS) + range(0, HOTBAR)
	if is_building(id) or GameData.ITEMS.has(id):
		order = range(0, SLOTS)   # tools and buildings are things you HOLD: hotbar first
	for i in order:
		if n <= 0:
			break
		var sl: Dictionary = inv[i]
		if String(sl.id) == "":
			var k: int = mini(cap, n)
			sl.id = id
			sl.n = k
			n -= k
	return n

# Take exactly n units (all-or-nothing). Backpack first, hotbar last (keep what is in hand).
static func take(s, id: String, n: int) -> bool:
	if n <= 0:
		return true
	if count(s, id) < n:
		return false
	var inv: Array = s.player.inv
	for i in range(SLOTS - 1, -1, -1):
		if n <= 0:
			break
		var sl: Dictionary = inv[i]
		if String(sl.id) == id:
			var k: int = mini(int(sl.n), n)
			sl.n = int(sl.n) - k
			n -= k
			if int(sl.n) <= 0:
				sl.id = ""
				sl.n = 0
	return true

# Move / merge / swap two slots (the «tap one, tap another» touch grammar).
static func move(s, a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= SLOTS or b >= SLOTS:
		return
	var inv: Array = s.player.inv
	var sa: Dictionary = inv[a]
	var sb: Dictionary = inv[b]
	if String(sa.id) != "" and String(sa.id) == String(sb.id):
		var cap := stack_max(String(sa.id))
		var k: int = mini(cap - int(sb.n), int(sa.n))
		sb.n = int(sb.n) + k
		sa.n = int(sa.n) - k
		if int(sa.n) <= 0:
			sa.id = ""
			sa.n = 0
		return
	inv[a] = sb
	inv[b] = sa

# Pick the hand slot; holding a tool/weapon IS using it (equip follows the hand).
static func set_hand(s, i: int) -> void:
	if not s.use_inventory:
		return
	s.player.hand = clampi(i, 0, HOTBAR - 1)
	var h: Dictionary = held(s)
	if GameData.ITEMS.has(String(h.id)):
		s.equip(String(h.id))

static func held(s) -> Dictionary:
	var h: int = clampi(int(s.player.get("hand", 0)), 0, HOTBAR - 1)
	return s.player.inv[h]

# ---- paying: backpack, plus linked storages when the perk is unlocked and one is near ----------------
static func link_unlocked(s) -> bool:
	return float(s.player.skills.get("gather", 0.0)) >= LINK_SKILL

static func _linked(s, at: Vector2) -> bool:
	if not link_unlocked(s):
		return false
	for b in s.buildings:
		if String(b.kind) == "storage" and at.distance_to(Vector2(b.x + 0.5, b.y + 0.5)) <= LINK_REACH:
			return true
	return false

static func can_pay(s, cost: Dictionary, at: Vector2) -> bool:
	var linked := _linked(s, at)
	for res in cost:
		var have: int = count(s, String(res)) + (int(s.res_amount(String(res))) if linked else 0)
		if have < int(cost[res]):
			return false
	return true

static func pay(s, cost: Dictionary, at: Vector2) -> bool:
	if not can_pay(s, cost, at):
		return false
	var linked := _linked(s, at)
	for res in cost:
		var need: int = int(cost[res])
		var from_inv: int = mini(count(s, String(res)), need)
		take(s, String(res), from_inv)
		need -= from_inv
		if need > 0 and linked:
			s._stock_take(String(res), need)
	return true

static func missing(s, cost: Dictionary, at: Vector2) -> Dictionary:
	var linked := _linked(s, at)
	var out := {}
	for res in cost:
		var have: int = count(s, String(res)) + (int(s.res_amount(String(res))) if linked else 0)
		if have < int(cost[res]):
			out[res] = int(cost[res]) - have
	return out

# ---- crafting a building into the backpack --------------------------------------------------------
static func near_station(s, station: String) -> bool:
	var at := Vector2(s.player.px, s.player.py)
	for b in s.buildings:
		if String(b.kind) == station and at.distance_to(Vector2(b.x + 0.5, b.y + 0.5)) <= STATION_REACH:
			return true
	return false

static func building_recipe(s, kind: String) -> Dictionary:
	var def: Dictionary = s.building_def(kind)
	if def.is_empty():
		return {}
	return {"kind": kind, "cost": def.get("cost", {}), "station": "" if HAND_CRAFT.has(kind) else "workbench",
		"name": String(def.get("name", kind))}

static func craft_building(s, kind: String) -> Dictionary:
	var rc := building_recipe(s, kind)
	if rc.is_empty():
		return {"ok": false, "msg": "Невідома будівля."}
	var def: Dictionary = s.building_def(kind)
	if not s.research_ok(def):
		return {"ok": false, "msg": "🔒 Потребує дослідження: %s." % s._research_label(def)}
	if String(rc.station) != "" and not near_station(s, String(rc.station)):
		return {"ok": false, "msg": "Потрібен верстак поруч."}
	var at := Vector2(s.player.px, s.player.py)
	if not can_pay(s, rc.cost, at):
		return {"ok": false, "msg": "%s — бракує: %s" % [String(rc.name), s._cost_str(missing(s, rc.cost, at))]}
	if room(s, BLD + kind) < 1:
		return {"ok": false, "msg": "Рюкзак повний."}
	pay(s, rc.cost, at)
	add(s, BLD + kind, 1)
	s._log("🛠 %s → у рюкзак." % String(rc.name), "good")
	return {"ok": true}

# ---- the storage chest: stash everything stackable / take a resource out --------------------------
static func near_storage(s) -> bool:
	var at := Vector2(s.player.px, s.player.py)
	for b in s.buildings:
		if String(b.kind) == "storage" and at.distance_to(Vector2(b.x + 0.5, b.y + 0.5)) <= STASH_REACH:
			return true
	return false

static func stash_all(s) -> Dictionary:
	if not near_storage(s):
		return {"ok": false, "msg": "Підійди до складу."}
	var moved := 0
	for i in range(HOTBAR, SLOTS):          # the backpack only: the hand row stays as the player set it
		var sl: Dictionary = s.player.inv[i]
		var id := String(sl.id)
		if id == "" or is_building(id) or GameData.ITEMS.has(id) or not GameData.RES.has(id):
			continue
		var put: int = s.deposit(id, int(sl.n), true)
		sl.n = int(sl.n) - put
		moved += put
		if int(sl.n) <= 0:
			sl.id = ""
			sl.n = 0
	return {"ok": moved > 0, "moved": moved, "msg": ("⇣ Розкладено на склад: %d" % moved) if moved > 0 else "Нема що розкласти."}

static func take_from_storage(s, res: String, n: int) -> Dictionary:
	if not near_storage(s):
		return {"ok": false, "msg": "Підійди до складу."}
	var k: int = mini(n, mini(int(s.res_amount(res)), room(s, res)))
	if k <= 0:
		return {"ok": false, "msg": "Нема на складі або рюкзак повний."}
	s._stock_take(res, k)
	add(s, res, k)
	return {"ok": true, "taken": k}

# ---- death bag ------------------------------------------------------------------------------------
static func drop_bag(s) -> void:
	var slots: Array = []
	for sl in s.player.inv:
		if String(sl.id) != "":
			slots.append({"id": String(sl.id), "n": int(sl.n)})
	if slots.is_empty():
		return
	s.bags.append({"x": int(s.player.px), "y": int(s.player.py), "slots": slots, "day": int(s.time.day)})
	s.player.inv = empty_slots()

# Walk-over pickup (called every tick): whatever fits comes back, the rest stays in the bag. A bag you just
# DROPPED is unarmed until you step away from it (otherwise it would jump straight back into your hands).
static func pickup_bags(s) -> void:
	if s.bags.is_empty():
		return
	var at := Vector2(s.player.px, s.player.py)
	for bag in s.bags.duplicate():
		var d: float = at.distance_to(Vector2(int(bag.x) + 0.5, int(bag.y) + 0.5))
		if not bool(bag.get("armed", true)):
			if d > BAG_REACH + 1.0:
				bag.armed = true
			continue
		if d > BAG_REACH:
			continue
		var left: Array = []
		for sl in bag.slots:
			var rest: int = add(s, String(sl.id), int(sl.n))
			if rest > 0:
				left.append({"id": String(sl.id), "n": rest})
		if left.is_empty():
			s.bags.erase(bag)
			s._log("🎒 Торбу підібрано — усе повернулось.", "good")
		else:
			bag.slots = left
			s._flash("🎒 Рюкзак повний — частина лишилась у торбі.")

# Starter kit for a fresh pawn in an inventory world: something to light, something to eat, a little stock.
static func starter(s) -> void:
	s.player.inv = empty_slots()
	s.player.hand = 0
	add(s, BLD + "campfire", 1)
	add(s, "wood", 20)
	add(s, "stone", 10)
	add(s, "food", 8)

# Tool/weapon crafting in an inventory world: paid from the backpack (+ linked storages), lands in the pack,
# is owned and equipped. The caller (sim.craft_item) has already checked id / workbench / research.
static func craft_tool(s, item_id: String) -> Dictionary:
	var recipe: Dictionary = GameData.ITEMS[item_id].recipe
	var at := Vector2(s.player.px, s.player.py)
	if not can_pay(s, recipe, at):
		return {"ok": false, "msg": "%s — бракує: %s" % [String(GameData.ITEMS[item_id].get("name", item_id)), s._cost_str(missing(s, recipe, at))]}
	if room(s, item_id) < 1:
		return {"ok": false, "msg": "Рюкзак повний."}
	pay(s, recipe, at)
	add(s, item_id, 1)
	s.player.items.append(item_id)
	s.equip(item_id)
	s._log("🛠 Скрафтив: %s → у рюкзак." % GameData.ITEMS[item_id].name, "good")
	return {"ok": true}

# ---- phase 2: sort · split · drop ----------------------------------------------------------------
const SORT_ORDER := ["bld", "tool", "raw", "processed", "food", "other"]

static func _sort_key(id: String) -> String:
	var cat := "other"
	if is_building(id):
		cat = "bld"
	elif GameData.ITEMS.has(id):
		cat = "tool"
	else:
		match stack_max(id):
			RAW_STACK: cat = "raw"
			PROCESSED_STACK: cat = "processed"
			FOOD_STACK: cat = "food"
	return "%d:%s" % [SORT_ORDER.find(cat), id]

# Backpack only (slots 8..31): merge equal stacks, then lay them out by category → id. The hotbar is the
# player's own arrangement and is never touched. Deterministic (pure sort on a string key).
static func sort_backpack(s) -> void:
	var totals := {}
	var order: Array = []
	for i in range(HOTBAR, SLOTS):
		var sl: Dictionary = s.player.inv[i]
		var id := String(sl.id)
		if id == "":
			continue
		if not totals.has(id):
			totals[id] = 0
			order.append(id)
		totals[id] = int(totals[id]) + int(sl.n)
		sl.id = ""
		sl.n = 0
	order.sort_custom(func(a: String, b: String) -> bool: return _sort_key(a) < _sort_key(b))
	var i := HOTBAR
	for id in order:
		var left: int = int(totals[id])
		var cap := stack_max(id)
		while left > 0 and i < SLOTS:
			var k: int = mini(cap, left)
			s.player.inv[i] = {"id": id, "n": k}
			left -= k
			i += 1

# Split a stack in half into the first empty slot (backpack first). The touch-friendly stand-in for a
# quantity slider: repeat to make smaller piles.
static func split(s, i: int) -> bool:
	if i < 0 or i >= SLOTS:
		return false
	var sl: Dictionary = s.player.inv[i]
	if String(sl.id) == "" or int(sl.n) < 2:
		return false
	var order: Array = range(HOTBAR, SLOTS) + range(0, HOTBAR)
	for j in order:
		if j != i and String(s.player.inv[j].id) == "":
			var half: int = int(sl.n) / 2
			sl.n = int(sl.n) - half
			s.player.inv[j] = {"id": String(sl.id), "n": half}
			return true
	return false

# Drop a whole slot on the ground as a small bag (unarmed until you walk away).
static func drop(s, i: int) -> bool:
	if i < 0 or i >= SLOTS:
		return false
	var sl: Dictionary = s.player.inv[i]
	if String(sl.id) == "":
		return false
	s.bags.append({"x": int(s.player.px), "y": int(s.player.py), "slots": [{"id": String(sl.id), "n": int(sl.n)}],
		"day": int(s.time.day), "armed": false})
	s.player.inv[i] = {"id": "", "n": 0}
	return true

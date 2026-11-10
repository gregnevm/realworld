# RealWorld — ui/goal_pointer.gd : spec 0014 (B+C, OD-127/125/126, 2026-11-09). A world marker: WHERE to act on the current goal /
# the cold's remedy. VIEW-ONLY: a pure function of (sim, vm slices) — nothing is written, no RNG, no clock; the tap does nothing
# (OD-128 «лише показ»). One marker at a time (REQ-0014-8).
extends RefCounted

const FormatScript = preload("res://scripts/ui/format.gd")
const InventoryMod = preload("res://scripts/sim/inventory.gd")
const LEARN_DAYS := 2          # = VitalsPanel.LEARN_DAYS: the word under the ring only while learning (REQ-0014-13)
const REACH := 6               # search radius (cells) around the hero

# The building kind the marker is about: the cold's remedy beats the goal chain (works without the chain, OD-129), else the
# current goal's own building. "" = nothing to point at.
static func target_kind(vm: Dictionary) -> String:
	if StringName((vm.get("vitals", {}) as Dictionary).get("comfort", &"ok")) == &"cold":
		return "campfire"
	return String((((vm.get("goals", {}) as Dictionary).get("current", {})) as Dictionary).get("build", ""))

# {} or {"kind": "goal"|"need", "build": id, "cell": Vector2i, "label": String}. `placing` = a ghost is already in hand → hide (REQ-6).
static func compute(sim, vm: Dictionary, placing: bool) -> Dictionary:
	if placing or bool(sim.dead):
		return {}
	var build := target_kind(vm)
	if build == "":
		return _gather_pointer(sim, vm)   # REQ-0014-3: ціль «добудь ресурси» → найближчий вузол дерева/скелі

	var def: Dictionary = sim.building_def(build)
	if def.is_empty():
		return {}
	if sim.use_inventory and int(InventoryMod.count(sim, InventoryMod.BLD + build)) <= 0:
		return {}   # REQ-0014-12: not carried yet → the backpack button breathes, not the map
	var cell: Variant = anchor_cell(sim, build, def)
	if cell == null:
		return {}
	var day: int = int((vm.get("clock", {}) as Dictionary).get("day", 1))
	var cold: bool = StringName((vm.get("vitals", {}) as Dictionary).get("comfort", &"ok")) == &"cold"
	return {"kind": "need" if cold else "goal", "build": build, "cell": cell,
		"label": String(def.get("name", "")) if day <= LEARN_DAYS else ""}

# REQ-0014-3: the nearest tree/rock node with something left (order: distance, y, x); {} when none within 2×REACH or the goal is not «gather».
static func _gather_pointer(sim, vm: Dictionary) -> Dictionary:
	var cur: Dictionary = (vm.get("goals", {}) as Dictionary).get("current", {})
	if String(cur.get("id", "")) != "gather":
		return {}
	var hx: int = int(sim.player.px)
	var hy: int = int(sim.player.py)
	var reach: int = REACH * 2
	var best: Variant = null
	var best_key := [1 << 30, 0, 0]
	var kind_at := ""
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var x: int = hx + dx
			var y: int = hy + dy
			if not sim._in(x, y) or not sim.map.nodes.has(y * int(sim.n) + x):
				continue
			var nd: Dictionary = sim.map.nodes[y * int(sim.n) + x]
			var k := String(nd.get("kind", ""))
			if (k != "tree" and k != "rock") or int(nd.get("amount", 0)) <= 0:
				continue
			var key := [absi(dx) + absi(dy), y, x]
			if key < best_key:
				best_key = key
				best = Vector2i(x, y)
				kind_at = k
	if best == null:
		return {}
	var day: int = int((vm.get("clock", {}) as Dictionary).get("day", 1))
	var word := "Дерево" if kind_at == "tree" else "Скеля"
	return {"kind": "goal", "build": "", "cell": best, "label": word if day <= LEARN_DAYS else ""}

# Nearest free cell where try_build WOULD accept `def` (same predicates as hud_model._ghost_refusal), order: distance, y, x.
static func anchor_cell(sim, _build: String, def: Dictionary) -> Variant:
	var hx: int = int(sim.player.px)
	var hy: int = int(sim.player.py)
	var best: Variant = null
	var best_key := [1 << 30, 0, 0]
	for dy in range(-REACH, REACH + 1):
		for dx in range(-REACH, REACH + 1):
			var x: int = hx + dx
			var y: int = hy + dy
			if (dx == 0 and dy == 0) or not sim.build_valid(x, y) or String(sim._kind_refusal(def, x, y)) != "":
				continue
			var d: int = absi(dx) + absi(dy)
			var key := [d, y, x]
			if key < best_key:
				best_key = key
				best = Vector2i(x, y)
	return best

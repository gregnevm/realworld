# RealWorld — sim/safe_stock.gd : spec 0011 REQ-0011-7/54/68/71 — the Orbit's safe stock (the ONE container, owner: 0011).
#
# 32 slots (OD-61/105), slot = {id, n} or {} (empty), stacks by the same caps as the personal inventory (spec 0009:
# Inventory.stack_max), no weight. Duck-typed seam for sim/orbit_stub.gd: `deposit(res, n) -> int` (the ACCEPTED amount — partial, OD-58).
# Deterministic: stacks are filled in slot order, then empty slots in slot order. Integers only; no clock, no RNG.
extends RefCounted

const Inventory = preload("res://scripts/sim/inventory.gd")

const SLOTS := 32

var slots: Array = []


func _init() -> void:
	for i in SLOTS:
		slots.append({})


# Free room for `id`: space in its open stacks + empty slots × cap.
func room_for(id: String) -> int:
	var cap: int = Inventory.stack_max(id)
	var room: int = 0
	for sl in slots:
		var d: Dictionary = sl
		if d.is_empty():
			room += cap
		elif String(d.get("id", "")) == id:
			room += maxi(0, cap - int(d.get("n", 0)))
	return room


# REQ-0011-54/68: n ≤ 0 is rejected (0 accepted); n > room → partial transfer. Returns the amount accepted.
func deposit(res: String, n: int) -> int:
	if n <= 0 or res == "":
		return 0
	var cap: int = Inventory.stack_max(res)
	var left: int = n
	for i in SLOTS:
		if left <= 0:
			break
		var d: Dictionary = slots[i]
		if not d.is_empty() and String(d.get("id", "")) == res:
			var put: int = mini(left, cap - int(d.get("n", 0)))
			if put > 0:
				d["n"] = int(d.get("n", 0)) + put
				left -= put
	for i in SLOTS:
		if left <= 0:
			break
		var d: Dictionary = slots[i]
		if d.is_empty():
			var put: int = mini(left, cap)
			slots[i] = {"id": res, "n": put}
			left -= put
	return n - left


func count(id: String) -> int:
	var c: int = 0
	for sl in slots:
		var d: Dictionary = sl
		if String(d.get("id", "")) == id:
			c += int(d.get("n", 0))
	return c


# Takes up to n of `id` (last slots first, so earlier stacks stay full); returns what was taken.
func take(id: String, n: int) -> int:
	if n <= 0:
		return 0
	var left: int = n
	var i: int = SLOTS - 1
	while i >= 0 and left > 0:
		var d: Dictionary = slots[i]
		if not d.is_empty() and String(d.get("id", "")) == id:
			var got: int = mini(left, int(d.get("n", 0)))
			d["n"] = int(d.get("n", 0)) - got
			left -= got
			if int(d["n"]) <= 0:
				slots[i] = {}
		i -= 1
	return n - left


func used_slots() -> int:
	var c: int = 0
	for sl in slots:
		if not (sl as Dictionary).is_empty():
			c += 1
	return c


func to_dict() -> Dictionary:
	var out: Array = []
	for sl in slots:
		out.append((sl as Dictionary).duplicate())
	return {"slots": out}


static func from_dict(d: Dictionary) -> RefCounted:
	var ss: RefCounted = (load("res://scripts/sim/safe_stock.gd") as GDScript).new()
	var src: Array = d.get("slots", [])
	for i in mini(SLOTS, src.size()):
		var e: Dictionary = src[i]
		if not e.is_empty():
			ss.slots[i] = {"id": String(e.get("id", "")), "n": int(e.get("n", 0))}   # JSON round-trip: float -> int
	return ss


func copy() -> RefCounted:
	return from_dict(to_dict())

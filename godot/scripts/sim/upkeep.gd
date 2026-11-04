# RealWorld — sim/upkeep.gd : building repair (domain module of the live sim; stateless static funcs on `s`).
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const Inventory = preload("res://scripts/sim/inventory.gd")

# Repair (touch Repair mode / radial «Ремонт»): restore a damaged building to full hp. Price = the build
# cost scaled by the missing hp fraction × 0.5 (ceil, ≥1 of each priced resource) — cheaper than a rebuild,
# never free. Paid through the open-stock seam (cost_keys/afford/pay), deterministic, action-driven.
static func repair_cost(s, b: Dictionary) -> Dictionary:
	var def: Dictionary = s.building_def(String(b.kind))
	var max_hp := float(def.get("hp", 50.0))
	var miss: float = clampf(1.0 - float(b.hp) / maxf(max_hp, 1.0), 0.0, 1.0)
	var out := {}
	if miss <= 0.0:
		return out
	for res in def.get("cost", {}):
		out[res] = maxi(1, int(ceil(float(def.cost[res]) * miss * 0.5)))
	return out

static func repair(s, x: int, y: int) -> Dictionary:
	if not s._in(x, y) or not s.bgrid.has(y * s.n + x):
		return {"ok": false, "msg": "Тут немає будівлі."}
	var b: Dictionary = s.bgrid[y * s.n + x]
	var def: Dictionary = s.building_def(String(b.kind))
	var max_hp := float(def.get("hp", 50.0))
	if float(b.hp) >= max_hp:
		return {"ok": false, "msg": "%s ціле." % String(def.get("name", b.kind))}
	var cost := repair_cost(s, b)
	if s.use_inventory:   # spec 0009: materials come from the backpack (+ linked storages with the perk)
		var at := Vector2(s.player.px, s.player.py)
		if not Inventory.pay(s, cost, at):
			return {"ok": false, "msg": "Бракує на ремонт: " + s._cost_str(Inventory.missing(s, cost, at))}
	elif not s.afford(cost):
		return {"ok": false, "msg": "Бракує на ремонт: " + s._cost_str(cost)}
	else:
		GameData.pay_cost(s.stock, s.cost_keys(cost))
	b.hp = max_hp
	s._log("🔧 %s відремонтовано (−%s)." % [String(def.get("name", b.kind)), s._cost_str(cost)], "good")
	return {"ok": true}

